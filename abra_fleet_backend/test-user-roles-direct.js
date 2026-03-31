// Test the user-roles endpoint directly
require('dotenv').config();
const mongoose = require('mongoose');
const UserRole = require('./models/UserRole');

async function testUserRolesEndpoint() {
  try {
    console.log('\n🧪 TESTING USER-ROLES ENDPOINT DIRECTLY');
    console.log('═'.repeat(80));
    
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB');
    
    // Test the UserRole model directly
    console.log('\n1️⃣  Testing UserRole.find()...');
    const users = await UserRole.find().sort({ createdAt: -1 });
    console.log(`   Found ${users.length} users in UserRole collection`);
    
    users.forEach((user, index) => {
      console.log(`\n   User ${index + 1}:`);
      console.log(`      ID: ${user._id}`);
      console.log(`      Name: ${user.name}`);
      console.log(`      Email: ${user.email}`);
      console.log(`      Role: ${user.role}`);
      console.log(`      Status: ${user.status}`);
      console.log(`      Custom Permissions: ${user.customPermissions ? 'Yes' : 'No'}`);
    });
    
    console.log('\n═'.repeat(80));
    console.log('✅ TEST COMPLETED!');
    console.log('═'.repeat(80) + '\n');
    
    await mongoose.disconnect();
    process.exit(0);
  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    console.error('Stack:', error.stack);
    console.error('═'.repeat(80) + '\n');
    process.exit(1);
  }
}

testUserRolesEndpoint();