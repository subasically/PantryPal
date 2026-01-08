import jwt from 'jsonwebtoken';
import { Request, Response, NextFunction } from 'express';
import { Database } from 'better-sqlite3';
import logger from '../utils/logger';

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';

// Lazy load database to avoid circular dependencies
let dbInstance: Database | null = null;
function getDb(): Database {
	if (!dbInstance) {
		dbInstance = require('../models/database').default;
	}
	return dbInstance as Database;
}

interface JwtPayload {
	id: string;
	email: string;
}

interface UserRow {
	id: string;
	email: string;
	name: string | null;
	household_id: string | null;
}

export interface AuthenticatedUser {
	id: string;
	email: string;
	name: string | null;
	householdId: string | null;
}

export interface AuthenticatedRequest extends Request {
	user: AuthenticatedUser;
}

function authenticateToken(req: Request, res: Response, next: NextFunction): void {
	const db = getDb();
	const authHeader = req.headers['authorization'];
	const token = authHeader && authHeader.split(' ')[1];

	if (!token) {
		logger.logAuth('token_missing', {
			path: req.path,
			ip: req.ip
		});
		res.sendStatus(401);
		return;
	}

	jwt.verify(token, JWT_SECRET, (err, decoded) => {
		if (err) {
			logger.logAuth('token_invalid', {
				error: err.message,
				path: req.path,
				ip: req.ip
			});
			res.sendStatus(403);
			return;
		}

		try {
			const user = decoded as JwtPayload;

			// Fetch fresh user data to ensure householdId is up to date
			const freshUser = db.prepare('SELECT * FROM users WHERE id = ?').get(user.id) as UserRow | undefined;

			if (!freshUser) {
				logger.logAuth('user_not_found', {
					userId: user.id,
					path: req.path
				});
				res.sendStatus(403);
				return;
			}

			(req as AuthenticatedRequest).user = {
				id: freshUser.id,
				email: freshUser.email,
				name: freshUser.name,
				householdId: freshUser.household_id
			};

			logger.logAuth('token_validated', {
				userId: freshUser.id,
				householdId: freshUser.household_id,
				path: req.path
			});

			next();
		} catch (error) {
			logger.logError('Auth middleware error', error as Error, {
				userId: (decoded as JwtPayload)?.id,
				path: req.path
			});
			res.sendStatus(500);
		}
	});
}

export default authenticateToken;
