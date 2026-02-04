# Masala Spice Shop - Performance Audit Report

## Overview

Comprehensive performance audit of the self-hosted Supabase stack covering:
- Database (PostgreSQL, indexes, RLS policies)
- API layer (PostgREST, Kong gateway)
- Edge Functions (Deno runtime)
- Infrastructure (Docker, connection pooling)

**Audit Date:** 2026-02-04
**Implementation Status:** Complete

---

## Executive Summary

This audit identified 40 performance optimization opportunities across the Masala Spice Shop backend. The optimizations have been implemented in the following files:

| File | Optimizations |
|------|---------------|
| `33-performance-indexes.sql` | Items 1-6, 9 (Database indexes) |
| `34-rls-optimization.sql` | Items 7-10 (RLS policy fixes) |
| `35-function-optimization.sql` | Items 11-13 (SQL function optimization) |
| `36-pg-stat-statements.sql` | Item 29 (Query monitoring) |
| `_shared/auth.ts` | Items 14-15, 17 (Edge function cold start) |
| `_shared/response.ts` | Item 35 (Cache-Control headers) |
| `_shared/push.ts` | Item 20 (Batch token removal) |
| `users/index.ts` | Items 18-19 (Pagination, column selection) |
| `docker-compose.yml` | Items 26-34 (Infrastructure) |
| `kong.yml` | Items 22-25 (Gateway optimization) |

---

## Implementation Details

### CATEGORY A: DATABASE INDEXES (Items 1-6)

**File:** `volumes/db/init/33-performance-indexes.sql`

| Item | Description | Impact |
|------|-------------|--------|
| 1 | Index on `order_items.product_id` | HIGH - FK JOINs |
| 2 | Composite index for cart lookups | HIGH - 10-50x faster |
| 3 | Composite index for order history | MEDIUM |
| 4 | Partial index for available products | MEDIUM |
| 5 | Composite index for category browsing | MEDIUM |
| 6 | Index on `order_status_history.changed_by` | LOW |

Additional indexes added for RLS policy performance:
- `idx_orders_delivery_staff_status`
- `idx_weight_options_product_available`
- `idx_orders_user_status`
- `idx_orders_status_created`

### CATEGORY B: RLS POLICY OPTIMIZATION (Items 7-10)

**File:** `volumes/db/init/34-rls-optimization.sql`

| Item | Description | Impact |
|------|-------------|--------|
| 7 | Wrap `auth.uid()` in subselect for cart_items | HIGH - initPlan caching |
| 8 | SECURITY DEFINER helper for shiprocket shipments | MEDIUM - No cascading RLS |
| 9 | Indexes on RLS policy columns | HIGH - Up to 100x faster |
| 10 | Review all policies for row-level function calls | MEDIUM |

**Before (slow):**
```sql
USING (user_id = auth.uid());
```

**After (fast):**
```sql
USING (user_id = (select auth.uid()));
```

### CATEGORY C: SQL FUNCTION OPTIMIZATION (Items 11-13)

**File:** `volumes/db/init/35-function-optimization.sql`

| Item | Description | Impact |
|------|-------------|--------|
| 11 | Fix N+1 query in `get_orders()` | CRITICAL |
| 12 | Optimize address default trigger | LOW |
| 13 | Batch rate limit checks | MEDIUM |

**Before (N+1 queries):**
```sql
(SELECT COUNT(*)::INT FROM order_items oi WHERE oi.order_id = o.id) AS item_count
```

**After (single query):**
```sql
LEFT JOIN (
    SELECT order_id, COUNT(*)::INT AS item_count
    FROM order_items
    GROUP BY order_id
) item_counts ON item_counts.order_id = o.id
```

### CATEGORY D: EDGE FUNCTION COLD START (Items 14-17)

**File:** `volumes/functions/_shared/auth.ts`

| Item | Description | Impact |
|------|-------------|--------|
| 14 | Cache Supabase client instances | CRITICAL - Eliminates client creation overhead |
| 15 | Cache imported crypto keys | HIGH - Avoids expensive `importKey` per request |
| 16 | Lazy load heavy dependencies | MEDIUM - (Noted for future) |
| 17 | Light auth option without DB round-trip | HIGH - `requireAuthLight()` added |

