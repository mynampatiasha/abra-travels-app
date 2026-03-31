const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkAllTrips() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    // Get all trips
    const trips = await db.collection('trips').find({}).limit(10).toArray();
    
    console.log(`📋 Found ${trips.length} trips:`);
    trips.forEach((trip, index) => {
      console.log(`\n${index + 1}. Trip:`);
      console.log(`   _id: ${trip._id}`);
      console.log(`   tripId: ${trip.tripId}`);
      console.log(`   tripNumber: ${trip.tripNumber}`);
      console.log(`   customer: ${trip.customerEmail || trip.customer?.email}`);
      console.log(`   status: ${trip.status}`);
    });
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkAllTrips();