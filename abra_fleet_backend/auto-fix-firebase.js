#!/usr/bin/env node

/**
 * AUTOMATED FIREBASE TO JWT MIGRATION SCRIPT
 * 
 * This script will automatically fix the most common Firebase → JWT issues
 * across all your route files.
 * 
 * Usage: node auto-fix-firebase.js
 */

const fs = require('fs');
const path = require('path');

console.log('🔧 AUTOMATED FIREBASE → JWT FIX SCRIPT\n');
console.log('═'.repeat(70));

let totalFilesFixed = 0;
let totalChanges = 0;
const changeLog = [];

// Backup directory
const backupDir = path.join(process.cwd(), 'routes_backup_before_firebase_removal');

function createBackup() {
  console.log('\n📦 Creating backup of route files...');
  
  if (!fs.existsSync(backupDir)) {
    fs.mkdirSync(backupDir, { recursive: true });
  }
  
  const routesDir = path.join(process.cwd(), 'routes');
  const files = fs.readdirSync(routesDir).filter(f => f.endsWith('.js'));
  
  files.forEach(file => {
    const src = path.join(routesDir, file);
    const dest = path.join(backupDir, file);
    fs.copyFileSync(src, dest);
  });
  
  console.log(`✅ Backed up ${files.length} files to: ${backupDir}\n`);
}

