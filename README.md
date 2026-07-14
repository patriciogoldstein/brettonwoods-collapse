# Replication package — "I Don't Want Your Dollars: Reverse Speculative Attacks and the Collapse of Bretton Woods (1971–1973)"

Patricio Goldstein (Columbia University) and Andrés Neumeyer (Universidad Torcuato Di Tella)

**Paper:** [`BrettonWoods_GoldsteinNeumeyer.pdf`](BrettonWoods_GoldsteinNeumeyer.pdf) (current draft, in this repository)

Reproduces every figure and table in the paper. Filenames follow the paper's
numbering (`fig01`–`fig11`, `figA1`–`figA11`, `tab01`–`tab03`).

The repository also hosts **`data/CB_FX_holdings_Fig1_public.xlsx`**: weekly
central-bank foreign-exchange holdings, 1971–1973, for nine central banks,
compiled by the authors from primary statistical publications. Source detail
is in the workbook.

## Requirements

- Stata 17+ with `grc1leg`, `xtscc`, `kountry` (`ssc install …`).
- Python 3.10+ with `numpy`, `scipy`, `pandas`, `matplotlib`.
- No internet access is needed.

## How to run

Edit one line at the top of `data/code/main.do`:

```stata
global path "/absolute/path/to/brettonwoods-collapse/data"
```

Run `main.do`, then the `build/` scripts in numeric order, then the chart
scripts:

```stata
do "data/code/main.do"
do "$code/build/01_bis_er.do"
do "$code/build/02_bis_inflation.do"
do "$code/build/03_gfd_er.do"          // needs the GFD file, see below
do "$code/build/04_wdidata.do"
do "$code/build/05_imf_mfs.do"
do "$code/build/06_imf_reserves.do"
do "$code/build/07_calibration_multi_country.do"
do "$code/charts/fig01_cbpurchases.do"
do "$code/charts/fig03_goldpool.do"       // needs the GFD file
do "$code/charts/fig04_exchangerates.do"
do "$code/charts/fig05_bao.do"
do "$code/charts/tab01_nda_growth.do"
do "$code/charts/fig06_balancesheet.do"
do "$code/charts/fig07_reserves.do"
do "$code/charts/fig08_prices.do"
do "$code/charts/figA2_us_ca_trade.do"
do "$code/charts/figA3_er_blackmarket.do" // needs the GFD file
```

Outputs land in `data/figures/`. `07_calibration_multi_country.do` also writes
`model/calibration_values.csv`, the input to the Python model (a pre-computed
copy is included, so the model runs without Stata):

```bash
cd model
python bw_main.py --step baseline --country DEU --attack attack73 --force   # Fig 9
python bw_main.py --step baseline --country JPN --attack attack73 --force   # Fig A10
python bw_main.py --step compstatics --country DEU --attack attack73        # Fig 10, Fig A11
python bw_main.py --step multicountry                                       # Fig 11
python bw_main.py --step table --country DEU JPN --attack attack71 attack73 # Table 3
```

Outputs land in `model/figures/`. Pre-generated copies of all outputs are
included.

## Data availability

All inputs are included except the Global Financial Data files (proprietary).

| Input | Source | Accessed |
|---|---|---|
| `data/CB_FX_holdings_Fig1_public.xlsx` | Authors' compilation (SNB, Bundesbank, Banque de France/Baubeau 2018, Bank of Japan, Bank of England/Naef, National Bank of Belgium, Sveriges Riksbank, Bank of Canada, De Nederlandsche Bank) | — |
| `raw/imf/imf_mfs_nsrf_2025-08-26_g10_1950-1979.csv` | IMF Monetary & Financial Statistics, NSRF archive ([data.imf.org](https://data.imf.org/), `IMF.STA:MFS_NSRF`) | 2025-08-26 |
| `raw/imf/imf_il_2025-11-18_g10_1950-1979.csv` | IMF International Liquidity ([data.imf.org](https://data.imf.org/), `IMF.STA:IL`) | 2025-11-18 |
| `raw/bis/bis_xru_g10_1950-1985.csv` | BIS US dollar exchange rates, `WS_XRU` ([data.bis.org](https://data.bis.org/topics/XRU)) | 2025-11-03 |
| `raw/bis/bis_long_cpi_g10_1950-1985.csv` | BIS consumer prices, `WS_LONG_CPI` ([data.bis.org](https://data.bis.org/topics/CPI)) | 2025-11-17 |
| `raw/wdi/wdi_gdp_2026-07-14.csv` | World Bank WDI (CC BY 4.0): `NY.GDP.MKTP.{CN,CD,KN,KD}`, `NE.CON.TOTL.ZS` | 2026-07-14 |
| `raw/fred/fred_us_ca_trade_2026-07-14.{dta,csv}` | FRED: `EXPGS`, `IMPGS`, `NETFI`, `GDP` | 2026-07-14 |
| `raw/bao/bao2018_fed_weekly_balancesheet.xlsx` | Bao, Chen, Fries, Gibson, Paine & Schuler (2018), [JHU Studies in Applied Economics](https://sites.krieger.jhu.edu/iae/files/2018/07/Federal-Reserve-Systems-Weekly-Balance-Sheet-Since-1914.pdf); data via [CFS](https://centerforfinancialstability.org/hfs/Fed_weekly_balance_sheet_since_1914_data.xlsb) | 2025-11-18 |
| `raw/naefdata/naef_figure101.xlsx` | Naef (2022); [Harvard Dataverse doi:10.7910/DVN/NXRRBI](https://doi.org/10.7910/DVN/NXRRBI), [openICPSR 111725](https://www.openicpsr.org/openicpsr/project/111725/version/V1/view) | 2025 |
| `raw/gfd/` | Global Financial Data / Finaeon: gold price; black-market exchange rates (tickers `USDDEMBM` etc.) | 2025-06-02 / 2025-12-09 |

GFD data is proprietary and not included; it affects Fig 3 (premium panel)
and Fig A3. Subscribers can place the series in `data/raw/gfd/` (filenames in
`03_gfd_er.do` and `fig03_goldpool.do`).

The IMF and BIS files are country/period subsets of the portal downloads,
produced by `data/code/prebuild/trim_raw_data.py`; rows and columns pass
through verbatim. The WDI and FRED files are frozen API pulls, produced by
`data/code/prebuild/freeze_wdi.py` and `freeze_fred.do`.

## Figure/table → script map

| Output | Script |
|---|---|
| Fig 1, Fig A1 | `charts/fig01_cbpurchases.do` |
| Fig 2 | archival cartoon (Fritz Wolf, via James 1996); not included |
| Fig 3 | `charts/fig03_goldpool.do` |
| Fig 4, Fig A5, Fig A6 | `charts/fig04_exchangerates.do` |
| Fig 5, Fig A4 | `charts/fig05_bao.do` |
| Table 1 | `charts/tab01_nda_growth.do` |
| Fig 6, Fig A7, Fig A8 | `charts/fig06_balancesheet.do` |
| Fig 7 | `charts/fig07_reserves.do` |
| Fig 8, Fig A9 | `charts/fig08_prices.do` |
| Table 2 | `build/07_calibration_multi_country.do` |
| Table 3 | `model/bw_main.py --step table` |
| Fig 9, Fig A10 | `model/bw_main.py --step baseline` |
| Fig 10, Fig A11 | `model/bw_main.py --step compstatics` |
| Fig 11 | `model/bw_main.py --step multicountry` |
| Fig A2 | `charts/figA2_us_ca_trade.do` |
| Fig A3 | `charts/figA3_er_blackmarket.do` |

## License

Code: MIT (see LICENSE). Data files remain under their providers' terms.
