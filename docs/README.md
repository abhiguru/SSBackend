# Shiprocket API Documentation for Claude Code

This folder contains organized Shiprocket API documentation extracted from the 101-page PDF and restructured for easy reference during coding.

## 📁 File Structure

```
shiprocket_docs/
├── README.md                    # This file
├── QUICK_REFERENCE.md          # ⭐ START HERE - Essential endpoints & flows
├── shiprocket-types.ts         # TypeScript type definitions
├── .clinerules                 # Claude Code rules & patterns
├── 1_authentication.txt        # Auth endpoints details
├── 2_orders.txt               # Order creation & management
├── 3_courier_shipment.txt     # Courier assignment & shipping
├── 4_tracking.txt             # Tracking endpoints
└── 5_webhooks.txt             # Webhook configuration
```

## 🚀 Quick Start

1. **Start with:** `QUICK_REFERENCE.md` - Contains all essential endpoints, request/response examples, and typical integration flow

2. **For TypeScript/JavaScript projects:** Use `shiprocket-types.ts` for type safety

3. **For detailed specs:** Reference the numbered `.txt` files for specific sections

4. **For Claude Code:** The `.clinerules` file helps Claude understand Shiprocket patterns automatically

## 📋 Common Integration Patterns

### Basic Flow
```
1. Authenticate (get token)
2. Create order
3. Check courier serviceability
4. Assign AWB
5. Generate pickup
6. Generate label
7. Track shipment
```

### Key Endpoints
- **Auth:** `/auth/login`
- **Create Order:** `/orders/create/adhoc`
- **Serviceability:** `/courier/serviceability`
- **Assign AWB:** `/courier/assign/awb`
- **Track:** `/courier/track/shipment/{id}`

## ⚠️ Important Notes

1. **Two Order IDs:**
   - Your `order_id` (your reference)
   - Shiprocket's `order_id` (returned in response)
   - Always use Shiprocket's ID for API operations

2. **Units:**
   - Weight: KG (use 0.5 for 500g)
   - Dimensions: CM

3. **Authentication:**
   - JWT tokens expire
   - Store token and refresh before expiry
   - Include in all requests: `Authorization: Bearer <token>`

4. **Testing:**
   - API calls with valid credentials affect REAL data
   - Be careful when testing

## 🔧 Using with Claude Code

### Option 1: Reference in Prompts
```
"Implement Shiprocket order creation using the specs in 
~/shiprocket_docs/QUICK_REFERENCE.md"
```

### Option 2: Copy to Project
Copy relevant files to your project's docs folder:
```bash
cp shiprocket_docs/QUICK_REFERENCE.md your-project/docs/
cp shiprocket_docs/shiprocket-types.ts your-project/src/types/
```

### Option 3: Use .clinerules
Copy `.clinerules` to your project root for automatic context:
```bash
cp shiprocket_docs/.clinerules your-project/
```

## 📖 Full Documentation Sections

### 1. Authentication (`1_authentication.txt`)
- Login/logout
- Token management
- JWT specifications

### 2. Orders (`2_orders.txt`)
- Create custom orders (adhoc)
- Create orders with product master
- Update orders
- Cancel orders
- Bulk import

### 3. Courier & Shipment (`3_courier_shipment.txt`)
- Check serviceability
- Get courier list
- Assign AWB
- Generate pickup
- Generate labels
- Print manifest

### 4. Tracking (`4_tracking.txt`)
- Track by shipment ID
- Track by AWB code
- Get tracking history
- Status updates

### 5. Webhooks (`5_webhooks.txt`)
- Configuration
- Payload structure
- Event types
- Security headers

## 💡 Tips for Claude Code

1. **For simple tasks:** Just reference `QUICK_REFERENCE.md`
   
2. **For complex implementations:** Reference multiple section files

3. **For type safety:** Import types from `shiprocket-types.ts`

4. **For validation:** Check `.clinerules` for required fields and formats

## 🔗 Official Resources

- **API Docs:** https://apidocs.shiprocket.in/
- **Support:** https://support.shiprocket.in/
- **Postman Collection:** Available via "Run in Postman" button

## 📝 Notes

- Original PDF: 101 pages
- Extracted text: ~119,000 characters
- Organized into 5 main sections + quick reference
- Includes TypeScript type definitions
- Ready for Claude Code integration

---

**Last Updated:** February 2026
**API Version:** v1/external
**Source:** Shiprocket_API.pdf
