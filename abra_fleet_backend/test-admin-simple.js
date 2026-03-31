// Simple test to check admin user in database
require('dotenv').config();
const mongoose = require('mongoose');

async function testAdminSimple() {
  try {
    console.log('\n🧪 Testing admin user in database...');
    console.log('─'.repeat(80));
    
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB');
    
    // Check admin_users collection
    const adminUser = await mongoose.connection.db.collection('admin_users').findOne({ 
      email: 'admin@abrafleet.com' 
    });
    
    if (adminUser) {
      console.log('✅ Admin user found in admin_users collection:');
      console.log('   Email:', adminUser.email);
      console.log('   Role:', adminUser.role);
      console.log('   Firebase UID:', adminUser.firebaseUid);
      console.log('   Modules:', adminUser.modules);
    } else {
      console.log('❌ Admin user not found in admin_users collection');
    }
    
    // Check users collection
    const user = await mongoose.connection.db.collection('users').findOne({ 
      email: 'admin@abrafleet.com' 
    });
    
    if (user) {
      console.log('\n✅ Admin user found in users collection:');
      console.log('   Email:', user.email);
      console.log('   Role:', user.role);
      console.log('   Firebase UID:', user.firebaseUid);
    } else {
      console.log('\n❌ Admin user not found in users collection');
    }
    
    console.log('\n─'.repeat(80) + '\n');
    
    await mongoose.disconnect();
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

testAdminSimple();