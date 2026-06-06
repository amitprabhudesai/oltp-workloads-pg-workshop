# Module 99: Permission Verification

This module is intended to be run by a rootconf volunteer/verifier before
the workshop to confirm the environment is set up correctly.

## Before you start: reset to a clean baseline

The seed data may have accumulated extra rows if the setup scripts were run
more than once. Always reset before verifying:

```bash
bash /workspace/scripts/reset_db.sh
```

Expected output after reset:
```
 accounts | transfers
----------+-----------
      100 |      5000
```

## Run the permission checks

Connect as `participant` (the role workshop attendees will use):

```bash
psql -U participant
```

Then inside psql:

```sql
\i /workspace/modules/99-verification/check_permissions.sql
```

## What it checks

| Check | Expected |
|---|---|
| Role memberships | `rcf_contributor=t`, `pg_read_all_stats=t`, `pg_checkpoint=t` |
| `pg_stat_activity` | All sessions visible (not just own row) |
| `pg_stat_wal` | Readable |
| `pg_stat_bgwriter` | Readable |
| `pg_stat_user_tables` | Readable for rootconf schema |
| `CHECKPOINT` | Succeeds |
| `rootconf.checkpoint_info()` | Returns one row |
| `CREATE TABLE` in rootconf | Denied (`insufficient_privilege`) |
| `DROP TABLE` on rootconf | Denied (`insufficient_privilege`) |
| `pg_cancel_backend` on another session | Denied (`insufficient_privilege`) |
