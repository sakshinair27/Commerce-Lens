# BI layer: Metabase setup

`docker compose up` starts two containers: `commercelens_pg` (Postgres 16,
auto-seeded on first boot via `docker/init/00-init.sh` -- DDL, raw CSV load,
and the full ETL all run automatically) and `commercelens_metabase`
(Metabase, using the same Postgres instance as its own application
database).

## First-time setup

1. `docker compose up -d` and wait ~30-60s for the Postgres healthcheck and
   init script to finish (`docker compose logs -f postgres` to watch it).
2. Open `http://localhost:3000` and complete Metabase's setup wizard
   (create an admin account -- this is local-only, no data leaves the
   container).
3. When Metabase asks you to connect a database, add:
   - Database type: PostgreSQL
   - Host: `postgres` (the Docker service name)
   - Port: `5432`
   - Database name: `commercelens`
   - Username / Password: `commercelens` / `commercelens`
4. Metabase will sync the schema and pick up `raw`, `warehouse`, and (if
   you've also run the dbt project against this same database)
   `dbt_dev_marts` / `dbt_dev_staging` / `dbt_dev_intermediate`.

## Suggested dashboards

Three dashboards map directly to the marts already built:

**Executive revenue overview** -- built on `warehouse.mart_customer_rfm`-
style aggregates and `dbt_dev_marts.mart_monthly_revenue_growth`: total
revenue, MoM growth %, and a state-level refund heatmap sourced from the
`fact_returns` / `dim_customer` join used in the optimization case study.

**Customer segmentation** -- built directly on `mart_customer_rfm`: a bar
chart of customer counts by `segment` (champion/loyal/at_risk/lost) plus a
table of top-monetary customers, filterable by state and signup cohort.

**Category performance** -- built on `mart_category_sales_rollup`: total
sales and line-item volume per top-level category, including everything
rolled up from subcategories via the recursive CTE.

## Why Metabase (vs. Power BI / Tableau / Looker)

FinGuard (the fintech project in this portfolio) already covers Power BI,
Tableau, and Looker with real DAX/calculated-field/LookML examples.
CommerceLens uses Metabase instead specifically because it's fully
open-source and runs in the same `docker compose up` as the database --
no desktop license, no cloud tenant, no separate signup -- so the whole
BI layer is reproducible by anyone who clones the repo.
