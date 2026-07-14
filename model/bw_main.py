"""
bw_main.py  Main pipeline — Bretton Woods speculative-attack model (v2).

Calibration
-----------
Closed-form calibration (run_calibration_closedform → bw_model.calibrate_closedform)
recovers (Dh0, Df0, m̄, α, α*) analytically from four moments — δ_h = d_{h,0}/y,
δ_f = d*_{f,0}/y*, μ_f = (m*_{f,0}−g_{f,0})/y*, and the attack date T — via a single
scalar root-find in P̃ (the rescaled collapse price), following the paper's
Calibration Algorithm appendix.  P_0 = 1 normalisation; c = y by construction.
T_target is inferred from date columns in calibration_values.csv.
T = 0 corresponds to December 1969 (Stata monthly = 119).
E_0 is normalised to 1 (closed-form convention, not imported from CSV).

Attack dates
------------
--attack attack71 : country-specific 1971 float (DEU=May, JPN=Aug)
--attack attack73 : March 1973 G-10 float (DEU, JPN)
Both can be passed together: --attack attack71 attack73

Usage
-----
    python bw_main.py --step baseline     --country DEU --attack attack73
    python bw_main.py --step compstatics  --country DEU --attack attack73
    python bw_main.py --step multicountry --country DEU JPN --attack attack73
    python bw_main.py --step table        --country DEU JPN --attack attack73
    python bw_main.py --step all          --country DEU JPN --attack attack71 attack73
    python bw_main.py --step sync                        # copy figures to Overleaf

Flags
-----
    --country  DEU [JPN ...]   countries to run (default: DEU)
    --attack   attack71 [attack73]     attack date(s) (default: attack71)
    --figdir   /path/...               output directory (default: figures/)
    --force                            bypass calibration cache
    --no-show                          suppress plt.show()
    --overleaf                         sync figures to Overleaf after running
"""

import argparse
import hashlib
import pickle
import sys
import warnings
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.lines import Line2D

# ── locate project root ─────────────────────────────────────
HERE     = Path(__file__).resolve().parent
ROOT     = HERE
CSV_PATH = ROOT / 'calibration_values.csv'

sys.path.insert(0, str(HERE))
from bw_model import (
    load_params, calibrate_closedform, solve_T_analytical,
    compute_model_paths, check_continuity_at_T,
)

DEFAULT_FIG_DIR = ROOT / 'figures'
OVERLEAF_DIR    = Path('/Users/patriciogoldstein/Library/CloudStorage/Dropbox/Apps/Overleaf/Bretton Woods/Figures')


BLUE = '#1f77b4'
RED  = '#d62728'

COUNTRY_COLORS = {
    'USA': (0.000, 0.000, 0.000),
    'DEU': (1.000, 0.498, 0.055),
    'JPN': (0.580, 0.404, 0.741),
    'GBR': (0.420, 0.510, 0.059),
}


# ════════════════════════════════════════════════════════════
#  CALIBRATION  (with disk cache)
# ════════════════════════════════════════════════════════════

def _param_hash(p: dict) -> str:
    # Must include every input the closed-form calibration targets or conditions
    # on — in particular μ_f (m_f0star_over_ystar) and g_f0, which determine
    # (α, α*, m̄).  Omitting them lets a CSV update silently reuse stale caches.
    keys = ['rho', 'sigma', 'theta', 'theta_star', 'y', 'ystar',
            'c', 'cstar', 'dh0', 'df0', 'm_hgstar_bar',
            'm_f0star_over_ystar', 'g_f0', 'E_0']
    def _fmt(v):
        return f'{v:.10f}' if isinstance(v, (int, float)) and np.isfinite(v) else 'NA'
    s = '_'.join(_fmt(p.get(k)) for k in keys)
    return hashlib.md5(s.encode()).hexdigest()[:12]


CACHE_FILE_CF = HERE / '.calib_cache_closedform_v1.pkl'


def run_calibration_closedform(country: str = 'DEU',
                                force: bool = False,
                                verbose: bool = True,
                                T_target: float = None,
                                attack: str = 'attack71') -> tuple:
    """Calibrate using the closed-form scalar root-finding algorithm.

    Uses four moments: δ_h, δ_f, μ_f, T.
    No warm-start or simulation required — all parameters recovered analytically
    up to one scalar root-find in P̃.
    """
    params         = load_params(CSV_PATH, country)
    fxres_attack71 = params.get('fxres_attack71')
    fxres_attack73 = params.get('fxres_attack73')

    if attack == 'attack71':
        if T_target is None:
            T_target = (int(round(fxres_attack71)) - 119) / 12
        mbar_data = params.get('m_hgstar_bar_attack71') or params['m_hgstar_bar']
        params['fxres_attack_date'] = int(round(fxres_attack71))
    else:
        if T_target is None:
            T_target = (int(round(fxres_attack73)) - 119) / 12
        mbar_data = params['m_hgstar_bar']
        params['fxres_attack_date'] = int(round(fxres_attack73))

    params['mbar_data']      = mbar_data
    params['mbar_data_prev'] = params.get('m_hgstar_bar_prev')
    params['attack']         = attack

    if params.get('m_f0star_over_ystar') is None:
        raise ValueError(
            f'CSV is missing m_f0star_over_ystar for {country}. '
            'Re-run calibration_multi_country.do first.'
        )

    T_tag     = f'{T_target:.6f}'
    cache_key = f'cf_{country}_Ttgt{T_tag}_{attack}_{_param_hash(params)}'

    cache = {}
    if CACHE_FILE_CF.exists():
        try:
            with open(CACHE_FILE_CF, 'rb') as f:
                cache = pickle.load(f)
        except Exception:
            cache = {}

    if not force and cache_key in cache:
        Dh0_c, Df0_c, mbar_c, alpha_c, alps_c = cache[cache_key]
        if verbose:
            print(f'[cache-cf] {country}: Dh0={Dh0_c:.8g}, Df0={Df0_c:.8g}, '
                  f'm̄={mbar_c:.8g}, alpha={alpha_c:.8g}, alpha*={alps_c:.8g}')
        params['Dh0']          = Dh0_c
        params['Df0']          = Df0_c
        params['m_hgstar_bar'] = mbar_c
        params['alpha']        = alpha_c
        params['alphastar']    = alps_c
        params['T_target']     = T_target
        return params, {'method': 'cached_closedform'}

    if verbose:
        print(f'\n=== Calibrating {country} [closed-form]  '
              f'(T_target={T_target:.4f}, attack={attack}) ===')

    params_cal, info = calibrate_closedform(params, T_target=T_target, verbose=verbose)
    params_cal['mbar_data']      = mbar_data
    params_cal['mbar_data_prev'] = params.get('m_hgstar_bar_prev')
    params_cal['T_target']       = T_target

    cache[cache_key] = (params_cal['Dh0'], params_cal['Df0'],
                        params_cal['m_hgstar_bar'],
                        params_cal['alpha'], params_cal['alphastar'])
    try:
        with open(CACHE_FILE_CF, 'wb') as f:
            pickle.dump(cache, f)
    except Exception:
        pass

    if verbose:
        print(f'  Dh0    = {params_cal["Dh0"]:.10g}')
        print(f'  Df0    = {params_cal["Df0"]:.10g}')
        print(f'  m̄     = {params_cal["m_hgstar_bar"]:.10g}')
        print(f'  alpha  = {params_cal["alpha"]:.10g}')
        print(f'  alpha* = {params_cal["alphastar"]:.10g}')

    return params_cal, info




# ════════════════════════════════════════════════════════════
#  PLOTTING HELPERS
# ════════════════════════════════════════════════════════════

def _join(t_pre, y_pre, t_post, y_post):
    t = np.concatenate([t_pre, [np.nan], t_post])
    y = np.concatenate([y_pre, [np.nan], y_post])
    return t, y


