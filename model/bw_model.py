"""
bw_model.py  Core model functions — Bretton Woods speculative-attack model.

Price levels solve
    Post-T : P(t) = [σα ∫_t^∞ e^{-ρσ(s-t)} (X(s)/c)^{-σ} ds]^{-1/σ}
    Pre-T  : P(t) = [σκ^σ ∫_t^T e^{-ρσ(s-t)} RHS(s)^{-σ} ds
                     + e^{-ρσ(T-t)} P_T^{-σ}]^{-1/σ}
with the integrals evaluated as vectorised reverse cumulative trapezoids.
"""

import warnings
import numpy as np
from scipy.optimize import brentq
from scipy.interpolate import PchipInterpolator
from scipy.integrate import quad


# ---------------------------------------------------------------------------
# MONEY DEMAND
# ---------------------------------------------------------------------------

def money_demand(i, c, alpha, sigma):
    """Real money demand: m = c * (alpha / i)^{1/sigma}."""
    return c * (alpha / i) ** (1.0 / sigma)


# ---------------------------------------------------------------------------
# INTEGRAL ENGINE  (vectorised reverse-cumtrapz)
# ---------------------------------------------------------------------------

def _rev_cumtrapz(h, t):
    """Reverse cumulative trapezoid: out[k] = ∫_{t[k]}^{t[-1]} h(s) ds."""
    dt = np.diff(t)
    inc = 0.5 * (h[:-1] + h[1:]) * dt          # trapezoid increments
    out = np.zeros(len(t))
    out[:-1] = np.cumsum(inc[::-1])[::-1]       # sum from k to end
    return out


def _analytic_tail(T_end, D, theta, reserves, c, sigma, rho):
    """Analytic contribution of ∫_{T_end}^∞ e^{-ρσs} (X(s)/c)^{-σ} ds.

    θ > 0: X(s) ≈ D·e^{θs} for large s (reserves become negligible),
           so the integrand decays at rate (ρ+θ)σ.
    θ ≤ 0: X(s) → constant (reserves for θ<0, D+reserves for θ=0),
           so the integrand decays only through the discount factor ρσ.
    """
    X_end = D * np.exp(theta * T_end) + reserves
    if X_end <= 0:
        return 0.0
    if theta > 0:
        denom = (rho + theta) * sigma
        return float((X_end / c) ** (-sigma)
                     * np.exp(-rho * sigma * T_end) / denom)
    return float((X_end / c) ** (-sigma)
                 * np.exp(-rho * sigma * T_end) / (rho * sigma))


def _Q_post_on_grid(t_grid, D, theta, reserves, c, alpha, sigma, rho, H_int):
    """Q(t) = σα ∫_t^∞ e^{-ρσ(s-t)} (X(s)/c)^{-σ} ds on t_grid.

    Integration grid covers [t_grid[0], t_grid[0]+H_int]; tail is added
    analytically.  t_grid must be sorted ascending.
    """
    t0 = t_grid[0]
    t_end = t0 + H_int

    # Fine integration grid (may be denser than t_grid)
    n_int = max(500, 5 * len(t_grid))
    s = np.linspace(t0, t_end, n_int)

    X_s = D * np.exp(theta * s) + reserves
    h_s = np.where(X_s > 0,
                   np.exp(-rho * sigma * s) * (X_s / c) ** (-sigma),
                   0.0)

    # Reverse-cumtrapz on fine grid → F_fine[k] = ∫_{s[k]}^{t_end} h(s) ds
    F_fine = _rev_cumtrapz(h_s, s)

    # Add analytic tail at t_end
    tail = _analytic_tail(t_end, D, theta, reserves, c, sigma, rho)
    F_fine += tail

    # Interpolate F_fine onto t_grid
    interp_F = PchipInterpolator(s, F_fine, extrapolate=True)
    F_eval = interp_F(t_grid)
    F_eval = np.maximum(F_eval, 0.0)

    # Q(t) = σα e^{ρσt} F(t)
    Q = sigma * alpha * np.exp(rho * sigma * t_grid) * F_eval
    return Q


def _Q_post_at_T(T, D, theta, reserves, c, alpha, sigma, rho, H_int):
    """Q evaluated at the single point T (for fixed-point iteration)."""
    return float(_Q_post_on_grid(np.array([T]),
                                 D, theta, reserves, c, alpha, sigma, rho,
                                 H_int)[0])


def _Q_pre_on_grid(t_grid, D_h, D_f, theta_h, theta_f, E_0,
                   kappa, sigma, rho, P_T, country):
    """Q(t) for pre-T on t_grid, including the BC term at T.

    Q(t) = σκ^σ e^{ρσt} G(t) + e^{-ρσ(T-t)} P_T^{-σ}
    G(t) = ∫_t^T e^{-ρσs} RHS(s)^{-σ} ds  (via reverse-cumtrapz).
    """
    T = t_grid[-1]

    if country == 'foreign':
        RHS = (D_h * np.exp(theta_h * t_grid) / E_0
               + D_f * np.exp(theta_f * t_grid))
    else:
        RHS = (D_h * np.exp(theta_h * t_grid)
               + E_0 * D_f * np.exp(theta_f * t_grid))

    h = np.where(RHS > 0,
                 np.exp(-rho * sigma * t_grid) * RHS ** (-sigma),
                 0.0)

    G = _rev_cumtrapz(h, t_grid)   # G[-1] = 0 (no tail: finite upper limit T)

    kap_sigma = kappa ** sigma
    Q = (sigma * kap_sigma * np.exp(rho * sigma * t_grid) * G
         + np.exp(-rho * sigma * (T - t_grid)) * P_T ** (-sigma))
    return Q


