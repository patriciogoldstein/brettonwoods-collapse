******************************************
* MAIN
******************************************

************* PRELIMINARIES *************

* EDIT THIS LINE: absolute path to the data/ folder of this package
global path "/EDIT/ME/brettonwoods-collapse/data"
************* GLOBALS *************
cd "${path}"

global code "${path}/code"
global raw "${path}/raw"
global temp "${path}/work"
global charts "${path}/figures"
global pathmodel "${path}/../model"   // python model folder (calibration_values.csv lands here)

* Frozen API snapshots (created by code/prebuild/freeze_*.py/.do — see headers there;
* to refresh a vintage, rerun the freeze script and update the filename here)
global wdisnapshot "${raw}/wdi/wdi_gdp_2026-07-14.csv"            // WDI vintage 2026-07-13
global fredsnapshot "${raw}/fred/fred_us_ca_trade_2026-07-14.dta" // FRED pull 2026-07-14

* Event dates (single source of truth — use these in every chart, never hardcode)
global goldpoolstart_day "=dmy(1,11,1961)"   // London Gold Pool begins operating, Nov 1961
global gbpdeval_day "=dmy(18,11,1967)"       // GBP devaluation announced
global goldpoolend_day "=dmy(17,3,1968)"     // two-tier gold market communique (London market closed Mar 15)
global demfloat_day "=dmy(5,5,1971)"         // Bundesbank stops intervening; DEM floats May 10
global nixonshock_day "=dmy(15,8,1971)"      // gold window closed
global smithsonian_day "=dmy(18,12,1971)"    // Smithsonian Agreement; official gold price $35 -> $38
global g10deval_day "=dmy(12,2,1973)"        // second USD devaluation announced; official gold price -> $42.22
global g10float_day "=dmy(16,3,1973)"        // G-10 communique; generalized float

global goldpoolstart_month "=ym(1961,11)"
global gbpdeval_month "=ym(1967,11)"
global goldpoolend_month "=ym(1968,3)"
global demfloat_month  "=ym(1971,5)"
global nixonshock_month  "=ym(1971,8)"
global smithsonian_month "=ym(1971,12)"
global g10deval_month "=ym(1973,2)"
global g10float_month  "=ym(1973,3)"

global demfloat_week "=yw(1971,19)"
global nixonshock_week  "=yw(1971,34)"
global g10float_week  "=yw(1973,11)"


************* CHART FORMAT *************

// ssc install scheme-burd, replace

global FRAcolor    "blue"
global DEUcolor    "orange"
global JPNcolor    "purple"
global NLDcolor    "green"
global CHEcolor    "red"
global GBRcolor    "olive"    
global USAcolor    "black"   
global BELcolor "gold"
global SWEcolor "midblue"
global CANcolor "cranberry"
global ITAcolor "lime"

global fontsize "medlarge"

