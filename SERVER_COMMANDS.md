# Server Quick Reference Commands

## 🚀 Deployment

### SSH & Navigate
```bash
# Connect to production server
ssh root@62.146.177.62

# Navigate to server directory
cd /root/pantrypal-server
```

### Copy Files from Local
```bash
# Single file
scp server/src/routes/inventory.js root@62.146.177.62:/root/pantrypal-server/src/routes/

# Multiple files (same directory)
scp server/src/routes/{auth,inventory,grocery}.js root@62.146.177.62:/root/pantrypal-server/src/routes/

# Entire directory (excluding node_modules and database)
rsync -avz --exclude='node_modules' --exclude='db/pantrypal.db' \
  server/ root@62.146.177.62:/root/pantrypal-server/
```

### Docker Operations
```bash
# Rebuild and restart (after file changes)
docker-compose up -d --build --force-recreate

# Quick restart (no rebuild)
docker-compose restart pantrypal-api

# Stop all containers
docker-compose down

# Start containers
docker-compose up -d

# View running containers
docker-compose ps
```

## 📋 Logs & Monitoring

### View Logs
```bash
# Follow all logs (real-time)
docker-compose logs -f pantrypal-api

# Last 100 lines
docker-compose logs --tail=100 pantrypal-api

# Logs since 1 hour ago
docker-compose logs --since=1h pantrypal-api

# Search for errors
docker-compose logs pantrypal-api | grep -i error

# Search for Premium checks
docker-compose logs pantrypal-api | grep -i premium

# Search for Grocery operations
docker-compose logs pantrypal-api | grep -i grocery

# Search for specific user/household
docker-compose logs pantrypal-api | grep "household-id-here"
```

## 🗄️ Database Operations

### Query Database (Read-Only)
```bash
# List all tables
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db '.tables'"

# Show table schema
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db 'PRAGMA table_info(households);'"

# Count inventory items per household
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db \
  'SELECT h.name, COUNT(i.id) FROM households h 
   LEFT JOIN inventory_items i ON h.id = i.household_id 
   GROUP BY h.id;'"

# List Premium households
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db \
  'SELECT id, name, is_premium, premium_expires_at FROM households WHERE is_premium = 1;'"

# Check user household membership
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db \
  'SELECT u.email, h.name FROM users u 
   LEFT JOIN households h ON u.household_id = h.id;'"

# Count grocery items per household
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db \
  'SELECT h.name, COUNT(g.id) FROM households h 
   LEFT JOIN grocery_items g ON h.id = g.household_id 
   GROUP BY h.id;'"

# Recent checkout history
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db \
  'SELECT p.name, ch.quantity, ch.checkout_date 
   FROM checkout_history ch 
   JOIN products p ON ch.product_id = p.id 
   ORDER BY ch.checkout_date DESC LIMIT 10;'"
```

### Database Modifications (USE WITH CAUTION)
```bash
# Make a backup first
docker-compose exec pantrypal-api sh -c "cp /app/db/pantrypal.db /app/db/pantrypal.backup.db"

# Set household to Premium (no expiration)
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db \
  \"UPDATE households SET is_premium = 1, premium_expires_at = NULL WHERE id = 'household-id';\""

# Set Premium with expiration date
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db \
  \"UPDATE households SET is_premium = 1, premium_expires_at = '2025-12-31 23:59:59' WHERE id = 'household-id';\""

# Remove Premium status
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db \
  \"UPDATE households SET is_premium = 0, premium_expires_at = NULL WHERE id = 'household-id';\""

# Delete test user
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db \
  \"DELETE FROM users WHERE email = 'test@example.com';\""

# Clear all inventory items (DANGER!)
# docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db 'DELETE FROM inventory_items;'"
```

### Run Migration Script
```bash
# Copy migration script to container
docker cp migration.js pantrypal-server-pantrypal-api-1:/app/

# Execute migration
docker-compose exec -T pantrypal-api node /app/migration.js

# Check migration logs
docker-compose logs pantrypal-api | grep -i migration
```

