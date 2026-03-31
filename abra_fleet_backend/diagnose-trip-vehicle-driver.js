// Diagnose why vehicle/driver not showing in trip details
// This script connects to MongoDB directly

const { MongoClient } = require('mongodb');
require('dotenv').config();

async function diagnose() {
  // Try to get MongoDB URI from environment or use default
  const mongoUri = process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017';
  const dbName = process.env.DB_NAME || 'abra_fleet';
  
  console.log(`🔌 Connecting to: ${mongoUri}`);
  console.log(`📦 Database: ${dbName}\n`);
  
  const client = new MongoClient(mongoUri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(dbName);
    
    // Find trips with status "assigned"
    console.log('🔍 Searching for trips with status "assigned"...\n');
    
    const assignedTrips = await db.collection('rosters').find({
      status: 'assigned'
    }).limit(5).toArray();
    
    console.log(`📊 Found ${assignedTrips.length} trips\n`);
    
    if (assignedTrips.length === 0) {
      console.log('⚠️  No trips with status "assigned" found!');
      console.log('\n🔍 Checking what statuses exist...');
      
      const statuses = await db.collection('rosters').aggregate([
        { $group: { _id: '$status', count: { $sum: 1 } } },
        { $sort: { count: -1 } }
      ]).toArray();
      
      console.log('\n📋 Available statuses:');
      statuses.forEach(s => {
        console.log(`   ${s._id}: ${s.count} trips`);
      });
      
      return;
    }
    
    // Analyze each trip
    let emptyCount = 0;
    
    assignedTrips.forEach((trip, idx) => {
      const hasVehicle = !!(trip.vehicleId || trip.vehicleNumber);
      const hasDriver = !!(trip.driverId || trip.driverName);
      
      if (!hasVehicle && !hasDriver) emptyCount++;
      
      console.log(`${'─'.repeat(70)}`);
      console.log(`TRIP ${idx + 1}: ${trip.customerName || 'Unknown'}`);
      console.log(`${'─'.repeat(70)}`);
      console.log(`Status: ${trip.status}`);
      console.log(`Company: ${trip.organizationName || 'N/A'}`);
      console.log(`Email: ${trip.customerEmail || 'N/A'}`);
      console.log(``);
      console.log(`🚗 Vehicle:`);
      console.log(`   ID: ${trip.vehicleId || '❌ EMPTY'}`);
      console.log(`   Number: ${trip.vehicleNumber || '❌ EMPTY'}`);
      console.log(``);
      console.log(`👨‍✈️ Driver:`);
      console.log(`   ID: ${trip.driverId || '❌ EMPTY'}`);
      console.log(`   Name: ${trip.driverName || '❌ EMPTY'}`);
      console.log(``);
      console.log(`📅 Dates:`);
      console.log(`   Created: ${trip.createdAt ? new Date(trip.createdAt).toLocaleString() : 'N/A'}`);
      console.log(`   Assigned: ${trip.assignedAt ? new Date(trip.assignedAt).toLocaleString() : 'N/A'}`);
      console.log(``);
    });
    
    // Final diagnosis
    console.log(`${'='.repeat(70)}`);
    console.log(`DIAGNOSIS`);
    console.log(`${'='.repeat(70)}`);
    console.log(`Total trips checked: ${assignedTrips.length}`);
    console.log(`Trips missing vehicle/driver: ${emptyCount}`);
    console.log(``);
    
    if (emptyCount === assignedTrips.length) {
      console.log(`❌ PROBLEM CONFIRMED!`);
      console.log(`   ALL ${assignedTrips.length} trips are missing vehicle and driver data!`);
      console.log(``);
      console.log(`🔍 ROOT CAUSE:`);
      console.log(`   These trips have status="assigned" but were never actually`);
      console.log(`   assigned to a vehicle/driver through Route Optimization.`);
      console.log(``);
      console.log(`💡 SOLUTION:`);
      console.log(`   1. Go to Admin Dashboard → Customer Management`);
      console.log(`   2. Click on "Pending Rosters" or "Trips"`);
      console.log(`   3. Select the trips you want to assign`);
      console.log(`   4. Click "Route Optimization"`);
      console.log(`   5. Choose a vehicle from the list`);
      console.log(`   6. Confirm the assignment`);
      console.log(``);
      console.log(`   This will populate the vehicleId, vehicleNumber,`);
      console.log(`   driverId, and driverName fields in the database.`);
    } else if (emptyCount > 0) {
      console.log(`⚠️  PARTIAL PROBLEM`);
      console.log(`   ${emptyCount} out of ${assignedTrips.length} trips are missing vehicle/driver data.`);
    } else {
      console.log(`✅ All trips have vehicle and driver data!`);
      console.log(`   The problem might be in the frontend display logic.`);
    }
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    
    if (error.message.includes('ECONNREFUSED')) {
      console.log('\n💡 MongoDB is not running!');
      console.log('   Please start MongoDB service first.');
      console.log('   Windows: net start MongoDB');
      console.log('   Mac: brew services start mongodb-community');
      console.log('   Linux: sudo systemctl start mongod');
    }
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

diagnose();
