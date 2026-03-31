const mongoose = require('mongoose');
require('dotenv').config();
const AdminUser = require('../models/AdminUser');

async function createTestAdmin() {
  try {
    console.log('🔄 Connecting to MongoDB...');
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected');

    // Check if admin exists
    let admin = await AdminUser.findOne({ email: 'admin@abrafleet.com' });
    
    if (admin) {
      console.log('⚠️  Admin already exists. Updating permissions...');
    } else {
      console.log('📦 Creating new admin...');
      admin = new AdminUser({
        name_parson: 'Super Admin',
        name: 'admin',
        email: 'admin@abrafleet.com',
        phone: '+91 9876543210',
        pwd: 'Admin123!',
        role: 'super_admin',
        isActive: true,
      });
    }
    
    // Grant ALL permissions
    admin.grantSuperAdminPermissions();
    await admin.save();
    
    console.log('\n✅ ADMIN SETUP COMPLETE!');
    console.log('─'.repeat(60));
    console.log('📧 Email: admin@abrafleet.com');
    console.log('🔑 Password: Admin123!');
    console.log('👑 Role: super_admin');
    console.log('✅ Status: Active');
    console.log('🔐 Permissions: ALL');
    console.log('─'.repeat(60));
    console.log('\n🎉 You can now login and create users!\n');
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

createTestAdmin();