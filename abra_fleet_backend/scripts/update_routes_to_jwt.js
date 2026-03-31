// scripts/update_routes_to_jwt.js - Update all backend routes to use JWT instead of Firebase
const fs = require('fs');
const path = require('path');

console.log('🔄 UPDATING ALL BACKEND ROUTES TO USE JWT INSTEAD OF FIREBASE');
console.log('─'.repeat(80));

// List of files to update
const filesToUpdate = [
  'routes/user_management_router.js',
  'routes/trip_creation_router.js', 
  'routes/tms.js',
  'routes/route_optimization_router.js',
  'routes/roster_router.js'
];

// Replacement patterns
const replacements = [
  // Replace req.user.uid with req.user.userId
  {
    pattern: /req\.user\.uid/g,
    replacement: 'req.user.userId'
  },
  // Replace Firebase UID references in comments
  {
    pattern: /Firebase UID/g,
    replacement: 'User ID'
  },
  // Replace firebaseUid field references
  {
    pattern: /firebaseUid: req\.user\.userId/g,
    replacement: '_id: new ObjectId(req.user.userId)'
  },
  // Replace firebaseUid in queries
  {
    pattern: /{ firebaseUid: req\.user\.userId }/g,
    replacement: '{ _id: new ObjectId(req.user.userId) }'
  },
  // Replace firebaseUid in $or queries
  {
    pattern: /{ firebaseUid: req\.user\.userId },/g,
    replacement: '{ _id: new ObjectId(req.user.userId) },'
  }
];

let totalUpdates = 0;

filesToUpdate.forEach(filePath => {
  const fullPath = path.join(__dirname, '..', filePath);
  
  if (!fs.existsSync(fullPath)) {
    console.log(`⚠️  File not found: ${filePath}`);
    return;
  }
  
  console.log(`\n📝 Processing: ${filePath}`);
  
  let content = fs.readFileSync(fullPath, 'utf8');
  let fileUpdates = 0;
  
  replacements.forEach(({ pattern, replacement }) => {
    const matches = content.match(pattern);
    if (matches) {
      content = content.replace(pattern, replacement);
      fileUpdates += matches.length;
      console.log(`   ✅ Replaced ${matches.length} occurrences of: ${pattern.source}`);
    }
  });
  
  if (fileUpdates > 0) {
    // Add ObjectId import if not present and needed
    if (content.includes('new ObjectId(') && !content.includes('const { ObjectId }')) {
      const mongoImportRegex = /const.*require\(['"]mongodb['"]\)/;
      if (mongoImportRegex.test(content)) {
        content = content.replace(mongoImportRegex, (match) => {
          if (match.includes('ObjectId')) {
            return match;
          }
          return match.replace('require(\'mongodb\')', 'require(\'mongodb\'); const { ObjectId } = require(\'mongodb\')');
        });
      } else {
        // Add ObjectId import at the top
        const lines = content.split('\n');
        let insertIndex = 0;
        for (let i = 0; i < lines.length; i++) {
          if (lines[i].includes('require(') && !lines[i].includes('//')) {
            insertIndex = i + 1;
            break;
          }
        }
        lines.splice(insertIndex, 0, 'const { ObjectId } = require(\'mongodb\');');
        content = lines.join('\n');
        console.log('   ✅ Added ObjectId import');
      }
    }
    
    fs.writeFileSync(fullPath, content);
    console.log(`   ✅ Updated ${fileUpdates} references in ${filePath}`);
    totalUpdates += fileUpdates;
  } else {
    console.log(`   ℹ️  No updates needed for ${filePath}`);
  }
});

console.log('\n' + '─'.repeat(80));
console.log(`✅ ROUTE UPDATE COMPLETE`);
console.log(`   Total files processed: ${filesToUpdate.length}`);
console.log(`   Total updates made: ${totalUpdates}`);
console.log('─'.repeat(80));

if (totalUpdates > 0) {
  console.log('\n⚠️  IMPORTANT NOTES:');
  console.log('1. Review the updated files to ensure all changes are correct');
  console.log('2. Test all affected routes after the updates');
  console.log('3. Some complex queries may need manual adjustment');
  console.log('4. Restart the backend server to apply changes');
}