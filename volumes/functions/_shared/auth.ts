// Shared authentication helpers for edge functions
// PERFORMANCE OPTIMIZED: Items 14, 15, 17 from performance audit

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

export interface JWTPayload {
  sub: string;      // user id
  phone: string;
  role: string;     // PostgreSQL role for PostgREST (always 'authenticated')
  user_role: 'customer' | 'admin' | 'delivery_staff'; // app-level role
  iat: number;
  exp: number;
}

export interface SignJWTInput {
  sub: string;
  phone: string;
  user_role: 'customer' | 'admin' | 'delivery_staff';
}

export interface AuthContext {
  userId: string;
  phone: string;
  role: 'customer' | 'admin' | 'delivery_staff';
}

// =============================================
// ITEM 14: Cache Supabase Client Instances
// =============================================
// Module-level singletons to avoid client creation overhead per request

let _serviceClient: SupabaseClient | null = null;
let _serviceClientUrl: string | null = null;
let _serviceClientKey: string | null = null;

// Create Supabase client with service role (CACHED)
export function getServiceClient(): SupabaseClient {
  const url = Deno.env.get('SUPABASE_URL') ?? 'http://kong:8000';
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  // Return cached client if URL and key haven't changed
  if (_serviceClient && _serviceClientUrl === url && _serviceClientKey === key) {
    return _serviceClient;
  }

  // Create and cache new client
  _serviceClient = createClient(url, key, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
  _serviceClientUrl = url;
  _serviceClientKey = key;

  return _serviceClient;
}

// Create Supabase client with user's JWT (NOT cached - token-specific)
export function getUserClient(authHeader: string): SupabaseClient {
  const token = authHeader.replace('Bearer ', '');
  return createClient(
    Deno.env.get('SUPABASE_URL') ?? 'http://kong:8000',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    {
      global: {
        headers: { Authorization: `Bearer ${token}` },
      },
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    }
  );
}

// =============================================
// ITEM 15: Cache Imported Crypto Keys
// =============================================
// Avoid expensive crypto.subtle.importKey per request

let _jwtVerifyKey: CryptoKey | null = null;
let _jwtVerifyKeySecret: string | null = null;

let _jwtSignKey: CryptoKey | null = null;
let _jwtSignKeySecret: string | null = null;

let _otpHmacKey: CryptoKey | null = null;
let _otpHmacKeySecret: string | null = null;

async function getJWTVerifyKey(secret: string): Promise<CryptoKey> {
  if (_jwtVerifyKey && _jwtVerifyKeySecret === secret) {
    return _jwtVerifyKey;
  }
  const encoder = new TextEncoder();
  _jwtVerifyKey = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['verify']
  );
  _jwtVerifyKeySecret = secret;
  return _jwtVerifyKey;
}

async function getJWTSignKey(secret: string): Promise<CryptoKey> {
  if (_jwtSignKey && _jwtSignKeySecret === secret) {
    return _jwtSignKey;
  }
  const encoder = new TextEncoder();
  _jwtSignKey = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  _jwtSignKeySecret = secret;
  return _jwtSignKey;
}

async function getOTPHmacKey(secret: string): Promise<CryptoKey> {
  if (_otpHmacKey && _otpHmacKeySecret === secret) {
    return _otpHmacKey;
  }
  const encoder = new TextEncoder();
  _otpHmacKey = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  _otpHmacKeySecret = secret;
  return _otpHmacKey;
}

// Verify JWT and extract claims (OPTIMIZED with cached key)
export async function verifyJWT(token: string): Promise<JWTPayload | null> {
  try {
    const secret = Deno.env.get('JWT_SECRET');
    if (!secret) {
      console.error('JWT_SECRET not configured');
      return null;
    }

    // Decode JWT (base64url)
    const parts = token.split('.');
    if (parts.length !== 3) return null;

    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));

    // Check expiration
    if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) {
      return null;
    }

    // Verify signature using cached key
    const key = await getJWTVerifyKey(secret);
    const encoder = new TextEncoder();

    const signatureBytes = Uint8Array.from(
      atob(parts[2].replace(/-/g, '+').replace(/_/g, '/')),
      c => c.charCodeAt(0)
    );

    const dataBytes = encoder.encode(`${parts[0]}.${parts[1]}`);

    const valid = await crypto.subtle.verify('HMAC', key, signatureBytes, dataBytes);

    if (!valid) return null;

    return payload as JWTPayload;
  } catch (error) {
    console.error('JWT verification error:', error);
    return null;
  }
}