# ---------------------------------------------------------------------------
# POST-T PRICE PATH  (t ≥ T, floating)
# ---------------------------------------------------------------------------

def solve_P_post(T, c, params, country='domestic'):
    """Post-T price path via the Sargent-Wallace integral (vectorised).

    Both countries solve a fixed-point P_T = Q(T, κ·P_T)^{-1/σ}:
      domestic: κ = −m̄  (reserves LEAVE home money supply at T)
      foreign:  κ = +m̄  (reserves ENTER foreign money supply at T)

    Returns (P_t_func, pi_t_func, P_T, pi_T).
    """
    rho   = params['rho']
    sigma = params['sigma']
    H     = params['H']

    _nf = lambda t: np.full(np.shape(t), np.nan)

    # ── country primitives ───────────────────────────────────
    if country == 'foreign':
        D     = params['Df0']
        theta = params['theta_star']
        alpha = params['alphastar']
        kappa = +params['m_hgstar_bar']   # positive: reserves add to foreign supply
    else:
        D     = params['Dh0']
        theta = params['theta']
        alpha = params['alpha']
        kappa = -params['m_hgstar_bar']   # negative: reserves leave home supply

    # ── theta = 0: closed-form constant price ───────────────
    if theta == 0.0:
        m_rho = money_demand(rho, c, alpha, sigma)
        denom = m_rho - kappa
        if denom <= 0:
            return _nf, _nf, np.nan, np.nan
        P_T_val = D / denom
        if P_T_val <= 0:
            return _nf, _nf, np.nan, np.nan
        return (lambda t: np.full(np.shape(t), P_T_val),
                lambda t: np.zeros(np.shape(t)),
                float(P_T_val), 0.0)

    # ── integration horizon ──────────────────────────────────
    decay = 1.0 / max(abs(theta) * sigma, rho * sigma)
    # Cap at 300 to prevent PchipInterpolator overflow for very small |theta|
    H_int = min(max(H, 10.0 * decay, 100.0), 300.0)

    # ── fixed-point for P_T ──────────────────────────────────
    m_rho    = money_demand(rho, c, alpha, sigma)
    P0_guess = max(1e-12, D / max(m_rho, 1e-12))

    # For domestic κ < 0: X(T) = D·exp(θT) + κ·P_T must stay positive.
    # For foreign  κ > 0: X(T) is always positive; no upper constraint.
    P_T_max = (D * np.exp(theta * T) / abs(kappa)
               if kappa < 0 else np.inf)

    def fp_res(PT):
        res_val = kappa * PT
        X_test  = D * np.exp(theta * T) + res_val
        if X_test <= 0:
            return 1e12
        Q_T = _Q_post_at_T(T, D, theta, res_val, c, alpha, sigma, rho, H_int)
        if not (np.isfinite(Q_T) and Q_T > 0):
            return 1e12
        return Q_T ** (-1.0 / sigma) - PT

    a = 0.1 * P0_guess
    b = min(10.0 * P0_guess, 0.99 * P_T_max)
    if a >= b:
        a = 1e-6
    for _ in range(14):
        fa, fb = fp_res(a), fp_res(b)
        if (np.isfinite(fa) and np.isfinite(fb)
                and np.sign(fa) != np.sign(fb)):
            break
        a /= 2.0
        b = min(b * 2.0, 0.99 * P_T_max)

    fa, fb = fp_res(a), fp_res(b)
    if not (np.isfinite(fa) and np.isfinite(fb)
            and np.sign(fa) != np.sign(fb)):
        return _nf, _nf, np.nan, np.nan

    try:
        P_T_val = brentq(fp_res, a, b, xtol=1e-10, rtol=1e-10)
    except Exception:
        return _nf, _nf, np.nan, np.nan

    reserves = kappa * P_T_val

    # ── build P(t) on grid ───────────────────────────────────
    t_grid = np.linspace(T, T + H, 200)
    Q_grid = _Q_post_on_grid(t_grid, D, theta, reserves, c, alpha, sigma, rho, H_int)

    valid = np.isfinite(Q_grid) & (Q_grid > 0)
    if valid.sum() < 2:
        return _nf, _nf, np.nan, np.nan

    P_plot  = Q_grid[valid] ** (-1.0 / sigma)
    interp  = PchipInterpolator(t_grid[valid], P_plot, extrapolate=True)

    def pi_func(t):
        t_a = np.asarray(t, dtype=float)
        P_a = interp(t_a)
        X_a = D * np.exp(theta * t_a) + reserves
        return (c * P_a * alpha ** (1.0 / sigma) / X_a) ** sigma - rho

    return interp, pi_func, float(P_T_val), float(pi_func(T))


# ---------------------------------------------------------------------------
# PRE-T PRICE PATH  (0 ≤ t ≤ T, peg)
# ---------------------------------------------------------------------------

