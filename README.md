# CommerceLens

An end-to-end, advanced-SQL-driven data warehouse project built on a
realistically messy synthetic e-commerce dataset. Real PostgreSQL (not
SQLite), a hand-written SQL ETL and an equivalent dbt project side by
side, PL/pgSQL triggers/procedures, a real query-optimization case study,
and a Dockerized BI layer.

Every number in this README is real, captured from an actual run against a
live Postgres 16 instance -- see `results/verification_output.txt` and
`results/dbt_verification_output.txt` for the full, unedited output.

## What's here

| Layer | What it demonstrates |
|---|---|
| `sql/ddl/` | Star schema design, CHECK constraints, a deferred self-referencing FK |
| `sql/ddl/03_triggers.sql` | An audit trigger and a data-quality enforcement trigger (PL/pgSQL) |
| `sql/ddl/04_procedures.sql` | A stored function (customer LTV) and a stored procedure |
| `sql/etl/05_load_warehouse.sql` | Hand-written raw -> warehouse ETL |
| `sql/advanced/` | Window functions (RFM, MoM growth, cohort retention), a recursive CTE |
| `sql/optimization/case_study.sql` | Real `EXPLAIN ANALYZE` before/after indexing |
| `dbt/commercelens/` | The same transformation rebuilt as staging/intermediate/marts, with 50 tests |
| `docker-compose.yml` + `docker/init/` | One-command Postgres + Metabase, auto-seeded |
| `bi/metabase_setup.md` | Dashboard setup on the Dockerized BI layer |

## Dataset

Generated with a seeded Faker script (`scripts/generate_data.py`,
`seed=42`) with intentional real-world messiness: mixed date formats
(`YYYY-MM-DD` and `MM/DD/YYYY`), ~25 exact-duplicate customer rows, mixed
price-string formatting (`"$19.99"` vs `"19.99"`), inconsistent email
casing, and a realistic order-status distribution. Actual generated volume:

```
categories=24  customers=5,025 (5,000 unique after dedup)  products=500
orders=25,000  order_items=74,859  returns=12,963
```

## Quickstart

```bash
git clone <this-repo>
cd commercelens-sql
docker compose up -d
# wait ~30-60s for the init script to apply DDL, load data, and run the ETL
# Postgres:  localhost:5432  (db/user/pass: commercelens)
# Metabase:  http://localhost:3000
```

No manual seeding step -- `docker/init/00-init.sh` runs automatically on
first container start and leaves you with a fully populated warehouse.

To run the dbt project against the same database:

```bash
cd dbt/commercelens
pip install dbt-postgres
dbt run && dbt test
```

## Real results (from `results/verification_output.txt`)

**ETL**: raw CSVs load with exact row-count parity (24 / 5,025 / 500 /
25,000 / 74,859 / 12,963), full raw-to-warehouse ETL completes in ~27
seconds.

**Stored procedure**: `sp_refresh_customer_summary()` populates
`customer_summary` for all 5,000 customers -- avg lifetime value $30,732.95,
max $124,973.91.

**RFM segmentation** (window functions, `NTILE(5)` x3): of 4,963 customers
with order history -- 1,381 loyal, 1,372 champion, 1,241 at-risk, 969 lost.

**Recursive CTE category rollup**: 6 top-level categories, each including
all nested subcategories' sales. Electronics leads at $8,842,357.73 across
5 subcategories and 38,092 line items.

**Query optimization case study** (`sql/optimization/case_study.sql`):
- A highly selective single-customer order lookup (~1:5,000 selectivity)
  went from a **Seq Scan** (2.16ms) to a **Bitmap Index Scan** (0.31ms)
  after adding `idx_orders_customer_key` -- a real, expected win.
- A full-table state x return-reason refund aggregate showed **no plan
  change** after indexing -- Postgres correctly kept hash joins + seq
  scans, since the query touches most of both tables at this data volume.
  Documented honestly rather than cherry-picked, because knowing *when
  indexing doesn't help* is as much the point of the exercise as knowing
  when it does.

## dbt rebuild (from `results/dbt_verification_output.txt`)

20 models (staging -> intermediate -> marts), **50/50 schema tests passing**
(uniqueness, not-null, relationships, accepted values, plus one
dependency-free custom generic test so the whole project runs offline with
no `dbt deps` network call). Output parity confirmed against the
hand-written SQL ETL -- e.g. `mart_customer_rfm` produces the identical
1,381 / 1,372 / 1,241 / 969 segment split.

## A real bug this project caught

`trg_enforce_return_has_record` (a PL/pgSQL trigger requiring any order
marked `returned` to have a matching `fact_returns` row) fired during the
first real verification run and correctly rejected the ETL: the
`total_amount` backfill `UPDATE` was running before the `fact_returns`
`INSERT`, so orders already flagged `returned` in the raw data had no
matching return record yet at the moment the trigger checked. Fixed by
reordering the two statements in `sql/etl/05_load_warehouse.sql` (see the
comment block there for the full explanation). Kept in this README rather
than quietly fixed and forgotten, because it's a more honest demonstration
of trigger-enforced data quality than a synthetic example would be.

## Repo structure

```
commercelens-sql/
  sql/
    ddl/                  raw + warehouse schema, triggers, procedures
    etl/                  hand-written raw -> warehouse ETL
    advanced/             window functions, recursive CTE
    optimization/         EXPLAIN ANALYZE case study
  dbt/commercelens/       staging / intermediate / marts, schema tests
  scripts/                data generation, raw load, verification runners
  docker/init/            Postgres auto-seed script
  bi/                     Metabase setup + suggested dashboards
  docs/                   ERD, build plan, resume bullets
  results/                real captured output from actual runs
  data/                   generated CSVs (gitignored; regenerate via scripts/generate_data.py)
```