## 🔍 Health Checks

### API Health
```bash
# Health endpoint
curl https://api-pantrypal.subasically.me/health

# With formatted JSON
curl -s https://api-pantrypal.subasically.me/health | jq .

# Test auth endpoint (requires token)
curl -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  https://api-pantrypal.subasically.me/api/auth/me

# Test inventory list (requires token)
curl -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  https://api-pantrypal.subasically.me/api/inventory
```

### Container Health
```bash
# Container status
docker-compose ps

# Container resource usage
docker stats pantrypal-server-pantrypal-api-1

# Container info
docker inspect pantrypal-server-pantrypal-api-1

# Disk usage
docker system df

# Check exposed ports
docker port pantrypal-server-pantrypal-api-1
```

## 🐛 Debugging

### Interactive Shell
```bash
# Enter container shell
docker-compose exec pantrypal-api sh

# Once inside:
# - cd /app              → navigate to app directory
# - ls -la               → list files
# - cat .env             → view environment variables
# - node --version       → check Node version
# - npm list             → list installed packages
# - exit                 → leave container
```

### Environment Variables
```bash
# View all environment variables
docker-compose exec pantrypal-api env

# Check specific variable
docker-compose exec pantrypal-api sh -c 'echo $ENABLE_ADMIN_ROUTES'
docker-compose exec pantrypal-api sh -c 'echo $FREE_LIMIT'
docker-compose exec pantrypal-api sh -c 'echo $JWT_SECRET'
```

### Network Debugging
```bash
# Test internal port (from server)
curl http://localhost:3002/health

# Test external port (from local machine)
curl http://62.146.177.62:3002/health

# Test HTTPS (production domain)
curl https://api-pantrypal.subasically.me/health

# Check DNS resolution
nslookup api-pantrypal.subasically.me

# Check SSL certificate
openssl s_client -connect api-pantrypal.subasically.me:443 -servername api-pantrypal.subasically.me
```

## 🧪 Testing

### Admin Endpoints (DEBUG Only)
```bash
# Set environment variables
export ADMIN_KEY="your-admin-key-here"
export HOUSEHOLD_ID="household-id-here"

# Simulate Premium (no expiration)
curl -X POST \
  -H "x-admin-key: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"isPremium": true}' \
  http://62.146.177.62/api/admin/households/$HOUSEHOLD_ID/premium

# Simulate Premium with expiration
curl -X POST \
  -H "x-admin-key: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"isPremium": true, "expiresAt": "2025-12-31T23:59:59Z"}' \
  http://62.146.177.62/api/admin/households/$HOUSEHOLD_ID/premium

# Remove Premium
curl -X POST \
  -H "x-admin-key: $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"isPremium": false}' \
  http://62.146.177.62/api/admin/households/$HOUSEHOLD_ID/premium
```

### Run Tests Locally
```bash
# Navigate to server directory (on local machine)
cd server

# Run all tests
npm test

# Run with coverage
npm run test:coverage

# Run specific test file
npm test -- tests/auth.test.js

# Run in watch mode
npm run test:watch
```

## 🔄 Rollback

### Emergency Rollback
```bash
# Stop current version
docker-compose down

# Restore database backup (if needed)
docker-compose exec pantrypal-api sh -c \
  "cp /app/db/pantrypal.backup.db /app/db/pantrypal.db"

# Start previous version
docker-compose up -d

# Verify rollback
curl https://api-pantrypal.subasically.me/health
```

## 📊 Common Queries

### Household Stats
```bash
# Household summary (items, members, premium)
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db <<EOF
SELECT 
  h.name,
  h.is_premium,
  h.premium_expires_at,
  (SELECT COUNT(*) FROM users WHERE household_id = h.id) as members,
  (SELECT COUNT(*) FROM inventory_items WHERE household_id = h.id) as inventory_items,
  (SELECT COUNT(*) FROM grocery_items WHERE household_id = h.id) as grocery_items
FROM households h;
EOF"
```

