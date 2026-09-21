# Security Notes: Least Privilege

## What least privilege means

Every user, service and role gets the minimum access needed to do its job, and nothing more. If an account only needs to read, it cannot write. If it only needs to change data, it cannot change the schema. The goal is to shrink the blast radius: when something goes wrong (a bug, a leaked password, a SQL injection), the damage is limited to what that account was allowed to do.

## Why applications should not use superuser accounts

A PostgreSQL superuser bypasses every permission check. If the API connects as `postgres`:

- **SQL injection becomes total compromise.** One injectable query can `DROP` tables, read every schema, create new logins, or run `COPY ... TO PROGRAM` to execute shell commands on the database server.
- **The audit trail stops meaning anything.** A superuser can `DELETE FROM audit_log` or disable triggers. Logs the attacker can edit are not evidence.
- **Bugs get worse.** A migration-style statement accidentally shipped in app code runs without resistance.
- **No separation of duties.** You can no longer tell app activity from admin activity, and you cannot revoke the app's access without locking out the DBA.

Superuser is for administrators and migrations run by a human or CI. The app gets a login that can only touch data.

## Role design

| Role | Type | Purpose |
|------|------|---------|
| `app_read` | Group role (NOLOGIN) | Read-only consumers: reporting, dashboards, analysts |
| `app_write` | Group role (NOLOGIN) | The application: reads and changes data, never structure |
| `api` | Login user, member of `app_write` | The credentials the API service actually uses |
| `postgres` | Superuser | Migrations (Flyway) and administration only |

Permissions are granted to group roles, never to individual logins. Adding a new service means `CREATE USER ... IN ROLE app_read`, with no new GRANT statements.

## Differences between app_read and app_write

| Capability | app_read | app_write |
|------------|:--------:|:---------:|
| CONNECT to `bootcamp` | Yes | Yes |
| USAGE on schema `public` | Yes | Yes |
| SELECT on tables | Yes | Yes |
| INSERT / UPDATE / DELETE on tables | No | Yes |
| Use sequences (needed for INSERT with identity ids) | No | Yes |
| Write to `audit_log` directly | No | **No** (read only) |
| CREATE / ALTER / DROP tables | No | No |
| See `flyway_schema_history` | No | No |

`app_write` can change data but not structure. Schema changes only happen through Flyway migrations run as the owner.

## Hardening beyond the base lab

1. `REVOKE ALL ON DATABASE bootcamp FROM PUBLIC` so a random login cannot even connect.
2. `REVOKE CREATE ON SCHEMA public FROM PUBLIC` so nobody can create objects in the schema (default since PG15, stated explicitly).
3. `audit_log` is read-only for the app. Rows are still written because `audit()` is `SECURITY DEFINER` (runs as its owner) with a pinned `search_path`. The function records `session_user`, so the log shows `api`, not the function owner.
4. `ALTER DEFAULT PRIVILEGES` so tables added by future migrations inherit the right grants automatically.
5. The lab password `strong-secret` is a placeholder. In production it comes from a secrets manager or environment variable, is rotated, and is never committed to Git.

## Role definitions (`\du`, `\dp`)

```text
                             List of roles
 Role name |                         Attributes                         
-----------+------------------------------------------------------------
 api       | 
 app_read  | Cannot login
 app_write | Cannot login
 postgres  | Superuser, Create role, Create DB, Replication, Bypass RLS

                                  Access privileges
 Schema |   Name   | Type  |     Access privileges     | Column privileges | Policies 
--------+----------+-------+---------------------------+-------------------+----------
 public | students | table | postgres=arwdDxt/postgres+|                   | 
        |          |       | app_read=r/postgres      +|                   | 
        |          |       | app_write=arwd/postgres   |                   | 
(1 row)

                                   Access privileges
 Schema |   Name    | Type  |     Access privileges     | Column privileges | Policies 
--------+-----------+-------+---------------------------+-------------------+----------
 public | audit_log | table | postgres=arwdDxt/postgres+|                   | 
        |           |       | app_read=r/postgres      +|                   | 
        |           |       | app_write=r/postgres      |                   | 
(1 row)
```

Reading the ACLs: `r`=SELECT, `a`=INSERT, `w`=UPDATE, `d`=DELETE, `D`=TRUNCATE, `x`=REFERENCES, `t`=TRIGGER. On `audit_log`, `app_write` has only `r`.

## Verification: logged in as `api` (app_write)

```text
--- as api (app_write) ---
 current_user | session_user 
--------------+--------------
 api          | api
(1 row)

 students_visible 
------------------
                3
(1 row)

INSERT 0 1
UPDATE 1
   op   |     name     | changed_by 
--------+--------------+------------
 UPDATE | Amina Yusuf  | api
 INSERT | Zawadi Njeri | api
(2 rows)

line 7: ERROR:  permission denied for table audit_log
line 8: ERROR:  permission denied for table audit_log
line 9: ERROR:  must be owner of table students
line 10: ERROR:  permission denied for schema public
LINE 1: CREATE TABLE hack (id int);
                     ^
```

Allowed: read, insert, update, and the audit trigger still logs `changed_by = api`. Blocked: rewriting the audit log, dropping tables, creating tables.

## Verification: logged in as a read-only user (app_read)

A temporary `reporter` login in `app_read` was created for this test, then dropped.

```text
--- as reporter (app_read) ---
 students_visible 
------------------
                4
(1 row)

line 3: ERROR:  permission denied for table students
line 4: ERROR:  permission denied for table students
```

(4 students visible here because the `api` test above inserted Zawadi Njeri.)
