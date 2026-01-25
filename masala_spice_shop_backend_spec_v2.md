# Masala Spice Shop - Backend Specification v2.0 (MVP)

> **Purpose:** Simplified MVP backend for a React Native spice ordering app.
> 
> **Version:** 2.0 - MVP: No inventory tracking, admin-controlled availability
>
> **Related Document:** `masala_spice_shop_frontend_spec_v2.md`
>
> ⚠️ **MVP SCOPE:** No stock management. Admin toggles product availability. Simple order flow.

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Backend | Self-hosted Supabase (Docker) |
| Database | PostgreSQL 15+ |
| API | PostgREST + Edge Functions (Deno) |
| Auth | Custom OTP + JWT |
| Storage | Supabase Storage |
| SMS | MSG91 |
| Push | FCM |

---

## Database Schema

### Enums

```sql
CREATE TYPE user_role AS ENUM ('super_admin', 'admin', 'delivery_staff', 'customer');

CREATE TYPE order_status AS ENUM (
  'placed',
  'confirmed',
  'out_for_delivery',
  'delivered',
  'cancelled',
  'delivery_failed'
);
```

---

### users

```sql
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone VARCHAR(15) UNIQUE NOT NULL,
  name VARCHAR(100),
  role user_role DEFAULT 'customer',
  language VARCHAR(5) DEFAULT 'en',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_role ON users(role);
```

### otp_requests

```sql
CREATE TABLE otp_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone VARCHAR(15) NOT NULL,
  otp_hash VARCHAR(255) NOT NULL,
  attempts INTEGER DEFAULT 0,
  expires_at TIMESTAMPTZ NOT NULL,
  verified BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_otp_phone_expires ON otp_requests(phone, expires_at DESC);
```

### refresh_tokens

```sql
CREATE TABLE refresh_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash VARCHAR(255) NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_refresh_user ON refresh_tokens(user_id);
```

### push_tokens

```sql
CREATE TABLE push_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  platform VARCHAR(10) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, token)
);
```

---

### categories

```sql
CREATE TABLE categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name_en VARCHAR(100) NOT NULL,
  name_gu VARCHAR(100) NOT NULL,
  image_url TEXT,
  sort_order INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_categories_sort ON categories(is_active, sort_order);
```

### products

```sql
CREATE TABLE products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID NOT NULL REFERENCES categories(id),
  name_en VARCHAR(150) NOT NULL,
  name_gu VARCHAR(150) NOT NULL,
  description_en TEXT,
  description_gu TEXT,
  image_url TEXT,
  is_available BOOLEAN DEFAULT true,  -- Admin toggles this
  sort_order INTEGER DEFAULT 0,
  search_text TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_products_available ON products(is_available, sort_order);
CREATE INDEX idx_products_search ON products USING gin(to_tsvector('simple', search_text));

-- Auto-update search text
CREATE OR REPLACE FUNCTION update_product_search()
RETURNS TRIGGER AS $$
BEGIN
  NEW.search_text := LOWER(COALESCE(NEW.name_en,'') || ' ' || COALESCE(NEW.name_gu,''));
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_product_search
BEFORE INSERT OR UPDATE ON products
FOR EACH ROW EXECUTE FUNCTION update_product_search();
```

### weight_options

```sql
CREATE TABLE weight_options (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  weight_grams INTEGER NOT NULL,
  weight_label VARCHAR(20) NOT NULL,  -- "100g", "250g", "500g"
  price_paise INTEGER NOT NULL,
  is_available BOOLEAN DEFAULT true,
  sort_order INTEGER DEFAULT 0
);

CREATE INDEX idx_weight_product ON weight_options(product_id, sort_order);
```

---

### user_addresses

```sql
CREATE TABLE user_addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  address_line1 VARCHAR(255) NOT NULL,
  address_line2 VARCHAR(255),
  city VARCHAR(100) NOT NULL,
  pincode VARCHAR(10) NOT NULL,
  is_default BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_addresses_user ON user_addresses(user_id);
```

### favorites

