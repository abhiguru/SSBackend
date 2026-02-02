// Shiprocket API Type Definitions
// Use these types when implementing Shiprocket integration

// ============================================================================
// AUTHENTICATION
// ============================================================================

export interface ShiprocketAuthRequest {
  email: string;
  password: string;
}

export interface ShiprocketAuthResponse {
  token: string;
  id: number;
  first_name: string;
  last_name: string;
  email: string;
  company_id: number;
}

// ============================================================================
// ORDER CREATION
// ============================================================================

export interface OrderItem {
  name: string;
  sku: string;
  units: number;
  selling_price: string | number;
  discount?: string | number;
  tax?: string | number;
  hsn?: string | number;
}

export interface CreateOrderRequest {
  order_id: string;                    // YOUR reference order ID
  order_date: string;                  // Format: "YYYY-MM-DD HH:MM"
  pickup_location: string;             // Must exist in your account
  channel_id?: string;
  comment?: string;
  
  // Billing address (required)
  billing_customer_name: string;
  billing_last_name?: string;
  billing_address: string;
  billing_address_2?: string;
  billing_city: string;
  billing_pincode: string;
  billing_state: string;
  billing_country: string;
  billing_email: string;
  billing_phone: string;
  
  // Shipping address (optional if same as billing)
  shipping_is_billing?: boolean;
  shipping_customer_name?: string;
  shipping_last_name?: string;
  shipping_address?: string;
  shipping_address_2?: string;
  shipping_city?: string;
  shipping_pincode?: string;
  shipping_state?: string;
  shipping_country?: string;
  shipping_email?: string;
  shipping_phone?: string;
  
  // Order items
  order_items: OrderItem[];
  
  // Payment & pricing
  payment_method: 'Prepaid' | 'COD';
  shipping_charges?: number;
  giftwrap_charges?: number;
  transaction_charges?: number;
  total_discount?: number;
  sub_total: number;
  
  // Package dimensions
  length: number;                      // in CM
  breadth: number;                     // in CM
  height: number;                      // in CM
  weight: number;                      // in KG
  
  // Optional fields
  reseller_name?: string;
  company_name?: string;
  ewaybill_no?: string;
  customer_gstin?: string;
  shipping_mode?: string;
  vendor_details?: any;
}

export interface CreateOrderResponse {
  order_id: number;                    // SHIPROCKET's internal order ID
  shipment_id: number;
  status: string;
  status_code: number;
  onboarding_completed_now: number;
  awb_code: string | null;
  courier_company_id: number | null;
  courier_name: string | null;
}

// ============================================================================
// COURIER & SERVICEABILITY
// ============================================================================

export interface CourierServiceabilityParams {
  pickup_postcode: string;
  delivery_postcode: string;
  cod: 0 | 1;                         // 0 for prepaid, 1 for COD
  weight: number;                     // in KG
  declared_value?: number;
}

export interface CourierServiceabilityResponse {
  data: {
    available_courier_companies: Array<{
      courier_company_id: number;
      courier_name: string;
      freight_charge: number;
      cod_charges: number;
      estimated_delivery_days: string;
      pickup_availability: string;
      rating: number;
      is_surface: boolean;
      is_custom_rate: boolean;
    }>;
  };
}

export interface AssignAWBRequest {
  shipment_id: number;
  courier_id: number;
}

export interface AssignAWBResponse {
  awb_assign_status: number;
  response: {
    data: {
      awb_code: string;
      courier_company_id: number;
      courier_name: string;
      shipment_id: number;
    };
  };
}

// ============================================================================
// PICKUP & LABEL GENERATION
// ============================================================================

export interface GeneratePickupRequest {
  shipment_id: number[];
}

export interface GeneratePickupResponse {
  pickup_status: number;
  response: {
    pickup_scheduled_date: string;
    pickup_token_number: string;
  };
}

export interface GenerateLabelRequest {
  shipment_id: number[];
}

export interface GenerateLabelResponse {
  label_created: number;
  response: {
    label_url: string;
    shipment_id: number;
  };
}

// ============================================================================
// TRACKING
// ============================================================================

export interface TrackingResponse {
  tracking_data: {
    track_status: number;
    shipment_status: string;
    shipment_track: Array<{
      id: number;
      awb_code: string;
      courier_company_id: number;
      shipment_id: number;
      order_id: number;
      pickup_date: string;
      delivered_date: string | null;
      weight: string;
      packages: number;
      current_status: string;
      delivered_to: string | null;
      destination: string;
      consignee_name: string;
      origin: string;
      courier_agent_details: string | null;
      edd: string | null;
    }>;
    shipment_track_activities: Array<{
      date: string;
      status: string;
      activity: string;
      location: string;
      sr_status?: string;
      sr_status_label?: string;
    }>;
  };
}

// ============================================================================
// WEBHOOKS
// ============================================================================

export interface WebhookPayload {
  order_id: number;
  shipment_id: number;
  awb: string;
  courier_name: string;
  current_status: string;
  status: string;
  delivered_date?: string;
  pickup_date?: string;
  scans?: Array<{
    date: string;
    activity: string;
    location: string;
    status: string;
  }>;
}

// ============================================================================
// ERROR RESPONSES
// ============================================================================

export interface ErrorResponse {
  message: string;
  errors?: Record<string, string[]>;
  status_code?: number;
}

// ============================================================================
// UTILITY TYPES
// ============================================================================

export interface ShiprocketConfig {
  baseUrl: string;
  email: string;
  password: string;
  token?: string;
  tokenExpiry?: Date;
}

export type PaymentMethod = 'Prepaid' | 'COD';
export type OrderStatus = 'NEW' | 'READY_TO_SHIP' | 'SHIPPED' | 'DELIVERED' | 'CANCELLED' | 'RTO';

// ============================================================================
// EXAMPLE USAGE
// ============================================================================

/*
// Example: Create an order
const orderRequest: CreateOrderRequest = {
  order_id: "ORDER-12345",
  order_date: "2024-01-15 10:30",
  pickup_location: "Primary",
  billing_customer_name: "John Doe",
  billing_address: "123 Main Street",
  billing_city: "Mumbai",
  billing_pincode: "400001",
  billing_state: "Maharashtra",
  billing_country: "India",
  billing_email: "john@example.com",
  billing_phone: "9876543210",
  shipping_is_billing: true,
  order_items: [
    {
      name: "Widget",
      sku: "WDG-001",
      units: 2,
      selling_price: 500,
      tax: 0,
      discount: 0
    }
  ],
  payment_method: "Prepaid",
  sub_total: 1000,
  length: 15,
  breadth: 10,
  height: 8,
  weight: 0.5
};

// Example: Check serviceability
const serviceability = await checkServiceability({
  pickup_postcode: "400001",
  delivery_postcode: "110001",
  cod: 0,
  weight: 0.5
});

// Example: Assign AWB
const awbResponse = await assignAWB({
  shipment_id: 12345,
  courier_id: 23
});
*/
