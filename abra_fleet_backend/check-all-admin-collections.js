// Check for admin users in all collections
require('dotenv').config();
const mongoose = require('mongoose');

async function checkAllAdminCollections() {
  try {
    console.log('\n🔍 Checking for admin users in all collections...');
    console.log('─'.repeat(80));
    
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB');
    
    // Check users collection
    console.log('\n📋 USERS COLLECTION:');
    const users = await mongoose.connection.db.collection('users').find({ 
      $or: [
        { role: 'admin' },
        { role: 'super_admin' },
        { role: 'superAdmin' },
        { email: 'admin@abrafleet.com' }
      ]
    }).toArray();
    
    console.log(`Found ${users.length} admin users:`);
    users.forEach(user => {
      console.log(`\n   Email: ${user.email}`);
      console.log(`   Name: ${user.name}`);
      console.log(`   Role: ${user.role}`);
      console.log(`   Firebase UID: ${user.firebaseUid}`);
      console.log(`   Organization: ${user.organizationId}`);
    });
    
    // Check admin_users collection
    console.log('\n📋 ADMIN_USERS COLLECTION:');
    const adminUsers = await mongoose.connection.db.collection('admin_users').find({}).toArray();
    
    console.log(`Found ${adminUsers.length} admin users:`);
    adminUsers.forEach(user => {
      console.log(`\n   Email: ${user.email}`);
      console.log(`   Name: ${user.name}`);
      console.log(`   Role: ${user.role}`);
      console.log(`   Firebase UID: ${user.firebaseUid}`);
      console.log(`   Organization: ${user.organizationId}`);
      console.log(`   Modules: ${JSON.stringify(user.modules)}`);
      console.log(`   Permissions: ${JSON.stringify(user.permissions)}`);
    });
    
    console.log('\n─'.repeat(80) + '\n');
    
    await mongoose.disconnect();
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

checkAllAdminCollections();