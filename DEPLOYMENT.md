# Deployment Guide

## 📦 Latest Changes (Dec 30, 2024)

### ✨ Premium Lifecycle Management
1. **Database**: Added `premium_expires_at` column to `households` table
2. **Premium Logic**: Graceful expiration (no immediate cutoff)
3. **Auto-Add**: Checkout-to-zero now triggers grocery auto-add for Premium
4. **Downgrade**: Read-only above limits (no data deletion)

### Files Modified:
Server:
- `server/db/schema.sql` (added premium_expires_at, grocery_items)
- `server/src/models/database.js` (migration)
- `server/src/utils/premiumHelper.js` (NEW - Premium logic)
- `server/src/routes/inventory.js` (use new helper)
- `server/src/routes/checkout.js` (auto-add on checkout)
- `server/src/routes/auth.js` (return premiumExpiresAt)
- `server/src/routes/admin.js` (support expiration)

iOS:
- `ios/PantryPal/Models/Models.swift` (Household model with expiration)

---

## 🚀 Deployment Steps

### Server Deployment (VPS: 62.146.177.62)

```bash
# 1. SSH to server
ssh root@62.146.177.62

# 2. Navigate to server directory
cd /root/pantrypal-server

# 3. Copy updated files from local (run from your machine)
# Option A: Use rsync for entire server directory
rsync -avz --exclude='node_modules' --exclude='db/pantrypal.db' \
  server/ root@62.146.177.62:/root/pantrypal-server/

# Option B: Copy specific files with scp
scp server/src/routes/*.js root@62.146.177.62:/root/pantrypal-server/src/routes/
scp server/src/utils/*.js root@62.146.177.62:/root/pantrypal-server/src/utils/
scp server/src/models/*.js root@62.146.177.62:/root/pantrypal-server/src/models/
scp server/db/schema.sql root@62.146.177.62:/root/pantrypal-server/db/

# 4. Back on server: Restart the container
docker-compose restart server

# 5. Check logs for migration success
docker-compose logs -f server | grep -i "migration"
# Should see: "Migration successful: premium_expires_at added"

# 6. Verify database schema
docker-compose exec server sh -c "sqlite3 /app/db/pantrypal.db 'PRAGMA table_info(households);'"
# Should show: premium_expires_at DATETIME column

docker-compose exec server sh -c "sqlite3 /app/db/pantrypal.db '.tables'"
# Should show: grocery_items table
```

### Testing After Deployment

```bash
# 1. Test auth endpoint returns premiumExpiresAt
curl -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  http://62.146.177.62/api/auth/me

# Expected response:
# {
#   "user": {...},
#   "household": {
#     "id": "...",
#     "isPremium": true/false,
#     "premiumExpiresAt": null or "2025-12-31T23:59:59Z"
#   }
# }

# 2. Test Premium simulation (DEBUG only)
curl -X POST \
  -H "x-admin-key: YOUR_ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"isPremium": true, "expiresAt": "2025-12-31T23:59:59Z"}' \
  http://62.146.177.62/api/admin/households/HOUSEHOLD_ID/premium

# 3. Test checkout auto-add to grocery
# - Checkout an item to qty=0 via app
# - Check grocery list for auto-added item (Premium only)
# - Server logs should show: "[Grocery] Auto-added ... to grocery list"
```

---

## 🔧 Manual Migration (If Needed)

If automatic migration doesn't run:

```bash
# SSH to server
ssh root@62.146.177.62

# Add premium_expires_at column manually
docker-compose exec server sh -c "sqlite3 /app/db/pantrypal.db \
  'ALTER TABLE households ADD COLUMN premium_expires_at DATETIME;'"

# Verify
docker-compose exec server sh -c "sqlite3 /app/db/pantrypal.db \
  'PRAGMA table_info(households);'"

# Create grocery_items table if missing
docker-compose exec server sh -c "sqlite3 /app/db/pantrypal.db < /app/db/schema.sql"
```

---

## 📱 iOS App

