-- =============================================================================
-- Module 2: MVCC and Concurrency  —  SESSION A
--
-- Driver session. Work top to bottom, pausing where indicated for Session B.
-- Connect: psql -U participant
-- =============================================================================

SET search_path TO rootconf, public;

\timing on

-- =============================================================================
-- Warmup: system columns under the hood
-- =============================================================================

-- W-1: Read the system columns of a live row.
--   xmin  — txid that created this version
--   xmax  — txid that deleted/superseded it  (0 = live)
--   ctid  — physical address (page, item offset)
SELECT xmin, xmax, ctid, id, balance
FROM accounts
WHERE id = 1;

-- W-2: Watch a version chain form inside a transaction.
BEGIN;

SELECT xmin, xmax, ctid, id, balance
FROM accounts WHERE id = 1;
-- Note xmin, xmax, ctid before the update.

UPDATE accounts SET balance = balance - 100 WHERE id = 1;

SELECT xmin, xmax, ctid, id, balance
FROM accounts WHERE id = 1;
-- xmin = our txid, xmax = 0, ctid advanced to a new slot.
-- The old version is invisible to normal SELECT (xmax = our txid, IN_PROGRESS).

ROLLBACK;  -- keep starting balance predictable for Exercise 2.3

-- W-3 (bonus — requires superuser): see both versions simultaneously via pageinspect.
-- Reconnect as postgres first: \c workshop postgres
--
-- CREATE EXTENSION IF NOT EXISTS pageinspect;
-- BEGIN;
-- UPDATE accounts SET balance = balance - 100 WHERE id = 1;
-- SELECT
--     lp AS slot, t_xmin, t_xmax, t_ctid,
--     (t_infomask & x'0100'::int) > 0 AS xmin_committed,
--     (t_infomask & x'0800'::int) > 0 AS xmax_invalid
-- FROM heap_page_items(get_raw_page('accounts', 0))
-- WHERE lp_flags = 1 AND t_xmin IS NOT NULL;
-- -- Two rows for account 1: old (xmax = our txid), new (xmin = our txid, xmax = 0).
-- ROLLBACK;


-- =============================================================================
-- Exercise 2.1: Snapshot isolation
-- =============================================================================

-- Step A-1: Insert a pending transfer. Do NOT commit yet.
BEGIN;

INSERT INTO transfers (from_account, to_account, amount, status)
VALUES (1, 2, 250.00, 'pending')
RETURNING id, status;

-- *** PAUSE — switch to Session B: run B-1, B-2 ***

-- Step A-2: Commit.
COMMIT;

-- *** PAUSE — switch to Session B: run B-3 ***

-- Discussion:
-- 1. Why did Session B not see the row before A-2?
-- 2. xmin on the committed row matches whose txid?
-- 3. What would xmax show if Session B had deleted the row after A-2?


-- =============================================================================
-- Exercise 2.2: Read Committed vs Repeatable Read
-- =============================================================================

-- Step A-3: Open a REPEATABLE READ transaction and record the baseline.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT count(*), sum(balance) AS total_balance
FROM accounts;

-- *** PAUSE — switch to Session B: run B-4, B-5 ***

-- Step A-4: Re-run. Snapshot is fixed — Session B's insert is not visible.
SELECT count(*), sum(balance) AS total_balance
FROM accounts;

COMMIT;

-- Step A-5: Repeat under READ COMMITTED (the default).
BEGIN;

SELECT count(*), sum(balance) AS total_balance
FROM accounts;

-- *** PAUSE — switch to Session B: run B-4 again ***

-- Step A-6: Re-run. New snapshot per statement — Session B's insert IS visible.
SELECT count(*), sum(balance) AS total_balance
FROM accounts;

COMMIT;

-- Discussion:
-- 1. At which isolation level does A-4 see the new account from Session B?
-- 2. What anomaly does REPEATABLE READ prevent that READ COMMITTED allows?
-- 3. When would you choose REPEATABLE READ over the default?


-- =============================================================================
-- Exercise 2.3: The lost update problem
-- =============================================================================

SELECT id, owner, balance FROM accounts WHERE id = 1;

-- Step A-7: Read the balance. Do not update yet.
BEGIN;
SELECT balance FROM accounts WHERE id = 1;

-- *** PAUSE — switch to Session B: run B-6, B-7 ***

-- Step A-8: Apply our debit.
-- Relative update (balance = balance - 500): arithmetic runs inside the DB,
-- no stale read possible.
UPDATE accounts SET balance = balance - 500 WHERE id = 1;
COMMIT;

-- Step A-9: Both debits should be reflected.
SELECT id, balance FROM accounts WHERE id = 1;

-- Dangerous pattern: application read-modify-write.
BEGIN;
SELECT balance AS read_value FROM accounts WHERE id = 1 \gset

-- *** PAUSE — switch to Session B: run B-8 ***

-- Step A-10: Write back a stale computed value. Session B's debit will be lost.
UPDATE accounts SET balance = :read_value - 200 WHERE id = 1;
COMMIT;

SELECT id, balance FROM accounts WHERE id = 1;
-- Lost update: balance dropped by 200 only, not 200 + 300 (Session B's debit).

-- Discussion:
-- 1. Why did the relative UPDATE in A-8 preserve both debits?
-- 2. Why did the application read-modify-write in A-10 lose Session B's work?
-- 3. What isolation level causes the read-modify-write pattern to error
--    instead of silently overwriting?


-- =============================================================================
-- Exercise 2.4: SELECT FOR UPDATE
-- =============================================================================

UPDATE accounts SET balance = 10000.00 WHERE id = 1;

-- Step A-11: Acquire a row lock before reading.
BEGIN;

SELECT id, balance FROM accounts WHERE id = 1 FOR UPDATE;

-- *** PAUSE — switch to Session B: run B-9 (it will block) ***

SELECT pg_backend_pid();

SELECT
    pid,
    locktype,
    CASE WHEN relation IS NOT NULL THEN relation::regclass::text END AS relation,
    mode,
    granted,
    pg_blocking_pids(pid) AS blocked_by
FROM pg_locks
WHERE relation = 'accounts'::regclass
ORDER BY granted DESC, pid;

SELECT pid, state, wait_event_type, wait_event, left(query, 80) AS query
FROM pg_stat_activity
WHERE state != 'idle' AND pid != pg_backend_pid()
ORDER BY state;

-- Step A-12: Commit. Session B unblocks and sees the post-commit balance.
UPDATE accounts SET balance = balance - 1000 WHERE id = 1;
COMMIT;

-- Discussion:
-- 1. What lock mode does FOR UPDATE acquire? Where did you see it in pg_locks?
-- 2. What would happen if Session A used ROLLBACK instead of COMMIT?
-- 3. When is SELECT FOR UPDATE the right tool vs. a plain relative UPDATE?