def _set_year_ticks(ax, x_max, base_year=1970):
    """Monthly minor ticks; major ticks + labels every 6 months as 'Jan/Jul YYYY'.

    T=0 is Jan 1, 1970, so t=1/12 is end of Jan 1970, t=6/12 is Jul 1970, etc.
    """
    from matplotlib.ticker import FixedLocator, FixedFormatter

    n_months = int(np.floor(x_max * 12)) + 1
    all_ticks = np.arange(0, n_months + 1) / 12
    all_ticks = all_ticks[all_ticks <= x_max + 1e-6]

    major_ticks = all_ticks[np.round(all_ticks * 12).astype(int) % 6 == 0]
    minor_ticks = all_ticks[np.round(all_ticks * 12).astype(int) % 6 != 0]

    def _label(t):
        m = int(round(t * 12))
        year = base_year + m // 12
        return f"{'Jan' if m % 12 == 0 else 'Jul'} {year}"

    ax.xaxis.set_major_locator(FixedLocator(major_ticks))
    ax.xaxis.set_major_formatter(FixedFormatter([_label(t) for t in major_ticks]))
    ax.xaxis.set_minor_locator(FixedLocator(minor_ticks))
    ax.tick_params(axis='x', which='major', length=5, labelsize=7)
    ax.tick_params(axis='x', which='minor', length=2)
    for lbl in ax.get_xticklabels():
        lbl.set_rotation(45)
        lbl.set_ha('right')


# Internal figure name -> paper/slides filename (numbering follows the paper).
# Anything not listed here is not used in the paper or slides and is NOT saved.
PAPER_FIGS = {
    # Fig 9 — model baseline, DEU attack73 (4 panels)
    'fig_panel_price_DEU_attack73.pdf':      'fig09a_model_price.pdf',
    'fig_panel_inflation_DEU_attack73.pdf':  'fig09b_model_inflation.pdf',
    'fig_panel_realmoney_DEU_attack73.pdf':  'fig09c_model_realmoney.pdf',
    'fig_panel_reserves_DEU_attack73.pdf':   'fig09d_model_reserves.pdf',
    # Fig 10 — comparative statics outcomes, DEU attack73 (4 panels)
    'fig_outcomes_theta_DEU_attack73.pdf':   'fig10a_model_outcomes_theta.pdf',
    'fig_outcomes_mbar_DEU_attack73.pdf':    'fig10b_model_outcomes_mbar.pdf',
    'fig_outcomes_ratio_DEU_attack73.pdf':   'fig10c_model_outcomes_ratio.pdf',
    'fig_outcomes_size_DEU_attack73.pdf':    'fig10d_model_outcomes_size.pdf',
    # Fig 11 — multicountry model-vs-data segments (trend GDP)
    'fig_multicountry_segments_trend.pdf':   'fig11_model_multicountry.pdf',
    # Appendix Fig A10 — model baseline, JPN attack73 (4 panels)
    'fig_panel_price_JPN_attack73.pdf':      'figA10a_model_price_JPN.pdf',
    'fig_panel_inflation_JPN_attack73.pdf':  'figA10b_model_inflation_JPN.pdf',
    'fig_panel_realmoney_JPN_attack73.pdf':  'figA10c_model_realmoney_JPN.pdf',
    'fig_panel_reserves_JPN_attack73.pdf':   'figA10d_model_reserves_JPN.pdf',
    # Appendix Fig A11 — comparative statics paths, DEU attack73 (4 panels)
    'fig_compstatics_theta_DEU_attack73.pdf':'figA11a_model_compstatics_theta.pdf',
    'fig_compstatics_mbar_DEU_attack73.pdf': 'figA11b_model_compstatics_mbar.pdf',
    'fig_compstatics_ratio_DEU_attack73.pdf':'figA11c_model_compstatics_ratio.pdf',
    'fig_compstatics_size_DEU_attack73.pdf': 'figA11d_model_compstatics_size.pdf',
}


def _savefig(fig: plt.Figure, path: Path, verbose: bool = True):
    paper_name = PAPER_FIGS.get(path.name)
    if paper_name is None:
        if verbose:
            print(f'  Skipped (not in paper/slides): {path.name}')
        return
    path = path.with_name(paper_name)
    fig.savefig(path, dpi=150, bbox_inches='tight')
    if verbose:
        print(f'  Saved: {path}')


def sync_to_overleaf(figdir: Path = DEFAULT_FIG_DIR,
                     overleaf_dir: Path = OVERLEAF_DIR,
                     verbose: bool = True):
    import shutil
    if not overleaf_dir.exists():
        print(f'  [overleaf] Directory not found: {overleaf_dir}')
        return
    files = sorted(figdir.glob('fig*.pdf')) + sorted(figdir.glob('tab*.tex'))
    if not files:
        print(f'  [overleaf] No fig*.pdf / tab*.tex found in {figdir}')
        return
    print(f'\n  Syncing {len(files)} file(s) to {overleaf_dir}')
    for src in files:
        import shutil as _sh
        _sh.copy2(src, overleaf_dir / src.name)
        if verbose:
            print(f'  ✓  {src.name}')
    print('  Done.')


# ════════════════════════════════════════════════════════════
#  STEP 1 — BASELINE 4-PANEL FIGURE
# ════════════════════════════════════════════════════════════

def step_baseline(country: str = 'DEU',
                  figdir: Path = DEFAULT_FIG_DIR,
                  force: bool = False,
                  show: bool = True,
                  attack: str = 'attack71') -> dict:
    print('\n' + '=' * 52)
    print(f'  STEP: baseline  (country={country}, attack={attack})')
    print('=' * 52)
    figdir.mkdir(parents=True, exist_ok=True)

    print('\n[1/4] Calibration')
    params_cal, _ = run_calibration_closedform(country, force=force, attack=attack,
                                               verbose=True)

    print('\n[2/4] Computing model paths')
    results, T = compute_model_paths(params_cal, tvals_size=500,
                                     T_known=params_cal.get('T_target'))
    print(f'  T = {T:.6f}')

    print('\n[3/4] Continuity check')
    check_continuity_at_T(results, params_cal)

    print('\n[4/4] Panel figures')
    x_max = 2.0 if attack == 'attack71' else 4.0
    sep_figs = _plot_4panel_singles(results, params_cal, country=country, x_max=x_max)
    sep_names = ['price', 'inflation', 'realmoney', 'reserves']
    for sf, sname in zip(sep_figs, sep_names):
        _savefig(sf, figdir / f'fig_panel_{sname}_{country}_{attack}.pdf')
        if show:
            plt.show()
        else:
            plt.close(sf)

    return {'results': results, 'params': params_cal}


