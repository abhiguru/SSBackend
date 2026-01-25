# Masala Spice Shop - Backend Architecture

## Overview

This backend powers the Masala Spice Shop React Native mobile app. It's built on a self-hosted Supabase stack with custom OTP authentication (not Supabase Auth).

---

## Quick Start

```bash
cd /home/gcswebserver/ws/SSMasala/backend

# Start the stack
docker compose up -d

# Run database migrations (required after first start or volume reset)
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/01-schema.sql
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/02-auth-helpers.sql
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/03-rls-policies.sql
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/04-seed-data.sql
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/05-auth-enhancements.sql

# Grant required permissions
docker exec masala-db psql -U supabase_admin -d postgres -c "ALTER ROLE supabase_storage_admin WITH SUPERUSER;"
docker exec masala-db psql -U supabase_admin -d postgres -c "CREATE SCHEMA IF NOT EXISTS _supavisor;"
docker exec masala-db psql -U supabase_admin -d postgres -c "GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;"
docker exec masala-db psql -U supabase_admin -d postgres -c "GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO service_role;"

# Restart storage and supavisor to pick up new permissions
docker compose restart storage supavisor

# Check status
docker compose ps
```

---

## Multi-Stack Server Configuration

**CRITICAL**: This server runs multiple Supabase stacks. Each stack must be completely isolated.

### GuruColdStorage Stack (DO NOT MODIFY)

| Property | Value |
|----------|-------|
| Location | `/home/gcswebserver/ws/GuruColdStorageSupabase/supabase/docker/` |
| Project Name | `supabase` |
| Network | `supabase_default` (172.20.0.0/24) |
| Container Prefix | `supabase-*` |

**Reserved Ports (GuruColdStorage)**:
- 8000, 8443 (Kong)
- 54323 (Studio)
- 5432, 5433 (PostgreSQL)
- 6543, 6544 (Supavisor)
- 4000, 4001 (Analytics/Admin)
- 3100, 6310, 9100, 9187, 8082, 9093, 9095, 3001 (Monitoring)

### Masala Stack

| Property | Value |
|----------|-------|
| Location | `/home/gcswebserver/ws/SSMasala/backend/` |
| Project Name | `masala` |
| Network | `masala_default` (172.21.0.0/24) |
| Container Prefix | `masala-*` |

---

## Service Ports

| Service | Internal Port | External Port | Binding | Description |
|---------|---------------|---------------|---------|-------------|
| Kong HTTP | 8000 | **8100** | 0.0.0.0 | API Gateway |
| Kong HTTPS | 8443 | **8543** | 0.0.0.0 | API Gateway (TLS) |
| PostgreSQL | 5432 | **5534** | 127.0.0.1 | Direct DB access |
| Supavisor Session | 5432 | **5535** | 127.0.0.1 | Connection pooler |
| Supavisor Transaction | 6543 | **6643** | 127.0.0.1 | Transaction pooler |
| Supavisor Admin | 4000 | **4101** | 127.0.0.1 | Pooler admin |
| Studio | 3000 | **54424** | 0.0.0.0 | Dashboard |
| Edge Functions | 9000 | (via Kong) | internal | Deno runtime |
| Storage | 5000 | (via Kong) | internal | File storage |
| PostgREST | 3000 | (via Kong) | internal | REST API |

---

## API Access

### Base URLs
- **API Gateway**: `http://localhost:8100`
- **Studio Dashboard**: `http://localhost:54424`

### API Key (Anonymous)
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzY5MzQxMDAwLCJleHAiOjE4OTM0NTYwMDB9.Aqgd7n3j-riUsqJ54DrU8FLgxtHx4K8vTp9Ij_h35nE
```

### Service Role Key (Keep Secret!)
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIiwiaXNzIjoic3VwYWJhc2UiLCJpYXQiOjE3NjkzNDEwMDAsImV4cCI6MTg5MzQ1NjAwMH0.L0z54vEiO4-NCiil4VvPD2HA3Z-_Wvt7e5axPvh7nns
```

### Example API Calls

```bash
# Get categories
curl http://localhost:8100/rest/v1/categories \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzY5MzQxMDAwLCJleHAiOjE4OTM0NTYwMDB9.Aqgd7n3j-riUsqJ54DrU8FLgxtHx4K8vTp9Ij_h35nE"

# Get products with weight options
curl "http://localhost:8100/rest/v1/products?select=*,weight_options(*)" \
  -H "apikey: ..."

# Send OTP
curl -X POST http://localhost:8100/functions/v1/send-otp \
  -H "apikey: ..." \
  -H "Content-Type: application/json" \
  -d '{"phone": "+919876543210"}'

# Check functions health
curl http://localhost:8100/functions/v1/health -H "apikey: ..."
```

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     Mobile App (React Native)                    │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Kong API Gateway (:8100)                      │
│  ┌──────────────┬──────────────┬──────────────┬───────────────┐ │
│  │  /rest/v1/   │  /storage/   │ /functions/  │    /pg/       │ │
│  │  (PostgREST) │  (Storage)   │ (Edge Funcs) │    (Meta)     │ │
│  └──────┬───────┴──────┬───────┴──────┬───────┴───────┬───────┘ │
└─────────┼──────────────┼──────────────┼───────────────┼─────────┘
          ▼              ▼              ▼               ▼
