const { MongoClient } = require('mongodb');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function resetRosterAssignments() {
  const mongoUri = process.env.MONGODB_URI;
  
  if (!mongoUri) {
    console.error('❌ MONGODB_URI not found');
    return;
  }
  
  const client = new MongoClient(mongoUri);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('Resetting all assigned rosters...\n');
    
    const result = await db.collection('rosters').updateMany(
      { status: { $in: ['assigned', 'in_progress', 'active', 'scheduled'] } },
      {
        $set: {
          status: 'pending_assignment',
          assignedVehicle: null,
          assignedDriver: null,
          pickupTime: null,
          dropoffTime: null,
          routeId: null,
          updatedAt: new Date()
        }
      }
    );
    
    console.log(`✅ Reset ${result.modifiedCount} rosters to pending_assignment`);
    
    // Step 2: Clear assignedCustomers array from all vehicles
    console.log('\nClearing assignedCustomers from vehicles...');
    
    const vehicleResult = await db.collection('vehicles').updateMany(
      {},
      {
        $set: {
          assignedCustomers: []
        }
      }
    );
    
    console.log(`✅ Cleared assignedCustomers from ${vehicleResult.modifiedCount} vehicles`);
    console.log('\nAll vehicle seats are now available.\n');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

resetRosterAssignments();
