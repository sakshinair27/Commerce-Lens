"""
CommerceLens ELT orchestration DAG.

Shape (v1, intentionally minimal): ingest_raw_data -> dbt_run -> dbt_test.

Design goal: the warehouse is config, not code. Every task below gets its
connection details from the Airflow Connection named `warehouse_conn` at
TASK EXECUTION time (not DAG parse time -- looking connections up at parse
time is a common beginner mistake: it breaks DAG import if the connection
doesn't exist yet, and hammers the metadata DB on every scheduler parse
cycle). Nothing here is hardcoded to Postgres.

When CommerceLens migrates to Snowflake, the plan is:

    1. Create/point `warehouse_conn` at Snowflake (conn_type="snowflake").
    2. Set the Airflow Variable COMMERCELENS_DBT_TARGET to "snowflake"
       (dbt_profile/profiles.yml in this repo already has a `snowflake`
       target block ready -- see that file for its current, untested
       status).
    3. Done. This DAG file does not change.

One honest, deliberate scope boundary: the *ingestion* task
(`scripts/load_raw.py`) uses Postgres's COPY protocol via psycopg2, which
has no Snowflake equivalent (Snowflake ingestion is PUT + COPY INTO, a
genuinely different mechanism, not a connection-string swap). So today,
`_dbt_env_for_connection` abstracts the warehouse for the dbt tasks across
both backends, but `ingest_raw_data` is Postgres-specific until it's
deliberately reworked as part of the Snowflake migration. See this
directory's README for more.

Run status: this DAG has been run end to end against a live Airflow
scheduler (Docker, LocalExecutor) with a real Postgres warehouse_conn --
all three tasks succeeded on run id
manual__2026-10-05T21:30:42.218667+00:00. See ../README.md's "Status"
section and ../../results/airflow_dag_run_output.txt for the real task
logs. The Snowflake path is still unexercised -- see this module's own
docstring above for that scope boundary.
"""
from __future__ import annotations

import os
import subprocess
import sys
from datetime import datetime

from airflow import DAG
from airflow.exceptions import AirflowException
from airflow.hooks.base import BaseHook
from airflow.models import Variable
from airflow.operators.python import PythonOperator

# Path to the commercelens-sql repo checkout, so this DAG can find
# scripts/load_raw.py and the dbt project without hardcoding a path that
# only works on one machine. Set this once as an Airflow Variable; falls
# back to "three directories up from this file" (repo_root/airflow/dags/..)
# which is correct if this file stays at airflow/dags/ inside the repo.
REPO_DIR = Variable.get(
    "COMMERCELENS_REPO_DIR",
    default_var=os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
)
DBT_PROJECT_DIR = os.path.join(REPO_DIR, "dbt", "commercelens")
DBT_PROFILES_DIR = os.path.join(REPO_DIR, "dbt_profile")  # holds the machine-facing profiles.yml
SCRIPTS_DIR = os.path.join(REPO_DIR, "scripts")

WAREHOUSE_CONN_ID = "warehouse_conn"


def _dbt_env_for_connection(conn) -> dict:
    """
    Map an Airflow Connection to the env vars dbt_profile/profiles.yml
    expects, for whichever backend the connection actually points at.
    This is the one place that knows about both Postgres and Snowflake --
    the tasks below just call this and otherwise don't care which it is.
    """
    extra = conn.extra_dejson or {}

    if conn.conn_type in ("postgres", "postgresql"):
        return {
            "DBT_PG_HOST": conn.host or "",
            "DBT_PG_USER": conn.login or "",
            "DBT_PG_PASSWORD": conn.password or "",
            "DBT_PG_PORT": str(conn.port or 5432),
            "DBT_PG_DBNAME": conn.schema or "",
            "DBT_PG_SCHEMA": extra.get("dbt_schema", "dbt_dev"),
        }

    if conn.conn_type == "snowflake":
        # Prepared for the migration; not exercised against a real
        # Snowflake account yet. Airflow's Snowflake connection type
        # typically carries account/warehouse/role/database in `extra`.
        return {
            "DBT_SF_ACCOUNT": extra.get("account", conn.host or ""),
            "DBT_SF_USER": conn.login or "",
            "DBT_SF_PASSWORD": conn.password or "",
            "DBT_SF_ROLE": extra.get("role", ""),
            "DBT_SF_DATABASE": extra.get("database", conn.schema or ""),
            "DBT_SF_WAREHOUSE": extra.get("warehouse", ""),
            "DBT_SF_SCHEMA": extra.get("dbt_schema", "dbt_dev"),
        }

    raise AirflowException(
        f"warehouse_conn has conn_type={conn.conn_type!r}, which this DAG "
        "doesn't have a dbt env mapping for yet. Add one to "
        "_dbt_env_for_connection before pointing warehouse_conn at it."
    )


