*==============================================================================
* figA3_er_blackmarket.do — official vs black-market exchange rates + premium (GFD)
* Input:   $temp/gfd_er.dta (run build/03_gfd_er.do first)
* Output:  $charts/figA3_er_blackmarket.pdf (appendix)
*==============================================================================


global fontsize "small"   // pinned: published figure uses small labels
use "$temp/gfd_er.dta", clear
drop if mdate < ym(1950,1)
drop if mdate > ym(1979,12)
sort mdate

local countries "GBR BEL CAN CHE DEU FRA ITA JPN NLD SWE"

local chartlist ""
foreach c of local countries {
    gen ln`c'    = ln(`c')
    gen ln`c'_BM = ln(`c'_BM)
    gen prem`c'  =  `c'_BM/`c'-1
	local chartlist "`chartlist' FX_`c'"
}

local nixon_shock = tm(1971m8)
foreach c of local countries  {

    twoway ///
        /// official ER (log): solid medium gray
        (line ln`c' mdate, ///
            lwidth(medthick) lcolor(black) lpattern(solid) ///
            yaxis(1)) ///
        /// parallel ER (log): dashed red
        (line ln`c'_BM mdate, ///
            lwidth(medthick) lcolor(red) lpattern(shortdash) ///
            yaxis(1)) ///
        /// premium (difference) as bar on right axis
        (bar prem`c' mdate, ///
            yaxis(2) ///
            barwidth(0.8) fcolor(gs8) lcolor(gs8)), ///
        ///
        ytitle("log ER", axis(1) size(vsmall)) ///
        ytitle("Premium", axis(2) size(vsmall)) ///
        ylabel(, axis(2)) ///
					xlabel(, labsize(small)  format(%tmCCYY)) ///
        xtitle("") ///
        ///
        yline(0, axis(2) lpattern(solid) lcolor(gs8) lwidth(medthick)) ///
	xline(`$goldpoolend_month', lpattern(dash) lcolor(gs4)) ///
	xline(`$demfloat_month', lpattern(dash) lcolor(gs8)) ///
    xline(`$nixonshock_month', lpattern(dash) lcolor(gs4)) ///
	xline(`$g10float_month', lpattern(dash) lcolor(gs8)) ///
    xlabel(, labsize(${fontsize})  format(%tmCCYY) ) ///
        legend(order(1 "Official ER (log)" ///
                     2 "Parallel ER (log)" ///
                     3 "Premium") ///
               pos(6) ring(0) cols(3) size(small)) ///
        ///
        title("`c'", size(medsmall)) ///
        name(FX_`c', replace)
}

grc1leg `chartlist', ///
              col(3) legendfrom(FX_FRA) 
graph display, ysize(9) xsize(9)

graph export "$charts/figA3_er_blackmarket.pdf", replace
graph export "$charts/figA3_er_blackmarket.png", replace
