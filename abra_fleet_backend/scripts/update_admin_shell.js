const fs = require('fs');
const path = require('path');

// Path to admin_main_shell.dart
const adminShellPath = path.join(__dirname, '../../abra_fleet/lib/features/admin/shell/admin_main_shell.dart');

console.log('🔧 Starting admin_main_shell.dart update...\n');

// Check if file exists
if (!fs.existsSync(adminShellPath)) {
  console.error('❌ File not found:', adminShellPath);
  console.error('Please verify the path is correct.');
  process.exit(1);
}

// Read the file
let content = fs.readFileSync(adminShellPath, 'utf8');
console.log('✅ File loaded successfully\n');

// Backup original file
const backupPath = adminShellPath + '.backup';
fs.writeFileSync(backupPath, content);
console.log('✅ Backup created:', backupPath, '\n');

let changeCount = 0;

// Change 1: Comment out RoleNavigationService import
console.log('🔄 Change 1: Commenting out RoleNavigationService import...');
const importPattern = /import 'package:abra_fleet\/core\/services\/role_navigation_service\.dart';/g;
if (importPattern.test(content)) {
  content = content.replace(
    importPattern,
    "// Role navigation handled by backend permissions\n// import 'package:abra_fleet/core/services/role_navigation_service.dart';"
  );
  changeCount++;
  console.log('   ✅ Import commented out\n');
} else {
  console.log('   ⚠️  Import not found (might already be updated)\n');
}

// Change 2: Update _setupSOSListener
console.log('🔄 Change 2: Updating _setupSOSListener...');
const sosListenerPattern = /void _setupSOSListener\(\) \{[\s\S]*?if \(!RoleNavigationService\.canSeeNotification\(_userRole, 'sos_alerts'\)\) \{[\s\S]*?return;[\s\S]*?\}/m;
if (sosListenerPattern.test(content)) {
  content = content.replace(
    sosListenerPattern,
    `void _setupSOSListener() {
    // Super admin and admin can see all notifications
    if (_userRole != 'super_admin' && _userRole != 'admin') {
      debugPrint('🔐 User role \$_userRole cannot see SOS alerts');
      return;
    }`
  );
  changeCount++;
  console.log('   ✅ _setupSOSListener updated\n');
} else {
  console.log('   ⚠️  Pattern not found (might already be updated)\n');
}

// Change 3: Update _setupRosterListener
console.log('🔄 Change 3: Updating _setupRosterListener...');
const rosterListenerPattern = /void _setupRosterListener\(\) \{[\s\S]*?if \(!RoleNavigationService\.canSeeNotification\(_userRole, 'pending_rosters'\)\) \{[\s\S]*?return;[\s\S]*?\}/m;
if (rosterListenerPattern.test(content)) {
  content = content.replace(
    rosterListenerPattern,
    `void _setupRosterListener() {
    // Super admin and admin can see all notifications
    if (_userRole != 'super_admin' && _userRole != 'admin') {
      debugPrint('🔐 User role \$_userRole cannot see roster notifications');
      return;
    }`
  );
  changeCount++;
  console.log('   ✅ _setupRosterListener updated\n');
} else {
  console.log('   ⚠️  Pattern not found (might already be updated)\n');
}

// Change 4: Update _setupDocumentExpiryListener
console.log('🔄 Change 4: Updating _setupDocumentExpiryListener...');
const docExpiryPattern = /void _setupDocumentExpiryListener\(\) \{[\s\S]*?if \(!RoleNavigationService\.canSeeNotification\(_userRole, 'document_expiry'\)\) \{[\s\S]*?return;[\s\S]*?\}/m;
if (docExpiryPattern.test(content)) {
  content = content.replace(
    docExpiryPattern,
    `void _setupDocumentExpiryListener() {
  // Super admin and admin can see all notifications
  if (_userRole != 'super_admin' && _userRole != 'admin') {
    debugPrint('🔐 User role \$_userRole cannot see document expiry notifications');
    return;
  }`
  );
  changeCount++;
  console.log('   ✅ _setupDocumentExpiryListener updated\n');
} else {
  console.log('   ⚠️  Pattern not found (might already be updated)\n');
}

// Change 5: Update _setupTripNotificationListener
console.log('🔄 Change 5: Updating _setupTripNotificationListener...');
const tripNotifPattern = /void _setupTripNotificationListener\(\) \{[\s\S]*?if \(!RoleNavigationService\.canSeeNotification\(_userRole, 'trip_responses'\)\) \{[\s\S]*?return;[\s\S]*?\}/m;
if (tripNotifPattern.test(content)) {
  content = content.replace(
    tripNotifPattern,
    `void _setupTripNotificationListener() {
    // Super admin and admin can see all notifications
    if (_userRole != 'super_admin' && _userRole != 'admin') {
      debugPrint('🔐 User role \$_userRole cannot see trip notifications');
      return;
    }`
  );
  changeCount++;
  console.log('   ✅ _setupTripNotificationListener updated\n');
} else {
  console.log('   ⚠️  Pattern not found (might already be updated)\n');
}

// Save the updated file
fs.writeFileSync(adminShellPath, content);

console.log('═'.repeat(60));
console.log('✅ UPDATE COMPLETE!');
console.log('═'.repeat(60));
console.log(`📊 Total changes made: ${changeCount}`);
console.log(`📁 Updated file: ${adminShellPath}`);
console.log(`📁 Backup file: ${backupPath}`);
console.log('═'.repeat(60));
console.log('\n🎯 Next Steps:');
console.log('1. Hot restart Flutter app (press R)');
console.log('2. Test navigation and permissions');
console.log('3. If anything breaks, restore from backup:');
console.log(`   cp ${backupPath} ${adminShellPath}`);
console.log('');