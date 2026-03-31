// create-customer123-firebase-user.js
// Creates Firebase Auth user for customer123@abrafleet.com

const admin = require('./config/firebase'); // Use existing Firebase config
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.DB_NAME || 'abra_fleet';

const DEMO_CUSTOMER = {
  email: 'customer123@abrafleet.com',
  password: 'Customer@123',
  name: 'Demo Customer',
  phone: '+91-9876543210',
  organizationName: 'Abra Travels Demo Org'
};

async function createFirebaseUser() {
  const mongoClient = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔗 Connecting to MongoDB...');
    await mongoClient.connect();
    const db = mongoClient.db(DB_NAME);
    console.log('✅ Connected to MongoDB\n');

    // Check if Firebase user already exists
    console.log(`🔍 Checking if Firebase user exists: ${DEMO_CUSTOMER.email}`);
    let firebaseUser;
    let userExists = false;
    
    try {
      firebaseUser = await admin.auth().getUserByEmail(DEMO_CUSTOMER.email);
      userExists = true;
      console.log(`✅ Firebase user already exists`);
      console.log(`   UID: ${firebaseUser.uid}`);
      console.log(`   Email: ${firebaseUser.email}`);
      console.log(`   Display Name: ${firebaseUser.displayName || 'Not set'}`);
    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        console.log(`❌ Firebase user not found - creating new user...`);
        
        // Create Firebase Auth user
        firebaseUser = await admin.auth().createUser({
          email: DEMO_CUSTOMER.email,
          password: DEMO_CUSTOMER.password,
          displayName: DEMO_CUSTOMER.name,
          emailVerified: true, // Auto-verify for demo
          disabled: false
        });
        
        console.log(`✅ Firebase user created successfully!`);
        console.log(`   UID: ${firebaseUser.uid}`);
        console.log(`   Email: ${firebaseUser.email}`);
        console.log(`   Password: ${DEMO_CUSTOMER.password}`);
      } else {
        throw error;
      }
    }

    // Set custom claims for customer role
    console.log(`\n🔧 Setting custom claims...`);
    await admin.auth().setCustomUserClaims(firebaseUser.uid, {
      role: 'customer',
      organizationName: DEMO_CUSTOMER.organizationName
    });
    console.log(`✅ Custom claims set: role=customer`);

    // Update/Create MongoDB user record
    console.log(`\n💾 Updating MongoDB user record...`);
    const mongoUser = {
      firebaseUid: firebaseUser.uid,
      email: DEMO_CUSTOMER.email,
      name: DEMO_CUSTOMER.name,
      phone: DEMO_CUSTOMER.phone,
      role: 'customer',
      companyName: DEMO_CUSTOMER.organizationName,
      organizationName: DEMO_CUSTOMER.organizationName,
      status: 'active',
      isApproved: true,
      createdAt: new Date(),
      updatedAt: new Date()
    };

    await db.collection('users').updateOne(
      { email: DEMO_CUSTOMER.email },
      { $set: mongoUser },
      { upsert: true }
    );
    console.log(`✅ MongoDB user record updated`);

    // Summary
    console.log(`\n${'='.repeat(80)}`);
    console.log(`✅ CUSTOMER123 SETUP COMPLETE`);
    console.log(`${'='.repeat(80)}`);
    console.log(`📧 Email: ${DEMO_CUSTOMER.email}`);
    console.log(`🔑 Password: ${DEMO_CUSTOMER.password}`);
    console.log(`🆔 Firebase UID: ${firebaseUser.uid}`);
    console.log(`👤 Name: ${DEMO_CUSTOMER.name}`);
    console.log(`📱 Phone: ${DEMO_CUSTOMER.phone}`);
    console.log(`🏢 Organization: ${DEMO_CUSTOMER.organizationName}`);
    console.log(`\n💡 You can now login with these credentials!`);
    console.log(`${'='.repeat(80)}\n`);

  } catch (error) {
    console.error('❌ Error:', error);
    console.error(error.stack);
  } finally {
    await mongoClient.close();
    console.log('✅ Disconnected from MongoDB');
  }
}

// Run the script
if (require.main === module) {
  createFirebaseUser().catch(console.error);
}

module.exports = { createFirebaseUser };