```sql
CREATE TABLE favorites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, product_id)
);

CREATE INDEX idx_favorites_user ON favorites(user_id);
```

---

### orders

```sql
CREATE TABLE orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_number VARCHAR(20) UNIQUE NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id),
  delivery_staff_id UUID REFERENCES users(id),
  status order_status DEFAULT 'placed',
  
  -- Amounts (paise)
  subtotal_paise INTEGER NOT NULL,
  shipping_paise INTEGER NOT NULL,
  total_paise INTEGER NOT NULL,
  
  -- Address snapshot
  address_line1 VARCHAR(255) NOT NULL,
  address_line2 VARCHAR(255),
  city VARCHAR(100) NOT NULL,
  pincode VARCHAR(10) NOT NULL,
  
  order_notes TEXT,
  delivery_otp VARCHAR(4),
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_orders_user ON orders(user_id, created_at DESC);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_delivery ON orders(delivery_staff_id) WHERE delivery_staff_id IS NOT NULL;
```

### order_items

```sql
CREATE TABLE order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id),
  weight_option_id UUID NOT NULL REFERENCES weight_options(id),
  
  -- Snapshot at order time
  product_name_en VARCHAR(150) NOT NULL,
  product_name_gu VARCHAR(150) NOT NULL,
  weight_label VARCHAR(20) NOT NULL,
  quantity INTEGER NOT NULL,
  unit_price_paise INTEGER NOT NULL,
  total_price_paise INTEGER NOT NULL
);

CREATE INDEX idx_order_items_order ON order_items(order_id);
```

### order_status_history

```sql
CREATE TABLE order_status_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  from_status order_status,
  to_status order_status NOT NULL,
  changed_by UUID REFERENCES users(id),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_history_order ON order_status_history(order_id);
```

---

### app_settings

```sql
CREATE TABLE app_settings (
  key VARCHAR(100) PRIMARY KEY,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO app_settings (key, value) VALUES
('shipping_charge_paise', '4000'),
('free_shipping_threshold_paise', '50000'),
('serviceable_pincodes', '["380001","380002","380003","380004","380005","380006","380007","380008","380009"]');
```

### daily_order_counters

```sql
CREATE TABLE daily_order_counters (
  date DATE PRIMARY KEY,
  counter INTEGER DEFAULT 0
);

CREATE OR REPLACE FUNCTION generate_order_number()
RETURNS VARCHAR(20) AS $$
DECLARE
  today DATE := CURRENT_DATE;
  seq INTEGER;
BEGIN
  INSERT INTO daily_order_counters (date, counter) VALUES (today, 1)
  ON CONFLICT (date) DO UPDATE SET counter = daily_order_counters.counter + 1
  RETURNING counter INTO seq;
  
  RETURN 'MSS-' || TO_CHAR(today, 'YYYYMMDD') || '-' || LPAD(seq::TEXT, 3, '0');
END;
$$ LANGUAGE plpgsql;
```

---

## Seed Data

```sql
-- Categories
INSERT INTO categories (name_en, name_gu, sort_order) VALUES
('Regular Spices', 'નિયમિત મસાલા', 1),
('Special Powders', 'વિશેષ પાવડર', 2),
('Masala Mixes', 'મસાલા મિશ્રણ', 3),
('Whole Spices', 'આખા મસાલા', 4);

-- First Admin (replace phone)
INSERT INTO users (phone, name, role) VALUES ('+919876543210', 'Shop Owner', 'super_admin');

-- Sample Product
DO $$
DECLARE cat_id UUID; prod_id UUID;
BEGIN
  SELECT id INTO cat_id FROM categories WHERE name_en = 'Regular Spices';
  
  INSERT INTO products (category_id, name_en, name_gu, description_en, is_available)
  VALUES (cat_id, 'Turmeric Powder', 'હળદર પાવડર', 'Fresh ground turmeric', true)
  RETURNING id INTO prod_id;
  
  INSERT INTO weight_options (product_id, weight_grams, weight_label, price_paise, sort_order) VALUES
  (prod_id, 50, '50g', 2500, 1),
  (prod_id, 100, '100g', 4500, 2),
  (prod_id, 250, '250g', 11000, 3);
END $$;
```