def _plot_4panel_singles(results: dict, params: dict, country: str = 'DEU',
                          x_max: float = 2.0) -> list:
    """Return list of 4 individual panel figs (no titles, with legends).

    Order: [price, inflation, real_money, reserves]
    Reserves panel uses t/T on x-axis (crisis at T=1).
    """
    T     = results['T']
    tp    = results['tvals_pre']
    tq    = results['tvals_post']
    mask  = tq <= x_max
    tq_v  = tq[mask]

    FS_LABEL = 10;  FS_LEG = 10
    col_dom = COUNTRY_COLORS.get('USA', (0.0, 0.0, 0.0))
    col_for = COUNTRY_COLORS.get(country, (0.839, 0.153, 0.157))
    cstar_val = params['cstar']

    leg_handles = [
        Line2D([], [], color=col_dom, lw=2,          label='Home (USA)'),
        Line2D([], [], color=col_for, lw=2, ls='--', label=f'Foreign ({country})'),
    ]

    def _make_pair(key, ylabel, scale=1.0):
        fig, ax = plt.subplots(figsize=(5, 4.0))
        fig.patch.set_facecolor('white');  ax.set_facecolor('white')
        pre_d = results[f'{key}_dom_pre'] * scale
        pre_f = results[f'{key}_for_pre'] * scale
        pst_d = results[f'{key}_dom_post'][mask] * scale
        pst_f = results[f'{key}_for_post'][mask] * scale
        t, yd = _join(tp, pre_d, tq_v, pst_d)
        _, yf = _join(tp, pre_f, tq_v, pst_f)
        ax.plot(t, yd, color=col_dom, lw=2)
        ax.plot(t, yf, color=col_for, lw=2, ls='--')
        ax.axvline(T, ls='--', color='k', lw=0.9)
        ax.set_ylabel(ylabel, fontsize=FS_LABEL)
        ax.set_xlim(0, x_max)
        ax.tick_params(labelsize=FS_LABEL)
        ax.grid(True, alpha=0.3)
        _set_year_ticks(ax, x_max)
        fig.legend(handles=leg_handles, loc='lower center', ncol=2,
                   fontsize=FS_LEG, frameon=False, bbox_to_anchor=(0.5, 0.0))
        fig.tight_layout(rect=[0, 0.12, 1, 1])
        return fig

    fig_p  = _make_pair('p',        r'$\log P$',  scale=1.0)
    fig_pi = _make_pair('pi',       r'% per year', scale=100)
    lo, hi = fig_pi.axes[0].get_ylim()
    fig_pi.axes[0].set_ylim(min(-1.0, lo), hi)
    fig_m  = _make_pair('m_over_y', r'% of GDP',  scale=100)

    # Reserves: dual axis, date x-axis (same as other panels)
    nom_frozen = float(results['reserves_nom_post'][0])

    fig_r, ax_r = plt.subplots(figsize=(5, 4.0))
    fig_r.patch.set_facecolor('white');  ax_r.set_facecolor('white')
    ax_r2 = ax_r.twinx()

    nom_pre_n = results['reserves_nom_pre']        / nom_frozen
    nom_pst_n = results['reserves_nom_post'][mask] / nom_frozen
    real_pre  = results['reserves_real_pre']        / cstar_val * 100
    real_pst  = results['reserves_real_post'][mask] / cstar_val * 100

    t_n, y_n = _join(tp, nom_pre_n, tq_v, nom_pst_n)
    t_r, y_r = _join(tp, real_pre,  tq_v, real_pst)

    ax_r.plot(t_n, y_n, color=col_dom, lw=2)
    ax_r2.plot(t_r, y_r, color=col_for, lw=2, ls='--')

    ax_r.set_ylabel(r'Nominal, normalized $\bar{M}^{g^*}_h = 1$', color=col_dom, fontsize=FS_LABEL)
    ax_r2.set_ylabel(r'% of For. GDP', color=col_for, fontsize=FS_LABEL)
    ax_r.tick_params(axis='y', labelcolor=col_dom, labelsize=FS_LABEL)
    ax_r2.tick_params(axis='y', labelcolor=col_for, labelsize=FS_LABEL)
    ax_r.axvline(T, ls='--', color='k', lw=0.9)
    ax_r.set_xlim(0, x_max)
    ax_r.tick_params(labelsize=FS_LABEL)
    ax_r.grid(True, alpha=0.3)
    ax_r.set_facecolor('white')
    _set_year_ticks(ax_r, x_max)
    res_leg_handles = [
        Line2D([], [], color=col_dom, lw=2,          label=r'Nominal'),
        Line2D([], [], color=col_for, lw=2, ls='--', label=r'Real (% For. GDP)'),
    ]
    fig_r.legend(handles=res_leg_handles, loc='lower center', ncol=2,
                 fontsize=FS_LEG - 1, frameon=False, bbox_to_anchor=(0.5, 0.0))
    fig_r.tight_layout(rect=[0, 0.12, 1, 1])

    return [fig_p, fig_pi, fig_m, fig_r]


# ════════════════════════════════════════════════════════════
#  STEP 2 — COMPARATIVE STATICS
# ════════════════════════════════════════════════════════════

def step_compstatics(baseline_data: dict = None,
                     country: str = 'DEU',
                     figdir: Path = DEFAULT_FIG_DIR,
                     force: bool = False,
                     show: bool = True,
                     scenarios: list = None,
                     attack: str = 'attack71'):
    print('\n' + '=' * 52)
    label = ', '.join(scenarios) if scenarios else 'all'
    print(f'  STEP: comparative statics  ({label})')
    print('=' * 52)
    figdir.mkdir(parents=True, exist_ok=True)

    if baseline_data is None:
        params_cal, _ = run_calibration_closedform(country, force=force, attack=attack,
                                                   verbose=False)
    else:
        params_cal = baseline_data['params']

    attack   = params_cal.get('attack', attack)
    cs_cache = figdir / f'comp_statics_cache_{country}_{attack}.pkl'
    cs_data  = _compute_compstatics(params_cal, cs_cache, force=force,
                                    scenarios=scenarios)
    figs = _plot_compstatics(cs_data, figdir, country=country, attack=attack)

    print('\n  Computing size CS data ...')
    size_cache = figdir / f'size_cs_cache_{country}_{attack}.pkl'
    size_data  = _compute_size_cs_data(params_cal, cache_path=size_cache, force=force)
    figs_out   = _plot_compstatics_outcomes(cs_data, size_data, figdir, country, attack)
    step_size_cs(figdir=figdir, show=show, attack=attack, size_data=size_data)
    figs.extend(figs_out)

    if show:
        plt.show()
    else:
        for f in figs:
            plt.close(f)


import contextlib, io

@contextlib.contextmanager
def _quiet():
    with contextlib.redirect_stdout(io.StringIO()):
        yield


def _eval_T_silent(params: dict) -> float:
    T = solve_T_analytical(params)
    return T if np.isfinite(T) else np.inf


def _find_param_for_T(params_base: dict, key: str, T_target: float,
                      lo: float, hi: float, sign: int = 1,
                      tol: float = 1e-4, maxiter: int = 50) -> float:
    from scipy.optimize import brentq

    def resid(val):
        p = dict(params_base)
        p[key] = val
        T = _eval_T_silent(p)
        if not np.isfinite(T):
            T = 0.0
        return sign * (T - T_target)

    lo_safe = max(lo, 1e-9)
    grid = np.geomspace(lo_safe, hi, 30)
    rs   = np.array([resid(v) for v in grid])

    bracket = None
    for i in range(len(grid) - 1):
        fa, fb = rs[i], rs[i + 1]
        if np.isfinite(fa) and np.isfinite(fb) and fa * fb < 0:
            bracket = (grid[i], grid[i + 1])
            break

    if bracket is None:
        finite = np.isfinite(rs)
        if not finite.any():
            return lo
        return float(grid[np.where(finite)[0][np.argmin(np.abs(rs[finite]))]])

    try:
        return brentq(resid, bracket[0], bracket[1], xtol=tol, maxiter=maxiter)
    except Exception:
        a, b = bracket
        return a if abs(resid(a)) <= abs(resid(b)) else b


