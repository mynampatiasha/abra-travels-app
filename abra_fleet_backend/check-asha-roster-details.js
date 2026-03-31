// check-asha-roster-details.js
// Check the full details of Asha's assigned roster

const { MongoClient, ObjectId } = require('mongodb');

const MONGO_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
const DB_NAME = 'abra_fleet';

async function checkRosterDetails() {
  const client = new MongoClient(MONGO_URI);
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🔍 CHECKING ASHA\'S ROSTER DETAILS');
    console.log('='.repeat(80));
    
    await client.connect();
    const db = client.db(DB_NAME);
    
    // Get the assigned roster
    const roster = await db.collection('rosters').findOne({
      _id: new ObjectId('693a57a81f77993e2eb68929')
    });
    
    if (roster) {
      console.log('\n📋 Full Roster Details:');
      console.log(JSON.stringify(roster, null, 2));
      
      console.log('\n' + '='.repeat(80));
      console.log('🔍 ANALYSIS');
      console.log('='.repeat(80));
      
      console.log(`\nStatus: ${roster.status}`);
      console.log(`Assigned Driver: ${JSON.stringify(roster.assignedDriver)}`);
      console.log(`Assigned Vehicle: ${JSON.stringify(roster.assignedVehicle)}`);
      
      if (roster.status === 'assigned' && (!roster.assignedDriver || !roster.assignedVehicle)) {
        console.log('\n⚠️  PROBLEM IDENTIFIED:');
        console.log('   The roster status is "assigned" but no driver/vehicle is actually assigned!');
        console.log('   This means the roster was marked as assigned without going through');
        console.log('   the proper route optimization flow that sends notifications.');
        console.log('\n   SOLUTION:');
        console.log('   1. Admin should use "Optimize Route" feature to properly assign');
        console.log('   2. Or we need to manually send a notification now');
      }
    } else {
      console.log('❌ Roster not found!');
    }
    
    // Check recent notifications for route_assignment type
    console.log('\n' + '='.repeat(80));
    console.log('📱 RECENT ROUTE ASSIGNMENT NOTIFICATIONS');
    console.log('='.repeat(80));
    
    const recentNotifications = await db.collection('notifications').find({
      type: { $in: ['route_assignment', 'route_assigned', 'roster_assigned', 'driver_assigned'] }
    }).sort({ createdAt: -1 }).limit(10).toArray();
    
    console.log(`\nFound ${recentNotifications.length} recent route assignment notifications:`);
    recentNotifications.forEach(n => {
      console.log(`\n- ${n.title}`);
      console.log(`  To: ${n.userId}`);
      console.log(`  Type: ${n.type}`);
      console.log(`  Created: ${n.createdAt}`);
      console.log(`  Roster ID in data: ${n.data?.rosterId || 'N/A'}`);
    });
    
    console.log('\n' + '='.repeat(80));
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed\n');
  }
}

checkRosterDetails();
