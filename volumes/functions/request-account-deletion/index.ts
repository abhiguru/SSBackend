// Request Account Deletion Edge Function
// POST /functions/v1/request-account-deletion
// Allows authenticated users to request account deletion

import { requireAuth, getServiceClient } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";
import { sendPushToUsers } from "../_shared/push.ts";

export async function handler(req: Request): Promise<Response> {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Only allow POST
    if (req.method !== 'POST') {
      return errorResponse('METHOD_NOT_ALLOWED', 'Only POST requests allowed', 405);
    }

    // Require authentication
    const auth = await requireAuth(req);
    const supabase = getServiceClient();

    // Check for existing pending request
    const { data: existing, error: checkError } = await supabase
      .from('account_deletion_requests')
      .select('id')
      .eq('user_id', auth.userId)
      .eq('status', 'pending')
      .maybeSingle();

    if (checkError) {
      console.error('Error checking existing deletion request:', checkError);
      return errorResponse('SERVER_ERROR', 'Failed to check existing requests', 500);
    }

    if (existing) {
      return errorResponse('DELETION_001', 'A pending account deletion request already exists', 409);
    }

    // Insert new deletion request
    const { error: insertError } = await supabase
      .from('account_deletion_requests')
      .insert({ user_id: auth.userId, status: 'pending' });

    if (insertError) {
      console.error('Error inserting deletion request:', insertError.message, insertError.code);
      return errorResponse('SERVER_ERROR', 'Failed to submit deletion request', 500);
    }

    // Notify admins (best-effort, don't fail the request)
    try {
      const { data: admins } = await supabase
        .from('users')
        .select('id')
        .eq('role', 'admin')
        .eq('is_active', true);

      if (admins && admins.length > 0) {
        const adminIds = admins.map((a: { id: string }) => a.id);
        await sendPushToUsers(adminIds, {
          title: 'Account Deletion Request',
          body: `A user has requested account deletion.`,
          data: { type: 'account_deletion_request', user_id: auth.userId },
        });
      }
    } catch (pushError) {
      console.error('Failed to notify admins:', pushError);
    }

    return jsonResponse({ message: 'Account deletion request submitted' });
  } catch (error) {
    return handleError(error, 'RequestAccountDeletion');
  }
}

// For standalone execution
Deno.serve(handler);
