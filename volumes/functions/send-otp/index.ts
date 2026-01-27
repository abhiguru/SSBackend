// Send OTP Edge Function
// POST /functions/v1/send-otp
// Body: { phone: "+91XXXXXXXXXX" }
//
// Flow:
// 1. Check IP rate limit (100/hour)
// 2. Check phone rate limit (40/hour, 20/day)
// 3. Check test_otp_records for fixed OTP
// 4. If production_mode=false, use '123456'
// 5. Otherwise, generate random OTP and send via MSG91

import { getServiceClient, generateOTP, hashOTP, validatePhone, normalizePhone } from "../_shared/auth.ts";
import { sendOTPWithConfig, getSMSConfig, SMSConfig } from "../_shared/sms.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { jsonResponse, errorResponse, handleError } from "../_shared/response.ts";

interface SendOTPRequest {
  phone: string;
}

interface RateLimitResult {
  allowed: boolean;
  hourly_remaining?: number;
  daily_remaining?: number;
  remaining?: number;
  error?: string;
  message?: string;
}

function getClientIP(req: Request): string | null {
  // Check various headers for client IP
  const forwarded = req.headers.get('x-forwarded-for');
  if (forwarded) {
    return forwarded.split(',')[0].trim();
  }

  const realIP = req.headers.get('x-real-ip');
  if (realIP) {
    return realIP;
  }

  // Cloudflare
  const cfIP = req.headers.get('cf-connecting-ip');
  if (cfIP) {
    return cfIP;
  }

  return null;
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
    const body: SendOTPRequest = await req.json();

    if (!body.phone) {
      return errorResponse('INVALID_PHONE', 'Phone number is required', 400);
    }

    // Normalize and validate phone
    const phone = normalizePhone(body.phone);

    if (!validatePhone(phone)) {
      return errorResponse('INVALID_PHONE', 'Invalid phone number format. Use +91XXXXXXXXXX', 400);
    }

    const supabase = getServiceClient();
    const clientIP = getClientIP(req);
    const userAgent = req.headers.get('user-agent') || null;

    // Step 1: Check IP rate limit (100/hour)
    if (clientIP) {
      const { data: ipRateResult, error: ipError } = await supabase.rpc('check_ip_rate_limit', {
        p_ip: clientIP
      });

      if (ipError) {
        console.error('IP rate limit check error:', ipError);
      } else if (ipRateResult && !ipRateResult.allowed) {
        return errorResponse(
          ipRateResult.error || 'IP_RATE_LIMITED',
          ipRateResult.message || 'Too many requests from this IP',
          429,
        );
      }
    }

    // Step 2: Check phone rate limit (40/hour, 20/day)
    const { data: phoneRateResult, error: phoneError } = await supabase.rpc('check_otp_rate_limit', {
      p_phone: phone
    });

    if (phoneError) {
      console.error('Phone rate limit check error:', phoneError);
    } else if (phoneRateResult && !phoneRateResult.allowed) {
      return errorResponse(
        phoneRateResult.error || 'RATE_LIMITED',
        phoneRateResult.message || 'Too many OTP requests',
        429,
      );
    }

    // Step 3: Check for test phone (fixed OTP)
    const { data: testOTP } = await supabase.rpc('get_test_otp', { p_phone: phone });

    // Step 4: Get SMS config
    const smsConfig = await getSMSConfig(supabase);

    // Determine OTP value and delivery status
    let otp: string;
    let deliveryStatus: string;
    let msg91RequestId: string | null = null;

    if (testOTP) {
      // Test phone - use fixed OTP
      otp = testOTP;
      deliveryStatus = 'test_phone';
      console.log(`[TEST_PHONE] Using fixed OTP for ${phone}`);
    } else if (!smsConfig.production_mode) {
      // Test mode - use hardcoded OTP
      otp = '123456';
      deliveryStatus = 'test_mode';
      console.log(`[TEST_MODE] Using test OTP 123456 for ${phone}`);
    } else {
      // Production mode - generate random OTP
      otp = generateOTP(6);
      deliveryStatus = 'pending';
    }

    const otpHash = await hashOTP(otp);

    // Get OTP expiry from settings
    const { data: settings } = await supabase
      .from('app_settings')
      .select('value')
      .eq('key', 'otp_expiry_seconds')
      .single();

    const otpExpiry = settings?.value ? parseInt(settings.value) : 300; // 5 minutes default
    const expiresAt = new Date(Date.now() + otpExpiry * 1000).toISOString();

    // Store OTP request with tracking fields
    const { error: insertError } = await supabase
      .from('otp_requests')
      .insert({
        phone,
        otp_hash: otpHash,
        expires_at: expiresAt,
        verified: false,
        attempts: 0,
        ip_address: clientIP,
        user_agent: userAgent,
        delivery_status: deliveryStatus,
      });

    if (insertError) {
      console.error('Failed to store OTP request:', insertError);
      return errorResponse('SERVER_ERROR', 'Failed to generate OTP', 500);
    }

    // Send OTP via SMS (only in production mode for non-test phones)
    if (deliveryStatus === 'pending') {
      const sendResult = await sendOTPWithConfig({ phone, otp }, smsConfig);

      // Update delivery status and request ID
      if (sendResult.success) {
        deliveryStatus = 'sent';
        msg91RequestId = sendResult.request_id || null;
      } else {
        deliveryStatus = 'failed';
        console.error('Failed to send OTP SMS:', sendResult.error);
      }

      // Update the OTP request with send result
      await supabase
        .from('otp_requests')
        .update({
          delivery_status: deliveryStatus,
          msg91_request_id: msg91RequestId,
        })
        .eq('phone', phone)
        .eq('otp_hash', otpHash);
    }

    return jsonResponse({
      success: true,
      message: 'OTP sent successfully',
      expires_in: otpExpiry,
      // Include rate limit info in response
      rate_limit: {
        hourly_remaining: phoneRateResult?.hourly_remaining,
        daily_remaining: phoneRateResult?.daily_remaining,
      },
    });
  } catch (error) {
    return handleError(error, 'Send OTP');
  }
}

// For standalone execution
Deno.serve(handler);
