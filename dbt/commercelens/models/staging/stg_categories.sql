with source as (
    select * from {{ source('raw', 'categories_raw') }}
)

select
    category_id,
    category_name,
    nullif(parent_category_id, '') as parent_category_id
from source
