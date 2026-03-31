// Check if Firebase user exists for driver
require('dotenv').config();
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.FIREBASE_PROJECT_ID
  });
}

async function checkFirebaseUser() {
  const email = 'suresh.reddy@abrafleet.com';
  
  console.log('🔍 Checking Firebase user for:', email);
  console.log('='.repeat(50));
  
  try {
    // Try to get user by email
    const user = await admin.auth().getUserByEmail(email);
    console.log('✅ Firebase user found!');
    console.log('   UID:', user.uid);
    console.log('   Email:', user.email);
    console.log('   Display Name:', user.displayName);
    console.log('   Email Verified:', user.emailVerified);
    console.log('   Disabled:', user.disabled);
    console.log('   Custom Claims:', user.customClaims);
    console.log('   Provider Data:', user.providerData);
    
  } catch (error) {
    console.log('❌ Firebase user not found!');
    console.log('   Error Code:', error.code);
    console.log('   Error Message:', error.message);
    
    if (error.code === 'auth/user-not-found') {
      console.log('\n💡 SOLUTION: Create Firebase user first');
      console.log('   The driver exists in MongoDB but not in Firebase Auth');
      console.log('   This is why password reset link generation fails');
    }
  }
}

checkFirebaseUser();