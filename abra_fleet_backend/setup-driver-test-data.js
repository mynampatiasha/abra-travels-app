// Setup test data for driver dashboard testing
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI;

async function setupDriverTestData() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Find or create a test driver
    console.log('\n📝 Setting up test driver...');
    const testDriverUid = 'test_driver_uid_123'; // Update with actual Firebase UID
    
    let driver = await db.collection('drivers').findOne({ uid: testDriverUid });
    
    if (!driver) {
      console.log('   Creating new test driver...');
      await db.collection('drivers').insertOne({
        uid: testDriverUid,
        name: 'Test Driver',
        email: 'driver@test.com',
        phone: '+91 98765 43210',
        licenseNumber: 'DL-0120110012345',
        status: 'available',
        createdAt: new Date(),
        totalTrips: 0,
        totalDistance: 0
      });
      console.log('   ✅ Test driver created');
    } else {
      console.log('   ✅ Test driver found:', driver.name);
    }
    
    // Find or create a test vehicle
    console.log('\n🚗 Setting up test vehicle...');
    let vehicle = await db.collection('vehicles').findOne({ registrationNumber: 'KA-01-AB-1234' });
    
    if (!vehicle) {
      console.log('   Creating new test vehicle...');
      const vehicleResult = await db.collection('vehicles').insertOne({
        registrationNumber: 'KA-01-AB-1234',
        model: 'Toyota Innova',
        make: 'Toyota',
        year: 2023,
        capacity: 7,
        status: 'available',
        fuelType: 'Diesel',
        createdAt: new Date()
      });
      vehicle = { _id: vehicleResult.insertedId };
      console.log('   ✅ Test vehicle created');
    } else {
      console.log('   ✅ Test vehicle found:', vehicle.registrationNumber);
    }
    
    // Create an active roster assignment
    console.log('\n📋 Setting up active roster...');
    const now = new Date();
    const startTime = new Date(now.getTime() - 2 * 60 * 60 * 1000); // 2 hours ago
    const endTime = new Date(now.getTime() + 6 * 60 * 60 * 1000); // 6 hours from now
    
    await db.collection('rosters').deleteMany({
      driverId: testDriverUid,
      status: 'active'
    });
    
    await db.collection('rosters').insertOne({
      driverId: testDriverUid,
      vehicleId: vehicle._id.toString(),
      startTime: startTime,
      endTime: endTime,
      status: 'active',
      createdAt: new Date()
    });
    console.log('   ✅ Active roster created');
    
    // Create a test customer
    console.log('\n👤 Setting up test customer...');
    let customer = await db.collection('customers').findOne({ email: 'customer@test.com' });
    
    if (!customer) {
      const customerResult = await db.collection('customers').insertOne({
        name: 'Sarah Kumar',
        email: 'customer@test.com',
        phone: '+91 98765 12345',
        createdAt: new Date()
      });
      customer = { _id: customerResult.insertedId };
      console.log('   ✅ Test customer created');
    } else {
      console.log('   ✅ Test customer found:', customer.name);
    }
    
    // Create an active trip
    console.log('\n🚕 Setting up active trip...');
    await db.collection('trips').deleteMany({
      driverId: testDriverUid,
      status: { $in: ['in_progress', 'on_route', 'started'] }
    });
    
    const tripStartTime = new Date(now.getTime() - 30 * 60 * 1000); // 30 minutes ago
    const estimatedEndTime = new Date(now.getTime() + 30 * 60 * 1000); // 30 minutes from now
    
    const tripResult = await db.collection('trips').insertOne({
      tripNumber: 'TR-1234',
      driverId: testDriverUid,
      vehicleId: vehicle._id.toString(),
      customerId: customer._id.toString(),
      pickupLocation: 'Cyber City, Gurgaon',
      dropoffLocation: 'Connaught Place, Delhi',
      origin: 'Cyber City',
      destination: 'Connaught Place',
      distance: 45.2,
      customerCount: 4,
      passengers: 4,
      status: 'in_progress',
      startTime: tripStartTime,
      estimatedEndTime: estimatedEndTime,
      currentLocation: {
        type: 'Point',
        coordinates: [77.0688, 28.4595]
      },
      createdAt: new Date(),
      statusHistory: [
        {
          status: 'started',
          timestamp: tripStartTime,
          updatedBy: testDriverUid
        },
        {
          status: 'in_progress',
          timestamp: new Date(),
          updatedBy: testDriverUid
        }
      ]
    });
    console.log('   ✅ Active trip created:', tripResult.insertedId);
    
    // Create some completed trips for stats
    console.log('\n📊 Creating completed trips for stats...');
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    const completedTrips = [];
    for (let i = 0; i < 5; i++) {
      const tripStart = new Date(today.getTime() + i * 2 * 60 * 60 * 1000);
      const tripEnd = new Date(tripStart.getTime() + 45 * 60 * 1000);
      
      completedTrips.push({
        tripNumber: `TR-${1000 + i}`,
        driverId: testDriverUid,
        vehicleId: vehicle._id.toString(),
        customerId: customer._id.toString(),
        pickupLocation: 'Location A',
        dropoffLocation: 'Location B',
        distance: 20 + Math.random() * 30,
        status: 'completed',
        startTime: tripStart,
        endTime: tripEnd,
        actualEndTime: tripEnd,
        scheduledEndTime: tripEnd,
        rating: 4 + Math.random(),
        createdAt: tripStart
      });
    }
    
    await db.collection('trips').insertMany(completedTrips);
    console.log(`   ✅ Created ${completedTrips.length} completed trips`);
    
    // Create vehicle check data
    console.log('\n🔧 Creating vehicle check data...');
    await db.collection('vehicle_checks').insertOne({
      vehicleId: vehicle._id.toString(),
      driverId: testDriverUid,
      checkDate: new Date(),
      checks: [
        {
          label: 'Fuel Level',
          status: 'Full',
          isOk: true,
          lastChecked: new Date()
        },
        {
          label: 'Engine Oil',
          status: 'Low',
          isOk: false,
          lastChecked: new Date()
        },
        {
          label: 'Tire Pressure',
          status: 'Normal',
          isOk: true,
          lastChecked: new Date()
        },
        {
          label: 'Brake System',
          status: 'Normal',
          isOk: true,
          lastChecked: new Date()
        }
      ],
      createdAt: new Date()
    });
    console.log('   ✅ Vehicle check data created');
    
    console.log('\n' + '='.repeat(80));
    console.log('🎉 TEST DATA SETUP COMPLETE!');
    console.log('='.repeat(80));
    console.log('\n📝 Test Driver Details:');
    console.log(`   UID: ${testDriverUid}`);
    console.log(`   Email: driver@test.com`);
    console.log(`   Vehicle: ${vehicle.registrationNumber}`);
    console.log(`   Active Trip: TR-1234`);
    console.log('\n⚠️  Update TEST_DRIVER_UID in test-driver-dashboard-apis.js with:');
    console.log(`   const TEST_DRIVER_UID = '${testDriverUid}';`);
    console.log('');
    
  } catch (error) {
    console.error('❌ Error setting up test data:', error);
  } finally {
    await client.close();
    console.log('✅ MongoDB connection closed');
  }
}

setupDriverTestData();
