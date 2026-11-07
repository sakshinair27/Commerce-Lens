with source as (
    select * from {{ source('raw', 'order_items_raw') }}
)

select
    order_item_id,
    order_id,
    product_id,
    quantity::int as quantity,
    unit_price::numeric as unit_price,
    discount_pct::numeric as discount_pct,
    round(quantity::int * unit_price::numeric * (1 - discount_pct::numeric / 100), 2) as line_total
from source
