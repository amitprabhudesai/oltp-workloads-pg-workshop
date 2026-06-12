-- 03_checkpoint_fpi:
--   CHECKPOINT advances checkpoint_lsn and its counter.
--   First write after CHECKPOINT carries a full-page image (fpi_length > 0);
--   subsequent writes in the same cycle are delta-only (fpi_length = 0).
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

-- 3.3  First write after CHECKPOINT carries an FPI (fpi_length > 0)
INSERT INTO accounts (owner, balance) VALUES ('_regress_fpi_test', 100.00);
CHECKPOINT;

SELECT pg_current_wal_lsn() AS before_lsn \gset
UPDATE accounts SET balance = 200.00 WHERE owner = '_regress_fpi_test';
SELECT pg_current_wal_lsn() AS after_lsn \gset

SELECT sum(fpi_length) > 0 AS first_write_has_fpi
FROM pg_get_wal_records_info(:'before_lsn', :'after_lsn')
WHERE resource_manager = 'Heap';

-- 3.4  Second write to the same page is delta-only (fpi_length = 0)
SELECT pg_current_wal_lsn() AS before_lsn \gset
UPDATE accounts SET balance = 300.00 WHERE owner = '_regress_fpi_test';
SELECT pg_current_wal_lsn() AS after_lsn \gset

SELECT sum(fpi_length) = 0 AS second_write_no_fpi
FROM pg_get_wal_records_info(:'before_lsn', :'after_lsn')
WHERE resource_manager = 'Heap';

DO $$ BEGIN
    DELETE FROM accounts WHERE owner = '_regress_fpi_test';
END; $$;
