# Shiprocket API Quick Reference

## Base Information

**Base URL:** `https://apiv2.shiprocket.in/v1/external`

**Authentication:** Bearer Token (JWT)

**Content-Type:** `application/json`

**Architecture:** REST API

---

## Authentication

### Login (Get Token)
```
POST /auth/login

Body:
{
  "email": "your-api-user@example.com",
  "password": "your-password"
}

Response:
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

### Logout
```
POST /auth/logout

Headers:
Authorization: Bearer <token>
```

**Note:** Store the token and use it in all subsequent API calls in the Authorization header.

---

## Order Management

### Create Custom Order (Quick Order)
```
POST /orders/create/adhoc

Headers:
Authorization: Bearer <token>
Content-Type: application/json

Body:
{
  "order_id": "your-reference-id",
  "order_date": "2024-01-15 10:30",
  "pickup_location": "Primary",
  "channel_id": "",
  "comment": "Order notes",
  "billing_customer_name": "John Doe",
  "billing_last_name": "Doe",
  "billing_address": "123 Main St",
  "billing_city": "Mumbai",
  "billing_pincode": "400001",
  "billing_state": "Maharashtra",
  "billing_country": "India",
  "billing_email": "john@example.com",
  "billing_phone": "9876543210",
  "shipping_is_billing": true,
  "order_items": [
    {
      "name": "Product Name",
      "sku": "PROD123",
      "units": 1,
      "selling_price": "500",
      "discount": "0",
      "tax": "0",
      "hsn": "12345"
    }
  ],
  "payment_method": "Prepaid",
  "shipping_charges": 0,
  "giftwrap_charges": 0,
  "transaction_charges": 0,
  "total_discount": 0,
  "sub_total": 500,
  "length": 10,
  "breadth": 10,
  "height": 10,
  "weight": 0.5
}

Response:
{
  "order_id": <Shiprocket Order ID>,
  "shipment_id": <Shipment ID>,
  "status": "NEW",
  "status_code": 1,
  "onboarding_completed_now": 0,
  "awb_code": null,
  "courier_company_id": null,
  "courier_name": null
}
```

**Important:** The `order_id` you provide is YOUR reference. The response contains the **Shiprocket Order ID** which you must use for all future API calls.

### Create Order (With Product Master)
```
POST /orders/create

Similar to adhoc but stores product in master catalog
```

### Update Order
```
POST /orders/update/adhoc

Include the Shiprocket order_id and updated fields
```

### Cancel Order
```
POST /orders/cancel

Body:
{
  "ids": [<shiprocket_order_id>]
}
```

---

## Courier & Shipment

### Get Courier Serviceability
```
GET /courier/serviceability?pickup_postcode=400001&delivery_postcode=110001&cod=0&weight=0.5

Check which couriers can deliver to a pincode
```

### Assign AWB (Air Waybill)
```
POST /courier/assign/awb

Body:
{
  "shipment_id": <shipment_id>,
  "courier_id": <courier_company_id>
}
```

### Generate Pickup
```
POST /courier/generate/pickup

Body:
{
  "shipment_id": [<shipment_id>]
}
```

### Generate Label
```
POST /courier/generate/label

Body:
{
  "shipment_id": [<shipment_id>]
}
```

### Generate Manifest
```
POST /manifest/generate

Body:
{
  "shipment_id": [<shipment_id>]
}
```

### Print Manifest
```
POST /manifest/print

Body:
{
  "order_ids": [<shiprocket_order_id>]
}
```

---

## Tracking

### Track Shipment
```
GET /courier/track/shipment/<shipment_id>

Returns tracking history and current status
```

### Track by AWB
```
GET /courier/track/awb/<awb_code>
```

---

## Webhooks

Configure webhooks at: **Settings → API → Webhooks**

Shiprocket will send POST requests to your callback URL when tracking events occur.

**Webhook Specs:**
- Method: POST
- Content-Type: application/json
- Response: Must return 200
- Security: Add `anx-api-key` header with your token

**Events:** Order created, Shipped, In transit, Delivered, RTO, etc.

---

## Common Response Codes

| Code | Meaning |
|------|---------|
| 200 | Success |
| 401 | Unauthorized (invalid/expired token) |
| 422 | Unprocessable Entity (validation error) |
| 404 | Not Found |
| 405 | Method Not Allowed |
| 429 | Rate Limit Exceeded |
| 500+ | Server Error |

---

## Important Notes

1. **Order ID vs Shiprocket Order ID:** Your `order_id` is different from Shiprocket's internal order ID. Always use Shiprocket's order ID for API operations.

2. **Weight:** Always in KG (use 0.5 for 500g)

3. **Dimensions:** Always in CM

4. **Pickup Location:** Must be pre-configured in your Shiprocket account

5. **Payment Method:** "Prepaid" or "COD"

6. **Token Expiry:** JWT tokens expire. Store expiry time and refresh before it expires.

7. **Rate Limits:** Respect the 429 response code. Implement exponential backoff.

---

## Typical Integration Flow

1. **Authenticate:** Get token via `/auth/login`
2. **Create Order:** Use `/orders/create/adhoc`
3. **Check Serviceability:** Use `/courier/serviceability`
4. **Assign AWB:** Use `/courier/assign/awb` with selected courier
5. **Generate Pickup:** Use `/courier/generate/pickup`
6. **Generate Label:** Use `/courier/generate/label`
7. **Track:** Use `/courier/track/shipment/<id>`

---

## Testing

Import the Postman collection using the "Run in Postman" button from the official docs.

**Warning:** API calls with valid credentials will affect real-time data in your account!

---

For complete API specification, refer to the full extracted documentation files.