---

## Row Level Security

### Enable RLS

```sql
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE weight_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE favorites ENABLE ROW LEVEL SECURITY;
ALTER TABLE push_tokens ENABLE ROW LEVEL SECURITY;
```

### Auth Helpers

```sql
CREATE OR REPLACE FUNCTION auth.uid() RETURNS UUID AS $$
  SELECT NULLIF(current_setting('request.jwt.claims', true)::json->>'sub', '')::UUID;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION auth.role() RETURNS user_role AS $$
  SELECT (current_setting('request.jwt.claims', true)::json->>'role')::user_role;
$$ LANGUAGE SQL STABLE;

CREATE OR REPLACE FUNCTION auth.is_admin() RETURNS BOOLEAN AS $$
  SELECT auth.role() IN ('admin', 'super_admin');
$$ LANGUAGE SQL STABLE;
```

### Policies

```sql
-- Public: read active categories
CREATE POLICY "categories_read" ON categories FOR SELECT USING (is_active = true);

-- Public: read available products
CREATE POLICY "products_read" ON products FOR SELECT USING (is_available = true);

-- Public: read weight options for available products
CREATE POLICY "weights_read" ON weight_options FOR SELECT USING (
  is_available = true AND 
  EXISTS (SELECT 1 FROM products p WHERE p.id = product_id AND p.is_available = true)
);

-- Users: own profile
CREATE POLICY "users_self" ON users FOR SELECT USING (id = auth.uid());
CREATE POLICY "users_update" ON users FOR UPDATE USING (id = auth.uid());

-- Users: own addresses
CREATE POLICY "addresses_self" ON user_addresses FOR ALL USING (user_id = auth.uid());

-- Users: own favorites
CREATE POLICY "favorites_self" ON favorites FOR ALL USING (user_id = auth.uid());

-- Users: own orders
CREATE POLICY "orders_user" ON orders FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "order_items_user" ON order_items FOR SELECT USING (
  EXISTS (SELECT 1 FROM orders o WHERE o.id = order_id AND o.user_id = auth.uid())
);

-- Users: own push tokens
CREATE POLICY "push_self" ON push_tokens FOR ALL USING (user_id = auth.uid());

-- Admin: all products
CREATE POLICY "products_admin" ON products FOR ALL USING (auth.is_admin());
CREATE POLICY "weights_admin" ON weight_options FOR ALL USING (auth.is_admin());
CREATE POLICY "categories_admin" ON categories FOR ALL USING (auth.is_admin());

-- Admin: all orders
CREATE POLICY "orders_admin" ON orders FOR SELECT USING (auth.is_admin());
CREATE POLICY "order_items_admin" ON order_items FOR SELECT USING (auth.is_admin());

-- Admin: all users
CREATE POLICY "users_admin" ON users FOR SELECT USING (auth.is_admin());

-- Delivery: assigned orders
CREATE POLICY "orders_delivery" ON orders FOR SELECT USING (
  auth.role() = 'delivery_staff' AND delivery_staff_id = auth.uid()
);
CREATE POLICY "order_items_delivery" ON order_items FOR SELECT USING (
  EXISTS (SELECT 1 FROM orders o WHERE o.id = order_id AND o.delivery_staff_id = auth.uid())
);
```

---

## Edge Functions

### send-otp

