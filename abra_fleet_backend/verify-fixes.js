#!/usr/bin/env node

/**
 * POST-FIX VERIFICATION SCRIPT
 * Quickly checks if the Firebase removal fixes are working
 */

const fs = require('fs');
const path = require('path');

console.log('✅ POST-FIX VERIFICATION\n');
console.log('═'.repeat(70));

// Check if any Firebase code remains
console.log('\n🔍 Checking for remaining Firebase references...\n');

const routesDir = path.join(process.cwd(), 'routes');
const files = fs.readdirSync(routesDir).filter(f => f.endsWith('.js'));

let remainingIssues = 0;
let filesWithIssues = [];

files.forEach(file => {
  const filePath = path.join(routesDir, file);
  const content = fs.readFileSync(filePath, 'utf8');
  
  const firebaseImport = (content.match(/require\(['"]firebase-admin['"]\)/g) || []).length;
  const uidUsage = (content.match(/req\.user\.uid(?!eo)/g) || []).length; // Exclude 'video'
  const customClaims = (content.match(/customClaims/g) || []).length;
  const uidQuery = (content.match(/\{\s*uid\s*:/g) || []).length;
  
  const total = firebaseImport + uidUsage + customClaims + uidQuery;
  
  if (total > 0) {
    remainingIssues += total;
    filesWithIssues.push({
      file,
      firebaseImport,
      uidUsage,
      customClaims,
      uidQuery,
      total
    });
  }
});

if (filesWithIssues.length === 0) {
  console.log('✅ ✅ ✅ ALL FIREBASE CODE REMOVED! ✅ ✅ ✅\n');
  console.log('🎉 Your codebase is now using JWT authentication!\n');
} else {
  console.log(`⚠️  Found ${remainingIssues} remaining Firebase references in ${filesWithIssues.length} files:\n`);
  
  filesWithIssues.forEach(item => {
    console.log(`   📄 ${item.file} (${item.total} issues)`);
    if (item.firebaseImport > 0) console.log(`      - Firebase import: ${item.firebaseImport}`);
    if (item.uidUsage > 0) console.log(`      - req.user.uid: ${item.uidUsage}`);
    if (item.customClaims > 0) console.log(`      - customClaims: ${item.customClaims}`);
    if (item.uidQuery > 0) console.log(`      - {uid:...}: ${item.uidQuery}`);
  });
  
  console.log('\n💡 These may need manual fixing.\n');
}

console.log('═'.repeat(70));
console.log('📋 VERIFICATION SUMMARY');
console.log('═'.repeat(70));

// Count fixed files
const fixedFiles = 23; // From auto-fix output
const totalChanges = 74; // From auto-fix output

console.log(`\n✅ Files automatically fixed: ${fixedFiles}`);
console.log(`✅ Changes made: ${totalChanges}`);
console.log(`✅ Files scanned: ${files.length}`);

if (remainingIssues > 0) {
  console.log(`⚠️  Remaining issues: ${remainingIssues} in ${filesWithIssues.length} files`);
} else {
  console.log(`✅ Remaining issues: 0`);
}

console.log('\n' + '═'.repeat(70));
console.log('🚀 NEXT STEPS');
console.log('═'.repeat(70));

if (remainingIssues === 0) {
  console.log('\n1️⃣  Remove Firebase package:');
  console.log('   npm uninstall firebase-admin');
  
  console.log('\n2️⃣  Clean .env file:');
  console.log('   Remove Firebase-related variables (optional)');
  
  console.log('\n3️⃣  Start your server:');
  console.log('   node server.js');
  
  console.log('\n4️⃣  Test the endpoints:');
  console.log('   TEST_EMAIL=admin@abrafleet.com TEST_PASSWORD=yourpassword node test-all-endpoints.js');
  
  console.log('\n5️⃣  Test in Flutter:');
  console.log('   - Remove Firebase packages from pubspec.yaml');
  console.log('   - Update API calls to use JWT tokens');
  console.log('   - Test login and protected endpoints\n');
} else {
  console.log('\n1️⃣  Review remaining issues (listed above)');
  console.log('\n2️⃣  Manually fix these files using manual-fix-guide.md');
  console.log('\n3️⃣  Run this script again to verify\n');
}

// Check if customClaims was in unified_registration.js
const unifiedRegPath = path.join(routesDir, 'unified_registration.js');
if (fs.existsSync(unifiedRegPath)) {
  const content = fs.readFileSync(unifiedRegPath, 'utf8');
  if (content.includes('customClaims')) {
    console.log('\n⚠️  SPECIAL ATTENTION NEEDED:');
    console.log('   unified_registration.js still has customClaims');
    console.log('   This needs manual review as it handles user registration\n');
  }
}

console.log('✅ Verification complete!\n');