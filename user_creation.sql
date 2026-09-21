-- security/user_creation.sql
-- Application login used by the API. Inherits only what app_write allows.
-- NOTE: 'strong-secret' is the lab placeholder. In real deployments, inject the
-- password from a secrets manager / environment variable and never commit it.

CREATE USER api
LOGIN PASSWORD 'strong-secret'
IN ROLE app_write;

-- Optional read-only login for reporting / BI tools:
-- CREATE USER reporter LOGIN PASSWORD 'another-strong-secret' IN ROLE app_read;
