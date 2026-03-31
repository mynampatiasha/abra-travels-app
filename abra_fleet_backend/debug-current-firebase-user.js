// debug-current-firebase-user.js
// Debug current Firebase users and compare with MongoDB

require('dotenv').config();
const mongoose = require('mongoose');
const admin = require('firebase-admin');

// Initialize Firebase Admin (if credentials are available)
let firebaseInitialized = false;
try {
  if (process.env.FIREBASE_PROJECT_ID && process.env.FIREBASE_CLIENT_EMAIL && process.env.FIREBASE_PRIVATE_KEY) {
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: process.env.FIREBASE_PROJECT_ID,
          clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
          privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
        }),
      });
    }
    firebaseInitialized = true;
  }
} catch (error) {
  console.log('⚠️  Firebase Admin not initialized:', error.message);
}

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

async function debugFirebaseUsers() {
  try {
    console.log('🔍 Debugging Firebase Users vs MongoDB...\n');

    await mongoose.connect(MONGODB_URI);
    console.log('✅ Connected to MongoDB\n');

    // Get all users from MongoDB
    const mongoUsers = await User.find({});
    console.log('📦 MongoDB Users:');
    console.log('═'.repeat(80));
    mongoUsers.forEach(user => {
      console.log(`📧 ${user.email}`);
      console.log(`   🔥 Firebase UID: ${user.firebaseUid}`);
      console.log(`   🔑 Role: ${user.role}`);
      console.log(`   🆔 MongoDB ID: ${user._id}`);
      console.log('');
    });

    if (firebaseInitialized) {
      console.log('🔥 Firebase Users:');
      console.log('═'.repeat(80));
      
      try {
        // List all Firebase users
        const listUsersResult = await admin.auth().listUsers(10);
        listUsersResult.users.forEach(userRecord => {
          console.log(`📧 ${userRecord.email}`);
          console.log(`   🔥 Firebase UID: ${userRecord.uid}`);
          console.log(`   👤 Display Name: ${userRecord.displayName || 'N/A'}`);
          console.log(`   ✅ Email Verified: ${userRecord.emailVerified}`);
          console.log(`   📅 Created: ${userRecord.metadata.creationTime}`);
          console.log('');
        });

        // Check specific admin user
        console.log('🔍 Admin User Comparison:');
        console.log('═'.repeat(80));
        
        const adminEmail = 'admin@abrafleet.com';
        const mongoAdmin = await User.findOne({ email: adminEmail });
        
        if (mongoAdmin) {
          console.log('📦 MongoDB Admin:');
          console.log(`   📧 Email: ${mongoAdmin.email}`);
          console.log(`   🔥 Firebase UID: ${mongoAdmin.firebaseUid}`);
          console.log(`   🔑 Role: ${mongoAdmin.role}`);
          
          try {
            const firebaseAdmin = await admin.auth().getUserByEmail(adminEmail);
            console.log('\n🔥 Firebase Admin:');
            console.log(`   📧 Email: ${firebaseAdmin.email}`);
            console.log(`   🔥 Firebase UID: ${firebaseAdmin.uid}`);
            console.log(`   👤 Display Name: ${firebaseAdmin.displayName || 'N/A'}`);
            
            console.log('\n🔍 UID Comparison:');
            console.log(`   MongoDB UID:  "${mongoAdmin.firebaseUid}"`);
            console.log(`   Firebase UID: "${firebaseAdmin.uid}"`);
            console.log(`   Match: ${mongoAdmin.firebaseUid === firebaseAdmin.uid ? '✅ YES' : '❌ NO'}`);
            
            if (mongoAdmin.firebaseUid !== firebaseAdmin.uid) {
              console.log('\n🔧 FIXING UID MISMATCH...');
              await User.findOneAndUpdate(
                { email: adminEmail },
                { 
                  firebaseUid: firebaseAdmin.uid,
                  updatedAt: new Date()
                }
              );
              console.log('✅ MongoDB UID updated to match Firebase');
            }
            
          } catch (fbError) {
            console.log('❌ Firebase admin user not found:', fbError.message);
          }
        } else {
          console.log('❌ MongoDB admin user not found');
        }
        
      } catch (listError) {
        console.log('❌ Error listing Firebase users:', listError.message);
      }
    } else {
      console.log('⚠️  Firebase not initialized - cannot compare users');
    }

    await mongoose.connection.close();
    console.log('\n✅ Debug completed');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error debugging users:', error);
    await mongoose.connection.close();
    process.exit(1);
  }
}

debugFirebaseUsers();