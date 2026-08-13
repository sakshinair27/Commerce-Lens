select
    row_number() over (order by o.order_id) as order_key,
    o.order_id,
    dc.customer_key,
    dd.date_key as order_date_key,
    o.order_status,
    o.payment_method,
    o.shipping_cost,
    o.total_amount
from {{ ref('int_order_totals') }} o
inner join {{ ref('dim_customer') }} dc on o.customer_id = dc.customer_id
left join {{ ref('dim_date') }} dd on o.order_date = dd.full_date
