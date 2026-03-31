// Quick fix to reset roster statuses to pending
const { MongoClient } = require('mongodb');

async function resetRosterStatus() {
  const client = new MongoClient('mongodb://localhost:27017');
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('🔄 Resetting roster statuses to pending...');
    
    const result = await db.collection('rosters').updateMany(
      { status: 'assigned' },
      { 
        $set: { 
          status: 'pending',
          vehicleId: null,
          vehicleNumber: null,
          driverId: null,
          driverName: null,
          driverPhone: null,
          assignedAt: null,
          assignedBy: null,
          updatedAt: new Date()
        }
      }
    );
    
    console.log(`✅ Updated ${result.modifiedCount} rosters to pending status`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

resetRosterStatus();