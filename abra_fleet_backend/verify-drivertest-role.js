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

async function verifyDriverTestRole() {
  const email = 'drivertest@gmail.com';
  
  console.log('\n🔍 Verifying drivertest@gmail.com Role');
  console.log('='.repeat(60));
  
  try {
    // 1. Check Firebase Auth
    console.log('\n1️⃣ Firebase Auth Check:');
    const firebaseUser = await admin.auth().getUserByEmail(email);
    console.log('   Email:', firebaseUser.email);
    console.log('   UID:', firebaseUser.uid);
    console.log('   Custom Claims:', JSON.stringify(firebaseUser.customClaims, null, 2));
    console.log('   Role from claims:', firebaseUser.customClaims?.role || 'NOT SET');
    
    // 2. Check MongoDB
    const mongoClient = new MongoClient(process.env.MONGODB_URI);
    await mongoClient.connect();
    const db = mongoClient.db();
    
    console.log('\n2️⃣ MongoDB users collection:');
    const user = await db.collection('users').findOne({ firebaseUid: firebaseUser.uid });
    if (user) {
      console.log('   Email:', user.email);
      console.log('   Role:', user.role);
      console.log('   Driver ID:', user.driverId || 'N/A');
    } else {
      console.log('   ❌ User NOT found in users collection');
    }
    
    console.log('\n3️⃣ MongoDB drivers collection:');
    const driver = await db.collection('drivers').findOne({ uid: firebaseUser.uid });
    if (driver) {
      console.log('   Driver ID:', driver.driverId);
      console.log('   Name:', driver.name);
      console.log('   Email:', driver.email);
      console.log('   Status:', driver.status);
    } else {
      console.log('   ❌ Driver NOT found in drivers collection');
    }
    
    await mongoClient.close();
    
    // 3. Summary
    console.log('\n' + '='.repeat(60));
    console.log('📊 ROLE VERIFICATION SUMMARY');
    console.log('='.repeat(60));
    
    const firebaseRole = firebaseUser.customClaims?.role;
    const mongoRole = user?.role;
    const isDriver = driver !== null;
    
    console.log(`   Firebase Role: ${firebaseRole || 'NOT SET'}`);
    console.log(`   MongoDB Role: ${mongoRole || 'NOT SET'}`);
    console.log(`   Is Driver: ${isDriver ? 'YES' : 'NO'}`);
    
    if (firebaseRole === 'driver' && mongoRole === 'driver' && isDriver) {
      console.log('\n✅ CORRECT: User is properly configured as DRIVER');
      console.log('   Should route to: Driver Dashboard');
    } else {
      console.log('\n⚠️  ISSUE DETECTED:');
      if (firebaseRole !== 'driver') {
        console.log(`   - Firebase role is "${firebaseRole}" (should be "driver")`);
      }
      if (mongoRole !== 'driver') {
        console.log(`   - MongoDB role is "${mongoRole}" (should be "driver")`);
      }
      if (!isDriver) {
        console.log('   - No driver record found in drivers collection');
      }
    }
    
    console.log('='.repeat(60));
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error.stack);
  }
}

verifyDriverTestRole();
