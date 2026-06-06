# Module 2: MVCC and Concurrency

**Estimated time:** 40–50 minutes  
**Sessions needed:** 2 psql sessions (open two terminal tabs in VS Code)

## What you will learn

- How MVCC provides snapshot isolation without blocking readers
- The difference between READ COMMITTED and REPEATABLE READ
- How the lost update problem arises, and two ways to prevent it
- How to observe row-level locks in `pg_locks` and diagnose blocking in `pg_stat_activity`

## Setup

Open **two terminal tabs** in VS Code.

**Tab 1 — Session A:**
```bash
psql -U participant
```

**Tab 2 — Session B:**
```bash
psql -U participant
```

Reset to a clean baseline before starting:
```bash
bash /workspace/scripts/reset_db.sh
```

## Exercise sequence

Work through the sessions in lockstep, following the step labels (A-1, B-1, A-2, …).
Each session file tells you when to pause and hand control to the other session.

| Step | Session | What happens |
|------|---------|-------------|
| A-1 | A | BEGIN, insert a transfer — **don't commit** |
| B-1 | B | SELECT — row is invisible (uncommitted) |
| B-2 | B | Inspect `pg_stat_activity` — see A's open transaction |
| A-2 | A | COMMIT |
| B-3 | B | SELECT again — row is now visible |
| A-3 | A | BEGIN REPEATABLE READ, count accounts |
| B-4 | B | Insert a new account and commit |
| A-4 | A | Count accounts again — same result (snapshot held) |
| A-5–6 | A | Repeat in READ COMMITTED — now sees B's new account |
| A-7 | A | BEGIN, read account 1 balance |
| B-6–7 | B | Read same balance, debit 300, commit first |
| A-8–9 | A | Apply relative debit — both debits are preserved ✓ |
| A-10 | A | Demo dangerous pattern: write stale computed value |
| B-8 | B | Concurrent write — one debit is lost ✗ |
| A-11 | A | BEGIN, `SELECT FOR UPDATE` account 1 — acquires row lock |
| B-9 | B | Try `SELECT FOR UPDATE` on same row — **blocks** |
| | A | Inspect `pg_locks` and `pg_stat_activity` while B waits |
| A-12 | A | Complete transfer, COMMIT — B unblocks |
| B-9 cont. | B | Sees post-commit balance, applies its own debit safely |

## Key views used

| View | What it shows |
|---|---|
| `pg_stat_activity` | Active sessions, transaction state, what they're waiting on |
| `pg_locks` | All lock requests — both granted and waiting |
| `pg_blocking_pids(pid)` | Which PIDs are blocking a given session |

## MVCC internals: xmin / xmax (reference)

Every heap tuple has two hidden system columns:

- **xmin** — the transaction ID (XID) that inserted this version
- **xmax** — the XID that deleted or updated this version (0 if current)

A tuple is visible to your transaction if:
1. `xmin` committed before your snapshot was taken, AND
2. `xmax` is either 0, or committed *after* your snapshot was taken

This is how PostgreSQL serves consistent reads with no read locks.

```sql
-- See xmin/xmax for account rows (requires superuser or table owner)
SELECT xmin, xmax, id, owner, balance FROM accounts LIMIT 5;
```

## Preventing lost updates: two approaches

| Approach | How | When to use |
|---|---|---|
| Relative UPDATE | `SET balance = balance - 500` (let the DB compute it) | Simple arithmetic on a single row |
| `SELECT FOR UPDATE` | Lock the row before reading; compute in the application | Complex multi-step logic, cross-table decisions |
| `SERIALIZABLE` isolation | PostgreSQL detects and aborts conflicting transactions | Complex invariants spanning multiple rows/tables |

## Discussion prompts

1. MVCC keeps old row versions until `VACUUM` reclaims them. What happens to
   a table with a very long-running transaction open against it?

2. `pg_locks` shows a waiting lock but `pg_stat_activity` shows the blocker
   in `idle in transaction` state. What does that mean operationally?

3. When would you choose `SELECT FOR UPDATE` over `SERIALIZABLE` isolation?
   What are the trade-offs?
