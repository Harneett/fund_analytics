-- 01_model.sql
-- Validates staging data, builds the star schema in the 'analytics' schema,
-- and reconciles the result back to staging. Requires PostgreSQL 12+.
-- Run with:  psql -d fund_analytics -f 01_model.sql

CREATE SCHEMA IF NOT EXISTS analytics;

-- =====================================================================
-- 1. DATA QUALITY CHECKS ON STAGING (results stored in analytics.dq_log)
-- =====================================================================
DROP TABLE IF EXISTS analytics.dq_log;
CREATE TABLE analytics.dq_log (
    check_name   text,
    failing_rows integer,
    status       text GENERATED ALWAYS AS
                 (CASE WHEN failing_rows = 0 THEN 'PASS' ELSE 'REVIEW' END) STORED,
    run_at       timestamp DEFAULT now()
);

INSERT INTO analytics.dq_log (check_name, failing_rows)
SELECT 'duplicate_ticker_date', COUNT(*) FROM (
    SELECT 1 FROM staging.stg_prices
    GROUP BY ticker, trade_date HAVING COUNT(*) > 1) d;

INSERT INTO analytics.dq_log (check_name, failing_rows)
SELECT 'null_prices', COUNT(*) FROM staging.stg_prices
WHERE close_price IS NULL OR adj_close IS NULL;

INSERT INTO analytics.dq_log (check_name, failing_rows)
SELECT 'non_positive_prices', COUNT(*) FROM staging.stg_prices
WHERE close_price <= 0 OR adj_close <= 0;

INSERT INTO analytics.dq_log (check_name, failing_rows)
SELECT 'extreme_daily_moves_over_25pct', COUNT(*) FROM (
    SELECT adj_close / NULLIF(LAG(adj_close) OVER
           (PARTITION BY ticker ORDER BY trade_date), 0) - 1 AS r
    FROM staging.stg_prices) x
WHERE ABS(r) > 0.25;

INSERT INTO analytics.dq_log (check_name, failing_rows)
SELECT 'portfolio_weights_not_summing_to_1', COUNT(*) FROM (
    SELECT portfolio_name FROM staging.stg_weights
    GROUP BY portfolio_name HAVING ABS(SUM(weight) - 1) > 0.0001) w;

INSERT INTO analytics.dq_log (check_name, failing_rows)
SELECT 'weights_with_unknown_ticker', COUNT(*) FROM staging.stg_weights w
WHERE NOT EXISTS (SELECT 1 FROM staging.stg_securities s WHERE s.ticker = w.ticker);

-- Look at the log before continuing. Investigate anything marked REVIEW.
SELECT * FROM analytics.dq_log;

-- =====================================================================
-- 2. BUILD THE STAR SCHEMA
-- =====================================================================
DROP TABLE IF EXISTS analytics.fact_portfolio_return CASCADE;
DROP TABLE IF EXISTS analytics.fact_portfolio_holding CASCADE;
DROP TABLE IF EXISTS analytics.fact_price CASCADE;
DROP TABLE IF EXISTS analytics.dim_portfolio CASCADE;
DROP TABLE IF EXISTS analytics.dim_security CASCADE;
DROP TABLE IF EXISTS analytics.dim_date CASCADE;

-- Security dimension
CREATE TABLE analytics.dim_security AS
SELECT ROW_NUMBER() OVER (ORDER BY ticker) AS security_key,
       ticker, security_name, asset_class, region
FROM staging.stg_securities;
ALTER TABLE analytics.dim_security ADD PRIMARY KEY (security_key);

-- Date dimension (calendar days across the price history)
CREATE TABLE analytics.dim_date AS
SELECT TO_CHAR(d, 'YYYYMMDD')::int       AS date_key,
       d::date                           AS date,
       EXTRACT(YEAR FROM d)::int         AS year,
       EXTRACT(QUARTER FROM d)::int      AS quarter,
       EXTRACT(MONTH FROM d)::int        AS month_number,
       TO_CHAR(d, 'Mon')                 AS month_name,
       TO_CHAR(d, 'YYYY-MM')             AS year_month,
       (EXTRACT(ISODOW FROM d) <= 5)     AS is_weekday
FROM generate_series(
        (SELECT MIN(trade_date) FROM staging.stg_prices),
        (SELECT MAX(trade_date) FROM staging.stg_prices WHERE adj_close IS NOT NULL),
        interval '1 day') AS d;
