"""Generate synthetic treasury data (bank accounts, bank transactions, ledger entries,
cash forecasts, FX rates) as CSV files. All data is fictional. Seeded for reproducibility."""
import csv, random, datetime as dt
from pathlib import Path

random.seed(42)
OUT = Path(__file__).parent / "data"
OUT.mkdir(exist_ok=True)

START, DAYS = dt.date(2025, 1, 1), 180
accounts = [
    (1, "Operating CAD", "Bank A", "CAD", 1_200_000, 250_000),
    (2, "Payroll CAD", "Bank A", "CAD", 400_000, 100_000),
    (3, "Collections CAD", "Bank B", "CAD", 650_000, 50_000),
    (4, "Operating USD", "Bank C", "USD", 500_000, 150_000),
    (5, "Reserve USD", "Bank C", "USD", 900_000, 600_000),
]
categories_in = ["Client Receipts", "Card Settlements", "Interest Income"]
categories_out = ["Vendor Payments", "Payroll", "Tax Remittance", "Bank Fees", "Card Program Funding"]

with open(OUT / "bank_accounts.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["account_id", "account_name", "bank", "currency", "opening_balance", "min_balance"])
    w.writerows(accounts)

# FX rates USD->CAD
with open(OUT / "fx_rates.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["rate_date", "from_ccy", "to_ccy", "rate"])
    rate = 1.36
    for d in range(DAYS):
        rate = round(rate + random.uniform(-0.006, 0.006), 4)
        w.writerow([START + dt.timedelta(d), "USD", "CAD", rate])

txns, ledger, txn_id, gl_id = [], [], 1, 1
for d in range(DAYS):
    day = START + dt.timedelta(d)
    if day.weekday() >= 5:
        continue
    for acc in accounts:
        aid = acc[0]
        n = random.randint(2, 6)
        for _ in range(n):
            inflow = random.random() < 0.5
            cat = random.choice(categories_in if inflow else categories_out)
            if aid == 2 and not inflow:
                cat = "Payroll"
            amt = round(random.uniform(2_000, 60_000), 2) * (1 if inflow else -1)
            ref = f"REF{txn_id:06d}"
            txns.append([txn_id, aid, day, amt, cat, ref])
            # Ledger normally mirrors the bank; inject reconciliation breaks
            r = random.random()
            if r < 0.015:
                pass  # missing in ledger (unrecorded bank item)
            elif r < 0.03:
                ledger.append([gl_id, aid, day + dt.timedelta(days=random.randint(1, 3)), amt, cat, ref]); gl_id += 1  # timing difference
            elif r < 0.04:
                ledger.append([gl_id, aid, day, round(amt + random.choice([-100, 50, 250]), 2), cat, ref]); gl_id += 1  # amount mismatch
            else:
                ledger.append([gl_id, aid, day, amt, cat, ref]); gl_id += 1
            txn_id += 1
    # occasional duplicate vendor payment
    if random.random() < 0.03:
        t = next(x for x in reversed(txns) if x[4] == "Vendor Payments")
        txns.append([txn_id, t[1], t[2], t[3], t[4], f"REF{txn_id:06d}"]); txn_id += 1

# ledger-only entries (recorded in books, not yet cleared at bank)
for _ in range(8):
    aid = random.randint(1, 5); day = START + dt.timedelta(random.randint(0, DAYS - 1))
    ledger.append([gl_id, aid, day, -round(random.uniform(1_000, 20_000), 2), "Vendor Payments", f"CHQ{gl_id:05d}"]); gl_id += 1

with open(OUT / "bank_transactions.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["txn_id", "account_id", "value_date", "amount", "category", "reference"]); w.writerows(txns)
with open(OUT / "ledger_entries.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["entry_id", "account_id", "posting_date", "amount", "category", "reference"]); w.writerows(ledger)

# weekly cash forecast by account (net flow), with realistic error
with open(OUT / "cash_forecast.csv", "w", newline="") as f:
    w = csv.writer(f); w.writerow(["week_start", "account_id", "forecast_net_flow"])
    weeks = {}
    for t in txns:
        ws = t[2] - dt.timedelta(days=t[2].weekday())
        weeks[(ws, t[1])] = weeks.get((ws, t[1]), 0) + t[3]
    for (ws, aid), actual in sorted(weeks.items()):
        w.writerow([ws, aid, round(actual * random.uniform(0.8, 1.2) + random.uniform(-15_000, 15_000), 2)])

print(f"{len(txns)} bank transactions, {len(ledger)} ledger entries written to {OUT}")
