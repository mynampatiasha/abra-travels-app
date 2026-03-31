// sync-firebase-drivers-to-mongodb.js
// Sync all drivers from Firebase/Firestore to MongoDB Atlas

const admin = require('firebase-admin');
const { MongoClient } = require('mongodb');
require('dotenv').config();

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: 'abrafleet-cec94',
  databaseURL: 'https://abrafleet-cec94-default-rtdb.firebaseio.com'
});

async function syncDriversFromFirebaseToMongoDB() {
  console.log('\n' + '='.repeat(80));
  console.log('🔄 SYNCING DRIVERS: FIREBASE → MONGODB ATLAS');
  console.log('='.repeat(80));
  
  let mongoClient;
  
  try {
    // ========== STEP 1: CONNECT TO FIREBASE ==========
    console.log('\n📋 STEP 1: Connecting to Firebase...');
    console.log('-'.repeat(80));
    
    const firestore = admin.firestore();
    console.log('✅ Connected to Firebase Firestore');
    
    // ========== STEP 2: GET ALL DRIVERS FROM FIREBASE ==========
    console.log('\n📋 STEP 2: Fetching drivers from Firebase...');
    console.log('-'.repeat(80));
    
    const driversSnapshot = await firestore.collection('drivers').get();
    console.log(`✅ Found ${driversSnapshot.size} driver(s) in Firebase`);
    
    if (driversSnapshot.empty) {
      console.log('\n⚠️  No drivers found in Firebase Firestore');
      console.log('💡 Checking Firebase Auth instead...');
      
      // Try to get drivers from Firebase Auth
      const listUsersResult = await admin.auth().listUsers();
      const driverUsers = listUsersResult.users.filter(user => 
        user.customClaims?.role === 'driver' || 
        user.email?.includes('driver') ||
        user.displayName?.toLowerCase().includes('driver')
      );
      
      console.log(`✅ Found ${driverUsers.length} potential driver(s) in Firebase Auth`);
      
      if (driverUsers.length === 0) {
        console.log('\n❌ No drivers found in Firebase Auth either');
        console.log('='.repeat(80));
        return;
      }
      
      // Convert Firebase Auth users to driver format
      const firebaseDrivers = driverUsers.map(user => ({
        uid: user.uid,
        driverId: user.customClaims?.driverId || `DRV-${Date.now()}`,
        email: user.email,
        name: user.displayName || 'Unknown Driver',
        phone: user.phoneNumber || '',
        personalInfo: {
          firstName: user.displayName?.split(' ')[0] || 'Unknown',
          lastName: user.displayName?.split(' ').slice(1).join(' ') || '',
          email: user.email,
          phone: user.phoneNumber || ''
        },
        status: user.disabled ? 'inactive' : 'active',
        createdAt: new Date(user.metadata.creationTime),
        source: 'firebase_auth'
      }));
      
      await syncToMongoDB(firebaseDrivers);
      return;
    }
    
    // ========== STEP 3: PROCESS FIREBASE DRIVERS ==========
    console.log('\n📋 STEP 3: Processing Firebase drivers...');
    console.log('-'.repeat(80));
    
    const firebaseDrivers = [];
    
    driversSnapshot.forEach(doc => {
      const data = doc.data();
      
      // Show driver info
      console.log(`\n   Driver: ${data.driverId || doc.id}`);
      console.log(`   Name: ${data.name || data.personalInfo?.firstName + ' ' + data.personalInfo?.lastName || 'N/A'}`);
      console.log(`   Email: ${data.email || data.personalInfo?.email || 'N/A'}`);
      console.log(`   Status: ${data.status || 'unknown'}`);
      
      firebaseDrivers.push({
        ...data,
        _firebaseDocId: doc.id,
        source: 'firebase_firestore'
      });
    });
    
    console.log(`\n✅ Processed ${firebaseDrivers.length} driver(s)`);
    
    // ========== STEP 4: SYNC TO MONGODB ==========
    await syncToMongoDB(firebaseDrivers);
    
  } catch (error) {
    console.error('\n❌ FATAL ERROR:', error);
    console.error(error.stack);
  } finally {
    if (mongoClient) {
      await mongoClient.close();
      console.log('✅ MongoDB connection closed');
    }
    process.exit(0);
  }
}

