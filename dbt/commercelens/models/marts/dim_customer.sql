select
    row_number() over (order by customer_id) as customer_key,
    customer_id,
    full_name,
    email,
    signup_date,
    city,
    state,
    country,
    segment
from {{ ref('stg_customers') }}
