# Deploy Server to Production

Deploy PantryPal Node.js server to VPS.

## When to Use
- User says "deploy server", "update production", "push to server"
- After making server-side changes
- After fixing bugs in API

## Production Details
- **Server:** 62.146.177.62 (root access)
- **Path:** `/root/pantrypal-server`
- **URL:** https://api-pantrypal.subasically.me
- **Container:** pantrypal-server-pantrypal-api-1

## Deployment Steps

1. **Copy updated files via SCP:**
   ```bash
   scp server/src/path/to/file.js root@62.146.177.62:/root/pantrypal-server/src/path/to/
   ```

2. **Or copy entire server directory:**
   ```bash
   scp -r server/* root@62.146.177.62:/root/pantrypal-server/
   ```

3. **Rebuild and restart container:**
   ```bash
   ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose down && docker-compose up -d --build --force-recreate"
   ```

4. **Check logs:**
   ```bash
   ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose logs -f --tail=50 pantrypal-api"
   ```

5. **Verify health:**
   ```bash
   curl https://api-pantrypal.subasically.me/health
   ```

## Database Migrations

If schema changes are needed:
```bash
# Create migration file locally
cat > migration.js << 'EOF'
const Database = require('better-sqlite3');
const db = new Database('/app/db/pantrypal.db');  // Correct path!

// Your migration SQL here
db.exec(`
  ALTER TABLE users ADD COLUMN new_field TEXT;
`);

console.log('Migration complete!');
db.close();
EOF

# Copy and run migration
scp migration.js root@62.146.177.62:/root/pantrypal-server/
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker cp migration.js pantrypal-server-pantrypal-api-1:/app/ && docker-compose exec -T pantrypal-api node /app/migration.js"
```

## Database Reset (Development)

For clean testing iterations:
```bash
./server/scripts/reset-database.sh
```

This removes the Docker volume and recreates a fresh database.

## IMPORTANT NOTES
- ⚠️ **NO GIT REPO** on production server - must use SCP
- ⚠️ Database is in Docker volume `pantrypal-server_pantrypal-data` at `/app/db/pantrypal.db`
- ⚠️ Always test locally first (use `TESTING.md` test plan)
- ⚠️ Check logs after deployment
- ⚠️ Backup database before schema changes
- ⚠️ **MVP Mode:** Skip migrations, update `db/schema.sql` directly and reset DB

## Quick Health Check
```bash
curl -s https://api-pantrypal.subasically.me/health | jq
```

Expected response:
```json
{
  "status": "ok",
  "timestamp": "2025-12-31T...",
  "database": "connected",
  "activeUsers": 123
}
```