ALTER TABLE analytics.dim_date ADD PRIMARY KEY (date_key);

-- Portfolio dimension
CREATE TABLE analytics.dim_portfolio AS
SELECT ROW_NUMBER() OVER (ORDER BY risk_rank) AS portfolio_key,
       portfolio_name, risk_rank
FROM (SELECT DISTINCT portfolio_name,
             CASE portfolio_name WHEN 'Cautious' THEN 1
                                 WHEN 'Balanced' THEN 2
                                 WHEN 'Growth'   THEN 3 END AS risk_rank
      FROM staging.stg_weights) p;
ALTER TABLE analytics.dim_portfolio ADD PRIMARY KEY (portfolio_key);

-- Price fact: de-duplicated, invalid prices removed, daily return added
CREATE TABLE analytics.fact_price AS
WITH cleaned AS (
    SELECT DISTINCT ON (ticker, trade_date) *
    FROM staging.stg_prices
    WHERE adj_close > 0 AND close_price > 0
    ORDER BY ticker, trade_date
)
SELECT TO_CHAR(c.trade_date, 'YYYYMMDD')::int AS date_key,
       s.security_key,
       c.close_price,
       c.adj_close,
       c.volume,
       c.adj_close / NULLIF(LAG(c.adj_close) OVER
           (PARTITION BY c.ticker ORDER BY c.trade_date), 0) - 1 AS daily_return
FROM cleaned c
JOIN analytics.dim_security s ON s.ticker = c.ticker;
ALTER TABLE analytics.fact_price ADD PRIMARY KEY (date_key, security_key);

-- Holdings fact: portfolio weights by security
CREATE TABLE analytics.fact_portfolio_holding AS
SELECT p.portfolio_key, s.security_key, w.weight
FROM staging.stg_weights w
JOIN analytics.dim_portfolio p ON p.portfolio_name = w.portfolio_name
JOIN analytics.dim_security  s ON s.ticker = w.ticker;
ALTER TABLE analytics.fact_portfolio_holding ADD PRIMARY KEY (portfolio_key, security_key);

-- Portfolio return fact.
-- SIMPLIFICATION: weights are held constant (rebalanced daily), no fees or tax.
-- A day only counts if every holding has a return that day.
CREATE TABLE analytics.fact_portfolio_return AS
WITH daily AS (
    SELECT f.date_key, h.portfolio_key,
           SUM(h.weight * f.daily_return) AS daily_return
    FROM analytics.fact_price f
    JOIN analytics.fact_portfolio_holding h ON h.security_key = f.security_key
    WHERE f.daily_return IS NOT NULL
    GROUP BY f.date_key, h.portfolio_key
    HAVING COUNT(*) = (SELECT COUNT(*) FROM analytics.fact_portfolio_holding x
                       WHERE x.portfolio_key = h.portfolio_key)
),
idx AS (
    SELECT date_key, portfolio_key, daily_return,
           EXP(SUM(LN(1 + daily_return)) OVER
               (PARTITION BY portfolio_key ORDER BY date_key)) AS growth_index
    FROM daily
)
SELECT date_key, portfolio_key, daily_return, growth_index,
       growth_index / MAX(growth_index) OVER
           (PARTITION BY portfolio_key ORDER BY date_key) - 1 AS drawdown
FROM idx;
ALTER TABLE analytics.fact_portfolio_return ADD PRIMARY KEY (date_key, portfolio_key);

-- =====================================================================
-- 3. RECONCILE BACK TO STAGING
-- =====================================================================
INSERT INTO analytics.dq_log (check_name, failing_rows)
SELECT 'fact_price_rowcount_vs_staging', ABS(
    (SELECT COUNT(*) FROM analytics.fact_price) -
    (SELECT COUNT(*) FROM (
        SELECT DISTINCT ticker, trade_date FROM staging.stg_prices
        WHERE adj_close > 0 AND close_price > 0) d));

INSERT INTO analytics.dq_log (check_name, failing_rows)
SELECT 'portfolios_without_return_history', COUNT(*) FROM analytics.dim_portfolio p
WHERE NOT EXISTS (SELECT 1 FROM analytics.fact_portfolio_return r
                  WHERE r.portfolio_key = p.portfolio_key);

SELECT * FROM analytics.dq_log ORDER BY run_at, check_name;
