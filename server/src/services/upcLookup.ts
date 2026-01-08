import https from 'https';

export interface UPCLookupResult {
	found: boolean;
	upc: string;
	name?: string;
	brand?: string | null;
	description?: string | null;
	image_url?: string | null;
	category?: string | null;
	requiresCustomProduct?: boolean;
	reason?: string;
}

interface OpenFoodFactsProduct {
	product_name?: string;
	product_name_en?: string;
	brands?: string;
	generic_name?: string;
	ingredients_text?: string;
	image_url?: string;
	image_front_url?: string;
	categories_tags?: string[];
}

interface OpenFoodFactsResponse {
	status: number;
	product?: OpenFoodFactsProduct;
}

// Open Food Facts API - free, no API key required
export async function lookupUPC(upc: string): Promise<UPCLookupResult> {
	return new Promise((resolve, reject) => {
		const url = `https://world.openfoodfacts.org/api/v0/product/${upc}.json`;

		const options = {
			headers: {
				'User-Agent': 'PantryPal/1.0 (subasically@gmail.com) - iOS App'
			}
		};

		https.get(url, options, (res) => {
			let data = '';

			res.on('data', chunk => {
				data += chunk;
			});

			res.on('end', () => {
				try {
					const json = JSON.parse(data) as OpenFoodFactsResponse;

					if (json.status === 1 && json.product) {
						const product = json.product;
						const name = product.product_name || product.product_name_en || null;

						// If no name found, treat as not found
						if (!name || name.trim() === '') {
							resolve({
								found: false,
								upc: upc,
								requiresCustomProduct: true,
								reason: 'Product exists but has no name'
							});
							return;
						}

						resolve({
							found: true,
							upc: upc,
							name: name,
							brand: product.brands || null,
							description: product.generic_name || product.ingredients_text || null,
							image_url: product.image_url || product.image_front_url || null,
							category: product.categories_tags?.[0]?.replace('en:', '') || null
						});
					} else {
						resolve({ found: false, upc: upc });
					}
				} catch (e) {
					reject(new Error('Failed to parse UPC response'));
				}
			});
		}).on('error', (err) => {
			reject(err);
		});
	});
}