```typescript
// supabase/functions/send-otp/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const { phone } = await req.json()
  
  const cleanPhone = phone.replace(/\D/g, '').slice(-10)
  if (!/^[6-9]\d{9}$/.test(cleanPhone)) {
    return Response.json({ error: 'AUTH_001', message: 'Invalid phone number' }, { status: 400 })
  }
  
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  
  const otp = Math.floor(100000 + Math.random() * 900000).toString()
  const fullPhone = '+91' + cleanPhone
  
  // Hash OTP
  const encoder = new TextEncoder()
  const data = encoder.encode(otp + Deno.env.get('OTP_SECRET'))
  const hashBuffer = await crypto.subtle.digest('SHA-256', data)
  const otpHash = Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2,'0')).join('')
  
  // Store
  await supabase.from('otp_requests').insert({
    phone: fullPhone,
    otp_hash: otpHash,
    expires_at: new Date(Date.now() + 5 * 60 * 1000).toISOString()
  })
  
  // Send SMS via MSG91
  await fetch('https://api.msg91.com/api/v5/flow/', {
    method: 'POST',
    headers: { 'authkey': Deno.env.get('MSG91_AUTH_KEY')!, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      template_id: Deno.env.get('MSG91_OTP_TEMPLATE'),
      mobile: '91' + cleanPhone,
      OTP: otp
    })
  })
  
  return Response.json({ success: true, expires_in: 300 })
})
```

### verify-otp

```typescript
// supabase/functions/verify-otp/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { create } from "https://deno.land/x/djwt@v2.8/mod.ts"

serve(async (req) => {
  const { phone, otp } = await req.json()
  
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  
  const cleanPhone = phone.replace(/\D/g, '').slice(-10)
  const fullPhone = '+91' + cleanPhone
  
  // Hash input OTP
  const encoder = new TextEncoder()
  const data = encoder.encode(otp + Deno.env.get('OTP_SECRET'))
  const hashBuffer = await crypto.subtle.digest('SHA-256', data)
  const otpHash = Array.from(new Uint8Array(hashBuffer)).map(b => b.toString(16).padStart(2,'0')).join('')
  
  // Find valid OTP
  const { data: record } = await supabase
    .from('otp_requests')
    .select('*')
    .eq('phone', fullPhone)
    .eq('otp_hash', otpHash)
    .eq('verified', false)
    .gt('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false })
    .limit(1)
    .single()
  
  if (!record) {
    const { data: expired } = await supabase
      .from('otp_requests')
      .select('expires_at')
      .eq('phone', fullPhone)
      .eq('verified', false)
      .order('created_at', { ascending: false })
      .limit(1)
      .single()
    
    if (expired && new Date(expired.expires_at) < new Date()) {
      return Response.json({ error: 'AUTH_002', message: 'OTP expired' }, { status: 400 })
    }
    return Response.json({ error: 'AUTH_003', message: 'Invalid OTP' }, { status: 400 })
  }
  
  // Mark verified
  await supabase.from('otp_requests').update({ verified: true }).eq('id', record.id)
  
  // Find or create user
  let { data: user } = await supabase.from('users').select('*').eq('phone', fullPhone).single()
  const isNewUser = !user
  
  if (!user) {
    const { data: newUser } = await supabase.from('users').insert({ phone: fullPhone }).select().single()
    user = newUser
  }
  
  // Generate JWT
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(Deno.env.get('JWT_SECRET')),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  )
  
  const accessToken = await create(
    { alg: "HS256", typ: "JWT" },
    { sub: user.id, role: user.role, exp: Math.floor(Date.now()/1000) + 3600 },
    key
  )
  
  // Refresh token
  const refreshToken = crypto.randomUUID()
  const rtData = encoder.encode(refreshToken + Deno.env.get('OTP_SECRET'))
  const rtHash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', rtData))).map(b => b.toString(16).padStart(2,'0')).join('')
  
  await supabase.from('refresh_tokens').insert({
    user_id: user.id,
    token_hash: rtHash,
    expires_at: new Date(Date.now() + 30*24*60*60*1000).toISOString()
  })
  
  return Response.json({
    access_token: accessToken,
    refresh_token: refreshToken,
    user: { id: user.id, phone: user.phone, name: user.name, role: user.role, language: user.language },
    is_new_user: isNewUser
  })
})
```

### checkout

