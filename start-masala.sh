#!/bin/bash

# ==============================================================================
# MASALA SPICE SHOP - SUPABASE PRODUCTION STARTUP SCRIPT
# ==============================================================================
#
# Production-ready startup script with:
# - Automatic stop of running services before starting fresh
# - Comprehensive logging to logs/startup-YYYYMMDD.log
# - Health monitoring and validation
# - Automatic log rotation (7 days retention)
# - Proper error handling without premature exits
# - Systemd integration ready
#
# Usage:
#   ./start-masala.sh          # Stop existing & start fresh
#
# ==============================================================================

# ==============================================================================
# LOGGING CONFIGURATION (Systemd-compatible - no process substitution)
# ==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/startup-$(date '+%Y%m%d').log"
DOCKER_DIR="$SCRIPT_DIR"
FUNCTIONS_DIR="$SCRIPT_DIR/volumes/functions"

# Create log directory
mkdir -p "$LOG_DIR"

# Logging function that outputs to both console and file (systemd-safe)
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_line="[$timestamp] [$level] $message"
    echo -e "$log_line"
    echo -e "$log_line" >> "$LOG_FILE"
}

log "INFO" "=========================================="
log "INFO" "Masala Supabase Startup Script Initiated"
log "INFO" "Script: $0"
log "INFO" "Working Directory: $SCRIPT_DIR"
log "INFO" "=========================================="

# ==============================================================================
# ERROR HANDLING (replaces set -e)
# ==============================================================================
handle_error() {
    local exit_code=$?
    local line_number=$1
    log "ERROR" "Command failed at line $line_number with exit code $exit_code"
    # Don't exit - allow script to continue for non-critical errors
}
trap 'handle_error $LINENO' ERR

critical_error() {
    log "CRITICAL" "$1"
    log "CRITICAL" "Startup failed - check logs at $LOG_FILE"
    exit 1
}

# ==============================================================================
# CONFIGURATION
# ==============================================================================
MAX_RETRIES=3
RETRY_INTERVAL=5
HEALTH_CHECK_TIMEOUT=30
DOCKER_COMMAND_TIMEOUT=120  # Timeout for docker commands (seconds)

# Masala-specific container names
CONTAINER_PREFIX="masala"

# Services to monitor (Masala stack)
services_to_check=(
    "masala-db"
    "masala-kong"
    "masala-rest"
    "masala-studio"
    "masala-storage"
    "masala-supavisor"
    "masala-functions"
    "masala-meta"
    "masala-imgproxy"
)

# Protected ports that should ONLY be bound to localhost (security)
# Format: "host_port:container_port"
protected_ports=(
    "5534:5432"   # PostgreSQL
    "5535:5432"   # Supavisor Session
    "6643:6543"   # Supavisor Transaction
    "4101:4000"   # Supavisor Admin
)

# ==============================================================================
# FUNCTION: Docker command wrapper with timeout (prevents hangs)
# ==============================================================================
docker_cmd() {
    local timeout_seconds=${DOCKER_COMMAND_TIMEOUT:-120}
    if command -v timeout &> /dev/null; then
        timeout --kill-after=10 "$timeout_seconds" docker "$@"
    else
        docker "$@"
    fi
}

# Note: --force flag is accepted for backwards compatibility but not needed
# (script always does full stop+start)
if [ "$1" = "--force" ]; then
    log "INFO" "Force flag acknowledged (script always does full restart)"
fi

# ==============================================================================
# FUNCTION: Log Rotation (keep last 7 days)
# ==============================================================================
rotate_logs() {
    log "INFO" "Rotating old logs..."
    find "$LOG_DIR" -name "startup-*.log" -mtime +7 -delete 2>/dev/null || true
    find "$LOG_DIR" -name "*.log.gz" -mtime +14 -delete 2>/dev/null || true
    # Compress logs older than 1 day (excluding current log)
    find "$LOG_DIR" -name "startup-*.log" -mtime +1 ! -name "$(basename $LOG_FILE)" -exec gzip -f {} \; 2>/dev/null || true
    log "INFO" "Log rotation complete"
}

