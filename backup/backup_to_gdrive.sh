#!/bin/bash

# ========================================
# MASALA DB - AUTOMATED GOOGLE DRIVE BACKUP
# ========================================
# Creates full SQL backup and uploads to Google Drive
# Keeps last 7 backups, deletes older ones
# Verifies backup integrity
# Adapted from GuruColdStorage backup system

# Use absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$BASE_DIR/logs"
LOG_FILE="$LOG_DIR/masala-backup.log"
LOCK_FILE="/tmp/masala_backup_to_gdrive.lock"
MAX_LOG_SIZE=52428800  # 50MB

# Backup configuration
CONTAINER_NAME="masala-db"
LOCAL_BACKUP_DIR="$SCRIPT_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${LOCAL_BACKUP_DIR}/masala_backup_${TIMESTAMP}.sql"
GDRIVE_FOLDER="gdrive2:/masala_backups"
KEEP_BACKUPS=7
MAX_RETRIES=5

# Colors (only for terminal)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    NC=''
fi

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Logging function with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo -e "$1"
}

# Rotate log if too large (50MB)
rotate_log() {
    if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        log "Log rotated (exceeded 50MB)"
    fi
}

# Retry with exponential backoff
retry_with_backoff() {
    local description="$1"
    shift
    local cmd="$@"
    local retry=0
    local delay=2

    while [ $retry -lt $MAX_RETRIES ]; do
        if eval "$cmd"; then
            return 0
        fi
        retry=$((retry + 1))
        log "${YELLOW}Retry $retry/$MAX_RETRIES for $description in ${delay}s...${NC}"
        sleep $delay
        delay=$((delay * 2))
    done
    log "${RED}ERROR: $description failed after $MAX_RETRIES attempts${NC}"
    return 1
}

# Cleanup function - remove partial backup on failure
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        if [ -f "$BACKUP_FILE" ]; then
            log "${YELLOW}Cleaning up partial backup file...${NC}"
            rm -f "$BACKUP_FILE" "${BACKUP_FILE}.sha256"
        fi
    fi
}
trap cleanup EXIT INT TERM

# Single instance check using flock
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    log "${RED}ERROR: Another instance is running${NC}"
    exit 1
fi

