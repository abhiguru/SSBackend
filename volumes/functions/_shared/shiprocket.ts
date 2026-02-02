// Shiprocket API Helper
// Token management, API wrapper, and status mapping

import { getServiceClient } from "./auth.ts";

const SR_BASE_URL = "https://apiv2.shiprocket.in/v1/external";
const TOKEN_TTL_MS = 9 * 24 * 60 * 60 * 1000; // 9 days (token valid for 10 days, refresh 1 day early)

interface SRTokenCache {
  token: string;
  expires_at: string; // ISO timestamp
}

// Fetch a valid Shiprocket JWT, refreshing if expired
async function getToken(): Promise<string> {
  const supabase = getServiceClient();

  // Check cached token in app_settings
  const { data: setting } = await supabase
    .from("app_settings")
    .select("value")
    .eq("key", "shiprocket_token")
    .single();

  if (setting?.value) {
    const cached = setting.value as SRTokenCache;
    if (cached.token && cached.expires_at && new Date(cached.expires_at) > new Date()) {
      return cached.token;
    }
  }

  // Token missing or expired — login
  const email = Deno.env.get("SHIPROCKET_EMAIL");
  const password = Deno.env.get("SHIPROCKET_PASSWORD");

  if (!email || !password) {
    throw new Error("SHIPROCKET_EMAIL and SHIPROCKET_PASSWORD must be set");
  }

  const res = await fetch(`${SR_BASE_URL}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Shiprocket login failed (${res.status}): ${body}`);
  }

  const data = await res.json();
  const token = data.token as string;

  // Cache token in app_settings
  const cacheValue: SRTokenCache = {
    token,
    expires_at: new Date(Date.now() + TOKEN_TTL_MS).toISOString(),
  };

  await supabase
    .from("app_settings")
    .upsert({
      key: "shiprocket_token",
      value: cacheValue,
      description: "Cached Shiprocket API token (auto-managed)",
    }, { onConflict: "key" });

  return token;
}

// Invalidate cached token (on 401, force re-login on next call)
async function invalidateToken(): Promise<void> {
  const supabase = getServiceClient();
  await supabase
    .from("app_settings")
    .delete()
    .eq("key", "shiprocket_token");
}

// Generic Shiprocket API fetch with auto-auth and retry on 401
export async function srFetch(
  path: string,
  options: RequestInit = {},
): Promise<Response> {
  const token = await getToken();

  const headers = new Headers(options.headers);
  headers.set("Content-Type", "application/json");
  headers.set("Authorization", `Bearer ${token}`);

  let res = await fetch(`${SR_BASE_URL}${path}`, {
    ...options,
    headers,
  });

  // Retry once on 401 (token may have been revoked server-side)
  if (res.status === 401) {
    await invalidateToken();
    const freshToken = await getToken();
    headers.set("Authorization", `Bearer ${freshToken}`);
    res = await fetch(`${SR_BASE_URL}${path}`, {
      ...options,
      headers,
    });
  }

  return res;
}

// Helper to parse srFetch response as JSON and throw on error
export async function srFetchJSON<T = Record<string, unknown>>(
  path: string,
  options: RequestInit = {},
): Promise<T> {
  const res = await srFetch(path, options);
  const body = await res.json();

  if (!res.ok) {
    const message = body?.message || body?.error || JSON.stringify(body);
    throw new Error(`Shiprocket API error (${res.status}) on ${path}: ${message}`);
  }

  return body as T;
}

// Map Shiprocket status codes to our order_status enum
// Reference: https://apidocs.shiprocket.in/#702f7ee3-48c4-4a8a-b66d-71ec105def6a
export function mapSRStatusToOrderStatus(
  statusCode: number,
): "out_for_delivery" | "delivered" | "delivery_failed" | null {
  switch (statusCode) {
    // Shipped / In Transit / Out for Delivery
    case 6:  // Shipped
    case 17: // Out for Delivery
    case 18: // In Transit
    case 38: // Reached at Destination Hub
    case 41: // Picked Up
    case 42: // Shipped - Shipment collected
      return "out_for_delivery";

    // Delivered
    case 7: // Delivered
      return "delivered";

    // RTO / Undelivered / Cancelled / Lost
    case 9:  // Undelivered (attempted but failed)
    case 10: // RTO Initiated
    case 14: // RTO Delivered (returned to seller)
    case 15: // RTO Acknowledged
    case 16: // Cancelled
    case 21: // Lost
      return "delivery_failed";

    default:
      // Unknown or intermediate status — don't change order
      return null;
  }
}