# ==============================================================================
# FUNCTION: Docker Connection Verification
# ==============================================================================
verify_docker() {
    log "INFO" "Verifying Docker connection..."

    export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export HOME="${HOME:-/home/gcswebserver}"

    local max_checks=15
    local check_count=0

    while [ $check_count -lt $max_checks ]; do
        if docker info > /dev/null 2>&1; then
            log "INFO" "Docker connected successfully"
            log "INFO" "  Docker version: $(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'unknown')"
            log "INFO" "  Compose version: $(docker compose version --short 2>/dev/null || echo 'unknown')"
            return 0
        fi

        log "WARN" "Waiting for Docker... (attempt $((check_count + 1))/$max_checks)"
        sleep 2
        check_count=$((check_count + 1))
    done

    critical_error "Docker connection failed after $max_checks attempts"
}

# ==============================================================================
# FUNCTION: System Resource Check
# ==============================================================================
check_system_resources() {
    log "INFO" "Checking system resources..."

    # CPU Usage
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' 2>/dev/null || echo "N/A")
    log "INFO" "  CPU Usage: ${cpu_usage}%"

    # Memory Usage
    if command -v free &> /dev/null; then
        local mem_usage=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')
        local mem_available=$(free -h | grep Mem | awk '{print $7}')
        log "INFO" "  Memory Usage: ${mem_usage}% (Available: $mem_available)"

        # Warn if memory usage is very high
        local mem_usage_int=${mem_usage%.*}
        if [ "$mem_usage_int" -gt 90 ] 2>/dev/null; then
            log "WARN" "  HIGH MEMORY USAGE: ${mem_usage}% - services may be slow or fail"
        fi
    fi

    # Load Average
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',' | xargs)
    log "INFO" "  Load Average: $load_avg"

    # Disk Space with thresholds
    local disk_usage=$(df -h "$SCRIPT_DIR" | tail -1 | awk '{print $5}')
    local disk_usage_int=${disk_usage%\%}
    local disk_free=$((100 - disk_usage_int))
    log "INFO" "  Disk Usage: $disk_usage (${disk_free}% free)"

    # Critical: Less than 10% free - emergency cleanup
    if [ "$disk_free" -lt 10 ] 2>/dev/null; then
        log "ERROR" "CRITICAL: Disk space critically low (${disk_free}% free)!"
        log "INFO" "  Attempting emergency cleanup..."

        # Emergency cleanup - remove old logs and docker artifacts
        find "$LOG_DIR" -name "*.log.gz" -mtime +3 -delete 2>/dev/null || true
        find "$LOG_DIR" -name "*.log" -mtime +3 ! -name "$(basename $LOG_FILE)" -delete 2>/dev/null || true
        docker system prune -f --volumes 2>/dev/null || true

        # Re-check
        disk_usage=$(df -h "$SCRIPT_DIR" | tail -1 | awk '{print $5}')
        disk_usage_int=${disk_usage%\%}
        disk_free=$((100 - disk_usage_int))
        log "INFO" "  After cleanup: $disk_usage (${disk_free}% free)"

        if [ "$disk_free" -lt 5 ] 2>/dev/null; then
            log "CRITICAL" "Disk still critically low after cleanup - manual intervention required!"
        fi
    # Warning: Less than 20% free
    elif [ "$disk_free" -lt 20 ] 2>/dev/null; then
        log "WARN" "  LOW DISK SPACE: Only ${disk_free}% free - consider cleanup"
    fi
}

