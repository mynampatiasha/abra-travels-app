// debug-admin-login.js
// Debug script to check admin user login details

require('dotenv').config();
const mongoose = require('mongoose');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

const userSchema = new mongoose.Schema({
  firebaseUid: String,
  email: String,
  name: String,
  role: String,
  phone: String,
  organizationId: String,
  createdAt: Date,
  updatedAt: Date,
});

const User = mongoose.model('User', userSchema);

async function debugAdminLogin() {
  try {
    console.log('🔍 Debugging Admin Login...\n');

    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    const adminEmail = 'admin@abrafleet.com';

    // Find the admin user
    const adminUser = await User.findOne({ email: adminEmail });

    if (adminUser) {
      console.log('✅ Admin User Found:');
      console.log('═══════════════════════════════════════════════════════');
      console.log('📧 Email:        ', adminUser.email);
      console.log('👤 Name:         ', adminUser.name);
      console.log('🔑 Role:         ', adminUser.role);
      console.log('🔑 Role Type:    ', typeof adminUser.role);
      console.log('🔑 Role Length:  ', adminUser.role?.length);
      console.log('🆔 MongoDB ID:   ', adminUser._id);
      console.log('🔥 Firebase UID: ', adminUser.firebaseUid);
      console.log('📱 Phone:        ', adminUser.phone);
      console.log('🏢 Org ID:       ', adminUser.organizationId);
      console.log('📅 Created:      ', adminUser.createdAt);
      console.log('📅 Updated:      ', adminUser.updatedAt);
      console.log('═══════════════════════════════════════════════════════');

      // Test role normalization
      const normalizedRole = adminUser.role?.toLowerCase().replaceAll(' ', '_');
      console.log('\n🔧 Role Processing:');
      console.log('   Original Role: "' + adminUser.role + '"');
      console.log('   Normalized:    "' + normalizedRole + '"');
      console.log('   Expected:      "super_admin"');
      console.log('   Match:         ', normalizedRole === 'super_admin');

      // Test navigation permissions
      const roleNavigationMap = {
        'super_admin': [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25],
        'hr_manager': [0, 3, 7, 17, 18, 19, 20, 21],
        'fleet_manager': [0, 1, 2, 6, 7, 12, 13, 14, 15, 16],
        'finance': [0, 4, 7, 22, 23, 24],
      };

      const allowedIndices = roleNavigationMap[normalizedRole] || [];
      console.log('\n🎯 Navigation Permissions:');
      console.log('   Allowed Sections: ', allowedIndices.length);
      console.log('   Full Access:      ', allowedIndices.length === 26);

    } else {
      console.log('❌ Admin user not found!');
    }

    await mongoose.connection.close();
    process.exit(0);
  } catch (error) {
    console.error('❌ Error debugging admin login:', error);
    await mongoose.connection.close();
    process.exit(1);
  }
}

debugAdminLogin();