def solve_P_pre(T, c, c_star, params, country='domestic'):
    """Pre-T price path via the Sargent-Wallace integral (vectorised).

    Returns (P_t_func, pi_t_func, P_0, P_T, pi_T).
    """
    alpha      = params['alpha']
    alpha_star = params['alphastar']
    sigma      = params['sigma']
    rho        = params['rho']
    theta      = params['theta']
    theta_star = params['theta_star']
    E_0        = params['E_0']
    eps0       = params['eps0']

    _nf = lambda t: np.full(np.shape(t), np.nan)

    # ── terminal P_T from post-T solution ───────────────────
    if country == 'domestic':
        _, _, P_post_T, _ = solve_P_post(T, c,      params, 'domestic')
    else:
        _, _, P_post_T, _ = solve_P_post(T, c_star, params, 'foreign')

    if not (np.isfinite(P_post_T) and P_post_T > 0):
        return _nf, _nf, np.nan, np.nan, np.nan

    kappa = c * alpha ** (1.0 / sigma) + c_star * alpha_star ** (1.0 / sigma)

    # ── build Q(t) on grid ───────────────────────────────────
    n_grid = 200
    t_grid = np.linspace(0.0, T, n_grid)

    Q_grid = _Q_pre_on_grid(
        t_grid,
        params['Dh0'], params['Df0'],
        theta, theta_star, E_0,
        kappa, sigma, rho, P_post_T, country,
    )

    valid = np.isfinite(Q_grid) & (Q_grid > 0)
    if valid.sum() < 2:
        return _nf, _nf, np.nan, np.nan, np.nan

    P_plot  = Q_grid[valid] ** (-1.0 / sigma)
    interp  = PchipInterpolator(t_grid[valid], P_plot, extrapolate=True)

    def pi_func(t):
        t_a = np.asarray(t, dtype=float)
        if country == 'foreign':
            RHS_t = (params['Dh0'] * np.exp(theta * t_a) / E_0
                     + params['Df0'] * np.exp(theta_star * t_a))
        else:
            RHS_t = (params['Dh0'] * np.exp(theta * t_a)
                     + E_0 * params['Df0'] * np.exp(theta_star * t_a))
        return (kappa * interp(t_a) / RHS_t) ** sigma - rho

    P_0    = float(interp(eps0))
    P_T    = float(interp(T))
    pi_T   = float(pi_func(T))
    return interp, pi_func, P_0, P_T, pi_T


# ---------------------------------------------------------------------------
# SWITCHING TIME T
# ---------------------------------------------------------------------------

def find_T_residual(T, c, c_star, params):
    """Switching condition:  P_T / P*_T − E_0 = 0."""
    try:
        _, _, P_T_dom,  _ = solve_P_post(T, c,      params, 'domestic')
        _, _, P_T_star, _ = solve_P_post(T, c_star, params, 'foreign')
        if not (np.isfinite(P_T_dom) and np.isfinite(P_T_star) and P_T_star > 0):
            return 1e12
        res = P_T_dom / P_T_star - params['E_0']
        return float(res) if np.isfinite(res) else 1e12
    except Exception:
        return 1e12


def solve_T(c, c_star, params, T_lo=0.0, T_hi=None, ngrid=50):
    """Grid search + brentq to find T*.  Returns (T_star, info_dict)."""
    if T_hi is None:
        T_hi = min(params['endtime'] - 1e-6, T_lo + params['H'])

    T_grid = np.linspace(T_lo, T_hi, ngrid)
    f_vals = np.array([find_T_residual(T, c, c_star, params) for T in T_grid])

    good = np.isfinite(f_vals) & (np.abs(f_vals) < 1e11)
    info = {'T_grid': T_grid, 'f_vals': f_vals, 'good': good,
            'n_good': int(good.sum())}

    idx = next(
        (i for i in range(len(T_grid) - 1)
         if good[i] and good[i + 1]
         and np.sign(f_vals[i]) != np.sign(f_vals[i + 1])),
        None,
    )

    if idx is None:
        info['status'] = 'no_bracket'
        info['min_good'] = float(np.min(f_vals[good])) if good.any() else np.nan
        info['max_good'] = float(np.max(f_vals[good])) if good.any() else np.nan
        return np.nan, info

    a, b = T_grid[idx], T_grid[idx + 1]
    print(f'[solve_T] brentq in [{a:.4f}, {b:.4f}]')

    try:
        T_star = brentq(find_T_residual, a, b,
                        args=(c, c_star, params),
                        xtol=1e-10, rtol=1e-10)
    except Exception as e:
        info['status'] = f'brentq_failed: {e}'
        return np.nan, info

    info.update({'status': 'solved', 'bracket': (a, b), 'T_star': T_star})
    return T_star, info


# ---------------------------------------------------------------------------
# ANALYTICAL T SOLVER  (two scalar root-finds, no path simulation)
# ---------------------------------------------------------------------------

