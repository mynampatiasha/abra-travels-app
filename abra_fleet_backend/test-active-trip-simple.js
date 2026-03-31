// Simple test for active-trip endpoint
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.MONGODB_DB_NAME || 'abra_fleet';

async function testEndpoint() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db(DB_NAME);
    
    const userId = 'b5aoloVR7xYI6SICibCIWecBaf82';
    
    console.log('🔍 Testing active-trip logic...\n');
    
    // Simulate what the endpoint does
    const activeTrip = await db.collection('rosters').findOne({
      customerId: userId,
      status: { $in: ['ongoing', 'in_progress', 'started'] }
    });
    
    if (!activeTrip) {
      console.log('❌ No active trip found');
      console.log('\nExpected API Response:');
      console.log(JSON.stringify({
        success: true,
        hasActiveTrip: false,
        trip: null
      }, null, 2));
    } else {
      console.log('✅ Active trip found!');
      console.log(`   ID: ${activeTrip._id}`);
      console.log(`   Status: ${activeTrip.status}`);
      console.log(`   Vehicle: ${activeTrip.vehicleNumber}`);
      console.log(`   Driver: ${activeTrip.driverName}\n`);
      
      console.log('Expected API Response:');
      console.log(JSON.stringify({
        success: true,
        hasActiveTrip: true,
        trip: {
          tripId: activeTrip._id.toString(),
          status: activeTrip.status,
          vehicleNumber: activeTrip.vehicleNumber,
          driverName: activeTrip.driverName
        }
      }, null, 2));
    }
    
    console.log('\n📍 Endpoint URL:');
    console.log(`   GET http://localhost:3000/api/rosters/active-trip/${userId}`);
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

testEndpoint();
