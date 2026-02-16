// Delete User Edge Function (Admin only)
// POST /functions/v1/delete-user
// Admin-initiated user deletion without a prior user request

import { requireAdmin, getServiceClient } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

export async function handler(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    if (req.method !== 'POST') {
      return errorResponse('METHOD_NOT_ALLOWED', 'Only POST requests allowed', 405);
    }

    const auth = await requireAdmin(req);
    const supabase = getServiceClient();

    let body: { user_id?: string };
    try {
      body = await req.json();
    } catch {
      return errorResponse('BAD_REQUEST', 'Invalid JSON body', 400);
    }

    const { user_id } = body;
    if (!user_id || typeof user_id !== 'string') {
      return errorResponse('BAD_REQUEST', 'user_id is required', 400);
    }

    const { data: _result, error: rpcError } = await supabase.rpc('admin_delete_user', {
      p_user_id: user_id,
      p_admin_id: auth.userId,
    });

    if (rpcError) {
      if (rpcError.message.includes('USER_NOT_FOUND')) {
        return errorResponse('USER_NOT_FOUND', 'No user with that ID exists', 404);
      }
      if (rpcError.message.includes('CANNOT_DELETE_ADMIN')) {
        return errorResponse('CANNOT_DELETE_ADMIN', 'Cannot delete an admin user', 403);
      }
      if (rpcError.message.includes('STAFF_HAS_ACTIVE_DELIVERY')) {
        return errorResponse('STAFF_HAS_ACTIVE_DELIVERY', 'Delivery staff member has an active delivery in progress', 409);
      }
      console.error('Error deleting user:', rpcError);
      return errorResponse('SERVER_ERROR', rpcError.message, 500);
    }

    return jsonResponse({ success: true });
  } catch (error) {
    return handleError(error, 'DeleteUser');
  }
}

// For standalone execution
Deno.serve(handler);
