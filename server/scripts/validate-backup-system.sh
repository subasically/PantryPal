#!/bin/bash

################################################################################
# PantryPal Backup System Validation Script
# 
# Purpose: Verify backup system is properly configured on production server
# Usage: ./validate-backup-system.sh
################################################################################

set -euo pipefail

echo "========================================="
echo "PantryPal Backup System Validator"
echo "========================================="
echo ""

ERRORS=0
WARNINGS=0

# Color codes
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
    ERRORS=$((ERRORS + 1))
}

warning() {
    echo -e "${YELLOW}⚠ WARNING: $1${NC}"
    WARNINGS=$((WARNINGS + 1))
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

info() {
    echo "  $1"
}

# Check 1: Scripts exist and are executable
echo "Checking scripts..."
if [ -x "/root/pantrypal-server/scripts/backup-database.sh" ]; then
    success "backup-database.sh is executable"
else
    error "backup-database.sh not found or not executable"
fi

if [ -x "/root/pantrypal-server/scripts/restore-database.sh" ]; then
    success "restore-database.sh is executable"
else
    error "restore-database.sh not found or not executable"
fi

echo ""

# Check 2: Directories exist
echo "Checking directories..."
if [ -d "/root/backups/pantrypal-db" ]; then
    success "Backup directory exists"
    info "Path: /root/backups/pantrypal-db"
    BACKUP_SIZE=$(du -sh /root/backups/pantrypal-db 2>/dev/null | cut -f1 || echo "0")
    info "Size: $BACKUP_SIZE"
else
    error "Backup directory not found: /root/backups/pantrypal-db"
fi

if [ -d "/root/pantrypal-server/logs" ]; then
    success "Log directory exists"
else
    warning "Log directory not found: /root/pantrypal-server/logs"
fi

echo ""

# Check 3: Docker container
echo "Checking Docker container..."
CONTAINER_NAME="pantrypal-server-pantrypal-api-1"
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    success "Container is running: $CONTAINER_NAME"
else
    error "Container not running: $CONTAINER_NAME"
fi

# Check database exists in container
if docker exec "$CONTAINER_NAME" test -f "/app/db/pantrypal.db" 2>/dev/null; then
    success "Database file found in container"
    DB_SIZE=$(docker exec "$CONTAINER_NAME" du -h /app/db/pantrypal.db 2>/dev/null | cut -f1 || echo "unknown")
    info "Database size: $DB_SIZE"
else
    error "Database file not found in container: /app/db/pantrypal.db"
fi

echo ""

# Check 4: Cron job
echo "Checking cron configuration..."
if crontab -l 2>/dev/null | grep -q "backup-database.sh"; then
    success "Cron job is configured"
    CRON_LINE=$(crontab -l 2>/dev/null | grep "backup-database.sh")
    info "Schedule: $CRON_LINE"
else
    error "Cron job not found in crontab"
fi

# Check cron service
if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
    success "Cron service is running"
else
    error "Cron service is not running"
fi

echo ""

# Check 5: Recent backups
echo "Checking recent backups..."
BACKUP_DIR="/root/backups/pantrypal-db"
if [ -d "$BACKUP_DIR" ]; then
    BACKUP_COUNT=$(find "$BACKUP_DIR" -name "pantrypal-*.db*" -type f 2>/dev/null | wc -l)
    
    if [ "$BACKUP_COUNT" -gt 0 ]; then
        success "Found $BACKUP_COUNT backup(s)"
        
        # Check for recent backup (within 48 hours)
        RECENT_BACKUP=$(find "$BACKUP_DIR" -name "pantrypal-*.db*" -type f -mtime -2 2>/dev/null | head -1)
        if [ -n "$RECENT_BACKUP" ]; then
            success "Recent backup found (< 48 hours old)"
            BACKUP_NAME=$(basename "$RECENT_BACKUP")
            BACKUP_AGE=$(stat -c %Y "$RECENT_BACKUP" 2>/dev/null || stat -f %m "$RECENT_BACKUP" 2>/dev/null || echo "0")
            CURRENT_TIME=$(date +%s)
            AGE_HOURS=$(( (CURRENT_TIME - BACKUP_AGE) / 3600 ))
            info "Latest: $BACKUP_NAME (${AGE_HOURS}h ago)"
        else
            warning "No recent backup found (last backup > 48 hours ago)"
        fi
    else
        warning "No backups found"
    fi
fi

echo ""

# Check 6: Log files
echo "Checking log files..."
if [ -f "/root/pantrypal-server/logs/backup.log" ]; then
    success "Backup log exists"
    LOG_SIZE=$(du -h "/root/pantrypal-server/logs/backup.log" 2>/dev/null | cut -f1 || echo "0")
    info "Log size: $LOG_SIZE"
    
    # Check for recent log entries
    if [ -s "/root/pantrypal-server/logs/backup.log" ]; then
        LAST_ENTRY=$(tail -1 "/root/pantrypal-server/logs/backup.log" 2>/dev/null || echo "")
        if [ -n "$LAST_ENTRY" ]; then
            info "Last log entry: $LAST_ENTRY"
        fi
    fi
else
    warning "Backup log not found"
fi

echo ""

# Check 7: Disk space
echo "Checking disk space..."
DISK_AVAIL=$(df -h /root/backups 2>/dev/null | awk 'NR==2 {print $4}' || echo "unknown")
DISK_USAGE=$(df -h /root/backups 2>/dev/null | awk 'NR==2 {print $5}' || echo "unknown")
if [ "$DISK_USAGE" != "unknown" ]; then
    USAGE_PCT=$(echo "$DISK_USAGE" | sed 's/%//')
    if [ "$USAGE_PCT" -lt 80 ]; then
        success "Sufficient disk space: $DISK_AVAIL available ($DISK_USAGE used)"
    elif [ "$USAGE_PCT" -lt 90 ]; then
        warning "Disk space low: $DISK_AVAIL available ($DISK_USAGE used)"
    else
        error "Critical disk space: $DISK_AVAIL available ($DISK_USAGE used)"
    fi
else
    warning "Could not determine disk space"
fi

echo ""

# Check 8: Required tools
echo "Checking required tools..."
for tool in sqlite3 gzip docker docker-compose; do
    if command -v "$tool" >/dev/null 2>&1; then
        success "$tool is installed"
    else
        error "$tool is not installed"
    fi
done

echo ""
echo "========================================="
echo "Validation Summary"
echo "========================================="

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "Backup system is properly configured and operational."
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Validation completed with $WARNINGS warning(s)${NC}"
    echo ""
    echo "Backup system is functional but has minor issues."
    exit 0
else
    echo -e "${RED}✗ Validation failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo "Please address the errors above before using the backup system."
    exit 1
fi