def _dbt_target_for_connection(conn) -> str:
    """Which dbt target block to use. An explicit Variable always wins;
    otherwise infer a sensible default from the connection type."""
    override = Variable.get("COMMERCELENS_DBT_TARGET", default_var=None)
    if override:
        return override
    return "dev" if conn.conn_type in ("postgres", "postgresql") else conn.conn_type


def _dbt_env() -> dict:
    """Resolved at call time (i.e. during task execution), never at DAG
    parse time -- see module docstring."""
    conn = BaseHook.get_connection(WAREHOUSE_CONN_ID)
    env = os.environ.copy()
    env.update(_dbt_env_for_connection(conn))
    env["DBT_TARGET"] = _dbt_target_for_connection(conn)
    return env


def _run_dbt(subcommand: str) -> None:
    # Which `dbt` executable to call -- defaults to whatever's on PATH
    # (fine for a plain venv setup), but overridable via Variable for
    # environments where dbt lives in its own isolated venv to avoid
    # dependency conflicts with Airflow's own pinned packages (e.g. the
    # Docker image used for local dev, which installs dbt into
    # /opt/dbt_venv specifically to keep it out of Airflow's venv).
    dbt_bin = Variable.get("COMMERCELENS_DBT_BIN", default_var="dbt")
    cmd = [dbt_bin, subcommand, "--project-dir", DBT_PROJECT_DIR, "--profiles-dir", DBT_PROFILES_DIR]
    result = subprocess.run(cmd, env=_dbt_env(), capture_output=True, text=True)
    # Surface dbt's own stdout/stderr in the task log either way -- the
    # output (which models ran, which tests failed and why) is the whole
    # point of this task, not just the exit code.
    print(result.stdout)
    print(result.stderr, file=sys.stderr)
    if result.returncode != 0:
        raise AirflowException(f"`{' '.join(cmd)}` failed with exit code {result.returncode}")


def ingest_raw_data(**_context) -> None:
    """
    Load the source CSVs into the `raw` schema. Postgres-only today (see
    module docstring) -- this task assumes warehouse_conn is a Postgres
    connection and raises clearly if it isn't.
    """
    conn = BaseHook.get_connection(WAREHOUSE_CONN_ID)
    if conn.conn_type not in ("postgres", "postgresql"):
        raise NotImplementedError(
            f"ingest_raw_data only supports Postgres today; warehouse_conn "
            f"is conn_type={conn.conn_type!r}. Rework this task (not just "
            "its config) as part of the Snowflake migration -- Snowflake "
            "ingestion is PUT + COPY INTO, a different mechanism from "
            "psycopg2's COPY, not a connection-string swap."
        )

    if SCRIPTS_DIR not in sys.path:
        sys.path.insert(0, SCRIPTS_DIR)
    import load_raw  # noqa: E402  (path inserted just above, at call time)

    conn_str = (
        f"postgresql://{conn.login}:{conn.password}@{conn.host}:"
        f"{conn.port or 5432}/{conn.schema}"
    )
    load_raw.load(conn_str)


def dbt_run(**_context) -> None:
    _run_dbt("run")


def dbt_test(**_context) -> None:
    _run_dbt("test")


with DAG(
    dag_id="commercelens_elt",
    description="CommerceLens: ingest raw CSVs, run dbt, run dbt tests.",
    start_date=datetime(2026, 1, 1),
    schedule=None,  # trigger manually / wire up a schedule once this is proven out
    catchup=False,
    max_active_runs=1,  # dbt's rename-to-backup materialization strategy
    # isn't safe for two concurrent `dbt run`s against the same schema --
    # they can race on the same `<model>__dbt_backup` relation name and
    # fail with "relation already exists". Found this the hard way: two
    # manually-triggered runs collided on the first real test. One run at
    # a time avoids it entirely.
    tags=["commercelens", "elt", "dbt"],
) as dag:

    ingest_task = PythonOperator(
        task_id="ingest_raw_data",
        python_callable=ingest_raw_data,
    )

    dbt_run_task = PythonOperator(
        task_id="dbt_run",
        python_callable=dbt_run,
    )

    dbt_test_task = PythonOperator(
        task_id="dbt_test",
        python_callable=dbt_test,
    )

    ingest_task >> dbt_run_task >> dbt_test_task