┌──────────────┐ ┌────────────┐ ┌─────────────┐ ┌─────────────┐
│   PostgREST  │ │  Storage   │ │ Edge Runtime│ │ Postgres    │
│   (:3000)    │ │  (:5000)   │ │   (:9000)   │ │ Meta        │
└──────┬───────┘ └──────┬─────┘ └──────┬──────┘ └──────┬──────┘
       │                │              │               │
       └────────────────┴──────────────┴───────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PostgreSQL Database (:5534)                   │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │ Tables: users, products, orders, categories, weight_options ││
│  │ RLS: Enabled on all tables                                  ││
│  │ Auth: Custom JWT via auth.uid(), auth.role()                ││
│  └─────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────┘
```

---

## Database Schema

### Enums

- `user_role`: customer, admin, delivery_staff, super_admin
- `order_status`: placed, confirmed, out_for_delivery, delivered, cancelled, delivery_failed

### Core Tables

| Table | Description | Key Fields |
|-------|-------------|------------|
| `users` | All user accounts | phone, name, role, is_active |
| `categories` | Product categories | name, name_gu, slug, display_order |
| `products` | Spice products | name, name_gu, category_id, is_available |
| `weight_options` | Price variants | product_id, weight_grams, price_paise |
| `orders` | Customer orders | order_number, user_id, status, total_paise |
| `order_items` | Line items | order_id, product snapshot, quantity |

### Authentication Tables

| Table | Description |
|-------|-------------|
| `otp_requests` | OTP verification records (with IP, user_agent, delivery_status) |
| `refresh_tokens` | JWT refresh tokens |
| `push_tokens` | FCM push notification tokens |
| `sms_config` | SMS provider configuration (production_mode toggle) |
| `otp_rate_limits` | Phone-based rate limits (40/hour, 20/day) |
| `ip_rate_limits` | IP-based rate limits (100/hour) |
| `test_otp_records` | Test phones with fixed OTPs |

### Supporting Tables

| Table | Description |
|-------|-------------|
| `user_addresses` | Delivery addresses |
| `favorites` | Product wishlist |
| `order_status_history` | Audit trail |
| `app_settings` | Key-value config |
| `daily_order_counters` | Order number generation |

---

## Edge Functions

All functions available at `/functions/v1/{function-name}`:

| Function | Auth | Description |
|----------|------|-------------|
| `send-otp` | No | Generate and send OTP via SMS |
| `verify-otp` | No | Verify OTP, return JWT |
| `checkout` | User | Create order from cart |
| `update-order-status` | Admin | Change order status |
| `verify-delivery-otp` | Delivery | Complete delivery |
| `mark-delivery-failed` | Delivery | Mark delivery failed |
| `reorder` | User | Recreate cart from past order |
| `health` | No | Health check endpoint |

### OTP Flow & Modes

**Rate Limits:**
| Limit | Value | Reset |
|-------|-------|-------|
| Phone hourly | 40 | Top of each hour |
| Phone daily | 20 | Midnight |
| IP hourly | 100 | Top of each hour |

**Test Phone Support:**
- Add phones to `test_otp_records` table with fixed OTPs
- Works in ALL modes (test and production)
- Default: `+919876543210` -> `123456`

**Production Mode Toggle:**
- Controlled by `sms_config.production_mode` flag
- `false` (default): Uses hardcoded OTP `123456` for all phones, no SMS sent
- `true`: Generates random OTP, sends via MSG91

```bash
# Check current mode
docker exec masala-db psql -U supabase_admin -d postgres \
  -c "SELECT production_mode FROM sms_config;"

# Enable production mode (when MSG91 configured)
docker exec masala-db psql -U supabase_admin -d postgres \
  -c "UPDATE sms_config SET production_mode = true;"

# Add a test phone
docker exec masala-db psql -U supabase_admin -d postgres \
  -c "INSERT INTO test_otp_records (phone_number, fixed_otp, description) VALUES ('+919999999999', '111111', 'QA test phone');"
```

**Development Logging:**
```bash
docker compose logs functions | grep "TEST"
# Output: [TEST_MODE] Using test OTP 123456 for +919876543210
# Or: [TEST_PHONE] Using fixed OTP for +919876543210
```

---

## Authentication Flow

```
1. User enters phone number
2. App calls POST /functions/v1/send-otp
   - Check IP rate limit (100/hour)
   - Check phone rate limit (40/hour, 20/day)
   - Check test_otp_records for fixed OTP
   - If production_mode=false: use '123456'
   - If production_mode=true: generate random OTP, send via MSG91
3. OTP sent via MSG91 SMS (or logged in test mode)
4. User enters OTP
5. App calls POST /functions/v1/verify-otp
   - Check test_otp_records first (works in ALL modes)
   - If production_mode=false: accept '123456' for any phone
   - Otherwise: verify against stored OTP hash
