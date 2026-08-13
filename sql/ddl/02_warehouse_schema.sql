-- Governed warehouse schema (star schema). This is what dbt marts build
-- into, and what fact/dim modeling questions in interviews are about.
CREATE SCHEMA IF NOT EXISTS warehouse;

CREATE TABLE IF NOT EXISTS warehouse.dim_date (
    date_key        INT PRIMARY KEY,           -- YYYYMMDD
    full_date       DATE NOT NULL UNIQUE,
    year             INT NOT NULL,
    quarter          INT NOT NULL,
    month            INT NOT NULL,
    day              INT NOT NULL,
    day_of_week      INT NOT NULL,
    is_weekend       BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS warehouse.dim_category (
    category_key         SERIAL PRIMARY KEY,
    category_id          TEXT NOT NULL UNIQUE,
    category_name        TEXT NOT NULL,
    parent_category_id   TEXT REFERENCES warehouse.dim_category(category_id) DEFERRABLE INITIALLY DEFERRED
);
-- self-referencing FK on a natural key requires category_id to be unique first;
-- see 05_category_fk.sql for the deferred constraint pattern used at load time.

CREATE TABLE IF NOT EXISTS warehouse.dim_customer (
    customer_key    SERIAL PRIMARY KEY,
    customer_id     TEXT NOT NULL UNIQUE,
    full_name       TEXT NOT NULL,
    email           TEXT,
    signup_date     DATE,
    city            TEXT,
    state           TEXT,
    country         TEXT,
    segment         TEXT,
    updated_at      TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS warehouse.dim_product (
    product_key     SERIAL PRIMARY KEY,
    product_id      TEXT NOT NULL UNIQUE,
    product_name    TEXT NOT NULL,
    category_id     TEXT REFERENCES warehouse.dim_category(category_id),
    brand           TEXT,
    unit_price      NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    is_active       BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE IF NOT EXISTS warehouse.fact_orders (
    order_key        SERIAL PRIMARY KEY,
    order_id         TEXT NOT NULL UNIQUE,
    customer_key     INT NOT NULL REFERENCES warehouse.dim_customer(customer_key),
    order_date_key   INT NOT NULL REFERENCES warehouse.dim_date(date_key),
    order_status     TEXT NOT NULL CHECK (order_status IN ('placed','shipped','delivered','cancelled','returned')),
    payment_method   TEXT,
    shipping_cost    NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (shipping_cost >= 0),
    total_amount     NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    created_at       TIMESTAMP NOT NULL DEFAULT now(),
    updated_at       TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS warehouse.fact_order_items (
    order_item_key   SERIAL PRIMARY KEY,
    order_key        INT NOT NULL REFERENCES warehouse.fact_orders(order_key),
    product_key      INT NOT NULL REFERENCES warehouse.dim_product(product_key),
    quantity         INT NOT NULL CHECK (quantity > 0),
    unit_price       NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),
    discount_pct     NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (discount_pct BETWEEN 0 AND 100),
    line_total       NUMERIC(12,2) NOT NULL CHECK (line_total >= 0)
);

CREATE TABLE IF NOT EXISTS warehouse.fact_returns (
    return_key       SERIAL PRIMARY KEY,
    order_item_key   INT NOT NULL REFERENCES warehouse.fact_order_items(order_item_key),
    return_date_key  INT NOT NULL REFERENCES warehouse.dim_date(date_key),
    return_reason    TEXT,
    refund_amount    NUMERIC(10,2) NOT NULL CHECK (refund_amount >= 0)
);

-- Audit table maintained by the trigger in 03_triggers.sql
CREATE TABLE IF NOT EXISTS warehouse.order_status_audit (
    audit_id        SERIAL PRIMARY KEY,
    order_key       INT NOT NULL REFERENCES warehouse.fact_orders(order_key),
    old_status      TEXT,
    new_status      TEXT,
    changed_at      TIMESTAMP NOT NULL DEFAULT now()
);
