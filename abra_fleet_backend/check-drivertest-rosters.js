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

const MONGODB_URI = process.env.MONGODB_URI;

async function checkDriverTestRosters() {
  const driverEmail = 'drivertest@gmail.com';
  const driverId = 'DRV-852306';
  
  console.log('\n🔍 Checking Rosters for drivertest@gmail.com');
  console.log('='.repeat(60));
  console.log('Driver Email:', driverEmail);
  console.log('Driver ID:', driverId);
  console.log('='.repeat(60));
  
  let mongoClient;
  
  try {
    // Get Firebase UID
    const firebaseUser = await admin.auth().getUserByEmail(driverEmail);
    const driverUid = firebaseUser.uid;
    console.log('\n✅ Firebase UID:', driverUid);
    
    // Connect to MongoDB
    mongoClient = new MongoClient(MONGODB_URI);
    await mongoClient.connect();
    const db = mongoClient.db('abra_fleet');
    
    // Check MongoDB driver record
    console.log('\n📊 Checking MongoDB Driver Record...');
    const driver = await db.collection('drivers').findOne({ driverId: driverId });
    if (driver) {
      console.log('✅ Driver found in MongoDB');
      console.log('   Name:', driver.personalInfo?.name || driver.name);
      console.log('   Email:', driver.email);
      console.log('   Status:', driver.status);
      console.log('   Assigned Vehicle:', driver.assignedVehicle || 'None');
    } else {
      console.log('❌ Driver NOT found in MongoDB');
    }
    
    // Check rosters in MongoDB (assigned trips)
    console.log('\n📋 Checking MongoDB Rosters (Assigned Trips)...');
    const mongoRosters = await db.collection('rosters').find({
      $or: [
        { driverId: driverId },
        { 'driver.driverId': driverId },
        { assignedDriver: driverId }
      ]
    }).toArray();
    
    console.log(`Found ${mongoRosters.length} rosters in MongoDB`);
    
    if (mongoRosters.length > 0) {
      mongoRosters.forEach((roster, index) => {
        console.log(`\n   Roster ${index + 1}:`);
        console.log('   - Roster ID:', roster.rosterId || roster._id);
        console.log('   - Customer:', roster.customerName || roster.customer?.name);
        console.log('   - Status:', roster.status);
        console.log('   - Vehicle:', roster.vehicleNumber || roster.vehicle?.vehicleNumber);
        console.log('   - Driver ID:', roster.driverId || roster.driver?.driverId);
        console.log('   - Pickup Time:', roster.pickupTime);
        console.log('   - Drop Time:', roster.dropTime);
      });
    } else {
      console.log('   ❌ No rosters found in MongoDB for this driver');
    }
    
    // Check Firebase rosters
    console.log('\n📋 Checking Firebase Rosters...');
    const firebaseRostersSnapshot = await admin.firestore()
      .collection('rosters')
      .where('driverId', '==', driverId)
      .get();
    
    console.log(`Found ${firebaseRostersSnapshot.size} rosters in Firebase`);
    
    if (!firebaseRostersSnapshot.empty) {
      firebaseRostersSnapshot.forEach((doc, index) => {
        const roster = doc.data();
        console.log(`\n   Roster ${index + 1}:`);
        console.log('   - Roster ID:', doc.id);
        console.log('   - Customer:', roster.customerName);
        console.log('   - Status:', roster.status);
        console.log('   - Vehicle:', roster.vehicleNumber);
        console.log('   - Pickup Time:', roster.pickupTime);
        console.log('   - Drop Time:', roster.dropTime);
      });
    } else {
      console.log('   ❌ No rosters found in Firebase for this driver');
    }
    
    // Check assigned vehicle
    if (driver && driver.assignedVehicle) {
      console.log('\n🚗 Checking Assigned Vehicle...');
      const vehicle = await db.collection('vehicles').findOne({ 
        vehicleNumber: driver.assignedVehicle 
      });
      
      if (vehicle) {
        console.log('✅ Vehicle found:', vehicle.vehicleNumber);
        console.log('   Type:', vehicle.vehicleType);
        console.log('   Capacity:', vehicle.capacity);
        console.log('   Driver:', vehicle.assignedDriver);
      }
    }
    
    console.log('\n' + '='.repeat(60));
    console.log('📊 SUMMARY');
    console.log('='.repeat(60));
    console.log('MongoDB Rosters:', mongoRosters.length);
    console.log('Firebase Rosters:', firebaseRostersSnapshot.size);
    console.log('Total Rosters:', mongoRosters.length + firebaseRostersSnapshot.size);
    
    if (mongoRosters.length === 0 && firebaseRostersSnapshot.size === 0) {
      console.log('\n⚠️  NO ROSTERS ASSIGNED TO THIS DRIVER');
      console.log('💡 To test the driver dashboard, you need to:');
      console.log('   1. Log in as Admin');
      console.log('   2. Go to Customer Management');
      console.log('   3. Assign rosters to this driver (DRV-852306)');
      console.log('   4. Or use route optimization to assign customers');
    } else {
      console.log('\n✅ Driver has rosters assigned!');
      console.log('💡 Log in as driver to see the route details');
    }
    console.log('='.repeat(60));
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error.stack);
  } finally {
    if (mongoClient) {
      await mongoClient.close();
    }
  }
}

checkDriverTestRosters();
