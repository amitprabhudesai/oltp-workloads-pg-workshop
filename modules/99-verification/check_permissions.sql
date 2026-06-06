-- =============================================================================
-- Permission verification
-- Run this as 'participant' to confirm the role setup is correct.
--
--   psql -U participant
--   \i /workspace/modules/99-verification/check_permissions.sql
-- =============================================================================

SET search_path TO rootconf, public;

\echo '================================================================'
\echo 'Who am I?'
\echo '================================================================'

SELECT
    current_user                                            AS login_user,
    pg_has_role(current_user, 'rcf_contributor', 'MEMBER') AS is_contributor,
    pg_has_role(current_user, 'rcf_owner',       'MEMBER') AS is_owner,
    pg_has_role(current_user, 'pg_read_all_stats','MEMBER') AS has_read_all_stats,
    pg_has_role(current_user, 'pg_checkpoint',    'MEMBER') AS has_checkpoint;

-- Expected:
--   login_user  | is_contributor | is_owner | has_read_all_stats | has_checkpoint
--   participant | t              | f        | t                  | t


\echo ''
\echo '================================================================'
\echo 'pg_stat_activity: can I see ALL sessions, not just my own?'
\echo '================================================================'

-- Without pg_read_all_stats, a non-superuser only sees their own row.
-- 'workshop' (superuser) should always have at least one background worker visible.
SELECT pid, usename, application_name, state, wait_event_type, wait_event
FROM pg_stat_activity
ORDER BY usename, pid;

-- PASS: rows from users other than 'participant' are visible
-- FAIL: only own row visible (means pg_read_all_stats is not in effect)


\echo ''
\echo '================================================================'
\echo 'pg_stat_wal'
\echo '================================================================'

SELECT
    wal_records,
    wal_fpi,
    pg_size_pretty(wal_bytes::bigint) AS wal_bytes,
    wal_write,
    wal_sync
FROM pg_stat_wal;


\echo ''
\echo '================================================================'
\echo 'pg_stat_bgwriter'
\echo '================================================================'

SELECT
    checkpoints_timed,
    checkpoints_req,
    pg_size_pretty((buffers_checkpoint * 8192)::bigint) AS checkpoint_written,
    pg_size_pretty((buffers_clean     * 8192)::bigint) AS bgwriter_written,
    pg_size_pretty((buffers_backend   * 8192)::bigint) AS backend_written
FROM pg_stat_bgwriter;


\echo ''
\echo '================================================================'
\echo 'pg_stat_user_tables (rootconf schema)'
\echo '================================================================'

SELECT relname, n_live_tup, n_dead_tup, last_vacuum, last_autovacuum
FROM pg_stat_user_tables
WHERE schemaname = 'rootconf'
ORDER BY relname;


\echo ''
\echo '================================================================'
\echo 'CHECKPOINT (requires pg_checkpoint role)'
\echo '================================================================'

CHECKPOINT;
\echo 'PASS: CHECKPOINT succeeded'

SELECT * FROM rootconf.checkpoint_info();


\echo ''
\echo '================================================================'
\echo 'Privilege boundaries: what participant cannot do'
\echo '================================================================'

-- Each block expects a specific error. PASS = error was raised as expected.

DO $$
BEGIN
    EXECUTE 'CREATE TABLE rootconf.should_fail (id int)';
    RAISE EXCEPTION 'FAIL: CREATE TABLE succeeded — participant should not have CREATE privilege';
EXCEPTION
    WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: CREATE TABLE correctly denied (insufficient_privilege)';
END;
$$;

DO $$
BEGIN
    EXECUTE 'DROP TABLE rootconf.accounts';
    RAISE EXCEPTION 'FAIL: DROP TABLE succeeded — participant should not have DROP privilege';
EXCEPTION
    WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: DROP TABLE correctly denied (insufficient_privilege)';
END;
$$;

DO $$
DECLARE
    other_pid int;
BEGIN
    -- Pick any backend that is not our own
    SELECT pid INTO other_pid
    FROM pg_stat_activity
    WHERE pid <> pg_backend_pid()
    LIMIT 1;

    IF other_pid IS NULL THEN
        RAISE NOTICE 'SKIP: no other backends visible to test pg_cancel_backend';
        RETURN;
    END IF;

    PERFORM pg_cancel_backend(other_pid);
    RAISE EXCEPTION 'FAIL: pg_cancel_backend succeeded — participant should not have pg_signal_backend';
EXCEPTION
    WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASS: pg_cancel_backend correctly denied (insufficient_privilege)';
END;
$$;
