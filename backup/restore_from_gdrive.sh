#!/bin/bash

# ========================================
# MASALA DB - GOOGLE DRIVE RESTORATION
# ========================================
# Downloads and restores SQL backup from Google Drive
# Verifies checksum before restoration
# Adapted from GuruColdStorage restore system
#
# Usage:
#   Interactive:     ./restore_from_gdrive.sh
#   Non-interactive: ./restore_from_gdrive.sh --backup <filename|latest> --yes [--cleanup]
#
# Options:
#   --backup <name>   Backup filename (e.g. masala_backup_20260211_214120.sql) or "latest"
#   --yes             Skip confirmation prompt (required for non-interactive)
#   --cleanup         Delete downloaded restore files after restore
#   --list            List available backups and exit

set -e

CONTAINER_NAME="masala-db"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_RESTORE_DIR="$SCRIPT_DIR/restore"
GDRIVE_FOLDER="gdrive2:/masala_backups"

# Parse arguments
BACKUP_ARG=""
AUTO_YES=false
AUTO_CLEANUP=false
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --backup)
            BACKUP_ARG="$2"
            shift 2
            ;;
        --yes)
            AUTO_YES=true
            shift
            ;;
        --cleanup)
            AUTO_CLEANUP=true
            shift
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--backup <filename|latest>] [--yes] [--cleanup] [--list]"
            echo ""
            echo "Options:"
            echo "  --backup <name>   Backup filename or \"latest\" for most recent"
            echo "  --yes             Skip confirmation prompt"
            echo "  --cleanup         Delete downloaded restore files after restore"
            echo "  --list            List available backups and exit"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage"
            exit 1
            ;;
    esac
