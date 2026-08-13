"""
Stands up the same real PostgreSQL instance used for the raw ETL
(sql/etl/05_load_warehouse.sql), points a generated dbt profile at it via a
Unix-socket connection, and runs `dbt run` + `dbt test` for real against the
already-loaded raw.* tables -- capturing real output (not estimated) to
results/dbt_verification_output.txt.

Must run in a single process (dbt is invoked as a subprocess against the
live pgserver instance, all within this one script) since the embedded
Postgres server does not persist across separate shell invocations.
"""
import os
import subprocess
import time

import pgserver

BASE = os.path.join(os.path.dirname(__file__), "..")
PGDATA = "/tmp/commercelens_pgdata"
DBT_PROJECT_DIR = os.path.join(BASE, "dbt", "commercelens")
PROFILES_DIR = "/tmp/commercelens_dbt_profiles"


def main():
    db = pgserver.get_server(PGDATA)  # reuses the disk-persisted raw/warehouse data
    uri = db.get_uri()  # postgresql://postgres:@/postgres?host=<PGDATA>

    os.makedirs(PROFILES_DIR, exist_ok=True)
    profile = f"""commercelens:
  target: dev
  outputs:
    dev:
      type: postgres
      host: "{PGDATA}"
      user: postgres
      password: ""
      port: 5432
      dbname: postgres
      schema: dbt_dev
      threads: 4
"""
    with open(os.path.join(PROFILES_DIR, "profiles.yml"), "w") as f:
        f.write(profile)

    env = dict(os.environ)
    env["DBT_PROFILES_DIR"] = PROFILES_DIR
    env["PATH"] = env.get("PATH", "") + ":/sessions/wonderful-focused-wright/.local/bin"

    results_path = os.path.join(BASE, "results", "dbt_verification_output.txt")
    with open(results_path, "w") as out:
        out.write("CommerceLens dbt Project - Real Verification Run\n")
        out.write(f"Run at: {time.strftime('%Y-%m-%d %H:%M:%S')}\n\n")

        for cmd_label, cmd in [
            ("dbt debug", ["dbt", "debug"]),
            ("dbt run", ["dbt", "run"]),
            ("dbt test", ["dbt", "test"]),
        ]:
            t0 = time.time()
            result = subprocess.run(
                cmd, cwd=DBT_PROJECT_DIR, env=env, capture_output=True, text=True, timeout=180
            )
            elapsed = time.time() - t0
            header = f"\n=== {cmd_label} (exit={result.returncode}, {elapsed:.1f}s) ===\n"
            print(header)
            print(result.stdout[-4000:])
            if result.returncode != 0:
                print(result.stderr[-2000:])
            out.write(header)
            out.write(result.stdout)
            if result.stderr:
                out.write("\n--- stderr ---\n" + result.stderr)

        # Sample real output from a couple of marts to prove they built with real data
        import psycopg2

        conn = psycopg2.connect(uri)
        cur = conn.cursor()
        out.write("\n\n=== Sample: mart_customer_rfm segment counts ===\n")
        try:
            cur.execute("SELECT segment, count(*) FROM dbt_dev_marts.mart_customer_rfm GROUP BY 1 ORDER BY 2 DESC;")
            for row in cur.fetchall():
                out.write(f"{row}\n")
        except Exception as e:
            out.write(f"(query failed: {e})\n")

        out.write("\n=== Sample: mart_category_sales_rollup ===\n")
        try:
            cur.execute("SELECT category_name, subcategory_count, total_sales FROM dbt_dev_marts.mart_category_sales_rollup ORDER BY total_sales DESC LIMIT 10;")
            for row in cur.fetchall():
                out.write(f"{row}\n")
        except Exception as e:
            out.write(f"(query failed: {e})\n")

        out.write("\n=== Sample: mart_monthly_revenue_growth (last 6 rows) ===\n")
        try:
            cur.execute("SELECT * FROM dbt_dev_marts.mart_monthly_revenue_growth ORDER BY order_month DESC LIMIT 6;")
            for row in cur.fetchall():
                out.write(f"{row}\n")
        except Exception as e:
            out.write(f"(query failed: {e})\n")

        cur.close()
        conn.close()

    print(f"\nFull results written to {results_path}")
    db.cleanup()


if __name__ == "__main__":
    main()
