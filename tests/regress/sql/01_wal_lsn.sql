-- 01_wal_lsn: INSERT/UPDATE/DELETE advance pg_current_wal_lsn();
--             ROLLBACK advances pg_current_wal_insert_lsn() (in-buffer).
SET search_path TO rootconf, public;

DO $$ BEGIN
    DELETE FROM accounts WHERE owner LIKE '_regress_%';
END; $$;

-- 1.1  INSERT
SELECT pg_current_wal_lsn() AS snap \gset
INSERT INTO accounts (owner, balance) VALUES ('_regress_alice', 1000.00);
SELECT pg_current_wal_lsn() > :'snap' AS insert_advances_lsn;

-- 1.2  UPDATE
SELECT pg_current_wal_lsn() AS snap \gset
UPDATE accounts SET balance = 900.00 WHERE owner = '_regress_alice';
SELECT pg_current_wal_lsn() > :'snap' AS update_advances_lsn;

-- 1.3  DELETE
SELECT pg_current_wal_lsn() AS snap \gset
DELETE FROM accounts WHERE owner = '_regress_alice';
SELECT pg_current_wal_lsn() > :'snap' AS delete_advances_lsn;

-- 1.4  ROLLBACK: ABORT record goes to WAL buffer, not flushed to disk yet;
--      use insert LSN (in-buffer), not write LSN (on-disk).
SELECT pg_current_wal_insert_lsn() AS snap \gset
BEGIN;
INSERT INTO accounts (owner, balance) VALUES ('_regress_aborted', 50.00);
ROLLBACK;
SELECT pg_current_wal_insert_lsn() > :'snap' AS rollback_advances_lsn;
