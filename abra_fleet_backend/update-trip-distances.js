const { MongoClient } = require('mongodb');

const MONGODB_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function updateTripDistances() {
  let client;
  
  try {
    console.log('='.repeat(60));
    console.log('UPDATING TRIP DISTANCES FOR CUSTOMER123');
    console.log('='.repeat(60));

    // Connect to MongoDB
    console.log('\n1. Connecting to MongoDB...');
    client = new MongoClient(MONGODB_URI);
    await client.connect();
    const db = client.db('abra_fleet');
    console.log('✓ Connected to MongoDB');

    const customerUID = 'b5aoloVR7xYI6SICibCIWecBaf82';
    
    // Get all trips for customer123
    console.log('\n2. Getting trips for customer123...');
    const trips = await db.collection('trips').find({ customerId: customerUID }).toArray();
    console.log(`✓ Found ${trips.length} trips`);

    // Update each trip with realistic distance values
    console.log('\n3. Updating trip distances...');
    let totalUpdated = 0;
    
    for (const trip of trips) {
      // Generate realistic distance between 12-25 km for Bangalore routes
      const baseDistance = 15.5; // Base distance
      const variation = (Math.random() - 0.5) * 10; // ±5 km variation
      const distance = Math.max(8, Math.min(30, baseDistance + variation)); // Between 8-30 km
      
      // For completed trips, use actualDistance; for others use estimated distance
      const updateData = {
        distance: Math.round(distance * 10) / 10, // Round to 1 decimal
        estimatedDistance: Math.round(distance * 10) / 10
      };
      
      if (trip.status === 'completed') {
        // Add slight variation for actual distance (usually slightly different from estimated)
        const actualVariation = (Math.random() - 0.5) * 2; // ±1 km variation
        updateData.actualDistance = Math.round((distance + actualVariation) * 10) / 10;
      }
      
      await db.collection('trips').updateOne(
        { _id: trip._id },
        { $set: updateData }
      );
      
      totalUpdated++;
    }

    console.log(`✓ Updated ${totalUpdated} trips with distance data`);

    // Verify the total distance
    console.log('\n4. Calculating total distance...');
    const updatedTrips = await db.collection('trips').find({ 
      customerId: customerUID,
      status: 'completed' 
    }).toArray();
    
    let totalDistance = 0;
    updatedTrips.forEach(trip => {
      if (trip.actualDistance) {
        totalDistance += trip.actualDistance;
      } else if (trip.distance) {
        totalDistance += trip.distance;
      }
    });
    
    console.log(`✓ Total distance for completed trips: ${Math.round(totalDistance * 10) / 10} km`);
    console.log(`✓ Average distance per trip: ${Math.round((totalDistance / updatedTrips.length) * 10) / 10} km`);

    console.log('\n' + '='.repeat(60));
    console.log('✅ TRIP DISTANCES UPDATED SUCCESSFULLY!');
    console.log('='.repeat(60));
    console.log(`Customer123 now has realistic distance data for ${trips.length} trips`);
    console.log(`Total distance traveled: ${Math.round(totalDistance * 10) / 10} km`);

  } catch (error) {
    console.error('\n' + '='.repeat(60));
    console.error('❌ ERROR UPDATING TRIP DISTANCES:');
    console.error('='.repeat(60));
    console.error(error.message);
    console.error(error.stack);
  } finally {
    if (client) {
      await client.close();
    }
    process.exit(0);
  }
}

updateTripDistances();