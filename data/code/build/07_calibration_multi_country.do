*==============================================================================
* 07_calibration_multi_country.do — model calibration inputs (theta, m_bar, shares)
* Input:   $temp/mfs_cbs_M.dta, $temp/imfreserves_M.dta, $wdisnapshot (frozen WDI)
* Output:  $charts/tab02_calibration_assumptions.tex (paper "Calibration Assumptions" table)
*          $charts/tab02_calibration_assumptions_slides.tex (compact slides version)
*          ${pathmodel}/calibration_values.csv (read by model/bw_main.py)
* Notes:   theta = growth-adjusted NDA trend 1964-73, same quantity as Table 1
*          (December GDP anchoring, newey point estimates). After rerunning,
*          regenerate the model figures (bw_main.py).
*==============================================================================

global countries "USA DEU JPN"
global yearinit 1969
global yearmin 1968
global yearmax 1973
global thetayearmin 1964
global thetayearmax 1973

* ============================================================================
* FX Reserve Date Settings
* fxres_attack71   : primary attack71 date
* fxres_prev_date  : fxres_attack71 - 1 month (bottom of dashed jump)
* fxres_date       : attack73 date = Mar 1973 for all
* ============================================================================

local DEU_fxres_date     = `$g10float_month'
local JPN_fxres_date     = `$g10float_month'

local DEU_fxres_attack71 = `$demfloat_month'
local JPN_fxres_attack71 = `$nixonshock_month'

local DEU_fxres_prev_date = `DEU_fxres_attack71' - 1
local JPN_fxres_prev_date = `JPN_fxres_attack71' - 1

* ============================================================================
* AUX
* ============================================================================

local ctry_count : word count $countries
local inlist_condition ""
forvalues i = 1/`ctry_count' {
    local ctry : word `i' of $countries
    if `i' == 1 {
        local inlist_condition `""`ctry'""'
    }
    else {
        local inlist_condition `"`inlist_condition',"`ctry'""'
    }
}
global countries_inlist `"inlist(country_iso3,`inlist_condition')"'


* ============================================================================
* Monetary Vars
* ============================================================================

local totalfreq = 12
local freqname  "month"

import delimited "$wdisnapshot", clear

gen keep = .
foreach country of global countries {
    replace keep = 1 if countrycode == "`country'"
}
keep if keep == 1
drop keep

keep countrycode year ny_gdp_mktp_kd ny_gdp_mktp_cn ne_con_totl_zs
rename countrycode   country_iso3
rename ny_gdp_mktp_kd gdp_lcuconstant
rename ny_gdp_mktp_cn gdp_lcu
rename ne_con_totl_zs conshare_wb
tempfile wb_annual
save `wb_annual'

use "$temp/mfs_cbs_M.dta", clear
keep if $countries_inlist

drop if country_iso3 == "DEU" & year < 1968
drop if country_iso3 == "USA" & year < 1960
drop if country_iso3 == "JPN" & year < 1965

egen id = group(country_iso3)
xtset id date

merge m:1 country_iso3 year using `wb_annual', keep(match master) nogenerate

* ---- GDP interpolation (constant LCU) ----
* Annual GDP anchored at DECEMBER, matching charts/tab01_nda_growth.do (Table 1)
gen gdp_lcuconstant_m = ln(gdp_lcuconstant)
replace gdp_lcuconstant_m = . if month(dofm(date)) != 12
bys id (date): ipolate gdp_lcuconstant_m date, gen(gdp_lcuconstant_ipol)
replace gdp_lcuconstant_ipol = exp(gdp_lcuconstant_ipol)

* ---- GDP interpolation (current LCU) ----
gen gdp_lcu_m = ln(gdp_lcu)
replace gdp_lcu_m = . if month(dofm(date)) != 12
bys id (date): ipolate gdp_lcu_m date, gen(gdp_lcu_ipol)
replace gdp_lcu_ipol = exp(gdp_lcu_ipol)
gen cons_lcu_ipol = gdp_lcu_ipol

* ---- Monetary aggregates ----
drop nda
gen nda = rm - nfa
gen nda_log          = ln(nda)

gen nda_gdpratio_log = ln(nda / gdp_lcuconstant_ipol)
gen nda_gdpratio     = nda / gdp_lcu_ipol
gen mb_gdpratio      = rm  / gdp_lcu_ipol

