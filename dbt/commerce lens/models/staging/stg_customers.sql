-- Dedup exact-duplicate rows, normalize email casing, parse two mixed date
-- formats. Equivalent transformation to the dim_customer block in
-- sql/etl/05_load_warehouse.sql, rebuilt in dbt's staging layer.
with source as (
    select * from {{ source('raw', 'customers_raw') }}
),

renamed as (
    select
        customer_id,
        full_name,
        nullif(lower(trim(email)), '') as email,
        case
            when signup_date ~ '^\d{4}-\d{2}-\d{2}$' then signup_date::date
            when signup_date ~ '^\d{2}/\d{2}/\d{4}$' then to_date(signup_date, 'MM/DD/YYYY')
            else null
        end as signup_date,
        city,
        state,
        country,
        segment
    from source
),

deduped as (
    select distinct on (customer_id) *
    from renamed
    order by customer_id, signup_date
)

select * from deduped