done

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

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Masala DB - Google Drive Restoration${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Create restore directory
mkdir -p "$LOCAL_RESTORE_DIR"

# Step 1: List available backups
echo -e "${YELLOW}[1/6] Fetching available backups from Google Drive...${NC}"
BACKUP_LIST=$(rclone lsf "$GDRIVE_FOLDER" | grep "masala_backup_.*\.sql$" | sort -r)

if [ -z "$BACKUP_LIST" ]; then
    echo -e "${RED}No backups found in Google Drive${NC}"
    exit 1
fi

echo -e "${GREEN}Available backups:${NC}"
echo ""
i=1
declare -a BACKUPS
while IFS= read -r backup; do
    BACKUPS[$i]="$backup"
    # Extract timestamp from filename
    TIMESTAMP=$(echo "$backup" | sed 's/masala_backup_\(.*\)\.sql/\1/')
    # Format timestamp for display
    DISPLAY_DATE=$(echo "$TIMESTAMP" | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)_\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')

    # Get file size
    SIZE=$(rclone size "$GDRIVE_FOLDER/$backup" --json | grep -o '"bytes":[0-9]*' | cut -d':' -f2)
    SIZE_MB=$((SIZE / 1024 / 1024))

    echo -e "${BLUE}$i)${NC} $DISPLAY_DATE (${SIZE_MB}MB) - $backup"
    ((i++))
done <<< "$BACKUP_LIST"
echo ""

# If --list, exit after showing backups
if [ "$LIST_ONLY" = true ]; then
    exit 0
fi

# Select backup: via argument or interactive prompt
if [ -n "$BACKUP_ARG" ]; then
    if [ "$BACKUP_ARG" = "latest" ]; then
        SELECTED_BACKUP="${BACKUPS[1]}"
        echo -e "${GREEN}Auto-selected latest: $SELECTED_BACKUP${NC}"
    else
        # Match by filename
        SELECTED_BACKUP=""
        for idx in "${!BACKUPS[@]}"; do
            if [ "${BACKUPS[$idx]}" = "$BACKUP_ARG" ]; then
                SELECTED_BACKUP="$BACKUP_ARG"
                break
            fi
        done
        if [ -z "$SELECTED_BACKUP" ]; then
            echo -e "${RED}Backup not found: $BACKUP_ARG${NC}"
            echo -e "${RED}Use --list to see available backups${NC}"
            exit 1
        fi
        echo -e "${GREEN}Selected: $SELECTED_BACKUP${NC}"
    fi
else
    read -p "Select backup to restore (1-$((i-1))): " selection
    if [ -z "${BACKUPS[$selection]}" ]; then
        echo -e "${RED}Invalid selection${NC}"
        exit 1
    fi
    SELECTED_BACKUP="${BACKUPS[$selection]}"
    echo -e "${GREEN}Selected: $SELECTED_BACKUP${NC}"
fi
echo ""

# Step 2: Download backup
echo -e "${YELLOW}[2/6] Downloading backup from Google Drive...${NC}"
RESTORE_FILE="${LOCAL_RESTORE_DIR}/${SELECTED_BACKUP}"
rclone copy "$GDRIVE_FOLDER/$SELECTED_BACKUP" "$LOCAL_RESTORE_DIR" --progress
echo -e "${GREEN}Downloaded: $RESTORE_FILE${NC}"
echo ""

# Step 3: Download and verify checksum
echo -e "${YELLOW}[3/6] Verifying backup integrity...${NC}"
if rclone copy "$GDRIVE_FOLDER/${SELECTED_BACKUP}.sha256" "$LOCAL_RESTORE_DIR" 2>/dev/null; then
    cd "$LOCAL_RESTORE_DIR"
    if sha256sum -c "${SELECTED_BACKUP}.sha256" > /dev/null 2>&1; then
        echo -e "${GREEN}Checksum verified - backup is intact${NC}"
    else
        echo -e "${RED}Checksum verification failed!${NC}"
        echo -e "${RED}Backup may be corrupted. Aborting.${NC}"
        exit 1
    fi
    cd - > /dev/null
else
    echo -e "${YELLOW}Warning: No checksum file found, skipping verification${NC}"
fi
echo ""

# Step 4: Pre-restoration checks
echo -e "${YELLOW}[4/6] Pre-restoration checks...${NC}"

if ! docker exec $CONTAINER_NAME psql -U postgres -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "${RED}Database is not running!${NC}"
    exit 1
fi

EXISTING_TABLES=$(docker exec $CONTAINER_NAME psql -U postgres -d postgres -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';" | tr -d ' ')
echo -e "${BLUE}  Existing tables in database: $EXISTING_TABLES${NC}"

BACKUP_TABLES=$(grep -c "^CREATE TABLE" "$RESTORE_FILE" || echo "0")
BACKUP_FUNCTIONS=$(grep -c "^CREATE FUNCTION" "$RESTORE_FILE" || echo "0")
echo -e "${BLUE}  Tables in backup: $BACKUP_TABLES${NC}"
echo -e "${BLUE}  Functions in backup: $BACKUP_FUNCTIONS${NC}"
echo ""

# Warning if database is not empty
if [ "$EXISTING_TABLES" -gt 0 ]; then
    echo -e "${RED}WARNING: Database is not empty!${NC}"
    echo -e "${YELLOW}This will DROP all existing tables and data!${NC}"
    echo ""
    if [ "$AUTO_YES" = true ]; then
        echo -e "${YELLOW}--yes flag set, proceeding automatically${NC}"
    else
        read -p "Are you SURE you want to continue? Type 'YES' to confirm: " confirm
        if [ "$confirm" != "YES" ]; then
            echo -e "${RED}Restoration cancelled${NC}"
            exit 1
        fi
    fi
fi
echo ""

# Step 5: Restore database
echo -e "${YELLOW}[5/6] Restoring database...${NC}"
echo -e "${BLUE}This may take several minutes for large databases...${NC}"
echo ""

# Stop supavisor to avoid connection issues during restore
echo -e "${BLUE}  Stopping supavisor...${NC}"
docker stop masala-supavisor 2>/dev/null || true

# Restore database
if docker exec -i $CONTAINER_NAME psql -U postgres -d postgres < "$RESTORE_FILE"; then
    echo ""
    echo -e "${GREEN}Database restored successfully${NC}"
else
    echo ""
    echo -e "${RED}Restoration failed! Check error messages above.${NC}"
    docker start masala-supavisor 2>/dev/null || true
    exit 1
fi
echo ""

# Restart supavisor
echo -e "${BLUE}  Starting supavisor...${NC}"
docker start masala-supavisor 2>/dev/null || true

# Step 6: Verify restoration
echo -e "${YELLOW}[6/6] Verifying restoration...${NC}"

RESTORED_TABLES=$(docker exec $CONTAINER_NAME psql -U postgres -d postgres -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public';" | tr -d ' ')
RESTORED_FUNCTIONS=$(docker exec $CONTAINER_NAME psql -U postgres -d postgres -t -c "SELECT COUNT(*) FROM pg_proc WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');" | tr -d ' ')

echo -e "${BLUE}  Tables restored: $RESTORED_TABLES${NC}"
echo -e "${BLUE}  Functions restored: $RESTORED_FUNCTIONS${NC}"

if [ "$RESTORED_TABLES" -eq "$BACKUP_TABLES" ]; then
    echo -e "${GREEN}Table count matches backup${NC}"
else
    echo -e "${YELLOW}Warning: Table count differs (backup: $BACKUP_TABLES, restored: $RESTORED_TABLES)${NC}"
fi
echo ""

# Test basic queries on Masala tables
echo -e "${YELLOW}Testing basic queries...${NC}"
if docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "SELECT COUNT(*) FROM users;" > /dev/null 2>&1; then
    USER_COUNT=$(docker exec $CONTAINER_NAME psql -U postgres -d postgres -t -c "SELECT COUNT(*) FROM users;" | tr -d ' ')
    echo -e "${GREEN}users table accessible ($USER_COUNT users)${NC}"
else
    echo -e "${YELLOW}users table not found (may be expected for fresh DB)${NC}"
fi

if docker exec $CONTAINER_NAME psql -U postgres -d postgres -c "SELECT COUNT(*) FROM products;" > /dev/null 2>&1; then
    PRODUCT_COUNT=$(docker exec $CONTAINER_NAME psql -U postgres -d postgres -t -c "SELECT COUNT(*) FROM products;" | tr -d ' ')
    echo -e "${GREEN}products table accessible ($PRODUCT_COUNT products)${NC}"
else
    echo -e "${YELLOW}products table not found (may be expected for fresh DB)${NC}"
fi
echo ""

# Cleanup
if [ "$AUTO_CLEANUP" = true ]; then
    rm -rf "$LOCAL_RESTORE_DIR"
    echo -e "${GREEN}Restore files deleted (--cleanup)${NC}"
elif [ -t 0 ]; then
    echo -e "${YELLOW}Delete downloaded restore files? (y/n):${NC}"
    read -t 10 -p "" cleanup_choice || cleanup_choice="n"
    if [[ "$cleanup_choice" =~ ^[Yy]$ ]]; then
        rm -rf "$LOCAL_RESTORE_DIR"
        echo -e "${GREEN}Restore files deleted${NC}"
    else
        echo -e "${BLUE}  Restore files kept: $LOCAL_RESTORE_DIR${NC}"
    fi
else
    echo -e "${BLUE}  Restore files kept: $LOCAL_RESTORE_DIR${NC}"
fi
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Restoration Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Restored from: $SELECTED_BACKUP"
echo -e "Tables:        $RESTORED_TABLES"
echo -e "Functions:     $RESTORED_FUNCTIONS"
echo -e "Timestamp:     $(date)"
echo ""
echo -e "${GREEN}Database is ready to use!${NC}"
echo ""