def solve_T_analytical(params):
    """Solve for the collapse date T analytically given all model parameters.

    Implements the two post-collapse fixed-point equations and the timing
    condition from the paper:

      P̃_T^{-σ} = σα c^σ  ∫_0^∞ (D_{h,0} e^{θu}  − P̃_T  m̄)^{−σ} e^{−ρσu} du
      P̃*_T^{-σ} = σα* c*^σ ∫_0^∞ (D*_{f,0} e^{θ*u} + P̃*_T m̄)^{−σ} e^{−ρσu} du
      T = ln(E · P̃*_T / P̃_T) / (θ − θ*)

    Each fixed point is a scalar equation solved by brentq.  No price paths,
    no pre-T integration, no time grids.

    Returns T (float), or np.nan if the root-find fails.
    """
    p      = params
    c      = p['c'];      c_star = p['cstar']
    rho    = p['rho'];    sigma  = p['sigma']
    theta  = p['theta'];  tstar  = p['theta_star']
    alp    = p['alpha'];  alps   = p['alphastar']
    Dh0    = p['Dh0'];    Df0    = p['Df0']
    mbar   = p['m_hgstar_bar']
    E0     = p.get('E_0', 1.0)

    # Truncation horizon for the semi-infinite integrals. The foreign
    # integrand decays only at rate ρσ when θ* < 0 (money supply → constant),
    # so 10/(ρσ) leaves an e^{-10} ≈ 1e-4 relative tail that shows up as a
    # parity gap at T. 20/(ρσ) pushes the truncation error below 1e-8.
    U_trunc = 20.0 / (rho * sigma)

    # ── Home post-collapse fixed point ──────────────────────────────────────
    # R_h(P̃) = P̃^{-σ} - σα c^σ ∫_0^U (Dh0 e^{θu} - P̃ mbar)^{-σ} e^{-ρσu} du = 0
    # Valid range: P̃ ∈ (0, Dh0/mbar)  so the integrand at u=0 stays positive.
    def _home_fp(Ptilde):
        def _integ(u):
            x = Dh0 * np.exp(theta * u) - Ptilde * mbar
            return x ** (-sigma) * np.exp(-rho * sigma * u) if x > 0 else 0.0
        val, _ = quad(_integ, 0.0, U_trunc, limit=200)
        return Ptilde ** (-sigma) - sigma * alp * c ** sigma * val

    Pt_hi = Dh0 / mbar * (1.0 - 1e-8)   # just below the integrand-zero boundary
    Pt_lo = 1e-12

    try:
        if _home_fp(Pt_lo) * _home_fp(Pt_hi) >= 0:
            # Scan for bracket
            grid = np.geomspace(Pt_lo, Pt_hi, 200)
            R    = np.array([_home_fp(g) for g in grid])
            bracket = None
            for i in range(len(grid) - 1):
                if np.isfinite(R[i]) and np.isfinite(R[i+1]) and R[i]*R[i+1] < 0:
                    bracket = (grid[i], grid[i+1])
                    break
            if bracket is None:
                return np.nan
            Ptilde = brentq(_home_fp, bracket[0], bracket[1],
                            xtol=1e-12, rtol=1e-10, maxiter=200)
        else:
            Ptilde = brentq(_home_fp, Pt_lo, Pt_hi,
                            xtol=1e-12, rtol=1e-10, maxiter=200)
    except Exception:
        return np.nan

    # ── Foreign post-collapse fixed point ───────────────────────────────────
    # R_f(P̃*) = P̃*^{-σ} - σα* c*^σ ∫_0^U (Df0 e^{θ*u} + P̃* mbar)^{-σ} e^{-ρσu} du = 0
    # RHS is decreasing in P̃*; LHS is also decreasing.
    # As P̃*→0: LHS→∞, RHS→finite → R_f > 0.
    # As P̃*→∞: LHS→0 faster than RHS (since mbar > 0) → R_f < 0.
    def _for_fp(Pstar):
        def _integ(u):
            x = Df0 * np.exp(tstar * u) + Pstar * mbar
            return x ** (-sigma) * np.exp(-rho * sigma * u) if x > 0 else 0.0
        val, _ = quad(_integ, 0.0, U_trunc, limit=200)
        return Pstar ** (-sigma) - sigma * alps * c_star ** sigma * val

    Ps_lo = 1e-12
    Ps_hi = (alps / rho) ** (1.0 / sigma) * c_star / mbar * 10.0  # generous upper bound

    try:
        if _for_fp(Ps_lo) * _for_fp(Ps_hi) >= 0:
            grid = np.geomspace(Ps_lo, Ps_hi, 200)
            R    = np.array([_for_fp(g) for g in grid])
            bracket = None
            for i in range(len(grid) - 1):
                if np.isfinite(R[i]) and np.isfinite(R[i+1]) and R[i]*R[i+1] < 0:
                    bracket = (grid[i], grid[i+1])
                    break
            if bracket is None:
                return np.nan
            Ptilde_star = brentq(_for_fp, bracket[0], bracket[1],
                                 xtol=1e-12, rtol=1e-10, maxiter=200)
        else:
            Ptilde_star = brentq(_for_fp, Ps_lo, Ps_hi,
                                 xtol=1e-12, rtol=1e-10, maxiter=200)
    except Exception:
        return np.nan

    # ── Timing condition ────────────────────────────────────────────────────
    if theta == tstar:
        return np.nan
    T = np.log(E0 * Ptilde_star / Ptilde) / (theta - tstar)
    return float(T) if np.isfinite(T) and T > 0 else np.nan


# ---------------------------------------------------------------------------
# CLOSED-FORM CALIBRATION  (scalar root-finding, no simulation)
# ---------------------------------------------------------------------------

