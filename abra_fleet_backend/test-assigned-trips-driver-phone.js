const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet';

async function testAssignedTripsDriverPhone() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(DB_NAME);
    
    // Get assigned rosters
    console.log('📋 Fetching assigned rosters from database...\n');
    const rosters = await db.collection('rosters')
      .find({ status: 'assigned' })
      .limit(5)
      .toArray();
    
    console.log(`Found ${rosters.length} assigned rosters\n`);
    console.log('='.repeat(80));
    
    rosters.forEach((roster, index) => {
      console.log(`\n${index + 1}. Roster ID: ${roster._id}`);
      console.log(`   Customer: ${roster.customerName || 'Unknown'}`);
      console.log(`   Status: ${roster.status}`);
      console.log(`   Vehicle Number: ${roster.vehicleNumber || 'Not set'}`);
      console.log(`   Driver Name: ${roster.driverName || 'Not set'}`);
      console.log(`   Driver Phone: ${roster.driverPhone || 'NOT SET ❌'}`);
      console.log(`   Assigned At: ${roster.assignedAt || 'Not set'}`);
    });
    
    console.log('\n' + '='.repeat(80));
    console.log('\n✅ Test complete!');
    console.log('\nExpected behavior:');
    console.log('- All assigned rosters should have driverPhone field');
    console.log('- Driver phone should be like: 9123456789');
    console.log('\nTo test the API endpoint:');
    console.log('1. Start the backend: node index.js');
    console.log('2. Make a GET request to: http://localhost:3000/api/rosters/admin/assigned-trips');
    console.log('3. Check that each trip has "driverPhone" field in the response');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

testAssignedTripsDriverPhone();