**Cached Resources:**
- `_serviceClient` - Supabase service role client
- `_jwtVerifyKey` - JWT verification key
- `_jwtSignKey` - JWT signing key
- `_otpHmacKey` - OTP hashing key

### CATEGORY E: QUERY OPTIMIZATION (Items 18-21)

| Item | File | Description | Impact |
|------|------|-------------|--------|
| 18 | `users/index.ts` | Pagination with `limit`/`offset` | HIGH |
| 19 | Various | Specific columns instead of `SELECT *` | MEDIUM |
| 20 | `_shared/push.ts` | Batch invalid token removal | MEDIUM |
| 21 | - | Cache geocoding results | (Future) |

**Pagination Response Format:**
```json
{
  "data": [...],
  "pagination": {
    "offset": 0,
    "limit": 50,
    "total": 123,
    "hasMore": true
  }
}
```

### CATEGORY F: KONG API GATEWAY (Items 22-25)

**File:** `volumes/api/kong.yml`

| Item | Description | Impact |
|------|-------------|--------|
| 22 | Response caching for public storage | HIGH - 1 hour TTL |
| 23 | Gateway-level rate limiting | HIGH - DDoS protection |
| 24 | Request ID tracking (X-Request-ID) | LOW - Observability |
| 25 | Enable only used plugins | LOW - Memory savings |

**Rate Limits:**
| Endpoint | Rate Limit |
|----------|------------|
| `/rest/v1/` | 120/minute |
| `/rest/v1/rpc/` | 60/minute |
| `/functions/v1/` | 60/minute |
| `/storage/v1/` | 100/minute |
| `/pg/` (admin) | 30/minute |

### CATEGORY G: POSTGRESQL CONFIGURATION (Items 26-29)

**File:** `docker-compose.yml` (db service)

| Item | Setting | Value |
|------|---------|-------|
| 26 | `shared_buffers` | 256MB |
| 26 | `effective_cache_size` | 768MB |
| 26 | `work_mem` | 16MB |
| 26 | `maintenance_work_mem` | 128MB |
| 27 | `log_min_duration_statement` | 1000ms |
| 28 | `max_wal_size` | 2GB |
| 28 | `checkpoint_completion_target` | 0.9 |
| 29 | `shared_preload_libraries` | pg_stat_statements |

### CATEGORY H: CONNECTION POOLING (Items 30-31)

**File:** `docker-compose.yml`

**PostgREST (Item 30):**
| Setting | Value |
|---------|-------|
| `PGRST_DB_POOL` | 20 |
| `PGRST_DB_POOL_ACQUISITION_TIMEOUT` | 10 |
| `PGRST_DB_POOL_MAX_IDLETIME` | 30 |
| `PGRST_DB_MAX_ROWS` | 1000 |

**Supavisor (Item 31):**
| Setting | Value |
|---------|-------|
| `DB_POOL_SIZE` | 20 |
| `POOL_IDLE_TIMEOUT` | 30000 |

### CATEGORY I: DOCKER/INFRASTRUCTURE (Items 32-34)

**File:** `docker-compose.yml`

| Item | Description | Implementation |
|------|-------------|----------------|
| 32 | Resource limits | All containers have CPU/memory limits |
| 33 | Health check intervals | Increased from 5s to 30s |
| 34 | Storage health check | Changed to lightweight curl probe |

**Resource Limits:**
| Service | CPU Limit | Memory Limit |
|---------|-----------|--------------|
| db | 2 | 2G |
| rest | 1 | 512M |
| kong | 1 | 512M |
| storage | - | - |
| imgproxy | 1 | 512M |
| functions | 1 | 512M |
| supavisor | 1 | 512M |

### CATEGORY J: RESPONSE OPTIMIZATION (Items 35-37)

**File:** `volumes/functions/_shared/response.ts`

