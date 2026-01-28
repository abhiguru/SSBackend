// Porter Delivery API Client
// Supports mock, sandbox, and production modes

export interface Coords {
  lat: number;
  lng: number;
}

export interface CustomerDetails {
  name: string;
  phone: string;
}

export interface PickupDetails {
  lat: number;
  lng: number;
  address: string;
  name: string;
  phone: string;
}

export interface DropDetails {
  lat: number;
  lng: number;
  address: string;
  name: string;
  phone: string;
}

export interface QuoteRequest {
  pickup: Coords;
  drop: Coords;
}

export interface QuoteResponse {
  fare_paise: number;
  estimated_minutes: number;
  distance_km: number;
  vehicle_type?: string;
}

export interface CreateOrderRequest {
  order_id: string;
  order_number: string;
  pickup: PickupDetails;
  drop: DropDetails;
  customer: CustomerDetails;
  order_value_paise: number;
}

export interface CreateOrderResponse {
  porter_order_id: string;
  crn: string;
  tracking_url: string;
  estimated_pickup_time?: string;
  estimated_delivery_time?: string;
}

export interface CancelOrderResponse {
  success: boolean;
  message?: string;
}

// Porter status mapping to internal status
export const PORTER_STATUS_MAP: Record<string, string> = {
  'live': 'pending',
  'allocated': 'assigned',
  'reached_for_pickup': 'assigned',
  'picked_up': 'picked_up',
  'reached_for_drop': 'in_transit',
  'ended': 'delivered',
  'cancelled': 'cancelled',
};

// Get Porter environment
function getPorterEnv(): 'mock' | 'sandbox' | 'production' {
  const env = Deno.env.get('PORTER_ENV') ?? 'mock';
  if (env === 'production' || env === 'sandbox' || env === 'mock') {
    return env;
  }
  return 'mock';
}

// Get Porter API base URL
function getPorterBaseUrl(): string {
  const env = getPorterEnv();
  if (env === 'production') {
    return 'https://api.porter.in/v1';
  }
  return 'https://sandbox-api.porter.in/v1';
}

// Get Porter API key
function getPorterApiKey(): string {
  return Deno.env.get('PORTER_API_KEY') ?? '';
}

// Get Porter webhook secret
function getPorterWebhookSecret(): string {
  return Deno.env.get('PORTER_WEBHOOK_SECRET') ?? '';
}

// Check if mock mode
function isMockMode(): boolean {
  return getPorterEnv() === 'mock';
}

/**
 * Get a delivery quote from Porter
 */
export async function getQuote(request: QuoteRequest): Promise<QuoteResponse> {
  if (isMockMode()) {
    // Return simulated quote
    const distance = calculateDistance(
      request.pickup.lat, request.pickup.lng,
      request.drop.lat, request.drop.lng
    );
    const baseFare = 5000; // Rs 50 base
    const perKmRate = 1500; // Rs 15 per km
    const fare = Math.round(baseFare + (distance * perKmRate));
    const minutes = Math.round(20 + (distance * 5)); // ~5 min per km + 20 min buffer

    return {
      fare_paise: fare + Math.floor(Math.random() * 2000), // Add some randomness
      estimated_minutes: minutes + Math.floor(Math.random() * 10),
      distance_km: Math.round(distance * 10) / 10,
      vehicle_type: 'bike',
    };
  }

  const response = await fetch(`${getPorterBaseUrl()}/get_quote`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': getPorterApiKey(),
    },
    body: JSON.stringify({
      pickup_details: {
        lat: request.pickup.lat,
        lng: request.pickup.lng,
      },
      drop_details: {
        lat: request.drop.lat,
        lng: request.drop.lng,
      },
      customer: {
        name: 'Masala Spice Shop',
        mobile: { country_code: '+91', number: '9876543210' },
      },
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Porter quote failed: ${error}`);
  }

  const data = await response.json();

  // Porter returns fare in rupees, convert to paise
  return {
    fare_paise: Math.round((data.fare?.minor_amount || data.fare * 100)),
    estimated_minutes: data.estimated_pickup_time_in_minutes || 30,
    distance_km: data.distance || 5,
    vehicle_type: data.vehicle_type,
  };
}

/**
 * Create a delivery order with Porter
 */
export async function createOrder(request: CreateOrderRequest): Promise<CreateOrderResponse> {
  if (isMockMode()) {
    // Return simulated order creation
    const mockId = `MOCK-${Date.now()}-${Math.random().toString(36).substring(7)}`;
    const now = new Date();
    const pickupTime = new Date(now.getTime() + 30 * 60 * 1000); // 30 min from now
    const deliveryTime = new Date(now.getTime() + 60 * 60 * 1000); // 60 min from now

    return {
      porter_order_id: mockId,
      crn: `CRN-${mockId}`,
      tracking_url: `https://porter.in/track/${mockId}`,
      estimated_pickup_time: pickupTime.toISOString(),
      estimated_delivery_time: deliveryTime.toISOString(),
    };
  }

  const response = await fetch(`${getPorterBaseUrl()}/orders/create`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': getPorterApiKey(),
    },
    body: JSON.stringify({
      request_id: request.order_id,
      delivery_instructions: {
        instructions_list: [
          { type: 'text', description: `Order: ${request.order_number}` },
        ],
      },
      pickup_details: {
        lat: request.pickup.lat,
        lng: request.pickup.lng,
        address: {
          apartment_address: '',
          street_address1: request.pickup.address,
          street_address2: '',
          landmark: '',
          city: 'Ahmedabad',
          state: 'Gujarat',
          pincode: '',
          country: 'India',
          contact_details: {
            name: request.pickup.name,
            phone_number: request.pickup.phone.replace('+91', ''),
          },
        },
      },
      drop_details: {
        lat: request.drop.lat,
        lng: request.drop.lng,
        address: {
          apartment_address: '',
          street_address1: request.drop.address,
          street_address2: '',
          landmark: '',
          city: 'Ahmedabad',
          state: 'Gujarat',
          pincode: '',
          country: 'India',
          contact_details: {
            name: request.drop.name,
            phone_number: request.drop.phone.replace('+91', ''),
          },
        },
      },
      additional_comments: `Masala Spice Shop Order ${request.order_number}`,
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    throw new Error(`Porter order creation failed: ${error}`);
  }

  const data = await response.json();

  return {
    porter_order_id: data.order_id,
    crn: data.crn || data.order_id,
    tracking_url: data.tracking_url || `https://porter.in/track/${data.order_id}`,
    estimated_pickup_time: data.estimated_pickup_time,
    estimated_delivery_time: data.estimated_drop_time,
  };
}

/**
 * Cancel a Porter delivery order
 */
export async function cancelOrder(crn: string, reason?: string): Promise<CancelOrderResponse> {
  if (isMockMode()) {
    // Simulate cancellation
    return {
      success: true,
      message: 'Mock order cancelled successfully',
    };
  }

  const response = await fetch(`${getPorterBaseUrl()}/orders/${crn}/cancel`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': getPorterApiKey(),
    },
    body: JSON.stringify({
      reason: reason || 'Cancelled by merchant',
    }),
  });

  if (!response.ok) {
    const error = await response.text();
    return {
      success: false,
      message: `Porter cancellation failed: ${error}`,
    };
  }

  return {
    success: true,
    message: 'Order cancelled successfully',
  };
}

