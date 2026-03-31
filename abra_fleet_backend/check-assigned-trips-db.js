// Direct database check for assigned trips
const { MongoClient } = require('mongodb');

async function checkAssignedTrips() {
  const client = new MongoClient('mongodb://localhost:27017');
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    // Find assigned trips
    const assignedTrips = await db.collection('rosters').find({
      status: 'assigned'
    }).limit(10).toArray();
    
    console.log(`📊 Found ${assignedTrips.length} trips with status "assigned"\n`);
    
    if (assignedTrips.length === 0) {
      console.log('⚠️  No assigned trips found!');
      
      // Check what statuses exist
      const allStatuses = await db.collection('rosters').distinct('status');
      console.log('\n📋 Available statuses in database:', allStatuses);
      return;
    }
    
    // Check each trip
    assignedTrips.forEach((trip, idx) => {
      console.log(`\n${'='.repeat(70)}`);
      console.log(`TRIP ${idx + 1}`);
      console.log(`${'='.repeat(70)}`);
      console.log(`👤 Customer: ${trip.customerName || trip.employeeDetails?.name || 'Unknown'}`);
      console.log(`📧 Email: ${trip.customerEmail || trip.employeeDetails?.email || 'N/A'}`);
      console.log(`🏢 Company: ${trip.organizationName || 'N/A'}`);
      console.log(`📍 Status: ${trip.status}`);
      console.log(`📋 Roster Type: ${trip.rosterType || 'N/A'}`);
      
      console.log(`\n🚗 VEHICLE DATA:`);
      console.log(`   vehicleId: ${trip.vehicleId || '❌ EMPTY'}`);
      console.log(`   vehicleNumber: ${trip.vehicleNumber || '❌ EMPTY'}`);
      
      console.log(`\n👨‍✈️ DRIVER DATA:`);
      console.log(`   driverId: ${trip.driverId || '❌ EMPTY'}`);
      console.log(`   driverName: ${trip.driverName || '❌ EMPTY'}`);
      
      console.log(`\n📅 DATES:`);
      console.log(`   Start: ${trip.startDate || trip.fromDate || 'N/A'}`);
      console.log(`   End: ${trip.endDate || trip.toDate || 'N/A'}`);
      console.log(`   Created: ${trip.createdAt || 'N/A'}`);
      console.log(`   Assigned: ${trip.assignedAt || 'N/A'}`);
      
      // Check if this trip has ANY vehicle/driver related fields
      const allFields = Object.keys(trip);
      const vehicleFields = allFields.filter(f => f.toLowerCase().includes('vehicle'));
      const driverFields = allFields.filter(f => f.toLowerCase().includes('driver'));
      
      if (vehicleFields.length > 0) {
        console.log(`\n🔍 All vehicle-related fields:`, vehicleFields);
      }
      if (driverFields.length > 0) {
        console.log(`🔍 All driver-related fields:`, driverFields);
      }
    });
    
    // Summary
    const withVehicleId = assignedTrips.filter(t => t.vehicleId).length;
    const withVehicleNumber = assignedTrips.filter(t => t.vehicleNumber).length;
    const withDriverId = assignedTrips.filter(t => t.driverId).length;
    const withDriverName = assignedTrips.filter(t => t.driverName).length;
    const withBoth = assignedTrips.filter(t => (t.vehicleId || t.vehicleNumber) && (t.driverId || t.driverName)).length;
    
    console.log(`\n\n${'='.repeat(70)}`);
    console.log('📊 SUMMARY');
    console.log(`${'='.repeat(70)}`);
    console.log(`Total assigned trips: ${assignedTrips.length}`);
    console.log(`With vehicleId: ${withVehicleId}`);
    console.log(`With vehicleNumber: ${withVehicleNumber}`);
    console.log(`With driverId: ${withDriverId}`);
    console.log(`With driverName: ${withDriverName}`);
    console.log(`With both vehicle AND driver: ${withBoth}`);
    
    if (withBoth === 0) {
      console.log(`\n❌ PROBLEM IDENTIFIED!`);
      console.log(`${'='.repeat(70)}`);
      console.log(`All ${assignedTrips.length} trips have status "assigned" but NO vehicle/driver data!`);
      console.log(`\n🔍 ROOT CAUSE:`);
      console.log(`   These rosters were marked as "assigned" but were never actually`);
      console.log(`   assigned to a vehicle/driver through the Route Optimization process.`);
      console.log(`\n💡 HOW TO FIX:`);
      console.log(`   Option 1: Use Route Optimization`);
      console.log(`   - Go to Admin → Pending Rosters`);
      console.log(`   - Select rosters`);
      console.log(`   - Click "Route Optimization"`);
      console.log(`   - Choose vehicle and confirm`);
      console.log(`\n   Option 2: Update database directly (if needed)`);
      console.log(`   - Run a script to populate vehicle/driver fields`);
      console.log(`   - Match rosters to available vehicles/drivers`);
    } else {
      console.log(`\n✅ ${withBoth} trips have complete vehicle/driver data`);
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    
    if (error.message.includes('ECONNREFUSED')) {
      console.log('\n💡 MongoDB is not running!');
      console.log('   Start MongoDB first, then run this script again.');
    }
  } finally {
    await client.close();
  }
}

checkAssignedTrips();
