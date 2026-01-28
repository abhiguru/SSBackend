// Delivery Staff List Edge Function (Admin only)
// GET /functions/v1/delivery-staff
// Returns list of active delivery staff with availability status

import { getServiceClient, requireAdmin } from "../_shared/auth.ts";
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
    // Only allow GET
    if (req.method !== 'GET') {
      return errorResponse('METHOD_NOT_ALLOWED', 'Only GET requests allowed', 405);
    }

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
      .eq('delivery_type', 'in_house')
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
  } catch (error) {
    return handleError(error, 'Delivery staff list');
  }
}

// For standalone execution
Deno.serve(handler);
