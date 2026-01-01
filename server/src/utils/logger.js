const winston = require('winston');
const DailyRotateFile = require('winston-daily-rotate-file');
const path = require('path');

const isProduction = process.env.NODE_ENV === 'production';
const isTest = process.env.NODE_ENV === 'test';

// Define log directory
const logDir = path.join(__dirname, '../../logs');

// Custom format for development (readable)
const devFormat = winston.format.combine(
    winston.format.colorize(),
    winston.format.timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
    winston.format.printf(({ timestamp, level, message, ...meta }) => {
        let msg = `${timestamp} [${level}]: ${message}`;
        if (Object.keys(meta).length > 0) {
            msg += ` ${JSON.stringify(meta)}`;
        }
        return msg;
    })
);

// Production format (JSON)
const prodFormat = winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
);

// Create transports array
const transports = [];

// Console transport (always enabled except in test)
if (!isTest) {
    transports.push(
        new winston.transports.Console({
            format: isProduction ? prodFormat : devFormat,
            level: isProduction ? 'info' : 'debug'
        })
    );
}

// File transports for production
if (isProduction) {
    // Combined logs (all levels)
    transports.push(
        new DailyRotateFile({
            dirname: logDir,
            filename: 'combined-%DATE%.log',
            datePattern: 'YYYY-MM-DD',
            maxSize: '20m',
            maxFiles: '14d',
            format: prodFormat,
            level: 'info'
        })
    );

    // Error logs only
    transports.push(
        new DailyRotateFile({
            dirname: logDir,
            filename: 'error-%DATE%.log',
            datePattern: 'YYYY-MM-DD',
            maxSize: '20m',
            maxFiles: '30d',
            format: prodFormat,
            level: 'error'
        })
    );

    // Premium enforcement logs
    transports.push(
        new DailyRotateFile({
            dirname: logDir,
            filename: 'premium-%DATE%.log',
            datePattern: 'YYYY-MM-DD',
            maxSize: '20m',
            maxFiles: '14d',
            format: prodFormat,
            level: 'info'
        })
    );
}

// Create logger instance
const logger = winston.createLogger({
    levels: winston.config.npm.levels, // error, warn, info, http, verbose, debug, silly
    transports,
    silent: isTest, // Completely disable logging in test environment
    exitOnError: false
});

// Helper methods for structured logging

/**
 * Log authentication events
 */
logger.logAuth = (event, details = {}) => {
    logger.info('AUTH_EVENT', {
        event,
        ...details,
        timestamp: new Date().toISOString()
    });
};

/**
 * Log premium enforcement decisions
 */
logger.logPremium = (action, details = {}) => {
    logger.info('PREMIUM_CHECK', {
        action,
        ...details,
        timestamp: new Date().toISOString()
    });
};

/**
 * Log API requests (for middleware)
 */
logger.logRequest = (method, path, status, duration, details = {}) => {
    logger.http('API_REQUEST', {
        method,
        path,
        status,
        duration,
        ...details,
        timestamp: new Date().toISOString()
    });
};

/**
 * Log errors with context
 */
logger.logError = (message, error, context = {}) => {
    logger.error(message, {
        error: error.message,
        stack: error.stack,
        ...context,
        timestamp: new Date().toISOString()
    });
};

module.exports = logger;
