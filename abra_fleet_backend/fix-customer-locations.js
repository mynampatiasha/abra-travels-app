// Fix customer locations for route optimization
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

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

async function fixCustomerLocations() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    console.log('\n' + '🔧'.repeat(50));
    console.log('FIXING CUSTOMER LOCATIONS FOR ROUTE OPTIMIZATION');
    console.log('🔧'.repeat(50));
    
    await client.connect();
    const db = client.db('abra_fleet');
    
    // Get all rosters without location coordinates
    console.log('\n📋 Finding rosters without location coordinates...');
    const rosters = await db.collection('rosters').find({
      status: 'pending_assignment',
      $or: [
        { latitude: { $exists: false } },
        { longitude: { $exists: false } },
        { latitude: null },
        { longitude: null },
        { 'location.latitude': { $exists: false } },
        { 'location.longitude': { $exists: false } }
      ]
    }).toArray();
    
    console.log(`✅ Found ${rosters.length} rosters needing location fixes`);
    
    if (rosters.length === 0) {
      console.log('🎉 All rosters already have location coordinates!');
      return;
    }
    
    let fixedCount = 0;
    let errors = [];
    
    for (const roster of rosters) {
      try {
        console.log(`\n🔍 Processing roster: ${roster._id}`);
        console.log(`   Customer: ${roster.customerName || roster.employeeDetails?.name || 'Unknown'}`);
        console.log(`   Office: ${roster.officeLocation || 'Unknown'}`);
        
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
          { _id: roster._id },
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
              locationFixedAt: new Date()
            }
          }
        );
        
        if (updateResult.modifiedCount > 0) {
          console.log(`   ✅ Updated with coordinates: ${coordinates.latitude}, ${coordinates.longitude}`);
          fixedCount++;
        } else {
          console.log(`   ⚠️  No changes made`);
        }
        
      } catch (error) {
        console.error(`   ❌ Error processing roster ${roster._id}: ${error.message}`);
        errors.push({ rosterId: roster._id, error: error.message });
      }
    }
    
    console.log('\n' + '✅'.repeat(50));
    console.log('LOCATION FIX COMPLETED');
    console.log('✅'.repeat(50));
    console.log(`📊 Summary:`);
    console.log(`   - Total rosters processed: ${rosters.length}`);
    console.log(`   - Successfully fixed: ${fixedCount}`);
    console.log(`   - Errors: ${errors.length}`);
    
    if (errors.length > 0) {
      console.log('\n❌ Errors encountered:');
      errors.forEach(error => {
        console.log(`   - ${error.rosterId}: ${error.error}`);
      });
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
fixCustomerLocations();