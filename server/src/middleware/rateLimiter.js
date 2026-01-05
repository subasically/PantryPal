const rateLimit = require('express-rate-limit');
const logger = require('../utils/logger');

// Bypass rate limiting in test environment
const skipRateLimiting = process.env.NODE_ENV === 'test';

/**
 * Handler for when rate limit is exceeded
 */
const rateLimitHandler = (req, res) => {
    const limitType = req.rateLimit?.limitType || 'general';
    const resetTime = new Date(req.rateLimit?.resetTime || Date.now());
    
    logger.warn('RATE_LIMIT_EXCEEDED', {
        ip: req.ip,
        path: req.path,
        method: req.method,
        limitType,
        userId: req.user?.id,
        householdId: req.user?.householdId,
        timestamp: new Date().toISOString()
    });

    res.status(429).json({
        error: 'Too many requests',
        message: `Rate limit exceeded for ${limitType} requests. Please try again later.`,
        retryAfter: Math.ceil((resetTime - Date.now()) / 1000),
        limitType
    });
};

/**
 * General API rate limiter
 * 100 requests per 15 minutes per IP
 */
const generalLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // Limit each IP to 100 requests per windowMs
    message: 'Too many requests from this IP, please try again later.',
    standardHeaders: true, // Return rate limit info in `RateLimit-*` headers
    legacyHeaders: false, // Disable `X-RateLimit-*` headers
    skip: () => skipRateLimiting,
    handler: (req, res) => {
        req.rateLimit = { ...req.rateLimit, limitType: 'general API' };
        rateLimitHandler(req, res);
    }
});

/**
 * UPC lookup rate limiter
 * 10 requests per minute per IP (expensive external API calls)
 */
const upcLookupLimiter = rateLimit({
    windowMs: 1 * 60 * 1000, // 1 minute
    max: 10, // Limit each IP to 10 requests per minute
    message: 'Too many UPC lookup requests, please try again later.',
    standardHeaders: true,
    legacyHeaders: false,
    skip: () => skipRateLimiting,
    handler: (req, res) => {
        req.rateLimit = { ...req.rateLimit, limitType: 'UPC lookup' };
        rateLimitHandler(req, res);
    }
});

/**
 * Authentication rate limiter
 * 20 requests per 5 minutes per IP
 * More lenient than before because /auth/me is called during:
 * - Initial sync, household creation, member management, etc.
 * Still protects against brute force on login/register endpoints
 */
const authLimiter = rateLimit({
    windowMs: 5 * 60 * 1000, // 5 minutes
    max: 20, // Limit each IP to 20 auth requests per 5 minutes
    message: 'Too many authentication requests, please try again later.',
    standardHeaders: true,
    legacyHeaders: false,
    skip: () => skipRateLimiting,
    handler: (req, res) => {
        req.rateLimit = { ...req.rateLimit, limitType: 'authentication' };
        // Log potential brute force attempt
        logger.warn('POTENTIAL_BRUTE_FORCE', {
            ip: req.ip,
            path: req.path,
            method: req.method,
            timestamp: new Date().toISOString()
        });
        rateLimitHandler(req, res);
    }
});

module.exports = {
    generalLimiter,
    upcLookupLimiter,
    authLimiter
};
