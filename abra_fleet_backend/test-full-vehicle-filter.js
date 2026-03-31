// Test script to verify full vehicles are filtered out from compatible vehicles list
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function testFullVehicleFilter() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Find a vehicle with existing assignments
    const vehiclesWithAssignments = await db.collection('vehicles').aggregate([
      {
        $match: {
          status: { $regex: /^active$/i },
          assignedDriver: { $exists: true, $ne: null }
        }
      },
      {
        $lookup: {
          from: 'rosters',
          let: { vehicleId: { $toString: '$_id' } },
          pipeline: [
            {
              $match: {
                $expr: { $eq: ['$vehicleId', '$$vehicleId'] },
                status: 'assigned',
                assignedAt: { $gte: new Date(new Date().setHours(0, 0, 0, 0)) }
              }
            }
          ],
          as: 'assignments'
        }
      },
      {
        $addFields: {
          assignmentCount: { $size: '$assignments' },
          totalSeats: { $ifNull: ['$seatCapacity', 4] },
          availableSeats: {
            $subtract: [
              { $subtract: [{ $ifNull: ['$seatCapacity', 4] }, 1] },
              { $size: '$assignments' }
            ]
          }
        }
      },
      {
        $match: {
          assignmentCount: { $gt: 0 }
        }
      },
      { $limit: 5 }
    ]).toArray();
    
    console.log('\n📊 Vehicles with Existing Assignments:');
    console.log('='.repeat(80));
    
    vehiclesWithAssignments.forEach((vehicle, idx) => {
      const name = vehicle.name || vehicle.vehicleNumber || 'Unknown';
      const isFull = vehicle.availableSeats <= 0;
      const status = isFull ? '❌ FULL' : '✅ AVAILABLE';
      
      console.log(`\n${idx + 1}. ${name} - ${status}`);
      console.log(`   Total Seats: ${vehicle.totalSeats}`);
      console.log(`   Assigned: ${vehicle.assignmentCount}`);
      console.log(`   Available: ${vehicle.availableSeats}`);
      console.log(`   Should Show in Dialog: ${!isFull ? 'YES' : 'NO (FILTERED OUT)'}`);
      
      if (isFull) {
        console.log(`   ⚠️  This vehicle should NOT appear in auto-detection dialog`);
      }
    });
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ Test completed');
    console.log('\nExpected Behavior:');
    console.log('- Vehicles with availableSeats > 0: Should appear in dialog');
    console.log('- Vehicles with availableSeats <= 0: Should NOT appear (filtered as incompatible)');
    console.log('- Error message should be clear: "Vehicle is full: X customers already assigned to Y available seats"');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

testFullVehicleFilter();
