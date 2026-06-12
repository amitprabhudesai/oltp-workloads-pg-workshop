-- =============================================================================
-- Module 2: MVCC and Concurrency  —  SESSION A
--
-- Driver session. Work top to bottom, pausing where indicated for Session B.
-- Connect: psql -U participant
-- =============================================================================

SET search_path TO rootconf, public;

\timing on

-- =============================================================================
-- Setup: bring named accounts to a known state
-- =============================================================================

-- Pin three accounts to the names and balances used throughout the slides.
UPDATE accounts SET owner = 'Arun',   balance = 1000.00 WHERE id = 1;
UPDATE accounts SET owner = 'Babita', balance =  500.00 WHERE id = 2;
UPDATE accounts SET owner = 'Chirag', balance = 1500.00 WHERE id = 3;

-- Remove seed-data transfers involving these accounts so Exercise 2.1 starts clean.
DELETE FROM transfers
WHERE from_account IN (1, 2, 3)
   OR to_account   IN (1, 2, 3);

SELECT owner, balance
FROM accounts
WHERE owner IN ('Arun', 'Babita', 'Chirag')
ORDER BY id;
-- Arun=1000  Babita=500  Chirag=1500


-- =============================================================================
-- Warmup: system columns under the hood
-- =============================================================================

-- W-1: Read the system columns of Arun's row.
--   xmin  — txid that created this version
--   xmax  — txid that deleted/superseded it  (0 = live)
--   ctid  — physical address (page, item offset)
SELECT xmin, xmax, ctid, owner, balance
FROM accounts
WHERE owner = 'Arun';

-- W-2: Watch a version chain form inside a transaction.
BEGIN;

SELECT xmin, xmax, ctid, owner, balance
FROM accounts WHERE owner = 'Arun';
-- Note xmin, xmax, ctid before the update.

UPDATE accounts SET balance = balance - 100 WHERE owner = 'Arun';

SELECT xmin, xmax, ctid, owner, balance
FROM accounts WHERE owner = 'Arun';
-- xmin = our txid, xmax = 0, ctid advanced to a new slot.
-- The old version is invisible to normal SELECT (xmax = our txid, IN_PROGRESS).

ROLLBACK;  -- keep Arun's balance at 1000 for exercises below

-- W-3 (bonus — requires superuser): see both versions simultaneously via pageinspect.
-- Reconnect as postgres first: \c workshop postgres
--
-- CREATE EXTENSION IF NOT EXISTS pageinspect;
-- BEGIN;
-- UPDATE accounts SET balance = balance - 100 WHERE owner = 'Arun';
-- SELECT
--     lp AS slot, t_xmin, t_xmax, t_ctid,
--     (t_infomask & x'0100'::int) > 0 AS xmin_committed,
--     (t_infomask & x'0800'::int) > 0 AS xmax_invalid
-- FROM heap_page_items(get_raw_page('accounts', 0))
-- WHERE lp_flags = 1 AND t_xmin IS NOT NULL;
-- -- Two rows for Arun: old (xmax = our txid), new (xmin = our txid, xmax = 0).
-- ROLLBACK;


-- =============================================================================
-- Exercise 2.1: Snapshot isolation
-- =============================================================================

-- Step A-1: Insert a pending Arun → Babita transfer. Do NOT commit yet.
BEGIN;

INSERT INTO transfers (from_account, to_account, amount, status)
VALUES (
    (SELECT id FROM accounts WHERE owner = 'Arun'),
    (SELECT id FROM accounts WHERE owner = 'Babita'),
    300.00, 'pending'
)
RETURNING id, status, amount;

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
FROM accounts
WHERE owner IN ('Arun', 'Babita', 'Chirag', 'Deepa');
-- Baseline: 3 rows (Deepa does not exist yet).

-- *** PAUSE — switch to Session B: run B-4 ***

-- Step A-4: Re-run. Snapshot is fixed — Session B's Deepa insert is not visible.
SELECT count(*), sum(balance) AS total_balance
FROM accounts
WHERE owner IN ('Arun', 'Babita', 'Chirag', 'Deepa');
-- Still 3 rows under REPEATABLE READ.

COMMIT;

-- Clean up Deepa so the READ COMMITTED demo starts from the same 3-row baseline.
DELETE FROM accounts WHERE owner = 'Deepa';

