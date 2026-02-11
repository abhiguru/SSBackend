#!/usr/bin/env bash
set -euo pipefail

BACKEND_DIR="/home/gcswebserver/ws/SSMasala/backend"
LOG_DIR="${BACKEND_DIR}/logs"
LOG_FILE="${LOG_DIR}/masala-startup.log"

cd "$BACKEND_DIR"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== Masala startup begin ==="

if ! /usr/bin/docker compose up -d --remove-orphans >> "$LOG_FILE" 2>&1; then
  log "ERROR: docker compose up failed"
  exit 1
fi
log "docker compose up completed"

# Wait for DB to be healthy (up to 60s)
log "Waiting for database health..."
for i in $(seq 1 30); do
  if /usr/bin/docker compose exec -T db pg_isready -U postgres > /dev/null 2>&1; then
    log "Database is ready (after ${i}x2s)"
    break
  fi
  if [ "$i" -eq 30 ]; then
    log "ERROR: Database not ready after 60s"
    /usr/bin/docker compose ps >> "$LOG_FILE" 2>&1
    exit 1
  fi
  sleep 2
done

# Log final container status
log "Container status:"
/usr/bin/docker compose ps >> "$LOG_FILE" 2>&1

log "=== Masala startup complete ==="
