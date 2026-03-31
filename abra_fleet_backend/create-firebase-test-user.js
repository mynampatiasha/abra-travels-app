// Create test user in both Firebase Authentication and MongoDB
require('dotenv').config();
const admin = require('./config/firebase');
const mongoose = require('mongoose');
const User = require('./models/User');

const testUser = {
  name: 'Chandrika Test User',
  email: 'chandrika123@abrafleet.com',
  password: 'chandrika123',
  phone: '+91 9876543210',
  role: 'admin'
};

async function createFirebaseTestUser() {
  try {
    console.log('\n🔧 Creating test user in Firebase Authentication and MongoDB...');
    console.log('═'.repeat(80));
    
    // Connect to MongoDB
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB');
    
    console.log(`\n👤 Creating user: ${testUser.email}`);
    console.log(`   Name: ${testUser.name}`);
    console.log(`   Password: ${testUser.password}`);
    console.log(`   Role: ${testUser.role}`);
    
    // Step 1: Check if user already exists in Firebase
    let firebaseUser;
    try {
      firebaseUser = await admin.auth().getUserByEmail(testUser.email);
      console.log('⚠️  User already exists in Firebase, deleting first...');
      await admin.auth().deleteUser(firebaseUser.uid);
      console.log('🗑️  Deleted existing Firebase user');
    } catch (error) {
      if (error.code !== 'auth/user-not-found') {
        throw error;
      }
      console.log('✅ User does not exist in Firebase (good)');
    }
    
    // Step 2: Check if user exists in MongoDB and delete
    const existingMongoUser = await User.findOne({ email: testUser.email });
    if (existingMongoUser) {
      console.log('⚠️  User already exists in MongoDB, deleting first...');
      await User.deleteOne({ email: testUser.email });
      console.log('🗑️  Deleted existing MongoDB user');
    }
    
    // Step 3: Create user in Firebase Authentication
    console.log('\n🔥 Creating user in Firebase Authentication...');
    firebaseUser = await admin.auth().createUser({
      email: testUser.email,
      password: testUser.password,
      displayName: testUser.name,
      emailVerified: true // Set as verified for testing
    });
    console.log(`✅ Firebase user created with UID: ${firebaseUser.uid}`);
    
    // Step 4: Set custom claims in Firebase
    console.log('🔧 Setting Firebase custom claims...');
    await admin.auth().setCustomUserClaims(firebaseUser.uid, {
      role: testUser.role,
      hasPermissions: true
    });
    console.log('✅ Custom claims set');
    
    // Step 5: Create user in MongoDB
    console.log('🗄️  Creating user in MongoDB...');
    const newUser = new User({
      name: testUser.name,
      email: testUser.email,
      phone: testUser.phone,
      password: testUser.password, // Will be hashed by pre-save hook
      role: testUser.role,
      firebaseUid: firebaseUser.uid,
      isActive: true,
      standardPermissions: [],
      customPermissions: []
    });
    
    await newUser.save();
    console.log('✅ User saved to MongoDB');
    
    // Step 6: Verify the user can be retrieved
    console.log('\n🔍 Verifying user creation...');
    
    // Check Firebase
    const verifyFirebaseUser = await admin.auth().getUser(firebaseUser.uid);
    console.log(`✅ Firebase verification: ${verifyFirebaseUser.email}`);
    
    // Check MongoDB
    const verifyMongoUser = await User.findOne({ email: testUser.email }).select('-password');
    console.log(`✅ MongoDB verification: ${verifyMongoUser.email} (Role: ${verifyMongoUser.role})`);
    
    console.log('\n🎉 SUCCESS! Test user created successfully!');
    console.log('═'.repeat(80));
    console.log('📋 LOGIN CREDENTIALS:');
    console.log(`   Email: ${testUser.email}`);
    console.log(`   Password: ${testUser.password}`);
    console.log('═'.repeat(80));
    console.log('\n✅ You can now login with these credentials in the Flutter app');
    
    await mongoose.disconnect();
    process.exit(0);
    
  } catch (error) {
    console.error('\n❌ Error creating test user:', error.message);
    console.error('Stack:', error.stack);
    console.error('═'.repeat(80) + '\n');
    
    await mongoose.disconnect();
    process.exit(1);
  }
}

createFirebaseTestUser();