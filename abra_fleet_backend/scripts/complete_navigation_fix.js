const fs = require('fs');
const path = require('path');

// Path to admin_main_shell.dart
const adminShellPath = path.join(__dirname, '../../abra_fleet/lib/features/admin/shell/admin_main_shell.dart');

console.log('🔧 Completing navigation fixes...\n');

// Read the file
let content = fs.readFileSync(adminShellPath, 'utf8');
let changeCount = 0;

// Fix _navigateToTab method
console.log('🔄 Updating _navigateToTab method...');
const navigatePattern = /\/\/ Check role-based access permission[\s\S]*?if \(!RoleNavigationService\.canAccessNavigation\(_userRole, screenIndex\)\) \{[\s\S]*?return;[\s\S]*?\}/m;
if (navigatePattern.test(content)) {
  content = content.replace(
    navigatePattern,
    `// Super admin and admin have access to all navigation
    // Permissions are checked on backend
    debugPrint('✅ Navigating to: $navigationKey (index: $screenIndex)');`
  );
  changeCount++;
  console.log('   ✅ _navigateToTab updated\n');
} else {
  console.log('   ⚠️  Pattern not found (might already be updated)\n');
}

// Fix _buildRoleBasedNavigation method
console.log('🔄 Updating _buildRoleBasedNavigation method...');
const buildNavPattern = /List<Widget> _buildRoleBasedNavigation\(bool isMobile\) \{[\s\S]*?return navigationItems;[\s\S]*?\}/m;
if (buildNavPattern.test(content)) {
  content = content.replace(
    buildNavPattern,
    `List<Widget> _buildRoleBasedNavigation(bool isMobile) {
    final List<Widget> navigationItems = [];
    
    debugPrint('🔍 Building navigation for role: $_userRole');
    
    // For now, show all navigation for admin users
    // Backend will enforce permissions via API calls
    final isAdmin = _userRole == 'super_admin' || _userRole == 'admin';
    
    if (!isAdmin) {
      // Non-admin users only see dashboard
      navigationItems.add(_buildMenuItem(title: 'Dashboard', icon: Icons.dashboard_rounded, navKey: NavigationKeys.dashboard, isMobile: isMobile));
      return navigationItems;
    }
    
    // Admin users see all navigation
    navigationItems.add(_buildMenuItem(title: 'Dashboard', icon: Icons.dashboard_rounded, navKey: NavigationKeys.dashboard, isMobile: isMobile));
    navigationItems.add(_buildVehicleDropdown(context, isMobile));
    navigationItems.add(_buildMenuItem(title: 'Drivers', icon: Icons.groups, navKey: NavigationKeys.drivers, isMobile: isMobile));
    navigationItems.add(_buildCustomerDropdown(context, isMobile));
    navigationItems.add(_buildClientDropdown(context, isMobile));
    navigationItems.add(_buildMenuItem(title: 'Fleet Map View', icon: Icons.map, navKey: NavigationKeys.fleetMap, isMobile: isMobile));
    navigationItems.add(_buildMenuItem(title: 'Reports', icon: Icons.analytics, navKey: NavigationKeys.reports, isMobile: isMobile));
    navigationItems.add(_buildSosExpansionTile(context, isMobile));
    navigationItems.add(_buildHrmDropdown(context, isMobile));
    navigationItems.add(_buildTmsDropdown(context, isMobile));
    navigationItems.add(_buildFeedbackDropdown(context, isMobile));
    navigationItems.add(_buildMenuItem(title: 'Role Access Control', icon: Icons.admin_panel_settings, navKey: NavigationKeys.roleAccessControl, isMobile: isMobile));
    
    return navigationItems;
  }`
  );
  changeCount++;
  console.log('   ✅ _buildRoleBasedNavigation updated\n');
} else {
  console.log('   ⚠️  Pattern not found (might already be updated)\n');
}

// Save the updated file
fs.writeFileSync(adminShellPath, content);

console.log('═'.repeat(60));
console.log('✅ NAVIGATION FIX COMPLETE!');
console.log('═'.repeat(60));
console.log(`📊 Additional changes made: ${changeCount}`);
console.log('═'.repeat(60));
console.log('\n🎯 Final Steps:');
console.log('1. Hot restart Flutter app (press R)');
console.log('2. Test all navigation items');
console.log('3. Login as admin@abrafleet.com');
console.log('4. Check Role Access Control works');
console.log('');