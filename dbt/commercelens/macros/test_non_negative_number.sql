{% test non_negative_number(model, column_name) %}
-- Custom generic test (kept dependency-free, no dbt_utils, so `dbt test`
-- runs offline). Fails rows where the column is negative.
select *
from {{ model }}
where {{ column_name }} < 0
{% endtest %}
