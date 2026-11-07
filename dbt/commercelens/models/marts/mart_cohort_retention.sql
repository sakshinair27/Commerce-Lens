-- Monthly signup-cohort retention: for each cohort month, what share of
-- customers placed an order in month N after signup.
with first_month as (
    select
        customer_key,
        date_trunc('month', signup_date)::date as cohort_month
    from {{ ref('dim_customer') }}
    where signup_date is not null
),

orders_by_month as (
    select
        fo.customer_key,
        date_trunc('month', dd.full_date)::date as order_month
    from {{ ref('fct_orders') }} fo
    inner join {{ ref('dim_date') }} dd on fo.order_date_key = dd.date_key
    group by 1, 2
),

cohort_activity as (
    select
        fm.cohort_month,
        obm.customer_key,
        (date_part('year', obm.order_month) - date_part('year', fm.cohort_month)) * 12
            + (date_part('month', obm.order_month) - date_part('month', fm.cohort_month)) as month_number
    from first_month fm
    inner join orders_by_month obm on fm.customer_key = obm.customer_key
    where obm.order_month >= fm.cohort_month
),

cohort_sizes as (
    select cohort_month, count(distinct customer_key) as cohort_size
    from first_month
    group by 1
)

select
    ca.cohort_month,
    ca.month_number,
    cs.cohort_size,
    count(distinct ca.customer_key) as active_customers,
    round(100.0 * count(distinct ca.customer_key) / nullif(cs.cohort_size, 0), 1) as retention_pct
from cohort_activity ca
inner join cohort_sizes cs on ca.cohort_month = cs.cohort_month
group by ca.cohort_month, ca.month_number, cs.cohort_size
order by ca.cohort_month, ca.month_number
