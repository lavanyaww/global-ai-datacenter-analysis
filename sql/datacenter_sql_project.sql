/* ============================================================================
   GLOBAL AI & DATA CENTER RESOURCE CONSUMPTION ANALYSIS
   SQL Data Analyst Portfolio Project (PostgreSQL)
   ----------------------------------------------------------------------------
   Dataset : datacenter_usage_raw.csv — 15 countries x 2015-2024, electricity
             (TWh), water (million litres), renewable energy %, and average
             PUE (Power Usage Effectiveness) per country-year.
             NOTE: figures are SYNTHETIC / illustrative, built to practice
             SQL analysis — not sourced from any official report.

   PART 0  Setup & import
   PART 1  Data exploration
   PART 2  Data cleaning
   PART 3  Global trend & YoY growth (LAG)
   PART 4  Country tiering (NTILE)
   PART 5  Z-score anomaly detection
   PART 6  Efficiency & sustainability analysis
   PART 7  Executive summary view
   ========================================================================= */


-- ============================================================================
-- PART 0: SETUP & IMPORT
-- ============================================================================

DROP TABLE IF EXISTS datacenter_raw;

CREATE TABLE datacenter_raw (
    record_id               INT PRIMARY KEY,
    country                 VARCHAR(50),
    region                  VARCHAR(30),
    year                    INT,
    num_data_centers        INT,
    electricity_twh         NUMERIC(10,2),
    water_million_liters    NUMERIC(12,1),
    renewable_energy_pct    NUMERIC(5,1),
    avg_pue                 NUMERIC(5,3)
);

-- \copy datacenter_raw FROM 'datacenter_usage_raw.csv' WITH (FORMAT csv, HEADER true);


-- ============================================================================
-- PART 1: DATA EXPLORATION
-- ============================================================================

SELECT COUNT(*) AS total_rows FROM datacenter_raw;
SELECT MIN(year), MAX(year) FROM datacenter_raw;
SELECT COUNT(DISTINCT country) AS countries FROM datacenter_raw;

-- Null check — renewable_energy_pct is expected to have some early-year gaps
SELECT COUNT(*) FILTER (WHERE renewable_energy_pct IS NULL) AS null_renewable
FROM datacenter_raw;

-- Spot invalid values (a negative consumption figure is a data-entry error,
-- not a real observation)
SELECT country, year, electricity_twh
FROM datacenter_raw
WHERE electricity_twh <= 0;

-- Spot exact duplicate rows
SELECT country, region, year, num_data_centers, electricity_twh,
       water_million_liters, renewable_energy_pct, avg_pue, COUNT(*)
FROM datacenter_raw
GROUP BY 1,2,3,4,5,6,7,8
HAVING COUNT(*) > 1;


-- ============================================================================
-- PART 2: DATA CLEANING
-- ============================================================================

-- 2.1 Remove exact duplicates
DROP TABLE IF EXISTS datacenter_deduped;
CREATE TABLE datacenter_deduped AS
SELECT * FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY country, region, year, num_data_centers, electricity_twh,
                         water_million_liters, renewable_energy_pct, avg_pue
            ORDER BY record_id
        ) AS rn
    FROM datacenter_raw
) t
WHERE rn = 1;

-- 2.2 Drop rows with an impossible (negative) consumption value
--     Left as NULL for renewable_energy_pct where it's genuinely missing —
--     that's a reporting gap, not an error, so it is NOT dropped or imputed.
DROP TABLE IF EXISTS datacenter_clean;
CREATE TABLE datacenter_clean AS
SELECT record_id, country, region, year, num_data_centers, electricity_twh,
       water_million_liters, renewable_energy_pct, avg_pue
FROM datacenter_deduped
WHERE electricity_twh > 0;

