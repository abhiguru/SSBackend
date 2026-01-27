// Verify OTP Edge Function
// POST /functions/v1/verify-otp
// Body: { phone: "+91XXXXXXXXXX", otp: "123456", name?: "User Name" }
//
// Flow:
// 1. Check test_otp_records for fixed OTP (works in ALL modes)
// 2. If production_mode=false, accept '123456' for any phone
// 3. Otherwise, verify against stored OTP hash

import { getServiceClient, hashOTP, validatePhone, normalizePhone, signJWT } from "../_shared/auth.ts";
import { getSMSConfig } from "../_shared/sms.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

interface VerifyOTPRequest {
  phone: string;
  otp: string;
  name?: string;
}

interface VerifyOTPResponse {
  success: boolean;
  access_token?: string;
  refresh_token?: string;
  user?: {
    id: string;
    phone: string;
    name: string | null;
    role: string;
    language: string;
  };
  is_new_user?: boolean;
  message?: string;
  error?: string;
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
    const body: VerifyOTPRequest = await req.json();

    if (!body.phone || !body.otp) {
      return errorResponse('INVALID_INPUT', 'Phone and OTP are required', 400);
    }

    // Normalize and validate phone
    const phone = normalizePhone(body.phone);

    if (!validatePhone(phone)) {
      return errorResponse('INVALID_PHONE', 'Invalid phone number format', 400);
    }

    // Validate OTP format (6 digits)
    if (!/^\d{6}$/.test(body.otp)) {
      return errorResponse('INVALID_OTP', 'OTP must be 6 digits', 400);
    }

    const supabase = getServiceClient();

    // Step 1: Check for test phone with fixed OTP (works in ALL modes)
    const { data: testOTP } = await supabase.rpc('get_test_otp', { p_phone: phone });
    let isTestVerification = false;

    if (testOTP && body.otp === testOTP) {
      // Test phone with correct fixed OTP
      isTestVerification = true;
      console.log(`[TEST_PHONE] Verified fixed OTP for ${phone}`);
    }

    // Step 2: Check SMS config for production mode
    const smsConfig = await getSMSConfig(supabase);

    // In test mode (production_mode=false), accept '123456' for any phone
    if (!isTestVerification && !smsConfig.production_mode && body.otp === '123456') {
      isTestVerification = true;
      console.log(`[TEST_MODE] Verified test OTP 123456 for ${phone}`);
    }

    // Step 3: If not a test verification, verify against stored OTP
    if (!isTestVerification) {
      // Get max attempts from settings
      const { data: settings } = await supabase
        .from('app_settings')
        .select('value')
        .eq('key', 'max_otp_attempts')
        .single();

      const maxAttempts = settings?.value ? parseInt(settings.value) : 3;

      // Find valid OTP request
      const { data: otpRequest, error: otpError } = await supabase
        .from('otp_requests')
        .select('*')
        .eq('phone', phone)
        .eq('verified', false)
        .gt('expires_at', new Date().toISOString())
        .lt('attempts', maxAttempts)
        .order('created_at', { ascending: false })
        .limit(1)
        .single();

      if (otpError || !otpRequest) {
        return errorResponse('OTP_EXPIRED', 'OTP has expired or too many attempts. Please request a new one.', 400);
      }

      // Hash the provided OTP and compare
      const otpHash = await hashOTP(body.otp);

      if (otpHash !== otpRequest.otp_hash) {
        // Increment attempts
        await supabase
          .from('otp_requests')
          .update({ attempts: otpRequest.attempts + 1 })
          .eq('id', otpRequest.id);

        const remainingAttempts = maxAttempts - otpRequest.attempts - 1;

        return errorResponse(
          'INVALID_OTP',
          remainingAttempts > 0
            ? `Invalid OTP. ${remainingAttempts} attempt(s) remaining.`
            : 'Invalid OTP. Please request a new one.',
          400,
        );
      }

      // Mark OTP as verified
      await supabase
        .from('otp_requests')
        .update({ verified: true })
        .eq('id', otpRequest.id);
    } else {
      // For test verifications, mark any pending OTP requests as verified
      await supabase
        .from('otp_requests')
        .update({ verified: true })
        .eq('phone', phone)
        .eq('verified', false);
    }

    // Find or create user
    let { data: user, error: userError } = await supabase
      .from('users')
      .select('*')
      .eq('phone', phone)
      .single();

    let isNewUser = false;

    if (userError || !user) {
      // Create new user
      isNewUser = true;
      const { data: newUser, error: createError } = await supabase
        .from('users')
        .insert({
          phone,
          name: body.name || null,
          role: 'customer',
          is_active: true,
        })
        .select()
        .single();

      if (createError || !newUser) {
        console.error('Failed to create user:', createError);
        return errorResponse('SERVER_ERROR', 'Failed to create user', 500);
      }

      user = newUser;
    } else if (!user.is_active) {
      return errorResponse('ACCOUNT_DEACTIVATED', 'Your account has been deactivated', 403);
    }

    // Update user name if provided and different
    if (body.name && body.name !== user.name) {
      await supabase
        .from('users')
        .update({ name: body.name })
        .eq('id', user.id);
      user.name = body.name;
    }

    // Generate access token (1 hour)
    const accessToken = await signJWT({
      sub: user.id,
      phone: user.phone,
      user_role: user.role,
    }, 3600);

    // Generate refresh token (30 days)
    const refreshTokenValue = crypto.randomUUID() + crypto.randomUUID();
    const refreshTokenHash = await hashOTP(refreshTokenValue);
    const refreshExpiry = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();

    // Store refresh token
    await supabase
      .from('refresh_tokens')
      .insert({
        user_id: user.id,
        token_hash: refreshTokenHash,
        expires_at: refreshExpiry,
        revoked: false,
      });

    const response: VerifyOTPResponse = {
      success: true,
      access_token: accessToken,
      refresh_token: refreshTokenValue,
      user: {
        id: user.id,
        phone: user.phone,
        name: user.name,
        role: user.role,
        language: user.language || 'en',
      },
      is_new_user: isNewUser,
    };

    return jsonResponse(response);
  } catch (error) {
    return handleError(error, 'Verify OTP');
  }
}

// For standalone execution
Deno.serve(handler);
