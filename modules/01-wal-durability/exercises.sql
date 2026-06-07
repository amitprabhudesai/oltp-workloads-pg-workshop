-- =============================================================================
-- Module 1: WAL and Durability
--
-- Run this in a single psql session. Each exercise builds on the previous.
-- Enable timing at the start and leave it on throughout.
--
-- Connect: psql -U participant
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

-- Step 1: Capture your current WAL position into a psql variable.
-- An LSN is a byte offset into the WAL stream — it increases monotonically.
-- \gset stores query columns as psql variables; reference them as :varname.
SELECT pg_current_wal_lsn() AS start_lsn \gset

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
SELECT pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), :'start_lsn')
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
SELECT a1, a2, round((random() * 500 + 1)::numeric, 2), 'completed'
FROM (
    SELECT
        (random() * 99 + 1)::bigint AS a1,
        (random() * 99 + 1)::bigint AS a2
    FROM generate_series(1, 1000)
) t
WHERE a1 <> a2;

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

-- Why CALL and not a DO block?
-- A DO block is ONE transaction — it fsyncs exactly once at the end regardless
-- of synchronous_commit. To observe per-commit sync behaviour each insert needs
-- its own COMMIT. Only a PROCEDURE allows COMMIT inside its body.
-- rootconf.bench_inserts(n) does exactly that: n inserts, n commits.

-- We measure wal_sync COUNTS rather than wall-clock time.
-- In a Docker container fsync is near-free (NVMe + VM buffering), so timing
-- doesn't reveal the difference. But the sync count always does:
--   synchronous_commit = on  → each COMMIT drives one WAL sync → wal_sync ≈ n
--   synchronous_commit = off → WAL writer batches syncs every wal_writer_delay
--                              (200ms default) → wal_sync stays near zero
--                              during a short run.
-- On real hardware the timing difference is dramatic (5–20x on spinning disks).

-- Step 1: synchronous_commit = on
-- Sleep > wal_writer_delay (200ms) so the WAL writer completes its current
-- cycle and idles out. Both runs then start from the same quiescent state,
-- reducing variance in the wal_sync counts.
SELECT pg_sleep(0.3);
SELECT wal_write, wal_sync FROM pg_stat_wal \gset before_on_

SET synchronous_commit = on;
CALL rootconf.bench_inserts(500);

SELECT
    wal_write - :before_on_wal_write  AS wal_writes,
    wal_sync  - :before_on_wal_sync   AS wal_syncs
FROM pg_stat_wal;
-- Expected: wal_writes ≈ wal_syncs ≈ 500.
-- Each COMMIT drove its own write-and-sync cycle before returning to the client.
-- Observed on Docker Desktop / macOS: wal_writes=501, wal_syncs=501, ~88ms.

-- Step 2: synchronous_commit = off
SELECT pg_sleep(0.3);
SELECT wal_write, wal_sync FROM pg_stat_wal \gset before_off_

SET synchronous_commit = off;
CALL rootconf.bench_inserts(500);

SELECT
    wal_write - :before_off_wal_write AS wal_writes,
    wal_sync  - :before_off_wal_sync  AS wal_syncs
FROM pg_stat_wal;
-- Expected: wal_writes << 500, wal_syncs ≈ 0–3.
-- The committing backend only appended to the in-memory WAL ring buffer and
-- returned immediately. The WAL writer owns the flush schedule (fires every
-- wal_writer_delay, default 200ms) — most records were still in shared memory
-- when this SELECT ran.
-- Observed on Docker Desktop / macOS: wal_writes=33, wal_syncs=3, ~44ms.
--
-- On Docker the 2x timing gap understates the real effect. On spinning disks
-- each fsync costs ~5–10ms, so 500 x on-commits ≈ 2.5–5 s vs ~100 ms off.
-- That 25–50x gap is what drives the use of this setting in production.

-- Reset
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

-- Step 1: Force a checkpoint to establish a clean, known baseline.
-- Without this, a timed checkpoint (checkpoint_timeout=60s) can fire mid-exercise
-- and shrink wal_since_checkpoint unexpectedly, obscuring the story.
CHECKPOINT;

SELECT
    checkpoints_req     AS req,
    buffers_checkpoint  AS chk_bufs,
    buffers_clean       AS bgw_bufs,
    buffers_backend     AS backend_bufs
FROM pg_stat_bgwriter \gset before_

-- Step 2: Confirm the checkpoint LSN anchor. wal_since_checkpoint should be
-- near zero right after the CHECKPOINT above.
SELECT * FROM rootconf.checkpoint_info();

-- Step 3: Generate some dirty buffers.
INSERT INTO transfers (from_account, to_account, amount, status)
SELECT a1, a2, round((random() * 500 + 1)::numeric, 2), 'completed'
FROM (
    SELECT (random() * 99 + 1)::bigint AS a1, (random() * 99 + 1)::bigint AS a2
    FROM generate_series(1, 5000)
) t WHERE a1 <> a2;

-- Step 4: How far has WAL advanced since the last checkpoint?
SELECT * FROM rootconf.checkpoint_info();
-- wal_since_checkpoint should now show several MB of unflushed heap changes.

-- Step 5: Force a checkpoint and observe.
CHECKPOINT;

SELECT * FROM rootconf.checkpoint_info();
-- wal_since_checkpoint resets to near zero: the checkpoint_lsn has advanced,
-- so crash recovery now only needs to replay from here forward.

-- Step 6: Show what happened in this exercise (delta, not lifetime totals).
SELECT
    checkpoints_req    - :before_req         AS checkpoints_added,
    pg_size_pretty(((buffers_checkpoint - :before_chk_bufs)  * 8192)::bigint) AS checkpoint_written,
    pg_size_pretty(((buffers_clean      - :before_bgw_bufs)  * 8192)::bigint) AS bgwriter_written
FROM pg_stat_bgwriter;

-- Expected: checkpoints_added=1, checkpoint_written ≈ size of your INSERT,
-- bgwriter_written=0 (bgwriter has nothing to do in a single-session container
-- with 60s checkpoints — the checkpointer handles everything).

-- NOTE on buffers_backend (not shown above):
-- In this container, log_autovacuum_min_duration=0 makes autovacuum very
-- aggressive. Its buffer writes are attributed to buffers_backend, making
-- the metric noisy for our purposes.
-- In production, buffers_backend > 0 is the signal that matters:
-- it means backends had to write dirty pages themselves (buffer eviction
-- under pressure) rather than the bgwriter staying ahead.
-- Sustained buffers_backend > 0 → tune bgwriter_lru_maxpages/bgwriter_delay
-- or increase shared_buffers.

