# PantryPal Copilot Instructions

You are assisting with **PantryPal**, a pantry inventory app consisting of a **Node.js/Express server** and an **iOS SwiftUI app**.

## 🧠 Project Philosophy (The "Ruthless MVP")
We are currently in the **Revenue Validation** phase.
- **Goal:** Validate that people will pay for household sharing and unlimited items.
- **Rule:** Do NOT suggest or implement "nice-to-have" features (recipes, nutrition, complex analytics) until we have revenue.
- **Focus:** Reliability, Sync, and the Paywall.

## 🛠 Tech Stack

### Server
- **Runtime:** Node.js 20 (Alpine Docker)
- **Database:** SQLite (via `better-sqlite3`)
- **Auth:** JWT + Apple Sign In + Email/Password
- **Architecture:** REST API, Controller/Service pattern
- **Deployment:** Docker Compose on VPS (62.146.177.62)
- **Production URL:** https://api-pantrypal.subasically.me
- **Server Path:** `/root/pantrypal-server`

### iOS App
- **Language:** Swift 6 (Strict Concurrency)
- **UI:** SwiftUI (iOS 18+)
- **Architecture:** MVVM + Repository/Service pattern
- **Local Data:** SwiftData (Caching) + UserDefaults (Auth)
- **Key Libs:** AVFoundation (Scanning), AuthenticationServices

## 📏 Coding Standards & Patterns

### General
- **Minimal Changes:** When fixing bugs, change the minimum amount of code necessary. Don't rewrite working logic.
- **Error Handling:** Always handle errors gracefully. On iOS, show user-facing error messages. On Server, log to console and return JSON error.

### Server
- **Database:** Use `better-sqlite3` synchronously. It's fast enough.
- **Schema:** `users.household_id` is **OPTIONAL** (NULL for new users).
- **Premium Logic:**
  - Free Tier: Hard limit of **25 inventory items** + **25 grocery items** (FREE_LIMIT = 25).
  - Premium: Unlimited items + Household Sharing (Write access) + Auto-add to grocery.
  - Check limits *before* INSERT/UPDATE using `checkInventoryLimit()` and `checkGroceryLimit()`.

### iOS
- **Concurrency:** Use `async/await` and `@MainActor` for UI updates.
- **Onboarding Flow:**
  1. Login/Register (Apple/Email)
  2. Check `user.householdId`
  3. If NULL -> Show `HouseholdSetupView` (Create / Join / Skip)
  4. If EXISTS -> Go to `InventoryListView`
- **Paywalls:**
  - Trigger immediately on client-side when hitting limits (don't wait for server 403 if possible).
  - Listen for `Notification.Name("showPaywall")`.
- **SwiftData Import:** 
  - **ALWAYS** add `import SwiftData` when using `FetchDescriptor`, `@Query`, or `modelContext.fetch()`.
  - Common error: "Cannot find type 'FetchDescriptor' in scope" = missing SwiftData import.
  - Files that need it: ViewModels with `@Query`, Services with `modelContext`, Models with `@Model`.
- **API Errors:** 
  - `APIError` enum is defined at **FILE LEVEL** (NOT inside APIService class).
  - **Correct:** `import Foundation` then use `APIError.unauthorized`
  - **Wrong:** `APIService.APIError.unauthorized` (will not compile)
  - Definition location: `ios/PantryPal/Services/APIService.swift` (lines 3-21, before class definition)

## ⚠️ Known "Gotchas"
1. **New Users:** A new user created via Apple Sign In does **NOT** have a household immediately. They must create or join one.
2. **Database Reset:** If the schema changes, the `pantrypal-data` Docker volume must be updated or the tables dropped.
3. **Loading States:** Ensure loading spinners persist for at least **1.5s** to prevent UI flashing.
4. **Auth Middleware:** Server uses `module.exports = authenticateToken` (default export), NOT named export. Import as `const authenticateToken = require('../middleware/auth')`.
5. **Server Deployment:** Server directory on VPS is `/root/pantrypal-server` (NOT a git repo). Use `scp` to copy files, then rebuild container.
6. **iOS Properties:** AuthViewModel uses `currentUser` and `currentHousehold` (NOT `user` or `householdInfo`).
7. **SwiftData Models:** Grocery items use `SDGroceryItem`. Inventory uses `SDInventoryItem`. Both are cached locally for offline support.
8. **SwiftData Import Required:** Files using `@Query`, `FetchDescriptor`, or `modelContext` MUST import SwiftData. Missing this import causes "Cannot find type" errors.
9. **APIError is File-Level:** `APIError` enum is NOT nested in `APIService` class. Use `APIError.unauthorized`, not `APIService.APIError.unauthorized`.

## 📝 Current Task Context
- ✅ New User Onboarding Flow complete
- ✅ Freemium Model (25 item limits) complete
- ✅ Grocery List Feature (with Premium auto-add + SwiftData cache) complete
- The server database schema was recently updated to allow NULL `household_id`.

## 🚀 Server Deployment

### Quick Deploy Process:
```bash
# 1. SSH to production server
ssh root@62.146.177.62

# 2. Navigate to project
cd /root/pantrypal-server

# 3. Copy updated files (or use scp from local)
# scp local-file root@62.146.177.62:/root/pantrypal-server/path/

# 4. Rebuild and restart
docker-compose up -d --build --force-recreate

# 5. Check logs
docker-compose logs -f pantrypal-api

# 6. Verify health
curl https://api-pantrypal.subasically.me/health
```

### Database Migrations:
```bash
# Run migration script inside container
docker cp migration.js pantrypal-server-pantrypal-api-1:/app/
docker-compose exec -T pantrypal-api node /app/migration.js
```

## 📦 Version Bumping

When the user says **"bump version and build"**:

1. **Read current version/build** from `ios/PantryPal.xcodeproj/project.pbxproj`:
   ```bash
   grep -A1 "MARKETING_VERSION = " ios/PantryPal.xcodeproj/project.pbxproj | head -2
   grep -A1 "CURRENT_PROJECT_VERSION = " ios/PantryPal.xcodeproj/project.pbxproj | head -2
   ```

2. **Increment build number** (keep version same unless major release):
   - Example: `1.0.0 (5)` → `1.0.0 (6)`
   - Use `sed` to update both MARKETING_VERSION and CURRENT_PROJECT_VERSION

3. **Commit and tag**:
   ```bash
   git add ios/PantryPal.xcodeproj/project.pbxproj
   git commit -m "chore: Bump version to X.Y.Z (BUILD)"
   git tag -a "vX.Y.Z-BUILD" -m "Release vX.Y.Z (BUILD)"
   git push origin main --tags
   ```

4. **Format**: Version follows `MAJOR.MINOR.PATCH (BUILD)` where BUILD increments for each TestFlight release.
