-- Order-level totals derived from line items -- avoids storing a
-- denormalized total_amount that could drift from its source rows.
with items as (
    select * from {{ ref('int_order_items_enriched') }}
),

orders as (
    select * from {{ ref('stg_orders') }}
),

totals as (
    select
        order_id,
        sum(line_total) as total_amount
    from items
    group by order_id
)

select
    o.order_id,
    o.customer_id,
    o.order_date,
    o.order_status,
    o.payment_method,
    o.shipping_cost,
    coalesce(t.total_amount, 0) as total_amount
from orders o
left join totals t on o.order_id = t.order_id
