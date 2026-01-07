/**
 * Jest global teardown
 * Runs once after all tests
 */

const fs = require('fs');
const path = require('path');

module.exports = async () => {
    console.log('\n🧹 Cleaning up test artifacts...\n');
    
    // Clean up tmp directory
    const tmpDir = path.join(__dirname, '../../tmp');
    if (fs.existsSync(tmpDir)) {
        const files = fs.readdirSync(tmpDir);
        for (const file of files) {
            try {
                fs.unlinkSync(path.join(tmpDir, file));
            } catch (error) {
                console.error(`Failed to delete ${file}:`, error.message);
            }
        }
        console.log(`✅ Cleaned up ${files.length} temporary files`);
    }
    
    console.log('✨ Test suite complete!\n');
};
