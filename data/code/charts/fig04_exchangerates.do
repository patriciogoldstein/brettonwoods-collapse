*==============================================================================
* fig04_exchangerates.do — nominal/real exchange rates + crisis-episode zooms (BIS)
* Input:   $temp/bis_exchangerates_{D,M}.dta, $temp/bis_inflation.dta
* Output:  $charts/fig04_exchangerates.pdf (Fig 4),
*          $charts/figA6_real_er.pdf (appendix),
*          $charts/figA5_er_episodes.pdf (appendix)
*==============================================================================

*Charts

global chartvar value
global lformat "lwidth(medium)" 
global minyear 1964
global maxyear 1980
use "$temp/bis_exchangerates_D.dta", clear  
keep if inrange(date, dmy(1,1,${minyear}), dmy(1,1,${maxyear}))
replace value = . if date == dmy(23,8,1971) & country_iso3 == "NLD" // Data error unnatural spike in NLD
gen temp = value if date == dmy(30,4,1971)
egen base = max(temp), by(country_iso3)
replace value = ln(value/base)
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
legend(order(1 "BEL" 2 "CAN" 3 "FRA" 4 "DEU" 5 "ITA" 6 "JPN" 7 "NLD" 8 "CHE" 9 "SWE" 10 "GBR") size(${fontsize}) ) ///
    ytitle("Log Dif. vs. Apr 30 1971, LC/USD", size(${fontsize}) )  xtitle("", size(${fontsize}) ) ///
	xline(`${goldpoolend_day}', lpattern(dash) lcolor(gs4)) ///
	text(-1 `${goldpoolend_day}' "Gold Pool End", ///
	place(w) size(medium) color(gs2)) ///
	xline(`${demfloat_day}', lpattern(dash) lcolor(gs8)) ///
	text(-1 `${demfloat_day}' "DEM Float", ///
	place(w) size(medium) color(gs6)) ///
	xline(`${nixonshock_day}', lpattern(dash) lcolor(gs8)) ///
	text(-1 `${nixonshock_day}' "Nixon Shock", ///
	place(e) size(medium) color(gs6)) xsize(8) ysize(4) ///
	xline(`${g10float_day}', lpattern(dash) lcolor(gs4)) ///
	text(-0.8 `${g10float_day}' "G10 Float", ///
	place(e) size(medium) color(gs2)) ///
    xlabel(, labsize(${fontsize})   format(%tdCCYY) ) ///
    ylabel(, labsize(${fontsize}) )
graph export "$charts/fig04_exchangerates.pdf", replace
graph export "$charts/fig04_exchangerates.png", replace





global lformat "lwidth(medium)" 
global minyear 1964
global maxyear 1980
use "$temp/bis_exchangerates_M.dta", clear  
rename value ner
merge 1:m country_iso3 date using "$temp/bis_inflation.dta"
keep if unit == "Index"
keep if inrange(date, ym(${minyear},1), ym(${maxyear},1))
rename value priceforeign
gen temp = priceforeign if country_iso3 == "USA"
egen pricehome = max(temp), by(date)
gen value = ner*pricehome/priceforeign
drop temp
gen temp = value if date == ym(1971,4)
egen base = max(temp), by(country_iso3)
replace value = ln(value/base)
sort country_iso3 date
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
legend(order(1 "BEL" 2 "CAN" 3 "FRA" 4 "DEU" 5 "ITA" 6 "JPN" 7 "NLD" 8 "CHE" 9 "SWE" 10 "GBR") size(${fontsize}) ) ///
    ytitle("Log Dif. vs. Apr 1971, LC/USD", size(${fontsize}) )  xtitle("", size(${fontsize}) ) ///
	xline(`${goldpoolend_month}', lpattern(dash) lcolor(gs4)) ///
	text(-0.6 `${goldpoolend_month}' "Gold Pool End", ///
	place(w) size(medium) color(gs2)) ///
	xline(`$demfloat_month', lpattern(dash) lcolor(gs8)) ///
	text(-0.6 `$demfloat_month' "DEM Float", ///
	place(w) size(medium) color(gs6)) ///
    xline(`$nixonshock_month', lpattern(dash) lcolor(gs8)) ///
    text(-0.6 `$nixonshock_month' "Nixon Shock", ///
	place(e) size(medium) color(gs6)) xsize(8) ysize(4) ///
	xline(`$g10float_month', lpattern(dash) lcolor(gs4)) ///
	text(-0.8 `$g10float_month' "G-10 Float", ///
	place(e) size(medium) color(gs2)) ///
    xlabel(, labsize(${fontsize})  format(%tmCCYY) ) ///
    ylabel(, labsize(${fontsize}) )
