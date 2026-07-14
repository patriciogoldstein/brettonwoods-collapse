*==============================================================================
* fig08_prices.do — CPI inflation and price levels (BIS)
* Input:   $temp/bis_inflation.dta (run build/02_bis_inflation.do first)
* Output:  $charts/fig08_prices.pdf (Fig 8), $charts/figA9_inflation.pdf (appendix)
*==============================================================================

*Charts

global fontsize "small"   // pinned: published figure uses small labels
global chartvar value
global lformat "lwidth(medium)" 
global USAlformat "lwidth(medthick)" 
global minyear 1964
global maxyear 1980
use "$temp/bis_inflation.dta", clear  
keep if unit == "YoY"
keep if inrange(date, ym(${minyear},1), ym(${maxyear},1))
twoway ///
(line $chartvar date if country_iso3 == "USA",   lcolor($USAcolor) $USAlformat ) ///
(line $chartvar date if country_iso3 == "BEL",   lcolor($BELcolor) $lformat ) ///
(line $chartvar date if country_iso3 == "CAN",   lcolor($CANcolor) $lformat ) ///
(line $chartvar date if country_iso3 == "FRA", lcolor($FRAcolor)  $lformat ) ///
(line $chartvar date if country_iso3 == "DEU", lcolor($DEUcolor)  $lformat ) ///
(line $chartvar date if country_iso3 == "ITA", lcolor($ITAcolor)  $lformat ) ///
(line $chartvar date if country_iso3 == "JPN", lcolor($JPNcolor)  $lformat ) ///
(line $chartvar date if country_iso3 == "NLD", lcolor($NLDcolor)  $lformat ) ///
(line $chartvar date if country_iso3 == "CHE", lcolor($CHEcolor)  $lformat ) ///
(line $chartvar date if country_iso3 == "SWE", lcolor($SWEcolor)  $lformat ) ///
(line $chartvar date if country_iso3 == "GBR", lcolor($GBRcolor)  $lformat ) ///
, ///
legend(order(1 "USA" 2 "BEL" 3 "CAN" 4 "FRA" 5 "DEU" 6 "ITA" 7 "JPN" 8 "NLD" 9 "CHE" 10 "SWE" 11 "GBR") size(${fontsize}) ) ///
    ytitle("Inflation (YoY %)", size(${fontsize}))  xtitle("") ///
	xline(`$goldpoolend_month', lpattern(dash) lcolor(gs4)) ///
	text(20 `$goldpoolend_month' "Gold Pool End", ///
	place(w) size(medium) color(gs2)) ///
	xline(`$demfloat_month', lpattern(dash) lcolor(gs8)) ///
	text(1 `$demfloat_month' "DEM Float", ///
	place(w) size(medsmall) color(gs6)) ///
    xline(`$nixonshock_month', lpattern(dash) lcolor(gs4)) ///
    text(1 `$nixonshock_month' "Nixon Shock", ///
	place(e) size(medsmall) color(gs2)) xsize(8) ysize(4) ///
	xline(`$g10float_month', lpattern(dash) lcolor(gs8)) ///
	text(2.5 `$g10float_month' "G-10 Float", ///
	place(e) size(medsmall) color(gs6)) ///
    xlabel(, labsize(${fontsize})  format(%tmCCYY) ) ///
    ylabel(, labsize(${fontsize}) )
graph export "$charts/figA9_inflation.pdf", replace
graph export "$charts/figA9_inflation.png", replace

global lformat "lwidth(medium)" 
global USAlformat "lwidth(medthick)" 
global minyear 1964
global maxyear 1980
use "$temp/bis_inflation.dta", clear  
keep if unit == "Index"
gen temp = value if date == `$g10float_month'
egen base = max(temp), by(country_iso3)
replace value = ln(value) - ln(base)
keep if inrange(date, ym(${minyear},1), ym(${maxyear},1))
twoway ///
(line $chartvar date if country_iso3 == "USA",   lcolor($USAcolor) $USAlformat ) ///
(line $chartvar date if country_iso3 == "BEL",   lcolor($BELcolor) $lformat ) ///
(line $chartvar date if country_iso3 == "CAN",   lcolor($CANcolor) $lformat ) ///
(line $chartvar date if country_iso3 == "FRA", lcolor($FRAcolor)  $lformat ) ///
(line $chartvar date if country_iso3 == "DEU", lcolor($DEUcolor)  $lformat ) ///
(line $chartvar date if country_iso3 == "ITA", lcolor($ITAcolor)  $lformat ) ///
(line $chartvar date if country_iso3 == "JPN", lcolor($JPNcolor)  $lformat ) ///
(line $chartvar date if country_iso3 == "NLD", lcolor($NLDcolor)  $lformat ) ///
(line $chartvar date if country_iso3 == "CHE", lcolor($CHEcolor)  $lformat ) ///
(line $chartvar date if country_iso3 == "SWE", lcolor($SWEcolor)  $lformat ) ///
(line $chartvar date if country_iso3 == "GBR", lcolor($GBRcolor)  $lformat ) ///
, ///
legend(order(1 "USA" 2 "BEL" 3 "CAN" 4 "FRA" 5 "DEU" 6 "ITA" 7 "JPN" 8 "NLD" 9 "CHE" 10 "SWE" 11 "GBR") size(${fontsize}) ) ///
    ytitle("Inflation (YoY %)", size(${fontsize}))  xtitle("") ///
    ytitle("Log Dif. vs. Mar 1973", size(${fontsize}))  xtitle("") ///
	xline(`$goldpoolend_month', lpattern(dash) lcolor(gs4)) ///
	text(0.7 `$goldpoolend_month' "Gold Pool End", ///
	place(w) size(medium) color(gs2)) ///
	xline(`$demfloat_month', lpattern(dash) lcolor(gs8)) ///
	text(.7 `$demfloat_month' "DEM Float", ///
	place(w) size(medsmall) color(gs6)) ///
    xline(`$nixonshock_month', lpattern(dash) lcolor(gs4)) ///
    text(.7 `$nixonshock_month' "Nixon Shock", ///
	place(e) size(medsmall) color(gs2)) xsize(8) ysize(4) ///
	xline(`$g10float_month', lpattern(dash) lcolor(gs8)) ///
	text(.6 `$g10float_month' "G-10 Float", ///
	place(e) size(medsmall) color(gs6)) ///
    xlabel(, labsize(${fontsize})  format(%tmCCYY) ) ///
    ylabel(, labsize(${fontsize}) )
graph export "$charts/fig08_prices.pdf", replace
graph export "$charts/fig08_prices.png", replace


