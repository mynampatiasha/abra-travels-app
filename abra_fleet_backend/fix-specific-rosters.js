// Fix the specific rosters that are being used in route optimization
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

// The specific roster IDs from the Flutter log
const specificRosterIds = [
  '69313068276f731cb408687c', // Amit Patel
  '69313060276f731cb4086879', // Sarah Smith  
  '6931305c276f731cb4086878'  // John Doe
];

// Bangalore office locations with coordinates
const officeLocations = {
  'Indiranagar Office Bangalore': { latitude: 12.9784, longitude: 77.6408 },
  'Whitefield Office Bangalore': { latitude: 12.9698, longitude: 77.7500 },
  'Koramangala Office Bangalore': { latitude: 12.9352, longitude: 77.6245 },
  'Electronic City Office Bangalore': { latitude: 12.8456, longitude: 77.6603 },
  'Marathahalli Office Bangalore': { latitude: 12.9591, longitude: 77.6974 },
  'BTM Layout Office Bangalore': { latitude: 12.9165, longitude: 77.6101 },
  'HSR Layout Office Bangalore': { latitude: 12.9116, longitude: 77.6473 },
  'JP Nagar Office Bangalore': { latitude: 12.9082, longitude: 77.5833 },
  'Jayanagar Office Bangalore': { latitude: 12.9279, longitude: 77.5937 },
  'Rajajinagar Office Bangalore': { latitude: 12.9915, longitude: 77.5536 }
};

// Default coordinates for unknown locations (Bangalore city center)
const defaultLocation = { latitude: 12.9716, longitude: 77.5946 };

async function fixSpecificRosters() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    console.log('\n' + '🎯'.repeat(50));
    console.log('FIXING SPECIFIC ROSTERS FOR ROUTE OPTIMIZATION');
    console.log('🎯'.repeat(50));
    
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('\n📋 Fixing specific rosters from Flutter log...');
    console.log('Target roster IDs:');
    specificRosterIds.forEach((id, index) => {
      console.log(`   ${index + 1}. ${id}`);
    });
    
    let fixedCount = 0;
    let errors = [];
    
    for (const rosterId of specificRosterIds) {
      try {
        console.log(`\n🔍 Processing roster: ${rosterId}`);
        
        // Get the roster
        const roster = await db.collection('rosters').findOne({
          _id: new ObjectId(rosterId)
        });
        
        if (!roster) {
          console.log(`   ❌ Roster not found: ${rosterId}`);
          errors.push({ rosterId, error: 'Roster not found' });
          continue;
        }
        
        console.log(`   Customer: ${roster.customerName || roster.employeeDetails?.name || 'Unknown'}`);
        console.log(`   Office: ${roster.officeLocation || 'Unknown'}`);
        console.log(`   Current Lat: ${roster.latitude || 'null'}`);
        console.log(`   Current Lng: ${roster.longitude || 'null'}`);
        
        // Determine coordinates based on office location
        let coordinates = defaultLocation;
        
        if (roster.officeLocation && officeLocations[roster.officeLocation]) {
          coordinates = officeLocations[roster.officeLocation];
          console.log(`   ✅ Found coordinates for ${roster.officeLocation}`);
        } else {
          console.log(`   ⚠️  Using default coordinates (office location not recognized)`);
        }
        
        // Update roster with location coordinates
        const updateResult = await db.collection('rosters').updateOne(
          { _id: new ObjectId(rosterId) },
          {
            $set: {
              latitude: coordinates.latitude,
              longitude: coordinates.longitude,
              location: {
                latitude: coordinates.latitude,
                longitude: coordinates.longitude,
                address: roster.officeLocation || 'Bangalore, Karnataka'
              },
              // Also add to pickup location for consistency
              pickupLocation: {
                latitude: coordinates.latitude,
                longitude: coordinates.longitude,
                address: roster.loginPickupAddress || roster.officeLocation || 'Bangalore, Karnataka'
              },
              updatedAt: new Date(),
              locationFixedAt: new Date(),
              specificFix: true // Mark this as specifically fixed
            }
          }
        );
        
        if (updateResult.modifiedCount > 0) {
          console.log(`   ✅ Updated with coordinates: ${coordinates.latitude}, ${coordinates.longitude}`);
          fixedCount++;
          
          // Verify the update
          const verifyRoster = await db.collection('rosters').findOne({
            _id: new ObjectId(rosterId)
          });
          console.log(`   🔍 Verification - Lat: ${verifyRoster.latitude}, Lng: ${verifyRoster.longitude}`);
        } else {
          console.log(`   ⚠️  No changes made`);
        }
        
      } catch (error) {
        console.error(`   ❌ Error processing roster ${rosterId}: ${error.message}`);
        errors.push({ rosterId, error: error.message });
      }
    }
    
    console.log('\n' + '✅'.repeat(50));
    console.log('SPECIFIC ROSTER FIX COMPLETED');
    console.log('✅'.repeat(50));
    console.log(`📊 Summary:`);
    console.log(`   - Target rosters: ${specificRosterIds.length}`);
    console.log(`   - Successfully fixed: ${fixedCount}`);
    console.log(`   - Errors: ${errors.length}`);
    
    if (errors.length > 0) {
      console.log('\n❌ Errors encountered:');
      errors.forEach(error => {
        console.log(`   - ${error.rosterId}: ${error.error}`);
      });
    }
    
    // Now verify all rosters have coordinates
    console.log('\n🔍 VERIFICATION: Checking all target rosters...');
    for (const rosterId of specificRosterIds) {
      const roster = await db.collection('rosters').findOne({
        _id: new ObjectId(rosterId)
      });
      
      if (roster) {
        const customerName = roster.customerName || roster.employeeDetails?.name || 'Unknown';
        const lat = roster.latitude;
        const lng = roster.longitude;
        
        if (lat && lng) {
          console.log(`   ✅ ${customerName}: ${lat}, ${lng}`);
        } else {
          console.log(`   ❌ ${customerName}: ${lat || 'null'}, ${lng || 'null'} - STILL MISSING!`);
        }
      }
    }
    
    console.log('\n🎯 Next Steps:');
    console.log('1. Try route optimization again in the Flutter app');
    console.log('2. The algorithm should now find customer locations');
    console.log('3. Vehicle selection should work properly');
    console.log('4. Complete route assignment should succeed');
    
  } catch (error) {
    console.error('\n❌ Script failed:', error);
  } finally {
    await client.close();
  }
}

// Run the fix
fixSpecificRosters();