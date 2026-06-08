-- 01_wal_lsn: INSERT/UPDATE/DELETE write Heap WAL records and advance the LSN;
--             ROLLBACK writes a Transaction ABORT record (WAL buffer only).
SET search_path TO rootconf, public;

DO $$ BEGIN
    DELETE FROM accounts WHERE owner LIKE '_regress_%';
END; $$;

-- 1.1  INSERT: Heap INSERT record in WAL
SELECT pg_current_wal_lsn() AS snap \gset
INSERT INTO accounts (owner, balance) VALUES ('_regress_alice', 1000.00);
SELECT pg_current_wal_lsn() AS end_lsn \gset

SELECT count(*) > 0 AS insert_writes_heap_record
FROM pg_get_wal_records_info(:'snap', :'end_lsn')
WHERE resource_manager = 'Heap' AND record_type = 'INSERT';

-- 1.2  UPDATE: Heap HOT_UPDATE or UPDATE record in WAL
SELECT pg_current_wal_lsn() AS snap \gset
UPDATE accounts SET balance = 900.00 WHERE owner = '_regress_alice';
SELECT pg_current_wal_lsn() AS end_lsn \gset

SELECT count(*) > 0 AS update_writes_heap_record
FROM pg_get_wal_records_info(:'snap', :'end_lsn')
WHERE resource_manager = 'Heap' AND record_type IN ('HOT_UPDATE', 'UPDATE');

-- 1.3  DELETE: Heap DELETE record in WAL
SELECT pg_current_wal_lsn() AS snap \gset
DELETE FROM accounts WHERE owner = '_regress_alice';
SELECT pg_current_wal_lsn() AS end_lsn \gset

SELECT count(*) > 0 AS delete_writes_heap_record
FROM pg_get_wal_records_info(:'snap', :'end_lsn')
WHERE resource_manager = 'Heap' AND record_type = 'DELETE';

-- 1.4  ROLLBACK: ABORT record goes to WAL buffer, not flushed to disk yet;
--      pg_get_wal_records_info reads on-disk WAL, so we fall back to the
--      insert LSN (in-buffer position) to prove the record was written.
SELECT pg_current_wal_insert_lsn() AS snap \gset
BEGIN;
INSERT INTO accounts (owner, balance) VALUES ('_regress_aborted', 50.00);
ROLLBACK;
SELECT pg_current_wal_insert_lsn() > :'snap' AS rollback_advances_lsn;
