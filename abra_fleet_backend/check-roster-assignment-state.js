// Check the current state of rosters to understand why assignment is failing
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abrafleet';

async function checkRosterAssignmentState() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db();
    
    console.log('\n🔍 CHECKING ROSTER ASSIGNMENT STATE');
    console.log('='.repeat(60));
    
    // Get roster status summary
    const statusSummary = await db.collection('rosters').aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 }
        }
      },
      { $sort: { count: -1 } }
    ]).toArray();
    
    console.log('📊 ROSTER STATUS SUMMARY:');
    statusSummary.forEach(item => {
      console.log(`   ${item._id || 'null'}: ${item.count} rosters`);
    });
    
    // Check pending rosters specifically
    const pendingRosters = await db.collection('rosters').find({
      status: { $in: ['pending_assignment', 'pending'] }
    }).limit(10).toArray();
    
    console.log(`\n📋 PENDING ROSTERS (${pendingRosters.length} found):`);
    pendingRosters.forEach((roster, index) => {
      console.log(`   ${index + 1}. ${roster.customerName || 'Unknown'}`);
      console.log(`      ID: ${roster._id}`);
      console.log(`      Status: ${roster.status}`);
      console.log(`      VehicleId: ${roster.vehicleId || 'null'}`);
      console.log(`      DriverId: ${roster.driverId || 'null'}`);
      console.log(`      Organization: ${roster.organizationName || 'N/A'}`);
      console.log('');
    });
    
    // Check assigned rosters
    const assignedRosters = await db.collection('rosters').find({
      status: 'assigned'
    }).limit(5).toArray();
    
    console.log(`📌 ASSIGNED ROSTERS (${assignedRosters.length} found):`);
    assignedRosters.forEach((roster, index) => {
      console.log(`   ${index + 1}. ${roster.customerName || 'Unknown'}`);
      console.log(`      Vehicle: ${roster.vehicleNumber || 'N/A'}`);
      console.log(`      Driver: ${roster.driverName || 'N/A'}`);
      console.log(`      Assigned: ${roster.assignedAt ? new Date(roster.assignedAt).toLocaleString() : 'N/A'}`);
      console.log('');
    });
    
    // Check for rosters with vehicleId but wrong status
    const inconsistentRosters = await db.collection('rosters').find({
      $or: [
        { vehicleId: { $ne: null }, status: { $nin: ['assigned', 'completed'] } },
        { driverId: { $ne: null }, status: { $nin: ['assigned', 'completed'] } }
      ]
    }).limit(5).toArray();
    
    if (inconsistentRosters.length > 0) {
      console.log(`⚠️  INCONSISTENT ROSTERS (${inconsistentRosters.length} found):`);
      inconsistentRosters.forEach((roster, index) => {
        console.log(`   ${index + 1}. ${roster.customerName || 'Unknown'}`);
        console.log(`      Status: ${roster.status}`);
        console.log(`      VehicleId: ${roster.vehicleId || 'null'}`);
        console.log(`      DriverId: ${roster.driverId || 'null'}`);
        console.log('');
      });
    }
    
    // Check vehicles with assigned drivers
    const vehiclesWithDrivers = await db.collection('vehicles').find({
      'assignedDriver': { $ne: null }
    }).limit(5).toArray();
    
    console.log(`🚗 VEHICLES WITH DRIVERS (${vehiclesWithDrivers.length} found):`);
    vehiclesWithDrivers.forEach((vehicle, index) => {
      console.log(`   ${index + 1}. ${vehicle.registrationNumber || vehicle.name || 'Unknown'}`);
      console.log(`      Driver: ${vehicle.assignedDriver?.name || 'Unknown'}`);
      console.log(`      Seats: ${vehicle.seatCapacity || vehicle.capacity?.passengers || 'N/A'}`);
      console.log('');
    });
    
    console.log('💡 ANALYSIS:');
    if (pendingRosters.length === 0) {
      console.log('   ❌ No pending rosters available for assignment');
      console.log('   💡 All rosters may already be assigned');
    } else if (vehiclesWithDrivers.length === 0) {
      console.log('   ❌ No vehicles have assigned drivers');
      console.log('   💡 Assign drivers to vehicles first');
    } else {
      console.log('   ✅ Both pending rosters and vehicles with drivers exist');
      console.log('   💡 Assignment should be possible');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

checkRosterAssignmentState();