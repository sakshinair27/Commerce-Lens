-- Stored function + procedure demonstrating reusable business logic living
-- in the database layer.

-- Function: compute a customer's lifetime value (sum of net order value
-- minus refunds) as of a given date. Used by the RFM mart and callable
-- directly for ad hoc analysis.
CREATE OR REPLACE FUNCTION warehouse.fn_customer_ltv(p_customer_key INT, p_as_of DATE DEFAULT CURRENT_DATE)
RETURNS NUMERIC AS $$
DECLARE
    v_ltv NUMERIC;
BEGIN
    SELECT COALESCE(SUM(fo.total_amount), 0) - COALESCE(SUM(fr.refund_amount), 0)
    INTO v_ltv
    FROM warehouse.fact_orders fo
    JOIN warehouse.dim_date dd ON fo.order_date_key = dd.date_key
    LEFT JOIN warehouse.fact_order_items foi ON foi.order_key = fo.order_key
    LEFT JOIN warehouse.fact_returns fr ON fr.order_item_key = foi.order_item_key
    WHERE fo.customer_key = p_customer_key
      AND dd.full_date <= p_as_of;

    RETURN COALESCE(v_ltv, 0);
END;
$$ LANGUAGE plpgsql STABLE;

-- Procedure: refresh a denormalized "customer summary" table used by the
-- BI layer for fast dashboard loads without hitting the fact tables
-- directly on every query. Run on a schedule (e.g. nightly via cron/Airflow
-- in production; called manually here).
CREATE TABLE IF NOT EXISTS warehouse.customer_summary (
    customer_key    INT PRIMARY KEY REFERENCES warehouse.dim_customer(customer_key),
    total_orders    INT NOT NULL,
    lifetime_value  NUMERIC(12,2) NOT NULL,
    last_order_date DATE,
    refreshed_at    TIMESTAMP NOT NULL DEFAULT now()
);

CREATE OR REPLACE PROCEDURE warehouse.sp_refresh_customer_summary()
LANGUAGE plpgsql AS $$
BEGIN
    TRUNCATE warehouse.customer_summary;

    INSERT INTO warehouse.customer_summary (customer_key, total_orders, lifetime_value, last_order_date)
    SELECT
        dc.customer_key,
        COUNT(DISTINCT fo.order_key) AS total_orders,
        warehouse.fn_customer_ltv(dc.customer_key) AS lifetime_value,
        MAX(dd.full_date) AS last_order_date
    FROM warehouse.dim_customer dc
    LEFT JOIN warehouse.fact_orders fo ON fo.customer_key = dc.customer_key
    LEFT JOIN warehouse.dim_date dd ON fo.order_date_key = dd.date_key
    GROUP BY dc.customer_key;

    RAISE NOTICE 'customer_summary refreshed: % rows', (SELECT count(*) FROM warehouse.customer_summary);
END;
$$;
