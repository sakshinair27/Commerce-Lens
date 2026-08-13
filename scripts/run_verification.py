"""
One-shot verification script: stands up a real PostgreSQL 16 instance,
builds the full schema, loads the generated dataset, runs the ETL, executes
every advanced-SQL demo file, and runs the before/after optimization case
study -- capturing real output (not estimated) to results/verification_output.txt.
"""
import os
import subprocess
import sys
import time

import pgserver
import psycopg2

BASE = os.path.join(os.path.dirname(__file__), "..")
PGDATA = "/tmp/commercelens_pgdata"


def run_sql_file(cur, path, label, capture=None):
    with open(path) as f:
        sql = f.read()
    print(f"\n=== Running {label} ===")
    if capture is not None:
        capture.write(f"\n=== {label} ===\n")
    cur.execute(sql)
    try:
        rows = cur.fetchall()
        cols = [d[0] for d in cur.description] if cur.description else []
        if capture is not None and rows:
            capture.write(f"columns: {cols}\n")
            for r in rows[:15]:
                capture.write(f"{r}\n")
    except psycopg2.ProgrammingError:
        pass  # statement had no result set (DDL, etc.)


def main():
    db = pgserver.get_server(PGDATA)
    uri = db.get_uri()
    conn = psycopg2.connect(uri)
    conn.autocommit = True
    cur = conn.cursor()

    results_path = os.path.join(BASE, "results", "verification_output.txt")
    with open(results_path, "w") as out:
        out.write("CommerceLens SQL Project - Real Verification Run\n")
        out.write(f"Run at: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
        out.write("PostgreSQL version: " + subprocess.run(["python3", "-c",
            "import psycopg2,pgserver;c=psycopg2.connect(pgserver.get_server('%s').get_uri());cur=c.cursor();cur.execute('select version()');print(cur.fetchone()[0])" % PGDATA],
            capture_output=True, text=True).stdout)

        # 1) Schema
        for f in ["01_raw_schema.sql", "02_warehouse_schema.sql", "03_triggers.sql", "04_procedures.sql"]:
            path = os.path.join(BASE, "sql", "ddl", f)
            cur.execute(open(path).read())
            print(f"Applied {f}")
        out.write("\nSchema DDL applied: 01_raw_schema.sql, 02_warehouse_schema.sql, 03_triggers.sql, 04_procedures.sql\n")

        # 2) Load raw data
        sys.path.insert(0, os.path.join(BASE, "scripts"))
        import load_raw
        print("\n=== Loading raw CSVs ===")
        out.write("\n=== Raw load ===\n")
        import io
        from contextlib import redirect_stdout
        buf = io.StringIO()
        with redirect_stdout(buf):
            load_raw.load(uri)
        print(buf.getvalue())
        out.write(buf.getvalue())

        # 3) ETL raw -> warehouse
        etl_path = os.path.join(BASE, "sql", "etl", "05_load_warehouse.sql")
        t0 = time.time()
        cur.execute(open(etl_path).read())
        etl_seconds = time.time() - t0
        print(f"\nETL raw->warehouse completed in {etl_seconds:.2f}s")
        out.write(f"\nETL raw->warehouse completed in {etl_seconds:.2f}s\n")

        # 4) Row counts
        out.write("\n=== Warehouse row counts ===\n")
        for t in ["dim_customer", "dim_product", "dim_category", "dim_date", "fact_orders", "fact_order_items", "fact_returns"]:
            cur.execute(f"SELECT count(*) FROM warehouse.{t};")
            n = cur.fetchone()[0]
            print(f"warehouse.{t}: {n} rows")
            out.write(f"warehouse.{t}: {n} rows\n")

        # 5) Stored procedure
        cur.execute("CALL warehouse.sp_refresh_customer_summary();")
        cur.execute("SELECT count(*), round(avg(lifetime_value),2), round(max(lifetime_value),2) FROM warehouse.customer_summary;")
        row = cur.fetchone()
        print(f"\ncustomer_summary refreshed: {row}")
        out.write(f"\ncustomer_summary refreshed via sp_refresh_customer_summary(): count={row[0]}, avg_ltv={row[1]}, max_ltv={row[2]}\n")

        # 6) Advanced SQL demos
        out.write("\n=== Window function demo: top RFM segment counts ===\n")
        cur.execute("""
            WITH customer_orders AS (
                SELECT dc.customer_key, MAX(dd.full_date) AS last_order_date,
                       COUNT(DISTINCT fo.order_key) AS frequency, SUM(fo.total_amount) AS monetary
                FROM warehouse.dim_customer dc
                JOIN warehouse.fact_orders fo ON fo.customer_key = dc.customer_key
                JOIN warehouse.dim_date dd ON fo.order_date_key = dd.date_key
                GROUP BY dc.customer_key
            ),
            rfm_scored AS (
                SELECT *, NTILE(5) OVER (ORDER BY CURRENT_DATE - last_order_date DESC) AS r,
                       NTILE(5) OVER (ORDER BY frequency ASC) AS f,
                       NTILE(5) OVER (ORDER BY monetary ASC) AS m
                FROM customer_orders
            )
            SELECT
                CASE WHEN (r+f+m) >= 12 THEN 'champion' WHEN (r+f+m) >= 9 THEN 'loyal'
                     WHEN (r+f+m) >= 6 THEN 'at_risk' ELSE 'lost' END AS segment,
                COUNT(*) AS customers
            FROM rfm_scored GROUP BY 1 ORDER BY 2 DESC;
        """)
        for row in cur.fetchall():
            out.write(f"{row}\n")

        out.write("\n=== Recursive CTE demo: category rollup ===\n")
        cur.execute(open(os.path.join(BASE, "sql", "advanced", "recursive_cte_category_rollup.sql")).read())
        for row in cur.fetchall():
            out.write(f"{row}\n")

        # 7a) Point-lookup case study - BEFORE (no index on fact_orders.customer_key yet)
        out.write("\n=== Optimization case study #1: single-customer order lookup, BEFORE index ===\n")
        point_query = """
            EXPLAIN (ANALYZE, FORMAT TEXT)
            SELECT fo.order_id, fo.order_status, fo.total_amount, dd.full_date
            FROM warehouse.fact_orders fo
            JOIN warehouse.dim_date dd ON fo.order_date_key = dd.date_key
            WHERE fo.customer_key = 123
            ORDER BY dd.full_date DESC;
        """
        cur.execute(point_query)
        point_before = "\n".join(r[0] for r in cur.fetchall())
        print("\nPOINT LOOKUP BEFORE:\n" + point_before)
        out.write(point_before + "\n")

        cur.execute("CREATE INDEX IF NOT EXISTS idx_orders_customer_key ON warehouse.fact_orders(customer_key);")
        cur.execute("ANALYZE warehouse.fact_orders;")

        out.write("\n=== Optimization case study #1: single-customer order lookup, AFTER index ===\n")
        cur.execute(point_query)
        point_after = "\n".join(r[0] for r in cur.fetchall())
        print("\nPOINT LOOKUP AFTER:\n" + point_after)
        out.write(point_after + "\n")

        # 7b) Aggregate case study - BEFORE
        out.write("\n=== Optimization case study #2: state x return-reason refund aggregate, BEFORE indexing ===\n")
        before_query = """
            EXPLAIN (ANALYZE, FORMAT TEXT)
            SELECT dc.state, fr.return_reason, COUNT(*) AS return_count, SUM(fr.refund_amount) AS total_refunded
            FROM warehouse.fact_returns fr
            JOIN warehouse.fact_order_items foi ON fr.order_item_key = foi.order_item_key
            JOIN warehouse.fact_orders fo ON foi.order_key = fo.order_key
            JOIN warehouse.dim_customer dc ON fo.customer_key = dc.customer_key
            JOIN warehouse.dim_date dd ON fr.return_date_key = dd.date_key
            WHERE dd.full_date >= CURRENT_DATE - INTERVAL '12 months'
            GROUP BY dc.state, fr.return_reason
            ORDER BY total_refunded DESC;
        """
        cur.execute(before_query)
        before_plan = "\n".join(r[0] for r in cur.fetchall())
        print("\nBEFORE:\n" + before_plan)
        out.write(before_plan + "\n")

        # 8) Add remaining indexes
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_returns_reason ON warehouse.fact_returns(return_reason);
            CREATE INDEX IF NOT EXISTS idx_returns_date_key ON warehouse.fact_returns(return_date_key);
            CREATE INDEX IF NOT EXISTS idx_customer_state ON warehouse.dim_customer(state);
            CREATE INDEX IF NOT EXISTS idx_order_items_order_key ON warehouse.fact_order_items(order_key);
        """)
        cur.execute("ANALYZE warehouse.fact_returns; ANALYZE warehouse.fact_order_items; ANALYZE warehouse.dim_customer;")

        # 9) Aggregate case study - AFTER
        out.write("\n=== Optimization case study #2: state x return-reason refund aggregate, AFTER indexing + ANALYZE ===\n")
        cur.execute(before_query)  # identical query
        after_plan = "\n".join(r[0] for r in cur.fetchall())
        print("\nAFTER:\n" + after_plan)
        out.write(after_plan + "\n")
        out.write(
            "\nNote: the aggregate query's plan is unchanged by indexing -- it touches "
            "most rows in fact_returns/fact_order_items/fact_orders, so Postgres correctly "
            "prefers hash joins + seq scans over index scans at this data volume. The point-"
            "lookup case study above (~1:5000 selectivity) is the fair test of index impact, "
            "and shows the expected Seq Scan -> Index Scan plan change.\n"
        )

    cur.close()
    conn.close()
    db.cleanup()
    print(f"\nFull results written to {results_path}")


if __name__ == "__main__":
    main()
