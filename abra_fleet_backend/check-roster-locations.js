const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkRosterLocations() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('🔍 Checking roster location data...\n');
    
    // Get a few sample rosters to see location format
    const rosters = await db.collection('rosters')
      .find({})
      .limit(3)
      .toArray();
    
    rosters.forEach((roster, index) => {
      console.log(`📋 Roster ${index + 1}:`);
      console.log('  ID:', roster._id);
      console.log('  Customer:', roster.customerName || roster.customerId);
      console.log('  Pickup Location:', roster.pickupLocation);
      console.log('  Drop Location:', roster.dropLocation);
      console.log('  Pickup Coords:', roster.pickupLat, roster.pickupLng);
      console.log('  Drop Coords:', roster.dropLat, roster.dropLng);
      console.log('  Office Location:', roster.officeLocation);
      console.log('  Locations Object:', roster.locations);
      console.log('  ---');
    });
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkRosterLocations();