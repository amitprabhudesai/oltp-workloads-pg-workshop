-- 03_checkpoint_fpi:
--   CHECKPOINT advances checkpoint_lsn and its counter.
--   First write after CHECKPOINT carries a full-page image (FPI);
--   subsequent writes in the same cycle are delta-only.
--   FPI is detected by ratio: first_delta > second_delta * 5.
SET search_path TO rootconf, public;

DO $$ BEGIN
    DELETE FROM accounts WHERE owner = '_regress_fpi_test';
END; $$;

-- 3.1  checkpoint_lsn advances
SELECT checkpoint_lsn AS snap FROM rootconf.checkpoint_info() \gset
CHECKPOINT;
SELECT (SELECT checkpoint_lsn FROM rootconf.checkpoint_info())
        > :'snap' AS checkpoint_lsn_advanced;

-- 3.2  checkpoint counter increments
SELECT checkpoints_req + checkpoints_timed AS snap FROM pg_stat_bgwriter \gset
CHECKPOINT;
SELECT (SELECT checkpoints_req + checkpoints_timed FROM pg_stat_bgwriter)
        > :snap AS checkpoint_count_incremented;

-- 3.3  FPI contrast: first write >> second write
-- page_lsn (INSERT) < redo_ptr after CHECKPOINT → FPI on first touch.
-- Ratio >> 5×; absolute threshold would be brittle under wal_compression.
INSERT INTO accounts (owner, balance) VALUES ('_regress_fpi_test', 100.00);
CHECKPOINT;

SELECT pg_current_wal_lsn() AS before_lsn \gset
UPDATE accounts SET balance = 200.00 WHERE owner = '_regress_fpi_test';
SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), :'before_lsn') AS first_delta \gset

SELECT pg_current_wal_lsn() AS before_lsn \gset
UPDATE accounts SET balance = 300.00 WHERE owner = '_regress_fpi_test';
SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), :'before_lsn') AS second_delta \gset

SELECT :first_delta > :second_delta * 5 AS fpi_write_larger_than_delta;

DO $$ BEGIN
    DELETE FROM accounts WHERE owner = '_regress_fpi_test';
END; $$;
