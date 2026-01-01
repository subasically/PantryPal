#!/bin/bash

################################################################################
# PantryPal Database Restore Script
# 
# Purpose: Restore SQLite database from backup to Docker volume
# Usage: ./restore-database.sh [backup-file] [--confirm]
# 
# CAUTION: This will OVERWRITE the current production database!
################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
BACKUP_DIR="/root/backups/pantrypal-db"
LOG_FILE="/root/pantrypal-server/logs/backup.log"
CONTAINER_NAME="pantrypal-server-pantrypal-api-1"
DB_PATH_IN_CONTAINER="/app/db/pantrypal.db"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handler
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Usage information
usage() {
    cat << EOF
PantryPal Database Restore Script

Usage:
    $0 [backup-file] --confirm

Arguments:
    backup-file    Path to backup file or filename in ${BACKUP_DIR}
                   Can be .db or .db.gz format
    --confirm      Required flag to confirm restore operation

Examples:
    # Restore specific backup
    $0 pantrypal-20260101-020000.db --confirm
    
    # Restore compressed backup
    $0 pantrypal-20251225-020000.db.gz --confirm
    
    # Restore with full path
    $0 /root/backups/pantrypal-db/pantrypal-20260101-020000.db --confirm
    
    # List available backups
    $0 --list

EOF
    exit 1
}

# List available backups
list_backups() {
    log "Available backups in ${BACKUP_DIR}:"
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        echo "No backups found."
        exit 0
    fi
    
    # List backups with details
    find "$BACKUP_DIR" -name "pantrypal-*.db*" -type f -printf "%T@ %p\n" | \
        sort -rn | \
        while read -r timestamp filepath; do
            filename=$(basename "$filepath")
            filesize=$(du -h "$filepath" | cut -f1)
            filedate=$(date -d "@${timestamp}" "+%Y-%m-%d %H:%M:%S")
            echo "  ${filename} (${filesize}, ${filedate})"
        done
    
    echo ""
    exit 0
}

# Parse arguments
if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
fi

if [ "$1" = "--list" ] || [ "$1" = "-l" ]; then
    list_backups
fi

if [ $# -lt 2 ]; then
    error_exit "Missing required arguments. Use --help for usage information."
fi

BACKUP_FILE="$1"
CONFIRM_FLAG="$2"

# Validate confirmation flag
if [ "$CONFIRM_FLAG" != "--confirm" ]; then
    error_exit "Missing --confirm flag. This operation will OVERWRITE the production database!"
fi

# Resolve backup file path
if [ ! -f "$BACKUP_FILE" ]; then
    # Try looking in backup directory
    if [ -f "${BACKUP_DIR}/${BACKUP_FILE}" ]; then
        BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILE}"
    else
        error_exit "Backup file not found: ${BACKUP_FILE}"
    fi
fi

log "========================================="
log "STARTING DATABASE RESTORE"
log "========================================="
log "Backup file: ${BACKUP_FILE}"
log "Target: ${CONTAINER_NAME}:${DB_PATH_IN_CONTAINER}"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    error_exit "Container ${CONTAINER_NAME} is not running"
fi

# Create pre-restore backup of current database
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
PRE_RESTORE_BACKUP="${BACKUP_DIR}/pre-restore-${TIMESTAMP}.db"

log "Creating pre-restore backup of current database..."
docker exec "$CONTAINER_NAME" sqlite3 "$DB_PATH_IN_CONTAINER" ".backup /tmp/pre-restore-${TIMESTAMP}.db" || error_exit "Failed to create pre-restore backup"
docker cp "${CONTAINER_NAME}:/tmp/pre-restore-${TIMESTAMP}.db" "$PRE_RESTORE_BACKUP" || error_exit "Failed to copy pre-restore backup"
docker exec "$CONTAINER_NAME" rm -f "/tmp/pre-restore-${TIMESTAMP}.db"

PRE_RESTORE_SIZE=$(du -h "$PRE_RESTORE_BACKUP" | cut -f1)
log "Pre-restore backup saved: pre-restore-${TIMESTAMP}.db (${PRE_RESTORE_SIZE})"

# Decompress if necessary
RESTORE_FILE="$BACKUP_FILE"
if [[ "$BACKUP_FILE" == *.gz ]]; then
    log "Decompressing backup file..."
    RESTORE_FILE="/tmp/pantrypal-restore-${TIMESTAMP}.db"
    gunzip -c "$BACKUP_FILE" > "$RESTORE_FILE" || error_exit "Failed to decompress backup"
fi

# Verify backup integrity
log "Verifying backup integrity..."
if ! sqlite3 "$RESTORE_FILE" "PRAGMA integrity_check;" | grep -q "ok"; then
    rm -f "$RESTORE_FILE"
    error_exit "Backup integrity check failed. Restore aborted."
fi
log "Backup integrity: OK"

# Stop the container to prevent database locks
log "Stopping container for safe restore..."
docker-compose -f /root/pantrypal-server/docker-compose.yml stop || error_exit "Failed to stop container"

# Copy restore file to container's temp location
TEMP_RESTORE_PATH="/tmp/pantrypal-restore-${TIMESTAMP}.db"
log "Copying restore file to container..."
docker cp "$RESTORE_FILE" "${CONTAINER_NAME}:${TEMP_RESTORE_PATH}" || error_exit "Failed to copy restore file to container"

# Start container temporarily to perform restore
log "Starting container for restore operation..."
docker-compose -f /root/pantrypal-server/docker-compose.yml start || error_exit "Failed to start container"
sleep 5  # Wait for container to fully start

# Perform the restore
log "Restoring database..."
docker exec "$CONTAINER_NAME" sh -c "cp ${TEMP_RESTORE_PATH} ${DB_PATH_IN_CONTAINER}" || error_exit "Failed to restore database"

# Clean up temp files
docker exec "$CONTAINER_NAME" rm -f "$TEMP_RESTORE_PATH"
if [ "$RESTORE_FILE" != "$BACKUP_FILE" ]; then
    rm -f "$RESTORE_FILE"
fi

# Verify restored database
log "Verifying restored database..."
if ! docker exec "$CONTAINER_NAME" sqlite3 "$DB_PATH_IN_CONTAINER" "PRAGMA integrity_check;" | grep -q "ok"; then
    error_exit "Restored database failed integrity check!"
fi

# Restart container
log "Restarting container..."
docker-compose -f /root/pantrypal-server/docker-compose.yml restart || error_exit "Failed to restart container"
sleep 5

# Verify container is healthy
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    error_exit "Container failed to start after restore"
fi

RESTORED_SIZE=$(docker exec "$CONTAINER_NAME" du -h "$DB_PATH_IN_CONTAINER" | cut -f1)
log "Database restored successfully (${RESTORED_SIZE})"
log "Pre-restore backup saved at: ${PRE_RESTORE_BACKUP}"
log "========================================="
log "RESTORE COMPLETE"
log "========================================="

exit 0
