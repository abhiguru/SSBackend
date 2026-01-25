-- =============================================
-- Masala Spice Shop - Auth Helper Functions
-- =============================================
-- These functions extract claims from JWT tokens for RLS policies

-- Create auth schema if not exists
CREATE SCHEMA IF NOT EXISTS auth;

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
CREATE OR REPLACE FUNCTION auth.role()
RETURNS user_role AS $$
DECLARE
    jwt_claim TEXT;
BEGIN
    -- Get the 'role' claim from the JWT
    jwt_claim := current_setting('request.jwt.claims', true)::json->>'role';

    IF jwt_claim IS NULL OR jwt_claim = '' THEN
        -- Check if it's a service role token
        IF current_setting('request.jwt.claims', true)::json->>'role' = 'service_role' THEN
            RETURN 'super_admin'::user_role;
        END IF;
        RETURN NULL;
    END IF;

    -- Handle both custom role claim and Supabase role claim
    IF jwt_claim IN ('customer', 'admin', 'delivery_staff', 'super_admin') THEN
        RETURN jwt_claim::user_role;
    ELSIF jwt_claim = 'service_role' THEN
        RETURN 'super_admin'::user_role;
    END IF;

    RETURN 'customer'::user_role;
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
        CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD current_setting('app.settings.postgres_password', true);
    END IF;
END
$$;

-- Grant role inheritance
GRANT anon TO authenticator;
GRANT authenticated TO authenticator;
