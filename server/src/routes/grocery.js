const express = require('express');
const router = express.Router();
const db = require('../models/database');
const authenticateToken = require('../middleware/auth');

console.log('🔵 [Grocery Routes] Module loaded - VERSION 2025-12-30-19:30');

const FREE_LIMIT = 25;

// Check if user can write (Premium required for shared households with multiple members)
function checkWritePermission(householdId) {
    console.log(`[GroceryWrite] START - householdId: ${householdId}`);
    
    if (!householdId) {
        console.log(`[GroceryWrite] No household - ALLOW`);
        return true;
    }
    
    // Get household data including member count
    const household = db.prepare(`
        SELECT h.id, h.is_premium, h.premium_expires_at,
               (SELECT COUNT(*) FROM users WHERE household_id = h.id) as member_count
        FROM households h
        WHERE h.id = ?
    `).get(householdId);
    
    console.log(`[GroceryWrite] Household query result:`, JSON.stringify(household));
    
    if (!household) {
        console.log(`[GroceryWrite] Household not found - ALLOW (shouldn't happen)`);
        return true;
    }
    
    // Single-member household: always allow
    if (household.member_count <= 1) {
        console.log(`[GroceryWrite] Single-member household (${household.member_count}) - ALLOW`);
        return true;
    }
    
    // Multi-member household: require Premium
    // Check if Premium is active (accounting for expiration)
    const isPremium = household.is_premium === 1 && 
                     (!household.premium_expires_at || 
                      new Date(household.premium_expires_at) > new Date());
    
    console.log(`[GroceryWrite] Multi-member household (${household.member_count} members), isPremium: ${isPremium}, is_premium: ${household.is_premium}, expires_at: ${household.premium_expires_at}`);
    
    if (isPremium) {
        console.log(`[GroceryWrite] ALLOW - Premium active`);
    } else {
        console.log(`[GroceryWrite] DENY - Premium required for multi-member household`);
    }
    
    return isPremium;
}

// Check if grocery list is under limit
function checkGroceryLimit(householdId) {
    if (!householdId) return true; // No household = no limit check
    
    const household = db.prepare('SELECT is_premium FROM households WHERE id = ?').get(householdId);
    if (household && household.is_premium) return true; // Premium = unlimited
    
    const count = db.prepare('SELECT COUNT(*) as count FROM grocery_items WHERE household_id = ?').get(householdId).count;
    return count < FREE_LIMIT;
}

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
      SELECT id, household_id, name, brand, upc, created_at
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
  const { name, brand, upc } = req.body;
  
  console.log('[Grocery] POST request - householdId:', householdId, 'name:', name, 'brand:', brand, 'upc:', upc);
  
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
    
    // Check write permission (shared household)
    console.log('[Grocery] BEFORE checkWritePermission, householdId:', householdId);
    const hasWritePermission = checkWritePermission(householdId);
    console.log('[Grocery] AFTER checkWritePermission, result:', hasWritePermission);
    
    if (!hasWritePermission) {
      console.log('[Grocery] DENYING write permission');
      return res.status(403).json({ 
        error: 'Household sharing is a Premium feature. Upgrade to add items.',
        code: 'PREMIUM_REQUIRED',
        upgradeRequired: true
      });
    }
    
    console.log('[Grocery] Write permission GRANTED, checking limit...');
    
    // Check grocery limit
    if (!checkGroceryLimit(householdId)) {
      return res.status(403).json({ 
        error: 'Grocery list limit reached',
        code: 'LIMIT_REACHED',
        limit: FREE_LIMIT,
        upgradeRequired: true
      });
    }
    
    const normalizedName = normalizeName(name);
    
    // Check if already exists
    const existing = db.prepare(`
      SELECT * FROM grocery_items
      WHERE household_id = ? AND normalized_name = ?
    `).get(householdId, normalizedName);
    
    if (existing) {
      console.log('[Grocery] Item already exists:', normalizedName);
      // Return success with the existing item (idempotent for auto-add)
      return res.status(200).json(existing);
    }
    
    const result = db.prepare(`
      INSERT INTO grocery_items (household_id, name, brand, upc, normalized_name)
      VALUES (?, ?, ?, ?, ?)
    `).run(householdId, name.trim(), brand || null, upc || null, normalizedName);
    
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

// DELETE /api/grocery/by-upc/:upc - Remove item by UPC (for auto-remove on restock)
router.delete('/by-upc/:upc', authenticateToken, (req, res) => {
  const householdId = req.user.householdId;
  const { upc } = req.params;
  
  console.log('[Grocery] DELETE by-upc request - householdId:', householdId, 'upc:', upc);
  
  try {
    if (!householdId) {
      return res.status(400).json({ 
        error: 'Please create or join a household first',
        requiresHousehold: true
      });
    }
    
    if (!upc) {
      return res.status(400).json({ error: 'UPC required' });
    }
    
    const result = db.prepare(`
      DELETE FROM grocery_items
      WHERE household_id = ? AND upc = ?
    `).run(householdId, upc);
    
    console.log('[Grocery] Deleted by UPC, changes:', result.changes);
    
    res.json({ 
      success: true, 
      removed: result.changes > 0,
      count: result.changes 
    });
  } catch (error) {
    console.error('Error deleting grocery item by UPC:', error);
    res.status(500).json({ error: 'Failed to delete grocery item' });
  }
});

// DELETE /api/grocery/by-name/:normalizedName - Remove item by normalized name (for auto-remove on restock)
router.delete('/by-name/:normalizedName', authenticateToken, (req, res) => {
  const householdId = req.user.householdId;
  const { normalizedName } = req.params;
  
  console.log('[Grocery] DELETE by-name request - householdId:', householdId, 'normalizedName:', normalizedName);
  
  try {
    if (!householdId) {
      return res.status(400).json({ 
        error: 'Please create or join a household first',
        requiresHousehold: true
      });
    }
    
    if (!normalizedName) {
      return res.status(400).json({ error: 'Name required' });
    }
    
    const result = db.prepare(`
      DELETE FROM grocery_items
      WHERE household_id = ? AND normalized_name = ?
    `).run(householdId, normalizedName);
    
    console.log('[Grocery] Deleted by name, changes:', result.changes);
    
    res.json({ 
      success: true, 
      removed: result.changes > 0,
      count: result.changes 
    });
  } catch (error) {
    console.error('Error deleting grocery item by name:', error);
    res.status(500).json({ error: 'Failed to delete grocery item' });
  }
});

module.exports = router;
