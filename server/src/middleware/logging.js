const logger = require('../utils/logger');

/**
 * Middleware to log all HTTP requests
 */
function requestLogger(req, res, next) {
    const startTime = Date.now();

    // Capture original end function
    const originalEnd = res.end;

    // Override end to log after response is sent
    res.end = function(...args) {
        const duration = Date.now() - startTime;
        
        // Log the request
        logger.logRequest(
            req.method,
            req.path,
            res.statusCode,
            duration,
            {
                userId: req.user?.id,
                householdId: req.user?.householdId,
                ip: req.ip,
                userAgent: req.get('user-agent')
            }
        );

        // Call original end
        originalEnd.apply(res, args);
    };

    next();
}

module.exports = requestLogger;
