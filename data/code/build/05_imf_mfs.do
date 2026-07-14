*==============================================================================
* 05_imf_mfs.do — IMF MFS NSRF archive -> central-bank balance sheets (G-10, 1950-79)
* Input:   $raw/imf/$mfsfile (G-10/1950-79 subset of the MFS NSRF archive CSV,
*          pulled 2025-08-26; derived by prebuild/trim_raw_data.py)
*          $temp/bis_exchangerates_{A,Q,M}.dta (run build/01_bis_er.do first)
* Output:  $temp/mfs_cbs_{A,Q,M}.dta  (nda, nfa, rm + _usd)
* Used by: tab01_nda_growth.do (Table 1), fig06_balancesheet.do (Fig 6),
*          build/07_calibration_multi_country.do (theta, m0)
*==============================================================================

global mfsfile "imf_mfs_nsrf_2025-08-26_g10_1950-1979.csv"

import delimited "$raw/imf/$mfsfile", clear varnames(nonames)

forvalues j = 1/44 {
    local val = v`j'[1]   // first observation of v`j'
	local vallower = lower("`val'")
    label var v`j' "`val'"
	rename v`j' `vallower'
}

forvalues j = 45/554 {
    local val = v`j'[1]
    local val = subinstr("`val'","-","",.)
    local val = subinstr("`val'"," ","_",.)
    local newname = "value" + substr("`val'",1,31)
    capture rename v`j' `newname'
}

gen country_iso3 = substr(series_code,1,3)
gen keepcountry =1 if inlist(country_iso3, "FRA","DEU","ITA","USA","CHE","GBR","BEL")
replace keepcountry =1 if inlist(country_iso3, "NLD","JPN","SWE","CAN")
keep if keepcountry == 1
drop keepcountry
keep if type_of_transformation == "Domestic currency" | (country_iso3== "USA" & type_of_transformation == "US dollar")

drop dataset series_code scale obs_measure  type_of_transformation precision decimals_displayed mfs_nsrf_instrl sector transformation unit derivation_type overlap ifs_flag status doi full_description author publisher department contact_point topic topic_dataset keywords keywords_dataset language publication_date update_date methodology methodology_notes access_sharing_level access_sharing_notes security_classification source short_source_citation full_source_citation license suggested_citation key_indicator series_name country

destring value*, replace
reshape long value , i(country indicator frequency mfs_srvy) j(date) string


save "$temp/mfs_temp.dta", replace

//

use "$temp/mfs_temp.dta", clear

keep if mfs_srvy == "Central Bank Survey"

gen flow = ""
replace flow = "nda_capacc" if indicator == "Capital Accounts"
replace flow = "nda_govdep" if indicator == "Central or General Government Deposits"
replace flow = "nda_claimsgov" if indicator == "Claims on Central or General Government"
replace flow = "nda_claimsdep" if indicator == "Claims on Other Depository Corporations"
replace flow = "nda_claimspriv" if indicator == "Claims on Private Sector"
replace flow = "nda_other" if indicator == "Other Items (Net)"
replace flow = "nda_bonds" if indicator == "Bonds (Debt Securities)"
replace flow = "nda_claimsstate" if indicator == "Claims on State and Local Government or Official Entities"
replace flow = "nda_claimsotherfin" if indicator == "Claims on Other Financial Corporations"
replace flow = "nfa_asset" if indicator == "Foreign Assets"
replace flow = "nfa_liab" if indicator == "Foreign Liabilities"
replace flow = "rm_bankdep" if indicator == "Reserve Money, Bankers Deposits"
replace flow = "rm_currency" if indicator == "Reserve Money, of which: Currency Outside Other Depository Corporations"
replace flow = "rm_privdep" if indicator == "Reserve Money, Private Sector Deposits"
replace flow = "rm_otherliab" if indicator == "Reserve Money, Other Liabilities to Other Depository Corporations"
replace flow = "rm_total" if indicator == "Reserve Money"
replace flow = "nda_liabotherfincorp" if indicator == "Liabilities to Other Financial Corporations"
replace flow = "nda_claimspublicnfc" if indicator == "Claims on Public Non-financial Corporations"
replace flow = "nda_netclaimsgov" if indicator == "Claims on Central or General Government, Net Claims on Central or General Government"
replace flow = "dep_restricted" if indicator == "Restricted Deposits"
replace flow = "dep_securities" if indicator == "Securities Other Than Shares, Liabilities of Central Bank: Securities"
replace flow = "dep_timedeposits" if indicator == "Time, Savings, and Foreign Currency Deposits"
drop indicator

reshape wide value, i(frequency date country_iso3) j(flow) string
rename value* *

sort country frequency date

gen str10 freq = ///
    cond(strpos(date,"M"), "Monthly", ///
    cond(strpos(date,"Q"), "Quarterly", "Annual"))
drop if freq!= frequency
drop freq

local liabilitiesvars "nfa_liab nda_other nda_govdep nda_liabotherfincorp nda_capacc"   
foreach var of local liabilitiesvars{
	replace `var' = -`var'
}

local rm_decomposed "rm_bankdep rm_currency rm_otherliab rm_privdep"
foreach var of local rm_decomposed {
	replace `var' =. if rm_total !=.
}

local balancesheet "nda nfa rm"
foreach var of local balancesheet {
	egen `var' = rowtotal(`var'_*)
}

replace frequency = substr(frequency,1,1)

save "$temp/mfs_cbs_temp.dta", replace

//


local frequencies "A Q M"
foreach f of local frequencies {
	use "$temp/mfs_cbs_temp.dta", clear
	rename date tempdate
	keep if frequency == "`f'"
    if "`f'" == "A" {
        gen date = real(tempdate)
        format date %ty
    }
    else if "`f'" == "Q" {
		gen year = real(substr(tempdate,1,4))
		gen quarter = real(substr(tempdate,6,1))
		gen date = yq(year,quarter)
        format date %tq
    }
    else if "`f'" == "M" {
		gen year = real(substr(tempdate,1,4))
		gen month = real(substr(tempdate,6,2))
		gen date = ym(year,month)
        format date %tm
    }
	drop temp*
	merge 1:1 country_iso3 date using "$temp/bis_exchangerates_`f'.dta"
	drop if _merge ==2
	drop _merge
	rename value er_bis
	local balancesheet "nda nfa rm"
	foreach var of local balancesheet {
		gen `var'_usd = `var'/er_bis
	}
	save "$temp/mfs_cbs_`f'.dta", replace
}
