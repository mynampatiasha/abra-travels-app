require('dotenv').config();
const { MongoClient, ObjectId } = require('mongodb');

const MONGO_URI = process.env.MONGO_URI;

async function checkRoster() {
  const client = new MongoClient(MONGO_URI);

  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');

    const db = client.db('abrafleet');

    // The roster ID from the logs
    const rosterId = '694a8a867dad313c6ad8b9a1';

    const roster = await db.collection('rosters').findOne({
      _id: new ObjectId(rosterId)
    });

    if (!roster) {
      console.log('❌ Roster not found!');
      return;
    }

    console.log('📋 ROSTER DETAILS:');
    console.log('================================================================================');
    console.log(`ID: ${roster._id}`);
    console.log(`Customer: ${roster.customerName || 'N/A'}`);
    console.log(`Email: ${roster.customerEmail || 'N/A'}`);
    console.log(`Status: ${roster.status}`);
    console.log(`Vehicle ID: ${roster.vehicleId || 'NONE'}`);
    console.log(`Driver ID: ${roster.driverId || 'NONE'}`);
    console.log(`Created: ${roster.createdAt}`);
    console.log(`Updated: ${roster.updatedAt}`);
    console.log('================================================================================\n');

    // Check if it matches our query
    const matchesStatus = ['pending_assignment', 'pending'].includes(roster.status);
    const hasNoVehicle = !roster.vehicleId || roster.vehicleId === null || roster.vehicleId === '';
    const hasNoDriver = !roster.driverId || roster.driverId === null || roster.driverId === '';

    console.log('🔍 QUERY MATCH ANALYSIS:');
    console.log(`✓ Status matches ['pending_assignment', 'pending']: ${matchesStatus ? '✅ YES' : '❌ NO'}`);
    console.log(`✓ No vehicle assigned: ${hasNoVehicle ? '✅ YES' : '❌ NO'}`);
    console.log(`✓ No driver assigned: ${hasNoDriver ? '✅ YES' : '❌ NO'}`);
    console.log(`\n🎯 WOULD MATCH QUERY: ${(matchesStatus && hasNoVehicle && hasNoDriver) ? '✅ YES' : '❌ NO'}\n`);

    if (!matchesStatus) {
      console.log(`⚠️  PROBLEM: Roster status is '${roster.status}', not 'pending_assignment' or 'pending'`);
    }
    if (!hasNoVehicle) {
      console.log(`⚠️  PROBLEM: Roster already has vehicleId: ${roster.vehicleId}`);
    }
    if (!hasNoDriver) {
      console.log(`⚠️  PROBLEM: Roster already has driverId: ${roster.driverId}`);
    }

  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkRoster();