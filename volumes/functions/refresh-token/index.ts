// Refresh Token Edge Function
// POST /functions/v1/refresh-token
// Body: { refresh_token: "..." }
//
// Flow:
// 1. Hash the provided refresh token
// 2. Look up in refresh_tokens table
// 3. If revoked -> revoke ALL user tokens (reuse detection), return 401
// 4. If expired -> return 401
// 5. Fetch fresh user data (role, active status)
// 6. Rotate: revoke old token, issue new refresh token
// 7. Issue new access_token via signJWT with user_role
// 8. Return { success, access_token, refresh_token, user }

import { getServiceClient, hashOTP, signJWT } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

interface RefreshTokenRequest {
  refresh_token: string;
}

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

    // Parse request body
    const body: RefreshTokenRequest = await req.json();

    if (!body.refresh_token) {
      return errorResponse('INVALID_INPUT', 'refresh_token is required', 400);
    }

    const supabase = getServiceClient();

    // Hash the provided refresh token
    const tokenHash = await hashOTP(body.refresh_token);

    // Look up the refresh token
    const { data: tokenRecord, error: tokenError } = await supabase
      .from('refresh_tokens')
      .select('*')
      .eq('token_hash', tokenHash)
      .single();

    if (tokenError || !tokenRecord) {
      return errorResponse('INVALID_TOKEN', 'Invalid refresh token', 401);
    }

    // Reuse detection: if token is already revoked, revoke ALL tokens for this user
    if (tokenRecord.revoked) {
      console.warn(`[REFRESH_TOKEN] Reuse detected for user ${tokenRecord.user_id}, revoking all tokens`);

      await supabase
        .from('refresh_tokens')
        .update({ revoked: true })
        .eq('user_id', tokenRecord.user_id)
        .eq('revoked', false);

      return errorResponse('TOKEN_REVOKED', 'Refresh token has been revoked. Please log in again.', 401);
    }

    // Check expiration
    if (new Date(tokenRecord.expires_at) < new Date()) {
      // Revoke the expired token
      await supabase
        .from('refresh_tokens')
        .update({ revoked: true })
        .eq('id', tokenRecord.id);

      return errorResponse('TOKEN_EXPIRED', 'Refresh token has expired. Please log in again.', 401);
    }

    // Fetch fresh user data
    const { data: user, error: userError } = await supabase
      .from('users')
      .select('id, phone, name, role, language, is_active')
      .eq('id', tokenRecord.user_id)
      .single();

    if (userError || !user) {
      return errorResponse('USER_NOT_FOUND', 'User not found', 401);
    }

    if (!user.is_active) {
      // Revoke all tokens for deactivated user
      await supabase
        .from('refresh_tokens')
        .update({ revoked: true })
        .eq('user_id', user.id)
        .eq('revoked', false);

      return errorResponse('ACCOUNT_DEACTIVATED', 'Your account has been deactivated', 403);
    }

    // Rotate: revoke old token
    await supabase
      .from('refresh_tokens')
      .update({ revoked: true })
      .eq('id', tokenRecord.id);

    // Issue new refresh token
    const newRefreshTokenValue = crypto.randomUUID() + crypto.randomUUID();
    const newRefreshTokenHash = await hashOTP(newRefreshTokenValue);
    const refreshExpiry = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();

    await supabase
      .from('refresh_tokens')
      .insert({
        user_id: user.id,
        token_hash: newRefreshTokenHash,
        expires_at: refreshExpiry,
        revoked: false,
      });

    // Issue new access token (1 hour)
    const accessToken = await signJWT({
      sub: user.id,
      phone: user.phone,
      user_role: user.role,
    }, 3600);

    return jsonResponse({
      success: true,
      access_token: accessToken,
      refresh_token: newRefreshTokenValue,
      user: {
        id: user.id,
        phone: user.phone,
        name: user.name,
        role: user.role,
        language: user.language || 'en',
      },
    });
  } catch (error) {
    return handleError(error, 'Refresh token');
  }
}

// For standalone execution
Deno.serve(handler);
