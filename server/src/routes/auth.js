const express = require('express');
const router = express.Router();
const authenticateToken = require('../middleware/auth');
const authService = require('../services/authService');

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
            return res.status(400).json({ error: 'Email and password are required' });
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
        const status = error.message === 'User already exists' ? 400 : 500;
        res.status(status).json({ error: error.message || 'Registration failed' });
    }
});

// Login
router.post('/login', async (req, res) => {
    try {
        const { email, password } = req.body;

        // Validate required fields
        if (!email || !password) {
            return res.status(400).json({ error: 'Email and password are required' });
        }

        const result = await authService.loginUser(email, password);
        res.json(result);
    } catch (error) {
        console.error('Login error:', error);
        const status = error.message === 'Invalid credentials' ? 401 : 500;
        res.status(status).json({ error: error.message || 'Login failed' });
    }
});

const FREE_LIMIT = 25;

// Get current user
router.get('/me', authenticateToken, (req, res) => {
    try {
        const result = authService.getCurrentUser(req.user.id);
        res.json(result);
    } catch (error) {
        console.error('Get current user error:', error);
        res.status(404).json({ error: 'User not found' });
    }
});

module.exports = router;
