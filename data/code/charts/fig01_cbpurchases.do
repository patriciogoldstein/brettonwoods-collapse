*==============================================================================
* fig01_cbpurchases.do — weekly change in CB FX holdings, per-country panels
* Input:   $path/CB_FX_holdings_Fig1_public.xlsx (sheet data_long),
*          $temp/bis_exchangerates_W.dta, $temp/temp_wdigdp.dta
* Output:  $charts/fig01_cbpurchases.pdf (Fig 1), figA1_cbpurchases_2.pdf (appendix)
*
* Reads the "total (plotted)" row per country, applies the per-country scaling
* (FRF/NLG /1e6, SEK/JPY thousand /1e3), the weekdate reassignments (see below),
* weekly BIS-rate USD conversion and the 1971-GDP deflator.
*
* NOTE on the "replace weekdate = ..." lines (CHE/DEU/NLD/BEL/SWE blocks): Stata's
* week() bins days [7(w-1)+1, 7w] (week 52 absorbs the year-end tail), so two returns a
* few days apart can share a bin and break the "merge 1:1 ... weekdate" / "tsset" or
* collapse a genuine week-to-week change. Each replace bumps ONE colliding return to the
* adjacent free week, preserving order. Do NOT remove without re-checking for dup weekdates.
*==============================================================================

* ---- load public data: keep the plotted total per country, parse raw dates ----
import excel "$path/CB_FX_holdings_Fig1_public.xlsx", firstrow sheet("data_long") clear
keep if role=="total (plotted)"
gen edate = date(date,"YMD")
format edate %td
drop date
rename edate date
rename value fxreserves
keep iso3 date fxreserves
tempfile pub
save `pub'

* ============================ per-country prep ================================
* CHE — CHF million, gross
use `pub', clear
keep if iso3=="CHE"
gen year = year(date)
gen weekdate = yw(year(date), week(date))
replace weekdate = 680 if date == dmy(28,1,1973)
format weekdate %tw
drop if weekdate==.
tsset weekdate
gen country_iso3 = "CHE"
merge 1:1 country_iso3 weekdate using "$temp/bis_exchangerates_W.dta"
drop if _merge ==2
drop _merge
rename value er
replace fxreserves = fxreserves / er
gen d_fx = .
replace d_fx = fxreserves - fxreserves[_n-1] if _n > 1
keep country_iso3 weekdate d_fx fxreserves
save "$temp/cbwk_pub_CHE.dta", replace

* DEU — DEM million (deposits + other foreign investments), gross
use `pub', clear
keep if iso3=="DEU"
drop if date==.
gen year = year(date)
gen weekdate = yw(year(date), week(date))
replace weekdate = 674 if date == dmy(23,12,1972)
format weekdate %tw
tsset weekdate
gen country_iso3 = "DEU"
merge 1:1 country_iso3 weekdate using "$temp/bis_exchangerates_W.dta"
drop if _merge ==2
drop _merge
rename value er
replace fxreserves = fxreserves / er
gen d_fx = .
replace d_fx = fxreserves - fxreserves[_n-1] if _n > 1
keep if year>=1971 & year <= 1973
keep country_iso3 weekdate d_fx fxreserves
save "$temp/cbwk_pub_DEU.dta", replace

* FRA — raw FRF (disponibilites + FSC autres) -> /1e6, gross
use `pub', clear
keep if iso3=="FRA"
gen year = year(date)
gen weekdate = yw(year(date), week(date))
format weekdate %tw
replace fxreserves = fxreserves/1e6
gen country_iso3 = "FRA"
keep if (date >= dmy(31,12,1970) & year<=1973)
merge 1:1 country_iso3 weekdate using "$temp/bis_exchangerates_W.dta"
drop if _merge ==2
drop _merge
rename value er
replace fxreserves = fxreserves / er
gen d_fx = .
replace d_fx = fxreserves - fxreserves[_n-1] if _n > 1
keep country_iso3 weekdate d_fx fxreserves
save "$temp/cbwk_pub_FRA.dta", replace

