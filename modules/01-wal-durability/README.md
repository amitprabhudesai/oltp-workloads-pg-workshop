# Module 1: WAL and Durability

**Estimated time:** 20–25 minutes  
**Sessions needed:** 1 psql session

## What you will learn

- How to measure WAL generation for a given workload (`pg_current_wal_lsn`, `pg_wal_lsn_diff`)
- What `synchronous_commit` actually controls, and how it differs from `fsync`
- How checkpoints fit into the write path and what `pg_stat_bgwriter` tells you

## Setup

Open a terminal in VS Code and connect:

```bash
psql -U participant
```

Then work through `exercises.sql` top to bottom.

## Key views used

| View / Function | What it shows |
|---|---|
| `pg_current_wal_lsn()` | Current write position in the WAL stream |
| `pg_wal_lsn_diff(a, b)` | Byte distance between two LSNs |
| `pg_stat_wal` | Cumulative WAL write/sync stats since last reset |
| `pg_stat_bgwriter` | Checkpoint and bgwriter activity |
| `pg_control_checkpoint()` | LSN of the most recent completed checkpoint |

## The write path (reference)

```
Client COMMIT
    │
    ▼
WAL buffer (shared memory)
    │
    │  WAL writer flushes every wal_writer_delay (200ms default)
    │  or immediately on COMMIT when synchronous_commit = on
    ▼
WAL files on disk  ◄──── durability boundary
    │
    │  Checkpointer flushes dirty shared_buffers pages
    ▼
Heap / index files on disk
```

A crash after the WAL write but before the heap write is fine — PostgreSQL
replays the WAL records during recovery to reconstruct the heap.

## Discussion prompts

1. Your WAL is ~4 MB for 10,000 single-row inserts. How does that change for
   UPDATE-heavy workloads? What about workloads with large TEXT/JSONB columns?

2. When would you set `synchronous_commit = off` in production? What monitoring
   would you want in place if you did?

3. `buffers_backend` in `pg_stat_bgwriter` is non-zero. What does that indicate,
   and what knobs would you reach for to fix it?
