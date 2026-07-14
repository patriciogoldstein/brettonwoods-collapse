*==============================================================================
* fig05_bao.do — US Fed weekly balance sheet (Bao et al. 2018)
* Input:   $raw/bao/bao2018_fed_weekly_balancesheet.xlsx
* Output:  $charts/fig05_fed_balancesheet.pdf (Fig 5), $charts/figA4_us_goldholdings.pdf (appendix)
*          $temp/bao_temp.dta (intermediate)
* Notes:   normalization base = first week with NFA, MB, NDA all available
*          (currently Jan 6, 1954); the y-title picks it up automatically.
*==============================================================================

clear all
set maxvar 8000
import excel "$raw/bao/bao2018_fed_weekly_balancesheet.xlsx", clear 
drop if _n<=7
replace B = B[_n-1] if B == "" & C != ""
replace A = A[_n-1] if A == "" & B != ""
gen varname = A+B+C
drop A-G
drop GYV-GYW
foreach var of varlist H-GYU {
	local val = `var'[1]  
	local year = substr("`val'",6,4)
	rename `var'  value`val'
	if `year' < 1945 | `year' >1980 {
		drop value`val'
	}
}
drop if varname ==""
drop if _n >=162 & _n !=192
drop if _n>=124 & _n <= 144
gen  category = ""
replace category = "Original - Resources / Assets" if _n >=2 & _n <= 87
replace category = "Original - Liabilities" if _n >=88 & _n <= 110
replace category = "Original - Capital Accounts" if _n >=111 & _n <= 123
replace category = "Simplified - Resources / Assets" if _n >=124 & _n <= 132
replace category = "Simplified - Liabilities" if _n >=133 & _n <= 140
replace category = "Other" if _n ==141

reshape long value, i(category varname) j(date) string

drop if category ==""
rename value value_old
gen value = real(value_old)
drop value_old
gen d_date = date(date, "DMY")
format d_date %td
gen w_date = week(d_date)
format w_date %tw
drop date

save "$temp/bao_temp.dta", replace

*

use "$temp/bao_temp.dta", clear
gen short_names = ""
replace short_names = "fed_tbillshort" if  varname == "U.S. Government securities:Bought outright / Securities held outright:U.S. bills [short-term securities]"
replace short_names = "fed_tbillmedium" if varname == "U.S. Government securities:Bought outright / Securities held outright:U.S.Treasury notes [medium-term securities; includes Victory notes starting 1923]"
replace short_names = "fed_tbilllong" if varname == "U.S. Government securities:Bought outright / Securities held outright:U.S. Treasury bonds [long-term securities]"
replace short_names = "fed_creditgov" if  varname == "Credit to federal government"
replace short_names = "fed_creditgovagencies" if  varname == "Credit to federal government agencies"
replace short_names = "fed_debitgov" if  varname == "Owed to federal government"
replace short_names = "fed_creditbanks" if  varname == "Credit to banks and other financial institutions"
replace short_names = "fed_creditprivate" if  varname == "Credit to nonfinancial private sector"
replace short_names = "fed_otherassets" if  varname == "Other or unspecified assets"
replace short_names = "fed_debitbanks" if  varname == "Owed to banks, other than banks' reserve deposits"
replace short_names = "fed_debitunspecified" if  varname == "Other or unspecified liabilities"
replace short_names = "fed_debitnetworth" if  varname == "Net worth: capital, surplus, etc."
replace short_names = "fedsum_assets" if  varname == "ASSETS, million dollars -- simplified"
replace short_names = "fedsum_gold" if  varname == "Gold or gold certificates"
replace short_names = "fedsum_foreignfin" if  varname == "Foreign financial assets"
replace short_names = "fedsum_otherlegaltender" if  varname == "Other legal tender"
replace short_names = "fedsum_liabilities" if  varname == "LIABILITIES, million dollars -- simplified"
replace short_names = "fedsum_foreignliabilities" if  varname == "Foreign liabilities"
replace short_names = "fedsum_mbcurrency" if  varname == "Monetary base: currency: notes (paper money)"
replace short_names = "fedsum_mbdeposits" if  varname == "Monetary base: deposits"
replace short_names = "fedother_goldholdings" if  varname == "Fed holdings of gold (million troy ounces; calclated from balance sheet and official price of gold)"

keep if short_names != ""
drop category varname w_date
reshape wide value, i(d_date) j(short_names) string
rename value* *


gen nfa = fedsum_foreignfin- fedsum_foreignliabilities+ fedsum_gold 
gen mb = fedsum_mbcurrency+fedsum_mbdeposits
gen nda = mb-nfa

gen year = yofd(d_date)
keep if year >=1954
keep if year <=1979

* Base = first observation with all three series available; the y-axis label picks it up automatically
sort d_date
qui sum d_date if !missing(nfa) & !missing(mb) & !missing(nda)
local basedate = r(min)
local basedatelab = trim("`: display %tdMon_dd,_CCYY `basedate''")
di as text "BAO normalization base date: `basedatelab'"
foreach var of varlist nfa mb nda {
	qui sum `var' if d_date == `basedate', meanonly
	gen `var'_norm = ln(`var') - ln(r(mean))
}

tsset d_date
label var nfa_norm "NFA"
label var nda_norm "NDA"
label var mb_norm  "MB"
	
twoway ///
(line nfa_norm d_date , lwidth(medthick)) ///
(line nda_norm d_date,     lwidth(medthick)  lpattern(dash)  ) ///
(line mb_norm  d_date ,  lwidth(medthick) lpattern(shortdash) ), ///
yline(0, lpattern(dash) lcolor(gs8) lwidth(medthin)) ///
legend(size(${fontsize}) cols(3) pos(6) ) ///
ytitle("Log Dif. vs. `basedatelab'", size(${fontsize})) ///
xtitle("") ///
	xline(`${goldpoolend_day}', lpattern(dash) lcolor(gs8)) ///
	    text(1.5 `${goldpoolend_day}' "Gold Pool End", ///
         place(w) size(medium) color(gs8)) ///
	xline(`${demfloat_day}', lpattern(dash) lcolor(gs8)) ///
	text(1.5 `${demfloat_day}' "DEM Float", ///
	place(w) size(medium) color(gs6)) ///
	xline(`$nixonshock_day', lpattern(dash) lcolor(gs4)) ///
	text(1.5 `$nixonshock_day' "Nixon Shock", ///
	place(e) size(medium) color(gs2)) xsize(8) ysize(4) ///
	xline(`${g10float_day}', lpattern(dash) lcolor(gs8)) ///
	text(1.3 `${g10float_day}' "G-10 Float", ///
	place(e) size(medium) color(gs6)) ///
		 xlabel(, labsize(${fontsize})   format(%tdCCYY) ) ///
    ylabel(, labsize(${fontsize}) )
graph export "$charts/fig05_fed_balancesheet.pdf", replace
graph export "$charts/fig05_fed_balancesheet.png", replace

twoway ///
(bar fedother_goldholdings d_date, yaxis(1) barwidth(7) color(gold%40)) ///
(line fedsum_gold d_date, yaxis(2) lwidth(medthick) lcolor(navy)), ///
legend(size(${fontsize}) cols(2) pos(6) label(1 "Gold Volume (M troy oz)") label(2 "Gold Value (RHS, USD M)")  ) ///
ytitle("Gold Value (USD M)", size(${fontsize}) axis(2)) ///
ytitle("Gold Volume (M troy oz)", size(${fontsize}) axis(1)) ///
xtitle("") ///
xline(`${goldpoolend_day}', lpattern(dash) lcolor(gs8)) ///
	    text(550 `${goldpoolend_day}' "Gold Pool End", ///
         place(w) size(medium) color(gs8)) ///
	xline(`${demfloat_day}', lpattern(dash) lcolor(gs8)) ///
	text(550 `${demfloat_day}' "DEM Float", ///
	place(w) size(medium) color(gs6)) ///
	xline(`$nixonshock_day', lpattern(dash) lcolor(gs4)) ///
	text(550 `$nixonshock_day' "Nixon Shock", ///
	place(e) size(medium) color(gs2))  ///
	xline(`${g10float_day}', lpattern(dash) lcolor(gs8)) ///
	text(500 `${g10float_day}' "G-10 Float", ///
	place(e) size(medium) color(gs6)) ///
		 xlabel(, labsize(${fontsize})   format(%tdCCYY) ) ///
    ylabel(, labsize(${fontsize}) )  ///
xsize(8) ysize(4)
graph export "$charts/figA4_us_goldholdings.pdf", replace
graph export "$charts/figA4_us_goldholdings.png", replace