| Item | Description | Implementation |
|------|-------------|----------------|
| 35 | Cache-Control headers | `cachedJsonResponse()` helper |
| 36 | ETag support | `checkConditionalRequest()` helper |
| 37 | gzip compression | Kong handles (verified) |

**New Response Helpers:**
```typescript
// Cached response
cachedJsonResponse(body, maxAgeSeconds, { isPrivate: false });

// Conditional request check
const cached = checkConditionalRequest(req, etag);
if (cached) return cached;
```

### CATEGORY K: MONITORING & OBSERVABILITY (Items 38-40)

**File:** `volumes/db/init/36-pg-stat-statements.sql`

| Item | Description | Implementation |
|------|-------------|----------------|
| 38 | Query performance monitoring | `pg_stat_statements` extension |
| 39 | APM integration | (Future - OpenTelemetry) |
| 40 | Performance baseline | (Establish after deployment) |

**Query Monitoring Views:**
```sql
-- View slow queries
SELECT * FROM public.slow_queries;

-- Get performance summary
SELECT * FROM public.get_query_performance_summary();

-- Reset statistics (after optimizations)
SELECT public.reset_query_stats();
```

---

## Verification Steps

After deploying these changes:

### 1. Verify Index Creation
```sql
-- Check indexes exist
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%'
ORDER BY indexname;
```

### 2. Verify RLS Policy Performance
```sql
-- EXPLAIN ANALYZE a cart query
EXPLAIN ANALYZE
SELECT * FROM cart_items
WHERE user_id = 'some-user-id';
```

### 3. Monitor Query Performance
```sql
-- Top slow queries
SELECT * FROM public.slow_queries LIMIT 10;
```

### 4. Check Container Resource Usage
```bash
docker stats --no-stream
```

### 5. Test Rate Limiting
```bash
# Should return 429 after 60 requests/minute
for i in {1..70}; do
  curl -s -o /dev/null -w "%{http_code}\n" \
    -H "apikey: YOUR_ANON_KEY" \
    http://localhost:8100/rest/v1/categories
done
```

---

## Migration Notes

### To Apply Changes

1. **Database migrations** (33-36.sql):
   ```bash
   docker compose exec db psql -U postgres -f /docker-entrypoint-initdb.d/33-performance-indexes.sql
   docker compose exec db psql -U postgres -f /docker-entrypoint-initdb.d/34-rls-optimization.sql
   docker compose exec db psql -U postgres -f /docker-entrypoint-initdb.d/35-function-optimization.sql
   docker compose exec db psql -U postgres -f /docker-entrypoint-initdb.d/36-pg-stat-statements.sql
   ```

2. **Restart services** (for docker-compose.yml changes):
   ```bash
   docker compose down
   docker compose up -d
   ```

3. **Reload Kong** (for kong.yml changes):
   ```bash
   docker compose restart kong
   ```

### Rollback

If issues occur:
1. Remove index migration: `DROP INDEX IF EXISTS idx_name;`
2. Revert RLS policies to original (backup in 03-rls-policies.sql)
3. Restore original docker-compose.yml
4. Restore original kong.yml

---

## Expected Impact

| Category | Expected Improvement |
|----------|---------------------|
| Cart operations | 10-50x faster |
| Order listing | 2-5x faster (N+1 fix) |
| RLS policy evaluation | Up to 100x faster |
| Edge function cold start | 50-70% reduction |
| API response times | 20-30% reduction |
| Memory usage | More predictable with limits |

---

## References

- [Supabase Performance Tuning Docs](https://supabase.com/docs/guides/platform/performance)
- [PostgreSQL RLS Optimization](https://scottpierce.dev/posts/optimizing-postgres-rls/)
- [PostgREST Connection Pool Docs](https://docs.postgrest.org/en/v12/references/connection_pool.html)
- [Supabase 97% Faster Cold Starts](https://dev.to/supabase/persistent-storage-and-97-faster-cold-starts-for-edge-functions-516f)
- [Kong Rate Limiting Plugin](https://docs.konghq.com/hub/kong-inc/rate-limiting/)
- [Supabase Postgres Best Practices](https://supaexplorer.com/best-practices/supabase-postgres/)
