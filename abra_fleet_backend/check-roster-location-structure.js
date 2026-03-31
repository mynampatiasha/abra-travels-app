// Check the exact structure of roster location data
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI;

async function checkRosterStructure() {
  const client = new MongoClient(MONGODB_URI);

  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');

    const db = client.db('abra_fleet');
    const rostersCollection = db.collection('rosters');

    // Find rosters for drivertest
    const rosters = await rostersCollection.find({
      driverId: 'DRV-852306'
    }).toArray();

    console.log(`\n📋 Found ${rosters.length} rosters for DRV-852306\n`);

    for (const roster of rosters) {
      console.log(`\n${'='.repeat(80)}`);
      console.log(`🔍 ROSTER: ${roster.customerName}`);
      console.log(`${'='.repeat(80)}`);
      console.log('\n📍 LOCATION FIELDS:');
      console.log(JSON.stringify({
        pickupLocation: roster.pickupLocation,
        dropLocation: roster.dropLocation,
        officeLocation: roster.officeLocation,
        pickupCoordinates: roster.pickupCoordinates,
        dropCoordinates: roster.dropCoordinates,
        locations: roster.locations,
        distance: roster.distance,
        estimatedDuration: roster.estimatedDuration
      }, null, 2));
    }

  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkRosterStructure();
