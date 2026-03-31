const mongoose = require('mongoose');
require('dotenv').config();
const AdminUser = require('../models/AdminUser');

async function deleteAdmin() {
  try {
    console.log('🔄 Connecting to MongoDB...');
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected');

    // Delete existing admin
    const result = await AdminUser.deleteOne({ email: 'admin@abrafleet.com' });
    
    if (result.deletedCount > 0) {
      console.log('✅ Deleted existing admin user');
    } else {
      console.log('⚠️  No admin user found to delete');
    }
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

deleteAdmin();