const https = require('https');

// Open Food Facts API - free, no API key required
async function lookupUPC(upc) {
    return new Promise((resolve, reject) => {
        const url = `https://world.openfoodfacts.org/api/v0/product/${upc}.json`;
        
        https.get(url, (res) => {
            let data = '';
            
            res.on('data', chunk => {
                data += chunk;
            });
            
            res.on('end', () => {
                try {
                    const json = JSON.parse(data);
                    
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

module.exports = { lookupUPC };
