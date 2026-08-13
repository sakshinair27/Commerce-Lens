-- ETL: raw (messy) -> warehouse (star schema). This is the "hand-written
-- SQL ETL" demonstration; the dbt project (/dbt) rebuilds an equivalent
-- transformation layer using the modern staging/intermediate/marts pattern
-- for comparison.

BEGIN;

-- dim_date: populate a full calendar range covering the order data.
INSERT INTO warehouse.dim_date (date_key, full_date, year, quarter, month, day, day_of_week, is_weekend)
SELECT
    (EXTRACT(YEAR FROM d)::INT * 10000 + EXTRACT(MONTH FROM d)::INT * 100 + EXTRACT(DAY FROM d)::INT) AS date_key,
    d::date,
    EXTRACT(YEAR FROM d)::INT,
    EXTRACT(QUARTER FROM d)::INT,
    EXTRACT(MONTH FROM d)::INT,
    EXTRACT(DAY FROM d)::INT,
    EXTRACT(DOW FROM d)::INT,
    EXTRACT(DOW FROM d) IN (0, 6)
FROM generate_series('2024-01-01'::date, '2026-12-31'::date, interval '1 day') d
ON CONFLICT (date_key) DO NOTHING;

-- dim_category: deferred FK lets us insert children before/with parents in one statement.
INSERT INTO warehouse.dim_category (category_id, category_name, parent_category_id)
SELECT category_id, category_name, NULLIF(parent_category_id, '')
FROM raw.categories_raw
ON CONFLICT (category_id) DO NOTHING;

-- dim_customer: dedup exact-duplicate rows, normalize email case, parse two date formats.
INSERT INTO warehouse.dim_customer (customer_id, full_name, email, signup_date, city, state, country, segment)
SELECT DISTINCT ON (customer_id)
    customer_id,
    full_name,
    NULLIF(lower(trim(email)), ''),
    CASE
        WHEN signup_date ~ '^\d{4}-\d{2}-\d{2}$' THEN signup_date::date
        WHEN signup_date ~ '^\d{2}/\d{2}/\d{4}$' THEN to_date(signup_date, 'MM/DD/YYYY')
        ELSE NULL
    END,
    city, state, country, segment
FROM raw.customers_raw
ORDER BY customer_id, signup_date  -- DISTINCT ON keeps one row per customer_id, dropping injected dupes
ON CONFLICT (customer_id) DO NOTHING;

-- dim_product: strip "$" from price strings, normalize boolean text variants.
INSERT INTO warehouse.dim_product (product_id, product_name, category_id, brand, unit_price, is_active)
SELECT
    product_id,
    product_name,
    NULLIF(category_id, ''),
    brand,
    REPLACE(unit_price, '$', '')::numeric,
    lower(is_active) IN ('true', '1')
FROM raw.products_raw
ON CONFLICT (product_id) DO NOTHING;

-- fact_orders: resolve customer_key/date_key, parse mixed date formats.
INSERT INTO warehouse.fact_orders (order_id, customer_key, order_date_key, order_status, payment_method, shipping_cost, total_amount)
SELECT
    o.order_id,
    dc.customer_key,
    (EXTRACT(YEAR FROM parsed_date)::INT * 10000 + EXTRACT(MONTH FROM parsed_date)::INT * 100 + EXTRACT(DAY FROM parsed_date)::INT),
    o.order_status,
    o.payment_method,
    o.shipping_cost::numeric,
    0  -- populated below once line items are loaded
FROM raw.orders_raw o
JOIN warehouse.dim_customer dc ON dc.customer_id = o.customer_id
CROSS JOIN LATERAL (
    SELECT CASE
        WHEN o.order_date ~ '^\d{4}-\d{2}-\d{2}$' THEN o.order_date::date
        WHEN o.order_date ~ '^\d{2}/\d{2}/\d{4}$' THEN to_date(o.order_date, 'MM/DD/YYYY')
    END AS parsed_date
) pd
ON CONFLICT (order_id) DO NOTHING;

-- fact_order_items
INSERT INTO warehouse.fact_order_items (order_key, product_key, quantity, unit_price, discount_pct, line_total)
SELECT
    fo.order_key,
    dp.product_key,
    oi.quantity::int,
    oi.unit_price::numeric,
    oi.discount_pct::numeric,
    ROUND(oi.quantity::int * oi.unit_price::numeric * (1 - oi.discount_pct::numeric / 100), 2)
FROM raw.order_items_raw oi
JOIN warehouse.fact_orders fo ON fo.order_id = oi.order_id
JOIN warehouse.dim_product dp ON dp.product_id = oi.product_id;

-- fact_returns: must load BEFORE the total_amount backfill UPDATE below --
-- trg_return_requires_record fires BEFORE UPDATE on fact_orders and requires
-- any order already marked 'returned' to have a matching fact_returns row.
-- Loading returns first (while fact_orders is still only being INSERTed,
-- which doesn't fire that trigger) satisfies the constraint by the time the
-- UPDATE runs. This ordering dependency was caught by the trigger itself on
-- the first real run of this ETL, not written in from the start.
INSERT INTO warehouse.fact_returns (order_item_key, return_date_key, return_reason, refund_amount)
SELECT
    foi.order_item_key,
    (EXTRACT(YEAR FROM r.return_date::date)::INT * 10000 + EXTRACT(MONTH FROM r.return_date::date)::INT * 100 + EXTRACT(DAY FROM r.return_date::date)::INT),
    r.return_reason,
    r.refund_amount::numeric
FROM raw.returns_raw r
JOIN raw.order_items_raw oi_raw ON oi_raw.order_item_id = r.order_item_id
JOIN warehouse.fact_orders fo ON fo.order_id = oi_raw.order_id
JOIN warehouse.fact_order_items foi ON foi.order_key = fo.order_key AND foi.product_key = (
    SELECT product_key FROM warehouse.dim_product WHERE product_id = oi_raw.product_id
);

-- backfill fact_orders.total_amount from its line items
UPDATE warehouse.fact_orders fo
SET total_amount = sub.total
FROM (
    SELECT order_key, SUM(line_total) AS total
    FROM warehouse.fact_order_items
    GROUP BY order_key
) sub
WHERE fo.order_key = sub.order_key;

COMMIT;
