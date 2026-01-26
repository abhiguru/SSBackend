-- =============================================
-- Fix JWT role claim for PostgREST compatibility
-- =============================================
-- Problem: JWT had role: "customer" (etc.), but PostgREST does SET ROLE <jwt.role>
-- and no PostgreSQL role "customer" exists, causing 400 errors.
-- Solution: JWT now uses role: "authenticated" (PG role) + user_role: "customer" (app role).
-- This migration updates auth.role() to read user_role claim first.

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
