"""
Loads the generated CSVs into Snowflake's `raw` schema via PUT + COPY INTO
-- the Snowflake equivalent of load_raw.py's psycopg2 COPY FROM STDIN.
Snowflake has no COPY FROM STDIN; the real mechanism is: stage the local
file (PUT), then bulk-load it server-side from the stage (COPY INTO).

TABLES mirrors load_raw.py's mapping exactly (filenames/columns) so the
two ingestion paths stay in sync and produce equivalent raw data -- dbt
staging models do the real cleaning either way, same as the Postgres
path. Deliberately NOT imported from load_raw.py: that module imports
psycopg2, which this script has no other reason to depend on.

Verified manually against a real Snowflake trial account before being
wired into the Airflow DAG (see ../results/ and the root README's
Snowflake portability section for the manual-load verification this
script replaces with automation).
"""
import os

import snowflake.connector

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")

TABLES = {
    "raw.categories_raw": ("categories.csv", ["category_id", "category_name", "parent_category_id"]),
    "raw.customers_raw": ("customers.csv", ["customer_id", "full_name", "email", "signup_date", "city", "state", "country", "segment"]),
    "raw.products_raw": ("products.csv", ["product_id", "product_name", "category_id", "brand", "unit_price", "is_active"]),
    "raw.orders_raw": ("orders.csv", ["order_id", "customer_id", "order_date", "order_status", "payment_method", "shipping_cost"]),
    "raw.order_items_raw": ("order_items.csv", ["order_item_id", "order_id", "product_id", "quantity", "unit_price", "discount_pct"]),
    "raw.returns_raw": ("returns.csv", ["return_id", "order_item_id", "return_date", "return_reason", "refund_amount"]),
}


def load(account: str, user: str, password: str, role: str, database: str, warehouse: str, schema: str = "raw"):
    conn = snowflake.connector.connect(
        account=account,
        user=user,
        password=password,
        role=role,
        warehouse=warehouse,
        database=database,
        schema=schema,
    )
    cur = conn.cursor()
    try:
        for table, (filename, cols) in TABLES.items():
            # TABLES keys are "raw.<table>_raw" (matches load_raw.py); once
            # connected with schema=raw above, the bare table name is enough.
            table_name = table.split(".", 1)[1]
            local_path = os.path.join(DATA_DIR, filename).replace("\\", "/")

            cur.execute(f"TRUNCATE TABLE {table_name};")
            # OVERWRITE so re-running this script (e.g. a retried Airflow
            # task) doesn't fail on a stage file that's already there.
            cur.execute(f"PUT file://{local_path} @%{table_name} OVERWRITE = TRUE AUTO_COMPRESS = TRUE;")
            cur.execute(
                f"""
                COPY INTO {table_name} ({', '.join(cols)})
                FROM @%{table_name}/{filename}.gz
                FILE_FORMAT = (TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY = '"')
                ON_ERROR = 'ABORT_STATEMENT';
                """
            )
            cur.execute(f"SELECT count(*) FROM {table_name};")
            print(f"{table}: {cur.fetchone()[0]} rows loaded")
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    load(
        account=os.environ["DBT_SF_ACCOUNT"],
        user=os.environ["DBT_SF_USER"],
        password=os.environ["DBT_SF_PASSWORD"],
        role=os.environ.get("DBT_SF_ROLE", ""),
        database=os.environ["DBT_SF_DATABASE"],
        warehouse=os.environ["DBT_SF_WAREHOUSE"],
        schema=os.environ.get("DBT_SF_RAW_SCHEMA", "raw"),
    )
