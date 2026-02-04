# Masala Spice Shop - Backend Architecture

Comprehensive technical documentation for the Masala Spice Shop MVP backend.

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Infrastructure Layer](#2-infrastructure-layer)
3. [API Gateway - Kong](#3-api-gateway---kong)
4. [Database Schema](#4-database-schema)
5. [Edge Functions](#5-edge-functions)
6. [External Integrations](#6-external-integrations)
7. [Security Architecture](#7-security-architecture)
8. [Edge Cases & Implementation Details](#8-edge-cases--implementation-details)
9. [Configuration Reference](#9-configuration-reference)
10. [Operations Guide](#10-operations-guide)
11. [Performance Optimizations & Migration Guide](#11-performance-optimizations--migration-guide)

---

## 1. System Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              REACT NATIVE APP                               │
│                         (iOS / Android Client)                              │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           KONG API GATEWAY                                  │
│                    (masala-kong:8100/8543)                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │   /rest/v1  │  │/functions/v1│  │ /storage/v1 │  │    /pg/     │       │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘       │
└─────────┼────────────────┼────────────────┼────────────────┼───────────────┘
          │                │                │                │
          ▼                ▼                ▼                ▼
    ┌──────────┐    ┌──────────┐    ┌──────────────┐  ┌──────────┐
    │ PostgREST│    │   Edge   │    │   Storage    │  │ Postgres │
    │  (rest)  │    │Functions │    │  + imgproxy  │  │   Meta   │
    └────┬─────┘    └────┬─────┘    └──────┬───────┘  └────┬─────┘
         │               │                 │               │
         └───────────────┴────────┬────────┴───────────────┘
                                  │
                                  ▼
                    ┌─────────────────────────┐
                    │      PostgreSQL 15+     │
                    │      (masala-db)        │
                    │   ┌─────────────────┐   │
                    │   │   Supavisor     │   │
                    │   │(Connection Pool)│   │
                    │   └─────────────────┘   │
                    └─────────────────────────┘
```

### Tech Stack

| Component | Technology | Version |
|-----------|------------|---------|
| Database | PostgreSQL | 15.8.1 |
| API Gateway | Kong | 2.8.1 |
| REST API | PostgREST | 12.2.0 |
| Edge Functions | Deno (Edge Runtime) | 1.65.3 |
| File Storage | Supabase Storage | 1.11.13 |
| Image Processing | imgproxy | 3.8.0 |
| Connection Pooler | Supavisor | 1.1.56 |
| Admin Dashboard | Supabase Studio | 20241202 |
| Auth | Custom OTP + JWT (not Supabase Auth) |

### Multi-Stack Server Isolation

This server hosts multiple Supabase stacks. Network isolation prevents conflicts:

| Stack | Network Subnet | Container Prefix | Purpose |
|-------|----------------|------------------|---------|
| GuruColdStorage | 172.20.0.0/24 | `supabase-*` | Existing production stack (DO NOT MODIFY) |
| **Masala** | **172.21.0.0/24** | **`masala-*`** | Spice shop backend |

---

## 2. Infrastructure Layer

### Docker Compose Services (9 Containers)

| Service | Image | Port Binding | IP Address | Purpose |
|---------|-------|--------------|------------|---------|
| **masala-db** | supabase/postgres:15.8.1.060 | 127.0.0.1:5534:5432 | 172.21.0.5 | PostgreSQL database |
| **masala-kong** | kong:2.8.1 | 0.0.0.0:8100:8000, 0.0.0.0:8543:8443 | 172.21.0.2 | API gateway (HTTP/HTTPS) |
| **masala-rest** | postgrest/postgrest:v12.2.0 | (internal only) | 172.21.0.10 | PostgREST database API |
| **masala-storage** | supabase/storage-api:v1.11.13 | (internal only) | 172.21.0.11 | File storage service |
| **masala-imgproxy** | darthsim/imgproxy:v3.8.0 | (internal only) | 172.21.0.17 | Image transformation |
| **masala-functions** | supabase/edge-runtime:v1.65.3 | (internal only) | 172.21.0.12 | Deno edge functions |
| **masala-meta** | supabase/postgres-meta:v0.84.2 | (internal only) | 172.21.0.14 | Schema introspection |
| **masala-studio** | supabase/studio:20241202-71e5240 | 0.0.0.0:54424:3000 | 172.21.0.15 | Admin dashboard |
| **masala-supavisor** | supabase/supavisor:1.1.56 | 127.0.0.1:5535:5432, 127.0.0.1:6643:6543, 127.0.0.1:4101:4000 | 172.21.0.18 | Connection pooler |

### Health Check Dependencies

```
masala-db (healthy)
    ├─► masala-kong
    ├─► masala-rest ──► masala-storage ◄── masala-imgproxy (started)
    ├─► masala-functions
    ├─► masala-meta ──► masala-studio
    └─► masala-supavisor
```

**Health Check Configuration:**

| Service | Command | Interval | Timeout | Retries |
|---------|---------|----------|---------|---------|
| db | `pg_isready -U postgres -h localhost` | 5s | 5s | 10 |
| storage | HTTP GET `/status` on :5000 | 5s | 5s | 5 |
| imgproxy | `imgproxy health` | 5s | 5s | 5 |
| studio | Node fetch `/api/profile` | 10s | 5s | 3 |
| supavisor | curl HEAD `/api/health` | 10s | 5s | 5 |

### Volume Persistence

| Volume | Mount Point | Purpose |
|--------|-------------|---------|
| `masala_db-config` | PostgreSQL data | Database files, configuration |
| `masala_storage` | Storage backend | Uploaded files (product images) |

**Host Mounts:**

```
./volumes/db/init/           → /docker-entrypoint-initdb.d    (Database migrations)
./volumes/api/kong.yml       → /home/kong/kong.yml            (Kong configuration)
./volumes/functions/         → /home/deno/functions           (Edge functions)
```

### Production Startup Script (`start-masala.sh`)

The startup script provides production-ready initialization:

1. **Log Rotation** - 7-day retention, compression of old logs
2. **Docker Verification** - Connection check with retries (15 attempts)
3. **System Resource Check** - CPU, memory, disk, load average
4. **Security Configuration** - Auto-fix port bindings to localhost
5. **Environment Validation** - Required variables, JWT configuration
6. **Pooler Key Generation** - Secret key and vault encryption key
7. **Service Management** - Stop existing → Start fresh
8. **Database Ready Check** - Poll until PostgreSQL accepts connections
9. **Permission Grants** - Supabase service role permissions
10. **Health Verification** - Final service health report

**Protected Port Bindings** (enforced to 127.0.0.1):
- `5534:5432` - PostgreSQL
- `5535:5432` - Supavisor Session
- `6643:6543` - Supavisor Transaction
- `4101:4000` - Supavisor Admin

---

## 3. API Gateway - Kong

### Route Configuration

| Route | Path Pattern | Backend Target | Auth Required |
|-------|--------------|----------------|---------------|
| `rest-v1` | `/rest/v1/` | http://rest:3000/ | key-auth + ACL |
| `rest-v1-rpc` | `/rest/v1/rpc/` | http://rest:3000/rpc/ | key-auth + ACL |
| `storage-v1-public` | `/storage/v1/object/public/` | http://storage:5000/object/public/ | None |
| `storage-v1-render-public` | `/storage/v1/render/image/public/` | http://storage:5000/render/image/public/ | None |
| `storage-v1` | `/storage/v1/` | http://storage:5000/ | key-auth + ACL |
| `functions-v1` | `/functions/v1/` | http://functions:9000/ | key-auth + ACL |
| `meta` | `/pg/` | http://meta:8080/ | key-auth + ACL (admin only) |

### Authentication Consumers

| Consumer | API Key | ACL Group | Purpose |
|----------|---------|-----------|---------|
| `anon` | `ANON_KEY` JWT | `anon` | Public/unauthenticated access |
| `service_role` | `SERVICE_ROLE_KEY` JWT | `admin` | Backend/admin access |
| `DASHBOARD` | Basic Auth | - | Studio dashboard access |

### CORS Configuration

```yaml
methods: [GET, HEAD, PUT, PATCH, POST, DELETE, OPTIONS, TRACE, CONNECT]
headers: [Accept, Accept-Version, Authorization, apikey, Content-Length, Content-MD5,
          Content-Type, Date, X-Auth-Token, x-client-info, X-Shiprocket-Signature]
origins: ["*"]  # Intentional - React Native app (no same-origin policy)
credentials: true
max_age: 3600
```

### Buffer Configuration

```yaml
request_body_size: 160k × 64 = 10.24 MB  # Large JSON responses
proxy_buffer_size: 160k
proxy_buffers: 64 160k
```

---

## 4. Database Schema

### Entity Relationship Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           USERS & AUTH                                  │
├─────────────────────────────────────────────────────────────────────────┤
│  users ◄──┬── otp_requests                                              │
│           ├── refresh_tokens                                            │
│           ├── push_tokens                                               │
│           ├── account_deletion_requests                                 │
│           └── user_addresses                                            │
└─────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         PRODUCT CATALOG                                 │
├─────────────────────────────────────────────────────────────────────────┤
│  categories ◄── products ◄── product_images                            │
│                    │                                                    │
│                    └── favorites (user_id + product_id)                 │
└─────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        SHOPPING & ORDERS                                │
├─────────────────────────────────────────────────────────────────────────┤
│  cart_items (user + product + custom_weight_grams)                      │
│       │                                                                 │
│       ▼                                                                 │
│  orders ◄── order_items (product snapshot)                              │
│       │                                                                 │
│       └── order_status_history (audit trail)                            │
└─────────────────────────────────────────────────────────────────────────┘
```

### Enums

```sql
-- User roles
CREATE TYPE user_role AS ENUM ('customer', 'admin', 'delivery_staff');

-- Order lifecycle states
CREATE TYPE order_status AS ENUM (
    'placed',           -- Initial state after checkout
    'confirmed',        -- Admin confirmed the order
    'out_for_delivery', -- Assigned to delivery staff
    'delivered',        -- Successfully delivered
    'cancelled',        -- Cancelled (by customer or admin)
    'delivery_failed'   -- Delivery attempt failed
);
```

### Core Tables

#### Users & Authentication

**`users`** - All user accounts (customers, admins, delivery staff)

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK, DEFAULT uuid_generate_v4() | Unique identifier |
| `phone` | VARCHAR(15) | UNIQUE, NOT NULL | Phone number (+91XXXXXXXXXX) |
| `name` | VARCHAR(100) | | Display name |
| `role` | user_role | DEFAULT 'customer' | User type |
| `language` | VARCHAR(5) | DEFAULT 'en' | Preferred language (en/gu) |
| `is_active` | BOOLEAN | DEFAULT true | Account status |
| `created_at` | TIMESTAMPTZ | DEFAULT NOW() | |
| `updated_at` | TIMESTAMPTZ | DEFAULT NOW() | |

**Indexes:** `phone`, `role`

---

**`otp_requests`** - OTP verification records

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `phone` | VARCHAR(15) | NOT NULL | Target phone |
| `otp_hash` | VARCHAR(64) | | SHA-256 hashed OTP |
| `expires_at` | TIMESTAMPTZ | | 5-minute default |
| `verified` | BOOLEAN | DEFAULT false | |
| `attempts` | INT | DEFAULT 0 | Failed attempt count |
| `ip_address` | INET | | Request IP for rate limiting |
| `user_agent` | TEXT | | Request user agent |
| `msg91_request_id` | VARCHAR(255) | | SMS provider tracking |
| `delivery_status` | TEXT | | pending/sent/failed |
| `created_at` | TIMESTAMPTZ | | |

**Indexes:** `phone`, `expires_at`

---

**`refresh_tokens`** - JWT refresh token management

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `user_id` | UUID | FK → users | Token owner |
| `token_hash` | VARCHAR(64) | UNIQUE | SHA-256 hashed token |
| `expires_at` | TIMESTAMPTZ | | 30-day default |
| `revoked` | BOOLEAN | DEFAULT false | Token invalidated |
| `created_at` | TIMESTAMPTZ | | |

**Indexes:** `user_id`, `token_hash`

---

**`push_tokens`** - Expo push notification tokens

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `user_id` | UUID | FK → users, NOT NULL | Device owner |
| `token` | TEXT | NOT NULL | Expo push token |
| `platform` | VARCHAR(10) | | ios / android |
| `created_at` | TIMESTAMPTZ | | |
| `updated_at` | TIMESTAMPTZ | | |

**Constraints:** UNIQUE(user_id, token)

---

**`account_deletion_requests`** - GDPR deletion workflow

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `user_id` | UUID | FK → users, ON DELETE CASCADE | Requesting user |
| `status` | VARCHAR(20) | CHECK IN ('pending', 'approved', 'rejected') | Request state |
| `admin_notes` | TEXT | | Admin response |
| `processed_by` | UUID | FK → users | Admin who processed |
| `processed_at` | TIMESTAMPTZ | | Processing timestamp |
| `created_at` | TIMESTAMPTZ | | |
| `updated_at` | TIMESTAMPTZ | | |

---

#### Rate Limiting

**`otp_rate_limits`** - Phone-based OTP rate limiting

| Column | Type | Description |
|--------|------|-------------|
| `phone_number` | VARCHAR(15) | PK |
| `hourly_count` | INT | Requests this hour |
| `daily_count` | INT | Requests today |
| `last_reset_hour` | TIMESTAMPTZ | Last hourly reset |
| `last_reset_day` | TIMESTAMPTZ | Last daily reset |

**`ip_rate_limits`** - IP-based rate limiting

| Column | Type | Description |
|--------|------|-------------|
| `ip_address` | INET | PK |
| `hourly_count` | INT | Requests this hour |
| `last_reset_hour` | TIMESTAMPTZ | Last reset |

**`test_otp_records`** - Fixed OTPs for development/testing

| Column | Type | Description |
|--------|------|-------------|
| `phone_number` | VARCHAR(15) | PK |
| `fixed_otp` | VARCHAR(6) | Test OTP value |
| `description` | TEXT | Test account description |

---

#### Product Catalog

**`categories`** - Product categories

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `name` | VARCHAR(100) | NOT NULL | English name |
| `name_gu` | VARCHAR(100) | | Gujarati name |
| `slug` | VARCHAR(100) | UNIQUE | URL-safe identifier |
| `image_url` | TEXT | | Category image |
| `display_order` | INT | DEFAULT 0 | Sort order |
| `is_active` | BOOLEAN | DEFAULT true | Visibility |
| `created_at` | TIMESTAMPTZ | | |
| `updated_at` | TIMESTAMPTZ | | |

**Indexes:** `(is_active, display_order)`

---

**`products`** - Product catalog

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `category_id` | UUID | FK → categories | |
| `name` | VARCHAR(200) | NOT NULL | English name |
| `name_gu` | VARCHAR(200) | | Gujarati name |
| `description` | TEXT | | English description |
| `description_gu` | TEXT | | Gujarati description |
| `image_url` | TEXT | | Primary image |
| `is_available` | BOOLEAN | DEFAULT true | In stock |
| `is_active` | BOOLEAN | DEFAULT true | Visible in app |
| `price_per_kg_paise` | INT | DEFAULT 0, >= 0 | Price per kilogram in paise |
| `display_order` | INT | | Sort order |
| `search_vector` | TSVECTOR | | Full-text search index |
| `created_at` | TIMESTAMPTZ | | |
| `updated_at` | TIMESTAMPTZ | | |

**Indexes:** `category_id`, `(is_available, is_active)`, `search_vector` (GIN)

**Note:** The `weight_options` table has been removed. All pricing is now calculated from `price_per_kg_paise` with custom weights.

---

**`product_images`** - Multi-image support with upload workflow

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `product_id` | UUID | FK → products ON DELETE CASCADE | |
| `image_url` | TEXT | NOT NULL | Storage URL |
| `display_order` | INT | DEFAULT 0 | Sort order |
| `upload_token` | UUID | UNIQUE | Validation token |
| `upload_status` | VARCHAR(20) | DEFAULT 'pending' | pending / confirmed |
| `created_at` | TIMESTAMPTZ | | |

**Upload Workflow:**
1. Client uploads image with unique `upload_token`
2. Image stored with `upload_status = 'pending'`
3. Admin confirms → `upload_status = 'confirmed'`
4. Orphan cleanup: pending images > 1 hour auto-deleted
5. On image delete: auto-update `product.image_url` to next image

---

**`favorites`** - User wishlist

| Column | Type | Constraints |
|--------|------|-------------|
| `id` | UUID | PK |
| `user_id` | UUID | FK → users |
| `product_id` | UUID | FK → products |
| `created_at` | TIMESTAMPTZ | |

**Constraints:** UNIQUE(user_id, product_id)

---

#### Shopping & Orders

**`cart_items`** - Shopping cart (custom weights only)

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `user_id` | UUID | FK → users | Cart owner |
| `product_id` | UUID | FK → products | |
| `custom_weight_grams` | INT | NOT NULL, 10-25000 | Weight in grams (10g to 25kg) |
| `quantity` | INT | DEFAULT 1, 1-100 | Item count |
| `created_at` | TIMESTAMPTZ | | |
| `updated_at` | TIMESTAMPTZ | | |

**Constraints:** UNIQUE(user_id, product_id, custom_weight_grams)

**Price Calculation:** `unit_price = ROUND(price_per_kg_paise × weight_grams / 1000)`

---

**`orders`** - Order records

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `order_number` | VARCHAR(20) | UNIQUE | MSS-YYYYMMDD-NNN format |
| `user_id` | UUID | FK → users | Customer |
| `status` | order_status | DEFAULT 'placed' | Current state |
| `shipping_name` | VARCHAR(100) | | Address snapshot |
| `shipping_phone` | VARCHAR(15) | | |
| `shipping_address_line1` | VARCHAR(200) | | |
| `shipping_address_line2` | VARCHAR(200) | | |
| `shipping_city` | VARCHAR(100) | | |
| `shipping_state` | VARCHAR(100) | | |
| `shipping_pincode` | VARCHAR(10) | | |
| `subtotal_paise` | INT | >= 0 | Items total |
| `shipping_paise` | INT | DEFAULT 0, >= 0 | Shipping charge |
| `total_paise` | INT | >= 0 | Grand total |
| `delivery_staff_id` | UUID | FK → users | Assigned delivery person |
| `delivery_otp_hash` | VARCHAR(64) | | Hashed 4-digit PIN |
| `delivery_otp_expires` | TIMESTAMPTZ | | 24-hour expiry |
| `customer_notes` | TEXT | | Customer instructions |
| `admin_notes` | TEXT | | Internal notes |
| `cancellation_reason` | TEXT | | If cancelled |
| `failure_reason` | TEXT | | If delivery failed |
| `created_at` | TIMESTAMPTZ | | |
| `updated_at` | TIMESTAMPTZ | | |

**Indexes:** `user_id`, `status`, `delivery_staff_id`, `order_number`, `(created_at DESC)`

---

**`order_items`** - Order line items (product snapshot)

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `order_id` | UUID | FK → orders | |
| `product_id` | UUID | FK → products ON DELETE SET NULL | Reference (may be null if product deleted) |
| `product_name` | VARCHAR(200) | | Snapshot at order time |
| `product_name_gu` | VARCHAR(200) | | |
| `weight_label` | VARCHAR(50) | | e.g., "100g", "1.5kg" |
| `weight_grams` | INT | | Weight at order time |
| `unit_price_paise` | INT | | Price per unit at order time |
| `quantity` | INT | > 0 | |
| `total_paise` | INT | | unit_price × quantity |
| `created_at` | TIMESTAMPTZ | | |

**Constraint:** `total_paise = unit_price_paise × quantity`

---

**`order_status_history`** - Immutable audit trail

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| `id` | UUID | PK | |
| `order_id` | UUID | FK → orders | |
| `from_status` | order_status | | Previous status (NULL for initial) |
| `to_status` | order_status | | New status |
| `changed_by` | UUID | FK → users | Actor |
| `notes` | TEXT | | Transition reason |
| `created_at` | TIMESTAMPTZ | | |

**Indexes:** `order_id`

---

**`daily_order_counters`** - Order number sequence

| Column | Type | Description |
|--------|------|-------------|
| `date` | DATE | PK - Current date |
| `counter` | INT | Sequence for the day |

---

#### Configuration

**`app_settings`** - Key-value configuration store

| Column | Type | Description |
|--------|------|-------------|
| `key` | VARCHAR(100) | PK |
| `value` | JSONB | Setting value |
| `description` | TEXT | Human-readable description |
| `updated_at` | TIMESTAMPTZ | |

**Default Settings:**

| Key | Default Value | Description |
|-----|---------------|-------------|
| `shipping_charge_paise` | `4000` | ₹40 base shipping |
| `free_shipping_threshold_paise` | `50000` | Free shipping above ₹500 |
| `min_order_paise` | `10000` | ₹100 minimum order |
| `serviceable_pincodes` | `[...]` | Delivery coverage list |
| `otp_expiry_seconds` | `300` | 5-minute OTP validity |
| `max_otp_attempts` | `3` | Max failed verifications |
| `delivery_otp_expiry_hours` | `24` | Delivery OTP validity |

---

**`sms_config`** - SMS provider settings (singleton)

| Column | Type | Description |
|--------|------|-------------|
| `id` | SERIAL | PK (always 1) |
| `production_mode` | BOOLEAN | true = send SMS, false = log only |
| `provider` | VARCHAR(20) | DEFAULT 'msg91' |
| `msg91_auth_key` | TEXT | API key |
| `msg91_template_id` | TEXT | OTP template |
| `msg91_sender_id` | VARCHAR(6) | DEFAULT 'MSSHOP' |

---

### SQL Functions

#### Auth Helper Functions

```sql
-- Extract user ID from JWT 'sub' claim
auth.uid() → UUID

-- Extract user role from JWT 'user_role' claim
auth.role() → user_role

-- Check if current user is admin
auth.is_admin() → BOOLEAN

-- Check if current user is delivery staff
auth.is_delivery_staff() → BOOLEAN

-- Verify user account is active
auth.check_user_active() → BOOLEAN
```

#### Cart RPC Functions

```sql
-- Get user's cart with calculated prices
get_cart() → JSON

-- Add item to cart (upsert on conflict)
add_to_cart(p_product_id UUID, p_weight_grams INT, p_quantity INT DEFAULT 1) → JSON

-- Update quantity only
update_cart_quantity(p_cart_item_id UUID, p_quantity INT) → JSON

-- Update weight (with merge if target weight exists)
update_cart_item_weight(p_cart_item_id UUID, p_new_weight_grams INT, p_new_quantity INT) → JSON

-- Remove single item
remove_from_cart(p_cart_item_id UUID) → JSON

-- Clear entire cart
clear_cart() → JSON

-- Get summary (count + subtotal)
get_cart_summary() → JSON
```

#### User Profile RPC Functions

```sql
-- Get profile with addresses
get_profile() → JSON

-- Update name/language
update_profile(p_name TEXT, p_language TEXT) → JSON

-- Address management
get_addresses() → JSON
add_address(label, full_name, phone, line1, line2, city, state, pincode, is_default, lat, lng) → JSON
update_address(p_address_id UUID, ...) → JSON
delete_address(p_address_id UUID) → JSON
set_default_address(p_address_id UUID) → JSON
```

#### Order RPC Functions

```sql
-- List orders with pagination and optional status filter
get_orders(p_status TEXT, p_limit INT, p_offset INT) → JSON

-- Get single order with items
get_order(p_order_id UUID) → JSON

-- Cancel own order (placed/confirmed only)
cancel_order(p_order_id UUID, p_reason TEXT) → JSON

-- Get order status history
get_order_status_history(p_order_id UUID) → JSON
```

#### Atomic Transaction Functions

```sql
-- Create order with items and initial history in one transaction
create_order_atomic(
    p_user_id UUID,
    p_shipping JSONB,
    p_subtotal_paise INT,
    p_shipping_paise INT,
    p_total_paise INT,
    p_customer_notes TEXT,
    p_items JSONB
) → JSONB

-- Status transition with optimistic locking
update_order_status_atomic(
    p_order_id UUID,
    p_new_status order_status,
    p_changed_by UUID,
    p_notes TEXT,
    p_expected_current_status order_status
) → BOOLEAN

-- Account deletion cascade + anonymization
process_account_deletion_atomic(
    p_user_id UUID,
    p_admin_id UUID,
    p_request_id UUID
) → BOOLEAN
```

#### Utility Functions

```sql
-- Generate order number (MSS-YYYYMMDD-NNN)
generate_order_number() → VARCHAR

-- Format weight for display (e.g., "1.5kg", "250g")
format_weight_label(weight_grams INT) → VARCHAR

-- Check product visibility
is_product_visible(product_id UUID) → BOOLEAN

-- Rate limiting checks
check_otp_rate_limit(phone VARCHAR, ip INET) → BOOLEAN
check_ip_rate_limit(ip INET) → BOOLEAN

-- Cleanup expired data
cleanup_expired_data() → JSONB
```

---

### Row Level Security (RLS) Policies

#### Public Access (anon + authenticated)

| Table | Policy | Access |
|-------|--------|--------|
| `categories` | `categories_public_read` | SELECT WHERE is_active = true |
| `products` | `products_public_read` | SELECT WHERE is_available AND is_active |
| `app_settings` | `app_settings_public_read` | SELECT all |

#### User-Owned Data (authenticated)

| Table | Access | Condition |
|-------|--------|-----------|
| `user_addresses` | SELECT, INSERT, UPDATE, DELETE | `auth.uid() = user_id` |
| `push_tokens` | SELECT, INSERT, UPDATE, DELETE | `auth.uid() = user_id` |
| `favorites` | SELECT, INSERT, DELETE | `auth.uid() = user_id` |
| `cart_items` | SELECT, INSERT, UPDATE, DELETE | `auth.uid() = user_id` |
| `orders` | SELECT | `auth.uid() = user_id` |
| `order_items` | SELECT | Via order ownership |
| `order_status_history` | SELECT | Via order ownership |
| `account_deletion_requests` | SELECT, INSERT | `auth.uid() = user_id` |

#### Admin Access (authenticated + is_admin)

| Table | Access |
|-------|--------|
| `users` | SELECT, UPDATE all |
| `categories` | SELECT, INSERT, UPDATE, DELETE |
| `products` | SELECT, INSERT, UPDATE, DELETE |
| `user_addresses` | SELECT all |
| `push_tokens` | SELECT all |
| `orders` | SELECT, UPDATE all |
| `order_items` | SELECT all |
| `order_status_history` | SELECT, INSERT |
| `app_settings` | UPDATE |
| `account_deletion_requests` | ALL |

#### Delivery Staff Access

| Table | Access | Condition |
|-------|--------|-----------|
| `orders` | SELECT | `delivery_staff_id = auth.uid() AND status = 'out_for_delivery'` |
| `order_items` | SELECT | Via assigned order |

---

## 5. Edge Functions

### Function Router

All edge functions are routed through `main/index.ts` which maps URL paths to function handlers. Health check available at `/` or `/health`.

### Authentication Functions

#### `send-otp` (POST)

Send OTP to phone number for authentication.

**Request:**
```json
{
  "phone": "+919876543210"
}
```

**Response:**
```json
{
  "success": true,
  "request_id": "msg91_request_id",
  "otp": "123456"  // Only in non-production mode
}
```

**Rate Limits:**
- 40 requests/hour per phone
- 20 requests/day per phone
- 100 requests/hour per IP

**Flow:**
1. Validate phone format (`+91[6-9]\d{9}`)
2. Check rate limits (phone + IP)
3. Check for test OTP in `test_otp_records`
4. Generate 6-digit OTP (or use test OTP)
5. Hash OTP (SHA-256) and store
6. Send via MSG91 (or log in non-production mode)

---

#### `verify-otp` (POST)

Verify OTP and authenticate user.

**Request:**
```json
{
  "phone": "+919876543210",
  "otp": "123456",
  "name": "Customer Name"  // Optional, for new users
}
```

**Response:**
```json
{
  "success": true,
  "access_token": "eyJ...",
  "refresh_token": "...",
  "user": {
    "id": "uuid",
    "phone": "+919876543210",
    "name": "Customer Name",
    "role": "customer"
  },
  "is_new_user": true
}
```

**Flow:**
1. Find latest unexpired OTP request for phone
2. Verify attempt count < 3
3. Hash provided OTP and compare
4. Find or create user
5. Generate access token (JWT, 1 hour expiry)
6. Generate refresh token (30-day expiry)
7. Mark OTP as verified

---

#### `refresh-token` (POST)

Refresh access token using refresh token.

**Request:**
```json
{
  "refresh_token": "..."
}
```

**Response:**
```json
{
  "access_token": "eyJ...",
  "expires_in": 3600
}
```

**Security:**
- Refresh token rotation (old token revoked)
- Reuse detection (if revoked token used, revoke all user tokens)
- Check user is_active status

---

### Order Functions

#### `checkout` (POST, authenticated)

Create order from cart.

**Request:**
```json
{
  "items": [
    {
      "product_id": "uuid",
      "weight_grams": 500,
      "quantity": 2
    }
  ],
  "address_id": "uuid",
  "notes": "Leave at door"
}
```

**Response:**
```json
{
  "order_id": "uuid",
  "order_number": "MSS-20250204-001",
  "subtotal_paise": 25000,
  "shipping_paise": 4000,
  "total_paise": 29000
}
```

**Flow:**
1. Validate all cart items exist and are available
2. Verify address belongs to user
3. Check pincode is serviceable
4. Calculate prices from `price_per_kg_paise`
5. Check minimum order amount (₹100)
6. Calculate shipping (₹40 or free above ₹500)
7. Create order atomically with items and history
8. Clear user's cart
9. Send push notification to admins

---

#### `update-order-status` (POST, admin only)

Transition order status.

**Request:**
```json
{
  "order_id": "uuid",
  "new_status": "out_for_delivery",
  "delivery_staff_id": "uuid",  // Required for out_for_delivery
  "notes": "Assigned to Ramesh"
}
```

**Status Transitions:**

```
placed ─────► confirmed ─────► out_for_delivery ─────► delivered
   │              │                  │
   ▼              ▼                  ▼
cancelled     cancelled        cancelled
                              delivery_failed
                                   │
                                   ▼
                            out_for_delivery (retry)
```

**Special Handling for `out_for_delivery`:**
1. Require `delivery_staff_id`
2. Generate 4-digit delivery OTP
3. Hash and store OTP with 24-hour expiry
4. Send OTP to customer via SMS

---

#### `verify-delivery-otp` (POST, delivery_staff only)

Complete delivery by verifying customer OTP.

**Request:**
```json
{
  "order_id": "uuid",
  "otp": "1234"
}
```

**Response:**
```json
{
  "success": true,
  "delivery_time": "2025-02-04T15:30:00Z"
}
```

**Validation:**
- Order must be assigned to requesting delivery staff
- Order status must be `out_for_delivery`
- OTP must not be expired
- OTP hash must match

---

#### `mark-delivery-failed` (POST, delivery_staff only)

Mark delivery as failed.

**Request:**
```json
{
  "order_id": "uuid",
  "reason": "Customer not available"
}
```

**Note:** Admin can reassign for retry by transitioning back to `out_for_delivery`.

---

#### `reorder` (POST, authenticated)

Recreate cart from previous order.

**Request:**
```json
{
  "order_id": "uuid"
}
```

**Response:**
```json
{
  "cart_items": [...],
  "unavailable_items": [...]  // Items no longer available
}
```

---

### Admin Functions

#### `users` (GET, admin only)

List all users with optional filtering.

**Query params:** `role`, `is_active`, `search`, `limit`, `offset`

---

#### `delivery-staff` (GET, admin only)

List delivery staff with current assignment status.

**Response includes:**
- Staff details
- Current assigned order (if any)
- Assignment count

---

#### `admin-addresses` (GET, admin only)

Get all user addresses with geocoding data.

---

#### `update-order-items` (POST, admin only)

Modify order items before delivery.

---

### User Functions

#### `register-push-token` (POST, authenticated)

Register device for push notifications.

**Request:**
```json
{
  "token": "ExponentPushToken[...]",
  "platform": "ios"  // or "android"
}
```

---

#### `request-account-deletion` (POST, authenticated)

Request account deletion (GDPR).

**Validation:**
- No active orders (placed, confirmed, out_for_delivery)
- No active delivery assignments (for delivery staff)

---

#### `process-account-deletion` (POST, admin only)

Process account deletion request.

**Request:**
```json
{
  "request_id": "uuid",
  "action": "approve",  // or "reject"
  "notes": "Processed per user request"
}
```

**On Approval:**
1. Delete: addresses, favorites, push_tokens, OTP records
2. Anonymize: phone → `+00deleted_{timestamp}_{random}`
3. Clear: name
4. Set: is_active = false

---

### Shared Utilities

#### `_shared/auth.ts`

```typescript
// Supabase clients
getServiceClient()      // Service role access
getUserClient(authHeader) // User-scoped access

// JWT operations
verifyJWT(token) → JWTPayload | null
signJWT({ sub, phone, role, user_role }) → string

// Auth middleware
requireAuth(req) → AuthContext      // Any authenticated user
requireAdmin(req) → AuthContext     // Admin only
requireDeliveryStaff(req) → AuthContext // Delivery staff only

// OTP utilities
generateOTP() → string    // 6-digit OTP
hashOTP(otp) → string     // SHA-256 hash
validatePhone(phone) → boolean
normalizePhone(phone) → string
```

---

#### `_shared/cors.ts`

```typescript
export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',  // React Native app
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
};
```

---

#### `_shared/response.ts`

```typescript
jsonResponse(data, status = 200)
errorResponse(code: string, message: string, status = 400)
handleError(error) // Format error for response
```

---

#### `_shared/sms.ts`

```typescript
// Get SMS config from database with env fallback
getSMSConfig(supabase) → SMSConfig

// Send OTP via MSG91
sendOTPWithConfig(phone, otp, config) → SendOTPResult

// Send transactional SMS
sendSMSWithConfig(phone, message, config) → SendSMSResult
```

---

#### `_shared/push.ts`

```typescript
// Send push notification (batches of 100)
sendPush(tokens: string[], title: string, body: string, data?: object)

// Admin notification for new orders
sendNewOrderPushToAdmins(order_number: string, total_paise: number)

// Customer notification for status changes
sendOrderStatusPushToCustomer(user_id: string, status: string, order_number: string)
```

**Auto-cleanup:** Invalid `DeviceNotRegistered` tokens are automatically removed.

---

#### `_shared/geocoding.ts`

```typescript
// Google Geocoding with fallback
geocodeAddress(address: string) → GeocodingResult

// Build address string from order
buildAddressString(order) → string

// Distance calculation (Haversine)
calculateDistance(lat1, lng1, lat2, lng2) → km
```

**Fallback Geocoding:** When Google API unavailable, uses hardcoded pincode centroids for Ahmedabad and Rajkot areas.

---

## 6. External Integrations

### MSG91 SMS

| Feature | Details |
|---------|---------|
| **Provider** | MSG91 (India) |
| **OTP Template** | 6-digit code with app name |
| **Transactional** | Order updates, delivery OTP |
| **Production Mode** | Controlled via `sms_config.production_mode` |
| **Test Mode** | Logs SMS to console, doesn't send |
| **Status Tracking** | pending → sent / failed |

**Environment Variables:**
- `MSG91_AUTH_KEY` - API authentication
- `MSG91_OTP_TEMPLATE` - OTP template ID
- `MSG91_TEMPLATE` - General SMS template ID

---

### Expo Push Notifications

| Feature | Details |
|---------|---------|
| **Batch Size** | 100 tokens per request |
| **Auto-cleanup** | Invalid tokens removed |
| **Platforms** | iOS, Android |
| **Token Format** | `ExponentPushToken[...]` |

**Notification Events:**
- New order placed (to admins)
- Order status changed (to customer)
- Delivery assigned (to delivery staff)

---

### Google Geocoding

| Feature | Details |
|---------|---------|
| **Purpose** | Address to coordinates |
| **Region Bias** | India (`region=in`) |
| **Component Filter** | `country:IN` |
| **Fallback** | Pincode centroid lookup |

**Pincode Centroids:** Hardcoded for Ahmedabad (380001-380016) and Rajkot (360001-360005) areas.

---

## 7. Security Architecture

### JWT Structure

**Access Token (1-hour expiry):**
```json
{
  "sub": "user_uuid",
  "phone": "+919876543210",
  "role": "authenticated",
  "user_role": "customer",
  "iat": 1707048000,
  "exp": 1707051600
}
```

**Claims:**
- `sub` - User ID (UUID)
- `phone` - Phone number
- `role` - PostgREST role (`authenticated`)
- `user_role` - Application role (`customer`, `admin`, `delivery_staff`)

### Role-Based Access Control

| Role | Capabilities |
|------|--------------|
| **customer** | Own profile, addresses, orders, cart, favorites |
| **admin** | All data, manage orders/users/products, process deletions |
| **delivery_staff** | View assigned orders, complete/fail delivery |

### OTP Security

| Measure | Implementation |
|---------|----------------|
| **Storage** | SHA-256 hash (not plaintext) |
| **Expiry** | 5 minutes |
| **Attempts** | Max 3 failed verifications |
| **Rate Limit (Phone)** | 40/hour, 20/day |
| **Rate Limit (IP)** | 100/hour |
| **Test Mode** | Fixed OTPs in `test_otp_records` |

### Delivery OTP

| Measure | Implementation |
|---------|----------------|
| **Format** | 4-digit PIN |
| **Generation** | When order → `out_for_delivery` |
| **Expiry** | 24 hours (configurable) |
| **Storage** | SHA-256 hash |
| **Delivery** | SMS to customer |
| **Verification** | By delivery staff via app |

### Data Protection

| Measure | Implementation |
|---------|----------------|
| **RLS** | Enabled on all tables |
| **Database Ports** | Localhost-only (127.0.0.1) |
| **Service Role** | Never exposed to client |
| **Token Rotation** | Refresh tokens rotated on use |
| **Reuse Detection** | Revokes all tokens if reused |
| **Account Deletion** | Phone anonymized, not deleted |

### Phone Anonymization

On account deletion:
```
+919876543210 → +00deleted_1707048000_abc123
```

Format: `+00deleted_{timestamp}_{random_suffix}`

---

## 8. Edge Cases & Implementation Details

### Pricing System

| Rule | Implementation |
|------|----------------|
| **Currency** | All prices in paise (₹1 = 100 paise) |
| **Per-kg Pricing** | `unit_price = price_per_kg_paise × weight_grams / 1000` |
| **Rounding** | ROUND() to nearest paise |
| **Shipping** | ₹40 (4000 paise) default |
| **Free Shipping** | Above ₹500 (50000 paise) |
| **Minimum Order** | ₹100 (10000 paise) |

**Price Calculation Example:**
```
Product: Turmeric Powder @ ₹400/kg (40000 paise/kg)
Weight: 250g
Unit Price: ROUND(40000 × 250 / 1000) = 10000 paise = ₹100
```

### Order Numbers

**Format:** `MSS-YYYYMMDD-NNN`

**Example:** `MSS-20250204-001`

**Generation:**
```sql
-- Upsert daily counter
INSERT INTO daily_order_counters (date, counter)
VALUES (CURRENT_DATE, 1)
ON CONFLICT (date) DO UPDATE SET counter = daily_order_counters.counter + 1
RETURNING counter;

-- Format: MSS-YYYYMMDD-NNN (zero-padded)
```

### Weight Handling

| Constraint | Value |
|------------|-------|
| **Minimum** | 10 grams |
| **Maximum** | 25,000 grams (25 kg) |
| **Display** | `format_weight_label()` function |

**Weight Label Examples:**
- 100g → "100g"
- 1000g → "1kg"
- 1500g → "1.5kg"
- 250g → "250g"

### Cart Merging

When updating cart item weight to match an existing item:

```sql
-- If item exists with target weight, merge quantities (cap at 99)
v_merged_quantity := LEAST(existing_qty + new_qty, 99);

-- Update existing, delete original
UPDATE cart_items SET quantity = v_merged_quantity WHERE id = existing_id;
DELETE FROM cart_items WHERE id = original_id;
```

### Product Image Workflow

**Upload:**
1. Client requests upload token
2. Upload image with token to storage
3. Create `product_images` record with `upload_status = 'pending'`
4. Admin confirms → `upload_status = 'confirmed'`

**Cleanup:**
- Cron job deletes pending images > 1 hour old

**On Delete:**
- Trigger updates `product.image_url` to next confirmed image
- If no images remain, sets to NULL

### Order Snapshot Immutability

Order items capture product state at order time:

| Field | Source | Purpose |
|-------|--------|---------|
| `product_name` | `products.name` | Display even if product renamed |
| `product_name_gu` | `products.name_gu` | Gujarati name at order time |
| `weight_grams` | Cart item | Exact weight ordered |
| `unit_price_paise` | Calculated | Price at order time |

**Note:** `product_id` is `ON DELETE SET NULL` - orders remain valid even if product deleted.

### Account Deletion Cascade

**On Approval:**
```sql
-- 1. Delete related data
DELETE FROM user_addresses WHERE user_id = p_user_id;
DELETE FROM favorites WHERE user_id = p_user_id;
DELETE FROM push_tokens WHERE user_id = p_user_id;
DELETE FROM otp_requests WHERE phone = user_phone;
DELETE FROM refresh_tokens WHERE user_id = p_user_id;
DELETE FROM cart_items WHERE user_id = p_user_id;

-- 2. Anonymize user
UPDATE users SET
    phone = '+00deleted_' || extract(epoch from now())::text || '_' || substring(md5(random()::text), 1, 6),
    name = NULL,
    is_active = false
WHERE id = p_user_id;
```

**Orders are preserved** for business records (with anonymized user reference).

---

## 9. Configuration Reference

### Environment Variables

#### Database

| Variable | Description | Example |
|----------|-------------|---------|
| `POSTGRES_PASSWORD` | Database password | `supersecret123` |
| `POSTGRES_HOST` | Database host | `db` |
| `POSTGRES_DB` | Database name | `postgres` |

#### JWT & Auth

| Variable | Description | Required |
|----------|-------------|----------|
| `JWT_SECRET` | JWT signing secret (32+ chars) | Yes |
| `OTP_SECRET` | OTP hashing secret | Yes |
| `ANON_KEY` | Anonymous JWT for public access | Yes |
| `SERVICE_ROLE_KEY` | Service role JWT for admin access | Yes |

#### SMS (MSG91)

| Variable | Description | Required |
|----------|-------------|----------|
| `MSG91_AUTH_KEY` | MSG91 API key | Yes |
| `MSG91_OTP_TEMPLATE` | OTP template ID | Yes |
| `MSG91_TEMPLATE` | General SMS template | Yes |
| `MSG91_SENDER_ID` | Sender ID (6 chars) | No (default: MSSHOP) |

#### External Services

| Variable | Description | Required |
|----------|-------------|----------|
| `GOOGLE_GEOCODING_API_KEY` | Geocoding API key | No |

#### Infrastructure

| Variable | Description | Default |
|----------|-------------|---------|
| `SECRET_KEY_BASE` | Supavisor secret (64+ chars) | Auto-generated |
| `VAULT_ENC_KEY` | Encryption key (32+ chars) | Auto-generated |
| `DASHBOARD_USERNAME` | Studio login | `supabase` |
| `DASHBOARD_PASSWORD` | Studio password | Required |

### app_settings Reference

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `shipping_charge_paise` | INT | `4000` | Base shipping charge (₹40) |
| `free_shipping_threshold_paise` | INT | `50000` | Free shipping above (₹500) |
| `min_order_paise` | INT | `10000` | Minimum order (₹100) |
| `serviceable_pincodes` | JSONB | `[...]` | Array of serviceable pincodes |
| `otp_expiry_seconds` | INT | `300` | OTP validity (5 min) |
| `max_otp_attempts` | INT | `3` | Max failed OTP attempts |
| `delivery_otp_expiry_hours` | INT | `24` | Delivery OTP validity |

---

## 10. Operations Guide

### Common Commands

```bash
# Start all services
docker compose up -d

# Start with full validation (recommended for production)
./start-masala.sh

# View service logs
docker compose logs -f              # All services
docker compose logs -f functions    # Edge functions only
docker compose logs -f db           # Database only

# Restart specific service
docker compose restart functions
docker compose restart kong

# Check service health
docker compose ps

# Access PostgreSQL directly
docker compose exec db psql -U postgres

# Run SQL migration
docker compose exec db psql -U postgres -f /docker-entrypoint-initdb.d/XX-migration.sql
```

### Migration Workflow

1. **Create Migration File:**
   ```bash
   # In volumes/db/init/
   touch XX-description.sql
   ```

2. **Test Migration:**
   ```bash
   docker compose exec db psql -U postgres -f /docker-entrypoint-initdb.d/XX-description.sql
   ```

3. **Verify:**
   ```bash
   docker compose exec db psql -U postgres -c "\dt"  # List tables
   docker compose exec db psql -U postgres -c "\df"  # List functions
   ```

**Note:** Migration files run automatically on fresh database initialization.

### Deployment Checklist

- [ ] Update `.env` with production secrets
- [ ] Verify `POSTGRES_PASSWORD` is strong (32+ chars)
- [ ] Verify `JWT_SECRET` is unique (32+ chars)
- [ ] Set `MSG91_AUTH_KEY` for production SMS
- [ ] Verify database port bindings are localhost-only
- [ ] Run `./start-masala.sh` for full validation
- [ ] Check `docker compose ps` - all services healthy
- [ ] Test Kong routes: `curl http://localhost:8100/rest/v1/`
- [ ] Test Studio access: `http://localhost:54424`

### Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Storage keeps restarting | Missing superuser permission | `ALTER ROLE supabase_storage_admin WITH SUPERUSER;` |
| JWT errors (401) | Secret mismatch | Verify `JWT_SECRET` matches across all services |
| Rate limit errors | Exceeded OTP limits | Check `otp_rate_limits`, `ip_rate_limits` tables |
| Functions not loading | File permission | Check `volumes/functions/` ownership |
| Kong 502 errors | Backend not ready | Wait for `db` healthy, restart Kong |
| Studio login fails | Wrong credentials | Check `DASHBOARD_USERNAME/PASSWORD` |

### Log Locations

| Service | Log Access |
|---------|------------|
| Startup Script | `logs/startup-YYYYMMDD.log` |
| All Services | `docker compose logs` |
| PostgreSQL | `docker compose logs db` |
| Edge Functions | `docker compose logs functions` |
| Kong Gateway | `docker compose logs kong` |

### Health Endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /functions/v1/health` | Edge functions health |
| `GET /rest/v1/` | PostgREST health |
| `curl -I localhost:8100` | Kong health |

---

## 11. Performance Optimizations & Migration Guide

This section documents all performance optimizations applied to the Masala stack. When migrating to a new server/VPS, these optimizations must be carried over to maintain performance.

### Migration Checklist

**What to Backup:**
- `.env` file (all environment variables)
- `docker-compose.yml` (contains PostgreSQL tuning, resource limits)
- `volumes/api/kong.yml` (contains rate limiting, caching configuration)
- `volumes/db/init/*.sql` (all database migrations including performance indexes)
- `volumes/functions/` (edge functions with cached clients)
- `masala_db-config` volume (PostgreSQL data)
- `masala_storage` volume (uploaded files)

**What to Apply on New Server:**
1. Run database migrations (SQL scripts in `volumes/db/init/`)
2. Verify docker-compose.yml has PostgreSQL memory tuning
3. Verify kong.yml has rate limiting and proxy-cache plugins
4. Verify container resource limits are set
5. Run post-migration verification commands

---

### Database Migrations (SQL Scripts)

Located in `volumes/db/init/`:

| Script | Purpose | Impact |
|--------|---------|--------|
| `33-performance-indexes.sql` | Performance indexes | HIGH |
| `34-rls-optimization.sql` | RLS policy fixes | HIGH |
| `35-function-optimization.sql` | SQL function fixes | MEDIUM |
| `36-pg-stat-statements.sql` | Query monitoring | LOW |

#### 33-performance-indexes.sql

Creates critical indexes for query performance:

| Index | Table | Purpose |
|-------|-------|---------|
| `idx_order_items_product` | order_items | FK lookups for order/product JOINs |
| `idx_cart_items_user_product_weight` | cart_items | Cart operations (10-50x speedup) |
| `idx_status_history_order_created` | order_status_history | Order timeline queries |
| `idx_products_available_active` | products | Partial index for catalog queries |
| `idx_products_category_available` | products | Browse by category |
| `idx_orders_user_status` | orders | User order listing |
| `idx_orders_status_created` | orders | Admin dashboard queries |
| `idx_orders_delivery_staff_status` | orders | Delivery staff queries |

#### 34-rls-optimization.sql

Fixes RLS policy performance issues:

- **Subselect wrapping**: Wraps `auth.uid()` in `(select ...)` for initPlan caching
- **SECURITY DEFINER helpers**: Avoids nested RLS evaluation in cross-table policies
- **Optimized policies**: cart_items, shiprocket_shipments

#### 35-function-optimization.sql

Optimizes SQL functions:

- **get_orders()**: Fixed N+1 query with LEFT JOIN aggregation
- **ensure_single_default_address()**: Added WHERE clause to limit scanned rows
- **check_rate_limits_combined()**: Single call for phone + IP rate limits

#### 36-pg-stat-statements.sql

Enables query performance monitoring:

```sql
-- View slow queries
SELECT * FROM public.slow_queries;

-- Get performance summary
SELECT * FROM public.get_query_performance_summary();

-- Reset stats after optimization
SELECT public.reset_query_stats();
```

---

### PostgreSQL Configuration (docker-compose.yml)

Memory tuning for 2GB+ RAM servers:

```yaml
db:
  command:
    - postgres
    # Memory Tuning
    - -c
    - shared_buffers=256MB        # 25% of available RAM
    - -c
    - effective_cache_size=768MB  # 75% of available RAM
    - -c
    - work_mem=16MB               # Per-operation memory
    - -c
    - maintenance_work_mem=128MB  # For VACUUM, CREATE INDEX
    # WAL Settings
    - -c
    - max_wal_size=2GB
    - -c
    - checkpoint_completion_target=0.9
    # Slow Query Logging (queries > 1 second)
    - -c
    - log_min_duration_statement=1000
    # Query Monitoring
    - -c
    - shared_preload_libraries=pg_stat_statements
    - -c
    - pg_stat_statements.track=all
```

---

### Connection Pooling Settings

#### PostgREST Pool Configuration

```yaml
rest:
  environment:
    PGRST_DB_POOL: "20"                      # Max connections
    PGRST_DB_POOL_ACQUISITION_TIMEOUT: "10"  # Wait time for connection
    PGRST_DB_POOL_MAX_IDLETIME: "30"         # Idle connection timeout
    PGRST_DB_MAX_ROWS: "1000"                # Max rows per request
```

#### Supavisor Pool Configuration

```yaml
supavisor:
  environment:
    DB_POOL_SIZE: "20"           # Connections per pool
    POOL_IDLE_TIMEOUT: "30000"   # 30 seconds idle timeout
```

---

### Kong Gateway Optimizations

Located in `volumes/api/kong.yml`:

#### Rate Limiting

| Route | Limit | Purpose |
|-------|-------|---------|
| `/rest/v1/` | 120/minute | Database REST API |
| `/rest/v1/rpc/` | 60/minute | RPC calls |
| `/functions/v1/` | 60/minute | Edge functions |
| `/storage/v1/` | 100/minute | Authenticated storage |
| `/pg/` | 30/minute | Admin meta API |

Configuration example:
```yaml
- name: rate-limiting
  config:
    minute: 120
    policy: local
    hide_client_headers: false
```

#### Proxy Cache for Images

Caches public storage objects (1 hour TTL):

```yaml
- name: proxy-cache
  config:
    response_code: [200]
    request_method: [GET, HEAD]
    content_type:
      - image/png
      - image/jpeg
      - image/webp
      - image/gif
      - image/svg+xml
    cache_ttl: 3600
    strategy: memory
```

Applied to routes:
- `/storage/v1/object/public/`
- `/storage/v1/render/image/public/`

#### Request Correlation IDs

Enables request tracking for debugging:

```yaml
- name: correlation-id
  config:
    header_name: X-Request-ID
    generator: uuid
    echo_downstream: true
```

---

### Container Resource Limits

All containers have resource limits to prevent runaway resource usage:

| Service | CPU Limit | Memory Limit | CPU Reserved | Memory Reserved |
|---------|-----------|--------------|--------------|-----------------|
| db | 2 cores | 2 GB | 0.5 cores | 512 MB |
| kong | 1 core | 512 MB | 0.25 cores | 128 MB |
| rest | 1 core | 512 MB | 0.25 cores | 128 MB |
| storage | - | - | - | - |
| imgproxy | 1 core | 512 MB | 0.25 cores | 128 MB |
| functions | 1 core | 512 MB | 0.25 cores | 128 MB |
| supavisor | 1 core | 512 MB | 0.25 cores | 128 MB |

Configuration example:
```yaml
deploy:
  resources:
    limits:
      cpus: '1'
      memory: 512M
    reservations:
      cpus: '0.25'
      memory: 128M
```

---

### Health Check Optimization

Health check intervals increased from 5s to 30s to reduce overhead:

| Service | Interval | Timeout | Retries |
|---------|----------|---------|---------|
| db | 30s | 10s | 5 |
| storage | 30s | 10s | 3 |
| imgproxy | 30s | 10s | 3 |
| supavisor | 30s | 10s | 3 |
| studio | 10s | 5s | 3 |

---

### Edge Function Optimizations

**Note:** These are in the codebase and migrate with git.

Located in `volumes/functions/_shared/`:

#### Cached Supabase Clients (`auth.ts`)

```typescript
// Module-level cached clients (reused across requests)
let cachedServiceClient: SupabaseClient | null = null;
let cachedCryptoKey: CryptoKey | null = null;

// Crypto key cached for JWT signing/verification
async function getCryptoKey(): Promise<CryptoKey> {
  if (cachedCryptoKey) return cachedCryptoKey;
  // ... import key once, cache forever
}
```

#### Response Helpers (`response.ts`)

Centralized JSON/error response functions with proper CORS headers.

#### Push Notification Batching (`push.ts`)

Expo push notifications sent in batches of 100 with automatic invalid token cleanup.

---

### Post-Migration Verification

#### Verify Indexes Exist

```bash
docker compose exec db psql -U postgres -c "
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE indexname LIKE 'idx_%'
ORDER BY tablename, indexname;
"
```

#### Check pg_stat_statements

```bash
docker compose exec db psql -U postgres -c "
SELECT * FROM public.slow_queries LIMIT 10;
"
```

#### Verify Container Resource Limits

```bash
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
```

#### Test Rate Limiting

```bash
# Should return rate limit headers
curl -I http://localhost:8100/rest/v1/ \
  -H "apikey: YOUR_ANON_KEY"

# Check for headers:
# X-RateLimit-Limit-Minute: 120
# X-RateLimit-Remaining-Minute: 119
```

#### Verify PostgreSQL Settings

```bash
docker compose exec db psql -U postgres -c "
SELECT name, setting, unit
FROM pg_settings
WHERE name IN ('shared_buffers', 'work_mem', 'effective_cache_size',
               'maintenance_work_mem', 'max_wal_size',
               'log_min_duration_statement');
"
```

#### Check Kong Plugins

```bash
docker compose exec kong kong config parse /home/kong/kong.yml 2>&1 | head -20
```

---

### Performance Optimization Summary

| Category | Items | Location |
|----------|-------|----------|
| Database Indexes | 12 indexes | `33-performance-indexes.sql` |
| RLS Policies | 6 policy fixes | `34-rls-optimization.sql` |
| SQL Functions | 4 function fixes | `35-function-optimization.sql` |
| Query Monitoring | pg_stat_statements | `36-pg-stat-statements.sql` |
| PostgreSQL Tuning | 6 settings | `docker-compose.yml` |
| Connection Pooling | PostgREST + Supavisor | `docker-compose.yml` |
| Rate Limiting | 5 route limits | `kong.yml` |
| Proxy Caching | 2 cache rules | `kong.yml` |
| Request Tracking | correlation-id plugin | `kong.yml` |
| Resource Limits | 6 containers | `docker-compose.yml` |
| Health Checks | 5 optimized intervals | `docker-compose.yml` |
| Edge Functions | Cached clients, batching | `volumes/functions/_shared/` |

**Total: 40+ optimization items**

---

## Document Info

- **Version:** 1.0
- **Last Updated:** 2025-02-04
- **Stack Version:** Masala MVP v1
- **Maintainer:** Backend Team
