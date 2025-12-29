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
  const householdId = req.user.householdId;
  
  try {
    // If no household, return empty array (not an error)
    if (!householdId) {
      return res.json([]);
    }
    
    const items = db.prepare(`
      SELECT id, household_id, name, created_at
      FROM grocery_items
      WHERE household_id = ?
      ORDER BY created_at DESC
    `).all(householdId);
    
    res.json(items);
  } catch (error) {
    console.error('Error fetching grocery items:', error);
    res.status(500).json({ error: 'Failed to fetch grocery items' });
  }
});

// POST /api/grocery - Add item to grocery list
router.post('/', authenticateToken, (req, res) => {
  const householdId = req.user.householdId;
  const { name } = req.body;
  
  console.log('[Grocery] POST request - householdId:', householdId, 'name:', name);
  
  if (!name?.trim()) {
    return res.status(400).json({ error: 'Item name required' });
  }
  
  try {
    if (!householdId) {
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
    `).get(householdId, normalizedName);
    
    if (existing) {
      console.log('[Grocery] Item already exists:', normalizedName);
      return res.status(409).json({ error: 'Item already on grocery list' });
    }
    
    const result = db.prepare(`
      INSERT INTO grocery_items (household_id, name, normalized_name)
      VALUES (?, ?, ?)
    `).run(householdId, name.trim(), normalizedName);
    
    const newItem = db.prepare('SELECT * FROM grocery_items WHERE id = ?').get(result.lastInsertRowid);
    
    console.log('[Grocery] Item added successfully:', newItem.id);
    
    res.status(201).json(newItem);
  } catch (error) {
    console.error('Error adding grocery item:', error);
    res.status(500).json({ error: 'Failed to add grocery item' });
  }
});

// DELETE /api/grocery/:id - Remove item from grocery list
router.delete('/:id', authenticateToken, (req, res) => {
  const householdId = req.user.householdId;
  const itemId = parseInt(req.params.id);
  
  try {
    if (!householdId) {
      return res.status(400).json({ 
        error: 'Please create or join a household first',
        requiresHousehold: true
      });
    }
    
    // Verify item belongs to user's household
    const item = db.prepare(`
      SELECT id FROM grocery_items
      WHERE id = ? AND household_id = ?
    `).get(itemId, householdId);
    
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
