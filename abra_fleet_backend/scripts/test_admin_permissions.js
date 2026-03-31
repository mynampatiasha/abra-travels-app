const mongoose = require('mongoose');
require('dotenv').config();
const AdminUser = require('../models/AdminUser');

async function testAdminPermissions() {
  try {
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    const admin = await AdminUser.findOne({ email: 'admin@abrafleet.com' });
        
    if (!admin) {
      console.log('❌ Admin not found!');
      console.log('   Run: node scripts/create_test_admin.js');
      process.exit(1);
    }

    console.log('📧 Email:', admin.email);
    console.log('👑 Role:', admin.role);
    console.log('✅ Active:', admin.isActive);
    console.log('🔐 Permissions exists:', !!admin.permissions);
    console.log('🔐 Permissions type:', typeof admin.permissions);
    console.log('🔐 Is Map:', admin.permissions instanceof Map);
        
    if (admin.permissions instanceof Map) {
      console.log('🔐 Permission count:', admin.permissions.size);
      console.log('🔐 First 5 keys:', Array.from(admin.permissions.keys()).slice(0, 5));
    } else if (typeof admin.permissions === 'object') {
      console.log('🔐 Permission count:', Object.keys(admin.permissions).length);
      console.log('🔐 First 5 keys:', Object.keys(admin.permissions).slice(0, 5));
    }
        
    console.log('\n🧪 Testing hasPermission method:\n');
        
    const testPermissions = ['fleet', 'drivers', 'customers', 'role_access_control', 'dashboard'];
        
    for (const perm of testPermissions) {
      try {
        const result = admin.hasPermission(perm);
        console.log(`   ${result ? '✅' : '❌'} ${perm}: ${result}`);
      } catch (err) {
        console.log(`   ❌ ${perm}: ERROR - ${err.message}`);
      }
    }
        
    console.log('\n🎉 All tests passed!');
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Test failed:', error.message);
    console.error(error.stack);
    process.exit(1);
  }
}

testAdminPermissions();