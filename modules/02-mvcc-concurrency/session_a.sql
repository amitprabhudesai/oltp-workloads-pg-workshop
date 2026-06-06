-- =============================================================================
-- Module 2: MVCC and Concurrency  —  SESSION A
--
-- This is the "driver" session. Work through each exercise, pausing where
-- indicated to let Session B run its steps. The README has the full sequence.
--
-- Connect: psql -h postgres -U workshop -d workshop
-- =============================================================================

\timing on

-- =============================================================================
-- Exercise 2.1: Snapshot isolation — readers don't block writers
--
-- MVCC (Multi-Version Concurrency Control) means PostgreSQL keeps multiple
-- versions of a row. Each transaction sees a consistent snapshot of the
-- database as it existed when the transaction (or statement) began.
-- =============================================================================

-- Step A-1: Start a transaction and insert a pending transfer.
-- Do NOT commit yet.
BEGIN;

INSERT INTO transfers (from_account, to_account, amount, status)
VALUES (1, 2, 250.00, 'pending')
RETURNING id, status;

-- *** PAUSE — switch to Session B and run steps B-1 and B-2 ***
-- Session B will try to SELECT this row. It won't see it.

-- Step A-2 (after Session B has run B-2): Now commit.
COMMIT;

-- *** PAUSE — switch to Session B and run step B-3 ***
-- Session B will SELECT again. Now it sees the row.


-- =============================================================================
-- Exercise 2.2: Read Committed vs Repeatable Read
--
-- In READ COMMITTED (PostgreSQL default), each statement gets a fresh snapshot.
-- In REPEATABLE READ, the snapshot is taken at the start of the transaction
-- and held for its duration. This prevents non-repeatable reads.
-- =============================================================================

-- Step A-3: Start a REPEATABLE READ transaction and take a snapshot.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;

SELECT count(*), sum(balance) AS total_balance
FROM accounts;
-- Note these numbers. They should stay the same for this entire transaction,
-- regardless of what Session B does.

-- *** PAUSE — switch to Session B and run steps B-4 and B-5 ***
-- Session B will insert a new account and commit it.

-- Step A-4: Re-run the same query. In REPEATABLE READ you see the same result.
SELECT count(*), sum(balance) AS total_balance
FROM accounts;

COMMIT;

-- Step A-5: Now run in READ COMMITTED (the default) and repeat.
BEGIN; -- defaults to READ COMMITTED

SELECT count(*), sum(balance) AS total_balance
FROM accounts;

-- *** PAUSE — switch to Session B and run B-4 again (insert another account) ***

-- Step A-6: Re-run. In READ COMMITTED, you see Session B's new account now.
SELECT count(*), sum(balance) AS total_balance
FROM accounts;

COMMIT;


-- =============================================================================
-- Exercise 2.3: The lost update problem
--
-- MVCC protects against dirty reads, but it does NOT prevent lost updates
-- when two transactions read-modify-write the same row without coordination.
-- This is the classic double-spend problem in payments systems.
-- =============================================================================

-- First, let's check account 1's balance.
SELECT id, owner, balance FROM accounts WHERE id = 1;

-- Step A-7: Read the balance (simulating the start of a transfer).
BEGIN;
SELECT balance FROM accounts WHERE id = 1;
-- Suppose we read 5,000.00. We intend to debit 500.

-- *** PAUSE — switch to Session B and run steps B-6 and B-7 ***
-- Session B reads the same balance and commits a debit of 300 first.

-- Step A-8 (after Session B commits): Now we apply OUR debit.
-- We're computing new balance from what WE read, which is now stale.
UPDATE accounts
SET balance = balance - 500
WHERE id = 1;
COMMIT;

-- Step A-9: What's the final balance?
SELECT id, balance FROM accounts WHERE id = 1;
-- Both debits were applied correctly because we used balance = balance - 500
-- (a relative update), not balance = <value we read> - 500.
--
-- The dangerous pattern is:
--   old_bal = SELECT balance ...          -- read
--   new_bal = old_bal - 500              -- compute in application
--   UPDATE accounts SET balance = new_bal -- write stale value  ← LOST UPDATE
--
-- Demonstrate the dangerous pattern:
BEGIN;
SELECT balance AS read_value FROM accounts WHERE id = 1;
-- Application code computes: new_balance = read_value - 200

-- *** PAUSE — switch to Session B and run step B-8 ***
-- Session B concurrently debits 300, commits. Now our read_value is stale.

-- Step A-10: Write the stale computed value — this OVERWRITES Session B's update.
-- Substitute <read_value - 200> with the value you computed above.
UPDATE accounts SET balance = <read_value - 200> WHERE id = 1;
COMMIT;

SELECT id, balance FROM accounts WHERE id = 1;
-- The balance should have decreased by BOTH 300 (Session B) and 200 (us).
-- If the lost update happened, it only decreased by 200 — Session B's work is gone.


-- =============================================================================
-- Exercise 2.4: SELECT FOR UPDATE — coordinating write access
--
-- SELECT FOR UPDATE takes a row-level lock, forcing concurrent writers to
-- wait rather than race. This is how you prevent lost updates without
-- moving to SERIALIZABLE isolation.
-- =============================================================================

-- Reset account 1 to a known balance first
UPDATE accounts SET balance = 10000.00 WHERE id = 1;

-- Step A-11: Start a transfer using SELECT FOR UPDATE.
BEGIN;

SELECT id, balance FROM accounts WHERE id = 1 FOR UPDATE;
-- This acquires a row-level ExclusiveLock on account 1's tuple.

-- *** PAUSE — switch to Session B and run step B-9 ***
-- Session B will try to SELECT FOR UPDATE the same row. It will BLOCK.
-- While it's blocked, inspect pg_locks:

SELECT
    pid,
    relation::regclass AS relation,
    locktype,
    mode,
    granted,
    pg_blocking_pids(pid) AS blocked_by
FROM pg_locks
WHERE relation = 'accounts'::regclass
  AND locktype = 'relation'
ORDER BY granted DESC, pid;

-- Also look at who is waiting and why:
SELECT
    pid,
    state,
    wait_event_type,
    wait_event,
    left(query, 80) AS query
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
ORDER BY state;

-- Step A-12: Complete the transfer and commit. Session B will unblock.
UPDATE accounts SET balance = balance - 1000 WHERE id = 1;
COMMIT;

-- Session B should now proceed with the balance it sees AFTER our commit.

