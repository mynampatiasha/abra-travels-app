// test-role-navigation.js
// Test script to verify role-based navigation permissions

require('dotenv').config();
const mongoose = require('mongoose');

// MongoDB Connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

// User Schema
const userSchema = new mongoose.Schema({
  firebaseUid: String,
  email: String,
  name: String,
  role: String,
  phone: String,
  organizationId: String,
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now },
});

const User = mongoose.model('User', userSchema);

// Role-based navigation permissions (matching Flutter service)
const roleNavigationMap = {
  'super_admin': [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25],
  'hr_manager': [0, 3, 7, 17, 18, 19, 20, 21],
  'fleet_manager': [0, 1, 2, 6, 7, 12, 13, 14, 15, 16],
  'finance': [0, 4, 7, 22, 23, 24],
};

const navigationNames = {
  0: 'Dashboard',
  1: 'Vehicle Dashboard',
  2: 'Drivers',
  3: 'Customer Management',
  4: 'Client Management',
  5: 'Maintenance',
  6: 'Fleet Map View',
  7: 'Reports',
  8: 'Resolved Alerts',
  9: 'Incomplete Alerts',
  10: 'Settings',
  11: 'Profile',
  12: 'Vehicle Master',
  13: 'Trip Operation',
  14: 'Maintenance Management',
  15: 'Vehicle Reports',
  16: 'Compliance Management',
  17: 'All Customers',
  18: 'Pending Approvals',
  19: 'Pending Rosters',
  20: 'Approved Rosters',
  21: 'Trip Cancellation',
  22: 'Client Details',
  23: 'Billing & Invoices',
  24: 'Trips',
  25: 'Role Access Control',
};

async function testRoleNavigation() {
  try {
    console.log('🧪 Testing Role-Based Navigation Permissions...\n');

    // Connect to MongoDB
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    // Test each role
    for (const [role, allowedIndices] of Object.entries(roleNavigationMap)) {
      console.log(`\n🔐 Testing Role: ${role.toUpperCase().replace('_', ' ')}`);
      console.log('═'.repeat(50));
      
      console.log('✅ ALLOWED NAVIGATION:');
      allowedIndices.forEach(index => {
        console.log(`   ${index.toString().padStart(2)}: ${navigationNames[index]}`);
      });
      
      console.log('\n❌ RESTRICTED NAVIGATION:');
      const restrictedIndices = Object.keys(navigationNames)
        .map(Number)
        .filter(index => !allowedIndices.includes(index));
      
      if (restrictedIndices.length === 0) {
        console.log('   None (Full Access)');
      } else {
        restrictedIndices.forEach(index => {
          console.log(`   ${index.toString().padStart(2)}: ${navigationNames[index]}`);
        });
      }
      
      console.log(`\n📊 Access Summary: ${allowedIndices.length}/${Object.keys(navigationNames).length} sections allowed`);
    }

    // Check if super admin exists
    console.log('\n\n🔍 Checking Super Admin User...');
    console.log('═'.repeat(50));
    
    const superAdmin = await User.findOne({ email: 'admin@abrafleet.com' });
    if (superAdmin) {
      console.log('✅ Super Admin Found:');
      console.log(`   📧 Email: ${superAdmin.email}`);
      console.log(`   👤 Name: ${superAdmin.name}`);
      console.log(`   🔑 Role: ${superAdmin.role}`);
      console.log(`   🆔 ID: ${superAdmin._id}`);
      console.log(`   🔥 Firebase UID: ${superAdmin.firebaseUid}`);
      
      // Test super admin permissions
      const superAdminPermissions = roleNavigationMap[superAdmin.role] || [];
      console.log(`   🎯 Navigation Access: ${superAdminPermissions.length}/${Object.keys(navigationNames).length} sections`);
    } else {
      console.log('❌ Super Admin not found!');
      console.log('   Run: node create-super-admin.js');
    }

    await mongoose.connection.close();
    console.log('\n✅ Test completed successfully!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error testing role navigation:', error);
    await mongoose.connection.close();
    process.exit(1);
  }
}

// Run the test
testRoleNavigation();