* GBR — daily USD intervention flow -> weekly sum
use `pub', clear
keep if iso3=="GBR"
gen year = year(date)
keep if year>=1971 & year<=1973
gen weekdate = yw(year(date), week(date))
format weekdate %tw
collapse (sum) fxreserves, by(weekdate)
tsset weekdate
gen d_fx = fxreserves
gen country_iso3 = "GBR"
keep country_iso3 weekdate d_fx
drop if weekdate==.
save "$temp/cbwk_pub_GBR.dta", replace

* NLD — raw NLG (FX claims net of FX balances) -> /1e6, net
use `pub', clear
keep if iso3=="NLD"
gen year = year(date)
gen weekdate = yw(year(date), week(date))
replace weekdate = 728 if date == dmy(31,12,1973)
format weekdate %tw
replace fxreserves = fxreserves/1e6
gen country_iso3 = "NLD"
drop if weekdate==.
merge 1:1 country_iso3 weekdate using "$temp/bis_exchangerates_W.dta"
drop if _merge ==2
drop _merge
rename value er
replace fxreserves = fxreserves / er
gen d_fx = .
replace d_fx = fxreserves - fxreserves[_n-1] if _n > 1
keep country_iso3 weekdate d_fx fxreserves year
save "$temp/cbwk_pub_NLD.dta", replace

* BEL — BEF million, gross
use `pub', clear
keep if iso3=="BEL"
gen year = year(date)
gen weekdate = yw(year(date), week(date))
replace weekdate = 641 if date == dmy(28,4,1972)
replace weekdate = 644 if date == dmy(19,5,1972)
replace weekdate = 656 if date == dmy(11,8,1972)
replace weekdate = 699 if date == dmy(8,6,1973)
replace weekdate = 705 if date == dmy(20,7,1973)
replace weekdate = 637 if date == dmy(31,3,1972)
drop if date == dmy(22,12,1972)
drop if date == dmy(20,4,1973)
drop if date == dmy(21,12,1973)
format weekdate %tw
gen country_iso3 = "BEL"
drop if weekdate==.
merge 1:1 country_iso3 weekdate using "$temp/bis_exchangerates_W.dta"
drop if _merge ==2
drop _merge
rename value er
replace fxreserves = fxreserves / er
gen d_fx = .
replace d_fx = fxreserves - fxreserves[_n-1] if _n > 1
keep if year>=1971 & year <= 1973
keep country_iso3 weekdate d_fx fxreserves
save "$temp/cbwk_pub_BEL.dta", replace

* SWE — raw SEK thousand -> /1e3, net at source
use `pub', clear
keep if iso3=="SWE"
gen year = year(date)
gen weekdate = yw(year(date), week(date))
replace weekdate = 674 if date == dmy(23,12,1972)
replace weekdate = 662 if date == dmy(30,9,1972)
format weekdate %tw
replace fxreserves = fxreserves/1e3
gen country_iso3 = "SWE"
drop if weekdate==.
merge 1:1 country_iso3 weekdate using "$temp/bis_exchangerates_W.dta"
drop if _merge ==2
drop _merge
rename value er
replace fxreserves = fxreserves / er
gen d_fx = .
replace d_fx = fxreserves - fxreserves[_n-1] if _n > 1
keep if year>=1971 & year <= 1973
keep country_iso3 weekdate d_fx fxreserves
save "$temp/cbwk_pub_SWE.dta", replace

* CAN — CAD million (assets - liabilities), net
use `pub', clear
keep if iso3=="CAN"
gen year = year(date)
gen weekdate = yw(year(date), week(date))
format weekdate %tw
gen country_iso3 = "CAN"
drop if weekdate==.
merge 1:1 country_iso3 weekdate using "$temp/bis_exchangerates_W.dta"
drop if _merge ==2
drop _merge
rename value er
replace fxreserves = fxreserves / er
gen d_fx = .
replace d_fx = fxreserves - fxreserves[_n-1] if _n > 1
keep if year>=1971 & year <= 1973
keep country_iso3 weekdate d_fx fxreserves
save "$temp/cbwk_pub_CAN.dta", replace

* JPN — raw JPY thousand -> /(1e3*er), gross
use `pub', clear
keep if iso3=="JPN"
gen year = year(date)
gen weekdate = yw(year(date), week(date))
format weekdate %tw
gen country_iso3 = "JPN"
drop if weekdate==.
merge 1:1 country_iso3 weekdate using "$temp/bis_exchangerates_W.dta"
drop if _merge ==2
drop _merge
rename value er
replace fxreserves = fxreserves / (1e3*er)
gen d_fx = .
replace d_fx = fxreserves - fxreserves[_n-1] if _n > 1
keep if year>=1971 & year <= 1973
keep country_iso3 weekdate d_fx fxreserves
save "$temp/cbwk_pub_JPN.dta", replace

