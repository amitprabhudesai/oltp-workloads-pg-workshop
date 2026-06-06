# OLTP Workloads — PostgreSQL Workshop

Hands-on playground for the **Write Path in OLTP Workloads (PostgreSQL)** workshop.

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (or Docker Engine + Compose)
- [VS Code](https://code.visualstudio.com/) with the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)

## Getting started

1. Clone the repository:
   ```bash
   git clone https://github.com/amitprabhudesai/oltp-workloads-pg-workshop.git
   cd oltp-workloads-pg-workshop/workshop-playground
   ```

2. Open in VS Code, then **Reopen in Container** when prompted.  
   First launch takes ~2 minutes to pull images and install the PostgreSQL client.

3. Once the devcontainer is running, a `post-create` script automatically loads
   the schema and seed data. You'll see:
   ```
   Workshop database is ready.
   Connect with: psql -h postgres -U workshop -d workshop
   ```

4. Open a terminal in VS Code and connect:
   ```bash
   psql
   # (PGHOST, PGUSER, PGDATABASE, PGPASSWORD are set in the container environment)
   ```

## Repository layout

```
workshop-playground/
├── .devcontainer/
│   ├── devcontainer.json   # VS Code devcontainer config
│   ├── docker-compose.yml  # workspace + postgres:16 services
│   ├── Dockerfile          # workspace image (Ubuntu + psql 16 client)
│   └── post-create.sh      # loads schema + seed data on first launch
│
├── modules/
│   ├── 00-setup/
│   │   ├── 01_schema.sql   # accounts, transfers, audit_log tables
│   │   └── 02_seed.sql     # 100 accounts, 5,000 historical transfers
│   │
│   ├── 01-wal-durability/
│   │   ├── README.md       # exercise guide and discussion prompts
│   │   └── exercises.sql   # single-session exercises
│   │
│   └── 02-mvcc-concurrency/
│       ├── README.md       # exercise guide, step sequence, discussion prompts
│       ├── session_a.sql   # Session A (driver)
│       └── session_b.sql   # Session B (concurrent writer / observer)
│
└── scripts/
    └── reset_db.sh         # drop and reload schema + seed data
```

## PostgreSQL configuration

The workshop container runs PostgreSQL 16 with these non-default settings
(all set via command-line flags in `docker-compose.yml`):

| Setting | Value | Why |
|---|---|---|
| `wal_level` | `logical` | Allows WAL inspection |
| `checkpoint_timeout` | `60s` | Short enough to see checkpoint effects during exercises |
| `checkpoint_completion_target` | `0.5` | Spreads checkpoint I/O over 50% of the interval |
| `log_checkpoints` | `on` | Checkpoints appear in container logs |
| `log_lock_waits` | `on` | Lock waits > deadlock_timeout appear in logs |
| `log_autovacuum_min_duration` | `0` | All autovacuum runs logged |
| `track_io_timing` | `on` | Enables I/O timing in `pg_stat_*` views |

All other settings are PostgreSQL defaults. `synchronous_commit` starts as `on`
and is toggled during Module 1 exercises.

## Resetting between exercises

If you want to return to a clean baseline (100 accounts, 5,000 transfers, nothing else):

```bash
bash /workspace/scripts/reset_db.sh
```

## Workshop modules

| Module | Topic | Time |
|---|---|---|
| [01-wal-durability](modules/01-wal-durability/README.md) | WAL generation, `synchronous_commit`, checkpoints | 20–25 min |
| [02-mvcc-concurrency](modules/02-mvcc-concurrency/README.md) | Snapshot isolation, lost updates, row locks | 40–50 min |
