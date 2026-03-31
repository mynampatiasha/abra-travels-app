// Create sample ratings data for testing
const { MongoClient } = require('mongodb');
require('dotenv').config();

async function createSampleRatingsData() {
  try {
    console.log('🌟 Creating sample ratings data...');
    
    const client = new MongoClient(process.env.MONGODB_URI || 'mongodb://localhost:27017');
    await client.connect();
    const db = client.db(process.env.DB_NAME || 'abra_fleet');
    
    // First, let's check if we have any drivers
    const drivers = await db.collection('drivers').find({}).limit(5).toArray();
    console.log(`📊 Found ${drivers.length} drivers`);
    
    if (drivers.length === 0) {
      console.log('❌ No drivers found. Please add some drivers first.');
      await client.close();
      return;
    }
    
    // Create sample trips with ratings for the first few drivers
    const sampleTrips = [];
    
    for (let i = 0; i < Math.min(3, drivers.length); i++) {
      const driver = drivers[i];
      
      // Create 3-5 completed trips with ratings for each driver
      const numTrips = 3 + Math.floor(Math.random() * 3); // 3-5 trips
      
      for (let j = 0; j < numTrips; j++) {
        const rating = 3 + Math.random() * 2; // Rating between 3.0 and 5.0
        
        const trip = {
          tripId: `TRIP_${Date.now()}_${i}_${j}`,
          driverId: driver.driverId,
          driverName: `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim() || 'Driver',
          customerId: `customer${i + 1}`,
          customerName: `Customer ${i + 1}`,
          status: 'completed',
          rating: Math.round(rating * 10) / 10, // Round to 1 decimal place
          ratingComment: [
            'Great service!',
            'Very professional driver',
            'Safe and comfortable ride',
            'On time pickup',
            'Excellent driving skills'
          ][Math.floor(Math.random() * 5)],
          pickupLocation: {
            address: `Pickup Location ${j + 1}`,
            coordinates: [77.5946 + Math.random() * 0.1, 12.9716 + Math.random() * 0.1]
          },
          dropLocation: {
            address: `Drop Location ${j + 1}`,
            coordinates: [77.5946 + Math.random() * 0.1, 12.9716 + Math.random() * 0.1]
          },
          tripDate: new Date(Date.now() - Math.random() * 30 * 24 * 60 * 60 * 1000), // Random date in last 30 days
          completedAt: new Date(),
          distance: 5 + Math.random() * 20, // 5-25 km
          duration: 15 + Math.random() * 45, // 15-60 minutes
          fare: 100 + Math.random() * 400 // 100-500 rupees
        };
        
        sampleTrips.push(trip);
      }
    }
    
    // Insert the sample trips
    if (sampleTrips.length > 0) {
      await db.collection('trips').insertMany(sampleTrips);
      console.log(`✅ Created ${sampleTrips.length} sample trips with ratings`);
      
      // Show summary
      const driverRatings = {};
      sampleTrips.forEach(trip => {
        if (!driverRatings[trip.driverId]) {
          driverRatings[trip.driverId] = {
            driverName: trip.driverName,
            ratings: [],
            totalRating: 0
          };
        }
        driverRatings[trip.driverId].ratings.push(trip.rating);
        driverRatings[trip.driverId].totalRating += trip.rating;
      });
      
      console.log('\n📈 Sample Ratings Summary:');
      Object.keys(driverRatings).forEach(driverId => {
        const data = driverRatings[driverId];
        const avgRating = (data.totalRating / data.ratings.length).toFixed(1);
        console.log(`   ${data.driverName}: ${avgRating} (${data.ratings.length} ratings)`);
      });
      
    } else {
      console.log('❌ No sample trips created');
    }
    
    await client.close();
    console.log('\n✅ Sample ratings data creation completed!');
    console.log('💡 Now you can test the ratings endpoint');
    
  } catch (error) {
    console.error('❌ Error creating sample ratings data:', error);
  }
}

createSampleRatingsData();