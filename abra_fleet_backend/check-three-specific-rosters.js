const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;

async function checkThreeRosters() {
  const client = new MongoClient(uri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abra_fleet');
    
    // The 3 specific roster IDs you're trying to assign
    const rosterIds = [
      '693fcc67c3a6100b317028cd', // Rajesh Kumar
      '693fcc6bc3a6100b317028ce', // Priya Sharma
      '693fcc6fc3a6100b317028cf'  // Amit Patel
    ];
    
    console.log('🔍 Checking the 3 rosters you tried to assign in AUTO MODE:\n');
    console.log('='.repeat(80));
    
    for (const rosterId of rosterIds) {
      const roster = await db.collection('rosters').findOne({ _id: new ObjectId(rosterId) });
      
      if (roster) {
        console.log(`\n📋 Roster: ${roster.customerName}`);
        console.log(`   ID: ${rosterId}`);
        console.log(`   📊 Status: ${roster.status}`);
        console.log(`   📧 Email: ${roster.customerEmail || 'N/A'}`);
        console.log(`   🚗 Vehicle ID: ${roster.vehicleId || 'NOT ASSIGNED'}`);
        console.log(`   🚗 Vehicle Number: ${roster.vehicleNumber || 'NOT ASSIGNED'}`);
        console.log(`   👨‍✈️ Driver ID: ${roster.driverId || 'NOT ASSIGNED'}`);
        console.log(`   👨‍✈️ Driver Name: ${roster.driverName || 'NOT ASSIGNED'}`);
        console.log(`   📅 Assigned At: ${roster.assignedAt || 'NOT ASSIGNED'}`);
        console.log(`   🔢 Pickup Sequence: ${roster.pickupSequence || 'N/A'}`);
        
        if (roster.status === 'assigned') {
          console.log(`\n   ✅ THIS ROSTER IS ALREADY ASSIGNED!`);
          console.log(`   ⚠️  That's why auto mode shows "0 customers assigned"`);
          console.log(`   ⚠️  The backend query excludes rosters with status='assigned'`);
        } else {
          console.log(`\n   ❌ Status is: ${roster.status}`);
        }
      } else {
        console.log(`\n❌ Roster ID ${rosterId} NOT FOUND`);
      }
      console.log('='.repeat(80));
    }
    
    console.log('\n💡 EXPLANATION:');
    console.log('   The backend query in route_optimization_router.js line 1208:');
    console.log('   ');
    console.log('   { _id: ObjectId(rosterId), status: { $nin: ["assigned", "completed", ...] } }');
    console.log('   ');
    console.log('   This query EXCLUDES rosters that already have status="assigned"');
    console.log('   Since these 3 rosters are already assigned, the query finds nothing.');
    console.log('   Result: "Successfully assigned 0 customers"');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkThreeRosters();