```typescript
// supabase/functions/checkout/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { verify } from "https://deno.land/x/djwt@v2.8/mod.ts"

serve(async (req) => {
  // Verify JWT
  const token = req.headers.get('Authorization')?.replace('Bearer ', '')
  if (!token) return Response.json({ error: 'Unauthorized' }, { status: 401 })
  
  let user
  try {
    const key = await crypto.subtle.importKey(
      "raw", new TextEncoder().encode(Deno.env.get('JWT_SECRET')),
      { name: "HMAC", hash: "SHA-256" }, false, ["verify"]
    )
    user = await verify(token, key)
  } catch {
    return Response.json({ error: 'Invalid token' }, { status: 401 })
  }
  
  const { items, address, order_notes } = await req.json()
  // items: [{ product_id, weight_option_id, quantity }]
  
  if (!items?.length) {
    return Response.json({ error: 'CHECKOUT_001', message: 'Cart is empty' }, { status: 400 })
  }
  
  if (!address?.address_line1 || !address?.pincode) {
    return Response.json({ error: 'CHECKOUT_002', message: 'Address required' }, { status: 400 })
  }
  
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  
  // Get settings
  const { data: settings } = await supabase.from('app_settings').select('key, value')
  const config: Record<string, any> = {}
  settings?.forEach((s: any) => config[s.key] = JSON.parse(s.value))
  
  // Check pincode
  if (!config.serviceable_pincodes?.includes(address.pincode)) {
    return Response.json({ error: 'CHECKOUT_003', message: 'Area not serviceable' }, { status: 400 })
  }
  
  // Build order items
  let subtotal = 0
  const orderItems = []
  
  for (const item of items) {
    const { data: product } = await supabase
      .from('products')
      .select('*, weight_options(*)')
      .eq('id', item.product_id)
      .eq('is_available', true)
      .single()
    
    if (!product) continue
    
    const wo = product.weight_options.find((w: any) => w.id === item.weight_option_id && w.is_available)
    if (!wo) continue
    
    const lineTotal = wo.price_paise * item.quantity
    subtotal += lineTotal
    
    orderItems.push({
      product_id: product.id,
      weight_option_id: wo.id,
      product_name_en: product.name_en,
      product_name_gu: product.name_gu,
      weight_label: wo.weight_label,
      quantity: item.quantity,
      unit_price_paise: wo.price_paise,
      total_price_paise: lineTotal
    })
  }
  
  if (!orderItems.length) {
    return Response.json({ error: 'CHECKOUT_001', message: 'No valid items' }, { status: 400 })
  }
  
  // Calculate shipping
  const shipping = subtotal >= (config.free_shipping_threshold_paise || 50000) ? 0 : (config.shipping_charge_paise || 4000)
  const total = subtotal + shipping
  
  // Generate order number and OTP
  const { data: orderNumber } = await supabase.rpc('generate_order_number')
  const deliveryOtp = Math.floor(1000 + Math.random() * 9000).toString()
  
  // Create order
  const { data: order, error: err } = await supabase
    .from('orders')
    .insert({
      order_number: orderNumber,
      user_id: user.sub,
      subtotal_paise: subtotal,
      shipping_paise: shipping,
      total_paise: total,
      address_line1: address.address_line1,
      address_line2: address.address_line2 || null,
      city: address.city,
      pincode: address.pincode,
      order_notes,
      delivery_otp: deliveryOtp
    })
    .select()
    .single()
  
  if (err) return Response.json({ error: 'Order failed' }, { status: 500 })
  
  // Create items
  await supabase.from('order_items').insert(orderItems.map(i => ({ ...i, order_id: order.id })))
  
  // Status history
  await supabase.from('order_status_history').insert({
    order_id: order.id, to_status: 'placed', changed_by: user.sub
  })
  
  // Save address
  await supabase.from('user_addresses').upsert({
    user_id: user.sub,
    address_line1: address.address_line1,
    address_line2: address.address_line2,
    city: address.city,
    pincode: address.pincode,
    is_default: true
  })
  
  // Push notification
  await sendPush(user.sub, 'Order Placed!', `Order ${orderNumber}. Total: ₹${total/100}`, supabase)
  
  return Response.json({ order_id: order.id, order_number: orderNumber, total_paise: total })
})

async function sendPush(userId: string, title: string, body: string, supabase: any) {
  const { data: tokens } = await supabase.from('push_tokens').select('token').eq('user_id', userId)
  for (const { token } of tokens || []) {
    await fetch('https://fcm.googleapis.com/fcm/send', {
      method: 'POST',
      headers: { 'Authorization': `key=${Deno.env.get('FCM_SERVER_KEY')}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ to: token, notification: { title, body } })
    })
  }
}
```

### update-order-status

```typescript
// supabase/functions/update-order-status/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const TRANSITIONS: Record<string, string[]> = {
  placed: ['confirmed', 'cancelled'],
  confirmed: ['out_for_delivery', 'cancelled'],
  out_for_delivery: ['delivered', 'delivery_failed', 'cancelled'],
  delivery_failed: ['out_for_delivery', 'cancelled'],
  delivered: [],
  cancelled: []
}

