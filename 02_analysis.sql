-- Treasury Cash Flow & Liquidity Analysis: analysis queries
-- Each query is separated by a "-- name:" header so run_analysis.py can execute them one by one.

-- name: 1_daily_cash_position_cad
-- Daily closing balance per account (running total with a window function),
-- converted to CAD and consolidated: the core "cash position" report.
WITH daily_flow AS (
    SELECT account_id, value_date, SUM(amount) AS net_flow
    FROM bank_transactions
    GROUP BY account_id, value_date
),
balances AS (
    SELECT d.account_id, d.value_date,
           a.opening_balance + SUM(d.net_flow) OVER (
               PARTITION BY d.account_id ORDER BY d.value_date
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS closing_balance,
           a.currency
    FROM daily_flow d
    JOIN bank_accounts a ON a.account_id = d.account_id
)
SELECT b.value_date,
       ROUND(SUM(CASE WHEN b.currency = 'CAD' THEN b.closing_balance
                      ELSE b.closing_balance * fx.rate END), 2) AS consolidated_cash_cad
FROM balances b
LEFT JOIN fx_rates fx ON fx.rate_date = b.value_date AND fx.from_ccy = b.currency AND fx.to_ccy = 'CAD'
GROUP BY b.value_date
ORDER BY b.value_date DESC
LIMIT 10;

-- name: 2_bank_to_ledger_reconciliation
-- Matches bank transactions to ledger entries on reference and flags every break:
-- missing in ledger, missing at bank, amount mismatch, or timing difference.
WITH matched AS (
    SELECT b.reference, b.account_id, b.value_date, b.amount AS bank_amount,
           g.posting_date, g.amount AS ledger_amount
    FROM bank_transactions b
    LEFT JOIN ledger_entries g ON g.reference = b.reference
    UNION ALL
    SELECT g.reference, g.account_id, NULL, NULL, g.posting_date, g.amount
    FROM ledger_entries g
    LEFT JOIN bank_transactions b ON b.reference = g.reference
    WHERE b.reference IS NULL
)
SELECT CASE
         WHEN ledger_amount IS NULL THEN 'Missing in ledger'
         WHEN bank_amount  IS NULL THEN 'Missing at bank (outstanding)'
         WHEN bank_amount <> ledger_amount THEN 'Amount mismatch'
         WHEN value_date <> posting_date THEN 'Timing difference'
       END AS break_type,
       COUNT(*) AS items,
       ROUND(SUM(COALESCE(bank_amount, 0) - COALESCE(ledger_amount, 0)), 2) AS net_difference
FROM matched
WHERE ledger_amount IS NULL OR bank_amount IS NULL
   OR bank_amount <> ledger_amount OR value_date <> posting_date
GROUP BY break_type
ORDER BY items DESC;

-- name: 3_forecast_vs_actual_by_week
-- Weekly forecast accuracy: actual net flow vs forecast, variance and absolute % error.
WITH actual AS (
    SELECT DATE(value_date, '-' || ((CAST(STRFTIME('%w', value_date) AS INTEGER) + 6) % 7) || ' days') AS week_start,
           SUM(amount) AS actual_net_flow
    FROM bank_transactions
    GROUP BY 1
),
forecast AS (
    SELECT week_start, SUM(forecast_net_flow) AS forecast_net_flow
    FROM cash_forecast GROUP BY week_start
)
SELECT a.week_start,
       ROUND(f.forecast_net_flow, 0) AS forecast,
       ROUND(a.actual_net_flow, 0)   AS actual,
       ROUND(a.actual_net_flow - f.forecast_net_flow, 0) AS variance,
       ROUND(ABS(a.actual_net_flow - f.forecast_net_flow) * 100.0
             / NULLIF(ABS(a.actual_net_flow), 0), 1) AS abs_pct_error
FROM actual a
JOIN forecast f ON f.week_start = a.week_start
ORDER BY a.week_start DESC
LIMIT 8;

-- name: 4_minimum_balance_breaches
-- Liquidity control: days on which an account closed below its minimum balance threshold.
WITH daily_flow AS (
    SELECT account_id, value_date, SUM(amount) AS net_flow
    FROM bank_transactions GROUP BY account_id, value_date
),
balances AS (
    SELECT d.account_id, d.value_date,
           a.opening_balance + SUM(d.net_flow) OVER (
               PARTITION BY d.account_id ORDER BY d.value_date) AS closing_balance,
           a.min_balance
    FROM daily_flow d JOIN bank_accounts a USING (account_id)
)
SELECT a.account_name, COUNT(*) AS breach_days,
       MIN(b.value_date) AS first_breach,
       ROUND(MIN(b.closing_balance - b.min_balance), 2) AS worst_shortfall
FROM balances b JOIN bank_accounts a USING (account_id)
WHERE b.closing_balance < b.min_balance
GROUP BY a.account_name
ORDER BY breach_days DESC;

-- name: 5_possible_duplicate_payments
-- Payment control: outflows with the same account, date, amount and category but different references.
SELECT t1.account_id, t1.value_date, t1.amount, t1.category,
       t1.reference AS reference_1, t2.reference AS reference_2
FROM bank_transactions t1
JOIN bank_transactions t2
  ON t1.account_id = t2.account_id
 AND t1.value_date = t2.value_date
 AND t1.amount = t2.amount
 AND t1.category = t2.category
 AND t1.txn_id < t2.txn_id
WHERE t1.amount < 0
ORDER BY t1.value_date;

-- name: 6_monthly_flows_mom
-- Monthly inflows and outflows with month-over-month change in net flow (LAG).
WITH monthly AS (
    SELECT STRFTIME('%Y-%m', value_date) AS month,
           SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS inflows,
           SUM(CASE WHEN amount < 0 THEN amount ELSE 0 END) AS outflows,
           SUM(amount) AS net_flow
    FROM bank_transactions GROUP BY 1
)
SELECT month, ROUND(inflows, 0) AS inflows, ROUND(outflows, 0) AS outflows, ROUND(net_flow, 0) AS net_flow,
       ROUND(net_flow - LAG(net_flow) OVER (ORDER BY month), 0) AS change_vs_prior_month
FROM monthly ORDER BY month;

-- name: 7_usd_exposure_cad_value
-- FX exposure: month-end USD balances and their CAD value, showing translation impact of rate moves.
WITH bal AS (
    SELECT a.account_id, STRFTIME('%Y-%m', t.value_date) AS month, MAX(t.value_date) AS month_end,
           a.opening_balance + (SELECT SUM(t2.amount) FROM bank_transactions t2
                                WHERE t2.account_id = a.account_id
                                  AND t2.value_date <= MAX(t.value_date)) AS usd_balance
    FROM bank_transactions t JOIN bank_accounts a USING (account_id)
    WHERE a.currency = 'USD'
    GROUP BY a.account_id, month
)
SELECT b.month, ROUND(SUM(b.usd_balance), 0) AS usd_exposure, fx.rate AS usd_cad,
       ROUND(SUM(b.usd_balance) * fx.rate, 0) AS cad_value
FROM bal b JOIN fx_rates fx ON fx.rate_date = b.month_end AND fx.from_ccy = 'USD'
GROUP BY b.month, fx.rate ORDER BY b.month;
