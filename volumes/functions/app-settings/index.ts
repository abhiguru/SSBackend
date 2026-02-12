// App Settings Edge Function (Public)
// GET /functions/v1/app-settings
// Returns customer-facing app settings

import { getServiceClient } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

const CUSTOMER_FACING_KEYS = [
  'shipping_charge_paise',
  'free_shipping_threshold_paise',
  'serviceable_pincodes',
  'min_order_paise',
];

export async function handler(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    if (req.method !== 'GET') {
      return errorResponse('METHOD_NOT_ALLOWED', 'Only GET requests allowed', 405);
    }

    const supabase = getServiceClient();

    const { data, error } = await supabase
      .from('app_settings')
      .select('key, value')
      .in('key', CUSTOMER_FACING_KEYS);

    if (error) {
      console.error('Failed to fetch app settings:', error);
      return errorResponse('SERVER_ERROR', 'Failed to fetch settings', 500);
    }

    const settings: Record<string, string> = {};
    for (const row of data ?? []) {
      settings[row.key] = row.value;
    }

    return jsonResponse({ settings }, 200, { cacheMaxAge: 300 });
  } catch (error) {
    return handleError(error, 'app-settings');
  }
}
