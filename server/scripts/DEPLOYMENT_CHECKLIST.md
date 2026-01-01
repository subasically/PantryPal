# Database Backup System Deployment Checklist

Use this checklist when deploying the backup system to production.

## 📋 Pre-Deployment

- [ ] Review backup requirements (retention, schedule, location)
- [ ] Verify production server access: `ssh root@62.146.177.62`
- [ ] Check production container name: `docker ps`
- [ ] Verify sufficient disk space: `df -h /root`
- [ ] Review DEPLOYMENT.md backup section

## 🚀 Deployment Steps

### 1. Copy Scripts to Production
```bash
# From local machine
cd /Users/subasically/Desktop/github/PantryPal
scp server/scripts/backup-database.sh root@62.146.177.62:/root/pantrypal-server/scripts/
scp server/scripts/restore-database.sh root@62.146.177.62:/root/pantrypal-server/scripts/
scp server/scripts/validate-backup-system.sh root@62.146.177.62:/root/pantrypal-server/scripts/
```
- [ ] Scripts copied successfully

### 2. SSH to Production
```bash
ssh root@62.146.177.62
cd /root/pantrypal-server
```
- [ ] Connected to production server

### 3. Set Permissions
```bash
chmod +x scripts/backup-database.sh
chmod +x scripts/restore-database.sh
chmod +x scripts/validate-backup-system.sh
```
- [ ] Scripts are executable

### 4. Create Directories
```bash
mkdir -p /root/backups/pantrypal-db
mkdir -p /root/pantrypal-server/logs
```
- [ ] Backup directory created
- [ ] Log directory created

### 5. Test Backup Script
```bash
/root/pantrypal-server/scripts/backup-database.sh
```
- [ ] Script runs without errors
- [ ] Backup file created in `/root/backups/pantrypal-db/`
- [ ] Log entry created in `logs/backup.log`
- [ ] Backup integrity verified (log shows "OK")

### 6. Verify Backup
```bash
ls -lh /root/backups/pantrypal-db/
tail -20 /root/pantrypal-server/logs/backup.log
```
- [ ] Backup file exists
- [ ] File size is reasonable (> 0 bytes)
- [ ] Log shows successful completion

### 7. Test Backup Integrity
```bash
LATEST=$(ls -t /root/backups/pantrypal-db/pantrypal-*.db | head -1)
sqlite3 "$LATEST" "PRAGMA integrity_check;"
```
- [ ] Output is "ok"

### 8. Install Cron Job
```bash
crontab -e
```

Add this line:
```
0 2 * * * /root/pantrypal-server/scripts/backup-database.sh >> /root/pantrypal-server/logs/backup-cron.log 2>&1
```

Save and exit.

- [ ] Cron job added

### 9. Verify Cron Configuration
```bash
crontab -l | grep backup
systemctl status cron
```
- [ ] Cron job listed
- [ ] Cron service is running

### 10. Run Validation Script
```bash
/root/pantrypal-server/scripts/validate-backup-system.sh
```
- [ ] All checks passed
- [ ] No errors reported

## ✅ Post-Deployment Verification

### Immediate (Day 1)
```bash
# Check backup was created
ls -lh /root/backups/pantrypal-db/

# Check logs
tail -20 /root/pantrypal-server/logs/backup.log
tail -20 /root/pantrypal-server/logs/backup-cron.log
```
- [ ] Initial backup exists
- [ ] Logs show success

### Next Day (Day 2)
```bash
# Verify cron job ran at 2 AM UTC
tail -50 /root/pantrypal-server/logs/backup-cron.log

# Check for second backup
ls -lht /root/backups/pantrypal-db/ | head -5
```
- [ ] Cron job executed successfully
- [ ] Second backup created
- [ ] Both backups have valid timestamps

### Week Later (Day 7)
```bash
# Check backup count
find /root/backups/pantrypal-db/ -name "pantrypal-*.db*" | wc -l

# Check disk usage
du -sh /root/backups/pantrypal-db/
```
- [ ] Multiple backups exist (~7 files)
- [ ] Disk usage is reasonable

### Two Weeks Later (Day 14)
```bash
# Check compression is working
ls -lh /root/backups/pantrypal-db/ | grep ".gz"

# Verify old backups compressed
find /root/backups/pantrypal-db/ -name "pantrypal-*.db" -mtime +7
```
- [ ] Old backups (7+ days) are compressed
- [ ] Recent backups remain uncompressed

### Month Later (Day 30)
```bash
# Check retention is working
find /root/backups/pantrypal-db/ -name "pantrypal-*.db*" | wc -l

# Should be ~30 backups (not more)
```
- [ ] Backup count is ~30 (retention working)
- [ ] Oldest backup is ~30 days old

## 🧪 Test Restore (Month 2)

**WARNING: Only test restore in non-peak hours**

```bash
# List backups
/root/pantrypal-server/scripts/restore-database.sh --list

# Test restore with a recent backup
/root/pantrypal-server/scripts/restore-database.sh pantrypal-YYYYMMDD-HHMMSS.db --confirm

# Verify application works after restore
curl https://api-pantrypal.subasically.me/health
```
- [ ] Restore completed successfully
- [ ] Pre-restore backup created
- [ ] Application is functional after restore
- [ ] No data loss detected

## 📊 Ongoing Monitoring

### Weekly Checks
- [ ] Verify backups are being created daily
- [ ] Check log files for errors
- [ ] Monitor disk space usage
- [ ] Verify compression is working

### Monthly Tasks
- [ ] Test restore procedure
- [ ] Review backup retention
- [ ] Check for system updates
- [ ] Update documentation if needed

## 🚨 Troubleshooting

If any step fails, see:
- `server/scripts/README.md` - Detailed documentation
- `server/scripts/QUICK_REFERENCE.md` - Quick commands
- `DEPLOYMENT.md` - Full deployment guide

## 📝 Notes

**Date Deployed:** _______________

**Deployed By:** _______________

**Initial Backup Size:** _______________

**Any Issues:** 
_______________________________________________
_______________________________________________
_______________________________________________

**Configuration Changes:**
_______________________________________________
_______________________________________________
_______________________________________________

## ✨ Success Criteria

- ✅ Backup script runs daily at 2 AM UTC
- ✅ Backups are created successfully
- ✅ Backups are verified for integrity
- ✅ Old backups are compressed (7+ days)
- ✅ Backups are deleted after 30 days
- ✅ Restore procedure works correctly
- ✅ Logs are maintained properly
- ✅ Disk space is managed effectively

---

**Status:** [ ] Deployed Successfully  [ ] Needs Attention

**Sign-off:** _______________  **Date:** _______________
