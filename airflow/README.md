# CommerceLens Airflow orchestration

Orchestrates the existing CommerceLens pipeline as one DAG:

```
ingest_raw_data  -->  dbt_run  -->  dbt_test
```

This is v1, deliberately minimal -- no retries tuning, no SLAs, no
sensors, no schedule set (trigger it manually -- it's had one full
real run so far, see Status below, not enough to call it battle-tested).
The goal of this pass was orchestration + a config boundary that
survives a future warehouse migration, not a fully productionized DAG.

**A real gotcha hit during setup, documented here for anyone else who
runs into it:** triggering multiple DAG runs close together can crash
`dbt_run` with `relation "<model>__dbt_backup" already exists`. dbt's
view/table materialization renames the existing relation to
`<model>__dbt_backup` during a run, then drops it at the end; two
concurrent `dbt run`s against the same schema can race on that rename and
leave orphaned backup relations behind. The DAG now sets
`max_active_runs=1` so Airflow won't start a second run while one's still
going, which prevents this. If you hit this error anyway (e.g. from
manually running dbt outside the DAG while the DAG is also running),
clean up the orphaned relations directly:
```
docker exec -it commercelens_pg psql -U commercelens -d commercelens -c "DROP VIEW IF EXISTS dbt_dev_staging.<model>__dbt_backup;"
```
(use `DROP TABLE` instead of `DROP VIEW` for marts models, which are
materialized as tables per `dbt_project.yml`).

## Why this exists

