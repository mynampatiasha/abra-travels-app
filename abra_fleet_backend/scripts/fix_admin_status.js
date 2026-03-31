const mongoose = require('mongoose');
require('dotenv').config();
const AdminUser = require('../models/AdminUser');

async function fixAdminStatus() {
  try {
    console.log('🔧 Fixing Admin User Status and Permissions...');
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    // Find the admin user
    const admin = await AdminUser.findOne({ email: 'admin@abrafleet.com' });
    
    if (!admin) {
      console.log('❌ Admin user not found!');
      console.log('   Run: node scripts/create_test_admin.js');
      process.exit(1);
    }

    console.log('📧 Found admin:', admin.email);
    console.log('👑 Current role:', admin.role);
    console.log('✅ Current status:', admin.isActive);
    
    // Fix 1: Ensure user is active
    admin.isActive = true;
    
    // Fix 2: Ensure role is correct
    admin.role = 'super_admin';
    
    // Fix 3: Fix permissions - ensure they are proper boolean values
    console.log('\n🔐 Fixing permissions...');
    
    // Clear existing permissions and set new ones with proper types
    admin.permissions = new Map();
    
    const allPermissions = [
      'dashboard',
      'fleet_management',
      'fleet_vehicles',
      'fleet_drivers',
      'fleet_trips',
      'fleet_gps_tracking',
      'fleet_maintenance',
      'fleet_list',
      'customer_fleet',
      'all_customers',
      'pending_approvals',
      'pending_rosters',
      'approved_rosters',
      'trip_cancellation',
      'abra_global_trading',
      'abra_food_works',
      'client_details',
      'billing_invoices',
      'trips',
      'reports',
      'sos_alerts',
      'incomplete_alerts',
      'resolved_alerts',
      'hrm_feedback',
      'hrm_employees',
      'hrm_departments',
      'hrm_leave_requests',
      'notice_board',
      'attendance',
      'feedback',
      'customer_feedback',
      'driver_feedback',
      'client_feedback',
      'role_access_control',
    ];

    // Set all permissions with proper boolean values
    allPermissions.forEach(key => {
      admin.permissions.set(key, {
        can_access: true,  // Boolean, not string
        edit_delete: true  // Boolean, not string
      });
    });

    console.log('   Set', allPermissions.length, 'permissions with boolean values');
    
    // Save the admin user
    await admin.save();
    
    console.log('\n✅ ADMIN USER FIXED!');
    console.log('─'.repeat(60));
    console.log('📧 Email: admin@abrafleet.com');
    console.log('👑 Role: super_admin');
    console.log('✅ Status: Active (true)');
    console.log('🔐 Permissions: ALL with boolean values');
    console.log('─'.repeat(60));
    
    // Verify the fix
    console.log('\n🧪 Verifying fix...');
    const verifyAdmin = await AdminUser.findOne({ email: 'admin@abrafleet.com' });
    
    console.log('   Email:', verifyAdmin.email);
    console.log('   Role:', verifyAdmin.role);
    console.log('   Active:', verifyAdmin.isActive, '(type:', typeof verifyAdmin.isActive, ')');
    console.log('   Permissions count:', verifyAdmin.permissions.size);
    
    // Test a few permissions
    const testKeys = ['dashboard', 'role_access_control', 'fleet_vehicles'];
    testKeys.forEach(key => {
      const perm = verifyAdmin.permissions.get(key);
      if (perm) {
        console.log(`   ${key}:`, {
          can_access: perm.can_access, 
          type: typeof perm.can_access
        });
      }
    });
    
    console.log('\n🎉 Admin user is now properly configured!');
    process.exit(0);
    
  } catch (error) {
    console.error('\n❌ Fix failed:', error.message);
    console.error(error.stack);
    process.exit(1);
  }
}

fixAdminStatus();