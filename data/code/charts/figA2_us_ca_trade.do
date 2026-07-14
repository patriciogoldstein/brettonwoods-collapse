* US Trade Balance and Current Account as % of GDP
* Source: FRED (EXPGS, IMPGS, NETFI, GDP) — quarterly, 1960–1975
* Input: $fredsnapshot (frozen FRED pull; see prebuild/freeze_fred.do for vintage)

global fontsize "small"   // pinned: published figure uses small labels
use "$fredsnapshot", clear

* Convert to Stata quarterly date
gen date = qofd(daten)
format date %tq
drop daten

* Compute series
gen trade_balance_gdp = 100 * (EXPGS - IMPGS) / GDP
gen ca_gdp            = 100 * NETFI / GDP

keep if date >= yq(1960,1) & date <= yq(1974,4)

* Event lines (quarterly)
local demfloat_q    = yq(1971,2)
local nixonshock_q  = yq(1971,3)
local g10float_q    = yq(1973,1)

* xlabels
local xlabels "`=yq(1960,1)' `=yq(1965,1)' `=yq(1970,1)' `=yq(1975,1)'"

twoway ///
	(line trade_balance_gdp date, lwidth(medthick) lcolor(navy)) ///
	(line ca_gdp            date, lwidth(medthick) lcolor(cranberry) lpattern(dash)), ///
	legend(order(1 "Trade Balance" 2 "Current Account") size(${fontsize}) cols(2) pos(6)) ///
	yline(0, lpattern(solid) lcolor(black) lwidth(thin)) ///
	xline(`demfloat_q',    lpattern(dash) lcolor(gs8)) ///
	xline(`nixonshock_q',  lpattern(dash) lcolor(gs4)) ///
	xline(`g10float_q',    lpattern(dash) lcolor(gs8)) ///
	ytitle("% of GDP", size(${fontsize})) xtitle("") ///
	xlabel(`xlabels', labsize(${fontsize}) format(%tqCCYY)) ///
	ylabel(, labsize(${fontsize})) ///
	xsize(8) ysize(4)
graph export "$charts/figA2_us_ca_trade.pdf", replace
graph export "$charts/figA2_us_ca_trade.png", replace
