const admin = require('firebase-admin');
const { MongoClient } = require('mongodb');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const MONGODB_URI = 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet';

async function createJohnDoeAccount() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db(DB_NAME);
    const usersCollection = db.collection('users');
    
    // Check if user already exists
    const existingUser = await usersCollection.findOne({ 
      email: 'john.doe@abrafleet.com' 
    });
    
    if (existingUser) {
      console.log('\n📧 User already exists!');
      console.log('Email:', existingUser.email);
      console.log('Firebase UID:', existingUser.uid);
      console.log('Role:', existingUser.role);
      console.log('\n⚠️  Password: Check Firebase Console or use password reset');
      
      // Try to get Firebase user
      try {
        const firebaseUser = await admin.auth().getUserByEmail('john.doe@abrafleet.com');
        console.log('\n✅ Firebase account exists');
        console.log('Created:', firebaseUser.metadata.creationTime);
      } catch (error) {
        console.log('\n❌ Firebase account not found');
      }
      
      return;
    }
    
    // Create new account
    const password = 'Welcome@test123';
    
    console.log('\n🔧 Creating new account...');
    
    // Create Firebase user
    const firebaseUser = await admin.auth().createUser({
      email: 'john.doe@abrafleet.com',
      password: password,
      displayName: 'John Doe',
      emailVerified: true
    });
    
    console.log('✅ Firebase user created:', firebaseUser.uid);
    
    // Create MongoDB user
    const mongoUser = {
      uid: firebaseUser.uid,
      email: 'john.doe@abrafleet.com',
      name: 'John Doe',
      role: 'customer',
      organizationId: 'abra_fleet',
      organizationName: 'Abra Fleet',
      phone: '+919876543210',
      status: 'active',
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    await usersCollection.insertOne(mongoUser);
    console.log('✅ MongoDB user created');
    
    console.log('\n🎉 Account created successfully!');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('📧 Email: john.doe@abrafleet.com');
    console.log('🔑 Password:', password);
    console.log('👤 Name: John Doe');
    console.log('🏢 Organization: Abra Fleet');
    console.log('🆔 Firebase UID:', firebaseUser.uid);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    
    if (error.code === 'auth/email-already-exists') {
      console.log('\n⚠️  Firebase account exists but not in MongoDB');
      console.log('Checking Firebase...');
      
      try {
        const firebaseUser = await admin.auth().getUserByEmail('john.doe@abrafleet.com');
        console.log('\n✅ Found in Firebase:');
        console.log('UID:', firebaseUser.uid);
        console.log('Email:', firebaseUser.email);
        console.log('Created:', firebaseUser.metadata.creationTime);
        console.log('\n⚠️  Password: Use password reset or check your records');
      } catch (err) {
        console.error('Error getting Firebase user:', err.message);
      }
    }
  } finally {
    await client.close();
    console.log('\n✅ MongoDB connection closed');
  }
}

createJohnDoeAccount();
