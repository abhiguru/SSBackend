// MSG91 SMS Helper
// Supports database-backed configuration with environment variable fallback

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

export interface SMSConfig {
  production_mode: boolean;
  provider: string;
  msg91_auth_key: string | null;
  msg91_template_id: string | null;
  msg91_sender_id: string;
  msg91_pe_id: string | null;
}

interface SendOTPOptions {
  phone: string;
  otp: string;
}

interface SendOTPResult {
  success: boolean;
  request_id?: string;
  error?: string;
}

interface SendSMSOptions {
  phone: string;
  message: string;
  templateId?: string;
  variables?: Record<string, string>;
}

interface MSG91Response {
  type: 'success' | 'error';
  message?: string;
  request_id?: string;
}

// Get SMS configuration from database with env fallback
export async function getSMSConfig(supabase: SupabaseClient): Promise<SMSConfig> {
  try {
    const { data, error } = await supabase.rpc('get_sms_config');

    if (error) {
      console.error('Failed to get SMS config from database:', error);
    }

    if (data) {
      // Use database config with env fallback for credentials
      return {
        production_mode: data.production_mode ?? false,
        provider: data.provider ?? 'msg91',
        msg91_auth_key: data.msg91_auth_key || Deno.env.get('MSG91_AUTH_KEY') || null,
        msg91_template_id: data.msg91_template_id || Deno.env.get('MSG91_OTP_TEMPLATE') || null,
        msg91_sender_id: data.msg91_sender_id || Deno.env.get('MSG91_SENDER_ID') || 'MSSHOP',
        msg91_pe_id: data.msg91_pe_id || null,
      };
    }
  } catch (err) {
    console.error('Error fetching SMS config:', err);
  }

  // Fallback to environment variables
  return {
    production_mode: Deno.env.get('SMS_PRODUCTION_MODE') === 'true',
    provider: 'msg91',
    msg91_auth_key: Deno.env.get('MSG91_AUTH_KEY') || null,
    msg91_template_id: Deno.env.get('MSG91_OTP_TEMPLATE') || null,
    msg91_sender_id: Deno.env.get('MSG91_SENDER_ID') || 'MSSHOP',
    msg91_pe_id: null,
  };
}

// Send OTP using provided SMS config
export async function sendOTPWithConfig(
  { phone, otp }: SendOTPOptions,
  config: SMSConfig
): Promise<SendOTPResult> {
  // Check if we have required credentials
  if (!config.msg91_auth_key || !config.msg91_template_id) {
    console.error('MSG91 credentials not configured');
    return { success: false, error: 'SMS credentials not configured' };
  }

  try {
    // Remove +91 prefix for MSG91
    const mobileNumber = phone.replace(/^\+91/, '');

    const response = await fetch('https://api.msg91.com/api/v5/otp', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'authkey': config.msg91_auth_key,
      },
      body: JSON.stringify({
        template_id: config.msg91_template_id,
        mobile: mobileNumber,
        otp: otp,
        otp_length: otp.length,
      }),
    });

    const result = await response.json() as MSG91Response;

    if (result.type === 'success') {
      console.log(`OTP sent successfully to ${phone}`);
      return { success: true, request_id: result.request_id };
    } else {
      console.error('MSG91 OTP error:', result.message);
      return { success: false, error: result.message };
    }
  } catch (error) {
    console.error('Failed to send OTP:', error);
    return { success: false, error: String(error) };
  }
}

// Legacy function - Send OTP via MSG91 OTP API (uses env variables)
export async function sendOTP({ phone, otp }: SendOTPOptions): Promise<boolean> {
  const authKey = Deno.env.get('MSG91_AUTH_KEY');
  const templateId = Deno.env.get('MSG91_OTP_TEMPLATE');

  if (!authKey || !templateId) {
    console.error('MSG91 credentials not configured');
    // In development, just log the OTP
    console.log(`[DEV] OTP for ${phone}: ${otp}`);
    return true;
  }

  try {
    // Remove +91 prefix for MSG91
    const mobileNumber = phone.replace(/^\+91/, '');

    const response = await fetch('https://api.msg91.com/api/v5/otp', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'authkey': authKey,
      },
      body: JSON.stringify({
        template_id: templateId,
        mobile: mobileNumber,
        otp: otp,
        otp_length: otp.length,
      }),
    });

    const result = await response.json() as MSG91Response;

    if (result.type === 'success') {
      console.log(`OTP sent successfully to ${phone}`);
      return true;
    } else {
      console.error('MSG91 OTP error:', result.message);
      return false;
    }
  } catch (error) {
    console.error('Failed to send OTP:', error);
    return false;
  }
}

// Send transactional SMS via MSG91 Flow API
export async function sendSMS({ phone, message, templateId, variables }: SendSMSOptions): Promise<boolean> {
  const authKey = Deno.env.get('MSG91_AUTH_KEY');
  const defaultTemplateId = Deno.env.get('MSG91_TEMPLATE');
  const senderId = Deno.env.get('MSG91_SENDER_ID') ?? 'MSSHOP';

  if (!authKey) {
    console.error('MSG91 auth key not configured');
    console.log(`[DEV] SMS to ${phone}: ${message}`);
    return true;
  }

  const template = templateId ?? defaultTemplateId;
  if (!template) {
    console.error('MSG91 template ID not configured');
    return false;
  }

  try {
    // Remove +91 prefix for MSG91
    const mobileNumber = phone.replace(/^\+91/, '');

    const response = await fetch('https://api.msg91.com/api/v5/flow/', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'authkey': authKey,
      },
      body: JSON.stringify({
        flow_id: template,
        sender: senderId,
        mobiles: `91${mobileNumber}`,
        ...variables,
      }),
    });

    const result = await response.json() as MSG91Response;

    if (result.type === 'success') {
      console.log(`SMS sent successfully to ${phone}`);
      return true;
    } else {
      console.error('MSG91 SMS error:', result.message);
      return false;
    }
  } catch (error) {
    console.error('Failed to send SMS:', error);
    return false;
  }
}

// Send transactional SMS using database config
export async function sendSMSWithConfig(
  { phone, message, templateId, variables }: SendSMSOptions,
  config: SMSConfig
): Promise<boolean> {
  const authKey = config.msg91_auth_key || Deno.env.get('MSG91_AUTH_KEY');
  const defaultTemplateId = Deno.env.get('MSG91_TEMPLATE');
  const senderId = config.msg91_sender_id || 'MSSHOP';

  if (!authKey) {
    console.error('MSG91 auth key not configured');
    console.log(`[DEV] SMS to ${phone}: ${message}`);
    return true;
  }

  const template = templateId ?? defaultTemplateId;
  if (!template) {
    console.error('MSG91 template ID not configured');
    return false;
  }

  try {
    // Remove +91 prefix for MSG91
    const mobileNumber = phone.replace(/^\+91/, '');

    const response = await fetch('https://api.msg91.com/api/v5/flow/', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'authkey': authKey,
      },
      body: JSON.stringify({
        flow_id: template,
        sender: senderId,
        mobiles: `91${mobileNumber}`,
        ...variables,
      }),
    });

    const result = await response.json() as MSG91Response;

    if (result.type === 'success') {
      console.log(`SMS sent successfully to ${phone}`);
      return true;
    } else {
      console.error('MSG91 SMS error:', result.message);
      return false;
    }
  } catch (error) {
    console.error('Failed to send SMS:', error);
    return false;
  }
}

// Send delivery OTP SMS
export async function sendDeliveryOTP(phone: string, orderNumber: string, otp: string): Promise<boolean> {
  const message = `Your delivery OTP for order ${orderNumber} is ${otp}. Share this with the delivery person.`;

  // Use sendSMS with delivery OTP template variables
  return sendSMS({
    phone,
    message,
    variables: {
      order_number: orderNumber,
      otp: otp,
    },
  });
}

// Send order confirmation SMS
export async function sendOrderConfirmation(phone: string, orderNumber: string): Promise<boolean> {
  const message = `Your order ${orderNumber} has been confirmed. We'll notify you when it's out for delivery.`;

  return sendSMS({
    phone,
    message,
    variables: {
      order_number: orderNumber,
    },
  });
}

// Send order status update SMS
export async function sendOrderStatusSMS(
  phone: string,
  orderNumber: string,
  status: string
): Promise<boolean> {
  let message: string;

  switch (status) {
    case 'confirmed':
      message = `Your order ${orderNumber} has been confirmed and is being prepared.`;
      break;
    case 'out_for_delivery':
      message = `Your order ${orderNumber} is out for delivery. You'll receive a delivery OTP shortly.`;
      break;
    case 'delivered':
      message = `Your order ${orderNumber} has been delivered. Thank you for shopping with Masala Spice Shop!`;
      break;
    case 'cancelled':
      message = `Your order ${orderNumber} has been cancelled. Please contact us for more information.`;
      break;
    case 'delivery_failed':
      message = `Delivery attempt for order ${orderNumber} was unsuccessful. We'll retry soon.`;
      break;
    default:
      message = `Your order ${orderNumber} status has been updated to ${status}.`;
  }

  return sendSMS({
    phone,
    message,
    variables: {
      order_number: orderNumber,
      status: status,
    },
  });
}
