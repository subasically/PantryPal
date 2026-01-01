#!/bin/bash

################################################################################
# PantryPal Database Backup Script
# 
# Purpose: Automated backup of production SQLite database from Docker volume
# Schedule: Daily at 2 AM UTC via cron
# Retention: 30 days of rolling backups
# Compression: Gzip for backups 7+ days old
# 
# Production database: docker volume pantrypal-data
# Container path: /app/db/pantrypal.db
################################################################################

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
BACKUP_DIR="/root/backups/pantrypal-db"
LOG_FILE="/root/pantrypal-server/logs/backup.log"
CONTAINER_NAME="pantrypal-server-pantrypal-api-1"
DB_PATH_IN_CONTAINER="/app/db/pantrypal.db"
RETENTION_DAYS=30
COMPRESS_AFTER_DAYS=7

# Timestamp format: YYYYMMDD-HHMMSS
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
DATE_ONLY=$(date +"%Y%m%d")
BACKUP_FILENAME="pantrypal-${TIMESTAMP}.db"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handler
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Create backup directory if it doesn't exist
log "Starting database backup..."
mkdir -p "$BACKUP_DIR" || error_exit "Failed to create backup directory"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    error_exit "Container ${CONTAINER_NAME} is not running"
fi

# Check if database exists in container
if ! docker exec "$CONTAINER_NAME" test -f "$DB_PATH_IN_CONTAINER"; then
    error_exit "Database file not found in container at ${DB_PATH_IN_CONTAINER}"
fi

# Perform backup using SQLite's backup command for consistency
log "Copying database from container..."
docker exec "$CONTAINER_NAME" sqlite3 "$DB_PATH_IN_CONTAINER" ".backup /tmp/backup-${TIMESTAMP}.db" || error_exit "SQLite backup command failed"

# Copy backup file from container to host
docker cp "${CONTAINER_NAME}:/tmp/backup-${TIMESTAMP}.db" "$BACKUP_PATH" || error_exit "Failed to copy backup from container"

# Clean up temp file in container
docker exec "$CONTAINER_NAME" rm -f "/tmp/backup-${TIMESTAMP}.db"

# Verify backup file integrity
if [ ! -f "$BACKUP_PATH" ]; then
    error_exit "Backup file not found at ${BACKUP_PATH}"
fi

BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
log "Backup created successfully: ${BACKUP_FILENAME} (${BACKUP_SIZE})"

# Verify backup integrity with SQLite
if sqlite3 "$BACKUP_PATH" "PRAGMA integrity_check;" | grep -q "ok"; then
    log "Backup integrity verified: OK"
else
    error_exit "Backup integrity check failed"
fi

# Compress backups older than 7 days
log "Compressing old backups (${COMPRESS_AFTER_DAYS}+ days old)..."
find "$BACKUP_DIR" -name "pantrypal-*.db" -type f -mtime +"$COMPRESS_AFTER_DAYS" | while read -r file; do
    if [ -f "$file" ] && [ ! -f "${file}.gz" ]; then
        log "Compressing: $(basename "$file")"
        gzip "$file" || log "WARNING: Failed to compress $file"
    fi
done

# Delete backups older than 30 days
log "Cleaning up old backups (${RETENTION_DAYS}+ days old)..."
DELETED_COUNT=0
find "$BACKUP_DIR" -name "pantrypal-*.db.gz" -type f -mtime +"$RETENTION_DAYS" -delete -print | while read -r file; do
    log "Deleted: $(basename "$file")"
    DELETED_COUNT=$((DELETED_COUNT + 1))
done

# Summary statistics
TOTAL_BACKUPS=$(find "$BACKUP_DIR" -name "pantrypal-*.db*" -type f | wc -l)
UNCOMPRESSED_BACKUPS=$(find "$BACKUP_DIR" -name "pantrypal-*.db" -type f | wc -l)
COMPRESSED_BACKUPS=$(find "$BACKUP_DIR" -name "pantrypal-*.db.gz" -type f | wc -l)
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)

log "Backup complete!"
log "Summary: ${TOTAL_BACKUPS} total backups (${UNCOMPRESSED_BACKUPS} uncompressed, ${COMPRESSED_BACKUPS} compressed), ${TOTAL_SIZE} total"
log "----------------------------------------"

exit 0
