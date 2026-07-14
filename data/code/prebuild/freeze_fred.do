*==============================================================================
* freeze_fred.do — one-time snapshot of the FRED pull (run 2026-07-14)
* Input:   live FRED API. Requires a personal API key set beforehand:
*          set fredkey <your-key>, permanently   (free at fred.stlouisfed.org)
* Output:  $raw/fred/fred_us_ca_trade_2026-07-14.dta and .csv
* Series (quarterly, BEA national accounts): EXPGS, IMPGS, NETFI, GDP
* Read by charts/fig_fred_us_ca_trade.do. Rerun only to refresh vintage.
*==============================================================================

import fred EXPGS IMPGS NETFI GDP, daterange(1955-10-01 1979-12-31) clear

save "$raw/fred/fred_us_ca_trade_2026-07-14.dta", replace
export delimited using "$raw/fred/fred_us_ca_trade_2026-07-14.csv", replace
