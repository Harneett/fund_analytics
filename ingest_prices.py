"""
ingest_prices.py
Downloads daily ETF prices (Yahoo Finance via yfinance) and loads them, plus the
security reference data and illustrative model-portfolio weights, into the
PostgreSQL 'staging' schema.

Usage:
    set the DB_URL environment variable (see README), then:  python ingest_prices.py
"""
import os
import pandas as pd
import yfinance as yf
from sqlalchemy import create_engine, text

START_DATE = "2016-01-01"
DB_URL = os.environ.get(
    "DB_URL",
    "postgresql+psycopg2://postgres:CHANGE_ME@localhost:5432/fund_analytics",
)

# Reference data: ticker, name, asset class, region.
# Prices are in USD. To use LSE-listed ETFs instead, swap in '.L' tickers,
# but check each one actually returns data before relying on it.
SECURITIES = pd.DataFrame(
    [
        ("VT",  "Vanguard Total World Stock ETF",        "Equity",       "Global"),
        ("SPY", "SPDR S&P 500 ETF",                      "Equity",       "North America"),
        ("EFA", "iShares MSCI EAFE ETF",                 "Equity",       "Developed ex-US"),
        ("EEM", "iShares MSCI Emerging Markets ETF",     "Equity",       "Emerging Markets"),
        ("AGG", "iShares Core US Aggregate Bond ETF",    "Fixed Income", "North America"),
        ("BND", "Vanguard Total Bond Market ETF",        "Fixed Income", "North America"),
        ("GLD", "SPDR Gold Shares",                      "Commodities",  "Global"),
        ("VNQ", "Vanguard Real Estate ETF",              "Property",     "North America"),
    ],
    columns=["ticker", "security_name", "asset_class", "region"],
)

# ILLUSTRATIVE model portfolios (not real products). Each must sum to 1.0.
WEIGHTS = pd.DataFrame(
    [
        ("Cautious", "AGG", 0.40), ("Cautious", "BND", 0.20), ("Cautious", "VT", 0.15),
        ("Cautious", "SPY", 0.10), ("Cautious", "GLD", 0.10), ("Cautious", "VNQ", 0.05),
        ("Balanced", "VT", 0.30),  ("Balanced", "SPY", 0.15), ("Balanced", "EFA", 0.10),
        ("Balanced", "EEM", 0.05), ("Balanced", "AGG", 0.20), ("Balanced", "BND", 0.10),
        ("Balanced", "GLD", 0.05), ("Balanced", "VNQ", 0.05),
        ("Growth", "VT", 0.35),    ("Growth", "SPY", 0.25),   ("Growth", "EFA", 0.15),
        ("Growth", "EEM", 0.10),   ("Growth", "VNQ", 0.05),   ("Growth", "AGG", 0.05),
        ("Growth", "GLD", 0.05),
    ],
    columns=["portfolio_name", "ticker", "weight"],
)


def fetch_prices(ticker: str) -> pd.DataFrame:
    df = yf.Ticker(ticker).history(start=START_DATE, auto_adjust=False)
    if df.empty:
        raise ValueError(f"No data returned for {ticker}")
    df = df.reset_index()
    df["trade_date"] = pd.to_datetime(df["Date"]).dt.tz_localize(None).dt.date
    df = df.rename(
        columns={
            "Open": "open_price",
            "High": "high_price",
            "Low": "low_price",
            "Close": "close_price",
            "Adj Close": "adj_close",
            "Volume": "volume",
        }
    )
    df["ticker"] = ticker
    return df[
        ["ticker", "trade_date", "open_price", "high_price",
         "low_price", "close_price", "adj_close", "volume"]
    ]


def main() -> None:
    frames = []
    for t in SECURITIES["ticker"]:
        print(f"Downloading {t} ...")
        frames.append(fetch_prices(t))
    prices = pd.concat(frames, ignore_index=True)
    prices["loaded_at"] = pd.Timestamp.now()

    # Keep a raw copy so the project is reproducible without re-downloading
    os.makedirs("data/raw", exist_ok=True)
    prices.to_csv("data/raw/prices_raw.csv", index=False)

    engine = create_engine(DB_URL)
    with engine.begin() as conn:
        conn.execute(text("CREATE SCHEMA IF NOT EXISTS staging"))
        conn.execute(text("CREATE SCHEMA IF NOT EXISTS analytics"))

    prices.to_sql("stg_prices", engine, schema="staging",
                  if_exists="replace", index=False, chunksize=5000)
    SECURITIES.to_sql("stg_securities", engine, schema="staging",
                      if_exists="replace", index=False)
    WEIGHTS.to_sql("stg_weights", engine, schema="staging",
                   if_exists="replace", index=False)

    print(f"Loaded {len(prices):,} price rows, {len(SECURITIES)} securities, "
          f"{len(WEIGHTS)} portfolio weights.")


if __name__ == "__main__":
    main()
