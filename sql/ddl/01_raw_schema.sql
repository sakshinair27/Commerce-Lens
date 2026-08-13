-- Raw landing schema: mirrors messy source-system data before cleaning.
-- Intentionally permissive (few constraints) since this represents data as
-- it arrives from upstream systems -- dbt staging models are responsible
-- for cleaning it, not this layer.
CREATE SCHEMA IF NOT EXISTS raw;

CREATE TABLE IF NOT EXISTS raw.customers_raw (
    customer_id     TEXT,
    full_name       TEXT,
    email           TEXT,
    signup_date     TEXT,          -- inconsistent formats in source data
    city            TEXT,
    state           TEXT,
    country         TEXT,
    segment         TEXT
);

CREATE TABLE IF NOT EXISTS raw.categories_raw (
    category_id         TEXT,
    category_name        TEXT,
    parent_category_id    TEXT     -- NULL/blank for top-level categories
);

CREATE TABLE IF NOT EXISTS raw.products_raw (
    product_id      TEXT,
    product_name    TEXT,
    category_id     TEXT,
    brand           TEXT,
    unit_price      TEXT,          -- sometimes "$19.99", sometimes "19.99"
    is_active       TEXT
);

CREATE TABLE IF NOT EXISTS raw.orders_raw (
    order_id        TEXT,
    customer_id     TEXT,
    order_date      TEXT,
    order_status    TEXT,
    payment_method  TEXT,
    shipping_cost   TEXT
);

CREATE TABLE IF NOT EXISTS raw.order_items_raw (
    order_item_id   TEXT,
    order_id        TEXT,
    product_id      TEXT,
    quantity        TEXT,
    unit_price      TEXT,
    discount_pct    TEXT
);

CREATE TABLE IF NOT EXISTS raw.returns_raw (
    return_id       TEXT,
    order_item_id   TEXT,
    return_date     TEXT,
    return_reason   TEXT,
    refund_amount   TEXT
);