def _compute_compstatics(params_base: dict,
                         cache_path: Path,
                         force: bool = False,
                         scenarios: list = None) -> dict:
    h = _param_hash(params_base)

    if not force and cache_path.exists():
        try:
            with open(cache_path, 'rb') as f:
                cached = pickle.load(f)
            if cached.get('param_hash') == h:
                print('  [cache] Loaded comparative statics')
                return cached
        except Exception:
            pass

    theta0 = params_base['theta']
    mbar0  = params_base['m_hgstar_bar']
    E0     = params_base['E_0']

    print('  Computing baseline T ...')
    T0 = _eval_T_silent(params_base)
    print(f'  T_base = {T0:.4f}')

    T_crash_target = 0.05

    def _want(name):
        return scenarios is None or name in scenarios

    theta_vals = theta_labels = None
    if _want('theta'):
        print('\n  Finding theta_crash ...')
        theta_crash = _find_param_for_T(params_base, 'theta',
                                        T_target=T_crash_target,
                                        lo=theta0, hi=1.0, sign=-1)
        print(f'  theta_crash = {theta_crash:.4f}')
        d_theta  = theta_crash - theta0
        theta_lo = max(0.025, theta0 - d_theta)
        theta_mid_lo = ((theta_lo + theta0) / 2 if theta0 - d_theta < 0.025
                        else theta0 - d_theta / 2)
        theta_vals = [
            theta_lo, theta_mid_lo, theta0, theta0 + d_theta / 2, theta_crash,
        ]
        theta_labels = [
            rf'$\theta={theta_lo:.3f}$',
            rf'$\theta={theta_mid_lo:.3f}$',
            rf'Baseline ($\theta={theta0:.3f}$)',
            rf'$\theta={theta0 + d_theta/2:.3f}$',
            rf'$\theta={theta_crash:.3f}$',
        ]

    mbar_vals = mbar_labels = None
    if _want('mbar'):
        print('\n  Finding mbar_crash ...')
        mbar_crash = _find_param_for_T(params_base, 'm_hgstar_bar',
                                       T_target=T_crash_target,
                                       lo=1e-6, hi=mbar0, sign=1)
        print(f'  mbar_crash = {mbar_crash:.5f}')
        d_mbar  = mbar0 - mbar_crash
        mbar_hi = mbar0 + d_mbar
        mbar_vals = [
            mbar_hi, mbar0 + d_mbar / 2, mbar0, mbar0 - d_mbar / 2, mbar_crash,
        ]
        mbar_labels = [
            rf'$\bar m={mbar_hi:.4f}$',
            rf'$\bar m={mbar0 + d_mbar/2:.4f}$',
            rf'Baseline ($\bar m={mbar0:.4f}$)',
            rf'$\bar m={mbar0 - d_mbar/2:.4f}$',
            rf'$\bar m={mbar_crash:.4f}$',
        ]

    ratio_vals = ratio_labels = None
    if _want('ratio'):
        Dh0_base = params_base['Dh0']
        Df0_base = params_base['Df0']
        r0 = Dh0_base / (Df0_base * E0)
        print('\n  Finding Lambda_crash ...')
        E_crash = _find_param_for_T(params_base, 'E_0',
                                    T_target=T_crash_target,
                                    lo=max(E0 * 0.01, 0.01), hi=E0, sign=1)
        r_crash = Dh0_base / (Df0_base * E_crash)
        print(f'  Lambda_crash = {r_crash:.4f}  (E_crash = {E_crash:.4f})')
        d_r      = r_crash - r0
        r_lo     = max(r0 - d_r, 1e-6)
        r_mid_lo = (r_lo + r0) / 2 if r0 - d_r < 1e-6 else r0 - d_r / 2
        ratio_vals = [r_lo, r_mid_lo, r0, r0 + d_r / 2, r_crash]
        ratio_labels = [
            rf'$\Lambda={r_lo:.3f}$',
            rf'$\Lambda={r_mid_lo:.3f}$',
            rf'Baseline ($\Lambda={r0:.3f}$)',
            rf'$\Lambda={r0 + d_r/2:.3f}$',
            rf'$\Lambda={r_crash:.3f}$',
        ]

    scenarios_def = {
        'theta': (r'$\theta$ (US credit growth)',                   theta_vals, theta_labels),
        'mbar':  (r'$\bar m_h^{g^*}$ (reserve limit)',             mbar_vals,  mbar_labels),
        'ratio': (r'$\Lambda = D_{h0}/(D_{f0} E)$ (relative NDA)', ratio_vals, ratio_labels),
    }
    param_keys   = {'theta': 'theta', 'mbar': 'm_hgstar_bar', 'ratio': 'ratio'}
    scenarios_def = {k: v for k, v in scenarios_def.items() if v[1] is not None}

    results_coll = {};  params_coll = {};  scenarios_out = {}

    for scen_name, (label, vals, lbls) in scenarios_def.items():
        key = param_keys[scen_name]
        print(f'\n  Scenario: {scen_name}')
        results_coll[scen_name] = [];  params_coll[scen_name] = []
        scenarios_out[scen_name] = {'label': label, 'values': vals, 'labels': lbls}

        for idx, val in enumerate(vals):
            lbl = lbls[idx]
            p = dict(params_base)
            if scen_name == 'ratio':
                p['E_0'] = params_base['Dh0'] / (params_base['Df0'] * val)
                print(f'    [{idx+1}/5]  Lambda={val:.5g}  E_0={p["E_0"]:.5g}', end='  ')
            else:
                p[key] = val
                print(f'    [{idx+1}/5]  {key}={val:.5g}', end='  ')
            try:
                with _quiet():
                    res, _ = compute_model_paths(p, tvals_size=300)
                results_coll[scen_name].append(res)
                params_coll[scen_name].append(p)
                print(f'T = {res["T"]:.4f}')
            except Exception as e:
                print(f'FAILED: {e}')
                results_coll[scen_name].append(None)
                params_coll[scen_name].append(None)

    out = {
        'results':    results_coll,
        'params':     params_coll,
        'scenarios':  scenarios_out,
        'T_base':     T0,
        'param_hash': h,
    }
    try:
        with open(cache_path, 'wb') as f:
            pickle.dump(out, f)
    except Exception:
        pass
    return out


def _plot_compstatics(cs_data: dict, figdir: Path, country: str = 'DEU', attack: str = 'attack71') -> list:
    from matplotlib.gridspec import GridSpec

    COLORS = ['#08519c', '#6baed6', '#000000', '#6baed6', '#08519c']
    LWS    = [1.5,       2.0,       2.5,       2.0,       1.5]
    LS     = ['-',       '-',       '-',       '--',      '--']
    FS_TITLE = 11;  FS_LABEL = 10;  FS_LEG = 9
    CRASH_IDX = 4

    def _set_ylim_from_data(ax, yd_list, pad=0.12):
        flat = np.concatenate([y[np.isfinite(y)] for y in yd_list if len(y)])
        if not len(flat):
            return
        lo_d, hi_d = np.min(flat), np.max(flat)
        span = max(hi_d - lo_d, 1e-8)
        ax.set_ylim(lo_d - span * pad, hi_d + span * pad)

    def _set_ylim_reserves(yd_list, pad=0.08):
        flat = np.concatenate([y[np.isfinite(y) & (y >= 0)] for y in yd_list if len(y)])
        if not len(flat):
            return None, None
        return -pad * np.max(flat), np.max(flat) * (1 + pad)

    figs = []
    for scen_name, scen in cs_data['scenarios'].items():
        res_list = cs_data['results'][scen_name]
        prm_list = cs_data['params'][scen_name]
        valid = [(r, p, i) for i, (r, p) in enumerate(zip(res_list, prm_list))
                 if r is not None]
        if not valid:
            continue

        non_crash_Ts = [r['T'] for r, _, i in valid if i != CRASH_IDX]
        T_ref = max(non_crash_Ts) if non_crash_Ts else max(r['T'] for r, _, _ in valid)
        x_max = min(5.0, np.ceil((T_ref + 0.5) * 12) / 12)

        fig = plt.figure(figsize=(10, 10))
        fig.patch.set_facecolor('white')
        gs = GridSpec(3, 2, figure=fig, hspace=0.42, wspace=0.32,
                      top=0.93, bottom=0.10)
        ax_pi_dom = fig.add_subplot(gs[0, 0])
        ax_pi_for = fig.add_subplot(gs[0, 1])
        ax_m_dom  = fig.add_subplot(gs[1, 0])
        ax_m_for  = fig.add_subplot(gs[1, 1])
        ax_res    = fig.add_subplot(gs[2, :])

        handles = [];  labels = []
        ylim_data = {ax_pi_dom: [], ax_pi_for: [],
                     ax_m_dom:  [], ax_m_for:  [], ax_res: []}

        for res, prm, idx in valid:
            T   = res['T']
            col = COLORS[idx];  lw = LWS[idx];  ls = LS[idx]
            lbl = scen['labels'][idx];  cstar = prm['cstar']
            is_crash = (idx == CRASH_IDX)
            mask = res['tvals_post'] <= x_max
            tp   = res['tvals_pre'];  tqv = res['tvals_post'][mask]

            def _p(ax, kpre, kpost, use_for_ylim=True, scale=1.0):
                ypre  = res[kpre] * scale;  ypost = res[kpost][mask] * scale
                t, y = _join(tp, ypre, tqv, ypost)
                h, = ax.plot(t, y, color=col, lw=lw, ls=ls, label=lbl)
                ax.axvline(T, ls=':', color=col, lw=0.7)
                ax.set_xlim(0, x_max);  ax.set_facecolor('white');  ax.grid(True, alpha=0.3)
                if use_for_ylim:
                    ylim_data[ax].append(np.concatenate([ypre, ypost]))
                return h

            h = _p(ax_pi_dom, 'pi_dom_pre',      'pi_dom_post',      scale=100)
            _p(ax_pi_for,     'pi_for_pre',       'pi_for_post',      scale=100)
            _p(ax_m_dom,      'm_over_y_dom_pre', 'm_over_y_dom_post', scale=100)
            _p(ax_m_for,      'm_over_y_for_pre', 'm_over_y_for_post', scale=100)

            rpre  = res['reserves_real_pre'] / cstar * 100
            rpost = res['reserves_real_post'][mask] / cstar * 100
            t, y  = _join(tp, rpre, tqv, rpost)
            ax_res.plot(t, y, color=col, lw=lw, ls=ls, label=lbl)
            ax_res.axvline(T, ls=':', color=col, lw=0.7)
            ax_res.set_xlim(0, x_max);  ax_res.set_facecolor('white');  ax_res.grid(True, alpha=0.3)
            if not is_crash:
                ylim_data[ax_res].append(np.concatenate([rpre, rpost]))
            handles.append(h);  labels.append(lbl)

        for ax in [ax_pi_dom, ax_pi_for, ax_m_dom, ax_m_for]:
            _set_ylim_from_data(ax, ylim_data[ax])
        res_lo, res_hi = _set_ylim_reserves(ylim_data[ax_res])
        if res_lo is not None:
            ax_res.set_ylim(res_lo, res_hi)

        panel_info = [
            (ax_pi_dom, r'$\pi$ (%)',      'Domestic Inflation'),
            (ax_pi_for, r'$\pi^*$ (%)',    'Foreign Inflation'),
            (ax_m_dom,  r'%',              'Domestic Real Money (% of GDP)'),
            (ax_m_for,  r'%',              'Foreign Real Money (% of GDP)'),
            (ax_res,    r'% of For. GDP',  'Real Foreign Reserves'),
        ]
        for ax, yl, ttl in panel_info:
            ax.set_title(ttl, fontsize=FS_TITLE, fontweight='bold')
            ax.set_xlabel('', fontsize=FS_LABEL)
            ax.set_ylabel(yl, fontsize=FS_LABEL)
            ax.tick_params(labelsize=FS_LABEL)
            _set_year_ticks(ax, x_max)

        do_reverse = scen['values'][-1] < scen['values'][0]
        h_ord = handles[::-1] if do_reverse else handles
        l_ord = labels[::-1]  if do_reverse else labels
        fig.legend(h_ord, l_ord, loc='lower center', ncol=len(handles),
                   fontsize=FS_LEG, frameon=False, bbox_to_anchor=(0.5, 0.01))

        _savefig(fig, figdir / f'fig_compstatics_{scen_name}_{country}_{attack}.pdf')
        figs.append(fig)
    return figs


