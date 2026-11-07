select
    row_number() over (order by p.product_id) as product_key,
    p.product_id,
    p.product_name,
    c.category_key,
    c.category_name,
    p.brand,
    p.unit_price,
    p.is_active
from {{ ref('stg_products') }} p
left join {{ ref('dim_category') }} c on p.category_id = c.category_id
