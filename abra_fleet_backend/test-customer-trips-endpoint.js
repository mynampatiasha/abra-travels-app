require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;

async function testCustomerTripsEndpoint() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Check what trips exist for Priya
    const trips = await db.collection('trips').find({ 
      customerEmail: 'priya.sharma@infosys.com' 
    }).toArray();
    
    console.log('\n🚗 Trips in database for priya.sharma@infosys.com:', trips.length);
    
    if (trips.length > 0) {
      trips.forEach((trip, i) => {
        console.log(`\n${i + 1}. Trip:`);
        console.log('   _id:', trip._id);
        console.log('   tripId:', trip.tripId);
        console.log('   customerEmail:', trip.customerEmail);
        console.log('   customerUid:', trip.customerUid);
        console.log('   status:', trip.status);
        console.log('   vehicleNumber:', trip.vehicleNumber);
        console.log('   driverName:', trip.driverName);
        console.log('   pickupLocation:', trip.pickupLocation);
        console.log('   dropLocation:', trip.dropLocation);
      });
    }
    
    // Check rosters too
    const rosters = await db.collection('rosters').find({ 
      customerEmail: 'priya.sharma@infosys.com' 
    }).toArray();
    
    console.log('\n📋 Rosters in database for priya.sharma@infosys.com:', rosters.length);
    
    if (rosters.length > 0) {
      rosters.forEach((roster, i) => {
        console.log(`\n${i + 1}. Roster:`);
        console.log('   _id:', roster._id);
        console.log('   customerEmail:', roster.customerEmail);
        console.log('   status:', roster.status);
        console.log('   vehicleNumber:', roster.vehicleNumber);
      });
    }
    
    console.log('\n💡 The app is calling /api/roster/customer/my-rosters');
    console.log('💡 But trips are in the trips collection, not rosters!');
    console.log('💡 Need to check what endpoint the "My Trips" screen is using');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    process.exit(0);
  }
}

testCustomerTripsEndpoint();
