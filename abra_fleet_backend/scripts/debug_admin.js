const mongoose = require('mongoose');
require('dotenv').config();
const AdminUser = require('../models/AdminUser');

async function debugAdmin() {
  try {
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected\n');

    const admin = await AdminUser.findOne({ email: 'admin@abrafleet.com' });
    
    if (!admin) {
      console.log('❌ Admin not found!');
      process.exit(1);
    }

    console.log('📧 Email:', admin.email);
    console.log('👑 Role:', admin.role);
    console.log('✅ Active:', admin.isActive);
    console.log('🔐 Permissions type:', typeof admin.permissions);
    console.log('🔐 Permissions instanceof Map:', admin.permissions instanceof Map);
    console.log('🔐 Permissions keys:', admin.permissions instanceof Map 
      ? Array.from(admin.permissions.keys()).slice(0, 5)
      : Object.keys(admin.permissions || {}).slice(0, 5)
    );
    
    console.log('\n🧪 Testing hasPermission method:');
    try {
      const result = admin.hasPermission('fleet');
      console.log('   fleet:', result);
    } catch (err) {
      console.log('   ❌ Error:', err.message);
    }
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

debugAdmin();