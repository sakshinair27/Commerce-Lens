# Schema / ERD

Three schemas, in order of the pipeline: `raw` (landing) -> `warehouse`
(hand-written SQL ETL target) -> `dbt_dev_*` (the dbt rebuild of the same
transformation, for comparison). This doc describes `warehouse`, the star
schema both approaches converge on.

## Star schema

```
                         dim_date
                            |
                            | order_date_key
                            |
dim_customer ---- customer_key ---- fact_orders ---- order_key ---- fact_order_items ---- product_key ---- dim_product
                                                                          |                                      |
                                                                          | order_item_key                       | category_key
                                                                          |                                      |
                                                                     fact_returns                            dim_category
                                                                     (return_date_key -> dim_date)          (self-referencing:
                                                                                                              parent_category_id)
```

## Tables

**dim_customer** -- one row per deduped customer (`customer_id` unique after
`DISTINCT ON` dedup in the ETL / dbt staging layer). `customer_key` surrogate
PK.

**dim_product** -- one row per product, FK to `dim_category`.

**dim_category** -- self-referencing on `parent_category_id` (nullable FK,
`DEFERRABLE INITIALLY DEFERRED` in the raw DDL so parent/child rows can be
inserted in either order within one transaction). This is what the recursive
CTE in `sql/advanced/recursive_cte_category_rollup.sql` walks.

**dim_date** -- calendar spine, `2024-01-01` to `2026-12-31`, `date_key` as
`YYYYMMDD` integer surrogate key (standard Kimball convention -- sorts and
partitions cleanly).

**fact_orders** -- one row per order. `total_amount` is derived (summed from
`fact_order_items`, not trusted from the raw source) and backfilled after
line items load. `order_status` is constrained to
`placed | shipped | delivered | cancelled | returned`.

**fact_order_items** -- one row per order line item, FK to both
`fact_orders` and `dim_product`. `line_total` is computed:
`quantity * unit_price * (1 - discount_pct/100)`.

**fact_returns** -- one row per return, FK to `fact_order_items`. Enforced
by `trg_enforce_return_has_record`: any order flagged `returned` in
`fact_orders` must have a matching `fact_returns` row, or the update is
rejected. This trigger caught a real bug in the ETL's statement ordering
during development (see `sql/etl/05_load_warehouse.sql` header comment).

**order_status_audit** -- append-only log written by
`trg_log_order_status_change`, one row per status transition on
`fact_orders` (old status, new status, changed_at).

**customer_summary** -- materialized by `sp_refresh_customer_summary()`
(callable stored procedure, not a view) using `fn_customer_ltv()`, a
PL/pgSQL function computing customer lifetime value as of a given date.

## Constraints worth noting

Every raw table is intentionally permissive (`TEXT` columns, no
constraints) to mirror real messy source-system exports -- mixed date
formats, `"$19.99"` vs `"19.99"` price strings, inconsistent email casing,
~25 exact-duplicate customer rows. All cleaning happens in the ETL /
staging layer, not the landing schema. `fact_order_items.quantity`,
`unit_price`, and `discount_pct` all carry `CHECK` constraints
(non-negative, discount 0-100) at the warehouse layer.
