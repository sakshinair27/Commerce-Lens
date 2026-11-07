{% macro regex_match(column, pattern) %}
    {#- Postgres and Snowflake use different regex-match operators (~ vs
       RLIKE). This macro picks the right one per target so the staging
       models stay warehouse-agnostic, same spirit as the Airflow DAG's
       _dbt_env_for_connection. Added during the Snowflake verification
       pass -- see dbt_profile/profiles.yml and the root README's
       Orchestration section. Postgres branch is untouched from the
       original inline `~` operator, so already-verified Postgres output
       doesn't change. #}
    {% if target.type == 'snowflake' %}
        {{ column }} rlike '{{ pattern }}'
    {% else %}
        {{ column }} ~ '{{ pattern }}'
    {% endif %}
{% endmacro %}
