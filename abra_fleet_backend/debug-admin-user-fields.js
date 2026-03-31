const mongoose = require('mongoose');
require('dotenv').config();

async function debugAdminUser() {
  try {
    console.log('🔍 Debugging Admin User Fields...');
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    // Check using raw MongoDB
    const db = mongoose.connection.db;
    const rawUser = await db.collection('admin_users').findOne({ 
      email: 'admin@abrafleet.com' 
    });
    
    if (rawUser) {
      console.log('📄 Raw MongoDB Document:');
      console.log('   _id:', rawUser._id);
      console.log('   email:', rawUser.email);
      console.log('   role:', rawUser.role);
      console.log('   isActive:', rawUser.isActive, '(type:', typeof rawUser.isActive, ')');
      console.log('   status:', rawUser.status, '(type:', typeof rawUser.status, ')');
      console.log('   name:', rawUser.name);
      console.log('   permissions type:', typeof rawUser.permissions);
      console.log('   permissions keys:', Object.keys(rawUser.permissions || {}).slice(0, 5));
    } else {
      console.log('❌ No user found in admin_users collection');
    }
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Debug failed:', error.message);
    process.exit(1);
  }
}

debugAdminUser();