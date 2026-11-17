"""
verify_cumulative_return.py
Independent check of the Power BI 'Cumulative Return' measure.
Recomputes each model portfolio's cumulative return in pandas from the raw
price file, using the same simplifications as the SQL model
(constant weights, daily rebalancing, no fees).

Run from the project folder with the virtual environment active:
    python verify_cumulative_return.py
"""
import pandas as pd
from ingest_prices import WEIGHTS

prices = pd.read_csv("data/raw/prices_raw.csv", parse_dates=["trade_date"])

# Same cleaning rule as the SQL model: drop rows with missing prices
prices = prices.dropna(subset=["adj_close", "close_price"])

wide = prices.pivot(index="trade_date", columns="ticker", values="adj_close")
returns = wide.pct_change(fill_method=None)

for name, w in WEIGHTS.groupby("portfolio_name"):
    weights = w.set_index("ticker")["weight"]
    r = returns[weights.index].dropna()          # days where every holding has a return
    daily = (r * weights).sum(axis=1)
    cumulative = (1 + daily).prod() - 1
    print(f"{name}: cumulative return {cumulative:.4f} ({cumulative:.2%}) over {len(daily):,} days")
