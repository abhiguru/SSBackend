#!/bin/bash
set -e

# Create roles needed by Supabase services
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Create anon role (for anonymous/public access)
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
            CREATE ROLE anon NOLOGIN NOINHERIT;
        END IF;
    END
    \$\$;

    -- Create authenticated role (for logged-in users)
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
            CREATE ROLE authenticated NOLOGIN NOINHERIT;
        END IF;
    END
    \$\$;

    -- Create service_role (for backend service access)
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
            CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
        END IF;
    END
    \$\$;

    -- Create supabase_admin role
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_admin') THEN
            CREATE ROLE supabase_admin LOGIN SUPERUSER CREATEDB CREATEROLE REPLICATION BYPASSRLS;
        END IF;
    END
    \$\$;

    -- Create authenticator role (used by PostgREST to connect)
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
            CREATE ROLE authenticator NOINHERIT LOGIN;
        END IF;
    END
    \$\$;

    -- Create supabase_storage_admin role for storage service
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
            CREATE ROLE supabase_storage_admin NOINHERIT LOGIN;
        END IF;
    END
    \$\$;

    -- Set passwords
    ALTER ROLE authenticator WITH PASSWORD '$POSTGRES_PASSWORD';
    ALTER ROLE supabase_admin WITH PASSWORD '$POSTGRES_PASSWORD';
    ALTER ROLE supabase_storage_admin WITH PASSWORD '$POSTGRES_PASSWORD';

    -- Grant role memberships
    GRANT anon TO authenticator;
    GRANT authenticated TO authenticator;
    GRANT service_role TO authenticator;
    GRANT supabase_admin TO authenticator;

    -- Grant anon and authenticated to supabase_admin
    GRANT anon TO supabase_admin;
    GRANT authenticated TO supabase_admin;

    -- Grant storage admin permissions
    GRANT ALL ON SCHEMA public TO supabase_storage_admin;

    -- Create storage schema if not exists
    CREATE SCHEMA IF NOT EXISTS storage;
    GRANT ALL ON SCHEMA storage TO supabase_storage_admin;
EOSQL

echo "Roles created successfully"
