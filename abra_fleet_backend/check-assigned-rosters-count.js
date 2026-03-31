const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const uri = process.env.MONGODB_URI;

async function checkAssignedRosters() {
  const client = new MongoClient(uri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('abraFleet');
    
    // The 3 specific roster IDs from the context
    const rosterIds = [
      '693fcc6fc3a6100b317028cf', // Amit Patel
      '693fcc6bc3a6100b317028ce', // Priya Sharma
      '693fcc67c3a6100b317028cd'  // Rajesh Kumar
    ];
    
    console.log('🔍 Checking specific rosters from auto mode assignment:\n');
    console.log('='.repeat(80));
    
    for (const rosterId of rosterIds) {
      const roster = await db.collection('rosters').findOne({ _id: new ObjectId(rosterId) });
      
      if (roster) {
        console.log(`\n📋 Roster ID: ${rosterId}`);
        console.log(`   👤 Customer: ${roster.customerName || 'Unknown'}`);
        console.log(`   📊 Status: ${roster.status}`);
        console.log(`   🚗 Vehicle ID: ${roster.vehicleId || 'NOT ASSIGNED'}`);
        console.log(`   🚗 Vehicle Number: ${roster.vehicleNumber || 'NOT ASSIGNED'}`);
        console.log(`   👨‍✈️ Driver ID: ${roster.driverId || 'NOT ASSIGNED'}`);
        console.log(`   👨‍✈️ Driver Name: ${roster.driverName || 'NOT ASSIGNED'}`);
        console.log(`   📅 Assigned At: ${roster.assignedAt || 'NOT ASSIGNED'}`);
        console.log(`   🔢 Pickup Sequence: ${roster.pickupSequence || 'N/A'}`);
        console.log(`   ⏰ Optimized Pickup Time: ${roster.optimizedPickupTime || 'N/A'}`);
        
        if (roster.status === 'assigned') {
          console.log(`   ✅ THIS ROSTER IS ASSIGNED!`);
        } else {
          console.log(`   ❌ THIS ROSTER IS NOT ASSIGNED (status: ${roster.status})`);
        }
      } else {
        console.log(`\n❌ Roster ID ${rosterId} NOT FOUND in database`);
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('\n📊 OVERALL STATISTICS:\n');
    
    // Count all rosters by status
    const statusCounts = await db.collection('rosters').aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 }
        }
      },
      {
        $sort: { count: -1 }
      }
    ]).toArray();
    
    console.log('All rosters by status:');
    statusCounts.forEach(stat => {
      console.log(`   ${stat._id}: ${stat.count}`);
    });
    
    // Count recently assigned rosters (last 10 minutes)
    const tenMinutesAgo = new Date(Date.now() - 10 * 60 * 1000);
    const recentlyAssigned = await db.collection('rosters').countDocuments({
      status: 'assigned',
      assignedAt: { $gte: tenMinutesAgo }
    });
    
    console.log(`\n⏰ Recently assigned (last 10 minutes): ${recentlyAssigned}`);
    
    // Show the most recently assigned rosters
    const latestAssignments = await db.collection('rosters').find({
      status: 'assigned'
    }).sort({ assignedAt: -1 }).limit(5).toArray();
    
    if (latestAssignments.length > 0) {
      console.log('\n📋 Latest 5 assigned rosters:');
      latestAssignments.forEach((roster, index) => {
        console.log(`\n   ${index + 1}. ${roster.customerName}`);
        console.log(`      ID: ${roster._id}`);
        console.log(`      Vehicle: ${roster.vehicleNumber || 'Unknown'}`);
        console.log(`      Driver: ${roster.driverName || 'Unknown'}`);
        console.log(`      Assigned: ${roster.assignedAt}`);
      });
    }
    
    console.log('\n' + '='.repeat(80));
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkAssignedRosters();