No additional deployment needed. Changes are in the app binary:
- Household model now includes `premiumExpiresAt`
- Premium status checks expiration date client-side
- Offline Premium caching supported

### TestFlight Update
1. Archive build in Xcode
2. Upload to App Store Connect
3. Add to TestFlight
4. Test Premium lifecycle flows

---

## 🧪 Testing Scenarios

### 1. Premium Active (No Expiration)
```sql
UPDATE households SET is_premium = 1, premium_expires_at = NULL WHERE id = 'xxx';
```
✅ All Premium features work

### 2. Premium with Future Expiration
```sql
UPDATE households SET is_premium = 1, premium_expires_at = '2025-12-31 23:59:59' WHERE id = 'xxx';
```
✅ Premium works until Dec 31, 2025

### 3. Premium Expired
```sql
UPDATE households SET is_premium = 1, premium_expires_at = '2024-01-01 00:00:00' WHERE id = 'xxx';
```
✅ Downgraded to free (read-only above 25 items)

### 4. Checkout Auto-Add
- Premium household checks out last item (qty → 0)
- ✅ Item auto-added to grocery list
- Check logs: `[Grocery] Auto-added "Product Name" to grocery list (Premium, checkout)`

### 5. Free Over Limit
- Household has 30 items, is_premium = 0
- ✅ Can view existing items
- ❌ Cannot add new items (403 error)

---

## 🚨 Troubleshooting

### Migration Not Running
```bash
# Check if column exists
docker-compose exec server sh -c "sqlite3 /app/db/pantrypal.db \
  'PRAGMA table_info(households);'" | grep premium_expires_at

# If missing, add manually (see Manual Migration above)
```

### Premium Not Working
1. Check household: `SELECT * FROM households WHERE id = 'xxx';`
2. Verify `is_premium = 1`
3. Check `premium_expires_at` is NULL or future date
4. Restart: `docker-compose restart server`
5. Clear iOS cache: Delete app and reinstall

### Auto-Add Not Working
1. Check server logs: `docker-compose logs server | grep Grocery`
2. Verify household is Premium: `isHouseholdPremium()` returns true
3. Check inventory quantity went from >0 to 0
4. Verify product has a name

---

## 📊 Monitoring

### Server Logs
```bash
# All logs
docker-compose logs -f server

# Premium checks
docker-compose logs server | grep -i premium

# Grocery auto-add
docker-compose logs server | grep -i grocery

# Errors
docker-compose logs server | grep -i error
```

### Database Queries
```bash
# Check Premium households
docker-compose exec server sh -c "sqlite3 /app/db/pantrypal.db \
  'SELECT id, name, is_premium, premium_expires_at FROM households;'"

# Check grocery items
docker-compose exec server sh -c "sqlite3 /app/db/pantrypal.db \
  'SELECT h.name, gi.name, gi.created_at 
   FROM grocery_items gi 
   JOIN households h ON gi.household_id = h.id 
   ORDER BY gi.created_at DESC LIMIT 10;'"

# Check expiring Premium households (within 7 days)
docker-compose exec server sh -c "sqlite3 /app/db/pantrypal.db \
  'SELECT id, name, premium_expires_at 
   FROM households 
   WHERE is_premium = 1 
   AND premium_expires_at IS NOT NULL 
   AND premium_expires_at < datetime(\"now\", \"+7 days\");'"
```

---

## 🔙 Rollback Plan

If deployment fails:

```bash
# 1. Stop server
docker-compose down

# 2. Restore database backup (if available)
cp /root/backups/pantrypal-$(date +%Y%m%d).db /root/pantrypal-server/db/pantrypal.db

# 3. Revert code changes
git reset --hard PREVIOUS_COMMIT_SHA

# 4. Restart
docker-compose up -d

# 5. Verify
curl http://62.146.177.62/health
```

---

## 📈 Success Metrics

After deployment, monitor:
1. **Premium Lifecycle:**
   - % of households with expiration dates
   - % of expired Premium staying vs churning
   - Revenue retention post-cancellation

2. **Grocery Auto-Add:**
   - % of Premium households using grocery list
   - Checkout-to-zero conversion rate
   - Manual vs auto-add ratio