6. Server returns JWT access_token + refresh_token
7. All subsequent requests include: Authorization: Bearer {access_token}
```

### JWT Structure

```json
{
  "sub": "user-uuid",
  "phone": "+919876543210",
  "role": "customer",
  "iat": 1706000000,
  "exp": 1706003600
}
```

---

## Order Status Flow

```
     ┌─────────┐
     │ placed  │
     └────┬────┘
          │
          ▼
   ┌──────────────┐
   │  confirmed   │───────────────────────────┐
   └──────┬───────┘                           │
          │                                   │
          ▼                                   ▼
┌─────────────────────┐               ┌─────────────┐
│  out_for_delivery   │──────────────►│  cancelled  │
└──────────┬──────────┘               └─────────────┘
           │                                   ▲
     ┌─────┴─────┐                             │
     │           │                             │
     ▼           ▼                             │
┌──────────┐ ┌────────────────┐                │
│delivered │ │delivery_failed │────────────────┘
└──────────┘ └───────┬────────┘
                     │
                     └──► (can retry → out_for_delivery)
```

---

## Credentials

### Database
- **Host**: localhost
- **Port**: 5534
- **User**: supabase_admin
- **Password**: masala-super-secret-postgres-password-2024
- **Database**: postgres

### Studio Dashboard
- **URL**: http://localhost:54424
- **Username**: supabase
- **Password**: masala-dashboard-2024

---

## Development Commands

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# View logs
docker compose logs -f

# View specific service logs
docker compose logs -f functions
docker compose logs -f storage

# Restart a service
docker compose restart functions

# Check status
docker compose ps

# Connect to database
docker exec -it masala-db psql -U supabase_admin -d postgres

# Run SQL migration
docker exec -i masala-db psql -U supabase_admin -d postgres < path/to/migration.sql
```

---

## Troubleshooting

### "permission denied for table X"
Grant permissions to the role:
```bash
docker exec masala-db psql -U supabase_admin -d postgres -c "GRANT ALL ON tablename TO service_role;"
```

### Storage keeps restarting
Grant superuser to storage admin:
```bash
docker exec masala-db psql -U supabase_admin -d postgres -c "ALTER ROLE supabase_storage_admin WITH SUPERUSER;"
docker compose restart storage
```

### Supavisor keeps restarting
Create the required schema:
```bash
docker exec masala-db psql -U supabase_admin -d postgres -c "CREATE SCHEMA IF NOT EXISTS _supavisor;"
docker compose restart supavisor
```

### Functions returning "invalid response from upstream"
Check if edge runtime is listening on port 9000 (not 8000). Kong routes to port 9000.

### JWT signature errors
Ensure API keys in `.env` and `kong.yml` match the JWT_SECRET. Regenerate keys if needed:
```bash
JWT_SECRET="your-jwt-secret"
# Generate proper keys signed with your secret
```

### Database was reset
Run migrations again:
```bash
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/01-schema.sql
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/02-auth-helpers.sql
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/03-rls-policies.sql
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/04-seed-data.sql
docker exec -i masala-db psql -U supabase_admin -d postgres < volumes/db/init/05-auth-enhancements.sql
```

---

## File Structure

```
backend/
├── docker-compose.yml      # Main compose file
├── .env                    # Secrets (git-ignored)
├── .env.example            # Environment template
├── CLAUDE.md               # AI assistant instructions
├── ARCHITECTURE.md         # This file
└── volumes/
    ├── api/
    │   └── kong.yml        # Kong gateway config
    ├── db/
    │   └── init/
    │       ├── 00-roles.sh             # Database roles setup
    │       ├── 01-schema.sql           # Tables and functions
    │       ├── 02-auth-helpers.sql     # Auth JWT helpers
    │       ├── 03-rls-policies.sql     # Row Level Security
    │       ├── 04-seed-data.sql        # Sample data
    │       └── 05-auth-enhancements.sql # Rate limits, SMS config, test phones
    ├── functions/
    │   ├── _shared/
    │   │   ├── auth.ts     # JWT, OTP helpers
    │   │   ├── sms.ts      # MSG91 integration
    │   │   └── push.ts     # FCM integration
    │   ├── send-otp/
    │   ├── verify-otp/
    │   ├── checkout/
    │   ├── update-order-status/
    │   ├── verify-delivery-otp/
    │   ├── mark-delivery-failed/
    │   ├── reorder/
    │   ├── main/           # Router
    │   └── import_map.json
    ├── logs/
    │   └── vector/
    │       └── vector.yml
    └── storage/            # File storage (volume)
```

---

## Security Notes

1. **Never commit `.env`** - Use `.env.example` as template
2. **Rotate secrets regularly** - JWT_SECRET, POSTGRES_PASSWORD
3. **Use localhost binding** - For internal services (PostgreSQL, Supavisor)
4. **RLS is critical** - Never bypass without service_role
5. **Validate phone numbers** - Format: +91XXXXXXXXXX
6. **Rate limit OTPs** - Phone: 40/hour, 20/day; IP: 100/hour
7. **Hash OTPs** - Never store plain text
8. **Production mode** - Set `sms_config.production_mode = true` before going live
