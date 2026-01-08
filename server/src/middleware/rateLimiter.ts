import rateLimit, { RateLimitRequestHandler } from 'express-rate-limit';
import { Request, Response } from 'express';
import logger from '../utils/logger';

const skipRateLimiting = process.env.NODE_ENV === 'test';

interface RateLimitRequest extends Request {
	rateLimit?: {
		limitType?: string;
		resetTime?: Date;
		limit?: number;
		current?: number;
		remaining?: number;
	};
}

/**
 * Handler for when rate limit is exceeded
 */
const rateLimitHandler = (req: RateLimitRequest, res: Response): void => {
	const limitType = req.rateLimit?.limitType || 'general';
	const resetTime = new Date(req.rateLimit?.resetTime || Date.now());

	logger.warn('RATE_LIMIT_EXCEEDED', {
		ip: req.ip,
		path: req.path,
		method: req.method,
		limitType,
		userId: (req as any).user?.id,
		householdId: (req as any).user?.householdId,
		timestamp: new Date().toISOString()
	});

	res.status(429).json({
		error: 'Too many requests',
		message: `Rate limit exceeded for ${limitType} requests. Please try again later.`,
		retryAfter: Math.ceil((resetTime.getTime() - Date.now()) / 1000),
		limitType
	});
};

/**
 * General API rate limiter
 * 100 requests per 15 minutes per IP
 */
export const generalLimiter: RateLimitRequestHandler = rateLimit({
	windowMs: 15 * 60 * 1000,
	max: 100,
	message: 'Too many requests from this IP, please try again later.',
	standardHeaders: true,
	legacyHeaders: false,
	skip: () => skipRateLimiting,
	handler: (req: Request, res: Response) => {
		const rateLimitReq = req as RateLimitRequest;
		rateLimitReq.rateLimit = { ...rateLimitReq.rateLimit, limitType: 'general API' };
		rateLimitHandler(rateLimitReq, res);
	}
});

/**
 * UPC lookup rate limiter
 * 10 requests per minute per IP
 */
export const upcLookupLimiter: RateLimitRequestHandler = rateLimit({
	windowMs: 1 * 60 * 1000,
	max: 10,
	message: 'Too many UPC lookup requests, please try again later.',
	standardHeaders: true,
	legacyHeaders: false,
	skip: () => skipRateLimiting,
	handler: (req: Request, res: Response) => {
		const rateLimitReq = req as RateLimitRequest;
		rateLimitReq.rateLimit = { ...rateLimitReq.rateLimit, limitType: 'UPC lookup' };
		rateLimitHandler(rateLimitReq, res);
	}
});

/**
 * Authentication rate limiter
 * 20 requests per 5 minutes per IP
 */
export const authLimiter: RateLimitRequestHandler = rateLimit({
	windowMs: 5 * 60 * 1000,
	max: 20,
	message: 'Too many authentication requests, please try again later.',
	standardHeaders: true,
	legacyHeaders: false,
	skip: () => skipRateLimiting,
	handler: (req: Request, res: Response) => {
		const rateLimitReq = req as RateLimitRequest;
		rateLimitReq.rateLimit = { ...rateLimitReq.rateLimit, limitType: 'authentication' };
		logger.warn('POTENTIAL_BRUTE_FORCE', {
			ip: req.ip,
			path: req.path,
			method: req.method,
			timestamp: new Date().toISOString()
		});
		rateLimitHandler(rateLimitReq, res);
	}
});

export default {
	generalLimiter,
	upcLookupLimiter,
	authLimiter
};