gen nda_consratio    = nda / cons_lcu_ipol
gen mb_consratio     = rm  / cons_lcu_ipol

bys country_iso3 (date): gen t = _n

* ============================================================================
* Theta calculation (growth-adjusted, standalone Newey-West, $thetayearmin-$thetayearmax)
* Each country: annualized NDA log trend minus average annual GDP growth rate
* GDP growth anchored at first available year in window (to handle late-starting series)
* ============================================================================

foreach c of global countries {
    preserve
    keep if country_iso3=="`c'" & inrange(year, $thetayearmin, $thetayearmax)
    sort id date
    quietly count
    local n = r(N)
    if `n' > 0 {
        local customlag = floor(4*(`n'/100)^(2/9))
        quietly newey nda_log t, lag(`customlag')
        local theta_nda_`c' = `totalfreq' * _b[t]
        quietly sum year, meanonly
        local gstart = r(min)
        quietly sum gdp_lcuconstant if year == `gstart', meanonly
        local gdp_s = r(mean)
        quietly sum gdp_lcuconstant if year == $thetayearmax, meanonly
        local gdp_e = r(mean)
        local gdpgr_`c' = (ln(`gdp_e') - ln(`gdp_s')) / ($thetayearmax - `gstart')
        local theta_adj_`c' = `theta_nda_`c'' - `gdpgr_`c''
    }
    else {
        local theta_adj_`c' = .
    }
    restore
    di "`c'  theta_nda = `theta_nda_`c''  gdpgr = `gdpgr_`c''  theta_adj = `theta_adj_`c''"
}