CommerceLens already has a working Postgres + dbt pipeline (see the repo
root README), but it's run manually (`scripts/load_raw.py`, then `dbt
run`, then `dbt test`, each as a separate step you kick off yourself).
This DAG turns that into one orchestrated pipeline with explicit
dependencies and a real failure signal if a step breaks.

## Status -- what's actually verified vs. not

Being precise about this on purpose, consistent with how the rest of this
project documents its verification (see `results/` in the repo root):

- **Verified end to end, for real (Postgres):** this DAG was deployed
  with the Docker setup below (Option A) and run against a live Airflow
  scheduler on `2026-10-05`, run id
  `manual__2026-10-05T21:30:42.218667+00:00`. All three tasks succeeded
  in order -- `ingest_raw_data` loaded the raw CSVs (categories=24,
  customers=5025, products=500, orders=25000, order_items=74859,
  returns=12963), `dbt_run` built all 20 models
  (`PASS=20 WARN=0 ERROR=0 SKIP=0`), and `dbt_test` passed all 50 tests
  (`PASS=50 WARN=0 ERROR=0 SKIP=0`). The full task logs from that run are
  captured in `../results/airflow_dag_run_output.txt`.
- Getting to a clean green run also surfaced two real infra issues along
  the way, both fixed and documented: the webserver missing Airflow's
  120s gunicorn healthcheck on Docker Desktop for Windows (fixed via the
  `WEB_SERVER_MASTER_TIMEOUT` / `WEB_SERVER_WORKER_TIMEOUT` /  `WORKERS`
  settings in `docker-compose.yaml`), and the `__dbt_backup` concurrency
  race described above (fixed via `max_active_runs=1`).
- **Verified end to end, for real (Snowflake):** the dbt layer was first
  verified standalone against a real Snowflake trial account (`dbt run &&
  dbt test` directly, 20/20 models and 50/50 tests passing, row counts
  matching the Postgres run exactly -- three Postgres-only SQL constructs,
  `generate_series`, the `~` regex operator, and `DISTINCT ON`, needed
  target-conditional fixes to get there; see the root README's "Snowflake
  portability" section and `../results/dbt_snowflake_verification_output.txt`).
  `ingest_raw_data` was then reworked to dispatch on the Airflow
  connection's `conn_type` -- Postgres keeps using `psycopg2`'s
  `COPY FROM STDIN` (`scripts/load_raw.py`); Snowflake uses `PUT` +
  `COPY INTO` (`scripts/load_raw_snowflake.py`), a genuinely different
  mechanism, not a connection-string swap. With `warehouse_conn`
  re-pointed at the same Snowflake trial account and
  `COMMERCELENS_DBT_TARGET` set to `snowflake`, this DAG was triggered for
  real against the Dockerized Airflow scheduler (same setup as the
  Postgres run) on `2026-11-07`, run id
  `manual__2026-11-07T21:21:16+00:00`. All three tasks succeeded in
  order: `ingest_raw_data` loaded 113,371 rows across 6 tables with exact
  row-count parity (categories=24, customers=5025, products=500,
  orders=25000, order_items=74859, returns=12963), `dbt_run` built all 20
  models (`PASS=20 WARN=0 ERROR=0 SKIP=0`), and `dbt_test` passed all 50
  tests (`PASS=50 WARN=0 ERROR=0 SKIP=0`). Full task logs in
  `../results/snowflake_dag_run_output.txt`.

## Setup

Airflow is POSIX-only outside of WSL2/containers -- a plain `pip install`
into a Windows venv will install fine but fail at `airflow db migrate`
with a SQLite path error. Two supported paths, pick one:

### Option A: Docker (recommended, works on Windows without WSL)

This repo includes `airflow/Dockerfile` and `airflow/docker-compose.yaml`
for exactly this. It runs Airflow (LocalExecutor, its own small Postgres
for metadata) joined to the same Docker network as the repo root's
`commercelens_pg` container, with dbt installed into an isolated venv
inside the image (`/opt/dbt_venv`) to avoid dependency conflicts with
Airflow's own pinned packages.

1. **Start the warehouse first**, from the repo root: `docker compose up -d postgres`
2. **Check the network name**: `docker network ls` -- find the one ending
   in `_default`. If it isn't literally `commercelens-sql_default`, edit
   the `networks.default.name` value at the bottom of
   `airflow/docker-compose.yaml` to match.
3. **Build and start Airflow**, from this `airflow/` directory:
   `docker compose up -d --build`
   (first run builds the image and runs `airflow-init`, which sets up the
   metadata DB and creates an `admin` / `admin` login -- give it a minute)
4. **Open the UI** at http://localhost:8080 and log in with `admin` / `admin`.
5. **Create the `warehouse_conn` Connection** (Admin -> Connections -> +):
   - Conn Id: `warehouse_conn`
   - Conn Type: `Postgres`
   - Host: `commercelens_pg` (the container name -- NOT `localhost`,
     since Airflow is running inside its own container now and reaches
     Postgres over the Docker network instead of your machine's loopback)
   - Schema: `commercelens`, Login: `commercelens`, Password: `commercelens`, Port: `5432`
     (matches `.env.example` / the root `docker-compose.yml`)
6. **Run it**: trigger `commercelens_elt` from the UI, or
   `docker compose exec airflow-scheduler airflow dags trigger commercelens_elt`

### Option B: WSL2 or native Linux/macOS

1. **Install**: `pip install apache-airflow dbt-postgres` against
   [Airflow's published constraints file](https://airflow.apache.org/docs/apache-airflow/stable/installation/installing-from-pypi.html)
   for your Python version -- don't `pip install apache-airflow` unconstrained.
2. **Point Airflow at this repo**: set `AIRFLOW_HOME` to an absolute path,
   set the Airflow Variable `COMMERCELENS_REPO_DIR` to this repo's
   absolute path, and point `dags_folder` at `airflow/dags/` in this repo
   (simplest while iterating, rather than copying the DAG file elsewhere).
3. `airflow db migrate`, then create a user with `airflow users create`.
4. **Create the `warehouse_conn` Connection**, same fields as Option A
   step 5, except Host is `localhost` (no container network involved here).
5. **Run it**: `airflow standalone` (quick single-process dev mode) or
   `airflow webserver` + `airflow scheduler` in separate terminals, then
   `airflow dags trigger commercelens_elt`.

## Migrating to Snowflake (done -- here's exactly how)

This is the part the DAG was specifically designed around, per the design
brief: the warehouse is config, not code. It's now actually been done end
to end against a real Snowflake trial account, not just planned -- these
are the real steps, including the one genuine DAG code change needed
(`ingest_raw_data`'s ingestion mechanism, not just its config).

1. Add `dbt-snowflake` to `/opt/dbt_venv` and `snowflake-connector-python`
   to Airflow's own environment in `airflow/Dockerfile`, then
   `docker compose build && docker compose up -d` to pick it up. (The
   two installs are deliberately separate: `dbt_run`/`dbt_test` call
   `dbt` as a subprocess inside `/opt/dbt_venv`; `ingest_raw_data` runs
   as a `PythonOperator` inside Airflow's own interpreter, so it needs
   `snowflake.connector` importable there -- a `--user` install fails in
   that venv, a plain `pip install` works.)
2. Re-point (or add a second) `warehouse_conn` Connection with
   Conn Type `Snowflake` (delete the old one first if reusing the same
   `conn_id`: `airflow connections delete warehouse_conn`), filling in
   account/warehouse/role/database in its `extra` field (see
   `_dbt_env_for_connection` in the DAG file for exactly which keys it
   reads), e.g.:
   ```
   airflow connections add warehouse_conn --conn-type snowflake \
     --conn-login <user> --conn-password <password> \
     --conn-extra '{"account": "<account_id>", "warehouse": "<warehouse>", "role": "<role>", "database": "<database>"}'
   ```
3. Set the Airflow Variable `COMMERCELENS_DBT_TARGET` to `snowflake`:
   `airflow variables set COMMERCELENS_DBT_TARGET snowflake`
4. `ingest_raw_data` in `commercelens_dag.py` now dispatches on
   `warehouse_conn`'s `conn_type` -- Postgres ingestion still uses
   `COPY FROM STDIN` via psycopg2 (`scripts/load_raw.py`); Snowflake uses
   `PUT` + `COPY INTO` (`scripts/load_raw_snowflake.py`), a different
   mechanism, not a connection-string swap. No further code changes
   needed here -- this step is done.
5. `dbt_run` / `dbt_test` need no changes -- they already read
   `DBT_TARGET` and the `DBT_SF_*` / `DBT_PG_*` env vars dynamically via
   `dbt_profile/profiles.yml`.
6. Trigger it: `airflow dags trigger commercelens_elt`, then check
   `airflow dags list-runs -d commercelens_elt` /
   `airflow tasks states-for-dag-run commercelens_elt <run_id>`.

## Files

- `dags/commercelens_dag.py` -- the DAG. `ingest_raw_data` dispatches on
  `warehouse_conn`'s `conn_type`; `../scripts/load_raw.py` (Postgres) and
  `../scripts/load_raw_snowflake.py` (Snowflake) are the two loaders it calls.
- `Dockerfile` / `docker-compose.yaml` -- Docker-based Airflow (Option A above),
  with `dbt-snowflake` and `snowflake-connector-python` installed for
  Snowflake support alongside the original Postgres path.
- `../dbt_profile/profiles.yml` -- the machine-facing dbt profile the DAG
  points `--profiles-dir` at. Separate from the repo root's
  `dbt/commercelens/profiles_example.yml`, which stays as the
  plain-English template for manual/local dbt use documented in the main
  README -- that file is unchanged by this work.