def calibrate_closedform(params_in, T_target, verbose=True):
    """Calibrate (D_{h,0}, D*_{f,0}, m̄, α, α*) analytically.

    Normalises P_0 = 1. All five parameters are recovered from four observed
    moments (δ_h, δ_f, μ_f, T) via a single outer scalar root-find in P̃.

    Moments used
    ------------
    δ_h  = dh0_over_c   * c    / c  = d_{h,0}/y   (from params['dh0']/c)
    δ_f  = df0_over_cstar * c* / c* = d*_{f,0}/y*  (from params['df0']/cstar)
    μ_f  = m_f0star_over_ystar       (foreign monetary base / y*)
    T    = T_target

    Note: home monetary base = d_{h,0} (home CB holds no foreign reserves),
    so d_{h,0}/y is not a separate moment — it equals δ_h by construction.

    Algorithm follows the paper's Calibration Algorithm subsection.
    Returns (params_out, info_dict).
    """
    p      = dict(params_in)
    c      = p['c'];      c_star = p['cstar']
    rho    = p['rho'];    sigma  = p['sigma']
    theta  = p['theta'];  tstar  = p['theta_star']
    T      = float(T_target)

    delta_h = p['dh0']   / c       # d_{h,0} / y
    delta_f = p['df0']   / c_star  # d*_{f,0} / y*
    mu_f    = p.get('m_f0star_over_ystar')
    if mu_f is None:
        raise ValueError('params must contain m_f0star_over_ystar')

    # ------------------------------------------------------------------
    # Step 1: nominal credit stocks  (P_0 = 1 normalisation)
    # ------------------------------------------------------------------
    Dh0 = delta_h * c        # = d_{h,0}  (real = nominal at t=0)
    Df0 = delta_f * c_star   # = d*_{f,0}

    # ------------------------------------------------------------------
    # Step 2: initial reserve stock and home money share w
    # ------------------------------------------------------------------
    mg0_data = (mu_f - delta_f) * c_star   # m^{g*}_{h,0} = m*_{f,0} - d*_{f,0}
    mh0_data = delta_h * c - mg0_data      # private home money balances
    mf0_data = delta_f * c_star + mg0_data # = mu_f * c_star  (check)

    world_money = mh0_data + mf0_data      # = delta_h*c + delta_f*c_star
    w = mh0_data / world_money             # home share of world private money

    if verbose:
        print(f'  [closedform] δ_h={delta_h:.5g}  δ_f={delta_f:.5g}  μ_f={mu_f:.5g}')
        print(f'               m^g*_h0={mg0_data:.5g}  m_h0_priv={mh0_data:.5g}  w={w:.5g}')

    # ------------------------------------------------------------------
    # Step 3: precomputed finite integral I_1
    # ------------------------------------------------------------------
    def _integrand_I1(s):
        return ((Dh0 * np.exp(theta * s) + Df0 * np.exp(tstar * s)) ** (-sigma)
                * np.exp(-rho * sigma * s))

    I1, _ = quad(_integrand_I1, 0.0, T, limit=200)

    # ------------------------------------------------------------------
    # Step 4 helpers: all parameters as functions of P̃ = e^{-θT} P_T
    # ------------------------------------------------------------------
    # Truncation horizon for the semi-infinite integrals (see solve_T_analytical:
    # 10/(ρσ) leaves an e^{-10} ≈ 1e-4 tail in the foreign integral when θ* < 0).
    U_trunc = 20.0 / (rho * sigma)

    def _kappa(Ptilde):
        num = 1.0 - np.exp(-(rho + theta) * sigma * T) * Ptilde ** (-sigma)
        denom = sigma * I1
        val = num / denom
        if val <= 0:
            return np.nan
        return val ** (1.0 / sigma)

    def _alphas(Ptilde):
        kap = _kappa(Ptilde)
        if not np.isfinite(kap):
            return np.nan, np.nan
        alp  = (kap * w       / c)      ** sigma
        alps = (kap * (1 - w) / c_star) ** sigma
        return alp, alps

    def _Ptildestar(Ptilde):
        return Ptilde * np.exp((theta - tstar) * T)

    def _mbar(Ptilde):
        """Solve for m̄ from the foreign post-collapse fixed-point."""
        _, alps = _alphas(Ptilde)
        if not np.isfinite(alps):
            return np.nan
        Pts = _Ptildestar(Ptilde)

        if tstar == 0.0:
            # Closed-form solution
            kap = _kappa(Ptilde)
            return kap * (1 - w) / rho ** (1.0 / sigma) - Df0 * np.exp(-theta * T) / Ptilde
        else:
            # Scalar root-find: LHS - RHS = 0
            # LHS = Pts^{-σ} / (σ α* c*^σ)
            lhs = Pts ** (-sigma) / (sigma * alps * c_star ** sigma)

            def _foreign_resid(mb):
                def _integ(u):
                    x = Df0 * np.exp(tstar * u) + Pts * mb
                    if x <= 0:
                        return 0.0
                    return x ** (-sigma) * np.exp(-rho * sigma * u)
                val, _ = quad(_integ, 0.0, U_trunc, limit=200)
                return val - lhs

            # bracket: mb must be > 0 and keep integrand positive
            mb_lo = 1e-10
            # upper bound: money_demand at rho / c_star (maximum feasible mbar)
            mb_hi = alps ** (1.0 / sigma) * c_star / rho ** (1.0 / sigma)
            try:
                mb = brentq(_foreign_resid, mb_lo, mb_hi, xtol=1e-12, rtol=1e-10)
            except ValueError:
                return np.nan
            return mb

    # ------------------------------------------------------------------
    # Step 5: outer scalar root-find in P̃
    # ------------------------------------------------------------------
    def _residual_R(Ptilde):
        alp, _ = _alphas(Ptilde)
        if not np.isfinite(alp):
            return np.nan
        mb = _mbar(Ptilde)
        if not np.isfinite(mb) or mb <= 0:
            return np.nan

        # Home post-collapse fixed-point
        lhs = Ptilde ** (-sigma)

        def _home_integ(u):
            x = Dh0 * np.exp(theta * u) - Ptilde * mb
            if x <= 0:
                return 0.0
            return x ** (-sigma) * np.exp(-rho * sigma * u)

        integral, _ = quad(_home_integ, 0.0, U_trunc, limit=200)
        rhs = sigma * alp * c ** sigma * integral
        return lhs - rhs

    # Bounds from feasibility constraints (see paper)
    # Lower bound: P̃ > e^{-(ρ+θ)T}  so kappa numerator > 0
    Pt_lo = np.exp(-(rho + theta) * T) * 1.001
    # Upper bound: search geometrically upward until we find a sign change or
    # infeasibility.  R(Pt_lo) > 0 (LHS large, RHS small); R decreases and
    # eventually goes negative or NaN as the home integrand turns negative.
    # Dh0 ~ 0.04 while the root is typically near P̃ ~ 1, so don't anchor to Dh0.
    Pt_hi = max(Pt_lo * 1000, 100.0)

    # Geometric scan: more resolution near Pt_lo where the root lives
    n_scan = 400
    Pt_grid = np.geomspace(Pt_lo, Pt_hi, n_scan)
    R_grid  = np.array([_residual_R(pt) for pt in Pt_grid])
    finite  = np.isfinite(R_grid)

    # Accept a sign change between two finite evaluations, or treat a
    # finite→NaN transition as an upper bracket (infeasibility = R < 0).
    bracket = None
    for i in range(len(Pt_grid) - 1):
        if finite[i] and finite[i + 1] and R_grid[i] * R_grid[i + 1] < 0:
            bracket = (Pt_grid[i], Pt_grid[i + 1])
            break
        if finite[i] and not finite[i + 1] and R_grid[i] > 0:
            # root lies between last finite point and the infeasibility boundary;
            # find the boundary by linear search
            for j in range(i + 1, min(i + 20, len(Pt_grid))):
                if not np.isfinite(_residual_R(Pt_grid[j - 1])):
                    break
                if np.isfinite(_residual_R(Pt_grid[j])) and _residual_R(Pt_grid[j]) < 0:
                    bracket = (Pt_grid[j - 1], Pt_grid[j])
                    break
            break

    if bracket is None:
        # Diagnostic: print a few values to help debug
        idx_fin = np.where(finite)[0]
        if len(idx_fin):
            lo_i, hi_i = idx_fin[0], idx_fin[-1]
            print(f'  [debug] P̃ scan: lo={Pt_grid[lo_i]:.4g} R={R_grid[lo_i]:.4g}'
                  f'  hi={Pt_grid[hi_i]:.4g} R={R_grid[hi_i]:.4g}')
        raise RuntimeError('calibrate_closedform: no sign change found in P̃ scan; '
                           'check feasibility of moments.')

    Ptilde_star = brentq(_residual_R, bracket[0], bracket[1],
                         xtol=1e-12, rtol=1e-10, maxiter=200)

    # ------------------------------------------------------------------
    # Step 6: recover all five parameters
    # ------------------------------------------------------------------
    kappa_star = _kappa(Ptilde_star)
    alp_star, alps_star = _alphas(Ptilde_star)
    mbar_star  = _mbar(Ptilde_star)
    P_T        = Ptilde_star * np.exp(theta * T)

    params_out = {
        **p,
        'Dh0':         Dh0,
        'Df0':         Df0,
        'alpha':       alp_star,
        'alphastar':   alps_star,
        'm_hgstar_bar': mbar_star,
    }

    # Self-contained verification: check residuals without any path solver
    R_star = _residual_R(Ptilde_star)
    # Foreign fixed-point residual (re-evaluate directly)
    _, alps_v = _alphas(Ptilde_star)
    Pts_v = _Ptildestar(Ptilde_star)
    def _for_resid_check(u):
        x = Df0 * np.exp(tstar * u) + Pts_v * mbar_star
        return x ** (-sigma) * np.exp(-rho * sigma * u) if x > 0 else 0.0
    for_integral, _ = quad(_for_resid_check, 0.0, U_trunc, limit=200)
    for_lhs = Pts_v ** (-sigma)
    for_rhs = sigma * alps_v * c_star ** sigma * for_integral
    R_for   = for_lhs - for_rhs

    # P_0 sanity check: σ κ^σ I1 + e^{-(ρ+θ)σT} P̃^{-σ} should = 1
    P0_check = (sigma * kappa_star**sigma * I1
                + np.exp(-(rho + theta) * sigma * T) * Ptilde_star**(-sigma))

    if verbose:
        print(f'  [closedform] P̃*={Ptilde_star:.6g}  P_T={P_T:.6g}')
        print(f'               κ={kappa_star:.6g}  α={alp_star:.6g}  α*={alps_star:.6g}')
        print(f'               m̄={mbar_star:.6g}')
        print(f'  [closedform] residuals (self-contained):')
        print(f'               R_home={R_star:.2e}  R_foreign={R_for:.2e}'
              f'  (both should be ≈0)')
        print(f'  [moments]    {"moment":<10} {"target":>12} {"model":>12} {"error":>10}')
        print(f'  [moments]    {"δ_h":<10} {delta_h:>12.6g} {Dh0/c:>12.6g} {Dh0/c - delta_h:>10.2e}')
        print(f'  [moments]    {"δ_f":<10} {delta_f:>12.6g} {Df0/c_star:>12.6g} {Df0/c_star - delta_f:>10.2e}')
        print(f'  [moments]    {"μ_f":<10} {mu_f:>12.6g} {mf0_data/c_star:>12.6g} {mf0_data/c_star - mu_f:>10.2e}')
        print(f'  [moments]    {"T":<10} {T:>12.6g} {"(input)":>12}')
        print(f'  [moments]    {"P_0":<10} {"1.000000":>12} {P0_check:>12.6g} {P0_check - 1.0:>10.2e}')

    return params_out, {
        'method':      'closedform',
        'Ptilde_star': Ptilde_star,
        'P_T':         P_T,
        'kappa':       kappa_star,
        'w':           w,
        'I1':          I1,
        'mbar':        mbar_star,
    }


