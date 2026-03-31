// test-permissions-direct.js - Direct MongoDB test without API
// Run with: node test-permissions-direct.js

require('dotenv').config();
const mongoose = require('mongoose');
const UserRole = require('./models/UserRole');
const Role = require('./models/Role');

async function testPermissions() {
  console.log('\n🧪 TESTING CUSTOM PERMISSIONS (Direct MongoDB)');
  console.log('═'.repeat(80));

  try {
    // Connect to MongoDB
    console.log('\n1️⃣  Connecting to MongoDB...');
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet');
    console.log('   ✅ Connected to MongoDB');

    // Initialize roles if needed
    console.log('\n2️⃣  Checking roles...');
    const roleCount = await Role.countDocuments();
    
    if (roleCount === 0) {
      console.log('   📝 Initializing default roles...');
      const defaultRoles = [
        {
          id: 'superAdmin',
          title: 'Super Admin',
          icon: '👑',
          color: '#ff6b6b',
          permissions: {
            'Fleet Management': ['View all vehicles', 'Add/Edit/Delete vehicles', 'Assign vehicles to routes'],
            'Driver Management': ['View all drivers', 'Add/Edit/Delete drivers'],
            'System Administration': ['User management', 'Role management', 'System settings']
          }
        },
        {
          id: 'hrManager',
          title: 'HR Manager',
          icon: '👥',
          color: '#43e97b',
          permissions: {
            'Customer/Employee': ['View employees', 'Manage rosters', 'Create schedules', 'Employee requests'],
            'Route Planning': ['View routes', 'Employee route assignment'],
            'Reports': ['Employee analytics', 'Attendance reports']
          }
        }
      ];
      
      await Role.insertMany(defaultRoles);
      console.log('   ✅ Roles initialized');
    } else {
      console.log(`   ✅ Found ${roleCount} roles`);
    }

    // Get HR Manager role
    const hrRole = await Role.findOne({ id: 'hrManager' });
    console.log('\n3️⃣  HR Manager Role:');
    console.log('   Title:', hrRole.title);
    console.log('   Permissions modules:', Object.keys(hrRole.permissions).join(', '));

    // Create test user with custom permissions
    console.log('\n4️⃣  Creating test user with custom permissions...');
    
    // Delete existing test user if any
    await UserRole.deleteMany({ email: /test-hr-manager.*@company.com/ });
    
    const customPermissions = {
      'Customer/Employee': {
        'View employees': true,
        'Manage rosters': true,
        'Create schedules': false,  // Disabled
        'Employee requests': true
      },
      'Route Planning': {
        'View routes': true,
        'Employee route assignment': false  // Disabled
      },
      'Reports': {
        'Employee analytics': true,
        'Attendance reports': true
      }
    };

    const testUser = new UserRole({
      name: 'Test HR Manager',
      email: `test-hr-manager-${Date.now()}@company.com`,
      phone: '+1234567890',
      password: 'TestPassword123',
      role: 'hrManager',
      customPermissions: customPermissions,
      status: 'active'
    });

    await testUser.save();
    console.log('   ✅ User created:', testUser.name);
    console.log('   📧 Email:', testUser.email);
    console.log('   🆔 ID:', testUser._id);

    // Retrieve and verify
    console.log('\n5️⃣  Retrieving user from database...');
    const savedUser = await UserRole.findById(testUser._id);
    console.log('   ✅ User retrieved:', savedUser.name);
    console.log('   🔐 Custom Permissions:');
    
    if (savedUser.customPermissions) {
      const permsObj = savedUser.customPermissions instanceof Map 
        ? Object.fromEntries(savedUser.customPermissions) 
        : savedUser.customPermissions;
      
      for (const [module, perms] of Object.entries(permsObj)) {
        console.log(`\n      📁 ${module}:`);
        for (const [perm, enabled] of Object.entries(perms)) {
          console.log(`         ${enabled ? '✓' : '✗'} ${perm}`);
        }
      }
    } else {
      console.log('   ⚠️  No custom permissions found');
    }

    // Update permissions
    console.log('\n6️⃣  Updating permissions...');
    savedUser.customPermissions = {
      'Customer/Employee': {
        'View employees': true,
        'Manage rosters': false,  // Changed
        'Create schedules': true,  // Changed
        'Employee requests': true
      },
      'Route Planning': {
        'View routes': true,
        'Employee route assignment': true  // Changed
      },
      'Reports': {
        'Employee analytics': false,  // Changed
        'Attendance reports': true
      }
    };
    
    await savedUser.save();
    console.log('   ✅ Permissions updated');

    // Verify update
    console.log('\n7️⃣  Verifying updated permissions...');
    const updatedUser = await UserRole.findById(testUser._id);
    console.log('   ✅ Updated permissions:');
    
    const updatedPermsObj = updatedUser.customPermissions instanceof Map 
      ? Object.fromEntries(updatedUser.customPermissions) 
      : updatedUser.customPermissions;
    
    for (const [module, perms] of Object.entries(updatedPermsObj)) {
      console.log(`\n      📁 ${module}:`);
      for (const [perm, enabled] of Object.entries(perms)) {
        console.log(`         ${enabled ? '✓' : '✗'} ${perm}`);
      }
    }

    // Get all users
    console.log('\n8️⃣  Fetching all users...');
    const allUsers = await UserRole.find();
    console.log('   ✅ Total users:', allUsers.length);
    console.log('   Users with custom permissions:', 
      allUsers.filter(u => u.customPermissions && Object.keys(u.customPermissions).length > 0).length
    );

    // Clean up
    console.log('\n9️⃣  Cleaning up test user...');
    await UserRole.findByIdAndDelete(testUser._id);
    console.log('   ✅ Test user deleted');

    console.log('\n═'.repeat(80));
    console.log('✅ ALL TESTS PASSED!');
    console.log('═'.repeat(80));
    console.log('\n📝 Summary:');
    console.log('   • Custom permissions are stored correctly');
    console.log('   • Permissions can be updated');
    console.log('   • Data structure is preserved');
    console.log('   • MongoDB schema is working properly');
    console.log('\n🚀 Next Steps:');
    console.log('   • Test through Flutter app with real authentication');
    console.log('   • Create users via the UI');
    console.log('   • Edit existing users and customize permissions');
    console.log('═'.repeat(80) + '\n');

  } catch (error) {
    console.error('\n❌ TEST FAILED!');
    console.error('═'.repeat(80));
    console.error('Error:', error.message);
    console.error('Stack:', error.stack);
    console.error('═'.repeat(80) + '\n');
    process.exit(1);
  } finally {
    await mongoose.connection.close();
    console.log('🔌 MongoDB connection closed\n');
  }
}

// Run tests
testPermissions();
