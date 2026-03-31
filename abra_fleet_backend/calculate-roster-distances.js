// Calculate and update distances for rosters assigned to drivertest
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI;

// Haversine formula to calculate distance between two coordinates
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Radius of Earth in kilometers
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = 
    Math.sin(dLat/2) * Math.sin(dLat/2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon/2) * Math.sin(dLon/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  const distance = R * c;
  return distance;
}

async function calculateRosterDistances() {
  const client = new MongoClient(MONGODB_URI);

  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');

    const db = client.db('abra_fleet');
    const rostersCollection = db.collection('rosters');

    // Find all rosters for drivertest (DRV-852306)
    const rosters = await rostersCollection.find({
      driverId: 'DRV-852306'
    }).toArray();

    console.log(`\n📋 Found ${rosters.length} rosters for DRV-852306\n`);

    for (const roster of rosters) {
      console.log(`\n🔍 Processing roster for ${roster.customerName}:`);
      console.log(`   Roster ID: ${roster._id}`);

      // Extract coordinates - support multiple field formats
      let pickupLat, pickupLon, dropLat, dropLon;

      // Try direct latitude/longitude fields first (most common)
      if (roster.pickupLatitude && roster.pickupLongitude) {
        pickupLat = roster.pickupLatitude;
        pickupLon = roster.pickupLongitude;
      } else if (roster.pickupCoordinates) {
        pickupLat = roster.pickupCoordinates.latitude;
        pickupLon = roster.pickupCoordinates.longitude;
      } else if (roster.locations?.loginPickup?.coordinates) {
        pickupLat = roster.locations.loginPickup.coordinates.latitude;
        pickupLon = roster.locations.loginPickup.coordinates.longitude;
      } else if (roster.locations?.pickup?.coordinates) {
        pickupLat = roster.locations.pickup.coordinates.latitude;
        pickupLon = roster.locations.pickup.coordinates.longitude;
      }

      // Try direct latitude/longitude fields first (most common)
      if (roster.dropLatitude && roster.dropLongitude) {
        dropLat = roster.dropLatitude;
        dropLon = roster.dropLongitude;
      } else if (roster.dropCoordinates) {
        dropLat = roster.dropCoordinates.latitude;
        dropLon = roster.dropCoordinates.longitude;
      } else if (roster.locations?.logoutDrop?.coordinates) {
        dropLat = roster.locations.logoutDrop.coordinates.latitude;
        dropLon = roster.locations.logoutDrop.coordinates.longitude;
      } else if (roster.locations?.drop?.coordinates) {
        dropLat = roster.locations.drop.coordinates.latitude;
        dropLon = roster.locations.drop.coordinates.longitude;
      }

      console.log(`   Pickup: ${pickupLat}, ${pickupLon}`);
      console.log(`   Drop: ${dropLat}, ${dropLon}`);

      if (pickupLat && pickupLon && dropLat && dropLon) {
        // Calculate distance
        const distance = calculateDistance(pickupLat, pickupLon, dropLat, dropLon);
        const roundedDistance = Math.round(distance * 10) / 10; // Round to 1 decimal

        console.log(`   ✅ Calculated distance: ${roundedDistance} KM`);

        // Update roster with distance
        await rostersCollection.updateOne(
          { _id: roster._id },
          { 
            $set: { 
              distance: roundedDistance,
              estimatedDuration: Math.round(distance * 3) // Rough estimate: 3 minutes per km
            } 
          }
        );

        console.log(`   ✅ Updated roster with distance: ${roundedDistance} KM`);
      } else {
        console.log(`   ⚠️  Missing coordinates, cannot calculate distance`);
        console.log(`   Pickup coords: ${pickupLat ? 'Found' : 'Missing'}`);
        console.log(`   Drop coords: ${dropLat ? 'Found' : 'Missing'}`);
      }
    }

    console.log('\n✅ Distance calculation complete!');
    console.log('\n📊 Summary:');
    
    // Show updated rosters
    const updatedRosters = await rostersCollection.find({
      driverId: 'DRV-852306'
    }).toArray();

    for (const roster of updatedRosters) {
      console.log(`\n${roster.customerName}:`);
      console.log(`  Distance: ${roster.distance || 0} KM`);
      console.log(`  Duration: ${roster.estimatedDuration || 0} minutes`);
      console.log(`  Pickup: ${roster.pickupLocation || 'N/A'}`);
      console.log(`  Drop: ${roster.dropLocation || roster.officeLocation || 'N/A'}`);
    }

  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

calculateRosterDistances();
