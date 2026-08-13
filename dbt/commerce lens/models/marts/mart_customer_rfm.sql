-- RFM segmentation: NTILE(5) quintiles on recency/frequency/monetary,
-- combined into a champion/loyal/at_risk/lost label. dbt equivalent of
-- sql/advanced/window_functions.sql's RFM query.
with customer_orders as (
    select
        dc.customer_key,
        f.last_order_date,
        f.frequency,
        f.monetary
    from {{ ref('int_customer_order_facts') }} f
    inner join {{ ref('dim_customer') }} dc on f.customer_id = dc.customer_id
),

rfm_scored as (
    select
        *,
        ntile(5) over (order by current_date - last_order_date desc) as r_score,
        ntile(5) over (order by frequency asc) as f_score,
        ntile(5) over (order by monetary asc) as m_score
    from customer_orders
)

select
    customer_key,
    last_order_date,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    (r_score + f_score + m_score) as rfm_total,
    case
        when (r_score + f_score + m_score) >= 12 then 'champion'
        when (r_score + f_score + m_score) >= 9 then 'loyal'
        when (r_score + f_score + m_score) >= 6 then 'at_risk'
        else 'lost'
    end as segment
from rfm_scored
