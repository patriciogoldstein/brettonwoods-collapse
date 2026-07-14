*==============================================================================
* 04_wdidata.do — World Bank WDI GDP (frozen snapshot), G-10 set
* Input:   $wdisnapshot (frozen WDI pull; see prebuild/freeze_wdi.py for vintage)
* Output:  $temp/temp_wdigdp.dta (1971 base-year GDP), $temp/temp_wdigdp_all.dta
* Used by: tab01_nda_growth.do, fig06_balancesheet.do, fig01_cbpurchases.do, fig07_reserves.do
* Notes:   euro-era LCU converted to legacy currency via eur_to_lcu; constant series
*          rebased to nominal in 1971. To refresh the vintage, rerun the freeze
*          script and update $wdisnapshot in main.do.
*==============================================================================

do "${code}/build/_eur_to_lcu.do"  // defines eur_to_lcu (official irrevocable euro rates)


* Program to adjust constant/real series to match nominal in base year 
* Usage: adjust_constant_to_base real_var nominal_var base_year [if] [in]

capture program drop adjust_constant_to_base
program define adjust_constant_to_base
    syntax varlist(min=2 max=2) , BASEyear(integer) [if] [in]
    
    marksample touse
    
    tokenize `varlist'
    local real_var `1'
    local nominal_var `2'
    
    tempvar ratio adj_real
    
    * Calculate the ratio of nominal to real in the base year
    quietly {
        gen double `ratio' = `nominal_var' / `real_var' if year == `baseyear' & `touse'
        
        * Fill the ratio forward for all years within each country
        bysort country_iso3 (`ratio'): egen double scalar_factor = mean(`ratio') if `touse'
        
        * Adjust the real series by multiplying by this ratio
        gen double `adj_real' = `real_var' * scalar_factor if `touse'
        
        * Replace the original variable
        replace `real_var' = `adj_real' if `touse'
        
        drop scalar_factor
    }

    di as text "Constant series adjusted to match nominal in `baseyear'"
end

capture program drop keepcountries
program define keepcountries
gen keepcountry =1 if inlist(country_iso3, "FRA","DEU","ITA","USA","GBR","BEL")
replace keepcountry =1 if inlist(country_iso3, "JPN","SWE","CAN","NLD","CHE")
keep if keepcountry == 1
drop keepcountry
end

* Dataset 1: Loading 1971 data
import delimited "$wdisnapshot", clear
keep if year == 1971
keep countrycode ny_gdp_mktp_cn ny_gdp_mktp_cd ny_gdp_mktp_kn
rename countrycode country_iso3
keepcountries
rename ny_gdp_mktp_cn gdp_1971_lcu
rename ny_gdp_mktp_cd gdp_1971_usd
eur_to_lcu gdp_1971_lcu
save "$temp/temp_wdigdp.dta", replace



* Dataset 2: Loading all years data
import delimited "$wdisnapshot", clear
keep countrycode ny_gdp_mktp_cn ny_gdp_mktp_cd ny_gdp_mktp_kn year
rename countrycode country_iso3
keepcountries
rename ny_gdp_mktp_cn gdp_lcu
rename ny_gdp_mktp_cd gdp_usd
rename ny_gdp_mktp_kn gdp_lcuconstant
eur_to_lcu gdp_lcu
adjust_constant_to_base gdp_lcuconstant gdp_lcu, baseyear(1971)
save "$temp/temp_wdigdp_all.dta", replace

