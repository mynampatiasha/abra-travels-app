// check-roster-trip-relationship.js
// Check how rosters and trips are related in the database

const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkRosterTripRelationship() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    console.log('\n' + '='.repeat(80));
    console.log('CHECKING ROSTER-TRIP RELATIONSHIP');
    console.log('='.repeat(80));
    
    // Check rosters collection
    console.log('\n📋 ROSTERS COLLECTION:');
    console.log('-'.repeat(80));
    
    const totalRosters = await db.collection('rosters').countDocuments();
    console.log(`Total rosters: ${totalRosters}`);
    
    const rostersByStatus = await db.collection('rosters').aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 }
        }
      },
      { $sort: { count: -1 } }
    ]).toArray();
    
    console.log('\nRosters by status:');
    rostersByStatus.forEach(item => {
      console.log(`  ${item._id || 'null'}: ${item.count}`);
    });
    
    // Sample roster
    const sampleRoster = await db.collection('rosters').findOne({});
    if (sampleRoster) {
      console.log('\nSample roster structure:');
      console.log(JSON.stringify(sampleRoster, null, 2));
    }
    
    // Check trips collection
    console.log('\n\n🚗 TRIPS COLLECTION:');
    console.log('-'.repeat(80));
    
    const totalTrips = await db.collection('trips').countDocuments();
    console.log(`Total trips: ${totalTrips}`);
    
    const tripsByStatus = await db.collection('trips').aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 }
        }
      },
      { $sort: { count: -1 } }
    ]).toArray();
    
    console.log('\nTrips by status:');
    tripsByStatus.forEach(item => {
      console.log(`  ${item._id || 'null'}: ${item.count}`);
    });
    
    // Sample trip
    const sampleTrip = await db.collection('trips').findOne({});
    if (sampleTrip) {
      console.log('\nSample trip structure:');
      console.log(JSON.stringify(sampleTrip, null, 2));
    }
    
    // Check for rosterId field in trips
    console.log('\n\n🔗 RELATIONSHIP CHECK:');
    console.log('-'.repeat(80));
    
    const tripsWithRosterId = await db.collection('trips').countDocuments({
      rosterId: { $exists: true, $ne: null }
    });
    
    console.log(`Trips with rosterId field: ${tripsWithRosterId} / ${totalTrips}`);
    
    if (tripsWithRosterId > 0) {
      const tripWithRoster = await db.collection('trips').findOne({
        rosterId: { $exists: true, $ne: null }
      });
      
      console.log('\nSample trip with rosterId:');
      console.log(`  Trip ID: ${tripWithRoster._id}`);
      console.log(`  Roster ID: ${tripWithRoster.rosterId}`);
      console.log(`  Status: ${tripWithRoster.status}`);
      
      // Try to find the corresponding roster
      const correspondingRoster = await db.collection('rosters').findOne({
        _id: new ObjectId(tripWithRoster.rosterId)
      });
      
      if (correspondingRoster) {
        console.log('\n  ✅ Found corresponding roster:');
        console.log(`     Roster ID: ${correspondingRoster._id}`);
        console.log(`     Status: ${correspondingRoster.status}`);
        console.log(`     Customer: ${correspondingRoster.customerName}`);
      } else {
        console.log('\n  ❌ No corresponding roster found');
      }
    }
    
    // Check for tripId field in rosters
    const rostersWithTripId = await db.collection('rosters').countDocuments({
      tripId: { $exists: true, $ne: null }
    });
    
    console.log(`\nRosters with tripId field: ${rostersWithTripId} / ${totalRosters}`);
    
    if (rostersWithTripId > 0) {
      const rosterWithTrip = await db.collection('rosters').findOne({
        tripId: { $exists: true, $ne: null }
      });
      
      console.log('\nSample roster with tripId:');
      console.log(`  Roster ID: ${rosterWithTrip._id}`);
      console.log(`  Trip ID: ${rosterWithTrip.tripId}`);
      console.log(`  Status: ${rosterWithTrip.status}`);
    }
    
    // Check assigned rosters
    console.log('\n\n📊 ASSIGNED ROSTERS:');
    console.log('-'.repeat(80));
    
    const assignedRosters = await db.collection('rosters').find({
      status: 'assigned',
      driverId: { $exists: true, $ne: null }
    }).limit(5).toArray();
    
    console.log(`Found ${assignedRosters.length} assigned rosters (showing first 5):`);
    
    assignedRosters.forEach((roster, index) => {
      console.log(`\n${index + 1}. Roster ${roster._id}:`);
      console.log(`   Customer: ${roster.customerName || 'Unknown'}`);
      console.log(`   Driver ID: ${roster.driverId || 'None'}`);
      console.log(`   Vehicle ID: ${roster.vehicleId || 'None'}`);
      console.log(`   Status: ${roster.status}`);
      console.log(`   Has tripId: ${roster.tripId ? 'Yes' : 'No'}`);
      console.log(`   Assigned at: ${roster.assignedAt || 'Unknown'}`);
    });
    
    // Summary
    console.log('\n\n' + '='.repeat(80));
    console.log('SUMMARY');
    console.log('='.repeat(80));
    console.log(`Total rosters: ${totalRosters}`);
    console.log(`Total trips: ${totalTrips}`);
    console.log(`Trips linked to rosters: ${tripsWithRosterId}`);
    console.log(`Rosters linked to trips: ${rostersWithTripId}`);
    
    if (totalTrips === 0 && totalRosters > 0) {
      console.log('\n⚠️  NO TRIPS FOUND!');
      console.log('   Trips are NOT automatically created from rosters.');
      console.log('   Trips need to be created separately or through a specific workflow.');
    } else if (tripsWithRosterId === 0 && rostersWithTripId === 0) {
      console.log('\n⚠️  NO RELATIONSHIP FOUND!');
      console.log('   Rosters and trips are stored separately.');
      console.log('   There is no automatic linking between them.');
    } else {
      console.log('\n✅ RELATIONSHIP EXISTS!');
      console.log('   Some rosters and trips are linked.');
    }
    
    console.log('='.repeat(80) + '\n');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('✅ Connection closed');
  }
}

checkRosterTripRelationship();
