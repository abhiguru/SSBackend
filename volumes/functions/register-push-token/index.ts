// Register Push Token endpoint
// Upserts an Expo push token for the authenticated user

import { requireAuth, getServiceClient } from "../_shared/auth.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

export async function handler(req: Request): Promise<Response> {
  if (req.method !== 'POST') {
    return errorResponse('METHOD_NOT_ALLOWED', 'Only POST is allowed', 405);
  }

  try {
    const auth = await requireAuth(req);

    const body = await req.json();
    const { push_token, platform } = body;

    if (!push_token || typeof push_token !== 'string') {
      return errorResponse('INVALID_INPUT', 'push_token is required', 400);
    }

    // Validate Expo push token format
    if (!push_token.startsWith('ExponentPushToken[') && !push_token.startsWith('ExpoPushToken[')) {
      return errorResponse('INVALID_TOKEN', 'Invalid Expo push token format', 400);
    }

    const validPlatform = platform === 'ios' ? 'ios' : 'android';

    const supabase = getServiceClient();

    // Upsert: on conflict (user_id, token) update the timestamp and platform
    const { error } = await supabase
      .from('push_tokens')
      .upsert(
        {
          user_id: auth.userId,
          token: push_token,
          platform: validPlatform,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'user_id,token' }
      );

    if (error) {
      console.error('Failed to upsert push token:', error);
      return errorResponse('DB_ERROR', 'Failed to register push token', 500);
    }

    return jsonResponse({ success: true });
  } catch (error) {
    return handleError(error, 'register-push-token');
  }
}
