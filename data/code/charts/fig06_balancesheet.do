*==============================================================================
* fig06_balancesheet.do — G-10 central-bank balance sheets, change vs 1969 (IMF MFS)
* Input:   $temp/mfs_cbs_{M,Q}.dta, $temp/temp_wdigdp{,_all}.dta
* Output:  $charts/fig06_balancesheet.pdf (Fig 6), figA8_balancesheet_2.pdf (appendix),
*          figA7_balancesheet_time.pdf (appendix), {fig06_balancesheet,figA8_balancesheet_2}_2x3.pdf (slides)
* Notes:   GBR enters at quarterly frequency, everyone else monthly.
*==============================================================================

global baseyear 1969
global endyear 1975

local freqs "M Q"

foreach f of local freqs {
	use "$temp/mfs_cbs_`f'.dta", clear
	merge m:1 country_iso3 using "$temp/temp_wdigdp.dta", nogenerate
	merge m:1 country_iso3 year using "$temp/temp_wdigdp_all.dta"
	drop if _merge==2
	
	gen keepcountry =1 if inlist(country_iso3, "FRA","DEU","ITA","USA","GBR","BEL")
	replace keepcountry =1 if inlist(country_iso3, "JPN","SWE","CAN","CHE","NLD")
	keep if keepcountry == 1

	drop if country_iso3 == "CHE" &year < 1963 // bad data
	drop if country_iso3 == "DEU" &year < 1968 // bad data
	drop if country_iso3 == "FRA" &year < 1963 // bad data
	drop if country_iso3 == "JPN" &year < 1965 // bad data
	drop if country_iso3 == "NLD" &year < 1960 // bad data
	drop if country_iso3 == "USA" &year < 1960 // bad data
	drop if country_iso3 == "GBR" &year < 1960 // bad data
	drop if country_iso3 == "BEL" &year < 1968 // bad data: currency-only RM before 1968, bankers' deposits appear 1968m1 (spurious break)
	drop if country_iso3 == "SWE" &year < 1964 // bad data
	drop if country_iso3 == "CAN" &year < 1960 // bad data
	drop if country_iso3 == "ITA" &year < 1962 // bad data

    if "`f'" == "Q" {
        keep if date >= yq(${baseyear},1)
		keep if date <= yq(${endyear},1)
		gen str20 datelab = string(date, "%tq")
		local totalfreq = 4
		local freqname "quarter"
    }
    else if "`f'" == "M" {
        keep if date >= ym(${baseyear},1)
		keep if date <= ym(${endyear},1)
		gen str20 datelab = string(date, "%tm")
		local totalfreq = 12
		local freqname = "month"
    }
	
	egen country_iso3_num = group(country_iso3)
	xtset country_iso3_num date
    sort country_iso3_num date
	
	gen gdp_lcu_m       = ln(gdp_lcu)
	replace gdp_lcu_m = . if `freqname' !=1
	bysort country_iso3_num (date): ipolate gdp_lcu_m date, gen(gdp_lcu_ipol)
	replace gdp_lcu_ipol = exp(gdp_lcu_ipol)
	keep if _merge == 3
	drop _merge
	
	drop nda_usd
	gen nda_usd = rm_usd -nfa_usd
	drop nda
	gen nda = rm- nfa

	local bsvars "rm nda nfa"
	foreach var of local bsvars {
	
	replace `var' = `var' / 1e6
	replace `var'_usd = `var'_usd / 1e6
		
    bysort country_iso3_num (date): gen base_`var'_usd = `var'_usd[1]
    bysort country_iso3: replace base_`var'_usd = base_`var'_usd[1]
	bysort country_iso3_num (date): gen base_`var'_gdp = `var'[1] / (gdp_lcu_ipol[1] /1e6)
    bysort country_iso3: replace  base_`var'_gdp  =  base_`var'_gdp[1]
	
	gen `var'_changeusd =  ((`var'_usd)- (base_`var'_usd))/1e3
	gen `var'_changegdp =  100*( (`var'_usd)- (base_`var'_usd) ) / (gdp_1971_usd/1e6)
	gen `var'_changegdptime =  100*( `var'  / (gdp_lcu_ipol /1e6) - base_`var'_gdp)

	}

	if "`f'" == "Q" keep if date < yq(${endyear},1)
	else if "`f'" == "M" keep if date < ym(${endyear},1)

    if "`f'" == "Q" {
	local ctrylist "GBR"
	format date %tq
	local xlabelformat "format(%tqCCYY)"
	local xlabels "`=yq(1969,1)' `=yq(1971,1)' `=yq(1973,1)' `=yq(1975,1)'"
	local DEMfloat = yq(1971,2)
	local nixonshock = yq(1971,3)
	local G10float = yq(1973,1)
	}
    else if "`f'" == "M" {
	local ctrylist "USA FRA JPN DEU NLD CHE CAN ITA BEL SWE"
	format date %tm
	local xlabelformat "format(%tmCCYY)"
	local xlabels "`=ym(1969,1)' `=ym(1971,1)' `=ym(1973,1)' `=ym(1975,1)'"
	local DEMfloat = `$demfloat_month'
	local nixonshock = `$nixonshock_month'
	local G10float = `$g10float_month'
    }

    foreach c of local ctrylist {
			
		label var nfa_changegdp "NFA"
		label var nda_changegdp "NDA"
		label var rm_changegdp  "MB"
			
		summarize nfa_changeusd if country_iso3 == "`c'", meanonly
		local max1 = r(max)
		local min1 = r(min)
		summarize nda_changeusd if country_iso3 == "`c'", meanonly
		local max2 = r(max)
		local min2 = r(min)
		summarize rm_changeusd if country_iso3 == "`c'", meanonly
		local max3 = r(max)
		local min3 = r(min)
		local y5 = max(`max1', `max2', `max3')
		local y1 = min(`min1', `min2' , `min3')
		local tempstep = (`y5'-`y1')/4
		
		if `tempstep' > 6 {
			local step = 10
		}

		if `tempstep' <= 6 & `tempstep' > 3 {
			local step = 5
		}

		if `tempstep' <= 3 & `tempstep' > 1.5 {
			local step = 2
		}

		if `tempstep' <= 1.5 & `tempstep' > 0.8 {
			local step = 1
		}
			if `tempstep' <= 0.8 {
			local step = 0.5
		}

		local y5 = `step' * ceil(`y5'/`step')
        local y1 = `y5' - 4*`step'
		local y2 = `y1' + `step' 
		local y3 = `y1' + 2*`step' 
		local y4 = `y1' + 3*`step' 
		
		sum gdp_1971_usd if country_iso3 == "`c'"
		local gdp1971 = `r(mean)'
		local deflator = 100*1e9/(`gdp1971')  // % x  Billions to usd / usd 
		local y12 = `y1' * `deflator'
		local y22 = `y2' * `deflator'
		local y32 = `y3' * `deflator'
		local y42 = `y4' * `deflator'
		local y52 = `y5' * `deflator'


		twoway ///
		(line nfa_changeusd date if country_iso3 == "`c'", lwidth(medthick) yaxis(1)) ///
		(line nda_changeusd date if country_iso3 == "`c'", lpattern(dash)     lwidth(medthick) yaxis(1)) ///
		(line rm_changeusd  date if country_iso3 == "`c'", lpattern(shortdash) lwidth(medthick) yaxis(1))  ///
		(line nfa_changegdp date if country_iso3 == "`c'", lcolor(none) lwidth(medthick) yaxis(2)) ///
		(line nda_changegdp date if country_iso3 == "`c'", lcolor(none) lpattern(dash)     lwidth(medthick) yaxis(2)) ///
		(line rm_changegdp date if country_iso3 == "`c'",  lcolor(none) lpattern(shortdash) lwidth(medthick) yaxis(2)) , ///
		legend(order(1 "NFA" 2 "NDA" 3 "MB") size(small) cols(3) pos(6)) ///
		yline(0, lpattern(dash) lcolor(gs8) lwidth(medthin)) ///
		xline(`DEMfloat', lpattern(dash) lcolor(gs8)) ///
		xline(`nixonshock', lpattern(dash) lcolor(gs4)) ///
		xline(`G10float', lpattern(dash) lcolor(gs8)) ///
		yscale(range(`y1' `y5') axis(1)) ///
		yscale(range(`y12' `y52') axis(2)) ///
		ylabel(`y1' `y2' `y3' `y4' `y5', axis(1) labsize(small)) ///
		ylabel(`y12' `y22' `y32' `y42'  `y52', axis(2) labsize(small) format(%9.1f)) ///
		legend(size(small) cols(3) pos(6)) ///
		ytitle("% of 1971 GDP", size(small) axis(2)) ///
		ytitle("USD Bn", size(small) axis(1)) ///
		xtitle("") ///
		title("`c'", size(medsmall)) ///
		xlabel(`xlabels', labsize(small) angle(45) `xlabelformat') ///
		name(Fig_BS_`c'_`f'_changegdp, replace) 
		
		twoway ///
        (line nfa_changegdptime date if country_iso3 == "`c'", lwidth(medthick)) ///
        (line nda_changegdptime date if country_iso3 == "`c'", lpattern(dash) lwidth(medthick)) ///
        (line rm_changegdptime date if country_iso3 == "`c'", lpattern(shortdash) lwidth(medthick)), ///
        legend(order(1 "NFA" 2 "NDA" 3 "MB") size(small) cols(3) pos(6)) ///
        yline(0, lpattern(dash) lcolor(gs8) lwidth(medthin)) ///
        xline(`DEMfloat', lpattern(dash) lcolor(gs8)) ///
        xline(`nixonshock', lpattern(dash) lcolor(gs4)) ///
        xline(`G10float', lpattern(dash) lcolor(gs8)) ///
        ylabel(, labsize(small) format(%9.1f)) ///
        ytitle("% of GDP", size(small)) ///
        xtitle("") ///
        title("`c'", size(medsmall)) ///
        xlabel(`xlabels', labsize(small) angle(45) `xlabelformat') ///
        name(Fig_BS_time_`c'_`f'_changegdptime, replace)
		
    }
	
}



    grc1leg ///
        Fig_BS_USA_M_changegdp ///
        Fig_BS_FRA_M_changegdp ///
        Fig_BS_DEU_M_changegdp ///
        Fig_BS_JPN_M_changegdp ///
        Fig_BS_CHE_M_changegdp ///
        Fig_BS_GBR_Q_changegdp, ///
        col(2) legendfrom(Fig_BS_USA_M_changegdp) ///
        name(Fig_BS_all_changegdp, replace)
    graph display Fig_BS_all_changegdp, ysize(9) xsize(9)
    graph export "$charts/fig06_balancesheet.png", replace
    graph export "$charts/fig06_balancesheet.pdf", replace
	
	
    grc1leg ///
        Fig_BS_USA_M_changegdp ///
        Fig_BS_FRA_M_changegdp ///
        Fig_BS_DEU_M_changegdp ///
        Fig_BS_JPN_M_changegdp ///
        Fig_BS_CHE_M_changegdp ///
        Fig_BS_GBR_Q_changegdp, ///
        col(3) legendfrom(Fig_BS_USA_M_changegdp) ///
        name(Fig_BS_all_changegdp, replace)
    graph display Fig_BS_all_changegdp, ysize(9) xsize(14)
    graph export "$charts/fig06_balancesheet_2x3.png", replace
    graph export "$charts/fig06_balancesheet_2x3.pdf", replace


	grc1leg ///
		Fig_BS_BEL_M_changegdp ///
		Fig_BS_CAN_M_changegdp ///
        Fig_BS_ITA_M_changegdp ///
		Fig_BS_NLD_M_changegdp ///
		Fig_BS_SWE_M_changegdp, ///
        col(2) legendfrom(Fig_BS_BEL_M_changegdp) ///
        name(Fig_BS_all_changegdp_2, replace)
    graph display Fig_BS_all_changegdp_2, ysize(9) xsize(9)
    graph export "$charts/figA8_balancesheet_2.png", replace
    graph export "$charts/figA8_balancesheet_2.pdf", replace
	
		grc1leg ///
		Fig_BS_BEL_M_changegdp ///
		Fig_BS_CAN_M_changegdp ///
        Fig_BS_ITA_M_changegdp ///
		Fig_BS_NLD_M_changegdp ///
		Fig_BS_SWE_M_changegdp, ///
        col(3) legendfrom(Fig_BS_BEL_M_changegdp) ///
        name(Fig_BS_all_changegdp_2, replace)
    graph display Fig_BS_all_changegdp_2, ysize(9) xsize(14)
    graph export "$charts/figA8_balancesheet_2_2x3.png", replace
    graph export "$charts/figA8_balancesheet_2_2x3.pdf", replace



grc1leg ///
    Fig_BS_time_USA_M_changegdptime ///
    Fig_BS_time_FRA_M_changegdptime ///
    Fig_BS_time_DEU_M_changegdptime ///
    Fig_BS_time_JPN_M_changegdptime ///
    Fig_BS_time_CHE_M_changegdptime ///
    Fig_BS_time_GBR_Q_changegdptime ///
	    Fig_BS_time_BEL_M_changegdptime ///
    Fig_BS_time_CAN_M_changegdptime ///
    Fig_BS_time_ITA_M_changegdptime ///
    Fig_BS_time_NLD_M_changegdptime ///
    Fig_BS_time_SWE_M_changegdptime , ///
    col(3) legendfrom(Fig_BS_time_USA_M_changegdptime) ///
    name(Fig_BS_time_all_1, replace)
graph display Fig_BS_time_all_1, ysize(9) xsize(9)
graph export "$charts/figA7_balancesheet_time.png", replace
graph export "$charts/figA7_balancesheet_time.pdf", replace

