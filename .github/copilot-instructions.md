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
- **Bug Pattern Detection:** When you find a bug (especially parameter order, missing validation, or logic errors), **ALWAYS search the entire codebase** for the same pattern. Fix all occurrences at once to prevent recurring issues.
  - Example: If `logSync(household, type, action, id)` is wrong, grep for all `logSync(` calls and verify parameter order.
  - Use `grep_search` or `semantic_search` to find similar code patterns.
  - Check both the file where the bug was found AND related files (e.g., all service files, all route handlers).

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
  2. **Households are auto-created** - `AuthViewModel` automatically calls `completeHouseholdSetup()` after login if `currentHousehold == nil`
  3. `HouseholdSetupView` only shows if auto-creation fails OR user wants to join existing household
  4. **No skip option** - Every user MUST have a household (required for inventory, grocery, locations)
  5. Setup screen options: "Join with invite code" (primary) or "Create my own pantry" (retry creation)
  6. Errors displayed inline - setup screen stays open until household is successfully created/joined
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
10. **syncLogger Parameter Order:** `logSync(householdId, entityType, entityId, action, payload)` - entity_id comes BEFORE action. Check all calls when modifying.
11. **Sync Debug Pattern:** If items aren't syncing, check: (1) syncLogger parameter order matches call sites, (2) sync_log entries have correct entity_id/action values, (3) sync cursor isn't stuck (use Force Full Sync in Settings → Debug).
12. **Household Setup Flow:** New users MUST have household created before dismissing HouseholdSetupView. "Create" button should call `await authViewModel.completeHouseholdSetup()` then dismiss. Never dismiss without household_id.
13. **Database Reset:** Use `./server/scripts/reset-database.sh` to reset production database on VPS. Script SSHs to server, removes volumes, and recreates fresh database. Supports `--force` flag to skip confirmation. Use for clean testing iterations.
14. **Household Member Limit:** Maximum 8 members per household. Check enforced in `joinHousehold()`.

## 📝 Current Task Context
- ✅ New User Onboarding Flow complete
- ✅ Freemium Model (25 item limits) complete
- ✅ Grocery List Feature (with Premium auto-add + SwiftData cache) complete
- ✅ Multi-Device Sync Bug Fixed (syncLogger parameter order + data migration)
- ✅ Household Creation Bug Fixed (auto-create on login + manual create button)
- ✅ Debug Tools Added (Force Full Sync in Settings)
- ✅ Comprehensive Testing Guide Created (TESTING.md with 7 test scenarios)
- **Current Phase:** Pre-TestFlight validation. Execute test plan from TESTING.md starting with Test 1 (Free Tier Solo User).

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

### Testing & Debug:
```bash
# Reset database for clean testing
./server/scripts/reset-database.sh

# Follow structured test plan
open TESTING.md
# Start with Test 1 (Free Tier Solo) → Test 2 (Premium) → Test 3 (Multi-Device)

# iOS Debug Tools:
# Settings → Debug → Force Full Sync Now (clears cursor, triggers bootstrap)
# Settings → Household Sharing → Delete All Household Data (nuclear reset)
```

## 📦 Version Bumping

When the user says **"bump version and build"**:

1. **Read current version/build** from `ios/PantryPal.xcodeproj/project.pbxproj`:
   ```bash
   grep -A1 "MARKETING_VERSION = " ios/PantryPal.xcodeproj/project.pbxproj | head -2
   grep -A1 "CURRENT_PROJECT_VERSION = " ios/PantryPal.xcodeproj/project.pbxproj | head -2
   ```

2. **Generate new build number** in timestamp format `YYYYMMDDHHmmss`:
   ```bash
   date +"%Y%m%d%H%M%S"
   # Example: 20251230221623
   ```

3. **Update project.pbxproj** using sed:
   ```bash
   # Update CURRENT_PROJECT_VERSION with new timestamp
   sed -i '' 's/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = NEW_BUILD;/g' ios/PantryPal.xcodeproj/project.pbxproj
   ```

4. **Commit and tag**:
   ```bash
   git add ios/PantryPal.xcodeproj/project.pbxproj
   git commit -m "chore: Bump build to X.Y.Z (TIMESTAMP)"
   git tag -a "vX.Y.Z-TIMESTAMP" -m "Release vX.Y.Z (TIMESTAMP)"
   git push origin main --tags
   ```

5. **Format**: 
   - Version: `MAJOR.MINOR.PATCH` (e.g., `1.0.0`)
   - Build: Timestamp `YYYYMMDDHHmmss` (e.g., `20251230221623`)
   - Tag: `vMAJOR.MINOR.PATCH-BUILD` (e.g., `v1.0.0-20251230221623`)
