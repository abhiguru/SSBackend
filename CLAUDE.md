# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Masala Spice Shop MVP backend - a self-hosted Supabase backend for a React Native spice ordering app. This is an MVP with no inventory tracking; admin controls product availability via toggles.

## Tech Stack

- **Backend**: Self-hosted Supabase (Docker)
- **Database**: PostgreSQL 15+
- **API**: PostgREST + Edge Functions (Deno)
- **Auth**: Custom OTP + JWT (not Supabase Auth)
- **Storage**: Supabase Storage
- **SMS**: MSG91
- **Push**: FCM

## Docker Stack Configuration

**CRITICAL**: This server runs multiple Supabase stacks. The GuruColdStorage stack MUST NOT be interfered with.

### Existing GuruColdStorage Stack (DO NOT MODIFY)

| Property | Value |
|----------|-------|
| Location | `/home/gcswebserver/ws/GuruColdStorageSupabase/supabase/docker/` |
| Project Name | `supabase` |
| Network | `supabase_default` (172.20.0.0/24) |
| Container Prefix | `supabase-*` |

**Ports in use by GuruColdStorage** (do not use these):

| Port | Service |
|------|---------|
| 8000 | Kong HTTP |
| 8443 | Kong HTTPS |
| 54323 | Studio |
| 5432-5433 | PostgreSQL |
| 6543-6544 | Supavisor |
| 4000-4001 | Analytics/Admin |
| 3100, 6310, 9100, 9187, 8082, 9093, 9095, 3001 | Monitoring stack |

### Masala Stack Configuration (REQUIRED)

When creating docker-compose.yml, use these settings:

```yaml
name: masala  # Sets container prefix to masala-*
networks:
  default:
    ipam:
      config:
        - subnet: 172.21.0.0/24
```

**Required port assignments for Masala**:

| Service | Port | Binding |
|---------|------|---------|
| Kong HTTP | 8100 | 0.0.0.0 |
| Kong HTTPS | 8543 | 0.0.0.0 |
| PostgreSQL | 5534 | 127.0.0.1 |
| Supavisor Session | 5535 | 127.0.0.1 |
| Supavisor Transaction | 6643 | 127.0.0.1 |
| Supavisor Admin | 4101 | 127.0.0.1 |
| Studio | 54424 | 0.0.0.0 |
| Analytics | 4100 | 127.0.0.1 |

**Volume naming**: All volumes must be prefixed with `masala_` (e.g., `masala_db-config`, `masala_storage`).

## Development Commands

```bash
# Start all services
docker compose up -d

# View logs
docker compose logs -f functions

# Restart a service
docker compose restart functions

# Run database migrations
docker compose exec postgres psql -U postgres -f /path/to/migration.sql

# Deploy edge functions
docker compose restart functions
```

## Architecture

### Database Structure

Key tables and relationships:
- `users` - All user types (customer, admin, delivery_staff, super_admin) via `user_role` enum
- `products` → `weight_options` - Products have multiple weight/price variants
- `orders` → `order_items` - Orders snapshot product data at order time
- `order_status_history` - Audit trail for order state changes
- `app_settings` - Key-value store for shipping charges, serviceable pincodes

**Order Status Flow**: `placed` → `confirmed` → `out_for_delivery` → `delivered`
Alternative paths: `cancelled` (from any pre-delivered state), `delivery_failed` (from out_for_delivery)

### Edge Functions (Deno)

Located in `supabase/functions/`:
- `send-otp` - Generate and send OTP via MSG91
- `verify-otp` - Verify OTP, create/find user, return JWT
- `checkout` - Validate cart, check pincode serviceability, create order
- `update-order-status` - Admin: transition order states, assign delivery staff
- `verify-delivery-otp` - Delivery staff: complete delivery with customer OTP
- `mark-delivery-failed` - Delivery staff: mark delivery failed with reason
- `reorder` - Customer: recreate cart from previous order (filters unavailable items)

Shared helpers in `supabase/functions/_shared/auth.ts`: `requireAuth()`, `requireAdmin()`, `requireDeliveryStaff()`, `sendPush()`, `sendSMS()`

### Row Level Security

RLS is enabled on all tables. Key patterns:
- Public read: active categories, available products/weight_options
- User-specific: addresses, favorites, own orders, push tokens
- Admin: full access to products, categories, orders, users
- Delivery staff: only assigned orders in `out_for_delivery` status

Auth helpers `auth.uid()` and `auth.role()` extract from JWT claims.

### API Patterns

PostgREST endpoints at `/rest/v1/`:
- Use query params for filtering: `?is_available=eq.true`
- Related data: `?select=*,weight_options(*)`
- Ordering: `?order=created_at.desc`

Edge functions at `/functions/v1/`:
- All require `Authorization: Bearer {jwt}` except send-otp/verify-otp
- Return structured errors: `{ error: 'CODE', message: 'Description' }`

## Environment Variables

Required in `.env`:
- `POSTGRES_PASSWORD`, `JWT_SECRET`, `OTP_SECRET`, `SERVICE_ROLE_KEY`
- `MSG91_AUTH_KEY`, `MSG91_OTP_TEMPLATE`, `MSG91_TEMPLATE`
- `FCM_SERVER_KEY`

## CORS Configuration

CORS headers are centralized in `volumes/functions/_shared/cors.ts`. The wildcard origin (`*`) is intentional: this backend serves a React Native mobile app, which does not enforce browser same-origin policy. Restricting origins would add no security benefit and would complicate development. All edge functions import CORS headers from this shared module.

Shared response helpers are in `volumes/functions/_shared/response.ts` (`jsonResponse`, `errorResponse`, `handleError`).

## Key Implementation Details

- Prices stored in paise (₹1 = 100 paise)
- Order numbers: `MSS-YYYYMMDD-NNN` (generated via `generate_order_number()` function)
- Phone format: `+91XXXXXXXXXX` (10 digits, starting with 6-9)
- OTPs hashed with SHA-256 before storage
- Delivery OTP: 4-digit, sent via SMS when order goes `out_for_delivery`
- Products have bilingual names (English + Gujarati)
