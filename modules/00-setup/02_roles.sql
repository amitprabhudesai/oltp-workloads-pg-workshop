-- =============================================================================
-- Role hierarchy for the rootconf workshop database
--
-- Design principles
-- -----------------
-- 1. Group roles (NOLOGIN) express capabilities; login users are members.
--    This separates "what you can do" from "who you are", making future
--    privilege changes a single GRANT/REVOKE on the group role.
--
-- 2. The rootconf schema is owned by rcf_owner. Other roles receive only
--    the minimum privileges needed: USAGE on the schema + DML on objects.
--    No role below rcf_owner can CREATE, ALTER, or DROP schema objects.
--
-- 3. Two predefined system roles are granted for workshop observability:
--    - pg_monitor    : read-only access to all pg_stat_* views and
--                      pg_control_checkpoint(). Needed so participants
--                      can observe WAL and lock state across sessions.
--    - pg_checkpoint : permits the CHECKPOINT command (PG14+). Granted
--                      so exercises can demonstrate the checkpoint cycle
--                      without superuser access.
--    In production, pg_checkpoint would typically be a DBA-only privilege.
--    Document this explicitly if you carry this setup beyond a workshop.
--
-- 4. Default privileges ensure objects created by rcf_owner in the future
--    are automatically accessible to lower roles without manual re-grants.
--
-- Security notes (see bottom of file for full discussion)
-- -------------------------------------------------------
-- * Passwords here are workshop defaults — change before any exposure
--   beyond a local devcontainer.
-- * pg_hba.conf in the Docker container trusts all connections from the
--   Docker bridge network. Restrict this in any non-local deployment.
-- * rcf_owner is NOT a superuser — it owns objects in rootconf only.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Group roles (no login — capability levels only)
-- ---------------------------------------------------------------------------

-- Schema owner: may CREATE/ALTER/DROP objects within rootconf.
-- Does NOT have CREATEROLE, CREATEDB, or SUPERUSER.
CREATE ROLE IF NOT EXISTS rcf_owner      NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;

-- Contributor: read/write data, execute functions. No DDL.
-- Intended for application users and workshop participants who write data.
CREATE ROLE IF NOT EXISTS rcf_contributor NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;

-- Reviewer: identical privileges to rcf_contributor for now.
-- Will become read-only (SELECT + EXECUTE only) once the role model matures.
CREATE ROLE IF NOT EXISTS rcf_reviewer   NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;

-- ---------------------------------------------------------------------------
-- Login roles
-- ---------------------------------------------------------------------------

-- amit: personal owner account. Member of rcf_owner — inherits all DDL rights.
-- Change the password immediately in any non-local environment.
CREATE ROLE IF NOT EXISTS amit LOGIN PASSWORD 'rcfowner'
    NOSUPERUSER NOCREATEDB NOCREATEROLE
    CONNECTION LIMIT 10;

-- participant: default devcontainer identity for workshop attendees.
-- Inherits rcf_contributor privileges.
CREATE ROLE IF NOT EXISTS participant LOGIN PASSWORD 'participant'
    NOSUPERUSER NOCREATEDB NOCREATEROLE
    CONNECTION LIMIT 5;

-- ---------------------------------------------------------------------------
-- Role memberships
-- ---------------------------------------------------------------------------

GRANT rcf_owner      TO amit;
GRANT rcf_contributor TO participant;

-- rcf_reviewer gets the same privilege set as rcf_contributor for now.
-- When reviewer becomes read-only, remove this grant and add SELECT-only grants.
GRANT rcf_contributor TO rcf_reviewer;

-- ---------------------------------------------------------------------------
-- Schema ownership
-- ---------------------------------------------------------------------------

ALTER SCHEMA rootconf OWNER TO rcf_owner;

ALTER TABLE rootconf.accounts  OWNER TO rcf_owner;
ALTER TABLE rootconf.transfers OWNER TO rcf_owner;
ALTER TABLE rootconf.audit_log OWNER TO rcf_owner;

-- Sequences backing BIGSERIAL columns
ALTER SEQUENCE rootconf.accounts_id_seq  OWNER TO rcf_owner;
ALTER SEQUENCE rootconf.transfers_id_seq OWNER TO rcf_owner;
ALTER SEQUENCE rootconf.audit_log_id_seq OWNER TO rcf_owner;

-- ---------------------------------------------------------------------------
-- Privileges for rcf_contributor (inherited by participant and rcf_reviewer)
-- ---------------------------------------------------------------------------

-- Namespace visibility
GRANT USAGE ON SCHEMA rootconf TO rcf_contributor;

-- Data access
GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA rootconf
    TO rcf_contributor;

-- nextval() / currval() for BIGSERIAL inserts
GRANT USAGE ON ALL SEQUENCES IN SCHEMA rootconf TO rcf_contributor;

-- Any functions defined in the schema
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA rootconf TO rcf_contributor;

-- ---------------------------------------------------------------------------
-- Default privileges
-- When rcf_owner creates new objects later, lower roles get access automatically.
-- ---------------------------------------------------------------------------

ALTER DEFAULT PRIVILEGES FOR ROLE rcf_owner IN SCHEMA rootconf
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rcf_contributor;

ALTER DEFAULT PRIVILEGES FOR ROLE rcf_owner IN SCHEMA rootconf
    GRANT USAGE ON SEQUENCES TO rcf_contributor;

ALTER DEFAULT PRIVILEGES FOR ROLE rcf_owner IN SCHEMA rootconf
    GRANT EXECUTE ON FUNCTIONS TO rcf_contributor;

-- ---------------------------------------------------------------------------
-- System roles for workshop observability
-- ---------------------------------------------------------------------------

-- pg_read_all_stats: read access to pg_stat_activity (all sessions),
-- pg_stat_bgwriter, pg_stat_wal, pg_stat_replication, and related views.
-- Without this, a non-superuser sees only their own row in pg_stat_activity.
--
-- Deliberately chosen over the broader pg_monitor role:
--   pg_monitor = pg_read_all_stats + pg_read_all_settings + pg_signal_backend
--   pg_read_all_settings can expose GUC values that may contain connection
--   strings or credentials in some configurations.
--   pg_signal_backend lets a role cancel or terminate any backend — too
--   powerful for workshop participants.
-- pg_read_all_stats gives the observability we need without the extra surface.
--
-- Note: pg_control_checkpoint() requires pg_monitor or superuser. We wrap it
-- in a SECURITY DEFINER function below so participants can call it safely.
GRANT pg_read_all_stats TO rcf_contributor;

-- pg_checkpoint: allows CHECKPOINT without superuser.
-- Intentional for the WAL module exercises. Document if taken to production.
GRANT pg_checkpoint TO rcf_contributor;

-- SECURITY DEFINER wrapper for pg_control_checkpoint().
-- Allows rcf_contributor to read checkpoint state without pg_monitor.
CREATE OR REPLACE FUNCTION rootconf.checkpoint_info()
RETURNS TABLE (
    redo_lsn            pg_lsn,
    checkpoint_lsn      pg_lsn,
    wal_since_checkpoint text
)
LANGUAGE sql
SECURITY DEFINER   -- executes as the function owner (rcf_owner / superuser)
SET search_path = rootconf, public
AS $$
    SELECT
        redo_lsn,
        checkpoint_lsn,
        pg_size_pretty(
            pg_wal_lsn_diff(pg_current_wal_lsn(), checkpoint_lsn)::bigint
        )
    FROM pg_control_checkpoint();
$$;

-- ---------------------------------------------------------------------------
-- Revoke public schema defaults (defense in depth)
-- ---------------------------------------------------------------------------

-- Prevent any role from creating objects in public by default.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- Security notes
-- ---------------------------------------------------------------------------
--
-- Passwords
--   amit       → 'rcfowner'   (CHANGE before any non-local use)
--   participant → 'participant' (acceptable for a sandboxed workshop)
--   workshop    → 'workshop'   (superuser, set in docker-compose)
--
-- Authentication (pg_hba.conf)
--   The Docker postgres image defaults to scram-sha-256 for password auth
--   on non-local connections. The Docker bridge network is trusted implicitly
--   by the container's pg_hba.conf. In production, restrict the allowed
--   CIDR to only the known application subnet.
--
-- pg_read_all_stats and pg_checkpoint
--   pg_read_all_stats exposes query text and wait events for ALL sessions.
--   This is intentional — exercises require observing other sessions' locks
--   and WAL activity. In production, restrict to dedicated monitoring accounts.
--   pg_monitor was deliberately NOT used: it additionally grants
--   pg_read_all_settings (may expose credential-bearing GUCs) and
--   pg_signal_backend (can cancel/terminate any backend).
--   pg_checkpoint allows triggering a checkpoint on demand (real I/O cost).
--   Limit to DBAs in production.
--   pg_control_checkpoint() is exposed via a SECURITY DEFINER function
--   (rootconf.checkpoint_info()) rather than granting pg_monitor directly.
--
-- rcf_owner scope
--   rcf_owner is not a superuser. It owns objects within rootconf only.
--   It cannot create roles, create databases, or access other schemas
--   unless explicitly granted. This is intentional.
--
-- Connection limits
--   amit: 10, participant: 5. Tune for the number of workshop attendees
--   and available server resources.
