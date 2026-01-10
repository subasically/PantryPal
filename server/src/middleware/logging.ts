import { Request, Response, NextFunction } from 'express';
import logger from '../utils/logger';

/**
 * Middleware to log all HTTP requests
 */
function requestLogger(req: Request, res: Response, next: NextFunction): void {
	const startTime = Date.now();

	// Capture original end function
	const originalEnd = res.end;

	// Override end to log after response is sent
	// @ts-ignore - Signature mismatch with Express Response.end but works at runtime
	res.end = function (...args: any[]): any {
		const duration = Date.now() - startTime;

		// Log the request
		logger.logRequest(
			req.method,
			req.path,
			res.statusCode,
			duration,
			{
				userId: (req as any).user?.id,
				householdId: (req as any).user?.householdId,
				ip: req.ip,
				userAgent: req.get('user-agent')
			}
		);

		// Call original end
		return originalEnd.apply(res, args as any);
	};

	next();
}

export default requestLogger;
