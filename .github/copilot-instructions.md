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
- **Deployment:** Docker Compose on a VPS

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
  - Free Tier: Hard limit of **30 items** (configurable).
  - Premium: Unlimited items + Household Sharing (Write access).
  - Check limits *before* INSERT/UPDATE.

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

## ⚠️ Known "Gotchas"
1. **New Users:** A new user created via Apple Sign In does **NOT** have a household immediately. They must create or join one.
2. **Database Reset:** If the schema changes, the `pantrypal-data` Docker volume must be updated or the tables dropped.
3. **Loading States:** Ensure loading spinners persist for at least **1.5s** to prevent UI flashing.

## 📝 Current Task Context
- We just implemented the **New User Onboarding Flow**.
- We just implemented the **Freemium Model** (30 item limit).
- The server database schema was recently updated to allow NULL `household_id`.
