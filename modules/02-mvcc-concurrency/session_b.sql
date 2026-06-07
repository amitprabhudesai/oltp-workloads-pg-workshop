-- =============================================================================
-- Module 2: MVCC and Concurrency  —  SESSION B
--
-- This is the "observer / concurrent writer" session. Only run each step
-- when Session A tells you to. The README has the full sequence.
--
-- Connect: psql -U participant
-- =============================================================================

SET search_path TO rootconf, public;

\timing on

-- =============================================================================
-- Exercise 2.1: Snapshot isolation
-- =============================================================================

-- Step B-1: Session A has started a transaction and inserted a transfer,
-- but has NOT committed. Try to find it.
SELECT id, status, amount
FROM transfers
ORDER BY id DESC
LIMIT 5;
-- You should NOT see Session A's pending row. MVCC hides uncommitted data.

-- Step B-2: Check pg_stat_activity to confirm Session A's transaction is live.
SELECT pid, state, xact_start, left(query, 60) AS last_query
FROM pg_stat_activity
WHERE datname = 'workshop'
  AND pid != pg_backend_pid()
ORDER BY xact_start;

-- *** Tell Session A to run step A-2 (COMMIT) ***

-- Step B-3: Now re-run the SELECT. You should see Session A's committed row.
SELECT id, status, amount
FROM transfers
ORDER BY id DESC
LIMIT 5;


-- =============================================================================
-- Exercise 2.2: Read Committed vs Repeatable Read
-- =============================================================================

-- Step B-4: Insert a new account while Session A holds its REPEATABLE READ snapshot.
BEGIN;
INSERT INTO accounts (owner, balance) VALUES ('new_user', 5000.00);
COMMIT;

-- Step B-5: Tell Session A to re-run its count/sum query (step A-4).
-- Session A's REPEATABLE READ snapshot will NOT include this new account.


-- =============================================================================
-- Exercise 2.3: The lost update problem
-- =============================================================================

-- Step B-6: Read account 1's balance (Session A is about to read it too).
BEGIN;
SELECT balance FROM accounts WHERE id = 1;
-- Read the same value Session A will read.

-- Step B-7: Apply a debit of 300 and commit BEFORE Session A does.
UPDATE accounts SET balance = balance - 300 WHERE id = 1;
COMMIT;

-- *** Tell Session A to run step A-8 (apply its debit and commit) ***

-- Step B-8 (dangerous pattern demo): Concurrent read-modify-write.
BEGIN;
SELECT balance AS read_value FROM accounts WHERE id = 1 \gset
-- \gset stores balance into :read_value — simulating "application read"

-- *** Wait for Session A's signal before running the UPDATE. ***
UPDATE accounts SET balance = :read_value - 300 WHERE id = 1;
COMMIT;


-- =============================================================================
-- Exercise 2.4: SELECT FOR UPDATE
-- =============================================================================

-- Step B-9: Session A holds a FOR UPDATE lock on account 1.
-- Try to acquire the same lock. This will BLOCK until Session A commits.
BEGIN;

SELECT pg_backend_pid();

SELECT id, balance FROM accounts WHERE id = 1 FOR UPDATE;
-- This hangs until Session A's step A-12 runs.
-- Once unblocked, you'll see the balance AFTER Session A's debit.

SELECT id, balance FROM accounts WHERE id = 1;

-- Apply Session B's debit on the post-commit balance.
UPDATE accounts SET balance = balance - 500 WHERE id = 1;
COMMIT;

-- Final balance check from both sessions:
SELECT id, balance FROM accounts WHERE id = 1;

