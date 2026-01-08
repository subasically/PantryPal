import express, { Response } from 'express';
import authenticateToken, { AuthenticatedRequest } from '../middleware/auth';
import authService from '../services/authService';

const router = express.Router();

// Apple Sign In
router.post('/apple', async (req, res) => {
    try {
        const { identityToken, email, name } = req.body;
        const result = await authService.appleSignIn(identityToken, email, name);
        res.json(result);
    } catch (error) {
        console.error('Apple Sign In error:', error);
        res.status(500).json({ error: 'Apple Sign In failed' });
    }
});

// Register
router.post('/register', async (req, res) => {
    try {
        const { email, password, firstName, lastName, name } = req.body;

        // Validate required fields
        if (!email || !password) {
            res.status(400).json({ error: 'Email and password are required' });
            return;
        }

        // Support both new (firstName/lastName) and legacy (name) formats
        let finalFirstName = firstName || '';
        let finalLastName = lastName || '';

        if (name && !firstName && !lastName) {
            const nameParts = name.trim().split(/\s+/);
            finalFirstName = nameParts[0] || '';
            finalLastName = nameParts.slice(1).join(' ') || '';
        }

        const result = await authService.registerUser(email, password, finalFirstName, finalLastName);
        res.status(201).json({ ...result, householdId: null });
    } catch (error) {
        console.error('Registration error:', error);
        const err = error as Error;
        const status = err.message === 'User already exists' ? 400 : 500;
        res.status(status).json({ error: err.message || 'Registration failed' });
    }
});

// Login
router.post('/login', async (req, res) => {
    try {
        const { email, password } = req.body;

        // Validate required fields
        if (!email || !password) {
            res.status(400).json({ error: 'Email and password are required' });
            return;
        }

        const result = await authService.loginUser(email, password);
        res.json(result);
    } catch (error) {
        console.error('Login error:', error);
        const err = error as Error;
        const status = err.message === 'Invalid credentials' ? 401 : 500;
        res.status(status).json({ error: err.message || 'Login failed' });
    }
});

const FREE_LIMIT = 25;

// Get current user
router.get('/me', authenticateToken, (req: AuthenticatedRequest, res: Response) => {
    try {
        const result = authService.getCurrentUser(req.user.id);
        res.json(result);
    } catch (error) {
        console.error('Get current user error:', error);
        res.status(404).json({ error: 'User not found' });
    }
});

export default router;