3. **Downgrade Behavior:**
   - % of free households over 25 items
   - Upgrade rate from "over limit" state
   - Support tickets related to limits

---

## 🎯 Next Steps

1. ✅ Deploy server changes (this guide)
2. ✅ Test Premium lifecycle flows
3. ⏭️ Implement StoreKit 2 integration
4. ⏭️ Add last-item confirmation for free households
5. ⏭️ Premium expiration warnings (7 days before)
6. ⏭️ App Store submission

---

## 💾 Database Backup System

### Overview
Automated daily backups of the production SQLite database with 30-day retention and compression.

### Backup Configuration
- **Schedule:** Daily at 2 AM UTC via cron
- **Location:** `/root/backups/pantrypal-db/`
- **Format:** `pantrypal-YYYYMMDD-HHMMSS.db`
- **Retention:** 30 days (rolling)
- **Compression:** Gzip for backups 7+ days old
- **Logging:** `/root/pantrypal-server/logs/backup.log`

### Setup Instructions

#### 1. Deploy Backup Scripts
```bash
# Copy scripts to production server
scp server/scripts/backup-database.sh root@62.146.177.62:/root/pantrypal-server/scripts/
scp server/scripts/restore-database.sh root@62.146.177.62:/root/pantrypal-server/scripts/

# SSH to server
ssh root@62.146.177.62

# Make scripts executable
chmod +x /root/pantrypal-server/scripts/backup-database.sh
chmod +x /root/pantrypal-server/scripts/restore-database.sh

# Create backup and log directories
mkdir -p /root/backups/pantrypal-db
mkdir -p /root/pantrypal-server/logs

# Test backup script manually
/root/pantrypal-server/scripts/backup-database.sh
```

#### 2. Configure Cron Job
```bash
# SSH to production server
ssh root@62.146.177.62

# Open crontab editor
crontab -e

# Add this line (daily backup at 2 AM UTC)
0 2 * * * /root/pantrypal-server/scripts/backup-database.sh >> /root/pantrypal-server/logs/backup-cron.log 2>&1

# Save and exit (Ctrl+X, Y, Enter in nano)

# Verify cron job is installed
crontab -l | grep backup-database

# Check cron service is running
systemctl status cron
```

#### 3. Verify Backup System
```bash
# Run backup manually
/root/pantrypal-server/scripts/backup-database.sh

# Check backup was created
ls -lh /root/backups/pantrypal-db/

# Check log file
tail -20 /root/pantrypal-server/logs/backup.log

# Verify backup integrity
sqlite3 /root/backups/pantrypal-db/pantrypal-YYYYMMDD-HHMMSS.db "PRAGMA integrity_check;"
# Should output: ok
```

### Restore Operations

#### List Available Backups
```bash
# SSH to server
ssh root@62.146.177.62

# List all backups
/root/pantrypal-server/scripts/restore-database.sh --list

# Or manually
ls -lht /root/backups/pantrypal-db/
```

#### Restore Database from Backup
```bash
# SSH to server
ssh root@62.146.177.62

# Navigate to server directory
cd /root/pantrypal-server

# Restore specific backup (CAUTION: Overwrites production DB!)
./scripts/restore-database.sh pantrypal-20260101-020000.db --confirm

# Or with full path
./scripts/restore-database.sh /root/backups/pantrypal-db/pantrypal-20260101-020000.db --confirm

# Restore from compressed backup
./scripts/restore-database.sh pantrypal-20251225-020000.db.gz --confirm

# Check logs
tail -50 /root/pantrypal-server/logs/backup.log
```

#### Restore Process Details
1. Creates pre-restore backup of current database
2. Stops container to prevent database locks
3. Verifies backup integrity before restore
4. Copies backup to container
5. Restarts container
6. Verifies restored database integrity
7. Logs all operations

### Backup Monitoring

