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

-- Step B-1: Session A inserted but has not committed. Try to find the row.
SELECT id, status, amount
FROM transfers
ORDER BY id DESC LIMIT 5;
-- Expected: Session A's row is not here. xmin is IN_PROGRESS.

-- Step B-2: Confirm Session A's transaction is still open.
SELECT pid, state, xact_start, left(query, 60) AS last_query
FROM pg_stat_activity
WHERE datname = 'workshop' AND pid != pg_backend_pid()
ORDER BY xact_start;

-- *** Tell Session A to run A-2 (COMMIT) ***

-- Step B-3: Re-run. Session A's row is now visible.
-- xmin matches Session A's txid; xmax = 0.
SELECT xmin, xmax, ctid, id, status, amount
FROM transfers
ORDER BY id DESC LIMIT 5;


-- =============================================================================
-- Exercise 2.2: Read Committed vs Repeatable Read
-- =============================================================================

-- Step B-4: Insert a new account while Session A holds its snapshot.
BEGIN;
INSERT INTO accounts (owner, balance) VALUES ('new_user', 5000.00);
COMMIT;

-- *** Tell Session A to run A-4 (re-check count/sum) ***


-- =============================================================================
-- Exercise 2.3: The lost update problem
-- =============================================================================

-- Step B-6: Read the same balance Session A is about to read.
BEGIN;
SELECT balance FROM accounts WHERE id = 1;

-- Step B-7: Commit a debit of 300 before Session A writes.
UPDATE accounts SET balance = balance - 300 WHERE id = 1;
COMMIT;

-- *** Tell Session A to run A-8 ***

-- Step B-8: Dangerous pattern — application read-modify-write.
BEGIN;
SELECT balance AS read_value FROM accounts WHERE id = 1 \gset

-- *** Wait for Session A's signal before running the UPDATE ***

UPDATE accounts SET balance = :read_value - 300 WHERE id = 1;
COMMIT;


-- =============================================================================
-- Exercise 2.4: SELECT FOR UPDATE
-- =============================================================================

-- Step B-9: Session A holds a FOR UPDATE lock on account 1. This will block.
BEGIN;

SELECT pg_backend_pid();

SELECT id, balance FROM accounts WHERE id = 1 FOR UPDATE;
-- Blocks until Session A commits (step A-12).
-- Once unblocked, balance reflects Session A's debit.

SELECT id, balance FROM accounts WHERE id = 1;

UPDATE accounts SET balance = balance - 500 WHERE id = 1;
COMMIT;

SELECT id, balance FROM accounts WHERE id = 1;