* ============================ combine + plot ==================================
use "$temp/cbwk_pub_CHE.dta", clear
append using "$temp/cbwk_pub_FRA.dta"
append using "$temp/cbwk_pub_DEU.dta"
append using "$temp/cbwk_pub_GBR.dta"
append using "$temp/cbwk_pub_NLD.dta"
append using "$temp/cbwk_pub_BEL.dta"
append using "$temp/cbwk_pub_SWE.dta"
append using "$temp/cbwk_pub_CAN.dta"
append using "$temp/cbwk_pub_JPN.dta"
encode country_iso3, gen(country_num)
xtset country_num weekdate
merge m:1 country_iso3 using "$temp/temp_wdigdp.dta"
drop if _merge==2
gen d_fx_usd = d_fx
gen d_fx_gdp = 100*d_fx_usd / (gdp_1971_usd/(1e6))

drop if weekdate > yw(1973,40) | weekdate < yw(1971,1)
drop _merge

merge m:1 country_iso3 weekdate using "$temp/bis_exchangerates_W.dta"
drop if _merge==2
gen er = ln(value)
rename value er_original
label var er "ER (log.)"

levelsof country_iso3, local(ctrylist)
foreach c of local ctrylist {

summarize d_fx_usd if country_iso3 == "`c'"
local y5 = r(max)
local y1 = r(min)
local tempstep = (`y5'-`y1')/4

if `tempstep' > 1100 {
	local step = 2000
}
if `tempstep' <= 1100 & `tempstep' > 600 {
	local step = 1000
}
if `tempstep' <= 600 & `tempstep' > 110 {
	local step = 500
}
if `tempstep' <= 110 & `tempstep' > 40 {
	local step = 100
}
if `tempstep' <= 40 {
	local step = 25
}

local y5 = `step' * ceil(`y5'/`step')
local y1 = `y5' - 4*`step'
local y2 = `y1' + `step'
local y3 = `y1' + 2*`step'
local y4 = `y1' + 3*`step'

sum gdp_1971_usd if country_iso3 == "`c'"
local gdp1971 = `r(mean)'

local deflator = 100/(`gdp1971'/1e6)
local y12 = `y1' * `deflator'
local y22 = `y2' * `deflator'
local y32 = `y3' * `deflator'
local y42 = `y4' * `deflator'
local y52 = `y5' * `deflator'

twoway ///
(line  d_fx_usd weekdate if country_iso3 == "`c'", lwidth(medthick) yaxis(1)) ///
(line  d_fx_gdp  weekdate if country_iso3 == "`c'", lcolor(none) lwidth(medthick) yaxis(2)) ///
(line  er  weekdate if country_iso3 == "`c'", lcolor(red) lwidth(medthick) yaxis(3)), ///
ytitle("% of 1971 GDP", size(small) axis(2)) ///
ytitle("USD M", size(small) axis(1)) ///
ytitle("Exchange Rate (log.)", size(small) axis(3)) ///
legend(order(1 "Change in FX Holdings" 3 "Exchange Rate (LC/USD, log.)" ) size(small) cols(3) pos(6)) ///
yline(0, lpattern(dash) lcolor(gs8) lwidth(medthin)) ///
xline(`$demfloat_week', lpattern(dash) lcolor(gs8)) ///
xline(`$nixonshock_week', lpattern(dash) lcolor(gs4)) ///
xline(`$g10float_week', lpattern(dash) lcolor(gs8)) ///
xlabel(`=yw(1971,1)' `=yw(1972,1)'  `=yw(1973,1)' , labsize(small) format(%twCCYY)) ///
yscale(range(`y1' `y5') axis(1)) ///
yscale(range(`y12' `y52') axis(2)) ///
yscale(alt axis(3)) ///
ylabel(`y1' `y2' `y3' `y4' `y5', axis(1) labsize(small)) ///
ylabel(`y12' `y22' `y32' `y42'  `y52', axis(2) labsize(small) format(%9.1f)) ///
ylabel(, axis(3) labsize(small) ) ///
xtitle("") ///
title("`c'", size(medsmall)) ///
name(Fig_pub_`c', replace)
}

grc1leg ///
Fig_pub_CHE ///
Fig_pub_DEU ///
Fig_pub_FRA ///
Fig_pub_JPN ///
, ///
col(2) legendfrom(Fig_pub_DEU) ///
name(Fig_pub_1, replace)
graph display Fig_pub_1, ysize(6) xsize(9)
graph export "$charts/fig01_cbpurchases.png", replace
graph export "$charts/fig01_cbpurchases.pdf", replace

grc1leg ///
Fig_pub_BEL ///
Fig_pub_CAN ///
Fig_pub_GBR ///
Fig_pub_NLD ///
Fig_pub_SWE ///
, ///
col(2) legendfrom(Fig_pub_BEL) ///
name(Fig_pub_2, replace)
graph display Fig_pub_2, ysize(6) xsize(9)
graph export "$charts/figA1_cbpurchases_2.png", replace
graph export "$charts/figA1_cbpurchases_2.pdf", replace
