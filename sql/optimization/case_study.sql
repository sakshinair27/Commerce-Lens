-- Performance case study: refund analysis by state and return reason.
-- Business question: "For each state and return reason, what's total
-- refund amount over the last 12 months?" -- a realistic finance/ops query
-- that scans fact_returns and dim_customer without any supporting index on
-- the filtered/grouped columns in the unoptimized baseline schema.

EXPLAIN ANALYZE
SELECT
    dc.state,
    fr.return_reason,
    COUNT(*) AS return_count,
    SUM(fr.refund_amount) AS total_refunded
FROM warehouse.fact_returns fr
JOIN warehouse.fact_order_items foi ON fr.order_item_key = foi.order_item_key
JOIN warehouse.fact_orders fo ON foi.order_key = fo.order_key
JOIN warehouse.dim_customer dc ON fo.customer_key = dc.customer_key
JOIN warehouse.dim_date dd ON fr.return_date_key = dd.date_key
WHERE dd.full_date >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY dc.state, fr.return_reason
ORDER BY total_refunded DESC;

-- ── Optimization: add indexes on the columns actually driving the filter/
--    join/group-by that had no index in the baseline schema. ──
CREATE INDEX IF NOT EXISTS idx_returns_reason ON warehouse.fact_returns(return_reason);
CREATE INDEX IF NOT EXISTS idx_returns_date_key ON warehouse.fact_returns(return_date_key);
CREATE INDEX IF NOT EXISTS idx_customer_state ON warehouse.dim_customer(state);
CREATE INDEX IF NOT EXISTS idx_order_items_order_key ON warehouse.fact_order_items(order_key);
ANALYZE warehouse.fact_returns;
ANALYZE warehouse.fact_order_items;
ANALYZE warehouse.fact_orders;
ANALYZE warehouse.dim_customer;

-- Re-run the identical query after indexing + ANALYZE:
EXPLAIN ANALYZE
SELECT
    dc.state,
    fr.return_reason,
    COUNT(*) AS return_count,
    SUM(fr.refund_amount) AS total_refunded
FROM warehouse.fact_returns fr
JOIN warehouse.fact_order_items foi ON fr.order_item_key = foi.order_item_key
JOIN warehouse.fact_orders fo ON foi.order_key = fo.order_key
JOIN warehouse.dim_customer dc ON fo.customer_key = dc.customer_key
JOIN warehouse.dim_date dd ON fr.return_date_key = dd.date_key
WHERE dd.full_date >= CURRENT_DATE - INTERVAL '12 months'
GROUP BY dc.state, fr.return_reason
ORDER BY total_refunded DESC;

-- ── Second case: a highly selective point lookup, the pattern indexes are
--    actually built for. The aggregate query above touches most of both
--    tables, so Postgres correctly prefers hash joins over seq scans
--    regardless of indexing -- a real (and common) finding, not a failure.
--    This second query -- one customer's order history -- has ~1:5000
--    selectivity, so it's a fair test of index vs. seq scan.
EXPLAIN ANALYZE
SELECT fo.order_id, fo.order_status, fo.total_amount, dd.full_date
FROM warehouse.fact_orders fo
JOIN warehouse.dim_date dd ON fo.order_date_key = dd.date_key
WHERE fo.customer_key = 123
ORDER BY dd.full_date DESC;

CREATE INDEX IF NOT EXISTS idx_orders_customer_key_pointlookup ON warehouse.fact_orders(customer_key);
ANALYZE warehouse.fact_orders;

EXPLAIN ANALYZE
SELECT fo.order_id, fo.order_status, fo.total_amount, dd.full_date
FROM warehouse.fact_orders fo
JOIN warehouse.dim_date dd ON fo.order_date_key = dd.date_key
WHERE fo.customer_key = 123
ORDER BY dd.full_date DESC;
