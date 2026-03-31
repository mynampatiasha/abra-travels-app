// Test the updated driver route API for Asha
const admin = require('firebase-admin');
const { MongoClient, ObjectId } = require('mongodb');

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  const serviceAccount = require('./serviceAccountKey.json');
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function testAshaRoute() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('\n🔍 TESTING ASHA DRIVER ROUTE API');
    console.log('================================\n');
    
    // 1. Find Asha driver
    const ashaDriver = await db.collection('drivers').findOne({
      email: 'ashamynampati2003@gmail.com'
    });
    
    if (!ashaDriver) {
      console.log('❌ Asha driver not found!');
      return;
    }
    
    console.log('✅ Asha Driver Found:');
    console.log(`   Name: ${ashaDriver.name}`);
    console.log(`   Email: ${ashaDriver.email}`);
    console.log(`   MongoDB _id: ${ashaDriver._id}`);
    console.log(`   Firebase UID: ${ashaDriver.uid}`);
    
    // 2. Check for rosters assigned to Asha
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    
    console.log(`\n📅 Checking rosters for today: ${today.toISOString().split('T')[0]}`);
    
    const rosters = await db.collection('rosters').find({
      assignedDriver: ashaDriver._id.toString(),
      startDate: { $lte: today },
      endDate: { $gte: today },
      status: { $nin: ['cancelled', 'completed'] }
    }).toArray();
    
    console.log(`\n📋 Found ${rosters.length} roster(s) for Asha today`);
    
    if (rosters.length === 0) {
      console.log('\n⚠️  NO ROSTERS ASSIGNED TO ASHA FOR TODAY');
      console.log('\n💡 TO FIX THIS:');
      console.log('   1. Login to admin panel');
      console.log('   2. Go to Customer Management');
      console.log('   3. Assign rosters to Asha driver (ashamynampati2003@gmail.com)');
      console.log('   4. Make sure the roster dates include today');
      
      // Show what other drivers have rosters
      console.log('\n📊 Checking other drivers with rosters today:');
      const allRosters = await db.collection('rosters').find({
        startDate: { $lte: today },
        endDate: { $gte: today },
        status: { $nin: ['cancelled', 'completed'] }
      }).toArray();
      
      const driverCounts = {};
      for (const roster of allRosters) {
        const driverId = roster.assignedDriver;
        driverCounts[driverId] = (driverCounts[driverId] || 0) + 1;
      }
      
      for (const [driverId, count] of Object.entries(driverCounts)) {
        try {
          // Try to convert to ObjectId if it's a valid hex string
          const driverObjectId = ObjectId.isValid(driverId) && driverId.length === 24 
            ? new ObjectId(driverId) 
            : driverId;
          
          const driver = await db.collection('drivers').findOne({ 
            $or: [
              { _id: driverObjectId },
              { driverCode: driverId }
            ]
          });
          console.log(`   - ${driver?.name || 'Unknown'} (${driver?.email || driverId}): ${count} roster(s)`);
        } catch (err) {
          console.log(`   - Unknown driver (${driverId}): ${count} roster(s)`);
        }
      }
      
      return;
    }
    
    // 3. Show roster details
    console.log('\n📋 ROSTER DETAILS:');
    for (let i = 0; i < rosters.length; i++) {
      const roster = rosters[i];
      console.log(`\n   Roster ${i + 1}:`);
      console.log(`   - ID: ${roster._id}`);
      console.log(`   - Customer UID: ${roster.userId}`);
      console.log(`   - Type: ${roster.rosterType}`);
      console.log(`   - Time: ${roster.startTime} - ${roster.endTime}`);
      console.log(`   - Status: ${roster.status}`);
      console.log(`   - Vehicle: ${roster.assignedVehicle}`);
      
      // Get customer details
      const customer = await db.collection('users').findOne({ uid: roster.userId });
      if (customer) {
        console.log(`   - Customer Name: ${customer.name}`);
        console.log(`   - Customer Phone: ${customer.phone}`);
        console.log(`   - Customer Email: ${customer.email}`);
      }
      
      // Show locations
      if (roster.locations) {
        console.log(`   - Pickup: ${roster.locations.loginPickup?.address || 'N/A'}`);
        console.log(`   - Drop: ${roster.locations.logoutDrop?.address || roster.officeLocation || 'N/A'}`);
      }
    }
    
    // 4. Simulate API call
    console.log('\n\n🌐 SIMULATING API RESPONSE:');
    console.log('================================\n');
    
    // Get vehicle details
    const firstRoster = rosters[0];
    const vehicle = firstRoster.assignedVehicle ? await db.collection('vehicles').findOne({
      _id: new ObjectId(firstRoster.assignedVehicle)
    }) : null;
    
    // Enrich customer data
    const enrichedCustomers = await Promise.all(rosters.map(async (roster) => {
      const customer = await db.collection('users').findOne({ uid: roster.userId });
      
      const pickupLocation = roster.locations?.loginPickup?.address || roster.locations?.pickup?.address || 'N/A';
      const dropLocation = roster.locations?.logoutDrop?.address || roster.locations?.drop?.address || roster.officeLocation || 'N/A';
      
      return {
        id: roster._id.toString(),
        customerId: roster.userId,
        name: customer?.name || 'Unknown Customer',
        phone: customer?.phone || 'N/A',
        email: customer?.email || 'N/A',
        rosterType: roster.rosterType,
        scheduledTime: roster.startTime,
        endTime: roster.endTime,
        pickupLocation: pickupLocation,
        dropLocation: dropLocation,
        officeLocation: roster.officeLocation,
        status: roster.status
      };
    }));
    
    const apiResponse = {
      status: 'success',
      data: {
        hasRoute: true,
        vehicle: vehicle ? {
          id: vehicle._id.toString(),
          registrationNumber: vehicle.registrationNumber,
          model: vehicle.model,
          make: vehicle.make,
          capacity: vehicle.capacity
        } : null,
        routeSummary: {
          totalCustomers: enrichedCustomers.length,
          completedCustomers: 0,
          pendingCustomers: enrichedCustomers.length
        },
        customers: enrichedCustomers
      }
    };
    
    console.log(JSON.stringify(apiResponse, null, 2));
    
    console.log('\n✅ API TEST COMPLETE');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

testAshaRoute();