-- Step A-5: Repeat under READ COMMITTED (the default).
BEGIN;

SELECT count(*), sum(balance) AS total_balance
FROM accounts
WHERE owner IN ('Arun', 'Babita', 'Chirag', 'Deepa');
-- Baseline: 3 rows (Deepa deleted above).

-- *** PAUSE — switch to Session B: run B-4 again ***

-- Step A-6: Re-run. New snapshot per statement — Session B's Deepa insert IS visible.
SELECT count(*), sum(balance) AS total_balance
FROM accounts
WHERE owner IN ('Arun', 'Babita', 'Chirag', 'Deepa');
-- Now 4 rows: READ COMMITTED takes a fresh snapshot per statement.

COMMIT;

-- Discussion:
-- 1. At which isolation level does A-4 see Deepa's new account?
-- 2. What anomaly does REPEATABLE READ prevent that READ COMMITTED allows?
-- 3. When would you choose REPEATABLE READ over the default?


-- =============================================================================
-- Exercise 2.3: The lost update problem
-- =============================================================================

-- Reset Arun's balance before the exercise.
UPDATE accounts SET balance = 1000.00 WHERE owner = 'Arun';
SELECT owner, balance FROM accounts WHERE owner IN ('Arun', 'Babita', 'Chirag') ORDER BY id;

-- -- Safe path: relative UPDATE ---------------------------------------------------

-- Step A-7: Read Arun's balance. Do not update yet.
BEGIN;
SELECT balance FROM accounts WHERE owner = 'Arun';

-- *** PAUSE — switch to Session B: run B-6, B-7 (Chirag credits Arun 200) ***

-- Step A-8: Debit Arun 300 (Arun → Babita).
-- Relative UPDATE: arithmetic runs inside the DB against the latest committed value.
-- No stale read possible.
UPDATE accounts SET balance = balance - 300 WHERE owner = 'Arun';
COMMIT;

-- Step A-9: Both updates are reflected: 1000 + 200 (B) - 300 (A) = 900.
SELECT owner, balance FROM accounts WHERE owner = 'Arun';

-- -- Dangerous path: application read-modify-write --------------------------------

-- Reset Arun's balance for the second half.
UPDATE accounts SET balance = 1000.00 WHERE owner = 'Arun';

-- Step A-10: Read Arun's balance into a psql variable.
BEGIN;
SELECT balance AS read_value FROM accounts WHERE owner = 'Arun' \gset

-- *** PAUSE — switch to Session B: run B-8 (B credits Arun from stale read) ***

-- Step A-11: Write back our stale computed value.
-- Session B's +200 credit is overwritten and lost.
UPDATE accounts SET balance = :read_value - 300 WHERE owner = 'Arun';
COMMIT;

SELECT owner, balance FROM accounts WHERE owner = 'Arun';
-- Lost update: balance = 700, not 900.  Session B's +200 credit is gone.

-- Discussion:
-- 1. Why did the relative UPDATE in A-8 preserve both updates?
-- 2. Why did the application read-modify-write in A-11 lose Session B's work?
-- 3. What isolation level causes the read-modify-write pattern to error
--    instead of silently overwriting?


-- =============================================================================
-- Exercise 2.4: SELECT FOR UPDATE
-- =============================================================================

-- Reset Arun's balance.
UPDATE accounts SET balance = 1000.00 WHERE owner = 'Arun';

-- Step A-12: Acquire a row lock before reading Arun's row.
BEGIN;

SELECT owner, balance FROM accounts WHERE owner = 'Arun' FOR UPDATE;

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

-- Step A-13: Debit Arun 300 (Arun → Babita). Session B unblocks and sees 700.
UPDATE accounts SET balance = balance - 300 WHERE owner = 'Arun';
COMMIT;

SELECT owner, balance FROM accounts WHERE owner = 'Arun';
-- After B also commits its +200: final balance should be 900.

-- Discussion:
-- 1. What lock mode does FOR UPDATE acquire? Where did you see it in pg_locks?
-- 2. What would happen if Session A used ROLLBACK instead of COMMIT?
-- 3. When is SELECT FOR UPDATE the right tool vs. a plain relative UPDATE?
