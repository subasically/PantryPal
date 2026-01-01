# Rate Limiting Documentation

PantryPal API implements rate limiting to protect against abuse, prevent brute force attacks, and manage expensive external API calls.

## Overview

Rate limiting is implemented using the `express-rate-limit` package and is applied at different levels based on endpoint sensitivity and resource cost.

## Rate Limit Configuration

### 1. General API Rate Limit
- **Limit:** 100 requests per 15 minutes per IP address
- **Applies to:** All `/api/*` endpoints (except those with specific limits)
- **Purpose:** Prevent general API abuse and ensure fair resource allocation
- **Status Code:** 429 (Too Many Requests)

### 2. Authentication Rate Limit
- **Limit:** 5 requests per 5 minutes per IP address
- **Applies to:** All `/api/auth/*` endpoints
  - `POST /api/auth/register`
  - `POST /api/auth/login`
  - `POST /api/auth/apple`
  - All other auth endpoints
- **Purpose:** Prevent brute force attacks and credential stuffing
- **Status Code:** 429 (Too Many Requests)
- **Additional Security:** Logs potential brute force attempts with Winston

### 3. UPC Lookup Rate Limit
- **Limit:** 10 requests per minute per IP address
- **Applies to:** `GET /api/products/lookup/:upc`
- **Purpose:** Protect expensive external UPC API calls and prevent abuse
- **Status Code:** 429 (Too Many Requests)

## Response Format

When a rate limit is exceeded, the API returns a 429 status code with the following JSON response:

```json
{
  "error": "Too many requests",
  "message": "Rate limit exceeded for authentication requests. Please try again later.",
  "retryAfter": 180,
  "limitType": "authentication"
}
```

### Response Fields
- **error:** Generic error message
- **message:** Human-readable explanation with context
- **retryAfter:** Seconds until the rate limit resets
- **limitType:** Which rate limiter was triggered (`"general API"`, `"authentication"`, or `"UPC lookup"`)

## Rate Limit Headers

The API includes standard rate limit headers in responses:

- `RateLimit-Limit`: Maximum requests allowed in the window
- `RateLimit-Remaining`: Requests remaining in current window
- `RateLimit-Reset`: Unix timestamp when the rate limit resets

Example:
```
RateLimit-Limit: 100
RateLimit-Remaining: 87
RateLimit-Reset: 1704758400
```

## Logging

Rate limit violations are logged using Winston with the following structure:

```javascript
{
  event: "RATE_LIMIT_EXCEEDED",
  ip: "192.168.1.100",
  path: "/api/auth/login",
  method: "POST",
  limitType: "authentication",
  userId: "uuid-if-authenticated",
  householdId: "uuid-if-exists",
  timestamp: "2026-01-01T22:30:00.000Z"
}
```

Authentication rate limit violations also log a `POTENTIAL_BRUTE_FORCE` event for security monitoring.

## Testing Environment

Rate limiting is **automatically disabled** when `NODE_ENV=test` to prevent test failures. This allows the test suite to make unlimited requests without hitting limits.

## Best Practices for Clients

### iOS App Recommendations

1. **Implement Exponential Backoff:** When receiving a 429 response, use the `retryAfter` value to wait before retrying.

2. **Cache Responses:** Cache UPC lookup results locally to avoid repeated API calls.

3. **Batch Operations:** Where possible, batch multiple operations into single requests.

4. **Handle 429 Gracefully:** Show user-friendly error messages like "Too many requests. Please wait a moment."

### Example Swift Error Handling

```swift
if response.statusCode == 429 {
    if let data = data,
       let error = try? JSONDecoder().decode(RateLimitError.self, from: data) {
        // Wait for error.retryAfter seconds before retrying
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(error.retryAfter)) {
            // Retry the request
        }
    }
}
```

## IP Address Detection

The server is configured with `trust proxy` enabled to correctly detect client IP addresses when behind:
- Reverse proxies (Nginx, Apache)
- Load balancers
- CDNs (Cloudflare, CloudFront)

This ensures rate limits are applied per actual client IP, not per proxy IP.

## Adjusting Rate Limits

To modify rate limits, edit `server/src/middleware/rateLimiter.js`:

```javascript
// Example: Increase auth limit to 10 requests per 5 minutes
const authLimiter = rateLimit({
    windowMs: 5 * 60 * 1000,
    max: 10, // Changed from 5 to 10
    // ... other config
});
```

After changing limits:
1. Restart the server
2. Update this documentation
3. Notify iOS app team if limits affect client behavior

## Monitoring

Monitor rate limit violations in production logs:

```bash
# View rate limit violations
docker-compose logs pantrypal-api | grep "RATE_LIMIT_EXCEEDED"

# View potential brute force attempts
docker-compose logs pantrypal-api | grep "POTENTIAL_BRUTE_FORCE"
```

## Future Enhancements

Consider implementing:
- [ ] User-based rate limiting (in addition to IP-based)
- [ ] Different limits for premium vs free users
- [ ] Redis-backed rate limiting for distributed deployments
- [ ] Dynamic rate limits based on server load
- [ ] Whitelist for trusted IPs (CI/CD, monitoring)

## Troubleshooting

### Issue: Tests Failing Due to Rate Limits
**Solution:** Ensure `NODE_ENV=test` is set. Rate limiting is automatically disabled in test mode.

### Issue: Rate Limits Too Restrictive
**Solution:** Review logs to identify legitimate use patterns. Adjust limits in `rateLimiter.js` accordingly.

### Issue: Rate Limits Not Working
**Solution:** Verify `trust proxy` is enabled in `app.js` and that the server is correctly detecting client IPs.

## Related Documentation

- [Winston Logging Implementation](./WINSTON_IMPLEMENTATION_SUMMARY.md)
- [Logging Guide](./LOGGING.md)
- [API Documentation](../README.md)
