# Quick Start: PantryPal Database Backups

## 🚀 Production Deployment (5 minutes)

```bash
# 1. Copy scripts
scp server/scripts/*.sh root@62.146.177.62:/root/pantrypal-server/scripts/

# 2. Setup on server
ssh root@62.146.177.62
chmod +x /root/pantrypal-server/scripts/*.sh
mkdir -p /root/backups/pantrypal-db /root/pantrypal-server/logs

# 3. Test backup
/root/pantrypal-server/scripts/backup-database.sh

# 4. Install cron (daily at 2 AM UTC)
(crontab -l 2>/dev/null; echo "0 2 * * * /root/pantrypal-server/scripts/backup-database.sh >> /root/pantrypal-server/logs/backup-cron.log 2>&1") | crontab -

# 5. Validate
/root/pantrypal-server/scripts/validate-backup-system.sh
```

## 📋 Daily Commands

```bash
# Check backup status
ssh root@62.146.177.62 "ls -lht /root/backups/pantrypal-db/ | head -5"

# View logs
ssh root@62.146.177.62 "tail -20 /root/pantrypal-server/logs/backup.log"

# Manual backup
ssh root@62.146.177.62 "/root/pantrypal-server/scripts/backup-database.sh"
```

## 🔄 Restore Database

```bash
# SSH to server
ssh root@62.146.177.62

# List backups
/root/pantrypal-server/scripts/restore-database.sh --list

# Restore (requires --confirm)
/root/pantrypal-server/scripts/restore-database.sh pantrypal-20260101-020000.db --confirm
```

## 📚 Full Documentation

- **Setup Guide:** `server/scripts/DEPLOYMENT_CHECKLIST.md`
- **Full Docs:** `server/scripts/README.md`
- **Quick Reference:** `server/scripts/QUICK_REFERENCE.md`
- **Deployment:** `DEPLOYMENT.md` (search for "Database Backup System")

## ✅ Success Check

After deployment, verify:
1. ✓ Backup created: `ls /root/backups/pantrypal-db/`
2. ✓ Log entry: `tail /root/pantrypal-server/logs/backup.log`
3. ✓ Cron installed: `crontab -l | grep backup`
4. ✓ Validation passes: `/root/pantrypal-server/scripts/validate-backup-system.sh`

---

**Need Help?** See `server/scripts/README.md` for detailed instructions.
