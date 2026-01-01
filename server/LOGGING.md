# Winston Logging System

PantryPal server uses Winston for structured logging with environment-specific configurations.

## Configuration

### Development Mode
- **Format:** Colorized, human-readable console output
- **Levels:** All levels enabled (error, warn, info, http, verbose, debug)
- **Output:** Console only

### Production Mode
- **Format:** JSON structured logs
- **Levels:** info and above (info, warn, error)
- **Output:** Console + Rotating log files

### Test Mode
- **Output:** No console output (silent)
- **Purpose:** Prevents test pollution

## Log Files (Production Only)

All log files are stored in `server/logs/` and are automatically rotated daily:

- **combined-YYYY-MM-DD.log** - All logs (info, warn, error)
  - Max size: 20MB per file
  - Retention: 14 days
  
- **error-YYYY-MM-DD.log** - Error logs only
  - Max size: 20MB per file
  - Retention: 30 days
  
- **premium-YYYY-MM-DD.log** - Premium enforcement logs
  - Max size: 20MB per file
  - Retention: 14 days

## Usage

### Basic Logging

```javascript
const logger = require('./utils/logger');

logger.error('Database connection failed');
logger.warn('API rate limit approaching');
logger.info('User registered successfully');
logger.http('GET /api/inventory 200 125ms');
logger.debug('Cache hit for key: inventory-123');
```

### Structured Logging Methods

#### Authentication Events
```javascript
logger.logAuth('login_success', {
    userId: 'user-123',
    email: 'user@example.com',
    householdId: 'household-456'
});

logger.logAuth('token_invalid', {
    error: 'Token expired',
    path: '/api/inventory',
    ip: '192.168.1.1'
});
```

#### Premium Enforcement
```javascript
logger.logPremium('limit_check', {
    householdId: 'household-123',
    isPremium: false,
    currentCount: 25,
    limit: 25,
    canAdd: false
});

logger.logPremium('premium_check', {
    householdId: 'household-123',
    isPremium: true,
    expiresAt: '2026-12-31T23:59:59Z'
});
```

#### API Requests (Automatic)
```javascript
// Middleware automatically logs all requests
logger.logRequest('POST', '/api/inventory', 201, 150, {
    userId: 'user-123',
    householdId: 'household-456',
    ip: '192.168.1.1'
});
```

#### Error Logging with Context
```javascript
try {
    // Some operation
} catch (error) {
    logger.logError('Failed to create inventory item', error, {
        userId: req.user.id,
        householdId: req.user.householdId,
        itemId: 'item-123'
    });
}
```

## Current Integrations

### ✅ Middleware
- **Request Logging:** All HTTP requests logged with method, path, status, duration
- **Auth Middleware:** Token validation events logged

### ✅ Routes
- **Auth Routes:** Login, logout, registration, Apple Sign In events
- **Premium Enforcement:** All limit checks and premium status checks

### ✅ Application
- **Server Startup:** Environment and port information
- **Cron Jobs:** Daily expiration checks, weekly low stock checks
- **Error Handlers:** Unhandled errors with context

## Log Levels

1. **error** - Application errors, failed operations
2. **warn** - Warnings, potential issues (e.g., rate limits)
3. **info** - General informational messages (auth events, premium checks)
4. **http** - HTTP request/response logs
5. **verbose** - Detailed operational information
6. **debug** - Debug information for development

## Best Practices

### DO:
✅ Use structured logging methods (`logAuth`, `logPremium`, etc.)
✅ Include user/household IDs for traceability
✅ Log both success and failure cases
✅ Use appropriate log levels
✅ Include context objects for errors

### DON'T:
❌ Log sensitive data (passwords, tokens, credit cards)
❌ Log PII without encryption/masking
❌ Use `console.log` in production code
❌ Create custom log files (use Winston transports)

## Querying Logs (Production)

```bash
# SSH to production server
ssh root@62.146.177.62

# View latest logs
cd /root/pantrypal-server/logs
tail -f combined-$(date +%Y-%m-%d).log

# Search for specific events
grep "AUTH_EVENT" combined-*.log | jq '.event'
grep "PREMIUM_CHECK" combined-*.log | jq '.householdId'

# View errors only
tail -f error-$(date +%Y-%m-%d).log

# Count login failures
grep "login_failed" combined-*.log | wc -l
```

## Environment Variables

No additional environment variables required. Logging behavior is controlled by `NODE_ENV`:

- `NODE_ENV=development` - Development logging
- `NODE_ENV=production` - Production logging
- `NODE_ENV=test` - Silent (test mode)

## Monitoring & Alerts

Future integrations:
- [ ] CloudWatch Logs (AWS)
- [ ] Sentry error tracking
- [ ] Datadog APM
- [ ] Slack alerts for critical errors
