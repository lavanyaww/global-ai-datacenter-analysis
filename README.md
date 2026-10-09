# Global AI & Data Center Resource Consumption Analysis (SQL Portfolio Project)

A country-level analysis of electricity and water consumption by data
centers/AI infrastructure, 2015–2024. Built to demonstrate statistical SQL
techniques that go beyond basic reporting: trend analysis, tiering, and
anomaly detection.

**Tech used:** PostgreSQL · Power BI (Power Query/M, DAX) · Window functions
(`LAG`, `NTILE`, `AVG`/`STDDEV_POP`) · CTEs · Z-score anomaly detection

> **Note on the data:** the dataset is **synthetic** — built to realistic,
> plausible scale for practicing analysis, not scraped or copied from any
> official report (IEA, company disclosures, etc.). Say so if asked about it;
> the value of the project is the analysis technique, not the specific numbers.

---

## 1. Project Overview

Global electricity and water demand from data centers has become a real
talking point as AI workloads scale up. This project simulates a country-year
panel of consumption data and answers three levels of question:

1. **Trend** — how fast is consumption growing, globally and per country?
2. **Ranking** — which countries are the heaviest consumers, and which run
   the most resource-intensive facilities per site?
3. **Anomaly** — did any country have a year that broke from its own trend,
   and is that a real one-off event or part of a broader shift?

## 2. Dataset

`datacenter_usage_raw.csv` — 154 rows: 15 countries × 2015–2024, plus a few
intentional data-quality issues to clean first:
- 4 exact duplicate rows
- 2 rows with a negative `electricity_twh` value (data-entry sign errors)
- 9 rows with a genuinely missing `renewable_energy_pct` (a few countries
  didn't track/report this consistently before 2018 — left as NULL, not
  imputed, since imputing would fabricate a number that was never observed)

Columns: `country`, `region`, `year`, `num_data_centers`, `electricity_twh`,
`water_million_liters`, `renewable_energy_pct`, `avg_pue` (Power Usage
Effectiveness — lower is more efficient).

## 3. Data Cleaning

154 raw rows → **150** after removing exact duplicates → **148** after
dropping the 2 impossible negative-consumption rows. The 9 missing
`renewable_energy_pct` values are left as NULL through the rest of the
analysis — they're excluded from renewable-% averages automatically, not
treated as zero.

## 4. Key Findings

**Global trend**
- Global electricity consumption: **199 TWh (2015) → 452 TWh (2024)**, up **127%**
- Global water consumption: **406 billion litres (2015) → 1.04 trillion litres (2024)**, up **157%**
- Growth accelerates sharply from 2023 onward across almost every country —
  consistent with the broader AI infrastructure buildout narrative, not just
  one country's story

**Country tiering (NTILE, 2024)**
- Top consumption tier: **United States, China, India, Japan**
- By intensity per data center (electricity ÷ site count) rather than raw
  volume, the ranking shifts: **China, United States, UAE, Ireland, and
  Singapore** run the most resource-dense facilities — small countries can
  rank high here even with modest total consumption

**Anomaly detection (Z-score on YoY growth, not raw level)**

A naive Z-score on raw consumption falsely flags almost every country's most
recent year, simply because the whole series trends upward — the most recent
year is always furthest from the mean. Running the Z-score on each country's
*year-over-year growth rate* instead fixes this, and surfaces two standout
outliers:
**Growth pattern:** The simulated dataset shows faster electricity and water consumption growth during 2023–2024. This reflects the patterns represented in the dataset and should not be interpreted as independent evidence of an industry-wide inflection point.
- **India, 2024: water consumption jumped 117% year-over-year (z ≈ 2.8)** —
  the sharpest water-specific anomaly, separate from its electricity trend
- Several other countries (China, Canada, Singapore, Brazil) also show
  elevated 2023–24 growth-rate anomalies, but at lower z-scores — read
  together, this suggests an industry-wide inflection point rather than one
  isolated event, with Ireland and India as the extremes

**Efficiency & sustainability**
- Average renewable energy share: **30.3% (2018) → 41.3% (2024)**
- Average PUE (efficiency): **1.75 (2015) → 1.49 (2024)** — lower is better,
  so this is a genuine efficiency improvement even as total consumption rose

## 5. Dashboard (Power BI)

The same cleaning and analysis logic (dedup, invalid-row filtering, YoY
growth, tiering, Z-score anomaly detection) is rebuilt in Power Query/DAX and
presented as a 4-page interactive dashboard — Overview, Country Tiering,
Anomaly Detection, and Efficiency & Sustainability. See `powerbi/` for the
`.pbix` file and screenshots.

## 6. Business Questions Answered (see `datacenter_sql_project.sql`)

1. How fast is global electricity/water consumption from data centers growing?
2. Which countries are the heaviest consumers, in absolute and per-site terms?
3. Did any country/year break from its own trend enough to flag for investigation?
4. Is efficiency (PUE) actually improving despite rising total consumption?
5. How is renewable energy adoption trending?

## 7. Skills Demonstrated

SQL, Data Cleaning, CTEs, Window Functions, Trend Analysis, Z-Score Anomaly Detection, Power Query (M), DAX, Power BI Dashboard Design, and Data Visualization.

<WritingBlock id="84216" variant="standard">## 8. How to Run
Open sql/datacenter_sql_project.sql in PostgreSQL and execute the queries against a database containing the project dataset. Open powerbi/global_data_analysis.pbix in Power BI Desktop to explore the dashboard.
Note: Import the dataset into PostgreSQL before running the SQL script.</WritingBlock>
