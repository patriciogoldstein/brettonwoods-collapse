*==============================================================================
* _eur_to_lcu.do — defines program eur_to_lcu (EUR -> pre-euro legacy LCU)
*
* SINGLE SOURCE OF TRUTH for the official irrevocable euro conversion rates.
* Load with:   do "${code}/build/_eur_to_lcu.do"
* Then apply:  eur_to_lcu <var> [if] [in]   (requires country_iso3 in memory)
*
* Source: Council Regulation (EC) No 2866/98 (31 Dec 1998) for the original
* members (BEF/LUF 40.3399, DEM 1.95583, ESP 166.386, FRF 6.55957,
* IEP 0.787564, ITL 1936.27, NLG 2.20371, ATS 13.7603, PTE 200.482,
* FIM 5.94573); GRD 340.750 via Reg. (EC) 1478/2000 (Greece, 2001); later
* adopters (SVN SVK EST LVA LTU MLT CYP HRV) via their accession regulations.
* Rates are irrevocable/exact and verified against the ECB fixings.
* Non-euro countries are left untouched.
*==============================================================================

capture program drop eur_to_lcu
program define eur_to_lcu
    syntax varlist(max=1) [if] [in]
    marksample touse
    quietly {
        replace `varlist' = `varlist' * 40.3399  if country_iso3 == "BEL" & `touse'
        replace `varlist' = `varlist' * 1.95583  if country_iso3 == "DEU" & `touse'
        replace `varlist' = `varlist' * 15.6466  if country_iso3 == "EST" & `touse'
        replace `varlist' = `varlist' * 0.787564 if country_iso3 == "IRL" & `touse'
        replace `varlist' = `varlist' * 340.750  if country_iso3 == "GRC" & `touse'
        replace `varlist' = `varlist' * 166.386  if country_iso3 == "ESP" & `touse'
        replace `varlist' = `varlist' * 0.585274 if country_iso3 == "CYP" & `touse'
        replace `varlist' = `varlist' * 6.55957  if country_iso3 == "FRA" & `touse'
        replace `varlist' = `varlist' * 7.53450  if country_iso3 == "HRV" & `touse'
        replace `varlist' = `varlist' * 1936.27  if country_iso3 == "ITA" & `touse'
        replace `varlist' = `varlist' * 0.702804 if country_iso3 == "LVA" & `touse'
        replace `varlist' = `varlist' * 3.45280  if country_iso3 == "LTU" & `touse'
        replace `varlist' = `varlist' * 40.3399  if country_iso3 == "LUX" & `touse'
        replace `varlist' = `varlist' * 0.429300 if country_iso3 == "MLT" & `touse'
        replace `varlist' = `varlist' * 2.20371  if country_iso3 == "NLD" & `touse'
        replace `varlist' = `varlist' * 13.7603  if country_iso3 == "AUT" & `touse'
        replace `varlist' = `varlist' * 200.482  if country_iso3 == "PRT" & `touse'
        replace `varlist' = `varlist' * 239.640  if country_iso3 == "SVN" & `touse'
        replace `varlist' = `varlist' * 30.1260  if country_iso3 == "SVK" & `touse'
        replace `varlist' = `varlist' * 5.94573  if country_iso3 == "FIN" & `touse'
    }
end
