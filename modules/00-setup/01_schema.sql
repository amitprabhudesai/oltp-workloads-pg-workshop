-- =============================================================================
-- Workshop Schema: Payments / Transfers
--
-- All objects live in the 'rootconf' schema.
-- Each SQL file sets search_path so table names can be used unqualified.
--
--   accounts  — hot rows: balance updates drive write contention and MVCC demos
--   transfers — insert-heavy: good for observing WAL generation
--   audit_log — append-only: illustrates write amplification
-- =============================================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS rootconf;

SET search_path TO rootconf, public;

CREATE TABLE IF NOT EXISTS accounts (
    id          BIGSERIAL PRIMARY KEY,
    owner       TEXT        NOT NULL,
    balance     NUMERIC(12, 2) NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT balance_non_negative CHECK (balance >= 0)
);

CREATE TABLE IF NOT EXISTS transfers (
    id              BIGSERIAL PRIMARY KEY,
    from_account    BIGINT      NOT NULL REFERENCES accounts(id),
    to_account      BIGINT      NOT NULL REFERENCES accounts(id),
    amount          NUMERIC(12, 2) NOT NULL,
    status          TEXT        NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT amount_positive     CHECK (amount > 0),
    CONSTRAINT valid_status        CHECK (status IN ('pending', 'completed', 'failed')),
    CONSTRAINT different_accounts  CHECK (from_account <> to_account)
);

-- Append-only audit trail written on every balance change.
-- Useful for illustrating write amplification: one transfer = 3 WAL writes
-- (debit accounts row, credit accounts row, audit_log insert).
CREATE TABLE IF NOT EXISTS audit_log (
    id          BIGSERIAL PRIMARY KEY,
    account_id  BIGINT      NOT NULL REFERENCES accounts(id),
    delta       NUMERIC(12, 2) NOT NULL,   -- negative = debit, positive = credit
    balance_after NUMERIC(12, 2) NOT NULL,
    transfer_id BIGINT      REFERENCES transfers(id),
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS transfers_from_account_idx ON transfers(from_account);
CREATE INDEX IF NOT EXISTS transfers_to_account_idx   ON transfers(to_account);
CREATE INDEX IF NOT EXISTS audit_log_account_idx      ON audit_log(account_id);

COMMIT;
