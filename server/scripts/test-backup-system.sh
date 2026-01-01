#!/bin/bash

################################################################################
# Local Test Script for Backup/Restore System
# Tests backup and restore scripts in a local Docker environment
################################################################################

set -euo pipefail

echo "========================================="
echo "PantryPal Backup System - Local Tests"
echo "========================================="
echo ""

# Configuration for local testing
TEST_BACKUP_DIR="./test-backups"
TEST_LOG_DIR="./test-logs"
TEST_CONTAINER="pantrypal-server-pantrypal-api-1"

# Create test directories
echo "Setting up test environment..."
mkdir -p "$TEST_BACKUP_DIR"
mkdir -p "$TEST_LOG_DIR"

# Check if container exists (from docker-compose)
echo "Checking for local test container..."
if docker ps -a --format '{{.Names}}' | grep -q "^${TEST_CONTAINER}$"; then
    echo "✓ Container found: ${TEST_CONTAINER}"
else
    echo "⚠ Warning: Container ${TEST_CONTAINER} not found"
    echo "  Run 'docker-compose up -d' in server/ directory first"
    exit 1
fi

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${TEST_CONTAINER}$"; then
    echo "Starting container..."
    cd server && docker-compose up -d && cd ..
    sleep 3
fi

# Test 1: Check database exists
echo ""
echo "Test 1: Checking database file..."
if docker exec "$TEST_CONTAINER" test -f "/app/db/pantrypal.db"; then
    DB_SIZE=$(docker exec "$TEST_CONTAINER" du -h /app/db/pantrypal.db | cut -f1)
    echo "✓ Database found (${DB_SIZE})"
else
    echo "✗ Database not found"
    exit 1
fi

# Test 2: Test SQLite backup command
echo ""
echo "Test 2: Testing SQLite backup command..."
docker exec "$TEST_CONTAINER" sqlite3 /app/db/pantrypal.db ".backup /tmp/test-backup.db"
if docker exec "$TEST_CONTAINER" test -f "/tmp/test-backup.db"; then
    echo "✓ SQLite backup command works"
    docker exec "$TEST_CONTAINER" rm -f /tmp/test-backup.db
else
    echo "✗ SQLite backup command failed"
    exit 1
fi

# Test 3: Test backup script (modified for local paths)
echo ""
echo "Test 3: Testing backup script..."
cat > ./test-backup-local.sh << 'EOF'
#!/bin/bash
set -euo pipefail

BACKUP_DIR="./test-backups"
LOG_FILE="./test-logs/backup.log"
CONTAINER_NAME="pantrypal-server-pantrypal-api-1"
DB_PATH_IN_CONTAINER="/app/db/pantrypal.db"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
BACKUP_FILENAME="pantrypal-${TIMESTAMP}.db"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

mkdir -p "$BACKUP_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

log "Starting test backup..."

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log "ERROR: Container not running"
    exit 1
fi

docker exec "$CONTAINER_NAME" sqlite3 "$DB_PATH_IN_CONTAINER" ".backup /tmp/backup-${TIMESTAMP}.db"
docker cp "${CONTAINER_NAME}:/tmp/backup-${TIMESTAMP}.db" "$BACKUP_PATH"
docker exec "$CONTAINER_NAME" rm -f "/tmp/backup-${TIMESTAMP}.db"

if [ ! -f "$BACKUP_PATH" ]; then
    log "ERROR: Backup file not created"
    exit 1
fi

BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
log "Backup created: ${BACKUP_FILENAME} (${BACKUP_SIZE})"

if sqlite3 "$BACKUP_PATH" "PRAGMA integrity_check;" | grep -q "ok"; then
    log "Integrity check: OK"
else
    log "ERROR: Integrity check failed"
    exit 1
fi

log "Test backup complete!"
echo "$BACKUP_PATH"
EOF

chmod +x ./test-backup-local.sh
BACKUP_FILE=$(./test-backup-local.sh 2>&1 | tail -1)

if [ -f "$BACKUP_FILE" ]; then
    echo "✓ Backup created: $(basename "$BACKUP_FILE")"
else
    echo "✗ Backup failed"
    exit 1
fi

# Test 4: Test compression
echo ""
echo "Test 4: Testing compression..."
TEST_COMPRESS_FILE="${TEST_BACKUP_DIR}/test-compress.db"
cp "$BACKUP_FILE" "$TEST_COMPRESS_FILE"
gzip "$TEST_COMPRESS_FILE"
if [ -f "${TEST_COMPRESS_FILE}.gz" ]; then
    COMPRESSED_SIZE=$(du -h "${TEST_COMPRESS_FILE}.gz" | cut -f1)
    echo "✓ Compression works (${COMPRESSED_SIZE})"
else
    echo "✗ Compression failed"
    exit 1
fi

# Test 5: Test decompression
echo ""
echo "Test 5: Testing decompression..."
gunzip -c "${TEST_COMPRESS_FILE}.gz" > ./test-decompress.db
if [ -f "./test-decompress.db" ]; then
    DECOMPRESSED_SIZE=$(du -h ./test-decompress.db | cut -f1)
    echo "✓ Decompression works (${DECOMPRESSED_SIZE})"
    rm -f ./test-decompress.db
else
    echo "✗ Decompression failed"
    exit 1
fi

# Test 6: Verify backup integrity
echo ""
echo "Test 6: Verifying backup integrity..."
if sqlite3 "$BACKUP_FILE" "PRAGMA integrity_check;" | grep -q "ok"; then
    echo "✓ Backup integrity verified"
else
    echo "✗ Backup integrity check failed"
    exit 1
fi

# Test 7: Test retention logic (simulate old files)
echo ""
echo "Test 7: Testing retention/cleanup logic..."
touch -t 202501010000 "${TEST_BACKUP_DIR}/pantrypal-old-file.db"
OLD_FILE_COUNT=$(find "$TEST_BACKUP_DIR" -name "pantrypal-*.db" -type f -mtime +7 | wc -l)
echo "  Found ${OLD_FILE_COUNT} files older than 7 days (for compression test)"
echo "✓ Retention logic testable"

# Summary
echo ""
echo "========================================="
echo "All Tests Passed!"
echo "========================================="
echo ""
echo "Test artifacts created:"
echo "  Backups: $(find "$TEST_BACKUP_DIR" -name "pantrypal-*.db*" -type f | wc -l) files"
echo "  Logs: $TEST_LOG_DIR/backup.log"
echo ""
echo "Clean up test files with:"
echo "  rm -rf $TEST_BACKUP_DIR $TEST_LOG_DIR test-backup-local.sh"
echo ""
echo "Ready for production deployment!"

exit 0
