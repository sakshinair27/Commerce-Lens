#!/bin/bash
# Runs automatically on first container start (Postgres's official image
# executes every script in docker-entrypoint-initdb.d/ once, against a
# fresh data directory). Applies the full DDL, loads the raw CSVs, and runs
# the ETL, so `docker compose up` alone gets you a populated warehouse --
# no manual steps required.
set -euo pipefail

echo "[init] applying DDL..."
for f in /sql/ddl/01_raw_schema.sql /sql/ddl/02_warehouse_schema.sql /sql/ddl/03_triggers.sql /sql/ddl/04_procedures.sql; do
    echo "[init]   $f"
    psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f "$f"
done

echo "[init] loading raw CSVs..."
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-EOSQL
    \copy raw.categories_raw (category_id, category_name, parent_category_id) FROM '/data/categories.csv' WITH (FORMAT csv, HEADER true)
    \copy raw.customers_raw (customer_id, full_name, email, signup_date, city, state, country, segment) FROM '/data/customers.csv' WITH (FORMAT csv, HEADER true)
    \copy raw.products_raw (product_id, product_name, category_id, brand, unit_price, is_active) FROM '/data/products.csv' WITH (FORMAT csv, HEADER true)
    \copy raw.orders_raw (order_id, customer_id, order_date, order_status, payment_method, shipping_cost) FROM '/data/orders.csv' WITH (FORMAT csv, HEADER true)
    \copy raw.order_items_raw (order_item_id, order_id, product_id, quantity, unit_price, discount_pct) FROM '/data/order_items.csv' WITH (FORMAT csv, HEADER true)
    \copy raw.returns_raw (return_id, order_item_id, return_date, return_reason, refund_amount) FROM '/data/returns.csv' WITH (FORMAT csv, HEADER true)
EOSQL

echo "[init] running ETL (raw -> warehouse)..."
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -f /sql/etl/05_load_warehouse.sql

echo "[init] refreshing customer_summary..."
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CALL warehouse.sp_refresh_customer_summary();"

echo "[init] done. warehouse is ready."