async function syncToMongoDB(firebaseDrivers) {
  console.log('\n📋 STEP 4: Syncing to MongoDB Atlas...');
  console.log('-'.repeat(80));
  
  // Connect to MongoDB
  const mongoUri = process.env.MONGODB_URI;
  if (!mongoUri) {
    throw new Error('MONGODB_URI not found in .env file');
  }
  
  console.log(`\n🔗 Connecting to MongoDB Atlas...`);
  console.log(`   URI: ${mongoUri.substring(0, 30)}...`);
  
  const mongoClient = new MongoClient(mongoUri);
  await mongoClient.connect();
  const db = mongoClient.db();
  
  console.log('✅ Connected to MongoDB Atlas');
  
  // Check existing drivers in MongoDB
  const existingDrivers = await db.collection('drivers').find({}).toArray();
  console.log(`\n📊 Existing drivers in MongoDB: ${existingDrivers.length}`);
  
  const results = {
    inserted: [],
    updated: [],
    skipped: [],
    failed: []
  };
  
  // Sync each driver
  for (let i = 0; i < firebaseDrivers.length; i++) {
    const driver = firebaseDrivers[i];
    const driverId = driver.driverId || driver._firebaseDocId;
    
    console.log(`\n[${i + 1}/${firebaseDrivers.length}] Processing: ${driverId}`);
    console.log('-'.repeat(60));
    
    try {
      // Check if driver exists in MongoDB
      const existingDriver = await db.collection('drivers').findOne({
        $or: [
          { driverId: driverId },
          { uid: driver.uid },
          { 'personalInfo.email': driver.email || driver.personalInfo?.email }
        ]
      });
      
      if (existingDriver) {
        console.log(`   ℹ️  Driver already exists in MongoDB`);
        console.log(`   MongoDB _id: ${existingDriver._id}`);
        
        // Update existing driver
        const updateResult = await db.collection('drivers').updateOne(
          { _id: existingDriver._id },
          { 
            $set: {
              ...driver,
              updatedAt: new Date(),
              syncedFrom: 'firebase',
              lastSyncDate: new Date()
            }
          }
        );
        
        console.log(`   ✅ Updated existing driver`);
        results.updated.push(driverId);
        
      } else {
        console.log(`   🆕 New driver - inserting into MongoDB`);
        
        // Prepare driver document for MongoDB
        const mongoDriver = {
          uid: driver.uid,
          driverId: driverId,
          name: driver.name || `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim(),
          email: driver.email || driver.personalInfo?.email,
          phone: driver.phone || driver.personalInfo?.phone,
          personalInfo: driver.personalInfo || {
            firstName: driver.name?.split(' ')[0] || 'Unknown',
            lastName: driver.name?.split(' ').slice(1).join(' ') || '',
            email: driver.email,
            phone: driver.phone
          },
          license: driver.license || null,
          emergencyContact: driver.emergencyContact || null,
          address: driver.address || null,
          employment: driver.employment || null,
          bankDetails: driver.bankDetails || null,
          status: driver.status || 'active',
          assignedVehicle: driver.assignedVehicle || null,
          documents: driver.documents || [],
          joinedDate: driver.joinedDate || driver.createdAt || new Date(),
          createdAt: driver.createdAt || new Date(),
          updatedAt: new Date(),
          syncedFrom: 'firebase',
          lastSyncDate: new Date()
        };
        
        // Insert into MongoDB
        const insertResult = await db.collection('drivers').insertOne(mongoDriver);
        console.log(`   ✅ Inserted into MongoDB: ${insertResult.insertedId}`);
        results.inserted.push(driverId);
      }
      
    } catch (driverError) {
      console.error(`   ❌ FAILED: ${driverError.message}`);
      results.failed.push({
        driverId: driverId,
        error: driverError.message
      });
    }
  }
  
  // ========== SUMMARY ==========
  console.log('\n\n' + '='.repeat(80));
  console.log('📊 SYNC SUMMARY');
  console.log('='.repeat(80));
  
  console.log(`\n📈 Statistics:`);
  console.log(`   Total drivers in Firebase: ${firebaseDrivers.length}`);
  console.log(`   Inserted into MongoDB: ${results.inserted.length}`);
  console.log(`   Updated in MongoDB: ${results.updated.length}`);
  console.log(`   Failed: ${results.failed.length}`);
  
  if (results.inserted.length > 0) {
    console.log(`\n✅ INSERTED (${results.inserted.length}):`);
    results.inserted.forEach((id, idx) => {
      console.log(`   ${idx + 1}. ${id}`);
    });
  }
  
  if (results.updated.length > 0) {
    console.log(`\n🔄 UPDATED (${results.updated.length}):`);
    results.updated.forEach((id, idx) => {
      console.log(`   ${idx + 1}. ${id}`);
    });
  }
  
  if (results.failed.length > 0) {
    console.log(`\n❌ FAILED (${results.failed.length}):`);
    results.failed.forEach((item, idx) => {
      console.log(`   ${idx + 1}. ${item.driverId}`);
      console.log(`      Error: ${item.error}`);
    });
  }
  
  console.log('\n' + '='.repeat(80));
  console.log('✅ SYNC COMPLETE');
  console.log('='.repeat(80));
  
  console.log('\n💡 NEXT STEPS:');
  console.log('   1. Verify drivers in MongoDB Atlas dashboard');
  console.log('   2. Test driver list in your app');
  console.log('   3. Test edit/delete operations');
  console.log('   4. Check if driver phone/email shows correctly');
  console.log('='.repeat(80) + '\n');
  
  await mongoClient.close();
}

// Run the sync
syncDriversFromFirebaseToMongoDB();