# ════════════════════════════════════════════════════════════
#  STEP 3 — COUNTRY-SIZE COMPARATIVE STATICS
# ════════════════════════════════════════════════════════════

def _compute_size_cs_data(params_cal: dict,
                           cache_path: Path = None,
                           force: bool = False,
                           y_vals: list = None) -> tuple:
    """Compute size CS scenarios with disk cache. Returns (y_vals, results_list, params_list)."""
    if y_vals is None:
        y_vals = [0.65, 0.70, 0.75, 0.80, 0.85]

    h = _param_hash(params_cal)
    if not force and cache_path is not None and cache_path.exists():
        try:
            with open(cache_path, 'rb') as f:
                cached = pickle.load(f)
            if cached.get('param_hash') == h:
                print('  [cache] Loaded size CS data')
                return cached['y_vals'], cached['results_list'], cached['params_list']
        except Exception:
            pass

    y_base    = params_cal['y'];    ystar_base = params_cal['ystar']
    mbar_base = params_cal['m_hgstar_bar']
    # money ratios are scale-invariant — preserve them across size scenarios
    mh0y_base  = params_cal.get('m_h0_over_y',        0.07)
    mf0y_base  = params_cal.get('m_f0star_over_ystar', 0.07)

    results_list = [];  params_list = []
    for y in y_vals:
        ystar = 1.0 - y
        # Scale all level targets proportionally to country size.
        # P_0 = 1 by normalization so Dh0 = dh0 and Df0 = df0 directly.
        dh0_s  = params_cal['dh0']          * y     / y_base
        df0_s  = params_cal['df0']          * ystar / ystar_base
        mbar_s = mbar_base                  * ystar / ystar_base
        p = dict(params_cal)
        p.update({'y': y, 'c': y, 'ystar': ystar, 'cstar': ystar,
                  'dh0':          dh0_s,
                  'df0':          df0_s,
                  'm_hgstar_bar': mbar_s,
                  'Dh0':          dh0_s,
                  'Df0':          df0_s,
                  'm_h0_over_y':        mh0y_base,
                  'm_f0star_over_ystar': mf0y_base})
        print(f'  y={y:.2f}', end='  ')
        try:
            T_ana = solve_T_analytical(p)
            if not np.isfinite(T_ana):
                raise ValueError(f'solve_T_analytical returned {T_ana}')
            with _quiet():
                res, _ = compute_model_paths(p, tvals_size=300, T_known=T_ana)
            results_list.append(res);  params_list.append(p)
            print(f'T = {T_ana:.4f}')
        except Exception as e:
            print(f'FAILED: {e}')
            results_list.append(None);  params_list.append(None)

    if cache_path is not None:
        try:
            with open(cache_path, 'wb') as f:
                pickle.dump({'param_hash': h, 'y_vals': y_vals,
                             'results_list': results_list, 'params_list': params_list}, f)
        except Exception:
            pass

    return y_vals, results_list, params_list


def step_size_cs(baseline_data: dict = None,
                 country: str = 'DEU',
                 figdir: Path = DEFAULT_FIG_DIR,
                 force: bool = False,
                 show: bool = True,
                 attack: str = 'attack71',
                 size_data: tuple = None):
    print('\n' + '=' * 52)
    print('  STEP: country-size comparative statics')
    print('=' * 52)
    figdir.mkdir(parents=True, exist_ok=True)

    if size_data is None:
        if baseline_data is None:
            params_cal, _ = run_calibration_closedform(country, force=force, attack=attack,
                                                       verbose=False)
        else:
            params_cal = baseline_data['params']
        attack = params_cal.get('attack', attack)
        size_cache = figdir / f'size_cs_cache_{country}_{attack}.pkl'
        size_data = _compute_size_cs_data(params_cal, cache_path=size_cache, force=force)

    y_vals, results_list, params_list = size_data
    fig = _plot_size_cs(y_vals, results_list, params_list)
    _savefig(fig, figdir / f'fig_compstatics_size_{country}_{attack}.pdf')
    if show:
        plt.show()
    else:
        plt.close(fig)


def _plot_size_cs(y_vals, results_list, params_list):
    from matplotlib.gridspec import GridSpec

    COLORS = ['#08306b', '#2171b5', '#6baed6', '#9ecae1', '#c6dbef']
    LWS = [2.0] * 5;  LS = ['-'] * 5
    FS_TITLE = 11;  FS_LABEL = 10;  FS_LEG = 9

    valid = [(res, prm, i) for i, (res, prm) in enumerate(zip(results_list, params_list))
             if res is not None]
    if not valid:
        raise RuntimeError('All size scenarios failed.')

    T_ref = max(r['T'] for r, _, _ in valid)
    x_max = np.ceil((T_ref + 0.5) * 2) / 2   # round up to nearest 0.5 yr, no cap

    fig = plt.figure(figsize=(10, 10))
    fig.patch.set_facecolor('white')
    gs = GridSpec(3, 2, figure=fig, hspace=0.42, wspace=0.32,
                  top=0.93, bottom=0.10)
    axes = {k: fig.add_subplot(gs[r, c])
            for k, (r, c) in zip(
                ['pi_dom', 'pi_for', 'm_dom', 'm_for'],
                [(0,0),(0,1),(1,0),(1,1)])}
    ax_res = fig.add_subplot(gs[2, :])

    handles = [];  labels = []
    ylim_data = {**{a: [] for a in axes.values()}, ax_res: []}

    def _set_ylim(ax, yd_list, pad=0.12):
        flat = np.concatenate([y[np.isfinite(y)] for y in yd_list if len(y)])
        if not len(flat):
            return
        lo, hi = np.min(flat), np.max(flat)
        span = max(hi - lo, 1e-8)
        ax.set_ylim(lo - span * pad, hi + span * pad)

    for res, prm, idx in valid:
        T = res['T'];  col = COLORS[idx];  lw = LWS[idx];  ls = LS[idx]
        y_val = y_vals[idx];  cstar = prm['cstar']
        lbl = rf'$c=y={y_val:.2f},\;c^*=y^*={1-y_val:.2f}$'
        mask = res['tvals_post'] <= x_max
        tp   = res['tvals_pre'];  tqv = res['tvals_post'][mask]

        def _p(ax, kpre, kpost, scale=1.0):
            ypre = res[kpre] * scale;  ypost = res[kpost][mask] * scale
            t, y = _join(tp, ypre, tqv, ypost)
            h, = ax.plot(t, y, color=col, lw=lw, ls=ls, label=lbl)
            ax.axvline(T, ls=':', color=col, lw=0.7)
            ax.set_xlim(0, x_max);  ax.set_facecolor('white');  ax.grid(True, alpha=0.3)
            ylim_data[ax].append(np.concatenate([ypre, ypost]))
            return h

        h = _p(axes['pi_dom'], 'pi_dom_pre',      'pi_dom_post',      scale=100)
        _p(axes['pi_for'],     'pi_for_pre',       'pi_for_post',      scale=100)
        _p(axes['m_dom'],      'm_over_y_dom_pre', 'm_over_y_dom_post', scale=100)
        _p(axes['m_for'],      'm_over_y_for_pre', 'm_over_y_for_post', scale=100)

        rpre = res['reserves_real_pre'] / cstar * 100
        rpost = res['reserves_real_post'][mask] / cstar * 100
        t, y = _join(tp, rpre, tqv, rpost)
        ax_res.plot(t, y, color=col, lw=lw, ls=ls, label=lbl)
        ax_res.axvline(T, ls=':', color=col, lw=0.7)
        ax_res.set_xlim(0, x_max);  ax_res.set_facecolor('white');  ax_res.grid(True, alpha=0.3)
        ylim_data[ax_res].append(np.concatenate([rpre, rpost]))
        handles.append(h);  labels.append(lbl)

    for ax in list(axes.values()) + [ax_res]:
        _set_ylim(ax, ylim_data[ax])
    lo, hi = ax_res.get_ylim()
    ax_res.set_ylim(min(lo, 0), hi)

    panel_info = [
        (axes['pi_dom'], r'$\pi$ (%)',     'Domestic Inflation'),
        (axes['pi_for'], r'$\pi^*$ (%)',   'Foreign Inflation'),
        (axes['m_dom'],  r'%',             'Domestic Real Money (% of GDP)'),
        (axes['m_for'],  r'%',             'Foreign Real Money (% of GDP)'),
        (ax_res,         r'% of For. GDP', 'Real Foreign Reserves'),
    ]
    for ax, yl, ttl in panel_info:
        ax.set_title(ttl, fontsize=11, fontweight='bold')
        ax.set_xlabel('', fontsize=10)
        ax.set_ylabel(yl, fontsize=10)
        ax.tick_params(labelsize=10)
        _set_year_ticks(ax, x_max)

    fig.legend(handles, labels, loc='lower center', ncol=len(handles),
               fontsize=9, frameon=False, bbox_to_anchor=(0.5, 0.01))
    return fig


def _plot_compstatics_outcomes(cs_data: dict, size_data: tuple,
                               figdir: Path, country: str, attack: str) -> list:
    """4 separate figures: T of crisis (left) and attack size % GDP (right) vs parameter.

    Attack size = drop in real reserves at T (pre-T level minus post-T level).
    Panels: theta, mbar, lambda (ratio), size (y).
    """
    def _attack_size(res, prm):
        # Delta = reserve gain at T (positive): CB absorbs capital inflow at attack
        gain = res['reserves_real_post'][0] - res['reserves_real_pre'][-1]
        return float(gain / prm['cstar'] * 100)

    def _make_panel(x_valid, T_vals, size_vals, xlabel, fname, x_decimals=None):
        fig, ax_T = plt.subplots(figsize=(5, 4.0))
        fig.patch.set_facecolor('white');  ax_T.set_facecolor('white')
        ax_S = ax_T.twinx()
        ax_T.plot(x_valid, T_vals,    color=BLUE, lw=2, marker='o', ms=5)
        ax_S.plot(x_valid, size_vals, color=RED,  lw=2, marker='o', ms=5, ls='--')
        ax_T.set_xlabel(xlabel, fontsize=10)
        if x_decimals is not None:
            ax_T.xaxis.set_major_formatter(
                plt.matplotlib.ticker.FormatStrFormatter(f'%.{x_decimals}f'))
        ax_T.set_ylabel('Years', color=BLUE, fontsize=10)
        ax_S.set_ylabel(r'$\Delta$ (% of Foreign GDP)', color=RED, fontsize=10)
        ax_T.tick_params(axis='y', labelcolor=BLUE, labelsize=9)
        ax_S.tick_params(axis='y', labelcolor=RED,  labelsize=9)
        ax_T.tick_params(axis='x', labelsize=9)
        ax_T.grid(True, alpha=0.3)
        # Enforce a minimum y-span on the Delta axis so tiny numerical
        # variation (e.g. 1e-12 noise when Delta is theoretically constant)
        # doesn't get zoomed in and appear as large swings.
        s_mean = float(np.mean(size_vals))
        s_span = max(float(np.ptp(size_vals)), 0.5 * abs(s_mean), 1.0)
        ax_S.set_ylim(s_mean - s_span * 0.7, s_mean + s_span * 0.7)
        ax_S.ticklabel_format(useOffset=False, axis='y')
        fig.legend(handles=[
            Line2D([], [], color=BLUE, lw=2, marker='o', ms=5,          label='$T$ (Years)'),
            Line2D([], [], color=RED,  lw=2, marker='o', ms=5, ls='--', label=r'Attack Size (% of Foreign GDP)'),
        ], loc='lower center', ncol=2, fontsize=9, frameon=False,
           bbox_to_anchor=(0.5, 0.0))
        fig.tight_layout(rect=[0, 0.12, 1, 1])
        _savefig(fig, fname)
        return fig

    figs = []
    scen_meta = [
        ('theta', r'$\theta$'),
        ('mbar',  r'$\bar{m}_h^{g^*} / y^*$'),
        ('ratio', r'$\Lambda = D_{h0}/(D_{f0} E)$'),
    ]

    for scen_name, xlabel in scen_meta:
        if scen_name not in cs_data.get('scenarios', {}):
            continue
        scen     = cs_data['scenarios'][scen_name]
        res_list = cs_data['results'][scen_name]
        prm_list = cs_data['params'][scen_name]

        x_valid = []; T_vals = []; size_vals = []
        for xv, res, prm in zip(scen['values'], res_list, prm_list):
            if res is None or prm is None:
                continue
            xv_plot = xv / prm['cstar'] if scen_name == 'mbar' else xv
            x_valid.append(xv_plot);  T_vals.append(res['T'])
            size_vals.append(_attack_size(res, prm))

        if not x_valid:
            continue
        fig = _make_panel(x_valid, T_vals, size_vals, xlabel,
                          figdir / f'fig_outcomes_{scen_name}_{country}_{attack}.pdf',
                          x_decimals=3 if scen_name == 'mbar' else None)
        figs.append(fig)

    # Size panel
    y_vals_s, res_s, prm_s = size_data
    x_valid = []; T_vals = []; size_vals = []
    for yv, res, prm in zip(y_vals_s, res_s, prm_s):
        if res is None or prm is None:
            continue
        x_valid.append(yv);  T_vals.append(res['T'])
        size_vals.append(_attack_size(res, prm))

    if x_valid:
        fig = _make_panel(x_valid, T_vals, size_vals, r'$y$ (Home GDP share)',
                          figdir / f'fig_outcomes_size_{country}_{attack}.pdf',
                          x_decimals=2)
        figs.append(fig)

    return figs


_MONTH_ABBR = ['Jan','Feb','Mar','Apr','May','Jun',
               'Jul','Aug','Sep','Oct','Nov','Dec']

def _T_to_date_label(T):
    """Convert model time T (years from Dec 1969) to 'MM/YY' string."""
    total = 11 + int(round(T * 12))   # months since Jan 1969
    year  = 1969 + total // 12
    month = total % 12 + 1
    return f"{month:02d}/{str(year)[2:]}"

def _stata_monthly_to_label(val):
    """Convert Stata monthly integer (months since Jan 1960) to 'Mon. YY'."""
    if val is None or (isinstance(val, float) and np.isnan(val)):
        return ''
    val = int(round(val))
    year  = 1960 + val // 12
    month = val % 12 + 1
    return f"{_MONTH_ABBR[month-1]}. {str(year)[2:]}"


# ════════════════════════════════════════════════════════════
#  STEP 6 — CALIBRATION TABLE
# ════════════════════════════════════════════════════════════

def _plot_multicountry(store: dict, figdir: Path):
    """Four-column chart: model vs data reserve change at attack date (trend GDP).

    store: {(country, attack): {'res': results, 'prm': params}}
    Columns: DEU/attack71, DEU/attack73, JPN/attack71, JPN/attack73
    Solid = model, dashed = data; dashed offset right; dots + date labels on dashed.
    """
    columns    = [('DEU', 'attack71'), ('DEU', 'attack73'),
                  ('JPN', 'attack71'), ('JPN', 'attack73')]
    x_pos      = [0.0, 1.0, 2.3, 3.3]   # gap between countries
    x_offset   = 0.10                    # dashed line offset right of solid

    fig, ax = plt.subplots(figsize=(7, 5))
    fig.patch.set_facecolor('white')
    ax.set_facecolor('white')

    for i, key in enumerate(columns):
        if key not in store:
            continue
        res   = store[key]['res']
        prm   = store[key]['prm']
        ctry  = key[0]
        cstar = prm['cstar']
        col   = COUNTRY_COLORS.get(ctry, (0.5, 0.5, 0.5))
        x     = x_pos[i]
        xd    = x + x_offset

        # Model segment: last pre-attack point → first post-attack point
        y_m_lo = float(res['reserves_real_pre'][-1]  / cstar * 100)
        y_m_hi = float(res['reserves_real_post'][0]  / cstar * 100)
        ax.plot([x, x], [y_m_lo, y_m_hi], color=col, lw=2.5,
                solid_capstyle='round')
        ax.plot([x, x], [y_m_lo, y_m_hi], ls='none', marker='o',
                ms=6, color=col)

        # Data segment: prev date → attack date
        mbar_prev = prm.get('mbar_data_prev')
        mbar_atk  = prm.get('mbar_data')
        if mbar_prev is not None and mbar_atk is not None:
            y_d_lo = float(mbar_prev / cstar * 100)
            y_d_hi = float(mbar_atk  / cstar * 100)
            ax.plot([xd, xd], [y_d_lo, y_d_hi], color=col, lw=2.5,
                    ls='--', solid_capstyle='round')
            ax.plot([xd, xd], [y_d_lo, y_d_hi], ls='none', marker='o',
                    ms=6, color=col)
            lbl_lo = _stata_monthly_to_label(prm.get('fxres_prev_date'))
            lbl_hi = _stata_monthly_to_label(prm.get('fxres_attack_date'))
            txt_x  = xd + 0.04
            if lbl_lo:
                ax.text(txt_x, y_d_lo, lbl_lo, fontsize=7, va='center',
                        ha='left', color=col)
            if lbl_hi:
                ax.text(txt_x, y_d_hi, lbl_hi, fontsize=7, va='center',
                        ha='left', color=col)

            # 1971 attack only: extend upward by outstanding forward FX
            # commitments (Bundesbank forward-dollar book, Coombs 1971).
            # The ratio is computed in calibration_multi_country.do, in the
            # same units and GDP mode as the dashed data segments; countries
            # without a forwards figure have a missing value and get no marker.
            fwd_val = prm.get('fwd_h_gstar_attack71_trend')
            if key[1] == 'attack71' and fwd_val is not None and np.isfinite(fwd_val):
                forwards_adj = float(fwd_val / cstar * 100)
                col_fwd = '#8B4500'          # darker orange
                y_fwd_lo = max(y_d_lo, y_d_hi)   # start at visual top of data segment
                y_fwd_hi = y_fwd_lo + forwards_adj
                ax.plot([xd, xd], [y_fwd_lo, y_fwd_hi], color=col_fwd, lw=2.5,
                        ls='--', solid_capstyle='round')
                ax.plot(xd, y_fwd_hi, ls='none', marker='o', ms=6, color=col_fwd)
                ax.text(txt_x, y_fwd_hi, 'Forwards', fontsize=7, va='center',
                        ha='left', color=col_fwd)

    # x-axis: month labels per column, country name shared above two columns
    month_labels = []
    for key in columns:
        prm = store[key]['prm'] if key in store else {}
        lbl = _stata_monthly_to_label(prm.get('fxres_attack_date')) or ''
        month_labels.append(lbl)
    ax.set_xticks(x_pos)
    ax.set_xticklabels(month_labels, fontsize=10)
    ax.tick_params(axis='x', length=0)

    # country names centered between their two columns, below tick labels
    y_ctry = -0.10   # axes-fraction below x-axis
    country_groups = [('DEU', 0, 1), ('JPN', 2, 3)]
    for ctry, i0, i1 in country_groups:
        x_mid = (x_pos[i0] + x_pos[i1]) / 2
        ax.text(x_mid, y_ctry, ctry, transform=ax.get_xaxis_transform(),
                ha='center', va='top', fontsize=10)

    ax.set_ylabel(r'% of Trend GDP', fontsize=10)
    ax.tick_params(labelsize=10)
    ax.grid(True, alpha=0.3, axis='y')
    ax.set_xlim(-0.35, max(x_pos) + 0.7)
    ax.legend(handles=[
        Line2D([], [], color='gray', lw=2.5,          label='Model'),
        Line2D([], [], color='gray', lw=2.5, ls='--', label='Data'),
    ], frameon=False, fontsize=9, loc='upper left')
    fig.tight_layout()
    _savefig(fig, figdir / 'fig_multicountry_segments_trend.pdf')
    return fig


def step_multicountry(countries: list = None,
                      figdir: Path = DEFAULT_FIG_DIR,
                      force: bool = False,
                      show: bool = True):
    """Build model-vs-data reserve-change chart for all (country, attack) combos.

    Data reserve segments are scaled by trend-extrapolated GDP (the paper's
    specification). Calibration is unaffected — only the dashed data lines use it.
    """
    if countries is None:
        countries = ['DEU', 'JPN']

    print('\n' + '=' * 52)
    print(f'  STEP: multicountry  ({", ".join(countries)}, trend GDP)')
    print('=' * 52)
    figdir.mkdir(parents=True, exist_ok=True)

    store = {}
    for ctry in countries:
        for atk in ('attack71', 'attack73'):
            params_cal, _ = run_calibration_closedform(ctry, force=force, attack=atk,
                                                       verbose=False)
            # Swap in trend-extrapolated GDP mbar values for the data segments only
            if atk == 'attack71':
                params_cal['mbar_data']      = params_cal.get('m_hgstar_bar_attack71_trend',
                                                               params_cal.get('mbar_data'))
            else:
                params_cal['mbar_data']      = params_cal.get('m_hgstar_bar_trend',
                                                               params_cal.get('mbar_data'))
            params_cal['mbar_data_prev'] = params_cal.get('m_hgstar_bar_prev_trend',
                                                           params_cal.get('mbar_data_prev'))
            results, _T = compute_model_paths(params_cal, tvals_size=500,
                                              T_known=params_cal.get('T_target'))
            store[(ctry, atk)] = {'res': results, 'prm': params_cal}

    fig = _plot_multicountry(store, figdir)
    if show:
        plt.show()
    else:
        plt.close(fig)


# ════════════════════════════════════════════════════════════

def step_table(countries: list = None,
               attacks: list = None,
               figdir: Path = DEFAULT_FIG_DIR,
               force: bool = False) -> Path:
    """Generate combined calibration table (all countries × attacks in one table).

    Columns: DEU May 71 | DEU Mar 73 | JPN Aug 71 | JPN Mar 73
    Row sections:
      Moments   — δ_h, δ_f, μ_f, T   (data targets)
      Parameters — α, α*, m̄           (calibrated)
    """
    figdir.mkdir(parents=True, exist_ok=True)

    if countries is None:
        countries = ['DEU', 'JPN']
    if attacks is None:
        attacks = ['attack71', 'attack73']

    # Human-readable column labels per (country, attack)
    _col_label = {
        ('DEU', 'attack71'): 'May 1971',
        ('DEU', 'attack73'): 'Mar 1973',
        ('JPN', 'attack71'): 'Aug 1971',
        ('JPN', 'attack73'): 'Mar 1973',
    }
    _country_label = {'DEU': 'DEU', 'JPN': 'JPN'}

    def _sci(val):
        s = f'{val:.2e}'
        mantissa, exp = s.split('e')
        return rf'${mantissa}\times10^{{{int(exp)}}}$'

    def _fmt4(val):
        return f'{val:.3f}'

    # Collect one params_cal per (country, attack) column
    cols = []   # list of (country, attack, params_cal)
    for ctry in countries:
        for atk in attacks:
            params_cal, _ = run_calibration_closedform(ctry, force=force, attack=atk,
                                                       verbose=False)
            cols.append((ctry, atk, params_cal))

    n = len(cols)   # number of data columns

    # ── header ──────────────────────────────────────────────────────────────
    col_spec = 'l' + ' c' * n
    lines = [rf'\begin{{tabular}}{{{col_spec}}}', r'\toprule']

    # Country multicolumn headers (group consecutive same-country cols)
    header_parts = ['']
    i = 0
    while i < n:
        ctry = cols[i][0]
        span = sum(1 for c in cols[i:] if c[0] == ctry)
        label = _country_label.get(ctry, ctry)
        header_parts.append(rf'\multicolumn{{{span}}}{{c}}{{{label}}}')
        i += span
    lines.append(' & '.join(header_parts) + r' \\')

    # Cmidrule per country group
    cmidrules = []
    i = 0
    col_idx = 2  # 1-based, first data col is 2
    while i < n:
        ctry = cols[i][0]
        span = sum(1 for c in cols[i:] if c[0] == ctry)
        cmidrules.append(rf'\cmidrule(lr){{{col_idx}-{col_idx + span - 1}}}')
        col_idx += span
        i += span
    lines.append(''.join(cmidrules))

    # Attack-date sub-headers
    attack_labels = [''] + [_col_label.get((c, a), f'{c} {a}') for c, a, _ in cols]
    lines.append(' & '.join(attack_labels) + r' \\')

    # ── Moments section ──────────────────────────────────────────────────────
    lines.append(r'\midrule')
    lines.append(rf'\multicolumn{{{n + 1}}}{{l}}{{\textit{{Observations}}}} \\')

    # δ_h = d_{h,0}/y
    row = [r'$d_{h,0}/y$']
    for _, _, p in cols:
        row.append(_fmt4(p['dh0'] / p['c']))
    lines.append(' & '.join(row) + r' \\')

    # δ_f = d*_{f,0}/y*
    row = [r'$d^*_{f,0}/y^*$']
    for _, _, p in cols:
        row.append(_fmt4(p['df0'] / p['cstar']))
    lines.append(' & '.join(row) + r' \\')

    # μ_f = m*_{f,0}/y* (FX only, adjusted)
    row = [r'$m^*_{f,0}/y^*$']
    for _, _, p in cols:
        row.append(_fmt4(p.get('m_f0star_over_ystar', float('nan'))))
    lines.append(' & '.join(row) + r' \\')

    # g*_{f,0} = non-FX reserves / y* at Dec 1969
    row = [r'$g^*_{f,0}/y^*$']
    for _, _, p in cols:
        row.append(_fmt4(p.get('g_f0', float('nan'))))
    lines.append(' & '.join(row) + r' \\')

    # T
    row = [r'$T$']
    for _, _, p in cols:
        T = p.get('T_target')
        row.append(_fmt4(T) if T is not None else '---')
    lines.append(' & '.join(row) + r' \\')

    # ── Parameters section ───────────────────────────────────────────────────
    lines.append(r'\midrule')
    lines.append(rf'\multicolumn{{{n + 1}}}{{l}}{{\textit{{Parameters}}}} \\')

    # α
    row = [r'$\alpha$']
    for _, _, p in cols:
        row.append(_sci(p['alpha']))
    lines.append(' & '.join(row) + r' \\')

    # α*
    row = [r'$\alpha^*$']
    for _, _, p in cols:
        row.append(_sci(p['alphastar']))
    lines.append(' & '.join(row) + r' \\')

    # m̄ / y*
    row = [r'$\bar{m}^{g^*}_h / y^*$']
    for _, _, p in cols:
        row.append(_fmt4(p['m_hgstar_bar'] / p['cstar']))
    lines.append(' & '.join(row) + r' \\')

    lines += [r'\bottomrule', r'\end{tabular}']

    out_path = figdir / 'tab03_calibration_results.tex'
    out_path.write_text('\n'.join(lines) + '\n')
    print(f'  Saved: {out_path}')
    return out_path


# ════════════════════════════════════════════════════════════
#  CLI
# ════════════════════════════════════════════════════════════

def main():
    ap = argparse.ArgumentParser(
        description='Bretton Woods model pipeline (v2 — T-targeting calibration)')
    ap.add_argument('--step',
                    choices=['baseline', 'compstatics', 'size', 'multicountry',
                             'table', 'all', 'sync'],
                    default='all')
    ap.add_argument('--overleaf', action='store_true')
    ap.add_argument('--country', default=None, nargs='+',
                    help='Countries to run (default: DEU; multicountry/table: DEU JPN)')
    ap.add_argument('--figdir', default=None)
    ap.add_argument('--force', action='store_true')
    ap.add_argument('--no-show', action='store_true')
    ap.add_argument('--attack', default=['attack71'], nargs='+',
                    choices=['attack71', 'attack73'],
                    help='Attack date(s) to run: attack71, attack73, or both')
    ap.add_argument('--cs-scenario', default=None,
                    choices=['theta', 'mbar', 'ratio'])
    args = ap.parse_args()

    figdir    = Path(args.figdir) if args.figdir else DEFAULT_FIG_DIR
    show      = not args.no_show
    cs_scenes = [args.cs_scenario] if args.cs_scenario else None

    # Per-step defaults: single-country steps run DEU; the multicountry chart
    # and the combined table need both countries unless overridden explicitly.
    countries      = args.country or ['DEU']
    countries_both = args.country or ['DEU', 'JPN']
    attacks   = args.attack   # list of one or both

    for attack in attacks:
        baseline_data = None

        for country in countries:
            if args.step in ('baseline', 'all'):
                baseline_data = step_baseline(country=country, figdir=figdir,
                                              force=args.force, show=show,
                                              attack=attack)

            if args.step in ('compstatics', 'all'):
                step_compstatics(baseline_data=baseline_data, country=country,
                                 figdir=figdir, force=args.force, show=show,
                                 scenarios=cs_scenes, attack=attack)

            if args.step in ('size', 'all'):
                step_size_cs(baseline_data=baseline_data, country=country,
                             figdir=figdir, force=args.force, show=show,
                             attack=attack)

    if args.step in ('table', 'all'):
        step_table(countries=countries_both, attacks=attacks, figdir=figdir, force=args.force)

    if args.step in ('multicountry', 'all'):
        step_multicountry(countries=countries_both, figdir=figdir, force=args.force, show=show)

    if args.overleaf or args.step == 'sync':
        sync_to_overleaf(figdir=figdir)

    print(f'\nDone.  Figures in: {figdir}')


if __name__ == '__main__':
    main()
