// Admin User Management - List users and update roles
// PERFORMANCE OPTIMIZED: Item 18, 19 from performance audit

import { requireAdmin, getServiceClient } from "../_shared/auth.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

const VALID_ROLES = ['customer', 'admin', 'delivery_staff'] as const;

// Item 18: Default and max pagination limits
const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;

export async function handler(req: Request): Promise<Response> {
  try {
    if (req.method === 'GET') {
      return await handleGet(req);
    } else if (req.method === 'PATCH') {
      return await handlePatch(req);
    }
    return errorResponse('METHOD_NOT_ALLOWED', 'Use GET or PATCH', 405);
  } catch (error) {
    return handleError(error, 'users');
  }
}

async function handleGet(req: Request): Promise<Response> {
  await requireAdmin(req);

  const url = new URL(req.url);
  const search = url.searchParams.get('search');
  const role = url.searchParams.get('role');

  // Item 18: Parse and validate pagination parameters
  let limit = parseInt(url.searchParams.get('limit') ?? '', 10);
  let offset = parseInt(url.searchParams.get('offset') ?? '', 10);

  if (isNaN(limit) || limit < 1) {
    limit = DEFAULT_LIMIT;
  } else if (limit > MAX_LIMIT) {
    limit = MAX_LIMIT;
  }

  if (isNaN(offset) || offset < 0) {
    offset = 0;
  }

  const supabase = getServiceClient();

  // Item 19: Select specific columns instead of * (reduces data transfer)
  let query = supabase
    .from('users')
    .select('id, name, phone, role, is_active, created_at', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(offset, offset + limit - 1);

  if (search) {
    query = query.or(`name.ilike.%${search}%,phone.ilike.%${search}%`);
  }

  if (role && VALID_ROLES.includes(role as typeof VALID_ROLES[number])) {
    query = query.eq('role', role);
  }

  const { data, error, count } = await query;

  if (error) {
    console.error('Users query error:', error);
    return errorResponse('QUERY_ERROR', 'Failed to fetch users', 500);
  }

  // Return paginated response with metadata
  return jsonResponse({
    data,
    pagination: {
      offset,
      limit,
      total: count ?? 0,
      hasMore: count !== null && offset + limit < count,
    },
  });
}

async function handlePatch(req: Request): Promise<Response> {
  const auth = await requireAdmin(req);

  const body = await req.json();
  const { user_id, role, name } = body;

  if (!user_id) {
    return errorResponse('MISSING_USER_ID', 'user_id is required', 400);
  }

  if (role !== undefined && !VALID_ROLES.includes(role)) {
    return errorResponse('INVALID_ROLE', `role must be one of: ${VALID_ROLES.join(', ')}`, 400);
  }

  if (role !== undefined && user_id === auth.userId) {
    return errorResponse('CANNOT_CHANGE_OWN_ROLE', 'You cannot change your own role', 400);
  }

  const supabase = getServiceClient();

  // Fetch target user - Item 19: Select only needed columns
  const { data: targetUser, error: fetchError } = await supabase
    .from('users')
    .select('id, role, is_active')
    .eq('id', user_id)
    .single();

  if (fetchError || !targetUser) {
    return errorResponse('USER_NOT_FOUND', 'User not found', 404);
  }

  const oldRole = targetUser.role;
  const newRole = role ?? oldRole;

  // Check active deliveries when demoting from delivery_staff
  if (oldRole === 'delivery_staff' && newRole !== 'delivery_staff') {
    const { data: activeOrders } = await supabase
      .from('orders')
      .select('id')
      .eq('delivery_staff_id', user_id)
      .eq('status', 'out_for_delivery')
      .limit(1);

    if (activeOrders && activeOrders.length > 0) {
      return errorResponse(
        'STAFF_HAS_ACTIVE_DELIVERY',
        'Cannot change role while staff has active deliveries',
        400,
      );
    }
  }

  // Build update
  const updateData: Record<string, unknown> = {};
  if (role !== undefined) updateData.role = role;
  if (name !== undefined) updateData.name = name;

  // Auto-activate when promoting to delivery_staff
  if (newRole === 'delivery_staff' && oldRole !== 'delivery_staff') {
    updateData.is_active = true;
  }

  if (Object.keys(updateData).length === 0) {
    return errorResponse('NO_CHANGES', 'No fields to update', 400);
  }

  const { data: updated, error: updateError } = await supabase
    .from('users')
    .update(updateData)
    .eq('id', user_id)
    .select('id, name, phone, role, is_active, created_at')
    .single();

  if (updateError) {
    console.error('User update error:', updateError);
    return errorResponse('UPDATE_ERROR', 'Failed to update user', 500);
  }

  return jsonResponse(updated);
}
