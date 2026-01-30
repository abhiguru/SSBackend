-- =============================================
-- Remove super_admin role usage
-- =============================================
-- Collapses super_admin into admin. The enum value remains in user_role
-- (PG cannot drop enum values without recreating the type), but nothing
-- references it after this migration.

BEGIN;

-- =============================================
-- 1. Migrate existing super_admin users to admin
-- =============================================
UPDATE users SET role = 'admin' WHERE role = 'super_admin';

-- =============================================
-- 2. Redefine auth.role() — map super_admin → admin, service_role → admin
-- =============================================
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
    IF user_role_claim IS NOT NULL THEN
        IF user_role_claim IN ('customer', 'admin', 'delivery_staff') THEN
            RETURN user_role_claim::user_role;
        ELSIF user_role_claim = 'super_admin' THEN
            RETURN 'admin'::user_role;
        END IF;
    END IF;

    -- Fall back to role claim (service_role tokens, legacy JWTs)
    IF role_claim IS NOT NULL THEN
        IF role_claim IN ('customer', 'admin', 'delivery_staff') THEN
            RETURN role_claim::user_role;
        ELSIF role_claim IN ('super_admin', 'service_role') THEN
            RETURN 'admin'::user_role;
        END IF;
    END IF;

    RETURN NULL;
EXCEPTION
    WHEN OTHERS THEN
        RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================
-- 3. Simplify auth.is_admin()
-- =============================================
CREATE OR REPLACE FUNCTION auth.is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN auth.role() = 'admin';
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- =============================================
-- 4. Drop policies that depend on auth.is_super_admin() FIRST
-- =============================================
DROP POLICY IF EXISTS "users_superadmin_insert" ON users;
DROP POLICY IF EXISTS "settings_superadmin_insert" ON app_settings;

-- =============================================
-- 5. Now drop auth.is_super_admin()
-- =============================================
REVOKE ALL ON FUNCTION auth.is_super_admin() FROM anon, authenticated;
DROP FUNCTION IF EXISTS auth.is_super_admin();

-- =============================================
-- 6. Recreate policies using auth.is_admin()
-- =============================================
CREATE POLICY "users_admin_insert" ON users
    FOR INSERT TO authenticated
    WITH CHECK ((select auth.is_admin()));

CREATE POLICY "settings_admin_insert" ON app_settings
    FOR INSERT TO authenticated
    WITH CHECK ((select auth.is_admin()));

COMMIT;
