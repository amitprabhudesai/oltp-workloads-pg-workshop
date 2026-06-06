# Module 99: Permission Verification

Run this as `participant` to confirm the role setup is working correctly
before starting the workshop exercises.

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
