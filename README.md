# Masala Spice Shop Backend

Self-hosted Supabase backend for the Masala Spice Shop React Native mobile app.

## Tech Stack

- **Database**: PostgreSQL 15+
- **API**: PostgREST + Deno Edge Functions
- **Gateway**: Kong
- **Auth**: Custom OTP + JWT (not Supabase Auth)
- **SMS**: MSG91
- **Push**: FCM

## Quick Start

```bash
# Clone the repository
git clone https://github.com/abhiguru/SSBackend.git
cd SSBackend

# Copy environment template and configure
cp .env.example .env
# Edit .env with your secrets

# Start the stack
docker compose up -d

# Run database migrations
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/01-schema.sql
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/02-auth-helpers.sql
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/03-rls-policies.sql
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/04-seed-data.sql
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/05-auth-enhancements.sql

# Grant required permissions
docker exec masala-db psql -U supabase_admin -d postgres -c "GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;"
docker exec masala-db psql -U supabase_admin -d postgres -c "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;"

# Verify services are running
docker compose ps
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| Kong API Gateway | 8100 | Main API endpoint |
| Studio Dashboard | 54424 | Admin UI |
| PostgreSQL | 5534 | Database (localhost only) |

## API Endpoints

### Authentication

```bash
# Send OTP
curl -X POST http://localhost:8100/functions/v1/send-otp \
  -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"phone": "+919876543210"}'

# Verify OTP
curl -X POST http://localhost:8100/functions/v1/verify-otp \
  -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"phone": "+919876543210", "otp": "123456"}'
```

### REST API (PostgREST)

```bash
# Get categories
curl http://localhost:8100/rest/v1/categories \
  -H "apikey: $ANON_KEY"

# Get products with weight options
curl "http://localhost:8100/rest/v1/products?select=*,weight_options(*)&is_available=eq.true" \
  -H "apikey: $ANON_KEY"
```

## Test Mode

By default, the system runs in **test mode**:

- OTP `123456` works for any phone number
- No SMS messages are sent
- Rate limits still apply (40/hour, 20/day per phone)

### Test Phone

The default test phone `+919876543210` with OTP `123456` works in ALL modes (test and production).

### Enable Production Mode

```bash
docker exec masala-db psql -U supabase_admin -d postgres -c "
  UPDATE sms_config SET
    production_mode = true,
    msg91_auth_key = 'your-msg91-key',
    msg91_template_id = 'your-template-id';
"
```

## Edge Functions

| Function | Auth Required | Description |
|----------|---------------|-------------|
| `send-otp` | No | Send OTP to phone number |
| `verify-otp` | No | Verify OTP, get JWT token |
| `checkout` | Yes | Create order from cart |
| `update-order-status` | Admin | Change order status |
| `verify-delivery-otp` | Delivery Staff | Complete delivery |
| `mark-delivery-failed` | Delivery Staff | Mark delivery failed |
| `reorder` | Yes | Recreate cart from past order |

## Database Schema

### Core Tables

- `users` - All user accounts (customer, admin, delivery_staff)
- `categories` - Product categories
- `products` - Spice products with bilingual names
- `weight_options` - Price variants (50g, 100g, 250g, 500g)
- `orders` - Customer orders with address snapshot
- `order_items` - Line items with product snapshot

### Auth Tables

- `otp_requests` - OTP verification records
- `sms_config` - SMS provider settings
- `otp_rate_limits` - Phone-based rate limits
- `ip_rate_limits` - IP-based rate limits
- `test_otp_records` - Test phones with fixed OTPs

## Rate Limits

| Limit | Value | Reset |
|-------|-------|-------|
| Phone (hourly) | 40 requests | Top of hour |
| Phone (daily) | 20 requests | Midnight |
| IP (hourly) | 100 requests | Top of hour |

## Development

```bash
# View logs
docker compose logs -f functions

# Restart edge functions after code changes
docker compose restart functions

# Connect to database
docker exec -it masala-db psql -U supabase_admin -d postgres

# Reload PostgREST schema cache
docker exec masala-db psql -U supabase_admin -d postgres -c "NOTIFY pgrst, 'reload schema';"
```

## Project Structure

```
backend/
├── docker-compose.yml
├── .env.example
├── ARCHITECTURE.md
├── CLAUDE.md
└── volumes/
    ├── api/kong.yml
    ├── db/init/
    │   ├── 01-schema.sql
    │   ├── 02-auth-helpers.sql
    │   ├── 03-rls-policies.sql
    │   ├── 04-seed-data.sql
    │   └── 05-auth-enhancements.sql
    └── functions/
        ├── _shared/
        ├── send-otp/
        ├── verify-otp/
        ├── checkout/
        └── ...
```

## License

Proprietary - All rights reserved
