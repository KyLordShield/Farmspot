"""
Step 3: Save step2's computed insights into the `insight` and `trend` tables.

This is the final bridge in the analytics pipeline:
    step1 (pull raw rows)  ->  step2 (compute with pandas)  ->  step3 (save to DB)

How it works:
    1. Re-use step2's compute functions to get today's numbers.
    2. Wipe the OLD snapshot rows (delete-then-insert = "snapshot" pattern, so
       re-running this daily never stacks up duplicate history).
    3. Write the fresh numbers:
         - "Top Searched This Week" -> one `insight` row holding the ranked
           list as JSON in INS_CONTENT.
         - "Listings by Category"    -> one `insight` row holding ranked
           category counts as JSON in INS_CONTENT.
         - Seasonal trends           -> one `trend` row per month, crops as
           JSON in TRND_DATA, TRND_PERIOD_MONTH = "2026-09" (sortable key).
"""

import json
import random
import string

import mysql.connector
from step2_compute_insights import (
    listings_by_category,
    seasonal_trends,
    top_searched_this_week,
)

# Same connection settings as the other scripts (XAMPP default: no password).
DB_CONFIG = {
    "host": "localhost",
    "user": "root",
    "password": "",       # default XAMPP has no password
    "database": "capstone_db",
}


def get_connection():
    return mysql.connector.connect(**DB_CONFIG)


def new_id(connection, table, column, length=6):
    """
    Creates a unique 6-character code (uppercase letters + digits) that is not
    already used as the primary key of `table`.`column`.
    Why? Every table here (insight, trend, search_log, listing, ...) uses that
    style of ID ('INS_D23A1B'), so step3 must make the same kind to stay
    consistent. Random + unique-check loop is a common way to fake it.
    """
    cursor = connection.cursor()
    try:
        while True:
            candidate = "".join(
                random.choices(string.ascii_uppercase + string.digits, k=length)
            )
            cursor.execute(
                f"SELECT COUNT(*) FROM {table} WHERE {column} = %s",
                (candidate,),
            )
            if cursor.fetchone()[0] == 0:
                return candidate
    finally:
        cursor.close()


def save_insights():
    connection = get_connection()
    cursor = connection.cursor()
    try:
        # 1) Wipe last run's snapshot so re-running never duplicates.
        cursor.execute("DELETE FROM insight")
        cursor.execute("DELETE FROM trend")

        # 2) ---------- TOP SEARCHED THIS WEEK ----------
        # step2 returns a tiny table: crop | search_count (top 4).
        top = top_searched_this_week()
        if top.empty:
            # No searches in the last 7 days -> keep the insight table empty.
            # An empty analysis table is CORRECT: showing stale guesses would
            # be worse than showing "no data yet".
            print("No top-searched data this week (no searches in 7 days).")
        else:
            # Turn the table into a list of dicts, then into one JSON string
            # that the whole ranked list nests inside a single row.
            rows = [
                {"rank": i + 1, "crop": row["crop"], "count": int(row["search_count"])}
                for i, row in top.iterrows()
            ]
            cursor.execute(
                """
                INSERT INTO insight
                    (INS_ID, INS_TITLE, INS_CONTENT, INS_CREATED_AT, CAT_ID, SRCH_ID)
                VALUES (%s, %s, %s, NOW(), NULL, NULL)
                """,
                (
                    new_id(connection, "insight", "INS_ID"),
                    "Top Searched This Week",
                    json.dumps(rows),
                ),
            )
            print(f"Saved {len(rows)} top-searched crops.")

        # 3) ---------- SEASONAL TRENDS ----------
        # step2 returns one row per month: month | month_key | crops.
        trends = seasonal_trends()
        if trends.empty:
            print("No seasonal trends (no listings with harvest dates).")
        else:
            for _, row in trends.iterrows():
                # 'month_key' is "2026-09" (sortable code), 'month' is
                # "September" (human label) and 'crops' is "Eggplant, Basil".
                crops = [c.strip() for c in row["crops"].split(",")]
                cursor.execute(
                    """
                    INSERT INTO trend
                        (TRND_ID, TRND_TITLE, TRND_DATA, TRND_PERIOD_MONTH,
                         TRND_CREATED_AT, CAT_ID)
                    VALUES (%s, %s, %s, %s, NOW(), NULL)
                    """,
                    (
                        new_id(connection, "trend", "TRND_ID"),
                        row["month"],
                        json.dumps(crops),
                        row["month_key"],
                    ),
                )
            print(f"Saved {len(trends)} seasonal trend months.")

        # 3b) ---------- LISTINGS BY CATEGORY ----------
        # Same shape as Top Searched: one insight row holding a ranked JSON list.
        cats = listings_by_category()
        if cats.empty:
            print("No active listings by category.")
        else:
            rows = [
                {
                    "rank": i + 1,
                    "category": row["category"],
                    "listing_count": int(row["listing_count"]),
                }
                for i, row in cats.iterrows()
            ]
            cursor.execute(
                """
                INSERT INTO insight
                    (INS_ID, INS_TITLE, INS_CONTENT, INS_CREATED_AT, CAT_ID, SRCH_ID)
                VALUES (%s, %s, %s, NOW(), NULL, NULL)
                """,
                (
                    new_id(connection, "insight", "INS_ID"),
                    "Listings by Category",
                    json.dumps(rows),
                ),
            )
            print(f"Saved {len(rows)} category counts.")

        # 4) Commit = make ALL the inserts above permanent together. Without
        #    this, nothing is actually written to the database.
        connection.commit()

    except Exception as e:
        # Roll back = undo everything since commit, so a partially-finished
        # run can never leave the tables half-written.
        connection.rollback()
        raise e
    finally:
        cursor.close()
        connection.close()


if __name__ == "__main__":
    save_insights()
    print("Done writing insights to the database.")