local USA_theta = `theta_adj_USA'

local foreignctry "DEU JPN"
foreach c of local foreignctry {
    local `c'_thetastar = `theta_adj_`c''

    * Starting NDA/Consumption share in ${yearinit}
    local `c'_ndaconsstartshare = .
    quietly count if country_iso3=="`c'" & year==${yearinit} & !missing(nda_consratio)
    if r(N) > 0 {
        preserve
        keep if country_iso3=="`c'" & year==${yearinit} & !missing(nda_consratio)
        gsort -date
        local `c'_ndaconsstartshare = nda_consratio[1]
        restore
    }

    * Initial MB/Consumption share at ${yearinit} (last available month)
    local `c'_mbconsstartshare = .
    quietly count if country_iso3=="`c'" & year==${yearinit} & !missing(mb_consratio)
    if r(N) > 0 {
        preserve
        keep if country_iso3=="`c'" & year==${yearinit} & !missing(mb_consratio)
        gsort -date
        local `c'_mbconsstartshare = mb_consratio[1]
        restore
    }

    di "`c'  theta* = ``c'_thetastar'   NDA/Cons_${yearinit} = ``c'_ndaconsstartshare'  MB/Cons_${yearinit} = ``c'_mbconsstartshare'"
}

* USA initial MB/Consumption share at ${yearinit}
local USA_ndaconsstartshare = .
quietly count if country_iso3=="USA" & year==${yearinit} & !missing(nda_consratio)
if r(N) > 0 {
    preserve
    keep if country_iso3=="USA" & year==${yearinit} & !missing(nda_consratio)
    gsort -date
    local USA_ndaconsstartshare = nda_consratio[1]
    restore
}

local USA_mbconsstartshare = .
quietly count if country_iso3=="USA" & year==${yearinit} & !missing(mb_consratio)
if r(N) > 0 {
    preserve
    keep if country_iso3=="USA" & year==${yearinit} & !missing(mb_consratio)
    gsort -date
    local USA_mbconsstartshare = mb_consratio[1]
    restore
}

di "USA  theta = `USA_theta'   NDA/Cons_${yearinit} = `USA_ndaconsstartshare'  MB/Cons_${yearinit} = `USA_mbconsstartshare'"

* ============================================================================
* GDP and Consumption Shares
* ============================================================================

import delimited "$wdisnapshot", clear

gen keep = .
foreach country of global countries {
    replace keep = 1 if countrycode == "`country'"
}
keep if keep == 1
drop keep

keep countrycode year ny_gdp_mktp_kd
keep if year >= $yearmin & year <= $yearmax
rename countrycode country_iso3
rename ny_gdp_mktp_kd gdp_kd

preserve
    keep if country_iso3 == "USA"
    rename gdp_kd gdp_usa
    keep year gdp_usa
    tempfile usagdp
    save `usagdp'
restore

merge m:1 year using `usagdp', keep(match master) nogenerate

gen gdp_ratio_c   = gdp_kd  / (gdp_kd + gdp_usa)   if country_iso3 != "USA"
gen gdp_ratio_usa = gdp_usa / (gdp_kd + gdp_usa)    if country_iso3 != "USA"

collapse (mean) gdp_ratio_c gdp_ratio_usa, by(country_iso3)

foreach c of local foreignctry {
    quietly su gdp_ratio_c   if country_iso3 == "`c'", meanonly
    local y_`c'_`c' = r(mean)
    quietly su gdp_ratio_usa if country_iso3 == "`c'", meanonly
    local y_USA_`c' = r(mean)
}

* ============================================================================
* Reserves (scaled by own current-USD GDP in the fxres_prev_date year)
* ============================================================================

import delimited "$wdisnapshot", clear

gen keep = .
foreach country of global countries {
    replace keep = 1 if countrycode == "`country'"
}
keep if keep == 1
drop keep

keep countrycode year ny_gdp_mktp_cd
rename countrycode country_iso3
rename ny_gdp_mktp_cd gdp_cur_usd
tempfile wb_gdp
save `wb_gdp'

use "$temp/imfreserves_M.dta", clear

merge m:1 country_iso3 year using `wb_gdp', keep(match master) nogenerate

foreach c of local foreignctry {
    local fxres_prev_year_`c' = year(dofm(``c'_fxres_prev_date'))

    preserve
    keep if country_iso3 == "`c'"
    sort date

    * Interpolate current-USD GDP monthly (log-linear, annual value anchored at Dec)
    gen gdp_cur_usd_log = ln(gdp_cur_usd) if month(dofm(date)) == 12
    ipolate gdp_cur_usd_log date, gen(gdp_cur_usd_log_ipol) epolate
    gen gdp_cur_usd_ipol = exp(gdp_cur_usd_log_ipol)

    qui sum gdp_cur_usd if year == `fxres_prev_year_`c'', meanonly
    local gdp_base_`c' = r(mean)

    * --- g_f0: non-FX reserves / interpolated GDP at Dec 1969 ---
    * Non-FX = gold + IMF position + SDRs (all in USD millions from IMF data)
    * Divided by interpolated current-USD GDP → directly comparable to mb_consratio (LCU/LCU)
    foreach rtype in gold imf sdr {
        qui sum reserves_`rtype' if year == 1969 & month(dofm(date)) == 12, meanonly
        local `rtype'_dec69 = cond(r(N) > 0, r(mean), 0)
    }
    qui sum gdp_cur_usd_ipol if year == 1969 & month(dofm(date)) == 12, meanonly
    local gdp_dec69_ipol = r(mean)
    local g_f0_`c' = (`gold_dec69' + `imf_dec69' + `sdr_dec69') * 1e6 / `gdp_dec69_ipol'
    di "`c' g_f0 (non-FX reserves / GDP, Dec 1969) = `g_f0_`c''"

    * --- Log-linear trend: regress ln(GDP_cur_usd) on year, 1968-1973 ---
    * Cannot use nested preserve in Stata; use tempfile instead
    tempfile trend_data_`c'
    quietly save `trend_data_`c'', replace
    collapse (mean) gdp_cur_usd, by(year)
    keep if inrange(year, 1968, 1973) & !missing(gdp_cur_usd)
    gen lngdp = ln(gdp_cur_usd)
    gen yr    = year - 1968
    quietly regress lngdp yr
    local b_trend_`c' = _b[yr]   // annualised log growth rate
    use `trend_data_`c'', clear
    di "`c' GDP trend (log annual growth rate, 1968-1973) = `b_trend_`c''"

    * Interpolated GDP at prev_date (anchor for trend extrapolation)
    qui sum gdp_cur_usd_ipol if date == ``c'_fxres_prev_date', meanonly
    local gdp_prev_`c' = r(mean)

    * Trend GDP at the 1971 attack (USD bn) — denominator for the Forwards
    * marker in the model's multicountry chart (same as the data segments)
    local gdp_usdbn_a71_trend_`c' = `gdp_prev_`c'' * exp(`b_trend_`c'' * (``c'_fxres_attack71' - ``c'_fxres_prev_date') / 12) / 1e9

    keep if date == ``c'_fxres_date' | date == ``c'_fxres_attack71' | date == ``c'_fxres_prev_date'

    if _N > 0 {
        gen fxres_cons      = reserves_fx * 1e6 / `gdp_base_`c''

        * Trend GDP: anchor at gdp_prev, grow at b_trend annual rate
        gen months_from_prev  = date - ``c'_fxres_prev_date'
        gen gdp_trend         = `gdp_prev_`c'' * exp(`b_trend_`c'' * months_from_prev / 12)
        gen fxres_cons_trend  = reserves_fx * 1e6 / gdp_trend

        * --- base-GDP deflator ---
        qui sum fxres_cons if date == ``c'_fxres_date', meanonly
        local `c'_fxres_cons = r(mean)
        qui sum fxres_cons if date == ``c'_fxres_attack71', meanonly
        local `c'_fxres_cons_attack71 = r(mean)
        if r(N) == 0 local `c'_fxres_cons_attack71 = .
        qui sum fxres_cons if date == ``c'_fxres_prev_date', meanonly
        local `c'_fxres_cons_prev = r(mean)
        if r(N) == 0 local `c'_fxres_cons_prev = .

        * --- trend-extrapolated GDP deflator ---
        qui sum fxres_cons_trend if date == ``c'_fxres_date', meanonly
        local `c'_fxres_cons_trend = r(mean)
        qui sum fxres_cons_trend if date == ``c'_fxres_attack71', meanonly
        local `c'_fxres_cons_attack71_trend = r(mean)
        if r(N) == 0 local `c'_fxres_cons_attack71_trend = .
        qui sum fxres_cons_trend if date == ``c'_fxres_prev_date', meanonly
        local `c'_fxres_cons_prev_trend = r(mean)
        if r(N) == 0 local `c'_fxres_cons_prev_trend = .

        di "`c' FX res attack73  base=``c'_fxres_cons'  trend=``c'_fxres_cons_trend'"
        di "`c' FX res attack71  base=``c'_fxres_cons_attack71'  trend=``c'_fxres_cons_attack71_trend'"
        di "`c' FX res prev      base=``c'_fxres_cons_prev'  trend=``c'_fxres_cons_prev_trend'"
    }
    else {
        foreach suf in "" "_attack71" "_prev" {
            local `c'_fxres_cons`suf'       = .
            local `c'_fxres_cons`suf'_trend = .
        }
        di "`c' FX reserves: data not available"
    }
    restore
}


* ============================================================================
* Calibration objects
* ============================================================================

local sigma 2
local rho 0.05

foreach c of local foreignctry {

    * c = y
    local c_USA_`c' = `y_USA_`c''
    local c_`c'_`c' = `y_`c'_`c''

    * theta
    local theta_`c'     = `USA_theta'
    local thetastar_`c' = ``c'_thetastar'

    * mbar (base-year GDP deflator)
    local mbar_h_gstar_`c'          = (``c'_fxres_cons')          * `c_`c'_`c''
    local mbar_h_gstar_attack71_`c' = (``c'_fxres_cons_attack71') * `c_`c'_`c''
    local mbar_h_gstar_prev_`c'     = (``c'_fxres_cons_prev')     * `c_`c'_`c''

    * mbar (trend-extrapolated GDP deflator)
    local mbar_trend_`c'     = (``c'_fxres_cons_trend')          * `c_`c'_`c''
    local mbar_a71_trend_`c' = (``c'_fxres_cons_attack71_trend') * `c_`c'_`c''
    local mbar_pv_trend_`c'  = (``c'_fxres_cons_prev_trend')     * `c_`c'_`c''

    * Forward FX commitments at the 1971 attack (USD bn): Bundesbank
    * forward-dollar book outstanding by May 1971, Coombs (1971)
    * [coombs_treasury_1971]. No comparable figure for Japan (missing).
    local coombs_fwd_usdbn_`c' = cond("`c'" == "DEU", 2.7, .)

    * Same units as the mbar_* rows (ratio to trend GDP x y*)
    local fwd_a71_trend_`c' = `coombs_fwd_usdbn_`c'' / `gdp_usdbn_a71_trend_`c'' * `c_`c'_`c''

    * Initial MB/output ratios at ${yearinit}
    * m_f0star_over_ystar adjusted: subtract non-FX reserves / GDP (g_f0)
    * g_f0 and mb_consratio are both dimensionless ratios (USD/USD and LCU/LCU cancel)
    local m_h0_over_y_`c'             = `USA_mbconsstartshare'
    local m_f0star_over_ystar_raw_`c' = ``c'_mbconsstartshare'
    local m_f0star_over_ystar_`c'     = ``c'_mbconsstartshare' - `g_f0_`c''
    di "`c' m_f0*/y* raw=`m_f0star_over_ystar_raw_`c''  g_f0=`g_f0_`c''  adj=`m_f0star_over_ystar_`c''"
}

* ============================================================================
* TeX table: Var | Description | Source | DEU | JPN
* Shared parameters (sigma, rho, E_0, theta) shown once (DEU column only)
* ============================================================================

file open fh using "$charts/tab02_calibration_assumptions.tex", write replace
file write fh "\begin{tabular}{l l l c c}" _n
file write fh "\toprule" _n
file write fh "Var. & Description & Source & DEU & JPN \\" _n
file write fh "\midrule" _n

* Shared parameters (same across all country pairs)
file write fh `"\(\sigma\) & Inverse intertemporal elasticity of substitution & Assumption & `=string(`sigma',"%9.0f")' & \\"' _n
file write fh `"\(\rho\) & Discount rate & Assumption & `=string(`rho',"%9.2f")' & \\"' _n
file write fh `"\(E_0\) & Fixed exchange rate & Assumption & 1 & \\"' _n
file write fh `"\(\theta\) & US dom.\ credit growth & IMF, WB & `=string(`theta_DEU',"%9.3f")' & \\"' _n
file write fh "\midrule" _n

* Country-specific parameters
file write fh `"\(y\) & US real GDP share (`=$yearmin'--`=$yearmax') & WB & `=string(`y_USA_DEU',"%9.3f")' & `=string(`y_USA_JPN',"%9.3f")' \\"' _n
file write fh `"\(y^{*}\) & Foreign real GDP share (`=$yearmin'--`=$yearmax') & WB & `=string(`y_DEU_DEU',"%9.3f")' & `=string(`y_JPN_JPN',"%9.3f")' \\"' _n
file write fh `"\(\theta^{*}\) & Foreign dom.\ credit growth & IMF, WB & `=string(`thetastar_DEU',"%9.3f")' & `=string(`thetastar_JPN',"%9.3f")' \\"' _n

file write fh "\bottomrule" _n
file write fh "\end{tabular}" _n
file close fh

* Slides version: same numbers, abbreviated descriptions (fits a beamer frame)
file open fs using "$charts/tab02_calibration_assumptions_slides.tex", write replace
file write fs "\begin{tabular}{l l l c c}" _n
file write fs "\toprule" _n
file write fs "Var. & Description & Source & DEU & JPN \\" _n
file write fs "\midrule" _n
file write fs `"\(\sigma\) & Inv.\ IES & Assumption & `=string(`sigma',"%9.0f")' & \\"' _n
file write fs `"\(\rho\) & Discount rate & Assumption & `=string(`rho',"%9.2f")' & \\"' _n
file write fs `"\(E_0\) & Fixed exchange rate & Assumption & 1 & \\"' _n
file write fs `"\(\theta\) & US dom.\ credit growth & IMF, WB & `=string(`theta_DEU',"%9.3f")' & \\"' _n
file write fs "\midrule" _n
file write fs `"\(y\) & US real GDP share (`=$yearmin'--`=$yearmax') & WB & `=string(`y_USA_DEU',"%9.3f")' & `=string(`y_USA_JPN',"%9.3f")' \\"' _n
file write fs `"\(y^{*}\) & Foreign real GDP share & WB & `=string(`y_DEU_DEU',"%9.3f")' & `=string(`y_JPN_JPN',"%9.3f")' \\"' _n
file write fs `"\(\theta^{*}\) & Foreign dom.\ credit growth & IMF, WB & `=string(`thetastar_DEU',"%9.3f")' & `=string(`thetastar_JPN',"%9.3f")' \\"' _n
file write fs "\bottomrule" _n
file write fs "\end{tabular}" _n
file close fs

* ============================================================================
* CSV export
* ============================================================================

clear
set obs 24
gen str40 name = ""

foreach c of local foreignctry {
    gen double value_`c' = .
}

local i = 0

local ++i
replace name="sigma" in `i'
foreach c of local foreignctry {
    replace value_`c' = `sigma' in `i'
}

local ++i
replace name="rho" in `i'
foreach c of local foreignctry {
    replace value_`c' = `rho' in `i'
}

local ++i
replace name="y" in `i'
foreach c of local foreignctry {
    replace value_`c' = `y_USA_`c'' in `i'
}

local ++i
replace name="y_star" in `i'
foreach c of local foreignctry {
    replace value_`c' = `y_`c'_`c'' in `i'
}

local ++i
replace name="c" in `i'
foreach c of local foreignctry {
    replace value_`c' = `c_USA_`c'' in `i'
}

local ++i
replace name="c_star" in `i'
foreach c of local foreignctry {
    replace value_`c' = `c_`c'_`c'' in `i'
}

local ++i
replace name="theta" in `i'
foreach c of local foreignctry {
    replace value_`c' = `theta_`c'' in `i'
}

local ++i
replace name="theta_star" in `i'
foreach c of local foreignctry {
    replace value_`c' = `thetastar_`c'' in `i'
}

local ++i
replace name="dh0_over_c" in `i'
foreach c of local foreignctry {
    replace value_`c' = `USA_ndaconsstartshare' in `i'
}

local ++i
replace name="df0_over_cstar" in `i'
foreach c of local foreignctry {
    replace value_`c' = ``c'_ndaconsstartshare' in `i'
}

local ++i
replace name="mbar_h_gstar_attack73" in `i'
foreach c of local foreignctry {
    replace value_`c' = `mbar_h_gstar_`c'' in `i'
}

local ++i
replace name="mbar_h_gstar_attack71" in `i'
foreach c of local foreignctry {
    replace value_`c' = `mbar_h_gstar_attack71_`c'' in `i'
}

