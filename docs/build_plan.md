# Build plan (5-7 days)

**Day 1 -- Schema design + raw landing layer.** Design the star schema
(dimensions/facts, grain of each fact table). Write `sql/ddl/01_raw_schema.sql`
(permissive landing tables) and `sql/ddl/02_warehouse_schema.sql` (constrained
star schema with CHECK constraints and a deferred self-referencing FK on
`dim_category`).

**Day 2 -- Synthetic data + triggers/procedures.** Build
`scripts/generate_data.py` (Faker, seeded) to produce a realistically messy
dataset: mixed date formats, ~25 injected duplicate customer rows, mixed
price-string formatting, a skewed order-status distribution. Write
`sql/ddl/03_triggers.sql` (status-change audit trigger, a data-quality
enforcement trigger requiring returned orders to have a matching return
record) and `sql/ddl/04_procedures.sql` (a PL/pgSQL LTV function + a
customer-summary refresh procedure).

**Day 3 -- ETL + advanced SQL.** Write the hand-written ETL
(`sql/etl/05_load_warehouse.sql`) and `scripts/load_raw.py`. Write the
window-function demos (RFM segmentation, MoM growth, cohort retention) and
the recursive CTE category rollup. Run everything against a real Postgres
instance and fix whatever the constraints/triggers catch -- in this build, a
real ETL statement-ordering bug was caught by the return-enforcement
trigger on the first run and fixed by re-sequencing the ETL.

**Day 4 -- Query optimization case study.** Pick a realistic, unindexed
query pattern, capture `EXPLAIN ANALYZE` before indexing, add targeted
indexes, capture `EXPLAIN ANALYZE` after, and document the honest result --
including that a full-table aggregate query's plan didn't change (Postgres
correctly prefers hash joins + seq scans at this data volume), while a
selective point-lookup query showed a clean Seq Scan -> Index Scan flip.

**Day 5 -- dbt project.** Rebuild the same transformation as a proper dbt
project: `staging` (1:1 cleaned sources), `intermediate` (reusable joins/
aggregations), `marts` (dimensional model + business marts: RFM, category
rollup, MoM growth, cohort retention). Add schema tests (uniqueness,
not-null, relationships, accepted values) and a dependency-free custom
generic test. Run `dbt run` + `dbt test` for real against the same Postgres
instance and confirm parity with the hand-written ETL's numbers.

**Day 6 -- Containerization + BI layer.** Write `docker-compose.yml` +
`docker/init/00-init.sh` so `docker compose up` alone stands up Postgres,
applies all DDL, loads the data, and runs the ETL with zero manual steps.
Wire up Metabase against the same Postgres instance and build the three
core dashboards (revenue overview, customer segmentation, category
performance).

**Day 7 -- Docs + polish.** Write the README (with real captured numbers,
not estimates), ERD doc, this build plan, and resume bullets sourced from
the actual verification run's output. Package the repo.
