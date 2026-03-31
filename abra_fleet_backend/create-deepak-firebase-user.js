// Create Firebase user for Deepak Joshi with known password
const { MongoClient } = require('mongodb');

// MongoDB connection
const MONGO_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function createDeepakFirebaseUser() {
  const client = new MongoClient(MONGO_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('🔍 Creating Firebase user for Deepak Joshi...\n');
    
    const email = 'deepak.joshi@abrafleet.com';
    const password = 'Deepak123!';
    const driverId = 'DRV-100012';
    
    // Initialize Firebase Admin
    const admin = require('firebase-admin');
    
    if (!admin.apps.length) {
      const serviceAccount = require('./serviceAccountKey.json');
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
        databaseURL: 'https://abra-fleet-default-rtdb.firebaseio.com'
      });
    }
    
    let firebaseUid = null;
    
    // Check if Firebase user already exists
    try {
      const existingUser = await admin.auth().getUserByEmail(email);
      firebaseUid = existingUser.uid;
      console.log('✅ Found existing Firebase user:', firebaseUid);
      
      // Update password
      await admin.auth().updateUser(firebaseUid, {
        password: password,
        emailVerified: true
      });
      console.log('✅ Password updated successfully');
      
    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        console.log('❌ Firebase user not found. Creating new user...');
        
        // Create new Firebase user
        const firebaseUser = await admin.auth().createUser({
          email: email,
          emailVerified: true,
          password: password,
          displayName: 'Deepak Joshi',
          disabled: false
        });
        
        firebaseUid = firebaseUser.uid;
        console.log('✅ Created new Firebase user:', firebaseUid);
      } else {
        throw error;
      }
    }
    
    // Set custom claims
    await admin.auth().setCustomUserClaims(firebaseUid, {
      role: 'driver',
      driverId: driverId
    });
    console.log('✅ Custom claims set');
    
    // Update MongoDB records with Firebase UID
    await db.collection('drivers').updateOne(
      { driverId: driverId },
      { 
        $set: { 
          firebaseUid: firebaseUid,
          uid: firebaseUid,
          updatedAt: new Date()
        }
      }
    );
    console.log('✅ Updated drivers collection with Firebase UID');
    
    await db.collection('admin_users').updateOne(
      { driverId: driverId },
      { 
        $set: { 
          firebaseUid: firebaseUid,
          updatedAt: new Date()
        }
      }
    );
    console.log('✅ Updated admin_users collection with Firebase UID');
    
    console.log('\n🎉 SUCCESS! Deepak Joshi is ready for testing!');
    console.log('='.repeat(60));
    console.log('📧 Email:', email);
    console.log('🔑 Password:', password);
    console.log('🆔 Driver ID:', driverId);
    console.log('🚗 Vehicle:', 'KA07JK1234');
    console.log('🔥 Firebase UID:', firebaseUid);
    console.log('='.repeat(60));
    
    console.log('\n💡 HOW TO TEST:');
    console.log('1. Open the driver app/dashboard');
    console.log('2. Login with:');
    console.log('   Email: deepak.joshi@abrafleet.com');
    console.log('   Password: Deepak123!');
    console.log('3. Should successfully login as driver');
    console.log('4. Should see driver dashboard with vehicle KA07JK1234');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error('Stack:', error.stack);
  } finally {
    await client.close();
    console.log('\n✅ MongoDB connection closed');
  }
}

createDeepakFirebaseUser();