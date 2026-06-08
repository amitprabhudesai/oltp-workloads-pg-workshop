-- 02_synchronous_commit:
--   on  → WAL flush LSN advances before COMMIT returns
--   off → COMMIT returns immediately; data visible; no consistency risk
SET search_path TO rootconf, public;

DO $$ BEGIN
    DELETE FROM accounts WHERE owner LIKE '_regress_%';
END; $$;

-- 2.1  on: flush LSN must advance across bench_inserts
SET synchronous_commit = on;
SELECT pg_current_wal_flush_lsn() AS snap \gset
CALL bench_inserts(10);
SELECT pg_current_wal_flush_lsn() > :'snap' AS on_wal_flushed;

-- 2.2  off: committed row is immediately visible
SET synchronous_commit = off;
BEGIN;
INSERT INTO accounts (owner, balance) VALUES ('_regress_async', 500.00);
COMMIT;
SELECT balance = 500.00 AS async_commit_data_visible
FROM accounts WHERE owner = '_regress_async';

-- 2.3  off: all 50 commits land
SELECT count(*) AS snap FROM transfers \gset
CALL bench_inserts(50);
SELECT count(*) - :snap = 50 AS all_async_commits_durable FROM transfers;

SET synchronous_commit = on;

DO $$ BEGIN
    DELETE FROM accounts WHERE owner LIKE '_regress_%';
END; $$;
