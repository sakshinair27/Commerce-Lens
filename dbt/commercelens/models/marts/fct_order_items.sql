select
    row_number() over (order by oi.order_item_id) as order_item_key,
    oi.order_item_id,
    fo.order_key,
    dp.product_key,
    oi.quantity,
    oi.unit_price,
    oi.discount_pct,
    oi.line_total
from {{ ref('int_order_items_enriched') }} oi
inner join {{ ref('fct_orders') }} fo on oi.order_id = fo.order_id
inner join {{ ref('dim_product') }} dp on oi.product_id = dp.product_id
