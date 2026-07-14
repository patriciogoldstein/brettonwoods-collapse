"""trim_raw_data.py — derive the shipped raw CSVs from the full IMF/BIS portal files.

The replication package ships country/period subsets of four large portal
downloads (the full files exceed GitHub size limits and are >95% out of scope).
This script is the exact derivation: rerunning it on the original portal files
reproduces the shipped raws bit-for-bit. Original vintages:

  IMF MFS NSRF archive   dataset_2025-08-26T13_38_33.167851117Z_..._IMF.STA_MFS_NSRF_1.0.3.csv
                         (data.imf.org, dataset IMF.STA:MFS_NSRF, pulled 2025-08-26)
  IMF International Liquidity
                         dataset_2025-11-18T01_09_45.387374803Z_..._IMF.STA_IL_13.0.1.csv
                         (data.imf.org, dataset IMF.STA:IL, pulled 2025-11-18)
  BIS US dollar exchange rates (WS_XRU flat CSV, data.bis.org)
  BIS consumer prices (WS_LONG_CPI flat CSV, data.bis.org)

Subsetting rules (nothing else is changed — rows and columns pass through verbatim):
  countries  FRA DEU ITA USA CHE GBR BEL NLD JPN SWE CAN (G-10 + Switzerland)
  IMF files  keep all metadata columns; keep period columns (annual/quarterly/
             monthly) with year <= 1979 — same scope as the positional
             truncation the build scripts previously applied
  BIS XRU    keep COLLECTION 'A' (period averages, the only collection used),
             periods <= 1985
  BIS CPI    periods <= 1985

Usage: python3 trim_raw_data.py <data/raw directory>
Reads the originals and writes the *_g10_* files next to them.
"""

import csv
import re
import sys
from pathlib import Path

G10_ISO3 = {"FRA", "DEU", "ITA", "USA", "CHE", "GBR", "BEL", "NLD", "JPN", "SWE", "CAN"}
G10_ISO2 = {"FR", "DE", "IT", "US", "CH", "GB", "BE", "NL", "JP", "SE", "CA"}
PERIOD_RE = re.compile(r"^(\d{4})(-M\d{2}|-Q\d)?$")


def trim_imf(src, dst, year_max):
    """Keep G-10 rows (SERIES_CODE prefix) and metadata + period columns <= year_max."""
    # utf-8-sig: the portal files carry a BOM; reading without it corrupts the
    # quoting of the first header field
    with open(src, newline="", encoding="utf-8-sig") as f, \
         open(dst, "w", newline="", encoding="utf-8-sig") as g:
        r = csv.reader(f)
        w = csv.writer(g)
        header = next(r)
        keep_idx = []
        for i, name in enumerate(header):
            m = PERIOD_RE.match(name)
            if m is None or int(m.group(1)) <= year_max:
                keep_idx.append(i)
        w.writerow([header[i] for i in keep_idx])
        code_col = header.index("SERIES_CODE")
        n = 0
        for row in r:
            if row[code_col][:3] in G10_ISO3:
                w.writerow([row[i] for i in keep_idx])
                n += 1
        print(f"{dst.name}: {n} series, {len(keep_idx)} columns")


def trim_bis(src, dst, year_max, collection_col=None):
    """Keep G-10 rows (REF_AREA prefix) with TIME_PERIOD year <= year_max."""
    with open(src, newline="", encoding="utf-8-sig") as f, \
         open(dst, "w", newline="", encoding="utf-8-sig") as g:
        r = csv.reader(f)
        w = csv.writer(g)
        header = next(r)
        w.writerow(header)
        area_col = next(i for i, c in enumerate(header) if c.startswith("REF_AREA"))
        time_col = next(i for i, c in enumerate(header) if c.startswith("TIME_PERIOD"))
        coll_col = (next(i for i, c in enumerate(header) if c.startswith("COLLECTION"))
                    if collection_col else None)
        n = 0
        for row in r:
            if row[area_col][:2] not in G10_ISO2:
                continue
            if not row[time_col][:4].isdigit() or int(row[time_col][:4]) > year_max:
                continue
            if coll_col is not None and row[coll_col][:1] != "A":
                continue
            w.writerow(row)
            n += 1
        print(f"{dst.name}: {n} rows")


raw = Path(sys.argv[1])
trim_imf(raw / "imf" / "dataset_2025-08-26T13_38_33.167851117Z_DEFAULT_INTEGRATION_IMF.STA_MFS_NSRF_1.0.3.csv",
         raw / "imf" / "imf_mfs_nsrf_2025-08-26_g10_1950-1979.csv", 1979)
trim_imf(raw / "imf" / "dataset_2025-11-18T01_09_45.387374803Z_DEFAULT_INTEGRATION_IMF.STA_IL_13.0.1.csv",
         raw / "imf" / "imf_il_2025-11-18_g10_1950-1979.csv", 1979)
trim_bis(raw / "bis" / "WS_XRU_csv_flat.csv",
         raw / "bis" / "bis_xru_g10_1950-1985.csv", 1985, collection_col=True)
trim_bis(raw / "bis" / "WS_LONG_CPI_csv_flat.csv",
         raw / "bis" / "bis_long_cpi_g10_1950-1985.csv", 1985)