serve(async (req) => {
  const user = await requireAdmin(req)
  if (!user) return Response.json({ error: 'Unauthorized' }, { status: 401 })
  
  const { order_id, new_status, delivery_staff_id } = await req.json()
  
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  
  const { data: order } = await supabase.from('orders').select('*').eq('id', order_id).single()
  if (!order) return Response.json({ error: 'Order not found' }, { status: 404 })
  
  if (!TRANSITIONS[order.status]?.includes(new_status)) {
    return Response.json({ error: 'Invalid status transition' }, { status: 400 })
  }
  
  // If going out_for_delivery, need delivery staff
  const updates: any = { status: new_status, updated_at: new Date().toISOString() }
  if (new_status === 'out_for_delivery' && delivery_staff_id) {
    updates.delivery_staff_id = delivery_staff_id
  }
  
  await supabase.from('orders').update(updates).eq('id', order_id)
  
  await supabase.from('order_status_history').insert({
    order_id, from_status: order.status, to_status: new_status, changed_by: user.sub
  })
  
  // Notify customer
  const messages: Record<string, string> = {
    confirmed: 'Your order has been confirmed!',
    out_for_delivery: `Your order is on the way! OTP: ${order.delivery_otp}`,
    delivered: 'Your order has been delivered!',
    cancelled: 'Your order has been cancelled.'
  }
  
  if (messages[new_status]) {
    await sendPush(order.user_id, `Order ${order.order_number}`, messages[new_status], supabase)
    
    if (new_status === 'out_for_delivery') {
      // SMS with OTP
      const { data: u } = await supabase.from('users').select('phone').eq('id', order.user_id).single()
      await sendSMS(u.phone, `Order ${order.order_number} is out for delivery. OTP: ${order.delivery_otp}`)
    }
  }
  
  // Notify delivery staff if assigned
  if (new_status === 'out_for_delivery' && delivery_staff_id) {
    await sendPush(delivery_staff_id, 'New Delivery', `Order ${order.order_number} assigned`, supabase)
  }
  
  return Response.json({ success: true })
})
```

### verify-delivery-otp

```typescript
// supabase/functions/verify-delivery-otp/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const user = await requireDeliveryStaff(req)
  if (!user) return Response.json({ error: 'Unauthorized' }, { status: 401 })
  
  const { order_id, otp } = await req.json()
  
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  
  const { data: order } = await supabase
    .from('orders')
    .select('*')
    .eq('id', order_id)
    .eq('delivery_staff_id', user.sub)
    .eq('status', 'out_for_delivery')
    .single()
  
  if (!order) return Response.json({ error: 'Order not found' }, { status: 404 })
  
  if (order.delivery_otp !== otp) {
    return Response.json({ error: 'DELIVERY_001', message: 'Invalid OTP' }, { status: 400 })
  }
  
  await supabase.from('orders').update({ status: 'delivered', updated_at: new Date().toISOString() }).eq('id', order_id)
  
  await supabase.from('order_status_history').insert({
    order_id, from_status: 'out_for_delivery', to_status: 'delivered', changed_by: user.sub
  })
  
  await sendPush(order.user_id, 'Delivered!', `Order ${order.order_number} delivered. Thank you!`, supabase)
  
  return Response.json({ success: true })
})
```

### mark-delivery-failed

```typescript
// supabase/functions/mark-delivery-failed/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const user = await requireDeliveryStaff(req)
  if (!user) return Response.json({ error: 'Unauthorized' }, { status: 401 })
  
  const { order_id, reason } = await req.json()
  
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  
  const { data: order } = await supabase
    .from('orders')
    .select('*')
    .eq('id', order_id)
    .eq('delivery_staff_id', user.sub)
    .eq('status', 'out_for_delivery')
    .single()
  
  if (!order) return Response.json({ error: 'Order not found' }, { status: 404 })
  
  await supabase.from('orders').update({ 
    status: 'delivery_failed', 
    delivery_staff_id: null,
    updated_at: new Date().toISOString() 
  }).eq('id', order_id)
  
  await supabase.from('order_status_history').insert({
    order_id, from_status: 'out_for_delivery', to_status: 'delivery_failed', changed_by: user.sub, notes: reason
  })
  
  await sendPush(order.user_id, 'Delivery Issue', `We couldn't deliver order ${order.order_number}. We'll retry.`, supabase)
  
  return Response.json({ success: true })
})
```

### reorder

```typescript
// supabase/functions/reorder/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