/**
 * Get order status from Porter
 */
export async function getOrderStatus(porterOrderId: string): Promise<{
  status: string;
  driver_name?: string;
  driver_phone?: string;
  vehicle_number?: string;
}> {
  if (isMockMode()) {
    return {
      status: 'live',
      driver_name: 'Mock Driver',
      driver_phone: '+919876543210',
      vehicle_number: 'GJ01AB1234',
    };
  }

  const response = await fetch(`${getPorterBaseUrl()}/orders/${porterOrderId}`, {
    method: 'GET',
    headers: {
      'x-api-key': getPorterApiKey(),
    },
  });

  if (!response.ok) {
    throw new Error(`Failed to get Porter order status: ${await response.text()}`);
  }

  const data = await response.json();

  return {
    status: data.status,
    driver_name: data.partner_info?.name,
    driver_phone: data.partner_info?.mobile,
    vehicle_number: data.partner_info?.vehicle_number,
  };
}

/**
 * Verify Porter webhook signature
 */
export function verifyWebhookSignature(payload: string, signature: string): boolean {
  const secret = getPorterWebhookSecret();

  if (!secret) {
    console.warn('PORTER_WEBHOOK_SECRET not configured, skipping signature verification');
    return true; // Allow in development
  }

  // Porter uses HMAC-SHA256 for webhook signatures
  // The signature header is typically 'x-porter-signature' or similar
  // For now, we'll do a simple comparison (adjust based on Porter's actual format)
  try {
    const encoder = new TextEncoder();
    const key = encoder.encode(secret);
    const data = encoder.encode(payload);

    // In production, use crypto.subtle.verify with the actual algorithm Porter uses
    // For now, this is a placeholder
    return signature === 'valid'; // Replace with actual verification
  } catch (error) {
    console.error('Webhook signature verification failed:', error);
    return false;
  }
}

/**
 * Calculate distance between two coordinates (Haversine formula)
 */
function calculateDistance(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371; // Earth's radius in km
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function toRad(deg: number): number {
  return deg * (Math.PI / 180);
}

/**
 * Parse Porter webhook event
 */
export interface PorterWebhookEvent {
  order_id: string;
  event_type: string;
  status?: string;
  partner_info?: {
    name?: string;
    mobile?: string;
    vehicle_number?: string;
  };
  actual_pickup_time?: string;
  actual_drop_time?: string;
  fare?: number;
}

export function parseWebhookEvent(payload: unknown): PorterWebhookEvent {
  const data = payload as Record<string, unknown>;

  return {
    order_id: String(data.order_id || data.request_id || ''),
    event_type: String(data.event_type || data.status || 'unknown'),
    status: data.status as string | undefined,
    partner_info: data.partner_info as PorterWebhookEvent['partner_info'],
    actual_pickup_time: data.actual_pickup_time as string | undefined,
    actual_drop_time: data.actual_drop_time as string | undefined,
    fare: data.fare as number | undefined,
  };
}
