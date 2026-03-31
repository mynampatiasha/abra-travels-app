const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkTripExists() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    // Check if the trip exists
    const trip = await db.collection('trips').findOne({
      $or: [
        { _id: 'trip_VSCJkbM0AEhupcIMsCXJr3oFeYo1' },
        { tripId: 'trip_VSCJkbM0AEhupcIMsCXJr3oFeYo1' },
        { tripNumber: 'trip_VSCJkbM0AEhupcIMsCXJr3oFeYo1' }
      ]
    });
    
    if (trip) {
      console.log('✅ Trip found:', {
        _id: trip._id,
        tripId: trip.tripId,
        tripNumber: trip.tripNumber,
        status: trip.status,
        driverId: trip.driverId,
        currentLocation: trip.currentLocation
      });
    } else {
      console.log('❌ Trip not found with ID: trip_VSCJkbM0AEhupcIMsCXJr3oFeYo1');
      
      // Let's see what trips exist for priya.sharma
      const userTrips = await db.collection('trips').find({
        'customer.email': 'priya.sharma@infosys.com'
      }).limit(5).toArray();
      
      console.log('\n📋 Available trips for priya.sharma@infosys.com:');
      userTrips.forEach(trip => {
        console.log(`- ID: ${trip._id}, tripId: ${trip.tripId}, tripNumber: ${trip.tripNumber}, status: ${trip.status}`);
      });
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkTripExists();