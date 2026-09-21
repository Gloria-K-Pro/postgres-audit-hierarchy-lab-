-- security/roles_and_permissions.sql
-- Least-privilege roles for the bootcamp database. Run as a superuser AFTER migrations.
-- app_read / app_write are group roles (NOLOGIN): people and services get them via membership.

CREATE ROLE app_read;
CREATE ROLE app_write;

-- 1. Lock the front door: nobody connects unless granted.
REVOKE ALL    ON DATABASE bootcamp FROM PUBLIC;
REVOKE CREATE ON SCHEMA public     FROM PUBLIC;

-- 2. Database connection
GRANT CONNECT ON DATABASE bootcamp TO app_read, app_write;

-- 3. Schema usage (lets roles see objects; does NOT allow creating tables)
GRANT USAGE ON SCHEMA public TO app_read, app_write;

-- 4. Read-only access
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_read;

-- 5. Read-write access (data only, no DDL)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO app_write;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA public TO app_write;

-- 6. Protect the audit trail: the application can read it but never rewrite history.
--    Rows still get written because audit() is SECURITY DEFINER.
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON audit_log FROM app_write;

-- 7. Flyway's bookkeeping table is for the migration user only.
--    (Only exists once Flyway has run; skipped otherwise.)
DO $$
BEGIN
    IF to_regclass('public.flyway_schema_history') IS NOT NULL THEN
        REVOKE ALL ON flyway_schema_history FROM app_read, app_write;
    END IF;
END $$;

-- 8. Tables created by future migrations get the same grants automatically.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_read;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_write;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO app_write;
