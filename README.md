# Model Portfolio Analytics: PostgreSQL + Power BI

An end-to-end analytics project. Public ETF price data is loaded with Python, cleaned and modelled in PostgreSQL as a star schema, and reported in Power BI. It compares three illustrative model portfolios (Cautious, Balanced, Growth) on return, risk and drawdown.

> **Disclaimer:** The portfolios are illustrative and are not real products. Returns assume constant weights (daily rebalancing), with no fees, tax or currency effects. Prices are in USD. This is a portfolio project, not investment advice.

## Business question

How have different risk levels of model portfolio performed, and what did investors give up in drawdown to get that return?

## Key findings

Full period: January 2016 to 13 November 2026 (2,732 trading days of returns).

| Portfolio | Cumulative return | Annualised return | Annualised volatility | Max drawdown | Return per unit of risk |
|---|---|---|---|---|---|
| Cautious | 91.40% | 6.16% | 7.10% | -18.33% | 0.87 |
| Balanced | 153.60% | 8.94% | 11.56% | -23.69% | 0.77 |
| Growth | 222.11% | 11.36% | 15.46% | -31.06% | 0.74 |

- **More risk bought more return.** Growth returned 11.4% a year against 6.2% for Cautious, but with more than twice the volatility (15.5% vs 7.1%) and a deeper worst fall (-31.1% vs -18.3%).
- **The extra risk was not rewarded proportionally.** Return per unit of risk was highest for Cautious (0.87) and lowest for Growth (0.74).
- **The portfolios moved closely together until the sharp fall in early 2020.** The gap between them widened considerably in the years afterwards.

## Architecture

`yfinance -> Python (ingest_prices.py) -> PostgreSQL staging -> SQL (01_model.sql) -> analytics star schema -> Power BI`

## Data model

| Table | Type | Grain |
|---|---|---|
| dim_date | Dimension | One row per calendar day |
| dim_security | Dimension | One row per ETF (8 ETFs) |
| dim_portfolio | Dimension | One row per model portfolio (3) |
| fact_price | Fact | One row per security per trading day |
| fact_portfolio_holding | Fact | One row per portfolio per security |
| fact_portfolio_return | Fact | One row per portfolio per trading day |

![Data model](docs/model_view.png)

## Data quality and governance

- Staging checks cover duplicates, null prices, non-positive prices, extreme daily moves, portfolio weights summing to 1, and unknown tickers. Results are stored in `analytics.dq_log`.
- After the build, the fact table row count is reconciled back to staging, and every portfolio is checked for return history.
- Primary keys are enforced on every table.
- **Latest run: 7 of 8 checks passed.** The `null_prices` check flagged 8 rows (one per ETF) with missing prices on 16 November 2026, an incomplete final day from the data source. These rows were excluded from the model, and row counts reconcile to staging. The date dimension also stops at the last day with prices (13 November 2026).

## Verification

The Power BI cumulative return measure was checked against an independent pandas calculation (`verify_cumulative_return.py`). Both matched to two decimal places for all three portfolios: Cautious 91.40%, Balanced 153.60% and Growth 222.11%.

## Development and AI Workflow

I designed the end-to-end architecture, financial methodology, and data model for this project. Claude(Anthropic) was used as a development assistant to accelerate boilerplate syntax for ingestion script, SQL queries, and intial DAX expressions. All logic, edge cases, and calculations were independentaly verified and refined:

- Environment & Pipeline: Resolved local environment conflicts (such as migrating off an unstable pre-release Python build) and debugged package dependencies to ensure reliable pipeline execution.
- Data Integrity & Edge Cases: Identified and handled data anomalies like an incomplete final trading day and audited all data quality outputs.
- Model & Metric Validation: Validated relational schemas in Power BI and cross-checked DAX cumulative return measures against independent pandas calculations to guarantee financial accuracy.

## How to run

1. Install PostgreSQL, Python 3.12 and Power BI Desktop (Windows).
2. Create a PostgreSQL database called `fund_analytics`.
3. `python -m venv .venv`, activate it, then `python -m pip install -r requirements.txt`
4. Set the `DB_URL` environment variable, e.g. `postgresql+psycopg2://postgres:PASSWORD@localhost:5432/fund_analytics`
5. `python ingest_prices.py`
6. Run `01_model.sql` (in pgAdmin's Query Tool, or `psql -d fund_analytics -f 01_model.sql`)
7. Open `report/fund_analytics.pbix` and refresh. The report connects to a local PostgreSQL server, so it needs steps 1 to 6 first. Screenshots are in `docs/`. Measures are in `02_dax_measures.dax`.
8. Optional: `python verify_cumulative_return.py` repeats the verification.

## Screenshots

![Overview page](docs/overview.png)

## Limitations and next steps

- Constant-weight (daily rebalanced) portfolios, with no fees, tax or currency effects. The portfolios are illustrative.
- Max Drawdown is measured from each portfolio's own start and does not respond to the date slicer.
- One period only (2016 to 2026), so results are not a guide to future performance.
- Next steps: add an allocation and holdings page, a data quality page in the report, and move the pipeline to a cloud platform such as Microsoft Fabric.
