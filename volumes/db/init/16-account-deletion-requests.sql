-- =============================================
-- Account Deletion Requests
-- =============================================
-- Allows customers to request account deletion.
-- Admins review and process these requests.

BEGIN;

-- =============================================
-- TABLE
-- =============================================

CREATE TABLE IF NOT EXISTS account_deletion_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    admin_notes TEXT,
    processed_by UUID REFERENCES users(id),
    processed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT adr_status_check CHECK (status IN ('pending', 'approved', 'rejected'))
);

-- =============================================
-- INDEXES
-- =============================================

CREATE INDEX IF NOT EXISTS idx_adr_user_status
    ON account_deletion_requests(user_id, status);

-- =============================================
-- UPDATED_AT TRIGGER
-- =============================================

CREATE TRIGGER set_adr_updated_at
    BEFORE UPDATE ON account_deletion_requests
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();

-- =============================================
-- ROW LEVEL SECURITY
-- =============================================

ALTER TABLE account_deletion_requests ENABLE ROW LEVEL SECURITY;

-- Users can view their own requests
CREATE POLICY "adr_user_select" ON account_deletion_requests
    FOR SELECT TO authenticated
    USING ((select auth.uid()) = user_id);

-- Users can insert their own requests
CREATE POLICY "adr_user_insert" ON account_deletion_requests
    FOR INSERT TO authenticated
    WITH CHECK ((select auth.uid()) = user_id);

-- Admins can do everything
CREATE POLICY "adr_admin_all" ON account_deletion_requests
    FOR ALL TO authenticated
    USING ((select auth.is_admin()))
    WITH CHECK ((select auth.is_admin()));

-- =============================================
-- GRANTS
-- =============================================

GRANT SELECT, INSERT ON account_deletion_requests TO authenticated;
GRANT ALL ON account_deletion_requests TO service_role;

COMMIT;
