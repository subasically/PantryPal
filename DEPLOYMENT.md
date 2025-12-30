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
