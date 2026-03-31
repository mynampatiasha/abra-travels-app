// Script to remove firebase-admin imports from route files
const fs = require('fs');
const path = require('path');

const routeFiles = [
  'routes/notification_router.js',
  'routes/customer_approval_router.js',
  'routes/admin_recent_activities.js',
  'routes/client_router.js',
  'routes/admin-customers-unified.js',
  'routes/admin-clients-unified.js',
  'routes/account-settings.js'
];

routeFiles.forEach(file => {
  const filePath = path.join(__dirname, file);
  
  try {
    let content = fs.readFileSync(filePath, 'utf8');
    
    // Remove firebase-admin import line
    const originalContent = content;
    content = content.replace(/const admin = require\(['"]firebase-admin['"]\);?\n?/g, '');
    
    if (content !== originalContent) {
      fs.writeFileSync(filePath, content, 'utf8');
      console.log(`✅ Removed firebase-admin import from ${file}`);
    } else {
      console.log(`⏭️  No firebase-admin import found in ${file}`);
    }
  } catch (error) {
    console.error(`❌ Error processing ${file}:`, error.message);
  }
});

console.log('\n✅ Firebase-admin imports removed from route files');
