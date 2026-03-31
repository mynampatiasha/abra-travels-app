const admin = require('firebase-admin');
const { MongoClient } = require('mongodb');
require('dotenv').config();

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

async function testDriverLogin() {
  const email = 'ashamynampati24@gmail.com';
  const password = 'ashamynampati24';
  
  console.log('\n🔐 Testing Driver Login');
  console.log('='.repeat(60));
  console.log('Email:', email);
  console.log('Password:', '***' + password.slice(-4));
  
  try {
    // 1. Check Firebase Auth user
    console.log('\n1️⃣ Checking Firebase Auth...');
    const firebaseUser = await admin.auth().getUserByEmail(email);
    console.log('✅ Firebase user found');
    console.log('   UID:', firebaseUser.uid);
    console.log('   Email:', firebaseUser.email);
    console.log('   Display Name:', firebaseUser.displayName);
    console.log('   Email Verified:', firebaseUser.emailVerified);
    console.log('   Disabled:', firebaseUser.disabled);
    
    const customClaims = firebaseUser.customClaims || {};
    console.log('   Custom Claims:', customClaims);
    console.log('   Role:', customClaims.role || 'Not set');
    console.log('   Driver ID:', customClaims.driverId || 'Not set');
    
    // 2. Check MongoDB users collection
    console.log('\n2️⃣ Checking MongoDB users collection...');
    const mongoClient = new MongoClient(process.env.MONGODB_URI);
    await mongoClient.connect();
    const db = mongoClient.db();
    
    const user = await db.collection('users').findOne({ firebaseUid: firebaseUser.uid });
    if (user) {
      console.log('✅ User found in MongoDB users collection');
      console.log('   Role:', user.role);
      console.log('   Driver ID:', user.driverId);
      console.log('   Status:', user.status);
    } else {
      console.log('❌ User NOT found in MongoDB users collection');
    }
    
    // 3. Check MongoDB drivers collection
    console.log('\n3️⃣ Checking MongoDB drivers collection...');
    const driver = await db.collection('drivers').findOne({ uid: firebaseUser.uid });
    if (driver) {
      console.log('✅ Driver found in MongoDB drivers collection');
      console.log('   Driver ID:', driver.driverId);
      console.log('   Name:', driver.name || `${driver.personalInfo?.firstName} ${driver.personalInfo?.lastName}`);
      console.log('   Email:', driver.email || driver.personalInfo?.email);
      console.log('   Phone:', driver.phone || driver.personalInfo?.phone);
      console.log('   Status:', driver.status);
      console.log('   Assigned Vehicle:', driver.assignedVehicle || 'None');
    } else {
      console.log('❌ Driver NOT found in MongoDB drivers collection');
    }
    
    await mongoClient.close();
    
    // 4. Summary
    console.log('\n' + '='.repeat(60));
    console.log('📊 LOGIN READINESS CHECK');
    console.log('='.repeat(60));
    
    const checks = {
      'Firebase Auth User': !!firebaseUser,
      'Email Verified': firebaseUser.emailVerified,
      'Account Enabled': !firebaseUser.disabled,
      'Driver Role Set': customClaims.role === 'driver',
      'MongoDB User Record': !!user,
      'MongoDB Driver Record': !!driver,
      'Correct Role in MongoDB': user?.role === 'driver'
    };
    
    let allPassed = true;
    for (const [check, passed] of Object.entries(checks)) {
      console.log(`   ${passed ? '✅' : '❌'} ${check}`);
      if (!passed) allPassed = false;
    }
    
    console.log('='.repeat(60));
    
    if (allPassed) {
      console.log('\n✅ ALL CHECKS PASSED!');
      console.log('   The driver can log in successfully.');
      console.log('\n📱 Login Credentials:');
      console.log('   Email:', email);
      console.log('   Password:', password);
      console.log('   Role: Driver');
      console.log('   Driver ID:', driver?.driverId || customClaims.driverId);
    } else {
      console.log('\n⚠️  SOME CHECKS FAILED');
      console.log('   Login may not work properly.');
    }
    
    console.log('='.repeat(60));
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error.stack);
  }
}

testDriverLogin();
