const { MongoClient } = require('mongodb');
const admin = require('firebase-admin');
require('dotenv').config();

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

async function changeDriverEmail() {
  const oldEmail = 'ashamynampati24@gmail.com';
  const newEmail = 'drivertest@gmail.com';
  const newPassword = 'drivertest';
  
  console.log('\n🔄 Changing Driver Email and Password');
  console.log('='.repeat(60));
  console.log('Old Email:', oldEmail);
  console.log('New Email:', newEmail);
  console.log('New Password:', newPassword);
  
  try {
    // 1. Get existing Firebase user
    console.log('\n1️⃣ Getting existing Firebase user...');
    const oldFirebaseUser = await admin.auth().getUserByEmail(oldEmail);
    console.log('✅ Found existing user');
    console.log('   UID:', oldFirebaseUser.uid);
    console.log('   Current Email:', oldFirebaseUser.email);
    
    const customClaims = oldFirebaseUser.customClaims || {};
    const driverId = customClaims.driverId;
    
    // 2. Update Firebase user email and password
    console.log('\n2️⃣ Updating Firebase Auth...');
    await admin.auth().updateUser(oldFirebaseUser.uid, {
      email: newEmail,
      password: newPassword,
      emailVerified: true
    });
    console.log('✅ Firebase Auth updated');
    console.log('   New Email:', newEmail);
    console.log('   New Password:', newPassword);
    
    // 3. Connect to MongoDB
    const mongoClient = new MongoClient(process.env.MONGODB_URI);
    await mongoClient.connect();
    const db = mongoClient.db();
    
    // 4. Update MongoDB users collection
    console.log('\n3️⃣ Updating MongoDB users collection...');
    const userUpdate = await db.collection('users').updateOne(
      { firebaseUid: oldFirebaseUser.uid },
      { 
        $set: { 
          email: newEmail,
          updatedAt: new Date()
        } 
      }
    );
    console.log('✅ Users collection updated');
    console.log('   Modified count:', userUpdate.modifiedCount);
    
    // 5. Update MongoDB drivers collection
    console.log('\n4️⃣ Updating MongoDB drivers collection...');
    const driverUpdate = await db.collection('drivers').updateOne(
      { uid: oldFirebaseUser.uid },
      { 
        $set: { 
          email: newEmail,
          'personalInfo.email': newEmail,
          updatedAt: new Date()
        } 
      }
    );
    console.log('✅ Drivers collection updated');
    console.log('   Modified count:', driverUpdate.modifiedCount);
    
    // 6. Verify the changes
    console.log('\n5️⃣ Verifying changes...');
    const updatedFirebaseUser = await admin.auth().getUser(oldFirebaseUser.uid);
    const updatedMongoUser = await db.collection('users').findOne({ firebaseUid: oldFirebaseUser.uid });
    const updatedDriver = await db.collection('drivers').findOne({ uid: oldFirebaseUser.uid });
    
    console.log('✅ Verification complete');
    console.log('   Firebase Email:', updatedFirebaseUser.email);
    console.log('   MongoDB User Email:', updatedMongoUser?.email);
    console.log('   MongoDB Driver Email:', updatedDriver?.email);
    
    await mongoClient.close();
    
    // 7. Summary
    console.log('\n' + '='.repeat(60));
    console.log('✅ EMAIL AND PASSWORD CHANGE COMPLETE!');
    console.log('='.repeat(60));
    console.log('\n📱 New Login Credentials:');
    console.log('   Email:', newEmail);
    console.log('   Password:', newPassword);
    console.log('   Role: Driver');
    console.log('   Driver ID:', driverId);
    console.log('\n💡 The driver can now log in with the new credentials');
    console.log('='.repeat(60));
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error.stack);
  }
}

changeDriverEmail();
