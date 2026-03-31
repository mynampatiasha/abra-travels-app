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

async function simulateDriverRouteAPI() {
  const driverEmail = 'drivertest@gmail.com';
  
  console.log('\n🧪 Simulating Driver Route API Logic');
  console.log('='.repeat(60));
  
  let mongoClient;
  
  try {
    // Get Firebase UID
    const firebaseUser = await admin.auth().getUserByEmail(driverEmail);
    const driverFirebaseUid = firebaseUser.uid;
    console.log('✅ Firebase UID:', driverFirebaseUid);
    
    // Connect to MongoDB
    mongoClient = new MongoClient(MONGODB_URI);
    await mongoClient.connect();
    const db = mongoClient.db('abra_fleet');
    
    // Step 1: Find driver by Firebase UID
    console.log('\n📊 Step 1: Finding driver...');
    const driver = await db.collection('drivers').findOne({
      uid: driverFirebaseUid
    });
    
    if (!driver) {
      console.log('❌ Driver not found');
      return;
    }
    
    console.log('✅ Driver found:');
    console.log('   Name:', driver.personalInfo?.name || driver.name);
    console.log('   Driver ID:', driver.driverId);
    console.log('   Assigned Vehicle:', driver.assignedVehicle);
    
    // Step 2: Find rosters by driverId
    console.log('\n📊 Step 2: Finding rosters...');
    const rosters = await db.collection('rosters').find({
      driverId: driver.driverId,
      status: { $in: ['assigned', 'pending', 'active', 'in_progress'] }
    }).toArray();
    
    console.log(`✅ Found ${rosters.length} rosters`);
    
    if (rosters.length === 0) {
      console.log('⚠️  No rosters found');
      return;
    }
    
    // Step 3: Get vehicle details
    console.log('\n📊 Step 3: Getting vehicle details...');
    const firstRoster = rosters[0];
    let vehicle = null;
    
    if (firstRoster.vehicleNumber) {
      vehicle = await db.collection('vehicles').findOne({
        vehicleNumber: firstRoster.vehicleNumber
      });
    }
    
    if (!vehicle && driver.assignedVehicle) {
      vehicle = await db.collection('vehicles').findOne({
        vehicleNumber: driver.assignedVehicle
      });
    }
    
    if (vehicle) {
      console.log('✅ Vehicle found:', vehicle.vehicleNumber);
    } else {
      console.log('⚠️  No vehicle found');
    }
    
    // Step 4: Enrich customer data
    console.log('\n📊 Step 4: Enriching customer data...');
    const enrichedCustomers = [];
    
    for (const roster of rosters) {
      const customerData = {
        id: roster._id.toString(),
        name: roster.customerName || 'Unknown',
        phone: roster.customerPhone || 'N/A',
        email: roster.customerEmail || 'N/A',
        pickupLocation: roster.pickupLocation || 'N/A',
        dropLocation: roster.dropLocation || 'N/A',
        scheduledTime: roster.pickupTime || 'N/A',
        status: roster.status
      };
      enrichedCustomers.push(customerData);
    }
    
    // Step 5: Build response
    console.log('\n📊 Step 5: Building response...');
    const response = {
      hasRoute: true,
      vehicle: vehicle ? {
        registrationNumber: vehicle.vehicleNumber,
        model: vehicle.vehicleType,
        capacity: vehicle.capacity
      } : null,
      routeSummary: {
        totalCustomers: enrichedCustomers.length,
        completedCustomers: 0,
        pendingCustomers: enrichedCustomers.length
      },
      customers: enrichedCustomers
    };
    
    console.log('\n✅ API Response would be:');
    console.log(JSON.stringify(response, null, 2));
    
    console.log('\n' + '='.repeat(60));
    console.log('✅ SUCCESS! The API should return this data');
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

simulateDriverRouteAPI();
