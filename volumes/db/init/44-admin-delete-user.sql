-- Admin-initiated user deletion (without a prior deletion request)
-- Reuses the same cleanup logic as process_account_deletion_atomic

CREATE OR REPLACE FUNCTION admin_delete_user(
    p_user_id UUID,
    p_admin_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_user RECORD;
    v_uuid_prefix TEXT;
BEGIN
    -- Fetch & lock the user
    SELECT * INTO v_user FROM users WHERE id = p_user_id FOR UPDATE;

    IF v_user IS NULL THEN
        RAISE EXCEPTION 'USER_NOT_FOUND';
    END IF;

    -- Cannot delete admins
    IF v_user.role = 'admin' THEN
        RAISE EXCEPTION 'CANNOT_DELETE_ADMIN';
    END IF;

    -- Check active delivery assignments for delivery staff
    IF v_user.role = 'delivery_staff' AND EXISTS (
        SELECT 1 FROM orders WHERE delivery_staff_id = v_user.id
        AND status = 'out_for_delivery'
    ) THEN
        RAISE EXCEPTION 'STAFF_HAS_ACTIVE_DELIVERY';
    END IF;

    -- NULL out delivery_staff_id on terminal orders
    IF v_user.role = 'delivery_staff' THEN
        UPDATE orders SET delivery_staff_id = NULL
        WHERE delivery_staff_id = v_user.id AND status IN ('delivered', 'cancelled');
    END IF;

    -- Delete user data
    DELETE FROM user_addresses WHERE user_id = v_user.id;
    DELETE FROM favorites WHERE user_id = v_user.id;
    DELETE FROM push_tokens WHERE user_id = v_user.id;
    DELETE FROM refresh_tokens WHERE user_id = v_user.id;

    -- Clean phone-based records
    DELETE FROM otp_requests WHERE phone = v_user.phone;
    DELETE FROM otp_rate_limits WHERE phone_number = v_user.phone;
    DELETE FROM test_otp_records WHERE phone_number = v_user.phone;

    -- Resolve any pending deletion request for this user
    UPDATE account_deletion_requests SET
        status = 'approved',
        processed_by = p_admin_id,
        processed_at = NOW(),
        admin_notes = 'Resolved via admin-initiated deletion'
    WHERE user_id = v_user.id AND status = 'pending';

    -- Anonymize user
    v_uuid_prefix := substring(gen_random_uuid()::TEXT from 1 for 8);
    UPDATE users SET
        phone = '+00deleted_' || v_uuid_prefix,
        name = 'Deleted User',
        is_active = false
    WHERE id = v_user.id;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION admin_delete_user TO service_role;
