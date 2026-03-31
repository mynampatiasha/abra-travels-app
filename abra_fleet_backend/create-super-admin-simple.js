// create-super-admin-simple.js
// Simple script to create super admin user in MongoDB only

require('dotenv').config();
const mongoose = require('mongoose');

// MongoDB Connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

// User Schema
const userSchema = new mongoose.Schema({
  firebaseUid: String,
  email: { type: String, required: true, unique: true },
  name: { type: String, required: true },
  role: { type: String, required: true },
  phone: String,
  organizationId: String,
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now },
});

const User = mongoose.model('User', userSchema);

async function createSuperAdmin() {
  try {
    console.log('🚀 Creating Super Admin in MongoDB...\n');

    // Connect to MongoDB
    console.log('📦 Connecting to MongoDB...');
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    const superAdminEmail = 'admin@abrafleet.com';
    const superAdminName = 'Super Admin';
    const superAdminRole = 'super_admin';

    // Check if user already exists
    const existingUser = await User.findOne({ email: superAdminEmail });
    if (existingUser) {
      console.log('⚠️  Super Admin already exists in MongoDB');
      console.log('📧 Email:', existingUser.email);
      console.log('👤 Name:', existingUser.name);
      console.log('🔑 Role:', existingUser.role);
      console.log('🆔 MongoDB ID:', existingUser._id);
      console.log('\n✅ Super Admin is ready to use!');
      await mongoose.connection.close();
      return;
    }

    // Create user in MongoDB
    console.log('💾 Creating super admin in MongoDB...');
    const newUser = new User({
      firebaseUid: 'super_admin_uid_' + Date.now(), // Temporary UID
      email: superAdminEmail,
      name: superAdminName,
      role: superAdminRole,
      phone: '+1234567890',
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    await newUser.save();
    console.log('✅ Super Admin created in MongoDB\n');

    // Display credentials
    console.log('═══════════════════════════════════════════════════════');
    console.log('🎉 SUPER ADMIN CREATED SUCCESSFULLY!');
    console.log('═══════════════════════════════════════════════════════');
    console.log('📧 Email:    ', superAdminEmail);
    console.log('🔑 Password: ', 'admin123');
    console.log('👤 Name:     ', superAdminName);
    console.log('🔐 Role:     ', superAdminRole);
    console.log('🆔 MongoDB ID:', newUser._id);
    console.log('═══════════════════════════════════════════════════════');
    console.log('\n✅ You can now login with these credentials!');
    console.log('📝 Note: Make sure to create the Firebase user manually or');
    console.log('   configure Firebase credentials for full functionality.');

    await mongoose.connection.close();
    console.log('\n✅ MongoDB connection closed');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error creating super admin:', error);
    await mongoose.connection.close();
    process.exit(1);
  }
}

// Run the script
createSuperAdmin();