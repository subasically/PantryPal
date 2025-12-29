const express = require('express');
const router = express.Router();
const db = require('../models/database');
const authenticateToken = require('../middleware/auth');

// Helper: Normalize name for deduplication
function normalizeName(name) {
  return name.trim().toLowerCase().replace(/\s+/g, ' ');
}

// GET /api/grocery - Get all grocery items for household
router.get('/', authenticateToken, (req, res) => {
  const userId = req.user.userId;
  
  try {
    const user = db.prepare('SELECT household_id FROM users WHERE id = ?').get(userId);
    
    // If no household, return empty array (not an error)
    if (!user || !user.household_id) {
      return res.json([]);
    }
    
    const items = db.prepare(`
      SELECT id, household_id, name, created_at
      FROM grocery_items
      WHERE household_id = ?
      ORDER BY created_at DESC
    `).all(user.household_id);
    
    res.json(items);
  } catch (error) {
    console.error('Error fetching grocery items:', error);
    res.status(500).json({ error: 'Failed to fetch grocery items' });
  }
});

// POST /api/grocery - Add item to grocery list
router.post('/', authenticateToken, (req, res) => {
  const userId = req.user.userId;
  const { name } = req.body;
  
  if (!name?.trim()) {
    return res.status(400).json({ error: 'Item name required' });
  }
  
  try {
    const user = db.prepare('SELECT household_id FROM users WHERE id = ?').get(userId);
    
    if (!user || !user.household_id) {
      return res.status(400).json({ 
        error: 'Please create or join a household first',
        requiresHousehold: true
      });
    }
    
    const normalizedName = normalizeName(name);
    
    // Check if already exists
    const existing = db.prepare(`
      SELECT id FROM grocery_items
      WHERE household_id = ? AND normalized_name = ?
    `).get(user.household_id, normalizedName);
    
    if (existing) {
      return res.status(409).json({ error: 'Item already on grocery list' });
    }
    
    const result = db.prepare(`
      INSERT INTO grocery_items (household_id, name, normalized_name)
      VALUES (?, ?, ?)
    `).run(user.household_id, name.trim(), normalizedName);
    
    const newItem = db.prepare('SELECT * FROM grocery_items WHERE id = ?').get(result.lastInsertRowid);
    
    res.status(201).json(newItem);
  } catch (error) {
    console.error('Error adding grocery item:', error);
    res.status(500).json({ error: 'Failed to add grocery item' });
  }
});

// DELETE /api/grocery/:id - Remove item from grocery list
router.delete('/:id', authenticateToken, (req, res) => {
  const userId = req.user.userId;
  const itemId = parseInt(req.params.id);
  
  try {
    const user = db.prepare('SELECT household_id FROM users WHERE id = ?').get(userId);
    
    if (!user || !user.household_id) {
      return res.status(400).json({ 
        error: 'Please create or join a household first',
        requiresHousehold: true
      });
    }
    
    // Verify item belongs to user's household
    const item = db.prepare(`
      SELECT id FROM grocery_items
      WHERE id = ? AND household_id = ?
    `).get(itemId, user.household_id);
    
    if (!item) {
      return res.status(404).json({ error: 'Item not found' });
    }
    
    db.prepare('DELETE FROM grocery_items WHERE id = ?').run(itemId);
    
    res.json({ success: true });
  } catch (error) {
    console.error('Error deleting grocery item:', error);
    res.status(500).json({ error: 'Failed to delete grocery item' });
  }
});

module.exports = router;
