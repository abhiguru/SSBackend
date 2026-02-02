// Sample Shiprocket API Implementation
// This file demonstrates common integration patterns

import axios, { AxiosInstance } from 'axios';

// ============================================================================
// CONFIGURATION
// ============================================================================

const SHIPROCKET_BASE_URL = 'https://apiv2.shiprocket.in/v1/external';

interface ShiprocketConfig {
  email: string;
  password: string;
}

// ============================================================================
// SHIPROCKET CLIENT CLASS
// ============================================================================

class ShiprocketClient {
  private config: ShiprocketConfig;
  private token: string | null = null;
  private tokenExpiry: Date | null = null;
  private client: AxiosInstance;

  constructor(config: ShiprocketConfig) {
    this.config = config;
    this.client = axios.create({
      baseURL: SHIPROCKET_BASE_URL,
      headers: {
        'Content-Type': 'application/json',
      },
    });
  }

  // ==========================================================================
  // AUTHENTICATION
  // ==========================================================================

  async authenticate(): Promise<string> {
    try {
      const response = await this.client.post('/auth/login', {
        email: this.config.email,
        password: this.config.password,
      });

      this.token = response.data.token;
      // JWT tokens typically expire in 24 hours
      this.tokenExpiry = new Date(Date.now() + 24 * 60 * 60 * 1000);

      return this.token;
    } catch (error) {
      throw new Error(`Authentication failed: ${error.message}`);
    }
  }

  async ensureAuthenticated(): Promise<void> {
    if (!this.token || !this.tokenExpiry || this.tokenExpiry < new Date()) {
      await this.authenticate();
    }
  }

  private getAuthHeaders() {
    return {
      Authorization: `Bearer ${this.token}`,
    };
  }

  // ==========================================================================
  // ORDER MANAGEMENT
  // ==========================================================================

  async createOrder(orderData: any): Promise<any> {
    await this.ensureAuthenticated();

    try {
      const response = await this.client.post(
        '/orders/create/adhoc',
        orderData,
        { headers: this.getAuthHeaders() }
      );

      return response.data;
    } catch (error) {
      throw new Error(`Order creation failed: ${error.message}`);
    }
  }

  async updateOrder(orderId: number, updateData: any): Promise<any> {
    await this.ensureAuthenticated();

    try {
      const response = await this.client.post(
        '/orders/update/adhoc',
        { id: orderId, ...updateData },
        { headers: this.getAuthHeaders() }
      );

      return response.data;
    } catch (error) {
      throw new Error(`Order update failed: ${error.message}`);
    }
  }

  async cancelOrder(orderIds: number[]): Promise<any> {
    await this.ensureAuthenticated();

    try {
      const response = await this.client.post(
        '/orders/cancel',
        { ids: orderIds },
        { headers: this.getAuthHeaders() }
      );

      return response.data;
    } catch (error) {
      throw new Error(`Order cancellation failed: ${error.message}`);
    }
  }

  // ==========================================================================
  // COURIER & SHIPMENT
  // ==========================================================================

  async checkServiceability(params: {
    pickup_postcode: string;
    delivery_postcode: string;
    cod: 0 | 1;
    weight: number;
  }): Promise<any> {
    await this.ensureAuthenticated();

    try {
      const response = await this.client.get('/courier/serviceability', {
        params,
        headers: this.getAuthHeaders(),
      });

      return response.data;
    } catch (error) {
      throw new Error(`Serviceability check failed: ${error.message}`);
    }
  }

  async assignAWB(shipmentId: number, courierId: number): Promise<any> {
    await this.ensureAuthenticated();

    try {
      const response = await this.client.post(
        '/courier/assign/awb',
        {
          shipment_id: shipmentId,
          courier_id: courierId,
        },
        { headers: this.getAuthHeaders() }
      );

      return response.data;
    } catch (error) {
      throw new Error(`AWB assignment failed: ${error.message}`);
    }
  }

  async generatePickup(shipmentIds: number[]): Promise<any> {
    await this.ensureAuthenticated();

    try {
      const response = await this.client.post(
        '/courier/generate/pickup',
        { shipment_id: shipmentIds },
        { headers: this.getAuthHeaders() }
      );

      return response.data;
    } catch (error) {
      throw new Error(`Pickup generation failed: ${error.message}`);
    }
  }

  async generateLabel(shipmentIds: number[]): Promise<any> {
    await this.ensureAuthenticated();

    try {
      const response = await this.client.post(
        '/courier/generate/label',
        { shipment_id: shipmentIds },
        { headers: this.getAuthHeaders() }
      );

      return response.data;
    } catch (error) {
      throw new Error(`Label generation failed: ${error.message}`);
    }
  }

