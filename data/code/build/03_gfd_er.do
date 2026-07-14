*==============================================================================
* 03_gfd_er.do — GFD official + black-market (parallel) exchange rates, monthly
* Input:   $raw/gfd/gfd_blackmarket_er_2025-12-09.xlsx (sheet "Price Data")
* Output:  $temp/gfd_er.dta  (per-country official + _BM series, LC/USD)
* Used by: figA3_er_blackmarket.do (appendix)
*==============================================================================

import excel "$raw/gfd/gfd_blackmarket_er_2025-12-09.xlsx", firstrow clear sheet("Price Data")

reshape wide Close, i(Date) j(Ticker) string
rename Close* *
rename USDBEF   BEL
rename USDBEFBM BEL_BM
rename GBPUSD   GBR
rename GBPUSDBM GBR_BM
rename USDFRF   FRA
rename USDDEM   DEU
rename USDITL   ITA
rename USDNLG   NLD
rename USDCHF   CHE
rename USDJPY   JPN
rename USDFRFBM FRA_BM
rename USDDEMBM DEU_BM
rename USDITLBM ITA_BM
rename USDNLGBM NLD_BM
rename USDCHFBM CHE_BM
rename USDJPYBM JPN_BM
rename USDCAD CAN
rename USDCADBM CAN_BM
rename USDSEK SWE
rename USDSEKBM SWE_BM

rename Date datestr
gen date = date(datestr, "MDY")
format date %td
gen mdate = ym(year(date),month(date))
format mdate %tm

replace GBR = 1 / GBR // official quote is USD/GBP; invert to LC/USD. BM quote is already GBP/USD, leave as is
replace FRA    = 0.01*FRA    if mdate <= ym(1959,12)
replace FRA_BM    = 0.01*FRA_BM    if mdate <= ym(1959,12)

gen USA    = 1
gen USA_BM = 1

save "$temp/gfd_er.dta", replace 
