// create-super-admin.js
// Script to create super admin user in MongoDB

require('dotenv').config();
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
const admin = require('firebase-admin');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    }),
  });
}

// MongoDB Connection
const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

// User Schema
const userSchema = new mongoose.Schema({
  firebaseUid: { type: String, required: true, unique: true },
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
    console.log('🚀 Starting Super Admin Creation...\n');

    // Connect to MongoDB
    console.log('📦 Connecting to MongoDB...');
    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    const superAdminEmail = 'admin@abrafleet.com';
    const superAdminPassword = 'admin123';
    const superAdminName = 'Super Admin';
    const superAdminRole = 'super_admin';

    // Check if user already exists in MongoDB
    const existingUser = await User.findOne({ email: superAdminEmail });
    if (existingUser) {
      console.log('⚠️  Super Admin already exists in MongoDB');
      console.log('📧 Email:', existingUser.email);
      console.log('👤 Name:', existingUser.name);
      console.log('🔑 Role:', existingUser.role);
      console.log('🆔 Firebase UID:', existingUser.firebaseUid);
      console.log('\n✅ Super Admin is ready to use!');
      await mongoose.connection.close();
      return;
    }

    // Create user in Firebase Auth
    console.log('🔥 Creating user in Firebase Auth...');
    let firebaseUser;
    try {
      firebaseUser = await admin.auth().getUserByEmail(superAdminEmail);
      console.log('✅ Firebase user already exists');
    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        firebaseUser = await admin.auth().createUser({
          email: superAdminEmail,
          password: superAdminPassword,
          displayName: superAdminName,
          emailVerified: true,
        });
        console.log('✅ Firebase user created');
      } else {
        throw error;
      }
    }

    // Create user in MongoDB
    console.log('💾 Creating user in MongoDB...');
    const newUser = new User({
      firebaseUid: firebaseUser.uid,
      email: superAdminEmail,
      name: superAdminName,
      role: superAdminRole,
      phone: '+1234567890',
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    await newUser.save();
    console.log('✅ User created in MongoDB\n');

    // Display credentials
    console.log('═══════════════════════════════════════════════════════');
    console.log('🎉 SUPER ADMIN CREATED SUCCESSFULLY!');
    console.log('═══════════════════════════════════════════════════════');
    console.log('📧 Email:    ', superAdminEmail);
    console.log('🔑 Password: ', superAdminPassword);
    console.log('👤 Name:     ', superAdminName);
    console.log('🔐 Role:     ', superAdminRole);
    console.log('🆔 MongoDB ID:', newUser._id);
    console.log('🔥 Firebase UID:', firebaseUser.uid);
    console.log('═══════════════════════════════════════════════════════');
    console.log('\n✅ You can now login with these credentials!');

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
