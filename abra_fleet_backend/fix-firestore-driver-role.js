const admin = require('firebase-admin');
require('dotenv').config();

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

async function fixFirestoreDriverRole() {
  const email = 'drivertest@gmail.com';
  
  console.log('\n🔧 Fixing Firestore Role for drivertest@gmail.com');
  console.log('='.repeat(60));
  
  try {
    // 1. Get Firebase user
    const firebaseUser = await admin.auth().getUserByEmail(email);
    console.log('✅ Firebase user found');
    console.log('   UID:', firebaseUser.uid);
    console.log('   Email:', firebaseUser.email);
    
    // 2. Check current Firestore document
    console.log('\n📄 Checking Firestore document...');
    const userDoc = await admin.firestore().collection('users').doc(firebaseUser.uid).get();
    
    if (userDoc.exists) {
      const userData = userDoc.data();
      console.log('   Current role in Firestore:', userData.role);
      console.log('   Current name:', userData.name);
    } else {
      console.log('   ❌ No Firestore document found');
    }
    
    // 3. Update Firestore document with driver role
    console.log('\n✏️  Updating Firestore document...');
    await admin.firestore().collection('users').doc(firebaseUser.uid).set({
      email: email,
      name: 'Rajesh Kumar',
      role: 'driver',
      driverId: 'DRV-852306',
      status: 'active',
      isApproved: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });
    
    console.log('✅ Firestore document updated');
    
    // 4. Verify the update
    console.log('\n🔍 Verifying update...');
    const updatedDoc = await admin.firestore().collection('users').doc(firebaseUser.uid).get();
    const updatedData = updatedDoc.data();
    
    console.log('   New role in Firestore:', updatedData.role);
    console.log('   New name:', updatedData.name);
    console.log('   Driver ID:', updatedData.driverId);
    
    console.log('\n' + '='.repeat(60));
    console.log('✅ FIRESTORE ROLE FIXED!');
    console.log('='.repeat(60));
    console.log('\n📱 Now log in again with:');
    console.log('   Email: drivertest@gmail.com');
    console.log('   Password: drivertest');
    console.log('\n💡 You should now be routed to the DRIVER dashboard');
    console.log('='.repeat(60));
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error.stack);
  }
}

fixFirestoreDriverRole();
