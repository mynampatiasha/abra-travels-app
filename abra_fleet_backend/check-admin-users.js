// Check for admin users in the system
require('dotenv').config();
const mongoose = require('mongoose');

async function checkAdminUsers() {
  try {
    console.log('\n🔍 Checking for admin users...');
    console.log('─'.repeat(80));
    
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB');
    
    // Check users collection
    const users = await mongoose.connection.db.collection('users').find({ role: 'admin' }).toArray();
    
    console.log(`\n📋 Found ${users.length} admin users:`);
    users.forEach(user => {
      console.log(`\n   Email: ${user.email}`);
      console.log(`   Name: ${user.name}`);
      console.log(`   Role: ${user.role}`);
      console.log(`   Firebase UID: ${user.firebaseUid}`);
    });
    
    console.log('\n─'.repeat(80) + '\n');
    
    await mongoose.disconnect();
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

checkAdminUsers();
