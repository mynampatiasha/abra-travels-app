const { MongoClient } = require('mongodb');

const uri = 'mongodb://localhost:27017';
const client = new MongoClient(uri);

async function checkTripsData() {
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');

    const db = client.db('fleet_management');
    const rostersCollection = db.collection('rosters');

    // Find assigned rosters
    const assignedRosters = await rostersCollection
      .find({ status: 'assigned' })
      .limit(5)
      .toArray();

    console.log(`📊 Found ${assignedRosters.length} assigned rosters\n`);

    assignedRosters.forEach((roster, index) => {
      console.log(`\n🔍 Roster ${index + 1}:`);
      console.log(`   Customer: ${roster.customerName || 'N/A'}`);
      console.log(`   Email: ${roster.customerEmail || 'N/A'}`);
      console.log(`   Company: ${roster.companyName || 'N/A'}`);
      console.log(`   Status: ${roster.status}`);
      console.log(`\n   📍 Location Data:`);
      console.log(`   - Home Address: ${roster.homeAddress || 'N/A'}`);
      console.log(`   - Office Location: ${roster.officeLocation || 'N/A'}`);
      console.log(`   - Pickup Location: ${roster.pickupLocation || 'N/A'}`);
      console.log(`   - Drop Location: ${roster.dropLocation || 'N/A'}`);
      console.log(`\n   🚗 Vehicle Data:`);
      console.log(`   - vehicleId: ${roster.vehicleId || 'NOT SET'}`);
      console.log(`   - vehicleNumber: ${roster.vehicleNumber || 'NOT SET'}`);
      console.log(`\n   👤 Driver Data:`);
      console.log(`   - driverId: ${roster.driverId || 'NOT SET'}`);
      console.log(`   - driverName: ${roster.driverName || 'NOT SET'}`);
      console.log(`   - driverPhone: ${roster.driverPhone || 'NOT SET'}`);
      console.log(`\n   ⏰ Time Data:`);
      console.log(`   - startTime: ${roster.startTime || 'N/A'}`);
      console.log(`   - rosterType: ${roster.rosterType || 'N/A'}`);
      console.log(`   - assignedAt: ${roster.assignedAt || 'N/A'}`);
      console.log('\n' + '='.repeat(60));
    });

    // Check if backend fix is applied
    const withVehicleNumber = await rostersCollection.countDocuments({
      status: 'assigned',
      vehicleNumber: { $exists: true, $ne: null, $ne: '' }
    });

    const withDriverName = await rostersCollection.countDocuments({
      status: 'assigned',
      driverName: { $exists: true, $ne: null, $ne: '' }
    });

    console.log(`\n\n📈 Summary:`);
    console.log(`   Total assigned rosters: ${assignedRosters.length}`);
    console.log(`   With vehicleNumber: ${withVehicleNumber}`);
    console.log(`   With driverName: ${withDriverName}`);

    if (withVehicleNumber === 0 && withDriverName === 0) {
      console.log(`\n❌ BACKEND NOT RESTARTED!`);
      console.log(`   The backend fix is in the code but not active.`);
      console.log(`   You need to restart the backend server.`);
    } else {
      console.log(`\n✅ Backend fix is active!`);
    }

  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkTripsData();
