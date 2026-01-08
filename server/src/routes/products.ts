import express, { Request, Response, Router } from 'express';
import authenticateToken from '../middleware/auth';
import * as productService from '../services/productService';

const router: Router = express.Router();

interface AuthenticatedRequest extends Request {
	user: {
		id: string;
		email: string;
		householdId: string;
	};
}

// All routes require authentication
router.use(authenticateToken);

// Lookup product by UPC
router.get('/lookup/:upc', async (req: AuthenticatedRequest, res: Response) => {
	try {
		const { upc } = req.params;
		console.log(`🔍 [Products] UPC lookup request: ${upc}`);
		console.log(`   - User ID: ${req.user.id}`);
		console.log(`   - Household ID: ${req.user.householdId}`);

		const result = await productService.lookupProductByUPC(upc, req.user.householdId);

		console.log(`✅ [Products] UPC lookup result for ${upc}:`);
		console.log(`   - Product found: ${result.product !== null}`);
		if (result.product) {
			console.log(`   - Product ID: ${result.product.id}`);
			console.log(`   - Product name: ${result.product.name}`);
			console.log(`   - Product brand: ${result.product.brand || 'null'}`);
		}

		res.json(result);
	} catch (error) {
		console.error('❌ [Products] UPC lookup error:', error);
		res.status(500).json({ error: 'UPC lookup failed' });
	}
});

// Create custom product
router.post('/', (req: AuthenticatedRequest, res: Response) => {
	try {
		const { upc, name, brand, description, category } = req.body;
		const result = productService.createCustomProduct(req.user.householdId, {
			upc,
			name,
			brand,
			description,
			category
		});
		const status = result.wasUpdated ? 200 : 201;
		res.status(status).json(result.product);
	} catch (error) {
		console.error('Create product error:', error);
		const err = error as Error;
		if (err.message === 'Product name is required') {
			return res.status(400).json({ error: err.message });
		}
		res.status(500).json({ error: 'Failed to create product' });
	}
});

// Get all products for household
router.get('/', (req: AuthenticatedRequest, res: Response) => {
	try {
		const products = productService.getAllProducts(req.user.householdId);
		res.json(products);
	} catch (error) {
		console.error('Get products error:', error);
		res.status(500).json({ error: 'Failed to get products' });
	}
});

// Get single product by ID
router.get('/:id', (req: AuthenticatedRequest, res: Response) => {
	try {
		const product = productService.getProductById(req.params.id);
		res.json(product);
	} catch (error) {
		console.error('Get product error:', error);
		const err = error as Error;
		if (err.message === 'Product not found') {
			return res.status(404).json({ error: err.message });
		}
		res.status(500).json({ error: 'Failed to get product' });
	}
});

// Update product
router.put('/:id', (req: AuthenticatedRequest, res: Response) => {
	try {
		const { name, brand, description, category } = req.body;
		const updatedProduct = productService.updateProduct(req.user.householdId, req.params.id, {
			name,
			brand,
			description,
			category
		});
		res.json(updatedProduct);
	} catch (error) {
		console.error('Update product error:', error);
		const err = error as Error;
		if (err.message === 'Product not found') {
			return res.status(404).json({ error: err.message });
		}
		res.status(500).json({ error: 'Failed to update product' });
	}
});

// Delete product
router.delete('/:id', (req: AuthenticatedRequest, res: Response) => {
	try {
		productService.deleteProduct(req.user.householdId, req.params.id);
		res.json({ success: true });
	} catch (error) {
		console.error('Delete product error:', error);
		const err = error as Error;
		if (err.message === 'Product not found') {
			return res.status(404).json({ error: err.message });
		}
		if (err.message === 'Cannot delete product that is in inventory') {
			return res.status(400).json({ error: err.message });
		}
		res.status(500).json({ error: 'Failed to delete product' });
	}
});

export default router;
