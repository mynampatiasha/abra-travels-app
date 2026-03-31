const admin = require('firebase-admin');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

async function checkJohnDoe() {
  try {
    const firebaseUser = await admin.auth().getUserByEmail('john.doe@abrafleet.com');
    
    console.log('\n✅ Account found in Firebase!');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('📧 Email: john.doe@abrafleet.com');
    console.log('👤 Name:', firebaseUser.displayName || 'Not set');
    console.log('🆔 Firebase UID:', firebaseUser.uid);
    console.log('📅 Created:', firebaseUser.metadata.creationTime);
    console.log('✉️  Email Verified:', firebaseUser.emailVerified);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('\n⚠️  Password: Cannot retrieve from Firebase');
    console.log('💡 Options:');
    console.log('   1. Use password reset feature in the app');
    console.log('   2. Set a new password (see below)');
    
  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      console.log('\n❌ Account does not exist');
      console.log('Creating new account...\n');
      
      const password = 'Welcome@test123';
      
      const newUser = await admin.auth().createUser({
        email: 'john.doe@abrafleet.com',
        password: password,
        displayName: 'John Doe',
        emailVerified: true
      });
      
      console.log('✅ Account created successfully!');
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      console.log('📧 Email: john.doe@abrafleet.com');
      console.log('🔑 Password:', password);
      console.log('👤 Name: John Doe');
      console.log('🆔 Firebase UID:', newUser.uid);
      console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
    } else {
      console.error('❌ Error:', error.message);
    }
  }
}

checkJohnDoe();
