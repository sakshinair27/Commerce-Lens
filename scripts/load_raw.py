"""
Loads the generated CSVs into the `raw` schema as-is (no cleaning) via
psycopg2's fast COPY. This represents the "data as it lands from source
systems" state that dbt staging models are responsible for cleaning.
"""
import os

import psycopg2

DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data")

TABLES = {
    "raw.categories_raw": ("categories.csv", ["category_id", "category_name", "parent_category_id"]),
    "raw.customers_raw": ("customers.csv", ["customer_id", "full_name", "email", "signup_date", "city", "state", "country", "segment"]),
    "raw.products_raw": ("products.csv", ["product_id", "product_name", "category_id", "brand", "unit_price", "is_active"]),
    "raw.orders_raw": ("orders.csv", ["order_id", "customer_id", "order_date", "order_status", "payment_method", "shipping_cost"]),
    "raw.order_items_raw": ("order_items.csv", ["order_item_id", "order_id", "product_id", "quantity", "unit_price", "discount_pct"]),
    "raw.returns_raw": ("returns.csv", ["return_id", "order_item_id", "return_date", "return_reason", "refund_amount"]),
}


def load(conn_str: str):
    conn = psycopg2.connect(conn_str)
    cur = conn.cursor()
    for table, (filename, cols) in TABLES.items():
        cur.execute(f"TRUNCATE {table};")
        path = os.path.join(DATA_DIR, filename)
        with open(path) as f:
            cur.copy_expert(f"COPY {table} ({', '.join(cols)}) FROM STDIN WITH CSV HEADER", f)
        conn.commit()
        cur.execute(f"SELECT count(*) FROM {table};")
        print(f"{table}: {cur.fetchone()[0]} rows loaded")
    cur.close()
    conn.close()


if __name__ == "__main__":
    import sys

    conn_str = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("DATABASE_URL", "postgresql://commercelens:commercelens@localhost:5432/commercelens")
    load(conn_str)
