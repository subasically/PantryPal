# Copilot Instructions Analysis & Improvements

**Date:** 2025-12-29  
**Status:** ✅ Updated with deployment info and lessons learned

---

## 📊 Analysis of Current Instructions

### ✅ **Strengths:**

1. **Clear Philosophy**: "Ruthless MVP" sets clear boundaries for feature creep
2. **Tech Stack**: Well-documented with specific versions (Node 20, Swift 6, iOS 18+)
3. **Coding Standards**: Minimal changes principle is excellent for maintainability
4. **Premium Logic**: Clearly defined (30 items free, unlimited Premium)
5. **Onboarding Flow**: Step-by-step guide prevents confusion

### 🔧 **Improvements Made (2025-12-29):**

#### Added Server Deployment Info:
- Production IP: `62.146.177.62`
- Server path: `/root/pantrypal-server`
- Production URL: `https://api-pantrypal.subasically.me`
- Quick deploy commands with Docker Compose
- Database migration instructions

#### Enhanced "Known Gotchas":
- Auth middleware import pattern (default vs named export)
- iOS property names (`currentUser` vs `user`)
- SwiftData import requirements
- APIError scope (file-level, not class member)
- Server deployment via `scp` (not git)

#### Updated iOS Standards:
- SwiftData import reminder
- APIError usage pattern
- Common property name mistakes

---

## 💡 Recommendations for Future Improvements

### 1. **Add Architecture Diagrams**
Consider adding:
- API request flow (iOS → Server → Database)
- Premium feature gating flow
- Sync mechanism overview

### 2. **Environment-Specific Configs**
Document:
- Local development setup (localhost:3002)
- Staging environment (if any)
- Production environment (current)

### 3. **Common Error Patterns**
Add section for:
- "Cannot find module" → Check imports
- "Build failed" → Check Xcode project file membership
- "403 Forbidden" → Check Premium household status

### 4. **Testing Guidelines**
Add:
- How to test Premium features locally
- How to test with multiple devices/households
- How to reset test data

### 5. **API Response Patterns**
Document:
```json
// Success
{ "data": {...} }

// Error with upgrade required
{ "error": "...", "code": "PREMIUM_REQUIRED", "upgradeRequired": true }
```

### 6. **Database Schema Reference**
Quick reference for key tables:
- `users` (household_id nullable)
- `households` (is_premium flag)
- `inventory` (quantity, expiration_date)
- `grocery_items` (household_id, normalized_name)

---

## 🎯 Current Task Context - What to Update Next

**Completed:**
- ✅ New User Onboarding Flow
- ✅ Freemium Model (30 item limit)
- ✅ Grocery List Feature (with Premium auto-add)

**Next Up (from TODO.md):**
- [ ] Push notifications for expiring items
- [ ] Background sync when online  
- [ ] In-App Purchases (StoreKit integration)
- [ ] One-time "household locked" banner
- [ ] Restore purchases

**When to update this section:**
- After completing a major feature
- Before starting a new sprint
- When project phase changes (e.g., Revenue Validation → Growth)

---

## 🔐 Security Considerations

**Currently Not in Instructions (Consider Adding):**

1. **JWT Token Handling**:
   - Tokens stored in UserDefaults
   - No token refresh mechanism documented
   - Token expiration policy

2. **Sensitive Data**:
   - Don't log user emails/passwords
   - Sanitize error messages before sending to client

3. **Rate Limiting**:
   - Not mentioned (may not be implemented)

---

## 📝 Maintenance Notes

**Update copilot instructions when:**
- Major architecture changes
- New deployment process
- Common bugs/gotchas discovered (like today's auth import issue)
- New team members join (onboarding clarity)
- Tech stack versions change

**Keep it concise:**
- Instructions are ~100 lines (good length)
- Focus on "what's different/unexpected" not "what's standard"
- Link to external docs for deep dives

---

## ✅ Action Items Completed

- [x] Added production server IP and path
- [x] Documented deployment process
- [x] Enhanced "Known Gotchas" with today's lessons
- [x] Added iOS coding standards for SwiftData/Errors
- [x] Updated current task context
- [x] Documented grocery list endpoints in README

## 🎉 Result

The copilot instructions are now:
- **Production-ready** with deployment info
- **Battle-tested** with real gotchas documented
- **Up-to-date** with latest features (grocery list)
- **Actionable** with copy-paste commands

---

**Next Review Date:** After implementing StoreKit / IAP