serve(async (req) => {
  const user = await requireAuth(req)
  if (!user) return Response.json({ error: 'Unauthorized' }, { status: 401 })
  
  const { order_id } = await req.json()
  
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  
  // Get order items
  const { data: items } = await supabase
    .from('order_items')
    .select('product_id, weight_option_id, quantity')
    .eq('order_id', order_id)
  
  if (!items?.length) {
    return Response.json({ error: 'Order not found' }, { status: 404 })
  }
  
  // Filter to available items
  const cartItems = []
  for (const item of items) {
    const { data: product } = await supabase
      .from('products')
      .select('id, is_available, weight_options(id, is_available)')
      .eq('id', item.product_id)
      .single()
    
    if (product?.is_available) {
      const wo = product.weight_options?.find((w: any) => w.id === item.weight_option_id && w.is_available)
      if (wo) {
        cartItems.push({ product_id: item.product_id, weight_option_id: item.weight_option_id, quantity: item.quantity })
      }
    }
  }
  
  return Response.json({ items: cartItems, unavailable_count: items.length - cartItems.length })
})
```

---

## Shared Auth Helpers

```typescript
// supabase/functions/_shared/auth.ts
import { verify } from "https://deno.land/x/djwt@v2.8/mod.ts"

export async function requireAuth(req: Request) {
  const token = req.headers.get('Authorization')?.replace('Bearer ', '')
  if (!token) return null
  try {
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(Deno.env.get('JWT_SECRET')), { name: "HMAC", hash: "SHA-256" }, false, ["verify"])
    return await verify(token, key)
  } catch { return null }
}

export async function requireAdmin(req: Request) {
  const user = await requireAuth(req)
  if (!user || !['admin', 'super_admin'].includes(user.role as string)) return null
  return user
}

export async function requireDeliveryStaff(req: Request) {
  const user = await requireAuth(req)
  if (!user || user.role !== 'delivery_staff') return null
  return user
}

