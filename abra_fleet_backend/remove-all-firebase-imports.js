// Script to remove ALL firebase-admin imports from route files
const fs = require('fs');
const path = require('path');

const routesDir = path.join(__dirname, 'routes');

// Get all .js files in routes directory
const files = fs.readdirSync(routesDir).filter(file => file.endsWith('.js'));

let removedCount = 0;
let skippedCount = 0;

files.forEach(file => {
  const filePath = path.join(routesDir, file);
  
  try {
    let content = fs.readFileSync(filePath, 'utf8');
    
    // Remove firebase-admin import line
    const originalContent = content;
    content = content.replace(/const admin = require\(['"]firebase-admin['"]\);?\n?/g, '');
    content = content.replace(/const admin = require\(['"]firebase-admin['"]\);?\r?\n?/g, '');
    
    if (content !== originalContent) {
      fs.writeFileSync(filePath, content, 'utf8');
      console.log(`✅ Removed firebase-admin from routes/${file}`);
      removedCount++;
    } else {
      skippedCount++;
    }
  } catch (error) {
    console.error(`❌ Error processing routes/${file}:`, error.message);
  }
});

console.log(`\n📊 Summary:`);
console.log(`   ✅ Removed: ${removedCount} files`);
console.log(`   ⏭️  Skipped: ${skippedCount} files`);
console.log(`\n✅ Firebase-admin imports removed from all route files`);
