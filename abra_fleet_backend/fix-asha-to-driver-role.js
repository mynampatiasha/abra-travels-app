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

async function fixAshaToDriverRole() {
  const email = 'ashamynampati24@gmail.com';
  
  console.log('\n🔧 Fixing User Role: Driver Setup');
  console.log('='.repeat(60));
  console.log('Email:', email);
  
  try {
    // 1. Get Firebase user
    console.log('\n1️⃣ Checking Firebase Auth...');
    const firebaseUser = await admin.auth().getUserByEmail(email);
    console.log('✅ Firebase user found');
    console.log('   UID:', firebaseUser.uid);
    console.log('   Current claims:', firebaseUser.customClaims || {});
    
    // 2. Connect to MongoDB
    const mongoClient = new MongoClient(process.env.MONGODB_URI);
    await mongoClient.connect();
    const db = mongoClient.db();
    
    // 3. Check if user exists in drivers collection
    console.log('\n2️⃣ Checking drivers collection...');
    const driver = await db.collection('drivers').findOne({
      $or: [
        { email: email },
        { 'personalInfo.email': email },
        { uid: firebaseUser.uid }
      ]
    });
    
    if (driver) {
      console.log('✅ Driver record found in MongoDB');
      console.log('   Driver ID:', driver.driverId);
      console.log('   Name:', driver.name || `${driver.personalInfo?.firstName} ${driver.personalInfo?.lastName}`);
      console.log('   Status:', driver.status);
      
      // 4. Update Firebase custom claims to driver role
      console.log('\n3️⃣ Updating Firebase custom claims...');
      await admin.auth().setCustomUserClaims(firebaseUser.uid, {
        role: 'driver',
        driverId: driver.driverId
      });
      console.log('✅ Firebase custom claims updated: role=driver');
      
      // 5. Update/Create user in users collection with driver role
      console.log('\n4️⃣ Updating users collection...');
      const userUpdate = await db.collection('users').updateOne(
        { firebaseUid: firebaseUser.uid },
        {
          $set: {
            role: 'driver',
            email: email,
            name: driver.name || `${driver.personalInfo?.firstName} ${driver.personalInfo?.lastName}`,
            driverId: driver.driverId,
            status: 'active',
            isApproved: true,
            updatedAt: new Date()
          },
          $setOnInsert: {
            firebaseUid: firebaseUser.uid,
            createdAt: new Date(),
            createdBy: 'driver_role_fix_script'
          }
        },
        { upsert: true }
      );
      
      if (userUpdate.upsertedCount > 0) {
        console.log('✅ User record created in users collection');
      } else {
        console.log('✅ User record updated in users collection');
      }
      
      // 6. Ensure driver has uid field
      if (!driver.uid) {
        console.log('\n5️⃣ Adding Firebase UID to driver record...');
        await db.collection('drivers').updateOne(
          { _id: driver._id },
          { 
            $set: { 
              uid: firebaseUser.uid,
              updatedAt: new Date()
            } 
          }
        );
        console.log('✅ Driver record updated with Firebase UID');
      }
      
      console.log('\n' + '='.repeat(60));
      console.log('✅ SUCCESS! Driver login is now configured');
      console.log('='.repeat(60));
      console.log('\n📱 Login Credentials:');
      console.log('   Email:', email);
      console.log('   Role: driver');
      console.log('   Driver ID:', driver.driverId);
      console.log('\n💡 The user can now log in as a DRIVER');
      console.log('='.repeat(60));
      
    } else {
      console.log('❌ No driver record found in MongoDB');
      console.log('\n💡 This user exists in Firebase but not in the drivers collection.');
      console.log('   They need to be added as a driver first.');
      
      // Check if they're in users collection
      const user = await db.collection('users').findOne({ firebaseUid: firebaseUser.uid });
      if (user) {
        console.log('\n⚠️  User exists in users collection with role:', user.role);
        console.log('   If they should be a driver, they need to be added to drivers collection first.');
      }
    }
    
    await mongoClient.close();
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error.stack);
  }
}

fixAshaToDriverRole();
