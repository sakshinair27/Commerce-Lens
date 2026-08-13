-- Advanced window-function demonstrations against the warehouse star schema.

-- 1) RFM segmentation: Recency, Frequency, Monetary percentile scoring per
--    customer using NTILE, paired with a running total via SUM() OVER.
WITH customer_orders AS (
    SELECT
        dc.customer_key,
        dc.full_name,
        MAX(dd.full_date) AS last_order_date,
        COUNT(DISTINCT fo.order_key) AS frequency,
        SUM(fo.total_amount) AS monetary
    FROM warehouse.dim_customer dc
    JOIN warehouse.fact_orders fo ON fo.customer_key = dc.customer_key
    JOIN warehouse.dim_date dd ON fo.order_date_key = dd.date_key
    GROUP BY dc.customer_key, dc.full_name
),
rfm_scored AS (
    SELECT
        *,
        CURRENT_DATE - last_order_date AS recency_days,
        NTILE(5) OVER (ORDER BY CURRENT_DATE - last_order_date DESC) AS recency_score,
        NTILE(5) OVER (ORDER BY frequency ASC) AS frequency_score,
        NTILE(5) OVER (ORDER BY monetary ASC) AS monetary_score
    FROM customer_orders
)
SELECT
    customer_key,
    full_name,
    recency_days,
    frequency,
    monetary,
    recency_score, frequency_score, monetary_score,
    (recency_score + frequency_score + monetary_score) AS rfm_total,
    CASE
        WHEN (recency_score + frequency_score + monetary_score) >= 12 THEN 'champion'
        WHEN (recency_score + frequency_score + monetary_score) >= 9  THEN 'loyal'
        WHEN (recency_score + frequency_score + monetary_score) >= 6  THEN 'at_risk'
        ELSE 'lost'
    END AS rfm_segment
FROM rfm_scored
ORDER BY rfm_total DESC
LIMIT 20;

-- 2) Month-over-month revenue growth using LAG().
WITH monthly_revenue AS (
    SELECT
        date_trunc('month', dd.full_date)::date AS month,
        SUM(fo.total_amount) AS revenue
    FROM warehouse.fact_orders fo
    JOIN warehouse.dim_date dd ON fo.order_date_key = dd.date_key
    WHERE fo.order_status <> 'cancelled'
    GROUP BY 1
)
SELECT
    month,
    revenue,
    LAG(revenue) OVER (ORDER BY month) AS prev_month_revenue,
    ROUND(
        100.0 * (revenue - LAG(revenue) OVER (ORDER BY month)) / NULLIF(LAG(revenue) OVER (ORDER BY month), 0),
        2
    ) AS mom_growth_pct
FROM monthly_revenue
ORDER BY month;

-- 3) Cohort retention: % of each signup-month cohort still ordering N months later.
WITH first_order AS (
    SELECT customer_key, MIN(date_trunc('month', dd.full_date))::date AS cohort_month
    FROM warehouse.fact_orders fo
    JOIN warehouse.dim_date dd ON fo.order_date_key = dd.date_key
    GROUP BY customer_key
),
orders_with_cohort AS (
    SELECT
        fo.customer_key,
        f.cohort_month,
        date_trunc('month', dd.full_date)::date AS order_month
    FROM warehouse.fact_orders fo
    JOIN warehouse.dim_date dd ON fo.order_date_key = dd.date_key
    JOIN first_order f ON f.customer_key = fo.customer_key
),
cohort_activity AS (
    SELECT
        cohort_month,
        order_month,
        (DATE_PART('year', order_month) - DATE_PART('year', cohort_month)) * 12
            + (DATE_PART('month', order_month) - DATE_PART('month', cohort_month)) AS month_number,
        COUNT(DISTINCT customer_key) AS active_customers
    FROM orders_with_cohort
    GROUP BY 1, 2, 3
),
cohort_size AS (
    SELECT cohort_month, COUNT(DISTINCT customer_key) AS cohort_customers
    FROM first_order
    GROUP BY 1
)
SELECT
    ca.cohort_month,
    ca.month_number,
    ca.active_customers,
    cs.cohort_customers,
    ROUND(100.0 * ca.active_customers / cs.cohort_customers, 1) AS retention_pct
FROM cohort_activity ca
JOIN cohort_size cs ON cs.cohort_month = ca.cohort_month
ORDER BY ca.cohort_month, ca.month_number;