# ==============================================================================
# FUNCTION: Security Configuration Check & Auto-Fix
# Automatically fixes database port bindings to 127.0.0.1 if exposed on 0.0.0.0
# ==============================================================================
check_security_config() {
    log "INFO" "Checking security configuration..."

    local compose_file="$DOCKER_DIR/docker-compose.yml"
    local fixes_applied=0

    if [ ! -f "$compose_file" ]; then
        log "WARN" "docker-compose.yml not found at $compose_file"
        return 1
    fi

    for port_mapping in "${protected_ports[@]}"; do
        # Check if port is exposed WITHOUT 127.0.0.1 prefix (dangerous!)
        # Matches: "- 5534:5432" or "- '5534:5432'" but NOT "- 127.0.0.1:5534:5432"
        if grep -E "^\s*-\s*[\"']?${port_mapping}[\"']?\s*$" "$compose_file" > /dev/null 2>&1; then
            log "WARN" "SECURITY: Port ${port_mapping} exposed on 0.0.0.0 - AUTO-FIXING to 127.0.0.1"

            # Create backup before first fix
            if [ $fixes_applied -eq 0 ]; then
                cp "$compose_file" "${compose_file}.security-backup"
                log "INFO" "  Backup created: ${compose_file}.security-backup"
            fi

            # Fix the binding - add 127.0.0.1: prefix
            sed -i "s/\(^\s*-\s*\)[\"']\?${port_mapping}[\"']\?\s*$/\1\"127.0.0.1:${port_mapping}\"/" "$compose_file"

            fixes_applied=$((fixes_applied + 1))
        fi
    done

    if [ $fixes_applied -gt 0 ]; then
        log "INFO" "============================================="
        log "INFO" "SECURITY AUTO-FIX: Applied $fixes_applied port binding fix(es)"
        log "INFO" "All database ports now bound to 127.0.0.1 only"
        log "INFO" "Backup saved: ${compose_file}.security-backup"
        log "INFO" "============================================="
    else
        log "INFO" "  Security check passed: All database ports already bound to localhost"
    fi

    return 0
}

# ==============================================================================
# FUNCTION: Load Environment Variables
# ==============================================================================
load_environment() {
    log "INFO" "Loading environment variables..."

    # Security: Check .env file permissions
    local env_file="$DOCKER_DIR/.env"
    if [ -f "$env_file" ]; then
        local env_perms=$(stat -c "%a" "$env_file" 2>/dev/null || stat -f "%OLp" "$env_file" 2>/dev/null)

        # Check if file is world-readable (permissions like 644, 664, etc.)
        if [[ "$env_perms" =~ [0-7][0-7][4-7] ]]; then
            log "WARN" "SECURITY: .env file is world-readable (permissions: $env_perms)"
            log "INFO" "  Auto-fixing to 600 (owner read/write only)..."
            chmod 600 "$env_file"
            log "INFO" "  .env permissions fixed to 600"
        else
            log "INFO" "  .env permissions secure ($env_perms)"
        fi

        # Source .env file for variables we need
        set -a
        source "$env_file"
        set +a
        log "INFO" "  Environment variables loaded from .env"
    else
        log "WARN" ".env file not found at $env_file"
    fi

    # Verify critical env vars
    if [ -z "$ANON_KEY" ]; then
        log "WARN" "ANON_KEY not set - some features may not work"
    fi
    if [ -z "$JWT_SECRET" ]; then
        log "WARN" "JWT_SECRET not set - authentication will fail"
    fi
    if [ -z "$POSTGRES_PASSWORD" ]; then
        log "WARN" "POSTGRES_PASSWORD not set - database connection will fail"
    fi
}

