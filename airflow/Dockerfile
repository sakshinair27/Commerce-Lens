# Airflow image for CommerceLens local dev, with dbt installed into its
# OWN virtualenv rather than pip-installed alongside Airflow. dbt-core and
# Airflow pin conflicting versions of several shared dependencies (click,
# jinja2, etc.); installing both into one Python environment is a known
# source of broken installs. Keeping dbt isolated avoids that entirely --
# the DAG calls /opt/dbt_venv/bin/dbt as a subprocess, same as it would
# call any other CLI tool.
FROM apache/airflow:2.9.3-python3.11

USER root
RUN python3 -m venv /opt/dbt_venv \
    && /opt/dbt_venv/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/dbt_venv/bin/pip install --no-cache-dir dbt-postgres dbt-snowflake

USER airflow

# snowflake-connector-python goes into Airflow's OWN environment (not
# /opt/dbt_venv) because ingest_raw_data runs as a PythonOperator inside
# Airflow's interpreter, not as a dbt subprocess -- it needs this import
# available where Airflow itself runs Python code.
RUN pip install --no-cache-dir snowflake-connector-python
