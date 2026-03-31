// update-admin-role.js
// Update existing admin user to super_admin role

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

async function updateAdminRole() {
  try {
    console.log('🔄 Updating Admin Role to Super Admin...\n');

    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    const adminEmail = 'admin@abrafleet.com';

    // Find and update the admin user
    const updatedUser = await User.findOneAndUpdate(
      { email: adminEmail },
      { 
        role: 'super_admin',
        updatedAt: new Date()
      },
      { new: true }
    );

    if (updatedUser) {
      console.log('✅ Admin role updated successfully!\n');
      console.log('═══════════════════════════════════════════════════════');
      console.log('📧 Email:    ', updatedUser.email);
      console.log('👤 Name:     ', updatedUser.name);
      console.log('🔑 Old Role: ', 'admin');
      console.log('🔐 New Role: ', updatedUser.role);
      console.log('🆔 MongoDB ID:', updatedUser._id);
      console.log('═══════════════════════════════════════════════════════');
      console.log('\n✅ Super Admin is now ready with full access!');
    } else {
      console.log('❌ Admin user not found');
    }

    await mongoose.connection.close();
    process.exit(0);
  } catch (error) {
    console.error('❌ Error updating admin role:', error);
    await mongoose.connection.close();
    process.exit(1);
  }
}

updateAdminRole();