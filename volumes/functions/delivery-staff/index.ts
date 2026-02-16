// Delivery Staff Edge Function (Admin only)
// GET  /functions/v1/delivery-staff — List active delivery staff with availability
// POST /functions/v1/delivery-staff — Add new delivery staff (create or promote)

import { getServiceClient, requireAdmin, validatePhone, normalizePhone } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

interface DeliveryStaff {
  id: string;
  name: string;
  phone: string;
  is_available: boolean;
}

export async function handler(req: Request): Promise<Response> {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    if (req.method === 'GET') {
      return await handleGet(req);
    } else if (req.method === 'POST') {
      return await handlePost(req);
    } else {
      return errorResponse('METHOD_NOT_ALLOWED', 'Only GET and POST requests allowed', 405);
    }
  } catch (error) {
    return handleError(error, 'Delivery staff');
  }
}

async function handleGet(req: Request): Promise<Response> {
  // Require admin authentication
  await requireAdmin(req);
  const supabase = getServiceClient();

  // Get all active delivery staff
  const { data: staff, error: staffError } = await supabase
    .from('users')
    .select('id, name, phone')
    .eq('role', 'delivery_staff')
    .eq('is_active', true)
    .order('name', { ascending: true });

  if (staffError) {
    console.error('Failed to fetch delivery staff:', staffError);
    return errorResponse('DATABASE_ERROR', 'Failed to fetch delivery staff', 500);
  }

  // Get staff currently on active in-house deliveries
  const { data: activeDeliveries } = await supabase
    .from('orders')
    .select('delivery_staff_id')
    .eq('status', 'out_for_delivery')
    .not('delivery_staff_id', 'is', null);

  const busyStaffIds = new Set(
    activeDeliveries?.map(o => o.delivery_staff_id).filter(Boolean) || []
  );

  // Map with availability status
  const staffWithAvailability: DeliveryStaff[] = (staff || []).map(s => ({
    id: s.id,
    name: s.name,
    phone: s.phone,
    is_available: !busyStaffIds.has(s.id),
  }));

  return jsonResponse({
    success: true,
    staff: staffWithAvailability,
  });
}

async function handlePost(req: Request): Promise<Response> {
  await requireAdmin(req);
  const supabase = getServiceClient();

  const body = await req.json();
  const { name, phone } = body;

  // Validate name
  if (!name || typeof name !== 'string' || !name.trim()) {
    return errorResponse('MISSING_NAME', 'Name is required', 400);
  }

  // Validate and normalize phone
  const normalized = normalizePhone(phone || '');
  if (!validatePhone(normalized)) {
    return errorResponse('INVALID_PHONE', 'Invalid phone number. Expected format: +91XXXXXXXXXX', 400);
  }

  // Lookup existing user by phone
  const { data: existing, error: lookupError } = await supabase
    .from('users')
    .select('id, name, phone, role, is_active')
    .eq('phone', normalized)
    .maybeSingle();

  if (lookupError) {
    console.error('Failed to lookup user:', lookupError);
    return errorResponse('DATABASE_ERROR', 'Failed to lookup user', 500);
  }

  if (existing) {
    if (existing.role === 'delivery_staff') {
      return errorResponse('STAFF_ALREADY_EXISTS', 'This phone number is already registered as delivery staff', 409);
    }
    if (existing.role === 'admin') {
      return errorResponse('PHONE_IN_USE', 'This phone number belongs to an admin account', 409);
    }

    // Promote customer to delivery_staff
    const { data: updated, error: updateError } = await supabase
      .from('users')
      .update({ role: 'delivery_staff', name: name.trim(), is_active: true })
      .eq('id', existing.id)
      .select('id, name, phone, is_active')
      .single();

    if (updateError) {
      console.error('Failed to promote user:', updateError);
      return errorResponse('DATABASE_ERROR', 'Failed to promote user to delivery staff', 500);
    }

    return jsonResponse({ success: true, staff: updated }, 200);
  }

  // Create new user as delivery_staff
  const { data: created, error: createError } = await supabase
    .from('users')
    .insert({ phone: normalized, name: name.trim(), role: 'delivery_staff', is_active: true })
    .select('id, name, phone, is_active')
    .single();

  if (createError) {
    console.error('Failed to create delivery staff:', createError);
    return errorResponse('DATABASE_ERROR', 'Failed to create delivery staff', 500);
  }

  return jsonResponse({ success: true, staff: created }, 201);
}

// For standalone execution
Deno.serve(handler);