function fixFile(filePath, fileName) {
  let content = fs.readFileSync(filePath, 'utf8');
  const originalContent = content;
  let changesInFile = 0;
  
  // Fix 1: Replace req.user.uid with req.user.email (most common)
  const uidMatches = content.match(/req\.user\.uid/g);
  if (uidMatches) {
    content = content.replace(/req\.user\.uid/g, 'req.user.email');
    changesInFile += uidMatches.length;
    changeLog.push({
      file: fileName,
      type: 'req.user.uid → req.user.email',
      count: uidMatches.length
    });
  }
  
  // Fix 2: Replace { uid: ... } in database queries with { email: ... }
  // Pattern: { uid: req.user.uid } or { uid: userId } etc.
  const uidQueryPattern = /\{\s*uid\s*:\s*([^}]+)\}/g;
  const uidQueryMatches = content.match(uidQueryPattern);
  if (uidQueryMatches) {
    content = content.replace(uidQueryPattern, (match, capture) => {
      // If it was req.user.uid, it's now req.user.email, so change field to email
      if (capture.includes('req.user')) {
        return `{ email: ${capture} }`;
      }
      // Otherwise, keep the variable name but change field to email
      return `{ email: ${capture} }`;
    });
    changesInFile += uidQueryMatches.length;
    changeLog.push({
      file: fileName,
      type: '{ uid: ... } → { email: ... }',
      count: uidQueryMatches.length
    });
  }
  
  // Fix 3: Replace driverUid with driverEmail in queries
  const driverUidPattern = /driverUid\s*:\s*req\.user\.email/g;
  if (driverUidPattern.test(content)) {
    content = content.replace(/driverUid\s*:/g, 'driverEmail:');
    changesInFile += 1;
    changeLog.push({
      file: fileName,
      type: 'driverUid → driverEmail',
      count: 1
    });
  }
  
  // Fix 4: Replace customClaims?.role with just role
  const customClaimsPattern = /req\.user\.customClaims\?\.role/g;
  const customClaimsMatches = content.match(customClaimsPattern);
  if (customClaimsMatches) {
    content = content.replace(customClaimsPattern, 'req.user.role');
    changesInFile += customClaimsMatches.length;
    changeLog.push({
      file: fileName,
      type: 'customClaims?.role → role',
      count: customClaimsMatches.length
    });
  }
  
  // Fix 5: Replace Firebase admin import (if exists)
  const firebaseImportPattern = /const\s+admin\s*=\s*require\(['"]firebase-admin['"]\);?\n?/g;
  if (firebaseImportPattern.test(content)) {
    content = content.replace(firebaseImportPattern, '// Firebase removed - using JWT authentication\n');
    changesInFile += 1;
    changeLog.push({
      file: fileName,
      type: 'Removed firebase-admin import',
      count: 1
    });
  }
  
  // Fix 6: Add .toLowerCase() to email comparisons
  // Pattern: email: req.user.email (without toLowerCase)
  const emailPattern = /email\s*:\s*req\.user\.email(?!\s*\.toLowerCase)/g;
  const emailMatches = content.match(emailPattern);
  if (emailMatches) {
    content = content.replace(emailPattern, 'email: req.user.email.toLowerCase()');
    changesInFile += emailMatches.length;
    changeLog.push({
      file: fileName,
      type: 'Added .toLowerCase() to email',
      count: emailMatches.length
    });
  }
  
  // Only write if changes were made
  if (content !== originalContent) {
    fs.writeFileSync(filePath, content, 'utf8');
    totalFilesFixed++;
    totalChanges += changesInFile;
    return true;
  }
  
  return false;
}

function processAllFiles() {
  console.log('🔄 Processing route files...\n');
  
  const routesDir = path.join(process.cwd(), 'routes');
  const files = fs.readdirSync(routesDir).filter(f => f.endsWith('.js'));
  
  // Files that definitely need fixing based on diagnostic
  const priorityFiles = [
    'driver-trips.js',
    'real_time_fleet_router.js',
    'customer_approval_router.js',
    'enhanced-customer.js',
    'admin-drivers.js',
    'admin-vehicles.js',
    'document_router.js',
    'assignment_routes.js',
    'driver-dashboard.js',
    'driver-documents.js',
    'gps_tracking_router.js',
    'maintenance_router.js',
    'multi_trip_routes.js',
    'driver-route-details.js',
    'enhanced-client.js',
    'hrm_departments.js',
    'hrm_employees.js',
    'live_tracking_routes.js',
    'unified_registration.js',
    'admin-users.js',
    'fcm_token_management.js',
    'notification_router.js'
  ];
  
  // Process priority files first
  priorityFiles.forEach(file => {
    const filePath = path.join(routesDir, file);
    if (fs.existsSync(filePath)) {
      const fixed = fixFile(filePath, file);
      if (fixed) {
        console.log(`✅ Fixed: ${file}`);
      }
    }
  });
  
  // Process remaining files
  files.forEach(file => {
    if (!priorityFiles.includes(file)) {
      const filePath = path.join(routesDir, file);
      const fixed = fixFile(filePath, file);
      if (fixed) {
        console.log(`✅ Fixed: ${file}`);
      }
    }
  });
}

function showSummary() {
  console.log('\n' + '═'.repeat(70));
  console.log('📊 SUMMARY OF CHANGES');
  console.log('═'.repeat(70));
  
  console.log(`\n✅ Files modified: ${totalFilesFixed}`);
  console.log(`✅ Total changes: ${totalChanges}\n`);
  
  // Group changes by type
  const changesByType = {};
  changeLog.forEach(change => {
    if (!changesByType[change.type]) {
      changesByType[change.type] = 0;
    }
    changesByType[change.type] += change.count;
  });
  
  console.log('Changes by type:');
  Object.entries(changesByType).forEach(([type, count]) => {
    console.log(`   ${type}: ${count}`);
  });
  
  console.log('\n' + '═'.repeat(70));
  console.log('🎯 NEXT STEPS');
  console.log('═'.repeat(70));
  console.log('\n1️⃣  Review the changes:');
  console.log('   - Original files backed up to: routes_backup_before_firebase_removal/');
  console.log('   - Check git diff to see what changed');
  
  console.log('\n2️⃣  Manual fixes still needed:');
  console.log('   - Check files for any complex Firebase logic not auto-fixed');
  console.log('   - Update database collections to use email field if needed');
  
  console.log('\n3️⃣  Test the endpoints:');
  console.log('   - Start your server: node server.js');
  console.log('   - Run tests: node test-all-endpoints.js');
  
  console.log('\n4️⃣  If something breaks:');
  console.log('   - Restore from backup: cp routes_backup_before_firebase_removal/* routes/');
  console.log('   - Apply fixes manually with more care\n');
}

// Main execution
console.log('⚠️  WARNING: This will modify your route files!');
console.log('   Backups will be created in: routes_backup_before_firebase_removal/\n');

// Create backup first
createBackup();

// Process files
processAllFiles();

// Show summary
showSummary();

console.log('✅ Auto-fix complete!\n');