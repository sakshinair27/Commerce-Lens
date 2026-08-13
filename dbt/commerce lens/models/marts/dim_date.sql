-- Calendar spine generated in-model (no seed needed) covering the order
-- date range plus a buffer on either side.
with spine as (
    select generate_series(
        '2024-01-01'::date, '2026-12-31'::date, interval '1 day'
    )::date as full_date
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
