"""
Step 2: Turn the raw data into the two metrics the Insights screen needs:
  1. Top Searched This Week   -> from search_log
  2. Seasonal Trends by Month -> from listing

Still just prints results for now. Saving them into the `insight`/`trend`
tables comes in Step 3.
"""

import mysql.connector
import pandas as pd
from datetime import datetime, timedelta

DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",
    "database": "capstone_db",
}


def get_connection():
    return mysql.connector.connect(**DB_CONFIG)


def top_searched_this_week(top_n=4):
    conn = get_connection()
    query = """
        SELECT SRCH_KEYWORD, SRCH_CREATED_AT
        FROM search_log
        WHERE SRCH_CREATED_AT >= %s
    """
    one_week_ago = datetime.now() - timedelta(days=7)
    df = pd.read_sql(query, conn, params=(one_week_ago,))
    conn.close()

    if df.empty:
        return pd.DataFrame(columns=["crop", "search_count"])

    # Normalize casing so "Carrot" and "carrot" count as the same thing
    df["SRCH_KEYWORD"] = df["SRCH_KEYWORD"].str.strip().str.lower()

    counts = (
        df.groupby("SRCH_KEYWORD")
        .size()
        .reset_index(name="search_count")
        .sort_values("search_count", ascending=False)
        .head(top_n)
        .rename(columns={"SRCH_KEYWORD": "crop"})
    )
    return counts.reset_index(drop=True)


def seasonal_trends(top_n_per_month=3):
    conn = get_connection()
    query = """
        SELECT LST_CROP_ICON, LST_HARVEST_DATE
        FROM listing
        WHERE LST_HARVEST_DATE IS NOT NULL
    """
    df = pd.read_sql(query, conn)
    conn.close()

    if df.empty:
        return pd.DataFrame(columns=["month", "crops"])

    # Filter out test/junk entries
    df = df[~df["LST_CROP_ICON"].str.contains("test", case=False, na=True)]

    df["LST_HARVEST_DATE"] = pd.to_datetime(df["LST_HARVEST_DATE"])
    # Two formats of the same date on purpose:
    #   month     = "September"   -> what humans see on screen
    #   month_key = "2026-09"     -> what machines sort chronologically
    df["month"] = df["LST_HARVEST_DATE"].dt.strftime("%B")  # e.g. "March"
    df["month_key"] = df["LST_HARVEST_DATE"].dt.strftime("%Y-%m")  # e.g. "2026-03"
    df["crop"] = df["LST_CROP_ICON"].str.strip().str.lower()

    # Count how many listings of each crop exist per month
    monthly_counts = (
        df.groupby(["month", "month_key", "crop"]).size().reset_index(name="count")
    )

    # For each month, take the top N crops by count
    results = []
    for (month, month_key), group in monthly_counts.groupby(["month", "month_key"]):
        top_crops = group.sort_values("count", ascending=False).head(top_n_per_month)
        crop_list = ", ".join(top_crops["crop"].str.capitalize())
        results.append({
            "month": month,
            "month_key": month_key,
            "crops": crop_list,
        })

    return pd.DataFrame(results)


def listings_by_category(top_n=5):
    conn = get_connection()
    query = """
        SELECT LST_ID, LST_STATUS, CAT_NAME
        FROM listing
        JOIN crop_category ON listing.CAT_ID = crop_category.CAT_ID
        WHERE LST_STATUS IN ('AVAILABLE_NOW', 'SOON_TO_HARVEST')
    """
    df = pd.read_sql(query, conn)
    conn.close()

    if df.empty:
        return pd.DataFrame(columns=["category", "listing_count"])

    counts = (
        df["CAT_NAME"]
        .value_counts()
        .rename_axis("category")
        .head(top_n)
        .reset_index(name="listing_count")
    )
    return counts.reset_index(drop=True)


if __name__ == "__main__":
    print("=== Top Searched This Week ===")
    top = top_searched_this_week()
    print(top if not top.empty else "No searches in the last 7 days.")

    print("\n=== Seasonal Trends by Month ===")
    trends = seasonal_trends()
    print(trends if not trends.empty else "No listings with harvest dates.")

    print("\n=== Listings by Category ===")
    cats = listings_by_category()
    print(cats if not cats.empty else "No active listings.")