-- =============================================================================
-- Module 1: WAL and Durability
--
-- Single psql session. Work top to bottom; each exercise builds on the last.
-- Connect: psql -U participant
-- =============================================================================

SET search_path TO rootconf, public;
\timing on
\set VERBOSITY verbose

-- =============================================================================
-- Exercise 1.1: Observing WAL generation
-- =============================================================================

-- Step 1: Snapshot your current WAL position.
-- \gset stores the result as a psql variable; reference it later as :start_lsn.
SELECT pg_current_wal_lsn() AS start_lsn \gset

-- Step 2: Generate WAL with a batch insert.
INSERT INTO transfers (from_account, to_account, amount, status)
SELECT a1, a2, round((random() * 500 + 1)::numeric, 2), 'completed'
FROM (
    SELECT
        (random() * 99 + 1)::bigint AS a1,
        (random() * 99 + 1)::bigint AS a2
    FROM generate_series(1, 10000)
) t
WHERE a1 <> a2;

-- Step 3: How much WAL did those inserts generate?
SELECT pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), :'start_lsn')
) AS wal_generated;
-- Typical: 3–5 MB. Each INSERT writes a WAL record for the heap tuple
-- plus any index updates.

-- Step 4: Inspect the WAL stream.
SELECT
    wal_records,
    wal_fpi,                                         -- full-page images
    pg_size_pretty(wal_bytes::bigint) AS wal_bytes,
    wal_write,
    wal_sync,
    round(wal_write_time::numeric, 2) AS write_ms,
    round(wal_sync_time::numeric, 2)  AS sync_ms
FROM pg_stat_wal;

-- wal_fpi spikes after a checkpoint: PostgreSQL writes the full 8 kB page
-- on the first modification of an existing page after each checkpoint.
-- New pages (INSERT extending the table) don't need this protection.
-- UPDATE existing rows to guarantee existing pages are modified.
SELECT wal_fpi AS fpi0 FROM pg_stat_wal \gset

CHECKPOINT;

UPDATE transfers SET status = 'completed' WHERE id <= 1000;

SELECT wal_fpi - :fpi0 AS new_fpis FROM pg_stat_wal;
-- new_fpis > 0: each touched page got a full-page image on its first
-- post-checkpoint write. On a busy system this is the "checkpoint tax".


-- =============================================================================
-- Exercise 1.2: synchronous_commit — the durability/performance dial
-- =============================================================================

SHOW synchronous_commit;

--   on (default) — WAL fsynced before COMMIT returns. Durable on crash.
--   off          — COMMIT returns once WAL is in the OS buffer. fsync happens
--                  within wal_writer_delay (200ms). Risk: up to 200ms of
--                  committed transactions lost on hard crash. DB stays consistent.
--   local        — fsynced to primary only; standby is async.
--   remote_write — WAL on standby OS buffer, not yet fsynced.

-- We use CALL (not a DO block) because a DO block is one transaction and
-- fsyncs exactly once regardless of the setting. bench_inserts() commits
-- after every row, so synchronous_commit has its full effect.

-- We measure wal_sync counts rather than timing — fsync is near-free in
-- Docker, but the sync count difference is always clear.

-- Step 1: synchronous_commit = on
-- SET first, then sleep past wal_writer_delay for a quiescent baseline.
SET synchronous_commit = on;
SELECT pg_sleep(0.3);
SELECT wal_write AS w0, wal_sync AS s0 FROM pg_stat_wal \gset
CALL rootconf.bench_inserts(500);
SELECT wal_write - :w0 AS wal_writes, wal_sync - :s0 AS wal_syncs FROM pg_stat_wal;
-- Expected: wal_writes ≈ wal_syncs ≈ 500. One fsync per commit.
-- Observed (Docker Desktop / macOS): 501 / 501, ~88ms.

-- Step 2: synchronous_commit = off
SET synchronous_commit = off;
SELECT pg_sleep(0.3);
SELECT wal_write AS w1, wal_sync AS s1 FROM pg_stat_wal \gset
CALL rootconf.bench_inserts(500);
SELECT wal_write - :w1 AS wal_writes, wal_sync - :s1 AS wal_syncs FROM pg_stat_wal;
-- Expected: wal_writes << 500, wal_syncs ≈ 0–3. The WAL writer batches.
-- Observed (Docker Desktop / macOS): 33 / 3, ~44ms.
-- On spinning disks: 500 syncs × 5–10ms each ≈ 2.5–5s vs ~100ms off. 25–50x.

SET synchronous_commit = on;

-- Discussion:
-- 1. What workloads suit synchronous_commit = off? (event logs, telemetry, ...)
-- 2. What is the maximum data loss window with synchronous_commit = off?
-- 3. synchronous_commit = off vs fsync = off — what's the difference in risk?


-- =============================================================================
-- Exercise 1.3: Checkpoints and the write path
-- =============================================================================

-- Step 1: Establish a clean baseline. Without this, a timed checkpoint
-- (checkpoint_timeout=60s) can fire mid-exercise and confuse the numbers.
CHECKPOINT;

SELECT
    checkpoints_req    AS req,
    buffers_checkpoint AS chk_bufs,
    buffers_clean      AS bgw_bufs,
    buffers_backend    AS backend_bufs
FROM pg_stat_bgwriter \gset before_

-- Step 2: Where is the WAL recovery anchor right now?
SELECT * FROM rootconf.checkpoint_info();
-- wal_since_checkpoint should be near zero right after our CHECKPOINT.

-- Step 3: Generate dirty buffers.
INSERT INTO transfers (from_account, to_account, amount, status)
SELECT a1, a2, round((random() * 500 + 1)::numeric, 2), 'completed'
FROM (
    SELECT (random() * 99 + 1)::bigint AS a1, (random() * 99 + 1)::bigint AS a2
    FROM generate_series(1, 5000)
) t WHERE a1 <> a2;

-- Step 4: How far has WAL grown since the checkpoint?
SELECT * FROM rootconf.checkpoint_info();
-- wal_since_checkpoint reflects the heap + index changes not yet checkpointed.
-- A crash now would require replaying this much WAL to recover.

-- Step 5: Checkpoint and watch the recovery horizon shrink.
CHECKPOINT;
SELECT * FROM rootconf.checkpoint_info();
-- wal_since_checkpoint back near zero. checkpoint_lsn has advanced.

-- Step 6: What did this checkpoint actually do?
SELECT
    checkpoints_req    - :before_req       AS checkpoints_added,
    pg_size_pretty(((buffers_checkpoint - :before_chk_bufs) * 8192)::bigint) AS checkpoint_written,
    pg_size_pretty(((buffers_clean      - :before_bgw_bufs) * 8192)::bigint) AS bgwriter_written
FROM pg_stat_bgwriter;
-- checkpoint_written ≈ size of your insert workload.
-- bgwriter_written = 0 is normal here: in a single-session container the
-- checkpointer handles everything; the bgwriter has nothing to do.
-- buffers_backend (omitted): in production, non-zero means write pressure —
-- backends evicting dirty pages themselves because the bgwriter can't keep up.

-- Discussion:
-- 1. What determines how often PostgreSQL checkpoints? (checkpoint_timeout,
--    max_wal_size — whichever fires first)
-- 2. Why does a larger max_wal_size improve write throughput but increase
--    crash recovery time?
-- 3. buffers_backend is non-zero on your production system. What do you do?
