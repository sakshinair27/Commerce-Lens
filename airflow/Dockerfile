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
    && /opt/dbt_venv/bin/pip install --no-cache-dir dbt-postgres

USER airflow
