// fix-duplicate-admin.js
// Fix duplicate admin users in MongoDB

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

async function fixDuplicateAdmin() {
  try {
    console.log('🔧 Fixing Duplicate Admin Users...\n');

    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    const adminEmail = 'admin@abrafleet.com';

    // Find all admin users
    const adminUsers = await User.find({ email: adminEmail });
    console.log(`📧 Found ${adminUsers.length} admin users with email: ${adminEmail}\n`);

    adminUsers.forEach((user, index) => {
      console.log(`Admin User ${index + 1}:`);
      console.log(`   🆔 MongoDB ID: ${user._id}`);
      console.log(`   🔥 Firebase UID: ${user.firebaseUid}`);
      console.log(`   🔑 Role: ${user.role}`);
      console.log(`   👤 Name: ${user.name}`);
      console.log(`   📅 Created: ${user.createdAt}`);
      console.log('');
    });

    if (adminUsers.length > 1) {
      console.log('🔄 Removing duplicate admin users...\n');

      // Keep the one with super_admin role, or the most recent one
      let keepUser = adminUsers.find(user => user.role === 'super_admin');
      if (!keepUser) {
        // If no super_admin, keep the most recent one
        keepUser = adminUsers.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))[0];
      }

      console.log('✅ Keeping this admin user:');
      console.log(`   🆔 MongoDB ID: ${keepUser._id}`);
      console.log(`   🔥 Firebase UID: ${keepUser.firebaseUid}`);
      console.log(`   🔑 Role: ${keepUser.role}`);

      // Remove all other admin users
      const usersToRemove = adminUsers.filter(user => user._id.toString() !== keepUser._id.toString());
      
      for (const userToRemove of usersToRemove) {
        console.log(`❌ Removing duplicate: ${userToRemove._id} (${userToRemove.role})`);
        await User.findByIdAndDelete(userToRemove._id);
      }

      // Ensure the kept user has super_admin role
      if (keepUser.role !== 'super_admin') {
        console.log('🔄 Updating role to super_admin...');
        await User.findByIdAndUpdate(keepUser._id, {
          role: 'super_admin',
          name: 'Super Admin',
          updatedAt: new Date()
        });
      }

      console.log('\n✅ Duplicates removed successfully!');
    } else if (adminUsers.length === 1) {
      console.log('✅ Only one admin user found - no duplicates to remove');
      
      // Ensure it has the correct role
      const adminUser = adminUsers[0];
      if (adminUser.role !== 'super_admin') {
        console.log('🔄 Updating role to super_admin...');
        await User.findByIdAndUpdate(adminUser._id, {
          role: 'super_admin',
          name: 'Super Admin',
          updatedAt: new Date()
        });
      }
    } else {
      console.log('❌ No admin users found!');
    }

    // Final verification
    const finalAdmin = await User.findOne({ email: adminEmail });
    if (finalAdmin) {
      console.log('\n═══════════════════════════════════════════════════════');
      console.log('🎉 FINAL ADMIN USER:');
      console.log('═══════════════════════════════════════════════════════');
      console.log('📧 Email:        ', finalAdmin.email);
      console.log('👤 Name:         ', finalAdmin.name);
      console.log('🔑 Role:         ', finalAdmin.role);
      console.log('🔥 Firebase UID: ', finalAdmin.firebaseUid);
      console.log('🆔 MongoDB ID:   ', finalAdmin._id);
      console.log('📅 Updated:      ', finalAdmin.updatedAt);
      console.log('═══════════════════════════════════════════════════════');
    }

    await mongoose.connection.close();
    console.log('\n✅ Fix completed successfully!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error fixing duplicate admin:', error);
    await mongoose.connection.close();
    process.exit(1);
  }
}

fixDuplicateAdmin();