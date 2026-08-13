-- Month-over-month revenue growth via LAG().
with monthly as (
    select
        date_trunc('month', dd.full_date)::date as order_month,
        sum(fo.total_amount) as revenue
    from {{ ref('fct_orders') }} fo
    inner join {{ ref('dim_date') }} dd on fo.order_date_key = dd.date_key
    group by 1
)

select
    order_month,
    revenue,
    lag(revenue) over (order by order_month) as prior_month_revenue,
    round(
        100.0 * (revenue - lag(revenue) over (order by order_month))
        / nullif(lag(revenue) over (order by order_month), 0),
        2
    ) as mom_growth_pct
from monthly
order by order_month