// Sign JWT (OPTIMIZED with cached key)
export async function signJWT(payload: SignJWTInput, expiresIn = 3600): Promise<string> {
  const secret = Deno.env.get('JWT_SECRET');
  if (!secret) throw new Error('JWT_SECRET not configured');

  const header = { alg: 'HS256', typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);

  const fullPayload: JWTPayload = {
    sub: payload.sub,
    phone: payload.phone,
    role: 'authenticated',        // PostgreSQL role for PostgREST SET ROLE
    user_role: payload.user_role,  // app-level role for RLS policies
    iat: now,
    exp: now + expiresIn,
  };

  const encoder = new TextEncoder();

  // Base64URL encode
  const base64url = (data: string) =>
    btoa(data).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

  const headerB64 = base64url(JSON.stringify(header));
  const payloadB64 = base64url(JSON.stringify(fullPayload));

  // Use cached key
  const key = await getJWTSignKey(secret);

  const signatureBytes = await crypto.subtle.sign(
    'HMAC',
    key,
    encoder.encode(`${headerB64}.${payloadB64}`)
  );

  const signature = base64url(String.fromCharCode(...new Uint8Array(signatureBytes)));

  return `${headerB64}.${payloadB64}.${signature}`;
}

// =============================================
// ITEM 17: Optimized requireAuth
// =============================================
// Option: Skip DB round-trip for non-sensitive operations
// The is_active check now uses a simple, fast query

// Require authentication - returns AuthContext or throws
export async function requireAuth(req: Request): Promise<AuthContext> {
  const authHeader = req.headers.get('Authorization');

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new AuthError('Missing or invalid Authorization header', 401);
  }

  const token = authHeader.replace('Bearer ', '');
  const payload = await verifyJWT(token);

  if (!payload) {
    throw new AuthError('Invalid or expired token', 401);
  }

  // Verify user is still active (uses indexed lookup)
  const supabase = getServiceClient();
  const { data: user, error } = await supabase
    .from('users')
    .select('is_active')
    .eq('id', payload.sub)
    .single();

  if (error || !user?.is_active) {
    throw new AuthError('User account is deactivated', 403);
  }

  return {
    userId: payload.sub,
    phone: payload.phone,
    role: payload.user_role,
  };
}

// Light auth check - JWT only, no DB round-trip
// Use for non-sensitive read operations where slight staleness is OK
export async function requireAuthLight(req: Request): Promise<AuthContext> {
  const authHeader = req.headers.get('Authorization');

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new AuthError('Missing or invalid Authorization header', 401);
  }

  const token = authHeader.replace('Bearer ', '');
  const payload = await verifyJWT(token);

  if (!payload) {
    throw new AuthError('Invalid or expired token', 401);
  }

  return {
    userId: payload.sub,
    phone: payload.phone,
    role: payload.user_role,
  };
}

// Require admin role
export async function requireAdmin(req: Request): Promise<AuthContext> {
  const auth = await requireAuth(req);

  if (auth.role !== 'admin') {
    throw new AuthError('Admin access required', 403);
  }

  return auth;
}

// Require delivery staff role
export async function requireDeliveryStaff(req: Request): Promise<AuthContext> {
  const auth = await requireAuth(req);

  if (auth.role !== 'delivery_staff' && auth.role !== 'admin') {
    throw new AuthError('Delivery staff access required', 403);
  }

  return auth;
}

// Custom auth error class
export class AuthError extends Error {
  status: number;

  constructor(message: string, status = 401) {
    super(message);
    this.name = 'AuthError';
    this.status = status;
  }
}

// Hash OTP for storage (OPTIMIZED with cached key)
export async function hashOTP(otp: string): Promise<string> {
  const secret = Deno.env.get('OTP_SECRET') ?? '';
  const encoder = new TextEncoder();

  const key = await getOTPHmacKey(secret);

  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(otp));

  return Array.from(new Uint8Array(signature))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

// Generate random OTP
export function generateOTP(length = 6): string {
  const digits = '0123456789';
  let otp = '';
  const randomValues = new Uint32Array(length);
  crypto.getRandomValues(randomValues);

  for (let i = 0; i < length; i++) {
    otp += digits[randomValues[i] % 10];
  }

  return otp;
}

// Generate 4-digit delivery OTP
export function generateDeliveryOTP(): string {
  return generateOTP(4);
}

// Validate Indian phone number
export function validatePhone(phone: string): boolean {
  // Format: +91XXXXXXXXXX (10 digits starting with 6-9)
  const phoneRegex = /^\+91[6-9]\d{9}$/;
  return phoneRegex.test(phone);
}

// Normalize phone number
export function normalizePhone(phone: string): string {
  // Remove spaces and dashes
  let normalized = phone.replace(/[\s-]/g, '');

  // Add +91 if not present
  if (normalized.startsWith('91') && normalized.length === 12) {
    normalized = '+' + normalized;
  } else if (normalized.length === 10 && /^[6-9]/.test(normalized)) {
    normalized = '+91' + normalized;
  }

  return normalized;
}
