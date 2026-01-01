# PantryPal Server Scripts

This directory contains operational scripts for managing the PantryPal production server.

## 📋 Scripts Overview

### `backup-database.sh`
Automated database backup script for production.

**Features:**
- Creates SQLite backup using `.backup` command (ACID-compliant)
- Verifies backup integrity with `PRAGMA integrity_check`
- Compresses backups older than 7 days with gzip
- Maintains 30-day rolling retention
- Logs all operations to `logs/backup.log`

**Usage:**
```bash
# Manual backup (production)
ssh root@62.146.177.62
/root/pantrypal-server/scripts/backup-database.sh

# Scheduled via cron (2 AM UTC daily)
0 2 * * * /root/pantrypal-server/scripts/backup-database.sh
```

**Configuration:**
- `BACKUP_DIR`: `/root/backups/pantrypal-db/`
- `LOG_FILE`: `/root/pantrypal-server/logs/backup.log`
- `CONTAINER_NAME`: `pantrypal-server-pantrypal-api-1`
- `RETENTION_DAYS`: 30
- `COMPRESS_AFTER_DAYS`: 7

---

### `restore-database.sh`
Database restore script with safety checks.

**Features:**
- Lists available backups with `--list` flag
- Creates pre-restore backup automatically
- Verifies backup integrity before restore
- Handles compressed (.db.gz) backups
- Stops container during restore to prevent locks
- Verifies restored database integrity

**Usage:**
```bash
# List available backups
./restore-database.sh --list

# Restore specific backup (REQUIRES --confirm flag)
./restore-database.sh pantrypal-20260101-020000.db --confirm

# Restore compressed backup
./restore-database.sh pantrypal-20251225-020000.db.gz --confirm

# Restore with full path
./restore-database.sh /root/backups/pantrypal-db/pantrypal-20260101-020000.db --confirm
```

**Safety Features:**
- Requires `--confirm` flag to prevent accidental restores
- Creates pre-restore backup (saved as `pre-restore-TIMESTAMP.db`)
- Verifies backup integrity before overwriting production database
- Stops container to ensure clean restore
- Logs all operations

---

### `test-backup-system.sh`
Local test script for backup/restore functionality.

**Tests:**
1. Database file existence check
2. SQLite backup command functionality
3. Backup script execution
4. Compression (gzip)
5. Decompression
6. Backup integrity verification
7. Retention/cleanup logic simulation

**Usage:**
```bash
# Run all tests (requires local Docker container)
./test-backup-system.sh

# Clean up test artifacts
rm -rf test-backups test-logs test-backup-local.sh
```

**Requirements:**
- Local Docker container running: `pantrypal-server-pantrypal-api-1`
- Start with: `cd server && docker-compose up -d`

---

## 🚀 Production Setup

### Initial Deployment

1. **Copy scripts to production:**
```bash
scp server/scripts/*.sh root@62.146.177.62:/root/pantrypal-server/scripts/
```

2. **Set permissions:**
```bash
ssh root@62.146.177.62
chmod +x /root/pantrypal-server/scripts/*.sh
```

3. **Create directories:**
```bash
mkdir -p /root/backups/pantrypal-db
mkdir -p /root/pantrypal-server/logs
```

4. **Test backup manually:**
```bash
/root/pantrypal-server/scripts/backup-database.sh
```

5. **Install cron job:**
```bash
crontab -e
# Add: 0 2 * * * /root/pantrypal-server/scripts/backup-database.sh >> /root/pantrypal-server/logs/backup-cron.log 2>&1
```

6. **Verify:**
```bash
crontab -l | grep backup
ls -lh /root/backups/pantrypal-db/
tail /root/pantrypal-server/logs/backup.log
```

---

## 📊 Monitoring

### Check Backup Status
```bash
# View recent logs
tail -50 /root/pantrypal-server/logs/backup.log

# List backups
ls -lht /root/backups/pantrypal-db/ | head -10

# Check total size
du -sh /root/backups/pantrypal-db/

# Count backups
find /root/backups/pantrypal-db/ -name "pantrypal-*.db*" | wc -l
```

### Verify Latest Backup
```bash
# Find latest backup
LATEST=$(ls -t /root/backups/pantrypal-db/pantrypal-*.db 2>/dev/null | head -1)

# Check integrity
sqlite3 "$LATEST" "PRAGMA integrity_check;"
# Should output: ok
```

---

## 🔧 Troubleshooting

### Backup Not Created
```bash
# Check cron is running
systemctl status cron

# Check cron job installed
crontab -l | grep backup

# Run manually to see errors
/root/pantrypal-server/scripts/backup-database.sh

# Check container name
docker ps --format '{{.Names}}'
```

### Disk Space Full
```bash
# Check disk usage
df -h /root/backups

# Delete old backups (60+ days)
find /root/backups/pantrypal-db/ -name "pantrypal-*.db.gz" -mtime +60 -delete

# Compress recent backups
find /root/backups/pantrypal-db/ -name "pantrypal-*.db" -mtime +1 -exec gzip {} \;
```

### Restore Failed
```bash
# Check pre-restore backup exists
ls -lh /root/backups/pantrypal-db/pre-restore-*.db

# Verify backup file integrity
sqlite3 BACKUP_FILE.db "PRAGMA integrity_check;"

# Check container status
docker ps | grep pantrypal

# Review logs
tail -100 /root/pantrypal-server/logs/backup.log
```

---

## 📝 Best Practices

1. **Test restores monthly** to ensure backups are valid
2. **Monitor disk space** regularly
3. **Keep pre-restore backups** for at least 7 days
4. **Set up off-site backups** (rsync, S3, etc.)
5. **Alert on failures** using monitoring tools
6. **Document any changes** to scripts or procedures

---

## 🔐 Security Notes

- Backup directory should have restricted permissions (700)
- Only root should have access to restore script
- Pre-restore backups prevent data loss from accidental restores
- Always verify backup integrity before restore

---

## 📚 References

- Deployment Guide: `../../DEPLOYMENT.md`
- SQLite Backup: https://www.sqlite.org/backup.html
- Cron Reference: https://crontab.guru/

---

**Last Updated:** 2026-01-01
**Version:** 1.0.0
