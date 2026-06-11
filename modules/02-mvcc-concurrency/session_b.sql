-- =============================================================================
-- Module 2: MVCC and Concurrency  —  SESSION B
--
-- Observer / concurrent writer. Run each step only when Session A signals.
-- Connect: psql -U participant
-- =============================================================================

SET search_path TO rootconf, public;

\timing on

-- =============================================================================
-- Exercise 2.1: Snapshot isolation
-- =============================================================================

-- Step B-1: Session A inserted an Arun → Babita transfer but has not committed.
-- Filter to just this transfer so the result is unambiguous.
SELECT id, amount, status
FROM transfers
WHERE from_account = (SELECT id FROM accounts WHERE owner = 'Arun')
  AND to_account   = (SELECT id FROM accounts WHERE owner = 'Babita')
ORDER BY id DESC;
-- Expected: 0 rows. Session A's INSERT is not yet visible — xmin is IN_PROGRESS.

-- Step B-2: Confirm Session A's transaction is still open.
SELECT pid, state, xact_start, left(query, 60) AS last_query
FROM pg_stat_activity
WHERE datname = 'workshop' AND pid != pg_backend_pid()
ORDER BY xact_start;

-- *** Tell Session A to run A-2 (COMMIT) ***

-- Step B-3: Re-run the same query. Session A's row is now visible.
-- xmin matches Session A's txid; xmax = 0 (live).
SELECT xmin, xmax, ctid, id, amount, status
FROM transfers
WHERE from_account = (SELECT id FROM accounts WHERE owner = 'Arun')
  AND to_account   = (SELECT id FROM accounts WHERE owner = 'Babita')
ORDER BY id DESC;


-- =============================================================================
-- Exercise 2.2: Read Committed vs Repeatable Read
-- =============================================================================

-- Step B-4: Insert a new account (Deepa) while Session A holds its snapshot.
BEGIN;
INSERT INTO accounts (owner, balance) VALUES ('Deepa', 2000.00);
COMMIT;

-- *** Tell Session A to run A-4 (re-check count/sum) ***


-- =============================================================================
-- Exercise 2.3: The lost update problem
-- =============================================================================

-- -- Safe path ---------------------------------------------------------------------

-- Step B-6: Read Arun's balance (same row Session A is about to read).
BEGIN;
SELECT balance FROM accounts WHERE owner = 'Arun';

-- Step B-7: Credit Arun 200 (Chirag → Arun). Commit before Session A writes.
UPDATE accounts SET balance = balance + 200 WHERE owner = 'Arun';
COMMIT;

-- *** Tell Session A to run A-8 ***

-- -- Dangerous path ----------------------------------------------------------------

-- Step B-8: Application read-modify-write on the reset balance.
BEGIN;
SELECT balance AS read_value FROM accounts WHERE owner = 'Arun' \gset
-- read_value = 1000 (stale — Session A will also read 1000 and write first)

-- *** Wait for Session A's signal before running the UPDATE ***

UPDATE accounts SET balance = :read_value + 200 WHERE owner = 'Arun';
COMMIT;
-- Session A wrote :read_value - 300 = 700.
-- We wrote :read_value + 200 = 1200, overwriting Session A's committed debit.
-- Or Session A overwrites us — whichever commits second wins.
-- Either way, one update is silently lost.


-- =============================================================================
-- Exercise 2.4: SELECT FOR UPDATE
-- =============================================================================

-- Step B-9: Session A holds a FOR UPDATE lock on Arun's row. This will block.
BEGIN;

SELECT pg_backend_pid();

SELECT owner, balance FROM accounts WHERE owner = 'Arun' FOR UPDATE;
-- Blocks until Session A commits (step A-13).
-- Once unblocked, balance reflects Session A's debit: Arun = 700.

SELECT owner, balance FROM accounts WHERE owner = 'Arun';

-- Credit Arun 200 (Chirag → Arun). Re-reads the post-commit value; no stale data.
UPDATE accounts SET balance = balance + 200 WHERE owner = 'Arun';
COMMIT;

-- Final: 1000 - 300 (A) + 200 (B) = 900.
SELECT owner, balance FROM accounts WHERE owner = 'Arun';
