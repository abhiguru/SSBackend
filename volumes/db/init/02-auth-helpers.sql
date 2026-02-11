-- =============================================
-- Masala Spice Shop - Auth Helper Functions
-- =============================================
-- These functions extract claims from JWT tokens for RLS policies

-- Create auth schema if not exists
CREATE SCHEMA IF NOT EXISTS auth;

-- Drop built-in auth functions that have incompatible return types
DROP FUNCTION IF EXISTS auth.uid();
DROP FUNCTION IF EXISTS auth.role();
DROP FUNCTION IF EXISTS auth.email();
DROP FUNCTION IF EXISTS auth.jwt();

-- =============================================
-- auth.uid() - Extract user ID from JWT
-- =============================================
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS UUID AS $$
DECLARE
    jwt_claim TEXT;
BEGIN
    -- Get the 'sub' claim from the JWT (set by PostgREST)
    jwt_claim := current_setting('request.jwt.claims', true)::json->>'sub';

    IF jwt_claim IS NULL OR jwt_claim = '' THEN
        RETURN NULL;
    END IF;

    RETURN jwt_claim::UUID;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================
-- auth.role() - Extract user role from JWT
-- =============================================
-- Reads 'user_role' claim first (new JWT format), falls back to 'role' claim
-- for backward compat and service_role tokens.
CREATE OR REPLACE FUNCTION auth.role()
RETURNS user_role AS $$
DECLARE
    jwt_claims JSON;
    user_role_claim TEXT;
    role_claim TEXT;
BEGIN
    jwt_claims := current_setting('request.jwt.claims', true)::json;
    user_role_claim := jwt_claims->>'user_role';
    role_claim := jwt_claims->>'role';

    -- Prefer user_role claim (new JWT format)
    IF user_role_claim IS NOT NULL AND user_role_claim IN ('customer', 'admin', 'delivery_staff', 'super_admin') THEN
        RETURN user_role_claim::user_role;
    END IF;

    -- Fall back to role claim (service_role tokens, legacy JWTs)
    IF role_claim IS NOT NULL THEN
        IF role_claim IN ('customer', 'admin', 'delivery_staff', 'super_admin') THEN
            RETURN role_claim::user_role;
        ELSIF role_claim = 'service_role' THEN
            RETURN 'super_admin'::user_role;
        END IF;
    END IF;

    RETURN NULL;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================
-- auth.is_admin() - Check if current user is admin
-- =============================================
CREATE OR REPLACE FUNCTION auth.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN auth.role() IN ('admin', 'super_admin');
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================
-- auth.is_delivery_staff() - Check if current user is delivery staff
-- =============================================
CREATE OR REPLACE FUNCTION auth.is_delivery_staff()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN auth.role() = 'delivery_staff';
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================
-- auth.is_super_admin() - Check if current user is super admin
-- =============================================
CREATE OR REPLACE FUNCTION auth.is_super_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN auth.role() = 'super_admin';
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================
-- auth.check_user_active() - Verify user is active
-- =============================================
CREATE OR REPLACE FUNCTION auth.check_user_active()
RETURNS BOOLEAN AS $$
DECLARE
    user_active BOOLEAN;
BEGIN
    SELECT is_active INTO user_active
    FROM users
    WHERE id = auth.uid();

    RETURN COALESCE(user_active, false);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================
-- Grant permissions
-- =============================================
GRANT USAGE ON SCHEMA auth TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.role() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.is_admin() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.is_delivery_staff() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.is_super_admin() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION auth.check_user_active() TO anon, authenticated;

-- =============================================
-- Create authenticated role if not exists
-- =============================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
        CREATE ROLE authenticated NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
        CREATE ROLE anon NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticator') THEN
        CREATE ROLE authenticator NOINHERIT LOGIN;
    END IF;
END
$$;

-- Grant role inheritance
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
