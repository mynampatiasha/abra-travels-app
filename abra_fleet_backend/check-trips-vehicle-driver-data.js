// Check if trips have vehicle and driver data
const { MongoClient } = require('mongodb');

async function checkTripsData() {
  const client = new MongoClient('mongodb://localhost:27017');
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    // Find all assigned trips
    const assignedTrips = await db.collection('rosters').find({
      status: { $in: ['assigned', 'scheduled', 'ongoing', 'in_progress', 'started', 'completed', 'done', 'cancelled'] }
    }).toArray();
    
    console.log(`📊 Total trips with assigned/ongoing/completed/cancelled status: ${assignedTrips.length}\n`);
    
    // Analyze vehicle and driver data
    let withVehicle = 0;
    let withDriver = 0;
    let withBoth = 0;
    let withNeither = 0;
    
    console.log('📋 Sample trips:\n');
    assignedTrips.slice(0, 10).forEach((trip, idx) => {
      const hasVehicle = !!(trip.vehicleId || trip.vehicleNumber);
      const hasDriver = !!(trip.driverId || trip.driverName);
      
      if (hasVehicle) withVehicle++;
      if (hasDriver) withDriver++;
      if (hasVehicle && hasDriver) withBoth++;
      if (!hasVehicle && !hasDriver) withNeither++;
      
      console.log(`${idx + 1}. ${trip.customerName || 'Unknown'}`);
      console.log(`   Status: ${trip.status}`);
      console.log(`   Vehicle ID: ${trip.vehicleId || 'NOT SET'}`);
      console.log(`   Vehicle Number: ${trip.vehicleNumber || 'NOT SET'}`);
      console.log(`   Driver ID: ${trip.driverId || 'NOT SET'}`);
      console.log(`   Driver Name: ${trip.driverName || 'NOT SET'}`);
      console.log(`   Assigned At: ${trip.assignedAt || 'NOT SET'}`);
      console.log('');
    });
    
    console.log('📊 Summary:');
    console.log(`   Total trips: ${assignedTrips.length}`);
    console.log(`   With vehicle data: ${withVehicle} (${((withVehicle/assignedTrips.length)*100).toFixed(1)}%)`);
    console.log(`   With driver data: ${withDriver} (${((withDriver/assignedTrips.length)*100).toFixed(1)}%)`);
    console.log(`   With both: ${withBoth} (${((withBoth/assignedTrips.length)*100).toFixed(1)}%)`);
    console.log(`   With neither: ${withNeither} (${((withNeither/assignedTrips.length)*100).toFixed(1)}%)`);
    
    // Check if there are any trips with vehicle/driver data
    if (withBoth === 0) {
      console.log('\n⚠️  WARNING: No trips have both vehicle and driver data!');
      console.log('   This means rosters were created but not assigned through route optimization.');
      console.log('\n💡 To fix this:');
      console.log('   1. Go to Admin Dashboard → Customer Management → Pending Rosters');
      console.log('   2. Select rosters and click "Route Optimization"');
      console.log('   3. Choose a vehicle and confirm assignment');
      console.log('   4. The trips will then have vehicle and driver data');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkTripsData();