# ---------------------------------------------------------------------------
# COMPUTE ALL MODEL PATHS
# ---------------------------------------------------------------------------

def compute_model_paths(params_cal, tvals_size=500, T_known=None):
    """Compute all model paths. Returns (results_dict, T)."""
    print('\n=== Computing model solution paths ===')

    c         = params_cal['c']
    c_star    = params_cal['cstar']
    rho       = params_cal['rho']
    sigma     = params_cal['sigma']
    alpha     = params_cal['alpha']
    alphastar = params_cal['alphastar']

    if T_known is not None:
        T = float(T_known)
        print(f'Switching time T = {T:.10g}  (supplied directly, no solve_T)')
    else:
        # Three-pass search:
        #   1. Ultra-fine [0.001, 3] to catch very small T (spacing 0.006)
        #   2. Fine [0, 150] to catch moderate T (spacing 0.2)
        #   3. Wide [0, endtime] for large T
        T, info = solve_T(c, c_star, params_cal, 0.001, 3.0, 500)
        if not np.isfinite(T):
            T, info = solve_T(c, c_star, params_cal, 0.0, 150.0, 750)
        if not np.isfinite(T):
            T, info = solve_T(c, c_star, params_cal, 0.0,
                              params_cal['endtime'] - 1e-6, 500)
        print(f'Switching time T = {T:.10g}')
        print(f'solve_T status  : {info["status"]}')

    tvals_pre  = np.linspace(0.0, T - 1e-10, tvals_size)
    tvals_post = np.linspace(T,   T + params_cal['H'], tvals_size)

    print('Solving post-switch paths...')
    P_dom_post_f, pi_dom_post_f, P_T_dom, _ = \
        solve_P_post(T, c,      params_cal, 'domestic')
    P_for_post_f, pi_for_post_f, _,       _ = \
        solve_P_post(T, c_star, params_cal, 'foreign')

    print('Solving pre-switch paths...')
    P_dom_pre_f, pi_dom_pre_f, *_ = \
        solve_P_pre(T, c, c_star, params_cal, 'domestic')
    P_for_pre_f, pi_for_pre_f, *_ = \
        solve_P_pre(T, c, c_star, params_cal, 'foreign')

    P_dom_pre   = P_dom_pre_f(tvals_pre)
    P_for_pre   = P_for_pre_f(tvals_pre)
    P_dom_post  = P_dom_post_f(tvals_post)
    P_for_post  = P_for_post_f(tvals_post)
    pi_dom_pre  = pi_dom_pre_f(tvals_pre)
    pi_for_pre  = pi_for_pre_f(tvals_pre)
    pi_dom_post = pi_dom_post_f(tvals_post)
    pi_for_post = pi_for_post_f(tvals_post)

    print('Computing money demand...')
    md_h = lambda pi: money_demand(rho + pi, c,      alpha,     sigma)
    md_f = lambda pi: money_demand(rho + pi, c_star, alphastar, sigma)

    m_over_y_dom_pre   = md_h(pi_dom_pre)  / params_cal['c']
    m_over_y_for_pre   = md_f(pi_for_pre)  / params_cal['cstar']
    m_over_y_dom_post  = md_h(pi_dom_post) / params_cal['c']
    m_over_y_for_post  = md_f(pi_for_post) / params_cal['cstar']

    print('Computing reserves...')
    m_h_t = md_h(pi_dom_pre)
    d_h_t = (params_cal['Dh0'] * np.exp(params_cal['theta'] * tvals_pre)
             / P_dom_pre)

    # Balance sheet identity: m_h + R = d_h  →  R = d_h - m_h
    reserves_real_pre = d_h_t - m_h_t
    reserves_nom_pre  = reserves_real_pre * P_dom_pre

    nom_frozen         = params_cal['m_hgstar_bar'] * P_dom_post[0]
    reserves_nom_post  = nom_frozen * np.ones(len(tvals_post))
    reserves_real_post = nom_frozen / P_dom_post

    results = {
        'tvals_pre': tvals_pre,   'tvals_post': tvals_post,   'T': T,
        'P_dom_pre': P_dom_pre,   'P_for_pre': P_for_pre,
        'P_dom_post': P_dom_post, 'P_for_post': P_for_post,
        'p_dom_pre': np.log(P_dom_pre),   'p_for_pre': np.log(P_for_pre),
        'p_dom_post': np.log(P_dom_post), 'p_for_post': np.log(P_for_post),
        'pi_dom_pre': pi_dom_pre,   'pi_for_pre': pi_for_pre,
        'pi_dom_post': pi_dom_post, 'pi_for_post': pi_for_post,
        'm_over_y_dom_pre': m_over_y_dom_pre,  'm_over_y_for_pre': m_over_y_for_pre,
        'm_over_y_dom_post': m_over_y_dom_post,'m_over_y_for_post': m_over_y_for_post,
        'reserves_nom_pre': reserves_nom_pre,   'reserves_real_pre': reserves_real_pre,
        'reserves_nom_post': reserves_nom_post, 'reserves_real_post': reserves_real_post,
    }

    print('Model paths computed successfully\n')
    return results, T


