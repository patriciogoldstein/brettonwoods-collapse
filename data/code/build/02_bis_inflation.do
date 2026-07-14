*==============================================================================
* 02_bis_inflation.do — BIS long CPI series (index + YoY), monthly
* Input:   $raw/bis/bis_long_cpi_g10_1950-1985.csv (G-10 subset of the BIS
*          WS_LONG_CPI flat CSV; derived by prebuild/trim_raw_data.py)
* Output:  $temp/bis_inflation.dta
* Used by: fig08_prices.do (Fig 8 + appendix), fig04_exchangerates.do (real ER)
*==============================================================================

*Import Dataset and Clean by Frequency

import delimited "$raw/bis/bis_long_cpi_g10_1950-1985.csv", clear
gen freq = substr(freqfrequency,1,1)
gen country_iso3 = substr(ref_areareferencearea,1,2)
rename time_periodtimeperiodorrange time 
rename obs_valueobservationvalue value
gen unit = substr(unit_measureunitofmeasure,1,3)
replace unit = "Index" if unit == "628"
replace unit = "YoY" if unit == "771"
keep if freq == "M"
keep  country_iso3 time value unit
gen date = monthly(time, "YM")
format date %tm
kountry country_iso3, from(iso2c) to(iso3c)
drop country_iso3
rename _ISO3C_ country_iso3
drop if country_iso3 == ""
save "$temp/bis_inflation.dta", replace