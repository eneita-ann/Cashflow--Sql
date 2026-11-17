"""Load the CSVs into SQLite and run every query in sql/02_analysis.sql, printing results."""
import csv, sqlite3
from pathlib import Path

ROOT = Path(__file__).parent
con = sqlite3.connect(ROOT / "treasury.db")
con.executescript((ROOT / "sql" / "01_schema.sql").read_text())

for table in ["bank_accounts", "fx_rates", "bank_transactions", "ledger_entries", "cash_forecast"]:
    with open(ROOT / "data" / f"{table}.csv") as f:
        rows = list(csv.reader(f))
    con.executemany(f"INSERT INTO {table} VALUES ({','.join('?' * len(rows[0]))})", rows[1:])
con.commit()

sql = (ROOT / "sql" / "02_analysis.sql").read_text()
for block in sql.split("-- name: ")[1:]:
    name, query = block.split("\n", 1)
    cur = con.execute(query)
    cols = [c[0] for c in cur.description]
    rows = cur.fetchall()
    print(f"\n=== {name.strip()} ({len(rows)} rows) ===")
    print(" | ".join(cols))
    for r in rows:
        print(" | ".join(str(v) for v in r))