graph export "$charts/figA6_real_er.pdf", replace
graph export "$charts/figA6_real_er.png", replace









global chartvar value
global lformat "lwidth(medium)"
use "$temp/bis_exchangerates_D.dta", clear
replace value = . if date == dmy(23,8,1971) & country_iso3 == "NLD" // Data error unnatural spike in NLD

local d_dem   = `$demfloat_day'    // DEM float
local d_nixon = `$nixonshock_day'   // Nixon shock
local d_smith = `${smithsonian_day}'  // Smithsonian (agreement signed)
local d_g10   = `$g10deval_day'   // G10 deval

global pre  30   // days before
global post 30  // days after

capture program drop _mkpanel
program define _mkpanel
    syntax , event(integer) title(string) name(name)
	preserve
		 local predate = `event' - $pre
		local postdate = `event' + $post
        keep if date >= `predate' & date <= `postdate'
        * base = first available quote in the window (predate itself may be a non-trading day)
        bysort country_iso3 (date): gen double base = value[1]
        replace value = ln(value/base)
        twoway ///
		(line $chartvar date if country_iso3=="BEL", lcolor($BELcolor ) $lformat ) ///
(line $chartvar date if country_iso3=="CAN", lcolor($CANcolor ) $lformat ) ///
(line $chartvar date if country_iso3=="FRA", lcolor($FRAcolor ) $lformat ) ///
(line $chartvar date if country_iso3=="DEU", lcolor($DEUcolor ) $lformat ) ///
(line $chartvar date if country_iso3=="ITA", lcolor($ITAcolor ) $lformat ) ///
(line $chartvar date if country_iso3=="JPN", lcolor($JPNcolor ) $lformat ) ///
(line $chartvar date if country_iso3=="NLD", lcolor($NLDcolor ) $lformat ) ///
(line $chartvar date if country_iso3=="CHE", lcolor($CHEcolor ) $lformat ) ///
(line $chartvar date if country_iso3=="SWE", lcolor($SWEcolor ) $lformat ) ///
(line $chartvar date if country_iso3=="GBR", lcolor($GBRcolor ) $lformat ) ///
            , ///
            ytitle("Log Dif., LC/USD", size(small)) ///
            xtitle("", size(small )) ///
            title("`title'", size(small)) ///
            xline(`event', lpattern(dash) lcolor(gs6)) ///
            xlabel(, labsize(small )) ///
            ylabel(, labsize(small )) ///
            legend( order(1 "BEL" 2 "CAN" 3 "FRA" 4 "DEU" 5 "ITA" 6 "JPN" ///
                      7 "NLD" 8 "CHE" 9 "SWE" 10 "GBR") size(small) row(2) pos(6) ) ///
            name(`name', replace)
			restore
end

_mkpanel, event(`d_dem')   title("DEM Float (May 5, 1971)") name(g_dem) 
_mkpanel, event(`d_nixon') title("Nixon Shock (Aug 15, 1971)")        name(g_nixon) 
_mkpanel, event(`d_smith') title("Smithsonian Agreement (Dec 18, 1971)")        name(g_smith) 
_mkpanel, event(`d_g10')   title("USD/Gold Devaluation (Feb 12, 1973)")          name(g_g10)  


grc1leg ///
g_dem ///
g_nixon ///
g_smith g_g10, ///
col(2) legendfrom(g_dem) ///
name(Fig_ERepisodes, replace)
graph display Fig_ERepisodes, ysize(6) xsize(9)
graph export "$charts/figA5_er_episodes.png", replace
graph export "$charts/figA5_er_episodes.pdf", replace	





