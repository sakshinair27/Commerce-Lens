-- One row per order line item, joined out to its order, customer, product,
-- and category. Feeds both the fct_order_items mart and the
-- category-rollup / RFM marts so those don't each repeat the same joins.
with order_items as (
    select * from {{ ref('stg_order_items') }}
),

orders as (
    select * from {{ ref('stg_orders') }}
),

products as (
    select * from {{ ref('stg_products') }}
),

joined as (
    select
        oi.order_item_id,
        oi.order_id,
        o.customer_id,
        oi.product_id,
        p.category_id,
        o.order_date,
        o.order_status,
        oi.quantity,
        oi.unit_price,
        oi.discount_pct,
        oi.line_total
    from order_items oi
    inner join orders o on oi.order_id = o.order_id
    left join products p on oi.product_id = p.product_id
)

select * from joined