-- 2.3 Cleaning audit
SELECT
    (SELECT COUNT(*) FROM datacenter_raw)      AS raw_rows,
    (SELECT COUNT(*) FROM datacenter_deduped)  AS after_dedupe,
    (SELECT COUNT(*) FROM datacenter_clean)    AS after_invalid_filter;


-- ============================================================================
-- PART 3: GLOBAL TREND & YEAR-OVER-YEAR GROWTH (LAG)
-- ============================================================================

-- 3.1 Global electricity & water totals by year
SELECT year,
       ROUND(SUM(electricity_twh), 1)      AS total_electricity_twh,
       ROUND(SUM(water_million_liters), 0) AS total_water_million_liters
FROM datacenter_clean
GROUP BY year
ORDER BY year;

-- 3.2 Per-country year-over-year growth using LAG
SELECT
    country, year, electricity_twh,
    ROUND(
        100.0 * (electricity_twh - LAG(electricity_twh) OVER (PARTITION BY country ORDER BY year))
        / NULLIF(LAG(electricity_twh) OVER (PARTITION BY country ORDER BY year), 0)
    , 1) AS yoy_growth_pct
FROM datacenter_clean
ORDER BY country, year;

-- 3.3 Decade-over-decade summary: 2015 vs 2024
WITH endpoints AS (
    SELECT
        SUM(electricity_twh) FILTER (WHERE year = 2015) AS elec_2015,
        SUM(electricity_twh) FILTER (WHERE year = 2024) AS elec_2024,
        SUM(water_million_liters) FILTER (WHERE year = 2015) AS water_2015,
        SUM(water_million_liters) FILTER (WHERE year = 2024) AS water_2024
    FROM datacenter_clean
)
SELECT
    elec_2015, elec_2024, ROUND(100.0*(elec_2024-elec_2015)/elec_2015, 1) AS elec_growth_pct,
    water_2015, water_2024, ROUND(100.0*(water_2024-water_2015)/water_2015, 1) AS water_growth_pct
FROM endpoints;


-- ============================================================================
-- PART 4: COUNTRY TIERING (NTILE)
-- ============================================================================

-- 4.1 Split countries into 4 tiers by 2024 electricity consumption
SELECT
    country,
    electricity_twh,
    NTILE(4) OVER (ORDER BY electricity_twh DESC) AS consumption_tier   -- 1 = heaviest consumers
FROM datacenter_clean
WHERE year = 2024
ORDER BY electricity_twh DESC;

-- 4.2 Same idea, but tiering by per-data-center intensity rather than
--     absolute volume — surfaces dense/large-scale hubs vs. many-small-sites
SELECT
    country,
    ROUND(electricity_twh * 1000.0 / num_data_centers, 2) AS gwh_per_data_center,
    NTILE(4) OVER (ORDER BY electricity_twh * 1000.0 / num_data_centers DESC) AS intensity_tier
FROM datacenter_clean
WHERE year = 2024
ORDER BY gwh_per_data_center DESC;


-- ============================================================================
-- PART 5: Z-SCORE ANOMALY DETECTION
-- ============================================================================
-- A naive Z-score on the RAW electricity/water level will falsely flag almost
-- every country's most recent year, simply because consumption trends upward
-- over the decade (the endpoint is always furthest from the series mean).
-- The fix: compute the Z-score on each country's YEAR-OVER-YEAR GROWTH RATE
-- instead of the raw level — that isolates years that were unusual even
-- relative to that country's own growth trajectory.

WITH yoy AS (
    SELECT
        country, year, electricity_twh,
        100.0 * (electricity_twh - LAG(electricity_twh) OVER (PARTITION BY country ORDER BY year))
          / NULLIF(LAG(electricity_twh) OVER (PARTITION BY country ORDER BY year), 0) AS yoy_growth_pct
    FROM datacenter_clean
),
yoy_stats AS (
    SELECT *,
        AVG(yoy_growth_pct) OVER (PARTITION BY country)        AS avg_growth,
        STDDEV_POP(yoy_growth_pct) OVER (PARTITION BY country) AS stddev_growth
    FROM yoy
    WHERE yoy_growth_pct IS NOT NULL
)
SELECT
    country, year, electricity_twh,
    ROUND(yoy_growth_pct, 1) AS yoy_growth_pct,
    ROUND((yoy_growth_pct - avg_growth) / NULLIF(stddev_growth, 0), 2) AS z_score
