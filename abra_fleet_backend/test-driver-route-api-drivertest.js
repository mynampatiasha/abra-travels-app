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

const MONGODB_URI = process.env.MONGODB_URI;

async function testDriverRouteAPI() {
  const driverEmail = 'drivertest@gmail.com';
  const driverId = 'DRV-852306';
  
  console.log('\n🧪 Testing Driver Route API for drivertest@gmail.com');
  console.log('='.repeat(60));
  
  let mongoClient;
  
  try {
    // Get Firebase UID
    const firebaseUser = await admin.auth().getUserByEmail(driverEmail);
    const driverUid = firebaseUser.uid;
    console.log('✅ Firebase UID:', driverUid);
    
    // Connect to MongoDB
    mongoClient = new MongoClient(MONGODB_URI);
    await mongoClient.connect();
    const db = mongoClient.db('abra_fleet');
    
    // Check driver in MongoDB
    console.log('\n📊 Checking Driver in MongoDB...');
    const driver = await db.collection('drivers').findOne({ uid: driverUid });
    
    if (driver) {
      console.log('✅ Driver found by Firebase UID');
      console.log('   MongoDB _id:', driver._id);
      console.log('   Driver ID:', driver.driverId);
      console.log('   Name:', driver.personalInfo?.name || driver.name);
    } else {
      console.log('❌ Driver NOT found by Firebase UID');
      
      // Try finding by driverId
      const driverByCode = await db.collection('drivers').findOne({ driverId: driverId });
      if (driverByCode) {
        console.log('⚠️  Driver found by driverId but missing Firebase UID!');
        console.log('   MongoDB _id:', driverByCode._id);
        console.log('   Driver ID:', driverByCode.driverId);
        console.log('   Firebase UID:', driverByCode.uid || 'MISSING');
      }
    }
    
    // Check rosters
    console.log('\n📋 Checking Rosters...');
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    // Check by driverId (current structure)
    const rostersByDriverId = await db.collection('rosters').find({
      driverId: driverId
    }).toArray();
    
    console.log(`Found ${rostersByDriverId.length} rosters with driverId: ${driverId}`);
    
    if (driver) {
      // Check by assignedDriver (what API expects)
      const rostersByAssignedDriver = await db.collection('rosters').find({
        assignedDriver: driver._id.toString()
      }).toArray();
      
      console.log(`Found ${rostersByAssignedDriver.length} rosters with assignedDriver: ${driver._id}`);
    }
    
    // Show roster structure
    if (rostersByDriverId.length > 0) {
      console.log('\n📄 Sample Roster Structure:');
      const sample = rostersByDriverId[0];
      console.log('   _id:', sample._id);
      console.log('   driverId:', sample.driverId);
      console.log('   assignedDriver:', sample.assignedDriver || 'MISSING');
      console.log('   driver:', sample.driver ? JSON.stringify(sample.driver) : 'MISSING');
      console.log('   customerName:', sample.customerName);
      console.log('   status:', sample.status);
    }
    
    console.log('\n' + '='.repeat(60));
    console.log('🔍 DIAGNOSIS');
    console.log('='.repeat(60));
    
    if (!driver) {
      console.log('❌ PROBLEM: Driver record missing Firebase UID');
      console.log('💡 FIX: Update driver record with Firebase UID');
    } else if (rostersByDriverId.length > 0 && !rostersByDriverId[0].assignedDriver) {
      console.log('❌ PROBLEM: Rosters use "driverId" but API expects "assignedDriver"');
      console.log('💡 FIX: Either:');
      console.log('   1. Update rosters to include assignedDriver field');
      console.log('   2. Update API to search by driverId instead');
    } else if (driver && rostersByDriverId.length > 0) {
      console.log('✅ Everything looks good!');
      console.log('   Driver has Firebase UID');
      console.log('   Rosters are assigned');
    }
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error.stack);
  } finally {
    if (mongoClient) {
      await mongoClient.close();
    }
  }
}

testDriverRouteAPI();
