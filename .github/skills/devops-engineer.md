# Deploy & Monitor Production Server

Deploy, monitor, and troubleshoot PantryPal API on production VPS.

## When to Use
- Deploying server changes
- Checking production logs
- Database migrations
- Troubleshooting production issues
- Server health monitoring

## Production Environment
- **Host:** 62.146.177.62 (root)
- **Path:** `/root/pantrypal-server`
- **URL:** https://api-pantrypal.subasically.me
- **Container:** `pantrypal-api`
- **Port:** 3002
- **Database:** SQLite in Docker volume `pantrypal-server_pantrypal-data` at `/app/db/pantrypal.db`
- **Testing:** Follow `TESTING.md` for structured test scenarios

## Quick Deploy

### Standard Deployment
```bash
# 1. Copy files (exclude node_modules and db)
rsync -avz --exclude='node_modules' --exclude='db/pantrypal.db' \
  server/ root@62.146.177.62:/root/pantrypal-server/

# 2. SSH and rebuild
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose up -d --build --force-recreate"

# 3. Check logs
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose logs -f pantrypal-api"

# 4. Verify health
curl https://api-pantrypal.subasically.me/health
```

### One-Liner Deploy
```bash
rsync -avz --exclude='node_modules' --exclude='db/pantrypal.db' server/ root@62.146.177.62:/root/pantrypal-server/ && \
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose up -d --build" && \
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose logs --tail=50 -f pantrypal-api"
```

## Monitoring

### View Logs
```bash
# Real-time logs
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose logs -f pantrypal-api"

# Last 100 lines
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose logs --tail=100 pantrypal-api"

# Search for errors
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose logs pantrypal-api | grep -i error"

# Premium-related logs
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose logs pantrypal-api | grep -i premium"
```

### Database Queries
```bash
# List all tables
ssh root@62.146.177.62 "docker-compose -f /root/pantrypal-server/docker-compose.yml exec pantrypal-api sh -c 'sqlite3 /app/db/pantrypal.db \".tables\"'"

# Check Premium households
ssh root@62.146.177.62 "docker-compose -f /root/pantrypal-server/docker-compose.yml exec pantrypal-api sh -c 'sqlite3 /app/db/pantrypal.db \"SELECT id, name, is_premium FROM households WHERE is_premium = 1;\"'"

# Count inventory items per household
ssh root@62.146.177.62 "docker-compose -f /root/pantrypal-server/docker-compose.yml exec pantrypal-api sh -c 'sqlite3 /app/db/pantrypal.db \"SELECT h.name, COUNT(i.id) FROM households h LEFT JOIN inventory i ON h.id = i.household_id GROUP BY h.id;\"'"
```

### Container Health
```bash
# Container status
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose ps"

# Resource usage
ssh root@62.146.177.62 "docker stats pantrypal-api --no-stream"

# Restart container
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose restart pantrypal-api"
```

## Database Migrations

### Check Migration Success
```bash
# View migration logs
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose logs pantrypal-api | grep -i migration"

# Verify table schema
ssh root@62.146.177.62 "docker-compose -f /root/pantrypal-server/docker-compose.yml exec pantrypal-api sh -c 'sqlite3 /app/db/pantrypal.db \"PRAGMA table_info(households);\"'"
```

### Manual Migration (if needed)
```bash
# Copy migration script
scp migration.sql root@62.146.177.62:/tmp/

# Execute migration
ssh root@62.146.177.62 "docker cp /tmp/migration.sql pantrypal-api:/tmp/ && \
docker-compose -f /root/pantrypal-server/docker-compose.yml exec pantrypal-api sh -c 'sqlite3 /app/db/pantrypal.db < /tmp/migration.sql'"

# Restart container
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose restart pantrypal-api"
```

### Backup Database
```bash
# Create backup
ssh root@62.146.177.62 "docker-compose -f /root/pantrypal-server/docker-compose.yml exec pantrypal-api sh -c 'sqlite3 /app/db/pantrypal.db \".backup /app/db/pantrypal.db.backup\"'"

# Copy to host
ssh root@62.146.177.62 "docker cp pantrypal-api:/app/db/pantrypal.db.backup /root/backups/pantrypal.db.$(date +%Y%m%d_%H%M%S)"
```

## Troubleshooting

### Container Won't Start
```bash
# Check logs for error
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose logs pantrypal-api"

# Rebuild from scratch
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose down && docker-compose up -d --build"
```

### 502 Bad Gateway
```bash
# Check if container is running
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose ps"

# Restart container
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose restart pantrypal-api"

# Check health
curl http://62.146.177.62:3002/health
```

### Database Locked
```bash
# Restart container (releases lock)
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose restart pantrypal-api"
```

## Rollback Procedure

### Code Rollback
```bash
# 1. Checkout previous commit locally
git log --oneline
git checkout <commit-hash>

# 2. Redeploy old code
rsync -avz --exclude='node_modules' --exclude='db/pantrypal.db' \
  server/ root@62.146.177.62:/root/pantrypal-server/

# 3. Rebuild
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose restart pantrypal-api"

# 4. Verify
curl https://api-pantrypal.subasically.me/health
```

### Database Rollback
```bash
# Restore from backup
ssh root@62.146.177.62 "docker cp /root/backups/pantrypal.db.20250101_120000 pantrypal-api:/app/db/pantrypal.db && \
cd /root/pantrypal-server && docker-compose restart pantrypal-api"
```

## Pre-Deployment Checklist
- [ ] Tests passing locally (`npm test` in server/)
- [ ] Database migration script ready (if schema changes)
- [ ] Backup current database (if critical changes)
- [ ] Deploy during low-traffic window
- [ ] Monitor logs for 5 minutes after deployment
- [ ] Verify health endpoint responds
- [ ] Test key endpoints with curl

## Best Practices
- ✅ Always verify health after deployment
- ✅ Monitor logs for errors immediately after deploy
- ✅ Keep last 7 days of database backups
- ✅ Deploy during off-peak hours (late night)
- ✅ Test in local Docker before production
- ⚠️ No Git on production - use SCP/rsync