export async function sendPush(userId: string, title: string, body: string, supabase: any) {
  const { data: tokens } = await supabase.from('push_tokens').select('token').eq('user_id', userId)
  for (const { token } of tokens || []) {
    await fetch('https://fcm.googleapis.com/fcm/send', {
      method: 'POST',
      headers: { 'Authorization': `key=${Deno.env.get('FCM_SERVER_KEY')}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ to: token, notification: { title, body } })
    })
  }
}

export async function sendSMS(phone: string, message: string) {
  await fetch('https://api.msg91.com/api/v5/flow/', {
    method: 'POST',
    headers: { 'authkey': Deno.env.get('MSG91_AUTH_KEY')!, 'Content-Type': 'application/json' },
    body: JSON.stringify({ template_id: Deno.env.get('MSG91_TEMPLATE'), mobile: phone.replace('+', ''), message })
  })
}
```

---

## API Summary

### Public
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/functions/v1/send-otp` | Send OTP |
| POST | `/functions/v1/verify-otp` | Verify & login |

### Customer
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/rest/v1/categories?is_active=eq.true` | Categories |
| GET | `/rest/v1/products?is_available=eq.true&select=*,weight_options(*)` | Products |
| GET | `/rest/v1/orders?order=created_at.desc` | My orders |
| GET | `/rest/v1/favorites` | My favorites |
| POST/DELETE | `/rest/v1/favorites` | Add/remove favorite |
| POST | `/functions/v1/checkout` | Place order |
| POST | `/functions/v1/reorder` | Reorder |

### Admin
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/rest/v1/orders?order=created_at.desc` | All orders |
| PATCH | `/rest/v1/products?id=eq.{id}` | Toggle availability |
| POST | `/functions/v1/update-order-status` | Update status |

### Delivery
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/rest/v1/orders?delivery_staff_id=eq.{me}&status=eq.out_for_delivery` | My deliveries |
| POST | `/functions/v1/verify-delivery-otp` | Complete delivery |
| POST | `/functions/v1/mark-delivery-failed` | Mark failed |

---

## Deployment

### Docker Compose

```yaml
version: '3.8'

services:
  postgres:
    image: supabase/postgres:15.1.0.117
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data
    restart: unless-stopped

  kong:
    image: kong:3.1
    ports:
      - "8000:8000"
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: /var/lib/kong/kong.yml
    volumes:
      - ./kong.yml:/var/lib/kong/kong.yml
    restart: unless-stopped

  postgrest:
    image: postgrest/postgrest:v11.2.0
    environment:
      PGRST_DB_URI: postgres://postgres:${POSTGRES_PASSWORD}@postgres:5432/postgres
      PGRST_JWT_SECRET: ${JWT_SECRET}
      PGRST_DB_ANON_ROLE: anon
    restart: unless-stopped

  functions:
    image: supabase/edge-runtime:v1.29.1
    environment:
      SUPABASE_URL: http://kong:8000
      SUPABASE_SERVICE_ROLE_KEY: ${SERVICE_ROLE_KEY}
      JWT_SECRET: ${JWT_SECRET}
      OTP_SECRET: ${OTP_SECRET}
      MSG91_AUTH_KEY: ${MSG91_AUTH_KEY}
      MSG91_OTP_TEMPLATE: ${MSG91_OTP_TEMPLATE}
      MSG91_TEMPLATE: ${MSG91_TEMPLATE}
      FCM_SERVER_KEY: ${FCM_SERVER_KEY}
    volumes:
      - ./functions:/home/deno/functions
    restart: unless-stopped

  storage:
    image: supabase/storage-api:v0.40.4
    environment:
      STORAGE_BACKEND: file
      FILE_STORAGE_BACKEND_PATH: /var/lib/storage
    volumes:
      - storagedata:/var/lib/storage
    restart: unless-stopped

volumes:
  pgdata:
  storagedata:
```

### Environment

```env
POSTGRES_PASSWORD=secure-password
JWT_SECRET=32-char-secret-minimum
OTP_SECRET=another-secret
SERVICE_ROLE_KEY=your-service-role-key
MSG91_AUTH_KEY=msg91-key
MSG91_OTP_TEMPLATE=otp-template-id
MSG91_TEMPLATE=generic-template-id
FCM_SERVER_KEY=fcm-key
```

---

## Error Codes

| Code | HTTP | Message |
|------|------|---------|
| AUTH_001 | 400 | Invalid phone number |
| AUTH_002 | 400 | OTP expired |
| AUTH_003 | 400 | Invalid OTP |
| CHECKOUT_001 | 400 | Cart is empty |
| CHECKOUT_002 | 400 | Address required |
| CHECKOUT_003 | 400 | Area not serviceable |
| DELIVERY_001 | 400 | Invalid OTP |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0 | Jan 2026 | MVP: Simplified spec. No inventory tracking. Admin toggles availability. Simple order flow. |
