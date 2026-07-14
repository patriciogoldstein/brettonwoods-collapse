*==============================================================================
* fig07_reserves.do — monthly official FX reserves (IMF International Liquidity)
* Input:   $temp/imfreserves_M.dta, $temp/temp_wdigdp.dta
* Output:  $charts/fig07_reserves.pdf (Fig 7)
*==============================================================================

use "$temp/imfreserves_M.dta", clear 
merge m:1 country_iso3 using "$temp/temp_wdigdp.dta", nogenerate
keep if date >= ym(1969,1)
keep if date < ym(1974,1)	
sort country_iso3 date

local reservesvars "reserves_fx reserves_gold reserves_imf reserves_other reserves_sdr reserves_total"
foreach var of local reservesvars {
	gen `var'_gdp = 100*`var'*1e6 / (gdp_1971_usd)
}

global fontsize "small"
global lformat "lwidth(medium)" 
global USAlformat "lwidth(medthick)" 
global chartvar reserves_fx_gdp
twoway ///
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
legend(order(1 "BEL" 2 "CAN" 3 "FRA" 4 "DEU" 5 "ITA" 6 "JPN" 7 "NLD" 8 "CHE" 9 "SWE" 10 "GBR") size(small)  cols(5) pos(6)) ///
ytitle("") ///
title("% of 1971 GDP", size(medium))  xtitle("") ///
xline(`$demfloat_month', lpattern(dash) lcolor(gs8)) ///
xline(`$nixonshock_month', lpattern(dash) lcolor(gs4)) ///
xline(`$g10float_month', lpattern(dash) lcolor(gs8)) ///
xlabel(#6, labsize(${fontsize})  format(%tmCCYY)) ///
ylabel(, labsize(${fontsize}) ) ///
name(Fig_reserves_gdp, replace) 


global chartvar reserves_fx
twoway ///
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
legend(order(1 "BEL" 2 "CAN" 3 "FRA" 4 "DEU" 5 "ITA" 6 "JPN" 7 "NLD" 8 "CHE" 9 "SWE" 10 "GBR") size(small)  cols(5) pos(6) ) ///
ytitle("") ///
title("USD M", size(medium))  xtitle("") ///
xline(`$demfloat_month', lpattern(dash) lcolor(gs8)) ///
xline(`$nixonshock_month', lpattern(dash) lcolor(gs4)) ///
xline(`$g10float_month', lpattern(dash) lcolor(gs8)) ///
xlabel(#6, labsize(${fontsize}) format(%tmCCYY) ) ///
ylabel(, labsize(${fontsize})  format(%9.0fc)) ///
name(Fig_reserves_usd, replace) 


grc1leg ///
		Fig_reserves_usd ///
		Fig_reserves_gdp , ///
        col(2) legendfrom(Fig_reserves_usd) ///
        name(Fig_reserves, replace)
    graph display Fig_reserves, ysize(9) xsize(11)
    graph export "$charts/fig07_reserves.png", replace
    graph export "$charts/fig07_reserves.pdf", replace
