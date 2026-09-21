# postgres-audit-hierarchy-lab

A PostgreSQL project demonstrating four database engineering practices: **trigger-based audit logging**, **hierarchical data with recursive CTEs**, **versioned migrations with Flyway**, and **least-privilege access control**.

Built and tested on PostgreSQL 16.

## Objectives

1. Track every INSERT, UPDATE and DELETE on application tables, with before/after snapshots, user and timestamp.
2. Model a category tree with a self-referencing table and traverse it with `WITH RECURSIVE`.
3. Manage all schema changes as ordered, checksummed Flyway migrations.
4. Give the application only the permissions it needs, and protect the audit trail from the application itself.

## Repository structure

```
postgres-audit-hierarchy-lab/
├── migrations/                  Flyway versioned migrations (source of truth for the schema)
│   ├── V1__core_tables.sql      students, courses, enrollments + seed data
│   ├── V2__audit_log.sql        audit_log table, audit() function, trg_audit trigger
│   └── V3__categories.sql       self-referencing categories + sample tree
├── audit/
│   ├── audit_trigger.sql        standalone, re-runnable audit setup
│   ├── audit_test.sql           UPDATE, DELETE, then query the audit trail
│   └── audit_results.md         captured output and analysis
├── hierarchy/
│   ├── categories_table.sql     standalone, re-runnable categories setup
│   ├── category_tree_query.sql  recursive CTE over the whole tree
│   └── hierarchy_results.md     captured output and explanation
├── security/
│   ├── roles_and_permissions.sql  app_read / app_write roles and grants
│   ├── user_creation.sql          api login user
│   └── security_notes.md          least-privilege explanation + permission tests
├── docs/
│   ├── migration_report.md      Flyway files, output, order, rationale
│   ├── audit_design.md
│   ├── hierarchy_design.md
│   └── reflection.md
├── .github/workflows/flyway.yml CI: runs Flyway + tests on a fresh Postgres every push
└── README.md
```

## Quick start

```bash
createdb -U postgres bootcamp

# 1. Schema (run from repo root)
flyway -url=jdbc:postgresql://localhost/bootcamp -user=postgres \
       -locations=filesystem:migrations migrate
flyway -url=jdbc:postgresql://localhost/bootcamp -user=postgres \
       -locations=filesystem:migrations info

# 2. Security (after migrations, as superuser)
psql -U postgres -d bootcamp -f security/roles_and_permissions.sql
psql -U postgres -d bootcamp -f security/user_creation.sql

# 3. Exercise it
psql -U postgres -d bootcamp -f audit/audit_test.sql
psql -U postgres -d bootcamp -f hierarchy/category_tree_query.sql
```

No Flyway installed? Use Docker:

```bash
docker run --rm --network host -v "$PWD/migrations:/flyway/sql" flyway/flyway:10 \
  -url=jdbc:postgresql://localhost:5432/bootcamp -user=postgres -password=<pw> migrate
```

## Migration workflow

1. Never change the schema by hand. Write a new file `migrations/V<n>__<description>.sql`.
2. Run `flyway migrate`. Flyway applies pending versions in order and records each in `flyway_schema_history` with a checksum.
3. Run `flyway info` to confirm every version shows **Success**.
4. Never edit an applied migration. Fix forward with a new version.
5. CI (`.github/workflows/flyway.yml`) rebuilds the database from zero on every push, so a broken migration fails the build.

Details and output: [`docs/migration_report.md`](docs/migration_report.md).

## Audit logging workflow

1. `trg_audit` fires `AFTER INSERT OR UPDATE OR DELETE ... FOR EACH ROW` on `students`.
2. `audit()` writes one row to `audit_log`: table, operation, `old_row` and `new_row` as JSONB, `session_user`, `clock_timestamp()`.
3. Query the trail:
   ```sql
   SELECT tbl, op, old_row->>'name' AS was, new_row->>'name' AS now, at
   FROM audit_log ORDER BY at DESC;
   ```
4. Audit another table with one line: `CREATE TRIGGER trg_audit AFTER INSERT OR UPDATE OR DELETE ON <table> FOR EACH ROW EXECUTE FUNCTION audit();`

Result from the test run:

| tbl | op | was | now |
|-----|----|-----|-----|
| students | DELETE | Brian Otieno | |
| students | UPDATE | Kofi Mensah | Kofi M. |

Details: [`audit/audit_results.md`](audit/audit_results.md), [`docs/audit_design.md`](docs/audit_design.md).

## Category hierarchy

```
Electronics
├── Computers
│    └── Laptops
└── Phones
```

Stored as an adjacency list (`parent_id` references `categories.id`) and traversed with `WITH RECURSIVE`. Details: [`hierarchy/hierarchy_results.md`](hierarchy/hierarchy_results.md), [`docs/hierarchy_design.md`](docs/hierarchy_design.md).

## Security implementation summary

| Role | Login | Can do |
|------|-------|--------|
| `app_read` | No (group) | CONNECT, USAGE on `public`, SELECT on all tables |
| `app_write` | No (group) | Above + INSERT/UPDATE/DELETE + sequence use. Read-only on `audit_log`. No DDL |
| `api` | Yes | Member of `app_write`. The only credentials the application uses |
| `postgres` | Yes | Superuser. Migrations and admin only, never the app |

Key points:

- `PUBLIC` loses CONNECT on the database and CREATE on the schema.
- The app cannot alter or delete audit history. The trigger still writes it because `audit()` is `SECURITY DEFINER` with a pinned `search_path`.
- `ALTER DEFAULT PRIVILEGES` gives future tables the same grants.
- Verified by logging in as `api`: reads and writes succeed, `DELETE FROM audit_log`, `DROP TABLE` and `CREATE TABLE` are denied.

Details: [`security/security_notes.md`](security/security_notes.md).

> `strong-secret` is the lab's placeholder password. Use a secrets manager in any real deployment.
