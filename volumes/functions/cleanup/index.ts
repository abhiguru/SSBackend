// Cleanup Edge Function (Admin only)
// POST /functions/v1/cleanup
// Deletes expired OTPs, revoked/expired refresh tokens, stale rate limit records

import { getServiceClient, requireAdmin } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

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

    // Require admin authentication
    await requireAdmin(req);
    const supabase = getServiceClient();

    // Run cleanup via database function
    const { data, error } = await supabase.rpc('cleanup_expired_data');

    if (error) {
      console.error('Cleanup failed:', error);
      return errorResponse('SERVER_ERROR', 'Cleanup operation failed', 500);
    }

    return jsonResponse({
      success: true,
      message: 'Cleanup completed',
      stats: data,
    });
  } catch (error) {
    return handleError(error, 'Cleanup');
  }
}

// For standalone execution
Deno.serve(handler);
