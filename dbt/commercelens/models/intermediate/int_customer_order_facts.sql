-- One row per customer: recency/frequency/monetary inputs for the RFM mart.
with orders as (
    select * from {{ ref('int_order_totals') }}
),

agg as (
    select
        customer_id,
        max(order_date) as last_order_date,
        count(distinct order_id) as frequency,
        sum(total_amount) as monetary
    from orders
    group by customer_id
)

select * from agg
