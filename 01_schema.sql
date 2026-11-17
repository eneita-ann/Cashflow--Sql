-- Treasury Cash Flow & Liquidity Analysis: schema
DROP TABLE IF EXISTS bank_accounts;
DROP TABLE IF EXISTS bank_transactions;
DROP TABLE IF EXISTS ledger_entries;
DROP TABLE IF EXISTS cash_forecast;
DROP TABLE IF EXISTS fx_rates;

CREATE TABLE bank_accounts (
    account_id      INTEGER PRIMARY KEY,
    account_name    TEXT NOT NULL,
    bank            TEXT NOT NULL,
    currency        TEXT NOT NULL,
    opening_balance NUMERIC NOT NULL,
    min_balance     NUMERIC NOT NULL      -- internal minimum liquidity threshold
);

CREATE TABLE bank_transactions (
    txn_id      INTEGER PRIMARY KEY,
    account_id  INTEGER REFERENCES bank_accounts(account_id),
    value_date  DATE NOT NULL,
    amount      NUMERIC NOT NULL,         -- positive = inflow, negative = outflow
    category    TEXT,
    reference   TEXT
);

CREATE TABLE ledger_entries (
    entry_id     INTEGER PRIMARY KEY,
    account_id   INTEGER REFERENCES bank_accounts(account_id),
    posting_date DATE NOT NULL,
    amount       NUMERIC NOT NULL,
    category     TEXT,
    reference    TEXT
);

CREATE TABLE cash_forecast (
    week_start        DATE,
    account_id        INTEGER REFERENCES bank_accounts(account_id),
    forecast_net_flow NUMERIC,
    PRIMARY KEY (week_start, account_id)
);

CREATE TABLE fx_rates (
    rate_date DATE,
    from_ccy  TEXT,
    to_ccy    TEXT,
    rate      NUMERIC,
    PRIMARY KEY (rate_date, from_ccy, to_ccy)
);

CREATE INDEX idx_txn_acct_date ON bank_transactions(account_id, value_date);
CREATE INDEX idx_gl_ref ON ledger_entries(reference);
