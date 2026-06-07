-- =============================================================================
-- Module 90-microbench: Workshop benchmark utilities
--
-- Procedures used by the hands-on exercises to demonstrate PostgreSQL
-- write-path behaviour. Kept separate from the application schema (00-setup)
-- so they can be loaded/reset independently.
--
-- Run as: psql -h postgres -U workshop -d workshop -f <this file>
-- =============================================================================

SET search_path TO rootconf, public;

-- ---------------------------------------------------------------------------
-- bench_inserts(n int)
--
-- Inserts n transfer rows, each in its own transaction, to measure the
-- per-commit cost of synchronous_commit settings.
--
-- Must be a PROCEDURE (not a DO block): only procedures allow COMMIT inside
-- their body. A DO block is a single transaction and fsyncs exactly once
-- regardless of synchronous_commit, making the benchmark meaningless.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE rootconf.bench_inserts(n int)
LANGUAGE plpgsql AS $$
DECLARE
    i   int;
    src bigint;
    dst bigint;
BEGIN
    FOR i IN 1..n LOOP
        LOOP
            src := (random() * 99 + 1)::bigint;
            dst := (random() * 99 + 1)::bigint;
            EXIT WHEN src <> dst;
        END LOOP;
        INSERT INTO transfers (from_account, to_account, amount, status)
        VALUES (src, dst, round((random() * 500 + 1)::numeric, 2), 'completed');
        COMMIT;
    END LOOP;
END;
$$;