  // ==========================================================================
  // TRACKING
  // ==========================================================================

  async trackShipment(shipmentId: number): Promise<any> {
    await this.ensureAuthenticated();

    try {
      const response = await this.client.get(
        `/courier/track/shipment/${shipmentId}`,
        { headers: this.getAuthHeaders() }
      );

      return response.data;
    } catch (error) {
      throw new Error(`Shipment tracking failed: ${error.message}`);
    }
  }

  async trackByAWB(awbCode: string): Promise<any> {
    await this.ensureAuthenticated();

    try {
      const response = await this.client.get(`/courier/track/awb/${awbCode}`, {
        headers: this.getAuthHeaders(),
      });

      return response.data;
    } catch (error) {
      throw new Error(`AWB tracking failed: ${error.message}`);
    }
  }
}

// ============================================================================
// EXAMPLE USAGE
// ============================================================================

async function example() {
  // Initialize client
  const client = new ShiprocketClient({
    email: 'your-api-user@example.com',
    password: 'your-password',
  });

  try {
    // 1. Create an order
    const order = await client.createOrder({
      order_id: 'ORDER-12345',
      order_date: '2024-01-15 10:30',
      pickup_location: 'Primary',
      billing_customer_name: 'John Doe',
      billing_last_name: 'Doe',
      billing_address: '123 Main Street',
      billing_city: 'Mumbai',
      billing_pincode: '400001',
      billing_state: 'Maharashtra',
      billing_country: 'India',
      billing_email: 'john@example.com',
      billing_phone: '9876543210',
      shipping_is_billing: true,
      order_items: [
        {
          name: 'Premium Widget',
          sku: 'WDG-001',
          units: 2,
          selling_price: 500,
          discount: 0,
          tax: 0,
        },
      ],
      payment_method: 'Prepaid',
      sub_total: 1000,
      length: 15,
      breadth: 10,
      height: 8,
      weight: 0.5,
    });

    console.log('Order created:', order.order_id);
    const shiprocketOrderId = order.order_id;
    const shipmentId = order.shipment_id;

    // 2. Check courier serviceability
    const serviceability = await client.checkServiceability({
      pickup_postcode: '400001',
      delivery_postcode: '110001',
      cod: 0,
      weight: 0.5,
    });

    console.log('Available couriers:', serviceability.data.available_courier_companies.length);

    // 3. Select courier and assign AWB
    const bestCourier = serviceability.data.available_courier_companies[0];
    const awbResult = await client.assignAWB(
      shipmentId,
      bestCourier.courier_company_id
    );

    console.log('AWB assigned:', awbResult.response.data.awb_code);

    // 4. Generate pickup
    const pickup = await client.generatePickup([shipmentId]);
    console.log('Pickup scheduled:', pickup.response.pickup_scheduled_date);

    // 5. Generate label
    const label = await client.generateLabel([shipmentId]);
    console.log('Label URL:', label.response.label_url);

    // 6. Track shipment
    const tracking = await client.trackShipment(shipmentId);
    console.log('Current status:', tracking.tracking_data.shipment_status);

  } catch (error) {
    console.error('Error:', error.message);
  }
}

// ============================================================================
// WEBHOOK HANDLER EXAMPLE (Express.js)
// ============================================================================

/*
import express from 'express';

const app = express();
app.use(express.json());

app.post('/webhook/shiprocket', (req, res) => {
  // Verify security token
  const securityToken = req.headers['anx-api-key'];
  
  if (securityToken !== process.env.SHIPROCKET_WEBHOOK_TOKEN) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const payload = req.body;
  
  console.log('Webhook received:', {
    order_id: payload.order_id,
    shipment_id: payload.shipment_id,
    awb: payload.awb,
    status: payload.current_status,
  });

  // Process the webhook
  // - Update database
  // - Send notifications to customers
  // - Trigger internal workflows

  // Must return 200
  res.status(200).json({ success: true });
});

app.listen(3000, () => {
  console.log('Webhook server running on port 3000');
});
*/

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

function formatOrderDate(date: Date): string {
  // Format: YYYY-MM-DD HH:MM
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  const hours = String(date.getHours()).padStart(2, '0');
  const minutes = String(date.getMinutes()).padStart(2, '0');

  return `${year}-${month}-${day} ${hours}:${minutes}`;
}

function convertGramsToKg(grams: number): number {
  return grams / 1000;
}

function validatePincode(pincode: string): boolean {
  return /^\d{6}$/.test(pincode);
}

function validatePhone(phone: string): boolean {
  return /^\d{10}$/.test(phone);
}

export { ShiprocketClient, formatOrderDate, convertGramsToKg, validatePincode, validatePhone };
