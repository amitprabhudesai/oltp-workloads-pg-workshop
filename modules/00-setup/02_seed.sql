-- =============================================================================
-- Seed Data
--
-- Creates 100 accounts with random starting balances, then generates 5,000
-- historical transfers between them. Run once at setup; use reset_db.sh to
-- return to this baseline between exercises if needed.
-- =============================================================================

BEGIN;

-- 100 accounts, balances between 1,000 and 50,000
INSERT INTO accounts (owner, balance)
SELECT
    'user_' || n,
    round((random() * 49000 + 1000)::numeric, 2)
FROM generate_series(1, 100) AS n;

-- 5,000 completed historical transfers
WITH acc AS (SELECT id FROM accounts)
INSERT INTO transfers (from_account, to_account, amount, status, created_at)
SELECT
    a1.id,
    a2.id,
    round((random() * 500 + 1)::numeric, 2),
    'completed',
    now() - (random() * interval '30 days')
FROM
    (SELECT id FROM accounts ORDER BY random()) a1,
    (SELECT id FROM accounts ORDER BY random()) a2,
    generate_series(1, 50)   -- 100 * 50 = 5,000 rows (with duplicates filtered below)
WHERE a1.id <> a2.id
LIMIT 5000;

COMMIT;

-- Sanity check
SELECT
    (SELECT count(*) FROM accounts)  AS accounts,
    (SELECT count(*) FROM transfers) AS transfers;
