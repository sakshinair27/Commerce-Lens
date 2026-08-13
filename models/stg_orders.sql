-- Parse mixed order_date formats into a real date; leave grain at one row
-- per source order (customer/date-key resolution happens in intermediate).
with source as (
    select * from {{ source('raw', 'orders_raw') }}
)

select
    order_id,
    customer_id,
    case
        when order_date ~ '^\d{4}-\d{2}-\d{2}$' then order_date::date
        when order_date ~ '^\d{2}/\d{2}/\d{4}$' then to_date(order_date, 'MM/DD/YYYY')
        else null
    end as order_date,
    order_status,
    payment_method,
    shipping_cost::numeric as shipping_cost
from source
