-- Strip "$" from price strings, normalize boolean text variants ("true"/"1"/etc).
with source as (
    select * from {{ source('raw', 'products_raw') }}
)

select
    product_id,
    product_name,
    nullif(category_id, '') as category_id,
    brand,
    replace(unit_price, '$', '')::numeric as unit_price,
    lower(is_active) in ('true', '1') as is_active
from source