local ++i
replace name="mbar_h_gstar_prev" in `i'
foreach c of local foreignctry {
    replace value_`c' = `mbar_h_gstar_prev_`c'' in `i'
}

local ++i
replace name="fxres_attack73" in `i'
foreach c of local foreignctry {
    replace value_`c' = ``c'_fxres_date' in `i'
}

local ++i
replace name="fxres_attack71" in `i'
foreach c of local foreignctry {
    replace value_`c' = ``c'_fxres_attack71' in `i'
}

local ++i
replace name="fxres_prev_date" in `i'
foreach c of local foreignctry {
    replace value_`c' = ``c'_fxres_prev_date' in `i'
}

local ++i
replace name="m_h0_over_y" in `i'
foreach c of local foreignctry {
    replace value_`c' = `m_h0_over_y_`c'' in `i'
}

local ++i
replace name="m_f0star_over_ystar" in `i'
foreach c of local foreignctry {
    replace value_`c' = `m_f0star_over_ystar_`c'' in `i'   // adjusted: raw - g_f0
}

local ++i
replace name="m_f0star_over_ystar_raw" in `i'
foreach c of local foreignctry {
    replace value_`c' = `m_f0star_over_ystar_raw_`c'' in `i'
}

local ++i
replace name="g_f0" in `i'
foreach c of local foreignctry {
    replace value_`c' = `g_f0_`c'' in `i'
}

local ++i
replace name="mbar_h_gstar_attack73_trend" in `i'
foreach c of local foreignctry {
    replace value_`c' = `mbar_trend_`c'' in `i'
}

local ++i
replace name="mbar_h_gstar_attack71_trend" in `i'
foreach c of local foreignctry {
    replace value_`c' = `mbar_a71_trend_`c'' in `i'
}

local ++i
replace name="mbar_h_gstar_prev_trend" in `i'
foreach c of local foreignctry {
    replace value_`c' = `mbar_pv_trend_`c'' in `i'
}

* Forward FX commitments at the 1971 attack (Coombs 1971), same units as the
* mbar_* rows; missing for countries without a forwards figure
local ++i
replace name="fwd_h_gstar_attack71_trend" in `i'
foreach c of local foreignctry {
    replace value_`c' = `fwd_a71_trend_`c'' in `i'
}

export delimited using "${pathmodel}/calibration_values.csv", replace
