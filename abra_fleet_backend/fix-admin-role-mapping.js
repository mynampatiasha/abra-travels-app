// Fix admin role mapping between MongoDB and Flutter
require('dotenv').config();
const mongoose = require('mongoose');

async function fixAdminRoleMapping() {
  try {
    console.log('\n🔧 Fixing admin role mapping...');
    console.log('─'.repeat(80));
    
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB');
    
    // Update admin_users collection to use super_admin instead of superAdmin
    const adminUsersResult = await mongoose.connection.db.collection('admin_users').updateMany(
      { role: 'superAdmin' },
      { $set: { role: 'super_admin' } }
    );
    
    console.log(`✅ Updated ${adminUsersResult.modifiedCount} admin_users records`);
    
    // Update users collection to use super_admin instead of admin for admin@abrafleet.com
    const usersResult = await mongoose.connection.db.collection('users').updateMany(
      { 
        email: 'admin@abrafleet.com',
        role: 'admin'
      },
      { $set: { role: 'super_admin' } }
    );
    
    console.log(`✅ Updated ${usersResult.modifiedCount} users records`);
    
    // Verify the changes
    console.log('\n📋 Verification:');
    
    const adminUser = await mongoose.connection.db.collection('admin_users').findOne({ 
      email: 'admin@abrafleet.com' 
    });
    
    if (adminUser) {
      console.log(`   admin_users role: ${adminUser.role}`);
    }
    
    const user = await mongoose.connection.db.collection('users').findOne({ 
      email: 'admin@abrafleet.com' 
    });
    
    if (user) {
      console.log(`   users role: ${user.role}`);
    }
    
    console.log('\n─'.repeat(80) + '\n');
    
    await mongoose.disconnect();
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

fixAdminRoleMapping();