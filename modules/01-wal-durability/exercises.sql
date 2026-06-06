-- =============================================================================
-- Module 1: WAL and Durability
--
-- Run this in a single psql session. Each exercise builds on the previous.
-- Enable timing at the start and leave it on throughout.
--
-- Connect: psql -h postgres -U workshop -d workshop
-- =============================================================================

SET search_path TO rootconf, public;

\timing on
\set VERBOSITY verbose

-- =============================================================================
-- Exercise 1.1: Observing WAL generation
--
-- Goal: make WAL visible and measurable. By the end of this exercise you
-- should be able to answer: "how much WAL does my workload generate?"
-- =============================================================================

-- Step 1: Record your current WAL position (Log Sequence Number).
-- An LSN is a byte offset into the WAL stream — it increases monotonically.
SELECT pg_current_wal_lsn() AS current_lsn;

-- Save the output. You will substitute it for <start_lsn> below.

-- Step 2: Insert a batch of transfers to generate WAL.
INSERT INTO transfers (from_account, to_account, amount, status)
SELECT
    a1,
    a2,
    round((random() * 500 + 1)::numeric, 2),
    'completed'
FROM (
    SELECT
        (random() * 99 + 1)::bigint AS a1,
        (random() * 99 + 1)::bigint AS a2
    FROM generate_series(1, 10000)
) t
WHERE a1 <> a2;

-- Step 3: How much WAL did those 10,000 inserts generate?
-- Replace '<start_lsn>' with the value from Step 1.
SELECT pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), '<start_lsn>'::pg_lsn)
) AS wal_generated;

-- Typical result: ~3–5 MB for 10,000 simple rows.
-- Each INSERT writes: a WAL record for the heap tuple + any index updates.

-- Step 4: What does the WAL stream look like right now?
SELECT
    wal_records,
    wal_fpi,                                          -- full-page images
    pg_size_pretty(wal_bytes::bigint) AS wal_bytes,
    wal_write,
    wal_sync,
    round(wal_write_time::numeric, 2)  AS write_ms,
    round(wal_sync_time::numeric, 2)   AS sync_ms
FROM pg_stat_wal;

-- wal_fpi (full-page images) spikes right after a checkpoint.
-- PostgreSQL writes the entire 8 kB page on the first modification after
-- each checkpoint — this is what makes the first write after a checkpoint
-- more expensive. Try forcing a checkpoint and re-running the insert batch.
CHECKPOINT;

SELECT pg_current_wal_lsn() AS lsn_after_checkpoint;

INSERT INTO transfers (from_account, to_account, amount, status)
SELECT
    (random() * 99 + 1)::bigint,
    (random() * 99 + 1)::bigint,
    round((random() * 500 + 1)::numeric, 2),
    'completed'
FROM generate_series(1, 1000)
WHERE (random() * 99 + 1)::bigint <> (random() * 99 + 1)::bigint;

-- Compare wal_fpi before and after the checkpoint. Notice it jumped?
SELECT wal_fpi, pg_size_pretty(wal_bytes::bigint) AS wal_bytes FROM pg_stat_wal;


-- =============================================================================
-- Exercise 1.2: synchronous_commit — the durability/performance dial
--
-- Goal: understand what synchronous_commit actually controls, and measure
-- the performance difference. This is one of the most commonly misunderstood
-- PostgreSQL durability settings.
-- =============================================================================

-- Current setting
SHOW synchronous_commit;

-- What does each level mean?
--
--   on (default) — WAL is written AND fsynced to disk before COMMIT returns.
--                  The transaction is durable even if the server crashes immediately.
--
--   remote_write — (streaming replication) WAL is on the standby's OS buffer,
--                  not yet fsynced. Survives primary failure but not standby crash.
--
--   local        — WAL is fsynced to the primary only; standby is asynchronous.
--
--   off          — COMMIT returns as soon as WAL is written to the OS buffer.
--                  PostgreSQL will fsync it within wal_writer_delay (default 200ms).
--                  Risk window: up to ~200ms of committed transactions can be lost
--                  on a hard crash. The database STAYS CONSISTENT — no torn writes,
--                  no partial transactions. Just a small loss of recent commits.

-- Benchmark: 500 single-row inserts with synchronous_commit = on
SET synchronous_commit = on;
\set start_lsn `psql -h postgres -U workshop -d workshop -Atc "SELECT pg_current_wal_lsn()"`

DO $$
DECLARE i int;
BEGIN
    FOR i IN 1..500 LOOP
        INSERT INTO transfers (from_account, to_account, amount, status)
        VALUES (
            (random() * 99 + 1)::bigint,
            (random() * 99 + 1)::bigint,
            round((random() * 500 + 1)::numeric, 2),
            'completed'
        );
    END LOOP;
END;
$$;

-- Note the elapsed time shown by \timing, then repeat with off:
SET synchronous_commit = off;

DO $$
DECLARE i int;
BEGIN
    FOR i IN 1..500 LOOP
        INSERT INTO transfers (from_account, to_account, amount, status)
        VALUES (
            (random() * 99 + 1)::bigint,
            (random() * 99 + 1)::bigint,
            round((random() * 500 + 1)::numeric, 2),
            'completed'
        );
    END LOOP;
END;
$$;

-- Reset for subsequent exercises
SET synchronous_commit = on;

-- Discussion questions:
-- 1. How much faster was synchronous_commit = off? Why?
-- 2. What class of application is synchronous_commit = off appropriate for?
--    (Hint: think about event logs, telemetry, analytics inserts)
-- 3. What's the difference between synchronous_commit = off and fsync = off?
--    (Answer: fsync = off is dangerous and can corrupt the cluster on crash.
--     synchronous_commit = off only risks losing the last ~200ms of commits.)


-- =============================================================================
-- Exercise 1.3: Checkpoints and the write path
--
-- Goal: understand where checkpoints fit in the write path and why they matter
-- for both durability and performance.
-- =============================================================================

-- Checkpoint stats
SELECT
    checkpoints_timed                                        AS timed,
    checkpoints_req                                          AS requested,
    pg_size_pretty((buffers_checkpoint * 8192)::bigint)      AS checkpoint_written,
    pg_size_pretty((buffers_clean * 8192)::bigint)           AS bgwriter_written,
    pg_size_pretty((buffers_backend * 8192)::bigint)         AS backend_written,
    round(checkpoint_write_time::numeric / 1000, 2)          AS checkpoint_write_s,
    round(checkpoint_sync_time::numeric / 1000, 2)           AS checkpoint_sync_s
FROM pg_stat_bgwriter;

-- buffers_backend is the important one: when it's high, backends are writing
-- dirty pages themselves because the checkpointer/bgwriter can't keep up.
-- This causes latency spikes on write-heavy workloads.

-- Force a checkpoint and observe the counter increment
CHECKPOINT;
SELECT checkpoints_req FROM pg_stat_bgwriter;

-- Key insight: after a checkpoint, PostgreSQL only needs to replay WAL from
-- that checkpoint LSN forward to recover from a crash.
-- The checkpoint_lsn is the "durability anchor."
-- pg_control_checkpoint() requires pg_monitor (superuser-level).
-- We expose it via a SECURITY DEFINER wrapper so participant can call it.
SELECT * FROM rootconf.checkpoint_info();
-- wal_since_checkpoint grows as you write; CHECKPOINT resets it to near zero.

