# Model Portfolio Analytics: PostgreSQL + Power BI

An end-to-end analytics project: public ETF price data is loaded with Python,
cleaned and modelled in PostgreSQL as a star schema, and reported in Power BI.
It compares three illustrative model portfolios (Cautious, Balanced, Growth)
on return, risk and drawdown.

> **Disclaimer:** The portfolios are illustrative and are not real products.
> Returns assume constant weights (daily rebalancing), with no fees, tax or
> currency effects. This is a portfolio project, not investment advice.

## Business question
[One sentence, e.g. "How have different risk levels of model portfolio
performed, and what did investors give up in drawdown to get that return?"]

## Key findings
- [Finding 1 with a number, e.g. Growth returned X% annualised vs Y% for Cautious, with a max drawdown of Z%]
- [Finding 2]
- [Finding 3]

## Architecture
`yfinance -> Python (ingest_prices.py) -> PostgreSQL staging -> SQL (01_model.sql) -> analytics star schema -> Power BI`

## Data model
| Table | Type | Grain |
|---|---|---|
| dim_date | Dimension | One row per calendar day |
| dim_security | Dimension | One row per ETF |
| dim_portfolio | Dimension | One row per model portfolio |
| fact_price | Fact | One row per security per trading day |
| fact_portfolio_holding | Fact | One row per portfolio per security |
| fact_portfolio_return | Fact | One row per portfolio per trading day |

[Add a screenshot of the Power BI model view here: `docs/model_view.png`]

## Data quality and governance
- Staging checks (duplicates, nulls, non-positive prices, extreme moves, weights summing to 1) are logged in `analytics.dq_log`.
- The star schema is reconciled back to staging row counts after each build.
- Primary keys are enforced on every table.
- Results are surfaced on a Data Quality page in the report.

## How to run
1. `python -m venv .venv` and activate it, then `pip install -r requirements.txt`
2. Create a PostgreSQL database called `fund_analytics`
3. Set the `DB_URL` environment variable, e.g. `postgresql+psycopg2://postgres:PASSWORD@localhost:5432/fund_analytics`
4. `python ingest_prices.py`
5. `psql -d fund_analytics -f 01_model.sql`
6. Open `report/fund_analytics.pbix` and refresh. Measures are listed in `02_dax_measures.dax`.

## Use of AI
I used [tool name] for: [e.g. drafting first-pass DAX measures, reviewing SQL, writing the data dictionary].
Every output was checked before use:
- [e.g. DAX cumulative return compared against a Python/pandas calculation: matched to 4 decimal places]
- [e.g. an AI-suggested drawdown formula was wrong for X, so I changed it to Y]

## Screenshots
[Add report page screenshots in `docs/`]

## Limitations and next steps
- Constant-weight simplification; no transaction costs or currency effects
- [Next step, e.g. add a Microsoft Fabric lakehouse, automate refresh, add CI checks for the SQL]