# ---------------------------------------------------------------------------
# CONTINUITY CHECK
# ---------------------------------------------------------------------------

def check_continuity_at_T(results, params_cal, tol_cont=1e-4):
    def relgap(a, b):
        return abs(a - b) / max(1.0, abs(a), abs(b))

    report = {'passed': True, 'warnings': []}

    # ── Continuity of each price path at T ──────────────────────────────────
    for name, a, b in [
        ('Domestic P', results['P_dom_pre'][-1], results['P_dom_post'][0]),
        ('Foreign P*', results['P_for_pre'][-1], results['P_for_post'][0]),
    ]:
        g = relgap(a, b)
        report[f'gap_{name}'] = g
        if g > tol_cont:
            msg = f'{name} gap at T = {g:.3g} (tol={tol_cont})'
            warnings.warn(msg);  report['passed'] = False
            report['warnings'].append(msg)

    # ── Parity condition at T: P_T / P_T* = E = 1 ──────────────────────────
    Pdom_Tm = results['P_dom_pre'][-1];  Pfor_Tm = results['P_for_pre'][-1]
    Pdom_Tp = results['P_dom_post'][0];  Pfor_Tp = results['P_for_post'][0]
    E_m = Pdom_Tm / Pfor_Tm;  E_p = Pdom_Tp / Pfor_Tp
    E0  = params_cal.get('E_0', 1.0)
    g_parity = abs(E_m - E0) / max(1.0, abs(E0))
    g_E      = relgap(E_m, E_p)
    report.update({'gap_E': g_E, 'gap_parity': g_parity,
                   'E_implied_Tm': E_m, 'E_implied_Tp': E_p})
    if g_parity > tol_cont:
        msg = f'Parity P_T/P_T* = {E_m:.6g} ≠ E={E0} (gap={g_parity:.3g})'
        warnings.warn(msg);  report['passed'] = False
        report['warnings'].append(msg)
    if g_E > tol_cont:
        report['warnings'].append(f'Exchange rate gap across T = {g_E:.3g}')

    # ── Moment checks from numerical paths ──────────────────────────────────
    P0_model  = results['P_dom_pre'][0]
    mhy_model = results['m_over_y_dom_pre'][0]
    mfy_model = results['m_over_y_for_pre'][0]

    c      = params_cal.get('c',      1.0)
    c_star = params_cal.get('cstar',  1.0)
    delta_h = params_cal.get('dh0', 0.0) / c
    delta_f = params_cal.get('df0', 0.0) / c_star
    mu_f    = params_cal.get('m_f0star_over_ystar', np.nan)

    # Private home money target: D_{h,0}/y minus foreign CB dollar holdings
    # m^{g*}_{h,0} = (μ_f − δ_f)·y*  →  m_{h,0,private}/y = δ_h − (μ_f−δ_f)·y*/y
    if np.isfinite(mu_f):
        mg0_over_y = (mu_f - delta_f) * c_star / c
        mhy_target = delta_h - mg0_over_y
    else:
        mhy_target = delta_h

    g_P0  = abs(P0_model - 1.0)
    g_mhy = abs(mhy_model - mhy_target) / max(abs(mhy_target), 1e-8)
    g_mfy = abs(mfy_model - mu_f)       / max(abs(mu_f),       1e-8) if np.isfinite(mu_f) else np.nan

    report.update({'P0_model': P0_model, 'mhy_model': mhy_model, 'mfy_model': mfy_model,
                   'gap_P0': g_P0, 'gap_mhy': g_mhy, 'gap_mfy': g_mfy})

    status = 'PASSED' if report['passed'] else '*** FAILED — investigate before using output ***'
    print(f'\nContinuity at T={results["T"]:.6f}: {status}')
    print(f'  Domestic P gap at T              = {report.get("gap_Domestic P", 0):.2e}')
    print(f'  Foreign P* gap at T              = {report.get("gap_Foreign P*", 0):.2e}')
    print(f'  Parity P_T/P_T* (vs E={E0})      = {E_m:.6g}  (gap={g_parity:.2e})')
    print(f'  Exchange rate gap across T       = {g_E:.2e}')
    print(f'  P_0 (model vs 1)                 = {P0_model:.6g}  (gap={g_P0:.2e})')
    print(f'  m_h0,priv/y (model vs target)    = {mhy_model:.6g} vs {mhy_target:.6g}  (gap={g_mhy:.2e})')
    if np.isfinite(mu_f):
        print(f'  m*_f0/y*   (model vs μ_f)        = {mfy_model:.6g} vs {mu_f:.6g}  (gap={g_mfy:.2e})')
    return report