#### Check Backup Status
```bash
# View recent backup logs
tail -100 /root/pantrypal-server/logs/backup.log

# Check last backup
ls -lht /root/backups/pantrypal-db/ | head -5

# Check backup count
find /root/backups/pantrypal-db/ -name "pantrypal-*.db*" | wc -l

# Check total backup size
du -sh /root/backups/pantrypal-db/

# Check cron logs
tail -50 /root/pantrypal-server/logs/backup-cron.log
```

#### Verify Backup Integrity
```bash
# Check latest backup
LATEST_BACKUP=$(ls -t /root/backups/pantrypal-db/pantrypal-*.db 2>/dev/null | head -1)
if [ -f "$LATEST_BACKUP" ]; then
    sqlite3 "$LATEST_BACKUP" "PRAGMA integrity_check;"
else
    echo "No uncompressed backups found, checking compressed..."
    LATEST_COMPRESSED=$(ls -t /root/backups/pantrypal-db/pantrypal-*.db.gz | head -1)
    gunzip -c "$LATEST_COMPRESSED" | sqlite3 - "PRAGMA integrity_check;"
fi
```

### Maintenance

#### Manual Backup
```bash
# Create immediate backup
/root/pantrypal-server/scripts/backup-database.sh
```

#### Cleanup Old Backups
```bash
# Delete backups older than 60 days (manual cleanup)
find /root/backups/pantrypal-db/ -name "pantrypal-*.db.gz" -mtime +60 -delete

# Or adjust retention in backup script:
# Edit RETENTION_DAYS variable in backup-database.sh
```

#### Adjust Backup Schedule
```bash
# Edit crontab
crontab -e

# Common schedules:
# Every 6 hours: 0 */6 * * * /root/pantrypal-server/scripts/backup-database.sh
# Twice daily: 0 2,14 * * * /root/pantrypal-server/scripts/backup-database.sh
# Weekly: 0 2 * * 0 /root/pantrypal-server/scripts/backup-database.sh
```

### Troubleshooting

#### Backup Not Running
```bash
# Check cron service
systemctl status cron

# Check cron job exists
crontab -l | grep backup

# Check script permissions
ls -l /root/pantrypal-server/scripts/backup-database.sh

# Check container name
docker ps --format '{{.Names}}' | grep pantrypal

# Run manually to see errors
/root/pantrypal-server/scripts/backup-database.sh
```

#### Restore Failed
```bash
# Check pre-restore backup was created
ls -lh /root/backups/pantrypal-db/pre-restore-*.db

# Check container is running
docker ps | grep pantrypal

# Verify backup integrity before restore
sqlite3 /root/backups/pantrypal-db/BACKUP_FILE.db "PRAGMA integrity_check;"

# Check logs for detailed error
tail -100 /root/pantrypal-server/logs/backup.log
```

#### Disk Space Issues
```bash
# Check disk usage
df -h /root/backups

# Check backup directory size
du -sh /root/backups/pantrypal-db/

# Delete old compressed backups
find /root/backups/pantrypal-db/ -name "pantrypal-*.db.gz" -mtime +30 -delete

# Compress recent backups immediately
find /root/backups/pantrypal-db/ -name "pantrypal-*.db" -mtime +1 -exec gzip {} \;
```

### Backup Best Practices

1. **Test Restores Regularly:** Verify backups work by doing test restores monthly
2. **Monitor Disk Space:** Ensure backup directory has adequate space
3. **Keep Pre-Restore Backups:** Don't delete pre-restore backups immediately
4. **Off-Site Backups:** Consider copying backups to external storage/cloud
5. **Document Procedures:** Keep this guide updated with any changes
6. **Alert on Failures:** Set up monitoring/alerts for backup failures

### Off-Site Backup (Optional)

```bash
# Sync backups to another location (e.g., AWS S3, rsync to another server)
# Add to cron after main backup:

# Example: Rsync to backup server
# 30 2 * * * rsync -avz /root/backups/pantrypal-db/ backup-server:/backups/pantrypal/

# Example: AWS S3 sync (requires aws-cli)
# 30 2 * * * aws s3 sync /root/backups/pantrypal-db/ s3://my-bucket/pantrypal-backups/
```

---
