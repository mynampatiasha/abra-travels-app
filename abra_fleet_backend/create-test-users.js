// Create test users in UserRole collection
require('dotenv').config();
const mongoose = require('mongoose');
const UserRole = require('./models/UserRole');

const testUsers = [
  {
    name: 'Admin User',
    email: 'admin@abrafleet.com',
    phone: '+91 9876543210',
    password: 'admin123',
    role: 'superAdmin',
    status: 'active',
    customPermissions: {
      'Fleet Management': {
        'View all vehicles': true,
        'Add/Edit/Delete vehicles': true,
        'Assign vehicles to routes': true,
        'Vehicle maintenance': true,
        'Fleet analytics': true
      },
      'Driver Management': {
        'View all drivers': true,
        'Add/Edit/Delete drivers': true,
        'Manage driver documents': true,
        'Driver performance reports': true
      }
    }
  },
  {
    name: 'Fleet Manager',
    email: 'fleet@abrafleet.com',
    phone: '+91 9876543211',
    password: 'fleet123',
    role: 'fleetManager',
    status: 'active',
    customPermissions: {
      'Fleet Management': {
        'View vehicles': true,
        'Add/Edit vehicles': true,
        'Vehicle maintenance': true,
        'Fleet reports': true
      },
      'Driver Management': {
        'View drivers': true,
        'Assign drivers': true,
        'Driver performance': true
      }
    }
  },
  {
    name: 'Operations Manager',
    email: 'operations@abrafleet.com',
    phone: '+91 9876543212',
    password: 'ops123',
    role: 'operations',
    status: 'active',
    customPermissions: {
      'Route Planning': {
        'View routes': true,
        'Create routes': true,
        'Modify routes': true,
        'Trip scheduling': true
      },
      'Real-Time Tracking': {
        'Live tracking': true,
        'Trip monitoring': true,
        'Delay management': true
      }
    }
  }
];

async function createTestUsers() {
  try {
    console.log('\n🔧 Creating test users in UserRole collection...');
    console.log('═'.repeat(80));
    
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB');
    
    // Delete existing users
    const deleteResult = await UserRole.deleteMany({});
    console.log(`🗑️  Deleted ${deleteResult.deletedCount} existing users`);
    
    // Insert test users
    const insertResult = await UserRole.insertMany(testUsers);
    console.log(`✅ Inserted ${insertResult.length} test users`);
    
    console.log('\n📋 Users Created:');
    insertResult.forEach(user => {
      console.log(`\n   Name: ${user.name}`);
      console.log(`   Email: ${user.email}`);
      console.log(`   Role: ${user.role}`);
      console.log(`   Status: ${user.status}`);
      console.log(`   Custom Permissions: ${user.customPermissions ? 'Yes' : 'No'}`);
    });
    
    console.log('\n✅ Test users creation complete!');
    console.log('═'.repeat(80) + '\n');
    
    await mongoose.disconnect();
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Error creating test users:', error.message);
    console.error('Stack:', error.stack);
    console.error('═'.repeat(80) + '\n');
    process.exit(1);
  }
}

createTestUsers();