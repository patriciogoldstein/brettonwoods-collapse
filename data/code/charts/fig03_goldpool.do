*==============================================================================
* fig03_goldpool.do — Gold Pool interventions + official/market gold price
* Input:   $raw/naefdata/naef_figure101.xlsx (Naef 2022), $raw/gfd/gfd_goldprice_2025-06-02.xlsx
* Output:  $charts/fig03_goldpool.pdf (Fig 3)
*==============================================================================


import excel using "$raw/naefdata/naef_figure101.xlsx", ///
    cellrange(A2:C5845) clear

rename A date_daily
rename B er_raw
rename C intervention_daily

format date_daily %td

keep if inrange(date_daily, dmy(6,11,1961), dmy(14,3,1968))
gen month = mofd(date_daily)
format month %tm
collapse (sum) intervention_monthly = intervention_daily, by(month)
tempfile interventions
save `interventions'


* ---- Gold premium from GFD data ----

import excel "$raw/gfd/gfd_goldprice_2025-06-02.xlsx", clear firstrow
keep if Year >= 1960 & Year <= 1974
keep Date Close
gen date_daily = date(Date, "MDY")
format date_daily %td
drop Date


gen Official = 35
replace Official = 38    if date >= `${smithsonian_day}'
replace Official = 42.22 if date >= `${g10deval_day}'
gen log_official = ln(Official)
gen log_parallel = ln(Close)

gen month = mofd(date_daily)
format month %tm
collapse (mean) log_official log_parallel, by(month)

tempfile goldpremium
save `goldpremium'


* ---- Merge ----

use `goldpremium', clear
keep if inrange(month, ym(1960,1), ym(1974,12))

merge 1:1 month using `interventions'
drop _merge
keep if inrange(month, ym(1960,1), ym(1974,12))
sort month


global lformat "lwidth(medium)"

twoway ///
    (bar intervention_monthly month, barwidth(0.8) color(red) yaxis(1)) ///
    (line log_parallel month, lcolor(navy) $lformat yaxis(2)) ///
    (line log_official month, lcolor(cranberry) $lformat lpattern(dash) yaxis(2)) ///
    , ///
    legend(order(1 "Monthly Gold Pool Interventions (USD M)" 3 "Official Price" 2 "Market Price") size(${fontsize}) pos(6) rows(1)) ///
    ytitle("Gold Pool Interventions (USD M)", size(${fontsize}) axis(1)) ///
    ytitle("Gold Price (USD/oz)", size(${fontsize}) axis(2)) ///
    xtitle("", size(${fontsize})) ///
    xline(`${goldpoolstart_month}', lpattern(dash) lcolor(gs6)) ///
    text(190 `${goldpoolstart_month}' "Gold Pool Start", place(w) size(small) color(gs4)) ///
    xline(`${gbpdeval_month}', lpattern(dash) lcolor(gs4)) ///
    text(190 `${gbpdeval_month}' "GBP Devaluation", place(w) size(small) color(gs2)) ///
    xline(`$goldpoolend_month', lpattern(dash) lcolor(gs4)) ///
    text(190 `$goldpoolend_month' "Gold Pool End", place(e) size(small) color(gs2)) ///
    xline(`$nixonshock_month', lpattern(dash) lcolor(gs8)) ///
    text(190 `$nixonshock_month' "Nixon Shock", place(e) size(small) color(gs6)) ///
    xline(`$g10float_month', lpattern(dash) lcolor(gs4)) ///
    text(190 `$g10float_month' "G10 Float", place(e) size(small) color(gs2)) ///
    xlabel(, labsize(${fontsize}) format(%tmCCYY)) ///
    ylabel(, labsize(${fontsize}) axis(1)) ///
    ylabel(`=ln(35)' "35" `=ln(50)' "50" `=ln(100)' "100" `=ln(200)' "200" , labsize(${fontsize}) axis(2)) ///
    xsize(8) ysize(4)

graph export "$charts/fig03_goldpool.pdf", replace
graph export "$charts/fig03_goldpool.png", replace
