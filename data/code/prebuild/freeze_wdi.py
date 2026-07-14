"""freeze_wdi.py — one-time snapshot of the World Bank WDI pull (run 2026-07-14).

Fetches five indicators for all countries and years from the World Bank API v2
(JSON) and writes data/raw/wdi/wdi_gdp_<date>.csv, the frozen input read by
build/wdidata.do and build/calibration_multi_country.do. WDI vintage at pull
time: last updated 2026-07-13.

Indicators:
  NY.GDP.MKTP.CN  GDP, current LCU        NY.GDP.MKTP.CD  GDP, current USD
  NY.GDP.MKTP.KN  GDP, constant LCU       NY.GDP.MKTP.KD  GDP, constant USD
  NE.CON.TOTL.ZS  final consumption expenditure, % of GDP

Usage: python3 freeze_wdi.py <output.csv>
Rerun only to refresh the vintage; then update $wdisnapshot in main.do.
"""

import csv
import json
import sys
import urllib.request

INDICATORS = {
    "NY.GDP.MKTP.CN": "ny_gdp_mktp_cn",
    "NY.GDP.MKTP.CD": "ny_gdp_mktp_cd",
    "NY.GDP.MKTP.KN": "ny_gdp_mktp_kn",
    "NY.GDP.MKTP.KD": "ny_gdp_mktp_kd",
    "NE.CON.TOTL.ZS": "ne_con_totl_zs",
}

data = {}
names = {}
for ind, col in INDICATORS.items():
    page, pages = 1, 1
    n = 0
    while page <= pages:
        url = (f"https://api.worldbank.org/v2/country/all/indicator/{ind}"
               f"?format=json&per_page=15000&page={page}")
        with urllib.request.urlopen(url, timeout=120) as r:
            meta, rows = json.load(r)
        pages = meta["pages"]
        for row in rows or []:
            iso3 = row["countryiso3code"]
            if not iso3:
                continue
            data.setdefault((iso3, int(row["date"])), {})[col] = row["value"]
            names[iso3] = row["country"]["value"]
            n += 1
        page += 1
    print(f"{ind}: {n} obs, lastupdated {meta.get('lastupdated')}", file=sys.stderr)

cols = list(INDICATORS.values())
with open(sys.argv[1], "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["countrycode", "countryname", "year"] + cols)
    for (iso3, year) in sorted(data):
        vals = data[(iso3, year)]
        w.writerow([iso3, names[iso3], year] + [vals.get(c, "") for c in cols])
print(f"rows: {len(data)}", file=sys.stderr)
