# PantryPal Backup Quick Reference

## 🚨 Emergency Restore

```bash
# SSH to production
ssh root@62.146.177.62

# List backups
/root/pantrypal-server/scripts/restore-database.sh --list

# Restore (creates pre-restore backup automatically)
cd /root/pantrypal-server
./scripts/restore-database.sh pantrypal-YYYYMMDD-HHMMSS.db --confirm
```

---

## ✅ Daily Operations

### Check Backup Status
```bash
ssh root@62.146.177.62
tail -20 /root/pantrypal-server/logs/backup.log
ls -lht /root/backups/pantrypal-db/ | head -5
```

### Manual Backup
```bash
ssh root@62.146.177.62
/root/pantrypal-server/scripts/backup-database.sh
```

### Verify Latest Backup
```bash
ssh root@62.146.177.62
LATEST=$(ls -t /root/backups/pantrypal-db/pantrypal-*.db 2>/dev/null | head -1)
sqlite3 "$LATEST" "PRAGMA integrity_check;"
```

---

## 📊 Monitoring

### Backup Logs
```bash
# Recent backup activity
tail -50 /root/pantrypal-server/logs/backup.log

# Cron execution logs
tail -50 /root/pantrypal-server/logs/backup-cron.log

# Search for errors
grep -i error /root/pantrypal-server/logs/backup.log
```

### Disk Space
```bash
# Backup directory size
du -sh /root/backups/pantrypal-db/

# Disk usage
df -h /root/backups

# Number of backups
find /root/backups/pantrypal-db/ -name "pantrypal-*.db*" | wc -l
```

---

## ⚙️ Cron Job

### View Cron Schedule
```bash
crontab -l | grep backup
```

### Edit Cron Schedule
```bash
crontab -e
# Current: 0 2 * * * (2 AM UTC daily)
```

### Check Cron Status
```bash
systemctl status cron
```

---

## 🔧 Troubleshooting

### Backup Failed
```bash
# Run manually to see error
/root/pantrypal-server/scripts/backup-database.sh

# Check container running
docker ps | grep pantrypal

# Check disk space
df -h /root/backups
```

### Restore Failed
```bash
# Check pre-restore backup created
ls -lh /root/backups/pantrypal-db/pre-restore-*.db

# Verify backup integrity
sqlite3 BACKUP_FILE.db "PRAGMA integrity_check;"

# Check logs
tail -100 /root/pantrypal-server/logs/backup.log
```

### Disk Space Full
```bash
# Delete old backups (60+ days)
find /root/backups/pantrypal-db/ -name "pantrypal-*.db.gz" -mtime +60 -delete

# Force compress recent backups
find /root/backups/pantrypal-db/ -name "pantrypal-*.db" -mtime +1 -exec gzip {} \;
```

---

## 📝 Key Paths

| Item | Path |
|------|------|
| Backup Directory | `/root/backups/pantrypal-db/` |
| Backup Log | `/root/pantrypal-server/logs/backup.log` |
| Cron Log | `/root/pantrypal-server/logs/backup-cron.log` |
| Backup Script | `/root/pantrypal-server/scripts/backup-database.sh` |
| Restore Script | `/root/pantrypal-server/scripts/restore-database.sh` |
| Production DB | `pantrypal-data` volume → `/app/db/pantrypal.db` |

---

## 📞 Support

For detailed instructions, see:
- `server/scripts/README.md`
- `DEPLOYMENT.md` (Database Backup System section)
