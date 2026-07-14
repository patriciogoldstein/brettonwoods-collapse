*==============================================================================
* 01_bis_er.do — BIS exchange rates (LC/USD), all frequencies
* Input:   $raw/bis/bis_xru_g10_1950-1985.csv (G-10/period-average subset of the
*          BIS WS_XRU flat CSV; derived by prebuild/trim_raw_data.py)
* Output:  $temp/bis_exchangerates{,_A,_Q,_M,_W,_D}.dta
* Used by: build/05_imf_mfs.do (USD conversion), fig04_exchangerates.do,
*          fig01_cbpurchases.do (weekly W file)
* Notes:   euro-era values converted back to legacy LCU via eur_to_lcu.
*==============================================================================

*Import Dataset and Clean by Frequency

import delimited "$raw/bis/bis_xru_g10_1950-1985.csv", clear
gen freq = substr(freqfrequency,1,1)
gen area = substr(ref_areareferencearea,1,2)
gen collection = substr(collectioncollection,1,1)
keep if collection == "A"
rename time_periodtimeperiodorrange time 
rename obs_valueobservationvalue value
keep  freq area time value
save "$temp/bis_exchangerates.dta", replace

use "$temp/bis_exchangerates.dta", clear
kountry area, from(iso2c) to(iso3c)
drop area
rename _ISO3C_ country_iso3
drop if country_iso3 == ""
local freqs "A Q M W D" //  A Q D M
do "${code}/build/_eur_to_lcu.do"  // official irrevocable euro rates (shared program)
eur_to_lcu value

foreach f of local freqs {
    preserve
	if "`f'" == "M" {
		keep if freq == "`f'"
		gen date = monthly(time, "YM")
        format date %tm
		drop freq time
    }
    else if "`f'" == "D" {
		keep if freq == "`f'"
        gen date = daily(time, "YMD")
        format date %td
		bysort country_iso3 (date): replace value = value[_n-1] if missing(value)
		drop freq time
    }
	else if "`f'" == "A" {
		keep if freq == "`f'"
        gen date = yearly(time, "Y")
        format date %ty
		drop freq time
    }
    else if "`f'" == "Q" {
		keep if freq == "`f'"
		gen temp = subinstr(time, "Q", "q", .)
		replace temp = subinstr(temp, "-", "", .)
		gen date = quarterly(temp, "Yq")
        format date %tq
		drop temp freq time
    }
    else if "`f'" == "W" {
		keep if freq == "D"
        gen tempdate = daily(time, "YMD")
		gen weekdate = yw(year(tempdate), week(tempdate))
		format weekdate %tw
		* sort by the DAILY date: sorting by weekdate alone leaves the within-week
		* order random, making the forward-fill (and the weekly mean) nondeterministic
		bysort country_iso3 (tempdate): replace value = value[_n-1] if missing(value)
        collapse (mean) value, by(country_iso3 weekdate)
    }
	save "$temp/bis_exchangerates_`f'.dta", replace
    restore
}
