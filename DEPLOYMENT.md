# Deployment Guide - Grocery List Feature

## 📦 What Changed

### Server Changes:
1. **Database**: New `grocery_items` table (already created in local DB)
2. **API Routes**: New `/api/grocery` endpoints (GET, POST, DELETE)
3. **Auto-Add Logic**: Premium households auto-add items when inventory reaches 0

### Files Modified/Created:
- `server/src/routes/grocery.js` (NEW)
- `server/src/routes/inventory.js` (Modified - added auto-manage grocery logic)
- `server/src/app.js` (Modified - registered grocery routes)

### iOS Changes:
- `ios/PantryPal/Models/Models.swift` (Added GroceryItem model)
- `ios/PantryPal/Services/APIService.swift` (Added grocery endpoints)
- `ios/PantryPal/ViewModels/GroceryViewModel.swift` (NEW)
- `ios/PantryPal/Views/GroceryListView.swift` (NEW)
- `ios/PantryPal/PantryPalApp.swift` (Added Grocery tab)

---

## 🚀 Deployment Steps

### Option 1: Git-Based Deployment (Recommended)

If your VPS pulls from GitHub:

```bash
# 1. Commit and push changes
git add server/src/routes/grocery.js server/src/routes/inventory.js server/src/app.js
git commit -m "Add grocery list feature with Premium auto-add"
git push origin main

# 2. SSH to your VPS
ssh root@api-pantrypal.subasically.me
# (or your VPS IP/hostname)

# 3. Pull latest changes
cd /path/to/PantryPal
git pull origin main

# 4. Restart the server
cd server
docker-compose restart api

# 5. Run database migration
docker-compose exec api node -e "
const db = require('./src/models/database');
db.exec(\`
  CREATE TABLE IF NOT EXISTS grocery_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    household_id INTEGER NOT NULL,
    name TEXT NOT NULL,
    normalized_name TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (household_id) REFERENCES households(id) ON DELETE CASCADE,
    UNIQUE(household_id, normalized_name)
  );
\`);
console.log('✓ grocery_items table created');
"

# 6. Verify
curl https://api-pantrypal.subasically.me/health
```

### Option 2: Manual File Upload

If you don't have Git on the VPS:

```bash
# 1. Copy files to VPS
scp server/src/routes/grocery.js root@YOUR_VPS_IP:/path/to/PantryPal/server/src/routes/
scp server/src/routes/inventory.js root@YOUR_VPS_IP:/path/to/PantryPal/server/src/routes/
scp server/src/app.js root@YOUR_VPS_IP:/path/to/PantryPal/server/src/

# 2. SSH and restart
ssh root@YOUR_VPS_IP
cd /path/to/PantryPal/server
docker-compose restart api

# 3. Run migration (see above)
```

---

## 🧪 Testing After Deployment

Test the new grocery endpoints:

```bash
# Set your auth token
TOKEN="your-jwt-token"

# Test GET grocery items
curl -H "Authorization: Bearer $TOKEN" \
  https://api-pantrypal.subasically.me/api/grocery

# Test POST add item
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Milk"}' \
  https://api-pantrypal.subasically.me/api/grocery

# Test auto-add (checkout an item to 0)
curl -X PATCH \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"adjustment":-1}' \
  https://api-pantrypal.subasically.me/api/inventory/ITEM_ID/quantity
```

---

## 📱 iOS App

The iOS changes are already built and working locally. Users will see:
- **Grocery tab** in bottom navigation
- **Manual add/remove** for all users
- **Auto-add badge** for Premium users
- Items automatically added when checking out to 0 (Premium only)

No additional deployment needed for iOS - changes are in the app binary.

---

## 🔧 Troubleshooting

### Database Migration Failed
```bash
# Connect directly to database
docker-compose exec api sh
sqlite3 /app/pantrypal.db
.schema grocery_items
```

### Routes Not Working
```bash
# Check logs
docker-compose logs -f api

# Verify routes registered
curl https://api-pantrypal.subasically.me/api | jq
# Should show grocery endpoint
```

### Auto-Add Not Working
- Verify household `is_premium = 1` in database
- Check server logs when adjusting quantity to 0
- Ensure inventory item has a product with a name

---

## 📊 Monitoring

After deployment, monitor:
1. Server logs for grocery errors
2. Database size (grocery_items table)
3. User adoption (how many add grocery items)
4. Premium conversion (users hitting grocery feature)

---

## 🎯 Next Steps

1. Deploy server changes (today)
2. Test with your own account
3. Monitor for errors
4. Prepare App Store update with grocery feature
