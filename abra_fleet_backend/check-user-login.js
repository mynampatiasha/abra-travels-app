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

async function checkUserLogin() {
  const email = 'ashamynampati24@gmail.com';
  
  console.log('\n🔍 Checking Login Issue for:', email);
  console.log('='.repeat(60));
  
  try {
    // Check Firebase Auth
    console.log('\n1️⃣ Checking Firebase Auth...');
    try {
      const firebaseUser = await admin.auth().getUserByEmail(email);
      console.log('✅ User exists in Firebase Auth');
      console.log(`   UID: ${firebaseUser.uid}`);
      console.log(`   Email: ${firebaseUser.email}`);
      console.log(`   Display Name: ${firebaseUser.displayName || 'N/A'}`);
      console.log(`   Email Verified: ${firebaseUser.emailVerified}`);
      console.log(`   Disabled: ${firebaseUser.disabled}`);
      
      // Check custom claims
      const customClaims = firebaseUser.customClaims || {};
      console.log(`   Custom Claims:`, customClaims);
      console.log(`   Role: ${customClaims.role || 'Not set'}`);
      
      // Check MongoDB
      console.log('\n2️⃣ Checking MongoDB users collection...');
      const mongoClient = new MongoClient(process.env.MONGODB_URI);
      await mongoClient.connect();
      const db = mongoClient.db();
      
      const mongoUser = await db.collection('users').findOne({
        $or: [
          { email: email },
          { firebaseUid: firebaseUser.uid }
        ]
      });
      
      if (mongoUser) {
        console.log('✅ User exists in MongoDB');
        console.log(`   MongoDB _id: ${mongoUser._id}`);
        console.log(`   Firebase UID: ${mongoUser.firebaseUid}`);
        console.log(`   Email: ${mongoUser.email}`);
        console.log(`   Name: ${mongoUser.name || 'N/A'}`);
        console.log(`   Role: ${mongoUser.role}`);
        console.log(`   Status: ${mongoUser.status || 'N/A'}`);
      } else {
        console.log('❌ User NOT found in MongoDB');
        console.log('\n💡 This is the problem! User exists in Firebase but not MongoDB.');
        console.log('   The login fails because the backend checks MongoDB for user data.');
        
        // Create the user in MongoDB
        console.log('\n3️⃣ Creating user in MongoDB...');
        const newUser = {
          firebaseUid: firebaseUser.uid,
          email: firebaseUser.email,
          name: firebaseUser.displayName || 'Admin User',
          role: customClaims.role || 'admin',
          status: 'active',
          isApproved: true,
          createdAt: new Date(firebaseUser.metadata.creationTime),
          updatedAt: new Date(),
          createdBy: 'login_fix_script'
        };
        
        const result = await db.collection('users').insertOne(newUser);
        console.log('✅ User created in MongoDB!');
        console.log(`   MongoDB _id: ${result.insertedId}`);
        console.log(`   Role: ${newUser.role}`);
        
        // Update Firebase custom claims if needed
        if (!customClaims.role) {
          await admin.auth().setCustomUserClaims(firebaseUser.uid, {
            role: 'admin'
          });
          console.log('✅ Updated Firebase custom claims: role=admin');
        }
      }
      
      await mongoClient.close();
      
      console.log('\n' + '='.repeat(60));
      console.log('✅ Login should work now!');
      console.log('   Try logging in again with:');
      console.log(`   Email: ${email}`);
      console.log('='.repeat(60));
      
    } catch (fbError) {
      console.log('❌ User NOT found in Firebase Auth');
      console.log(`   Error: ${fbError.message}`);
    }
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error.stack);
  }
}

checkUserLogin();
