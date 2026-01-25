-- =============================================
-- Supabase System Roles & Schemas
-- Must run BEFORE application schema
-- =============================================

-- =============================================
-- ROLES (Supabase standard roles)
-- =============================================

-- anon role (for unauthenticated API requests)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN NOINHERIT;
    END IF;
END
$$;

-- authenticated role (for authenticated API requests)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN NOINHERIT;
    END IF;
END
$$;

-- service_role (for service-level access, bypasses RLS)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS;
    END IF;
END
$$;

-- supabase_admin (for admin operations)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_admin') THEN
        CREATE ROLE supabase_admin NOLOGIN NOINHERIT BYPASSRLS;
    END IF;
END
$$;

-- authenticator role (PostgREST connects as this, then switches to anon/authenticated)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
        CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD current_setting('app.settings.postgres_password', true);
    END IF;
END
$$;

-- Grant role switching to authenticator
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
GRANT service_role TO authenticator;

-- supabase_storage_admin (for Storage service)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'supabase_storage_admin') THEN
        CREATE ROLE supabase_storage_admin NOLOGIN NOINHERIT BYPASSRLS;
    END IF;
END
$$;

-- =============================================
-- SCHEMAS
-- =============================================

-- Storage schema
CREATE SCHEMA IF NOT EXISTS storage;
GRANT ALL ON SCHEMA storage TO supabase_storage_admin;
GRANT USAGE ON SCHEMA storage TO anon, authenticated, service_role;

-- Supavisor schema
CREATE SCHEMA IF NOT EXISTS _supavisor;
GRANT ALL ON SCHEMA _supavisor TO postgres;
GRANT ALL ON SCHEMA _supavisor TO supabase_admin;

-- Extensions schema (if needed)
CREATE SCHEMA IF NOT EXISTS extensions;
GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;

-- =============================================
-- PERMISSIONS
-- =============================================

-- Grant usage on public schema
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role, supabase_admin;

-- Grant all on public schema to admin roles
GRANT ALL ON SCHEMA public TO supabase_admin;
GRANT ALL ON SCHEMA public TO service_role;

-- Default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO supabase_admin;

-- Default privileges for sequences
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE ON SEQUENCES TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role, supabase_admin;

-- Default privileges for functions
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO anon, authenticated, service_role;

-- =============================================
-- STORAGE SERVICE PERMISSIONS
-- =============================================

-- Storage admin needs to create tables and run migrations
GRANT CREATE ON DATABASE postgres TO supabase_storage_admin;
ALTER ROLE supabase_storage_admin SET search_path TO storage, public, extensions;

-- Grant storage admin ownership ability
GRANT ALL ON SCHEMA storage TO supabase_storage_admin WITH GRANT OPTION;

-- Storage admin can create extensions
GRANT CREATE ON SCHEMA extensions TO supabase_storage_admin;

-- =============================================
-- SUPAVISOR PERMISSIONS
-- =============================================

-- Grant supavisor schema permissions for migrations
GRANT ALL ON SCHEMA _supavisor TO supabase_admin WITH GRANT OPTION;

-- Create migration tracking table for supavisor if schema exists
DO $$
BEGIN
    -- Ensure the schema_migrations table can be created
    EXECUTE 'ALTER SCHEMA _supavisor OWNER TO supabase_admin';
EXCEPTION
    WHEN OTHERS THEN
        NULL; -- Ignore if already owned
END
$$;

-- =============================================
-- META SERVICE PERMISSIONS
-- =============================================

-- supabase_admin needs access for postgres-meta service
GRANT ALL PRIVILEGES ON DATABASE postgres TO supabase_admin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO supabase_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO supabase_admin;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO supabase_admin;

-- =============================================
-- SET PASSWORDS (using environment variable)
-- =============================================

-- Set authenticator password from POSTGRES_PASSWORD env var
DO $$
DECLARE
    pg_pass TEXT;
BEGIN
    -- Try to get password from environment
    pg_pass := current_setting('app.settings.postgres_password', true);
    IF pg_pass IS NULL OR pg_pass = '' THEN
        -- Fallback: use the postgres user's password (set via POSTGRES_PASSWORD env)
        -- This requires the password to be passed differently
        RAISE NOTICE 'Password not set via app.settings, authenticator may need manual password setup';
    ELSE
        EXECUTE format('ALTER ROLE authenticator WITH PASSWORD %L', pg_pass);
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Could not set authenticator password: %', SQLERRM;
END
$$;
