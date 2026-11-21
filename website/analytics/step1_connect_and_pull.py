"""
Step 1: Connect to capstone_db and pull the raw data we'll analyze later.
No analysis yet -- just proving the connection works and looking at real rows.
"""

import mysql.connector
import pandas as pd

# ---- Update these if your XAMPP MySQL setup is different ----
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",       # default XAMPP has no password
    "database": "capstone_db",
}

def get_connection():
    return mysql.connector.connect(**DB_CONFIG)


def pull_search_logs():
    conn = get_connection()
    query = """
        SELECT SRCH_ID, SRCH_KEYWORD, SRCH_FILTERS, SRCH_CREATED_AT, USR_ID
        FROM search_log
        ORDER BY SRCH_CREATED_AT DESC
    """
    df = pd.read_sql(query, conn)
    conn.close()
    return df


def pull_listings():
    conn = get_connection()
    query = """
        SELECT
            l.LST_ID,
            l.LST_STATUS,
            l.LST_HARVEST_DATE,
            l.LST_CREATED_AT,
            l.CAT_ID,
            c.CAT_NAME
        FROM listing l
        JOIN crop_category c ON l.CAT_ID = c.CAT_ID
        ORDER BY l.LST_CREATED_AT DESC
    """
    df = pd.read_sql(query, conn)
    conn.close()
    return df


if __name__ == "__main__":
    print("Pulling search_log...")
    searches = pull_search_logs()
    print(searches.head(10))
    print(f"Total search rows: {len(searches)}\n")

    print("Pulling listing (joined with crop_category)...")
    listings = pull_listings()
    print(listings.head(10))
    print(f"Total listing rows: {len(listings)}")