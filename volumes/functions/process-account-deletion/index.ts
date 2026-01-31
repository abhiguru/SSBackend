// Process Account Deletion Edge Function
// POST /functions/v1/process-account-deletion
// Admin-only: approve or reject account deletion requests

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

    // Parse and validate body
    let body: { request_id?: string; action?: string; admin_notes?: string };
    try {
      body = await req.json();
    } catch {
      return errorResponse('BAD_REQUEST', 'Invalid JSON body', 400);
    }

    const { request_id, action, admin_notes } = body;

    if (!request_id || typeof request_id !== 'string') {
      return errorResponse('BAD_REQUEST', 'request_id is required', 400);
    }

    if (action !== 'approved' && action !== 'rejected') {
      return errorResponse('BAD_REQUEST', 'action must be "approved" or "rejected"', 400);
    }

    // Fetch the deletion request
    const { data: deletionRequest, error: fetchError } = await supabase
      .from('account_deletion_requests')
      .select('id, user_id, status')
      .eq('id', request_id)
      .maybeSingle();

    if (fetchError) {
      console.error('Error fetching deletion request:', fetchError);
      return errorResponse('SERVER_ERROR', 'Failed to fetch deletion request', 500);
    }

    if (!deletionRequest) {
      return errorResponse('NOT_FOUND', 'Deletion request not found', 404);
    }

    if (deletionRequest.status !== 'pending') {
      return errorResponse('ALREADY_PROCESSED', `Request already ${deletionRequest.status}`, 409);
    }

    // Handle rejection — just update the request row
    if (action === 'rejected') {
      const { error: updateError } = await supabase
        .from('account_deletion_requests')
        .update({
          status: 'rejected',
          processed_by: auth.userId,
          processed_at: new Date().toISOString(),
          admin_notes: admin_notes || null,
        })
        .eq('id', request_id);

      if (updateError) {
        console.error('Error rejecting deletion request:', updateError);
        return errorResponse('SERVER_ERROR', 'Failed to reject request', 500);
      }

      return jsonResponse({ message: 'Account deletion request rejected' });
    }

    // Handle approval — validate + anonymize atomically
    const { data: result, error: rpcError } = await supabase.rpc('process_account_deletion_atomic', {
      p_request_id: request_id,
      p_admin_id: auth.userId,
      p_admin_notes: admin_notes || null,
    });

    if (rpcError) {
      if (rpcError.message.includes('ACTIVE_ORDERS_EXIST')) {
        return errorResponse('ACTIVE_ORDERS_EXIST', 'User has active orders that must be resolved first', 409);
      }
      if (rpcError.message.includes('ACTIVE_DELIVERY_ASSIGNMENTS')) {
        return errorResponse('ACTIVE_DELIVERY_ASSIGNMENTS', 'User has active delivery assignments that must be resolved first', 409);
      }
      if (rpcError.message.includes('User not found')) {
        return errorResponse('NOT_FOUND', 'User not found', 404);
      }
      console.error('Error processing account deletion:', rpcError);
      return errorResponse('SERVER_ERROR', rpcError.message, 500);
    }

    return jsonResponse({ message: 'Account deletion approved and user anonymized' });
  } catch (error) {
    return handleError(error, 'ProcessAccountDeletion');
  }
}

// For standalone execution
Deno.serve(handler);
