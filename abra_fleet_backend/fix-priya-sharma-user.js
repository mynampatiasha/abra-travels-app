const admin = require('firebase-admin');
const { MongoClient } = require('mongodb');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

require('dotenv').config();
const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME = 'abra_fleet';

async function fixPriyaSharmaUser() {
  const mongoClient = new MongoClient(MONGODB_URI);
  
  try {
    await mongoClient.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = mongoClient.db(DB_NAME);
    const usersCollection = db.collection('users');
    
    // Check if user exists in MongoDB
    const existingUser = await usersCollection.findOne({ 
      email: 'priya.sharma@infosys.com' 
    });
    
    if (existingUser) {
      console.log('✅ User already exists in MongoDB:', existingUser);
      console.log('   Continuing to check/create Firestore document...');
    }
    
    // Get Firebase user
    let firebaseUser;
    try {
      firebaseUser = await admin.auth().getUserByEmail('priya.sharma@infosys.com');
      console.log('✅ Found Firebase user:', firebaseUser.uid);
    } catch (error) {
      console.log('❌ User not found in Firebase. Creating...');
      
      // Create Firebase user
      firebaseUser = await admin.auth().createUser({
        email: 'priya.sharma@infosys.com',
        password: 'Welcome@6vipo81i',
        displayName: 'Priya Sharma',
        emailVerified: true
      });
      console.log('✅ Created Firebase user:', firebaseUser.uid);
    }
    
    // Create MongoDB user if not exists
    if (!existingUser) {
      console.log('❌ User not found in MongoDB. Creating...');
      const newUser = {
        uid: firebaseUser.uid,
        email: 'priya.sharma@infosys.com',
        name: 'Priya Sharma',
        phone: '+91 9876543210',
        role: 'customer',
        organization: 'Infosys',
        status: 'active',
        createdAt: new Date(),
        updatedAt: new Date()
      };
      
      await usersCollection.insertOne(newUser);
      console.log('✅ Created MongoDB user:', newUser);
    }
    
    // Create Firestore user document
    console.log('\n📝 Creating Firestore user document...');
    const firestore = admin.firestore();
    await firestore.collection('users').doc(firebaseUser.uid).set({
      uid: firebaseUser.uid,
      email: 'priya.sharma@infosys.com',
      name: 'Priya Sharma',
      phone: '+91 9876543210',
      role: 'customer',
      organization: 'Infosys',
      status: 'Active',
      isActive: true,
      isPendingApproval: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    console.log('✅ Created Firestore user document');
    
    // Verify
    const verifyUser = await usersCollection.findOne({ 
      email: 'priya.sharma@infosys.com' 
    });
    console.log('✅ Verification - User in MongoDB:', verifyUser);
    
    const firestoreDoc = await firestore.collection('users').doc(firebaseUser.uid).get();
    console.log('✅ Verification - User in Firestore:', firestoreDoc.data());
    
    console.log('\n🎉 SUCCESS! Priya Sharma can now login!');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await mongoClient.close();
    process.exit(0);
  }
}

fixPriyaSharmaUser();