# Main backup function
main() {
    rotate_log

    log ""
    log "${GREEN}========================================${NC}"
    log "${GREEN}Masala DB Backup - $(date)${NC}"
    log "${GREEN}========================================${NC}"
    log ""

    # Create local backup directory
    mkdir -p "$LOCAL_BACKUP_DIR"

    # Step 1: Create SQL backup with timeout (10 minutes)
    log "${YELLOW}[1/5] Creating SQL backup...${NC}"
    if ! timeout 600 docker exec $CONTAINER_NAME pg_dump -U postgres -d postgres \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges \
        > "$BACKUP_FILE"; then
        log "${RED}ERROR: Backup creation failed${NC}"
        return 1
    fi

    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log "${GREEN}Backup created: $(basename $BACKUP_FILE) ($BACKUP_SIZE)${NC}"
    log ""

    # Step 2: Verify backup integrity
    log "${YELLOW}[2/5] Verifying backup integrity...${NC}"

    if [ ! -s "$BACKUP_FILE" ]; then
        log "${RED}ERROR: Backup file is empty!${NC}"
        return 1
    fi

    if grep -q "PostgreSQL database dump complete" "$BACKUP_FILE"; then
        log "${GREEN}Backup integrity verified${NC}"
    else
        log "${RED}ERROR: Backup may be incomplete (no completion marker)${NC}"
        return 1
    fi

    TABLE_COUNT=$(grep -c "^CREATE TABLE" "$BACKUP_FILE" || echo "0")
    FUNCTION_COUNT=$(grep -c "^CREATE FUNCTION" "$BACKUP_FILE" || echo "0")
    log "${BLUE}  Tables: $TABLE_COUNT${NC}"
    log "${BLUE}  Functions: $FUNCTION_COUNT${NC}"
    log ""

    # Step 3: Generate checksum
    log "${YELLOW}[3/5] Generating checksum...${NC}"
    CHECKSUM=$(sha256sum "$BACKUP_FILE" | cut -d' ' -f1)
    echo "$CHECKSUM  masala_backup_${TIMESTAMP}.sql" > "${BACKUP_FILE}.sha256"
    log "${GREEN}Checksum: ${CHECKSUM:0:16}...${NC}"
    log ""

    # Step 4: Upload to Google Drive with retry
    log "${YELLOW}[4/5] Uploading to Google Drive...${NC}"

    if ! retry_with_backoff "Upload backup to GDrive" rclone copy "$BACKUP_FILE" "$GDRIVE_FOLDER" --progress; then
        log "${RED}ERROR: Failed to upload backup${NC}"
        return 1
    fi

    if ! retry_with_backoff "Upload checksum to GDrive" rclone copy "${BACKUP_FILE}.sha256" "$GDRIVE_FOLDER" --progress; then
        log "${YELLOW}Warning: Checksum upload failed (backup still uploaded)${NC}"
    fi

    log "${GREEN}Uploaded to Google Drive${NC}"
    log ""

    # Step 5: Cleanup old backups (Google Drive)
    log "${YELLOW}[5/5] Cleaning up old backups (keeping last $KEEP_BACKUPS)...${NC}"

    BACKUP_LIST=$(rclone lsf "$GDRIVE_FOLDER" 2>/dev/null | grep "masala_backup_.*\.sql$" | sort -r)
    BACKUP_COUNT=$(echo "$BACKUP_LIST" | grep -c "." || echo "0")

    if [ "$BACKUP_COUNT" -gt "$KEEP_BACKUPS" ]; then
        echo "$BACKUP_LIST" | tail -n +$((KEEP_BACKUPS + 1)) | while read old_backup; do
            if [ -n "$old_backup" ]; then
                log "${BLUE}  Deleting: $old_backup${NC}"
                rclone delete "$GDRIVE_FOLDER/$old_backup" 2>/dev/null || true
                rclone delete "$GDRIVE_FOLDER/${old_backup}.sha256" 2>/dev/null || true
            fi
        done
        log "${GREEN}Old GDrive backups cleaned${NC}"
    else
        log "${BLUE}  Only $BACKUP_COUNT backups in GDrive, no cleanup needed${NC}"
    fi
    log ""

    # Cleanup old LOCAL backups (keep last 7)
    LOCAL_BACKUP_COUNT=$(ls -1 ${LOCAL_BACKUP_DIR}/masala_backup_*.sql 2>/dev/null | wc -l)
    if [ "$LOCAL_BACKUP_COUNT" -gt "$KEEP_BACKUPS" ]; then
        ls -1t ${LOCAL_BACKUP_DIR}/masala_backup_*.sql | tail -n +$((KEEP_BACKUPS + 1)) | while read old_local; do
            log "${BLUE}  Deleting local: $(basename $old_local)${NC}"
            rm -f "$old_local" "${old_local}.sha256"
        done
        log "${GREEN}Old local backups cleaned${NC}"
    fi
    log ""

    # Summary
    log "${GREEN}========================================${NC}"
    log "${GREEN}Backup Summary${NC}"
    log "${GREEN}========================================${NC}"
    log "Timestamp:     $(date)"
    log "Backup file:   masala_backup_${TIMESTAMP}.sql"
    log "Size:          $BACKUP_SIZE"
    log "Tables:        $TABLE_COUNT"
    log "Functions:     $FUNCTION_COUNT"
    log "Checksum:      ${CHECKSUM:0:32}..."
    log "Location:      $GDRIVE_FOLDER"
    log "Total backups: $(rclone lsf $GDRIVE_FOLDER 2>/dev/null | grep -c 'masala_backup_.*\.sql$' || echo '0')"
    log ""
    log "${GREEN}Backup complete!${NC}"
    log ""

    return 0
}

# Run main and capture exit code
if main; then
    exit 0
else
    log "${RED}ERROR: Backup failed${NC}"
    exit 1
fi