# ==============================================================================
# FUNCTION: Fix Pooler Encryption Key (Supavisor)
# ==============================================================================
fix_pooler_encryption_key() {
    log "INFO" "Validating Pooler encryption key..."

    local current_key=$(grep "^VAULT_ENC_KEY=" "$DOCKER_DIR/.env" 2>/dev/null | cut -d'=' -f2)
    local key_length=${#current_key}

    # Skip if using placeholder/default
    if [[ "$current_key" == "your-super-secret"* ]]; then
        log "WARN" "VAULT_ENC_KEY using default placeholder - generating secure key..."
        local new_key=$(head -c 16 /dev/urandom | xxd -p | tr -d '\n' | head -c 32)
        if [ ${#new_key} -ne 32 ]; then
            # Fallback if xxd not available
            new_key=$(openssl rand -hex 16 | head -c 32)
        fi
        sed -i.bak "s/^VAULT_ENC_KEY=.*/VAULT_ENC_KEY=$new_key/" "$DOCKER_DIR/.env"
        log "INFO" "VAULT_ENC_KEY generated securely (32 random characters)"
    elif [ "$key_length" -lt 32 ]; then
        log "WARN" "Invalid VAULT_ENC_KEY: ${key_length} characters (needs 32)"
        local new_key=$(head -c 16 /dev/urandom | xxd -p | tr -d '\n' | head -c 32)
        if [ ${#new_key} -ne 32 ]; then
            new_key=$(openssl rand -hex 16 | head -c 32)
        fi
        sed -i.bak "s/^VAULT_ENC_KEY=.*/VAULT_ENC_KEY=$new_key/" "$DOCKER_DIR/.env"
        log "INFO" "VAULT_ENC_KEY generated securely (32 random characters)"
    else
        log "INFO" "VAULT_ENC_KEY valid (${key_length} characters)"
    fi
}

# ==============================================================================
# FUNCTION: Validate JWT Configuration (CRITICAL for auth)
# ==============================================================================
validate_jwt_config() {
    log "INFO" "Validating JWT configuration across containers..."

    local env_jwt_secret=$(grep "^JWT_SECRET=" "$DOCKER_DIR/.env" 2>/dev/null | cut -d'=' -f2)
    local env_service_key=$(grep "^SERVICE_ROLE_KEY=" "$DOCKER_DIR/.env" 2>/dev/null | cut -d'=' -f2)
    local env_anon_key=$(grep "^ANON_KEY=" "$DOCKER_DIR/.env" 2>/dev/null | cut -d'=' -f2)

    # SECURITY: Check for demo/default keys (CRITICAL)
    local demo_jwt_prefix="your-super-secret-jwt-token"
    local demo_anon_prefix="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIi"

    local is_demo_key=false
    if [[ "$env_jwt_secret" == *"$demo_jwt_prefix"* ]] || [[ "$env_jwt_secret" == "super-secret-jwt-token"* ]]; then
        log "ERROR" "SECURITY: Demo JWT_SECRET detected!"
        is_demo_key=true
    fi
    if [[ "$env_anon_key" == "$demo_anon_prefix"* ]]; then
        log "ERROR" "SECURITY: Demo ANON_KEY detected!"
        is_demo_key=true
    fi

    if [ "$is_demo_key" = true ]; then
        log "WARN" "============================================="
        log "WARN" "DEMO KEYS DETECTED - PRODUCTION USE NOT RECOMMENDED"
        log "WARN" "Please generate production keys before deploying"
        log "WARN" "============================================="
    fi

    local stale_containers=()

    # Check PostgREST JWT_SECRET
    local container_jwt=$(docker inspect masala-rest 2>/dev/null | grep -o '"PGRST_JWT_SECRET=[^"]*"' | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -n "$container_jwt" ] && [ "$container_jwt" != "$env_jwt_secret" ]; then
        log "WARN" "PostgREST has stale JWT_SECRET"
        stale_containers+=("rest")
    fi

    # Check Edge Functions SERVICE_ROLE_KEY
    local container_service_key=$(docker exec masala-functions printenv SUPABASE_SERVICE_ROLE_KEY 2>/dev/null || echo "")
    if [ -n "$container_service_key" ] && [ "$container_service_key" != "$env_service_key" ]; then
        log "WARN" "Edge Functions has stale SERVICE_ROLE_KEY"
        stale_containers+=("functions")
    fi

    # Check Kong ANON_KEY (via inspect)
    local container_anon_key=$(docker inspect masala-kong 2>/dev/null | grep -o '"SUPABASE_ANON_KEY=[^"]*"' | cut -d'=' -f2 | tr -d '"' || echo "")
    if [ -n "$container_anon_key" ] && [ "$container_anon_key" != "$env_anon_key" ]; then
        log "WARN" "Kong has stale ANON_KEY"
        stale_containers+=("kong")
    fi

    if [ ${#stale_containers[@]} -gt 0 ]; then
        log "WARN" "Containers with stale JWT config: ${stale_containers[*]}"
        log "INFO" "Will force recreate these containers to pick up new config"
        JWT_STALE_CONTAINERS="${stale_containers[*]}"
        return 1
    else
        log "INFO" "All containers have current JWT configuration"
        JWT_STALE_CONTAINERS=""
        return 0
    fi
}

# ==============================================================================
# FUNCTION: Smart Service Health Check
# ==============================================================================
smart_health_recovery() {
    log "INFO" "Performing smart health check..."

    local unhealthy_services=()

    for service in "${services_to_check[@]}"; do
        local status=$(docker inspect --format='{{.State.Status}}' "$service" 2>/dev/null || echo "not_found")
        local health=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null || echo "none")

        if [ "$status" = "running" ] && [ "$health" != "unhealthy" ]; then
            log "INFO" "  $service: healthy (status: $status)"
        else
            log "WARN" "  $service: needs attention (status: $status, health: $health)"
            unhealthy_services+=("$service")
        fi
    done

    if [ ${#unhealthy_services[@]} -eq 0 ]; then
        log "INFO" "All services healthy"
        return 0
    fi

    log "INFO" "${#unhealthy_services[@]} service(s) need recovery: ${unhealthy_services[*]}"
    return 1
}


# ==============================================================================
# FUNCTION: Stop Services (for full restart)
# ==============================================================================
stop_services() {
    log "INFO" "Stopping existing services..."

    docker compose \
        -f "$DOCKER_DIR/docker-compose.yml" \
        --env-file "$DOCKER_DIR/.env" \
        --project-directory "$DOCKER_DIR" \
        down 2>/dev/null || true

    sleep 3
    log "INFO" "Services stopped"
}

# ==============================================================================
# FUNCTION: Start Services
# ==============================================================================
start_services() {
    log "INFO" "Starting Masala Supabase services..."
    log "INFO" "  Compose file: $DOCKER_DIR/docker-compose.yml"
    log "INFO" "  Env file: $DOCKER_DIR/.env"

    local max_retries=3
    local retry=0
    local success=false

    while [ $retry -lt $max_retries ]; do
        log "INFO" "Startup attempt $((retry + 1))/$max_retries..."

        if docker compose \
            -f "$DOCKER_DIR/docker-compose.yml" \
            --env-file "$DOCKER_DIR/.env" \
            --project-directory "$DOCKER_DIR" \
            up -d --remove-orphans 2>&1 | while read line; do log "INFO" "  $line"; done; then

            success=true
            log "INFO" "Docker Compose started successfully"
            break
        else
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                log "WARN" "Attempt failed, retrying in 5 seconds..."
                sleep 5
            fi
        fi
    done

    if [ "$success" = false ]; then
        critical_error "Failed to start Masala after $max_retries attempts"
    fi
}

# ==============================================================================
# FUNCTION: Force Recreate Containers with Stale JWT Config
# ==============================================================================
recreate_stale_jwt_containers() {
    if [ -z "$JWT_STALE_CONTAINERS" ]; then
        return 0
    fi

    log "INFO" "Force recreating containers with stale JWT config: $JWT_STALE_CONTAINERS"

    for service in $JWT_STALE_CONTAINERS; do
        log "INFO" "  Recreating $service..."
        docker compose \
            -f "$DOCKER_DIR/docker-compose.yml" \
            --env-file "$DOCKER_DIR/.env" \
            --project-directory "$DOCKER_DIR" \
            up -d --force-recreate "$service" 2>&1 | while read line; do log "INFO" "    $line"; done
    done

    # If Edge Functions was recreated, sync ALL function files
    if [[ "$JWT_STALE_CONTAINERS" == *"functions"* ]]; then
        sync_edge_functions
    fi

    log "INFO" "Stale containers recreated successfully"
}

# ==============================================================================
# FUNCTION: Sync ALL Edge Function files to container
# ==============================================================================
sync_edge_functions() {
    if [[ ! -d "$FUNCTIONS_DIR" ]]; then
        log "WARN" "Functions directory not found: $FUNCTIONS_DIR"
        return 1
    fi

    log "INFO" "Syncing Edge Function files to container..."
    sleep 3

    # Copy _shared directory first (contains auth.ts, sms.ts, push.ts)
    if [[ -d "$FUNCTIONS_DIR/_shared" ]]; then
        docker cp "$FUNCTIONS_DIR/_shared" masala-functions:/home/deno/functions/ 2>/dev/null || true
        log "INFO" "  _shared (auth helpers)"
    fi

    # Copy import_map.json if exists
    if [[ -f "$FUNCTIONS_DIR/import_map.json" ]]; then
        docker cp "$FUNCTIONS_DIR/import_map.json" masala-functions:/home/deno/functions/ 2>/dev/null || true
        log "INFO" "  import_map.json"
    fi

    # Copy all function directories (skip _shared and hidden dirs)
    for func_dir in "$FUNCTIONS_DIR"/*/; do
        local func_name=$(basename "$func_dir")
        # Skip _shared and any hidden directories
        if [[ "$func_name" != "_shared" && ! "$func_name" =~ ^\. ]]; then
            docker cp "$func_dir" masala-functions:/home/deno/functions/ 2>/dev/null || true
            log "INFO" "  $func_name"
        fi
    done

    # Restart to pick up changes
    docker restart masala-functions 2>/dev/null || true
    sleep 3
    log "INFO" "Edge Functions synced and restarted"
}

# ==============================================================================
# FUNCTION: Wait for Database
# ==============================================================================
wait_for_database() {
    log "INFO" "Waiting for database to be ready..."

    local max_attempts=30
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        local result=$(docker exec masala-db psql -U supabase_admin -d postgres -t -c "SELECT 1;" 2>/dev/null | tr -d ' ' || echo "0")

        if [ "$result" = "1" ]; then
            log "INFO" "Database is ready"
            return 0
        fi

        attempt=$((attempt + 1))
        log "INFO" "  Waiting for database... ($attempt/$max_attempts)"
        sleep 2
    done

    log "WARN" "Database did not become ready in time, continuing anyway..."
    return 1
}

# ==============================================================================
# FUNCTION: Apply Database Permissions for Supabase Services
# ==============================================================================
apply_database_permissions() {
    log "INFO" "Applying database permissions for Supabase services..."

    docker exec masala-db psql -U supabase_admin -d postgres -c "
-- Create schemas if not exist
CREATE SCHEMA IF NOT EXISTS storage;
CREATE SCHEMA IF NOT EXISTS _supavisor;
CREATE SCHEMA IF NOT EXISTS extensions;

-- Grant storage admin full permissions
GRANT ALL ON SCHEMA storage TO supabase_storage_admin WITH GRANT OPTION;
GRANT CREATE ON DATABASE postgres TO supabase_storage_admin;
GRANT ALL PRIVILEGES ON DATABASE postgres TO supabase_storage_admin;
ALTER ROLE supabase_storage_admin SET search_path TO storage, public, extensions;

-- Grant supavisor schema permissions
GRANT ALL ON SCHEMA _supavisor TO supabase_admin WITH GRANT OPTION;
ALTER SCHEMA _supavisor OWNER TO supabase_admin;

-- Grant to service_role
GRANT ALL ON SCHEMA storage TO service_role;
GRANT USAGE ON SCHEMA _supavisor TO service_role;
" 2>&1 | while read line; do log "INFO" "  $line"; done

    log "INFO" "Database permissions applied"
}

# ==============================================================================
# FUNCTION: Final Health Report
# ==============================================================================
final_health_report() {
    log "INFO" "=========================================="
    log "INFO" "FINAL SERVICE STATUS"
    log "INFO" "=========================================="

    # List all containers
    docker ps --format "table {{.Names}}\t{{.Status}}" --filter "name=masala" 2>/dev/null | while read line; do
        log "INFO" "  $line"
    done

    # API health check
    sleep 3
    local api_response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8100/rest/v1/" -H "apikey: ${ANON_KEY:-dummy}" 2>/dev/null || echo "000")
    if [ "$api_response" = "200" ] || [ "$api_response" = "401" ]; then
        log "INFO" "API Gateway responding (HTTP $api_response)"
    else
        log "WARN" "API Gateway returned HTTP $api_response"
    fi

    log "INFO" "=========================================="
    log "INFO" "Service URLs:"
    log "INFO" "  API Gateway:     http://localhost:8100"
    log "INFO" "  Supabase Studio: http://localhost:54424"
    log "INFO" "  Database:        localhost:5534"
    log "INFO" "  Supavisor:       localhost:5535 (session) / 6643 (transaction)"
    log "INFO" "=========================================="

    log "INFO" "Startup completed at $(date)"
    log "INFO" "Log file: $LOG_FILE"
    log "INFO" "=========================================="
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

log "INFO" ""
log "INFO" "Step 1: Log Rotation"
log "INFO" "-------------------------------------------"
rotate_logs

log "INFO" ""
log "INFO" "Step 2: Docker Verification"
log "INFO" "-------------------------------------------"
verify_docker

log "INFO" ""
log "INFO" "Step 3: System Resources"
log "INFO" "-------------------------------------------"
check_system_resources

log "INFO" ""
log "INFO" "Step 4: Security Configuration Check & Auto-Fix"
log "INFO" "-------------------------------------------"
check_security_config

log "INFO" ""
log "INFO" "Step 5: Environment Setup"
log "INFO" "-------------------------------------------"
load_environment

log "INFO" ""
log "INFO" "Step 6: Pooler Key Validation"
log "INFO" "-------------------------------------------"
fix_pooler_encryption_key

log "INFO" ""
log "INFO" "Step 7: JWT Configuration Validation"
log "INFO" "-------------------------------------------"
validate_jwt_config || true  # Don't fail startup, just detect stale containers

log "INFO" ""
log "INFO" "Step 8: Health Status Check"
log "INFO" "-------------------------------------------"
smart_health_recovery || true  # Just log current state, will restart regardless

log "INFO" ""
log "INFO" "Step 9: Service Management"
log "INFO" "-------------------------------------------"

# Always stop existing services first for clean startup
log "INFO" "Stopping any running Masala services..."
stop_services

log "INFO" "Starting fresh..."
start_services

# Check for stale JWT containers after startup
if [ -n "$JWT_STALE_CONTAINERS" ]; then
    log "WARN" "JWT config mismatch detected - recreating affected containers"
    recreate_stale_jwt_containers
fi

log "INFO" ""
log "INFO" "Step 10: Database Ready Check"
log "INFO" "-------------------------------------------"
wait_for_database

log "INFO" ""
log "INFO" "Step 10b: Apply Database Permissions"
log "INFO" "-------------------------------------------"
apply_database_permissions

log "INFO" ""
log "INFO" "Step 11: Final Health Verification"
log "INFO" "-------------------------------------------"
final_health_report

log "INFO" ""
log "INFO" "Masala startup script completed successfully"
exit 0