# ---------------------------------------------------------------------------
# PARAMETERS LOADER
# ---------------------------------------------------------------------------

def load_params(csv_path, country='DEU'):
    """Load calibration CSV and return parameter dict."""
    import pandas as pd
    df  = pd.read_csv(csv_path, index_col='name')
    col = f'value_{country}'
    if col not in df.columns:
        raise ValueError(f'Country {country} not in CSV.')
    cal = df[col].astype(float).to_dict()

    c     = cal['c']
    cstar = cal['c_star']
    dh0   = cal['dh0_over_c']    * c
    df0   = cal['df0_over_cstar'] * cstar

    p = {
        'rho':          cal['rho'],
        'sigma':        cal['sigma'],
        'y':            cal['y'],
        'ystar':        cal['y_star'],
        'c':            c,
        'cstar':        cstar,
        'dh0':          dh0,
        'df0':          df0,
        'E_0':          1.0,
        'theta':        cal['theta'],
        'theta_star':   cal['theta_star'],
        'm_hgstar_bar':          cal['mbar_h_gstar_attack73'],
        'm_hgstar_bar_attack71': cal.get('mbar_h_gstar_attack71'),
        'm_hgstar_bar_prev':     cal.get('mbar_h_gstar_prev'),
        'm_hgstar_bar_trend':          cal.get('mbar_h_gstar_attack73_trend'),
        'm_hgstar_bar_attack71_trend': cal.get('mbar_h_gstar_attack71_trend'),
        'm_hgstar_bar_prev_trend':     cal.get('mbar_h_gstar_prev_trend'),
        'fxres_attack73':        cal.get('fxres_attack73'),
        'fxres_attack71':        cal.get('fxres_attack71'),
        'fxres_prev_date':       cal.get('fxres_prev_date'),
        'm_h0_over_y':       cal.get('m_h0_over_y'),
        'm_f0star_over_ystar':     cal.get('m_f0star_over_ystar'),
        'm_f0star_over_ystar_raw': cal.get('m_f0star_over_ystar_raw'),
        'g_f0':                    cal.get('g_f0'),
        # Forward FX commitments at the 1971 attack (Coombs 1971), same units
        # as the mbar_* rows (trend GDP); missing for countries without a
        # forwards figure. Computed in 07_calibration_multi_country.do.
        'fwd_h_gstar_attack71_trend':   cal.get('fwd_h_gstar_attack71_trend'),
        'H':            50,
        'endtime':      1000,
        'tol':          1e-15,
        'eps0':         1e-10,
    }
    return p