FROM yoy_stats
ORDER BY ABS((yoy_growth_pct - avg_growth) / NULLIF(stddev_growth, 0)) DESC
LIMIT 10;

-- Same technique applied to water consumption
WITH yoy AS (
    SELECT
        country, year, water_million_liters,
        100.0 * (water_million_liters - LAG(water_million_liters) OVER (PARTITION BY country ORDER BY year))
          / NULLIF(LAG(water_million_liters) OVER (PARTITION BY country ORDER BY year), 0) AS yoy_growth_pct
    FROM datacenter_clean
),
yoy_stats AS (
    SELECT *,
        AVG(yoy_growth_pct) OVER (PARTITION BY country)        AS avg_growth,
        STDDEV_POP(yoy_growth_pct) OVER (PARTITION BY country) AS stddev_growth
    FROM yoy
    WHERE yoy_growth_pct IS NOT NULL
)
SELECT
    country, year, water_million_liters,
    ROUND(yoy_growth_pct, 1) AS yoy_growth_pct,
    ROUND((yoy_growth_pct - avg_growth) / NULLIF(stddev_growth, 0), 2) AS z_score
FROM yoy_stats
ORDER BY ABS((yoy_growth_pct - avg_growth) / NULLIF(stddev_growth, 0)) DESC
LIMIT 10;


-- ============================================================================
-- PART 6: EFFICIENCY & SUSTAINABILITY TRENDS
-- ============================================================================

-- 6.1 Renewable energy adoption trend, 2018 vs 2024 (2018 chosen as baseline
--     since earlier years have reporting gaps for a few countries)
SELECT
    ROUND(AVG(renewable_energy_pct) FILTER (WHERE year = 2018), 1) AS avg_renewable_2018,
    ROUND(AVG(renewable_energy_pct) FILTER (WHERE year = 2024), 1) AS avg_renewable_2024
FROM datacenter_clean;

-- 6.2 PUE (efficiency) improvement over time — lower is better
SELECT year, ROUND(AVG(avg_pue), 3) AS avg_pue
FROM datacenter_clean
GROUP BY year
ORDER BY year;

-- 6.3 Countries improving efficiency fastest (PUE change 2015 -> 2024)
WITH endpoints AS (
    SELECT country,
           MAX(avg_pue) FILTER (WHERE year = 2015) AS pue_2015,
           MAX(avg_pue) FILTER (WHERE year = 2024) AS pue_2024
    FROM datacenter_clean
    GROUP BY country
)
SELECT country, pue_2015, pue_2024, ROUND(pue_2015 - pue_2024, 3) AS pue_improvement
FROM endpoints
ORDER BY pue_improvement DESC;


-- ============================================================================
-- PART 7: EXECUTIVE SUMMARY VIEW
-- ============================================================================

CREATE OR REPLACE VIEW datacenter_summary AS
SELECT
    (SELECT ROUND(SUM(electricity_twh),1) FROM datacenter_clean WHERE year=2024)      AS electricity_twh_2024,
    (SELECT ROUND(SUM(water_million_liters),0) FROM datacenter_clean WHERE year=2024) AS water_million_liters_2024,
    (SELECT COUNT(DISTINCT country) FROM datacenter_clean)                            AS countries_tracked,
    (SELECT ROUND(AVG(renewable_energy_pct),1) FROM datacenter_clean WHERE year=2024) AS avg_renewable_pct_2024;

SELECT * FROM datacenter_summary;

/* ============================================================================
   END OF SCRIPT
   ========================================================================= */
