select
    row_number() over (order by r.return_id) as return_key,
    r.return_id,
    foi.order_item_key,
    dd.date_key as return_date_key,
    r.return_reason,
    r.refund_amount
from {{ ref('stg_returns') }} r
inner join {{ ref('fct_order_items') }} foi on r.order_item_id = foi.order_item_id
left join {{ ref('dim_date') }} dd on r.return_date = dd.full_date
