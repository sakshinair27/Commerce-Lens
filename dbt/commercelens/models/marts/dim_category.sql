select
    row_number() over (order by category_id) as category_key,
    category_id,
    category_name,
    parent_category_id
from {{ ref('stg_categories') }}
