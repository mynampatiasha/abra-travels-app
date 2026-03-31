// Script to add test location coordinates to existing rosters
const { MongoClient, ObjectId } = require('mongodb');

const MONGODB_URI = 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet_management';

// Test locations in Bangalore
const testLocations = [
  {
    name: 'Koramangala',
    coordinates: { latitude: 12.9352, longitude: 77.6245 },
    address: 'Koramangala, Bangalore, Karnataka, India'
  },
  {
    name: 'Electronic City',
    coordinates: { latitude: 12.8456, longitude: 77.6603 },
    address: 'Electronic City, Bangalore, Karnataka, India'
  },
  {
    name: 'Whitefield',
    coordinates: { latitude: 12.9698, longitude: 77.7499 },
    address: 'Whitefield, Bangalore, Karnataka, India'
  },
  {
    name: 'Indiranagar',
    coordinates: { latitude: 12.9716, longitude: 77.6412 },
    address: 'Indiranagar, Bangalore, Karnataka, India'
  },
  {
    name: 'BTM Layout',
    coordinates: { latitude: 12.9165, longitude: 77.6101 },
    address: 'BTM Layout, Bangalore, Karnataka, India'
  }
];

async function addTestLocations() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db(DB_NAME);
    const rostersCollection = db.collection('rosters');
    
    // Get rosters without location coordinates
    const rosters = await rostersCollection.find({
      status: { $in: ['pending_assignment', 'pending', 'created'] },
      'locations.pickup.coordinates': { $exists: false }
    }).limit(10).toArray();
    
    console.log(`\n📊 Found ${rosters.length} rosters without coordinates`);
    
    if (rosters.length === 0) {
      console.log('✅ All rosters already have coordinates!');
      return;
    }
    
    console.log('\n🔧 Adding test coordinates...');
    
    for (let i = 0; i < rosters.length; i++) {
      const roster = rosters[i];
      const testLocation = testLocations[i % testLocations.length];
      
      console.log(`\n${i + 1}. ${roster.customerName || 'Unknown Customer'}`);
      console.log(`   Adding location: ${testLocation.name}`);
      console.log(`   Coordinates: ${testLocation.coordinates.latitude}, ${testLocation.coordinates.longitude}`);
      
      // Update roster with location data
      const updateData = {
        $set: {
          locations: {
            pickup: {
              coordinates: testLocation.coordinates,
              address: testLocation.address,
              timestamp: new Date()
            }
          },
          // Also add array format for compatibility
          loginPickupLocation: [testLocation.coordinates.latitude, testLocation.coordinates.longitude],
          loginPickupAddress: testLocation.address,
          updatedAt: new Date()
        }
      };
      
      // If it's a 'both' type roster, add drop location too
      if (roster.rosterType === 'both') {
        const dropLocation = testLocations[(i + 1) % testLocations.length];
        updateData.$set.locations.drop = {
          coordinates: dropLocation.coordinates,
          address: dropLocation.address,
          timestamp: new Date()
        };
        updateData.$set.logoutDropLocation = [dropLocation.coordinates.latitude, dropLocation.coordinates.longitude];
        updateData.$set.logoutDropAddress = dropLocation.address;
        
        console.log(`   Drop location: ${dropLocation.name}`);
        console.log(`   Drop coordinates: ${dropLocation.coordinates.latitude}, ${dropLocation.coordinates.longitude}`);
      }
      
      const result = await rostersCollection.updateOne(
        { _id: roster._id },
        updateData
      );
      
      if (result.modifiedCount > 0) {
        console.log(`   ✅ Updated successfully`);
      } else {
        console.log(`   ❌ Update failed`);
      }
    }
    
    console.log('\n🎉 Test location data added successfully!');
    console.log('\n💡 Now you can test route optimization with real coordinates.');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

// Only run if MongoDB is available
addTestLocations().catch(err => {
  if (err.message.includes('ECONNREFUSED')) {
    console.log('⚠️  MongoDB is not running. Please start MongoDB first.');
    console.log('   Then run: node add-test-locations.js');
  } else {
    console.error('❌ Error:', err.message);
  }
});