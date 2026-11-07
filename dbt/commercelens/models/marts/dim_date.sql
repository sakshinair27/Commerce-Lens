-- Calendar spine generated in-model (no seed needed) covering the order
-- date range plus a buffer on either side.
with spine as (
{% if target.type == 'snowflake' %}
    -- Snowflake has no generate_series() table function; build the spine
    -- from a row generator instead. 1096 = days from 2024-01-01 through
    -- 2026-12-31 inclusive (366 + 365 + 365, 2024 is a leap year) -- keep
    -- this in sync with the date range below if it ever changes.
    select dateadd(day, seq4(), '2024-01-01'::date) as full_date
    from table(generator(rowcount => 1096))
{% else %}
    select generate_series(
        '2024-01-01'::date, '2026-12-31'::date, interval '1 day'
    )::date as full_date
{% endif %}
)

select
    (extract(year from full_date)::int * 10000
        + extract(month from full_date)::int * 100
        + extract(day from full_date)::int) as date_key,
    full_date,
    extract(year from full_date)::int as year,
    extract(quarter from full_date)::int as quarter,
    extract(month from full_date)::int as month,
    extract(day from full_date)::int as day,
    extract(dow from full_date)::int as day_of_week,
    extract(dow from full_date) in (0, 6) as is_weekend
from spine