### Premium Expiration Check
```bash
# Households expiring in next 7 days
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db \
  \"SELECT id, name, premium_expires_at 
   FROM households 
   WHERE is_premium = 1 
   AND premium_expires_at IS NOT NULL 
   AND premium_expires_at < datetime('now', '+7 days');\""
```

### Activity Monitoring
```bash
# Recent API activity (from logs)
docker-compose logs --tail=100 pantrypal-api | grep "POST\|GET\|PUT\|DELETE"

# Error rate
docker-compose logs --since=1h pantrypal-api | grep -i error | wc -l

# Request count by endpoint
docker-compose logs --since=1h pantrypal-api | grep -oP 'POST|GET|PUT|DELETE /api/\w+' | sort | uniq -c
```

## 🎯 Common Workflows

### Deploy Code Changes
```bash
# 1. Copy updated files
rsync -avz --exclude='node_modules' --exclude='db/pantrypal.db' \
  server/ root@62.146.177.62:/root/pantrypal-server/

# 2. SSH to server
ssh root@62.146.177.62

# 3. Navigate and rebuild
cd /root/pantrypal-server && docker-compose up -d --build --force-recreate

# 4. Watch logs for errors
docker-compose logs -f pantrypal-api

# 5. Test health (Ctrl+C to exit logs first)
curl https://api-pantrypal.subasically.me/health
```

### Debug Sync Issues
```bash
# 1. Check recent logs for household
docker-compose logs --tail=200 pantrypal-api | grep "HOUSEHOLD_ID"

# 2. Verify inventory items
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db \
  'SELECT * FROM inventory_items WHERE household_id = \"HOUSEHOLD_ID\";'"

# 3. Check if items have locations
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db \
  'SELECT COUNT(*) FROM inventory_items WHERE location_id IS NULL;'"

# 4. Verify household members can see items
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db \
  'SELECT u.email, u.household_id FROM users u WHERE u.household_id = \"HOUSEHOLD_ID\";'"
```

### Test Premium Flow
```bash
# 1. Set household to free
curl -X POST -H "x-admin-key: $ADMIN_KEY" -H "Content-Type: application/json" \
  -d '{"isPremium": false}' \
  http://62.146.177.62/api/admin/households/$HOUSEHOLD_ID/premium

# 2. Check current item count
docker-compose exec pantrypal-api sh -c "sqlite3 /app/db/pantrypal.db \
  'SELECT COUNT(*) FROM inventory_items WHERE household_id = \"$HOUSEHOLD_ID\";'"

# 3. Try to add item via app (should fail if over 25)

# 4. Set to Premium
curl -X POST -H "x-admin-key: $ADMIN_KEY" -H "Content-Type: application/json" \
  -d '{"isPremium": true}' \
  http://62.146.177.62/api/admin/households/$HOUSEHOLD_ID/premium

# 5. Try to add item via app (should succeed)
```

## 📝 Notes

- **Always backup database before modifications:** `cp pantrypal.db pantrypal.backup.db`
- **Container name may vary:** Replace `pantrypal-server-pantrypal-api-1` with actual container name from `docker-compose ps`
- **Admin endpoints require:** `ENABLE_ADMIN_ROUTES=true` in `.env` and valid `x-admin-key` header
- **Database timezone:** SQLite stores dates in UTC, display may differ based on client timezone
- **Rate limiting:** Not currently implemented, but plan for it before public launch
- **Logs retention:** Docker logs are rotated automatically, but old logs may be lost

## 🔗 Related Documentation

- [DEPLOYMENT.md](./DEPLOYMENT.md) - Full deployment guide with migration steps
- [README.md](./README.md) - Project overview and API endpoints
- [TODO.md](./TODO.md) - Current sprint and upcoming features
- [PREMIUM_LIFECYCLE_SUMMARY.md](./PREMIUM_LIFECYCLE_SUMMARY.md) - Premium feature details
