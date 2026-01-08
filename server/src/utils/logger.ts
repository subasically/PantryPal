import winston from 'winston';
import DailyRotateFile from 'winston-daily-rotate-file';
import path from 'path';

const isProduction = process.env.NODE_ENV === 'production';
const isTest = process.env.NODE_ENV === 'test';

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
const transports: winston.transport[] = [];

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
    levels: winston.config.npm.levels,
    transports,
    silent: isTest,
    exitOnError: false
});

// Extend logger with custom methods
interface CustomLogger extends winston.Logger {
    logAuth: (event: string, details?: Record<string, any>) => void;
    logPremium: (action: string, details?: Record<string, any>) => void;
    logRequest: (method: string, path: string, status: number, duration: number, details?: Record<string, any>) => void;
    logError: (message: string, error: Error, context?: Record<string, any>) => void;
}

const customLogger = logger as CustomLogger;

customLogger.logAuth = (event: string, details: Record<string, any> = {}) => {
    logger.info('AUTH_EVENT', {
        event,
        ...details,
        timestamp: new Date().toISOString()
    });
};

customLogger.logPremium = (action: string, details: Record<string, any> = {}) => {
    logger.info('PREMIUM_CHECK', {
        action,
        ...details,
        timestamp: new Date().toISOString()
    });
};

customLogger.logRequest = (method: string, path: string, status: number, duration: number, details: Record<string, any> = {}) => {
    logger.http('API_REQUEST', {
        method,
        path,
        status,
        duration,
        ...details,
        timestamp: new Date().toISOString()
    });
};

customLogger.logError = (message: string, error: Error, context: Record<string, any> = {}) => {
    logger.error(message, {
        error: error.message,
        stack: error.stack,
        ...context,
        timestamp: new Date().toISOString()
    });
};

export default customLogger;
