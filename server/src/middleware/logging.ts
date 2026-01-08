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
	res.end = function (...args: any[]): Response {
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
		return originalEnd.apply(res, args);
	};

	next();
}

export default requestLogger;
