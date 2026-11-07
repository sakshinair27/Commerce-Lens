with source as (
    select * from {{ source('raw', 'returns_raw') }}
)

select
    return_id,
    order_item_id,
    return_date::date as return_date,
    return_reason,
    refund_amount::numeric as refund_amount
from source
