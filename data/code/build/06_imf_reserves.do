*==============================================================================
* 06_imf_reserves.do — IMF International Liquidity -> official reserves (G-10)
* Input:   $raw/imf/$reservesfile (G-10/1950-79 subset of the IMF IL CSV,
*          pulled 2025-11-18; derived by prebuild/trim_raw_data.py)
* Output:  $temp/imfreserves_{A,Q,M}.dta (fx, gold, sdr, imf position; USD M)
* Used by: fig07_reserves.do (Fig 7), build/07_calibration_multi_country.do (mbar)
*==============================================================================

global reservesfile "imf_il_2025-11-18_g10_1950-1979.csv"

import delimited "$raw/imf/$reservesfile", clear varnames(nonames)

forvalues j = 1/41 {
    local val = v`j'[1]   // first observation of v`j'
	local vallower = lower("`val'")
    label var v`j' "`val'"
	rename v`j' `vallower'
}

forvalues j = 42/636 {
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
keep if unit == "US dollar"


drop dataset  series_code obs_measure country scale decimals_displayed   ra_type il_acct sector mfs_coltn counterparty_sector valuation transformation ifs_flag  decimals_displayed doi full_description author publisher department contact_point topic topic_dataset keywords keywords_dataset language publication_date update_date methodology methodology_notes access_sharing_level access_sharing_notes security_classification short_source_citation full_source_citation license suggested_citation key_indicator series_name unit
destring value*, replace
reshape long value , i(country_iso3 indicator frequency) j(date) string

save "$temp/imfreserves_temp.dta", replace

//

use "$temp/imfreserves_temp.dta", clear

gen flow = ""
replace flow = "reserves_total" if indicator == "Total reserves (gold at national valuation)"
replace flow = "reserves_gold" if indicator == "Gold reserves at national valuation"
replace flow = "reserves_sdr" if indicator == "Reserves, Special Drawing Rights (SDRs)"
replace flow = "reserves_fx" if indicator == "Reserves excluding gold, foreign exchange"
replace flow = "reserves_imf" if indicator == "Reserves, reserve position in the IMF"
replace flow = "reserves_other" if indicator == "Reserves excluding gold, other reserve assets"
drop if flow == ""
drop indicator

reshape wide value, i(frequency date country_iso3) j(flow) string
rename value* *

sort country frequency date

gen str10 freq = ///
    cond(strpos(date,"M"), "Monthly", ///
    cond(strpos(date,"Q"), "Quarterly", "Annual"))
drop if freq!= frequency
drop freq

replace frequency = substr(frequency,1,1)

local frequencies "A Q M"
foreach f of local frequencies {
	preserve
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
	save "$temp/imfreserves_`f'.dta", replace
	restore
}