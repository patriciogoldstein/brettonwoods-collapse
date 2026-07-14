*==============================================================================
* tab01_nda_growth.do — Table 1: NDA trend growth, 1964-73 / 1968-73 (IMF MFS)
* Input:   $temp/mfs_cbs_{M,Q}.dta, $temp/temp_wdigdp_all.dta
* Output:  $charts/tab01_nda_growth.tex (Table 1),
*          $charts/tab01_nda_growth_slides.tex (compact slides version)
* Notes:   USA row: Newey-West SEs. Other rows: Driscoll-Kraay (xtscc) pooled
*          two-country regressions vs USA; stars are ONE-SIDED (growth > USA).
*          GBR estimated at quarterly frequency, others monthly.
*          CHE/NLD excluded (negative NDA levels; see paper fn).
*==============================================================================

local freqs M Q

foreach freq of local freqs{
	
if "`freq'" == "M" {
	local totalfreq = 12
	local freqname "month"
}
else if "`freq'" == "Q" {
	local totalfreq = 4
	local freqname "quarter"
}	
	
use "$temp/mfs_cbs_`freq'.dta", clear
gen keepcountry =1 if inlist(country_iso3, "FRA","DEU","ITA","USA","GBR","BEL")
replace keepcountry =1 if inlist(country_iso3, "JPN","SWE","CAN")
keep if keepcountry == 1
drop keepcountry

drop if country_iso3 == "DEU" &year < 1968 // bad data
drop if country_iso3 == "FRA" &year < 1963 // bad data
drop if country_iso3 == "JPN" &year < 1965 // bad data
drop if country_iso3 == "USA" &year < 1960 // bad data
drop if country_iso3 == "GBR" &year < 1960 // bad data
drop if country_iso3 == "BEL" &year < 1968 // bad data: currency-only RM before 1968, bankers' deposits appear 1968m1 (spurious break)
drop if country_iso3 == "SWE" &year < 1964 // bad data
drop if country_iso3 == "CAN" &year < 1960 // bad data
drop if country_iso3 == "ITA" &year < 1962 // bad data

egen country_iso3_num = group(country_iso3)
xtset country_iso3_num date  
merge m:1 country_iso3 year using "$temp/temp_wdigdp_all.dta"
drop if _merge==2
keep if year >= 1959 & year <= 1979

gen gdp_lcuconstant_m       = ln(gdp_lcuconstant)
replace gdp_lcuconstant_m = . if month(dofm(date)) != 12
bysort country_iso3_num (date): ipolate gdp_lcuconstant_m date, gen(gdp_lcuconstant_ipol)
replace gdp_lcuconstant_ipol = exp(gdp_lcuconstant_ipol)
keep if _merge == 3
drop _merge
gen gdp_lcu_log     = ln(gdp_lcuconstant_ipol)
drop nda
gen nda       = rm - nfa
gen nda_log   = ln(nda)
gen nda_gdpratio  = nda / gdp_lcuconstant_ipol
gen nda_gdpratio_log     = ln(nda_gdpratio)
bysort country_iso3 (date): gen t = _n

tempname mem
local regvars nda_log  nda_gdpratio_log
local yeargroups "6473 6873"

// Pre-compute annual GDP growth rates per country x yeargroup
// Uses annual gdp_lcuconstant (same for all months within a year after merge)
foreach yeargroup of local yeargroups {
	local yeargroupstart = floor(`yeargroup'/100)
	local yeargroupend   = mod(`yeargroup', 100)
	levelsof country_iso3, local(ctrylist_gdp)
	foreach c of local ctrylist_gdp {
		// Use first year actually available for this country in the window
		qui sum year if country_iso3 == "`c'" & inrange(year, 19`yeargroupstart', 19`yeargroupend'), meanonly
		if r(N) == 0 {
			local gdpgr_`c'_`yeargroup' = .
			continue
		}
		local actual_start = r(min)
		qui sum gdp_lcuconstant if country_iso3 == "`c'" & year == `actual_start', meanonly
		local gdp_s = cond(r(N) > 0 & r(mean) > 0, r(mean), .)
		qui sum gdp_lcuconstant if country_iso3 == "`c'" & year == 19`yeargroupend', meanonly
		local gdp_e = cond(r(N) > 0 & r(mean) > 0, r(mean), .)
		if "`gdp_s'" != "." & "`gdp_e'" != "." {
			local nyears = 19`yeargroupend' - `actual_start'
			local gdpgr_`c'_`yeargroup' = (ln(`gdp_e') - ln(`gdp_s')) / `nyears'
		}
		else {
			local gdpgr_`c'_`yeargroup' = .
		}
	}
}

// Build postfile variable list
local postfilevars ""
local postfilecoefs ""
foreach yeargroup of local yeargroups {
	foreach regvar of local regvars {
		local yeargroupstart = floor(`yeargroup'/100)
		local yeargroupend = mod(`yeargroup',100)
		// Individual country estimates
		local postfilevars "`postfilevars' b_`regvar'_`yeargroupstart'`yeargroupend' se_`regvar'_`yeargroupstart'`yeargroupend'"
		local postfilecoefs "`postfilecoefs' (b_`regvar'_`yeargroupstart'`yeargroupend') (se_`regvar'_`yeargroupstart'`yeargroupend')"
		// Difference from USA
		local postfilevars "`postfilevars' diff_`regvar'_`yeargroupstart'`yeargroupend' se_diff_`regvar'_`yeargroupstart'`yeargroupend'"
		local postfilecoefs "`postfilecoefs' (diff_`regvar'_`yeargroupstart'`yeargroupend') (se_diff_`regvar'_`yeargroupstart'`yeargroupend')"
	}
}

	// Add nda_log_adj (GDP-growth-adjusted NDA growth) to postfile
	foreach yeargroup of local yeargroups {
		local yeargroupstart = floor(`yeargroup'/100)
		local yeargroupend   = mod(`yeargroup', 100)
		local postfilevars "`postfilevars' b_nda_log_adj_`yeargroupstart'`yeargroupend' se_nda_log_adj_`yeargroupstart'`yeargroupend'"
		local postfilecoefs "`postfilecoefs' (b_nda_log_adj_`yeargroupstart'`yeargroupend') (se_nda_log_adj_`yeargroupstart'`yeargroupend')"
		local postfilevars "`postfilevars' diff_nda_log_adj_`yeargroupstart'`yeargroupend' se_diff_nda_log_adj_`yeargroupstart'`yeargroupend'"
		local postfilecoefs "`postfilecoefs' (diff_nda_log_adj_`yeargroupstart'`yeargroupend') (se_diff_nda_log_adj_`yeargroupstart'`yeargroupend')"
	}

postfile `mem' str3 country_iso3 `postfilevars'  using "$temp/nda_trend_table_`freq'.dta", replace

levelsof country_iso3, local(ctrylist)
local minyeargroupstart 2000

foreach c of local ctrylist {
	
	foreach yeargroup of local yeargroups {
		local yeargroupstart = floor(`yeargroup'/100)
		local yeargroupend = mod(`yeargroup',100)
		
		foreach regvar of local regvars {
			
			// Check for missing or non-positive values
			if inlist("`regvar'","nda_log","nda_gdpratio_log") {
				summarize nda if country_iso3 == "`c'" ///
					& inrange(year, 19`yeargroupstart', 19`yeargroupend')
				if (r(N) == 0 | r(min) <= 0) {
					scalar b_`regvar'_`yeargroupstart'`yeargroupend' = .
					scalar se_`regvar'_`yeargroupstart'`yeargroupend' = .
					scalar diff_`regvar'_`yeargroupstart'`yeargroupend' = .
					scalar se_diff_`regvar'_`yeargroupstart'`yeargroupend' = .
					continue
				}
			}
			
			// Estimate individual country growth with Newey-West
			if "`c'" == "USA" {
			preserve				
			keep if country_iso3 == "`c'"
			keep if inrange(year, 19`yeargroupstart', 19`yeargroupend')
			sort country_iso3_num date
			sum year
			local count = r(N)
			local customlag = floor(4*(`count'/100)^(2/9))
			qui newey `regvar' t if inrange(year, 19`yeargroupstart', 19`yeargroupend'), lag(`customlag')
			scalar b_`regvar'_`yeargroupstart'`yeargroupend' = `totalfreq' * _b[t]
			scalar se_`regvar'_`yeargroupstart'`yeargroupend' = `totalfreq' * _se[t]
			scalar diff_`regvar'_`yeargroupstart'`yeargroupend' = 0
			scalar se_diff_`regvar'_`yeargroupstart'`yeargroupend' = 0
			restore
			}
			
			// Estimate difference from USA with Newey-West (accounting for covariance)
			if "`c'" != "USA" {
				preserve
				
				// Keep only USA and current country
				keep if country_iso3 == "USA" | country_iso3 == "`c'"
				keep if inrange(year, 19`yeargroupstart', 19`yeargroupend')
				
				// Create interaction term
				gen usa_dummy = (country_iso3 == "USA")
				gen t_x_usa = t * usa_dummy
				
				// Run pooled Newey-West regression
				// Coefficient on t_x_usa is (USA growth - country growth)
				sort country_iso3_num date
				qui xtscc `regvar' t t_x_usa usa_dummy if inrange(year, 19`yeargroupstart', 19`yeargroupend')
				scalar b_`regvar'_`yeargroupstart'`yeargroupend' = `totalfreq' * _b[t]
				scalar se_`regvar'_`yeargroupstart'`yeargroupend' = `totalfreq' * _se[t]
				scalar diff_`regvar'_`yeargroupstart'`yeargroupend' = `totalfreq' * _b[t_x_usa]
				scalar se_diff_`regvar'_`yeargroupstart'`yeargroupend' = `totalfreq' * _se[t_x_usa]
				
				restore
			}
		}
		local minyeargroupstart = min(`minyeargroupstart', 19`yeargroupstart')
	}
	
	// Compute GDP-adjusted NDA growth: nda_log trend minus annual GDP growth rate
	foreach yeargroup of local yeargroups {
		local yeargroupstart = floor(`yeargroup'/100)
		local yeargroupend   = mod(`yeargroup', 100)
		local g_c   = `gdpgr_`c'_`yeargroup''
		local g_usa = `gdpgr_USA_`yeargroup''
		scalar b_nda_log_adj_`yeargroupstart'`yeargroupend'  = scalar(b_nda_log_`yeargroupstart'`yeargroupend') - `g_c'
		scalar se_nda_log_adj_`yeargroupstart'`yeargroupend' = scalar(se_nda_log_`yeargroupstart'`yeargroupend')
		if "`c'" == "USA" {
			scalar diff_nda_log_adj_`yeargroupstart'`yeargroupend'    = 0
			scalar se_diff_nda_log_adj_`yeargroupstart'`yeargroupend' = 0
		}
		else {
			scalar diff_nda_log_adj_`yeargroupstart'`yeargroupend'    = scalar(diff_nda_log_`yeargroupstart'`yeargroupend') - (`g_usa' - `g_c')
			scalar se_diff_nda_log_adj_`yeargroupstart'`yeargroupend' = scalar(se_diff_nda_log_`yeargroupstart'`yeargroupend')
		}
	}

	// Post results for this country
	post `mem' ("`c'") `postfilecoefs' 
	
	// Store minimum year for this country
	qui sum year if country_iso3 == "`c'"
	local year_`c' = r(min)
	local year_`c' = max(`year_`c'',`minyeargroupstart')
}

postclose `mem'

// ============================================================================
// Create formatted table
// ============================================================================

use "$temp/nda_trend_table_`freq'.dta", clear

local t10 = invnormal(0.90)   // 10% (one-sided)
local t5  = invnormal(0.95)   // 5% (one-sided)
local t1  = invnormal(0.99)   // 1% (one-sided)

gen year = .
foreach c of local ctrylist {
	replace year = `year_`c'' if country_iso3 == "`c'"
}

foreach yeargroup of local yeargroups {
	foreach regvar of local regvars {
		
		// Calculate t-statistic using the proper SE from difference regression
		gen t_`regvar'_`yeargroup' = diff_`regvar'_`yeargroup' / se_diff_`regvar'_`yeargroup'
		
		// One-sided significance stars (H1: growth faster than USA)
		gen `regvar'_`yeargroup'_star = ///
			cond(t_`regvar'_`yeargroup' > `t1',  "***", ///
			cond(t_`regvar'_`yeargroup' > `t5',  "**", ///
			cond(t_`regvar'_`yeargroup' > `t10', "*", "")))
		
		// Format 1: Show individual country coefficient with Newey-West SE
		gen `regvar'_`yeargroup'_fmt = ///
			string(b_`regvar'_`yeargroup', "%6.4f") + `regvar'_`yeargroup'_star ///
			+ " \\ " ///
			+ "(" + string(t_`regvar'_`yeargroup', "%6.2f") + ")"
		replace `regvar'_`yeargroup'_fmt = ///
			string(b_`regvar'_`yeargroup', "%6.4f") + `regvar'_`yeargroup'_star ///
			+ " \\ " + "(" + string(se_`regvar'_`yeargroup', "%6.4f") + ")" ///
			if country_iso3 == "USA"
		replace `regvar'_`yeargroup'_fmt = "" if `regvar'_`yeargroup'_fmt == ".*** \\ (.)"
		
		// Format 2: Show difference from USA with proper SE of difference
		gen `regvar'_`yeargroup'_fmt_2 = ///
			string(diff_`regvar'_`yeargroup', "%6.4f") + `regvar'_`yeargroup'_star ///
			+ " \\ " ///
			+ "(" + string(se_diff_`regvar'_`yeargroup', "%6.4f") + ")"
		replace `regvar'_`yeargroup'_fmt_2 = "" if `regvar'_`yeargroup'_fmt_2 == ".*** \\ (.)"
		
		// Clean up
		drop t_`regvar'_`yeargroup' b_`regvar'_`yeargroup' diff_`regvar'_`yeargroup' 
		drop se_`regvar'_`yeargroup' se_diff_`regvar'_`yeargroup'
	}
}

	// Format nda_log_adj column
	foreach yeargroup of local yeargroups {
		local yeargroupstart = floor(`yeargroup'/100)
		local yeargroupend   = mod(`yeargroup', 100)
		local yg `yeargroupstart'`yeargroupend'
		gen t_adj_`yg' = diff_nda_log_adj_`yg' / se_diff_nda_log_adj_`yg'
		gen nda_log_adj_`yg'_star = ///
			cond(t_adj_`yg' > `t1',  "***", ///
			cond(t_adj_`yg' > `t5',  "**",  ///
			cond(t_adj_`yg' > `t10', "*", "")))
		gen nda_log_adj_`yg'_fmt = ///
			string(b_nda_log_adj_`yg', "%6.4f") + nda_log_adj_`yg'_star ///
			+ " \\ " ///
			+ "(" + string(t_adj_`yg', "%6.2f") + ")"
		replace nda_log_adj_`yg'_fmt = ///
			string(b_nda_log_adj_`yg', "%6.4f") + nda_log_adj_`yg'_star ///
			+ " \\ " + "(" + string(se_nda_log_adj_`yg', "%6.4f") + ")" ///
			if country_iso3 == "USA"
		replace nda_log_adj_`yg'_fmt = "" if nda_log_adj_`yg'_fmt == ".*** \\ (.)"
		gen nda_log_adj_`yg'_fmt_2 = ///
			string(diff_nda_log_adj_`yg', "%6.4f") + nda_log_adj_`yg'_star ///
			+ " \\ " ///
			+ "(" + string(se_diff_nda_log_adj_`yg', "%6.4f") + ")"
		replace nda_log_adj_`yg'_fmt_2 = "" if nda_log_adj_`yg'_fmt_2 == ".*** \\ (.)"
		drop t_adj_`yg' b_nda_log_adj_`yg' diff_nda_log_adj_`yg'
		drop se_nda_log_adj_`yg' se_diff_nda_log_adj_`yg'
	}

save "$temp/nda_trend_table_`freq'.dta", replace

}

* ============================================================================
* Create LaTeX Table
* ============================================================================

use "$temp/nda_trend_table_Q.dta" , clear

keep if country_iso3 == "GBR"
append using  "$temp/nda_trend_table_M.dta", gen(monthly)
drop if  country_iso3 == "GBR" & monthly == 1
drop monthly
sort country_iso3
levelsof country_iso3, local(ctrylist)

* Two versions from the same estimates: the paper table (coefficient with
* t-stat/SE stacked via \makecell) and a compact slides table (coefficient +
* stars only, one line per country)
file open fh using "$charts/tab01_nda_growth.tex", write replace
file open fs using "$charts/tab01_nda_growth_slides.tex", write replace

foreach h in fh fs {
    file write `h' "\begin{tabular}{llcccc}" _n
    file write `h' "\toprule" _n
    file write `h' " & & \multicolumn{2}{c}{1964--1973} & \multicolumn{2}{c}{1968--1973} \\" _n
    file write `h' " & Min. Year & NDA (log) & Growth-Adjusted & NDA (log) & Growth-Adjusted \\" _n
    file write `h' "\midrule" _n
}

foreach c of local ctrylist {

    preserve
    keep if country_iso3 == "`c'"

	local year0 = year[1]

    * Take the first (and only) row for that country
	local a1 = nda_log_6473_fmt[1]
    local a2 = nda_log_adj_6473_fmt[1]
	local b1 = nda_log_6873_fmt[1]
    local b2 = nda_log_adj_6873_fmt[1]

    * Strip any double quotes that might be inside
    foreach v in  a1 a2 b1 b2 {
        local `v' : subinstr local `v' `"""' "", all
    }

    * Slides cells: coefficient + stars only (drop the " \\ (t)" tail)
    foreach v in a1 a2 b1 b2 {
        local pos = strpos(`"``v''"', " \\ ")
        if `pos' > 0 local `v's = substr(`"``v''"', 1, `pos' - 1)
        else         local `v's = `"``v''"'
    }

	if "`c'" == "USA" {
		file write fh "\midrule" _n
		file write fs "\midrule" _n
	}

    file write fh ///
    `" `c' & `year0' & \makecell{`a1'} & \makecell{`a2'} & \makecell{`b1'} & \makecell{`b2'} \\ "' _n
    file write fs ///
    `" `c' & `year0' & `a1s' & `a2s' & `b1s' & `b2s' \\ "' _n

    restore
}

foreach h in fh fs {
    file write `h' "\bottomrule" _n
    file write `h' "\end{tabular}" _n
    file close `h'
}
