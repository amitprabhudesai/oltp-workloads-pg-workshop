-- 04_index_wal_amplification: HOT updates skip index WAL; non-HOT updates don't.
--   HOT fires when: no indexed column changed AND new tuple fits on same page.
--   fillfactor = 50 reserves space so HOT condition 2 is always met here.
SET search_path TO rootconf, public;

CREATE TABLE rootconf._regress_wal_amp (
    id      int  PRIMARY KEY,
    indexed text NOT NULL,
    payload text NOT NULL
) WITH (fillfactor = 50);

CREATE INDEX _regress_wal_amp_idx ON rootconf._regress_wal_amp (indexed);

INSERT INTO rootconf._regress_wal_amp VALUES (1, 'aaa', 'original');

-- Warm-up: CHECKPOINT then one dummy update to consume the first-post-checkpoint
-- FPI, so it doesn't skew the WAL-size comparison in test 4.3.
CHECKPOINT;
UPDATE rootconf._regress_wal_amp SET payload = 'warmed' WHERE id = 1;

-- 4.1  HOT update (non-indexed column) — no Btree WAL records
SELECT pg_current_wal_lsn() AS before_lsn \gset
UPDATE rootconf._regress_wal_amp SET payload = 'hot_1' WHERE id = 1;
SELECT pg_current_wal_lsn() AS after_lsn \gset

SELECT count(*) FILTER (WHERE resource_manager = 'Btree') = 0
    AS hot_update_no_index_wal
FROM pg_get_wal_records_info(:'before_lsn', :'after_lsn');

-- 4.2  Non-HOT update (indexed column) — Btree WAL records present
SELECT pg_current_wal_lsn() AS before_lsn \gset
UPDATE rootconf._regress_wal_amp SET indexed = 'bbb' WHERE id = 1;
SELECT pg_current_wal_lsn() AS after_lsn \gset

SELECT count(*) FILTER (WHERE resource_manager = 'Btree') > 0
    AS indexed_update_writes_index_wal
FROM pg_get_wal_records_info(:'before_lsn', :'after_lsn');

-- 4.3  Non-HOT update generates more total WAL than HOT update
SELECT pg_current_wal_lsn() AS before_lsn \gset
UPDATE rootconf._regress_wal_amp SET payload = 'hot_2' WHERE id = 1;
SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), :'before_lsn') AS hot_bytes \gset

SELECT pg_current_wal_lsn() AS before_lsn \gset
UPDATE rootconf._regress_wal_amp SET indexed = 'ccc' WHERE id = 1;
SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), :'before_lsn') AS indexed_bytes \gset

SELECT :indexed_bytes > :hot_bytes AS indexed_update_more_wal;

-- Cleanup
DROP INDEX rootconf._regress_wal_amp_idx;
DROP TABLE rootconf._regress_wal_amp;
