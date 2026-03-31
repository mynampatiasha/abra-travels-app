// Fix assigned trips that have vehicleId/driverId but missing vehicleNumber/driverName
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

async function fixMissingNames() {
  const mongoUri = process.env.MONGODB_URI || 'mongodb://127.0.0.1:27017';
  const dbName = process.env.DB_NAME || 'abra_fleet';
  
  const client = new MongoClient(mongoUri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(dbName);
    
    // Find trips with vehicleId but no vehicleNumber OR driverId but no driverName
    const tripsToFix = await db.collection('rosters').find({
      status: 'assigned',
      $or: [
        { vehicleId: { $exists: true, $ne: null, $ne: '' }, vehicleNumber: { $in: [null, ''] } },
        { driverId: { $exists: true, $ne: null, $ne: '' }, driverName: { $in: [null, ''] } }
      ]
    }).toArray();
    
    console.log(`📊 Found ${tripsToFix.length} trips needing fixes\n`);
    
    if (tripsToFix.length === 0) {
      console.log('✅ All trips already have complete data!');
      return;
    }
    
    let fixed = 0;
    let errors = 0;
    
    for (const trip of tripsToFix) {
      console.log(`\n${'─'.repeat(70)}`);
      console.log(`Fixing trip: ${trip.customerName || 'Unknown'}`);
      console.log(`   Current vehicleId: ${trip.vehicleId || 'NONE'}`);
      console.log(`   Current vehicleNumber: ${trip.vehicleNumber || 'EMPTY'}`);
      console.log(`   Current driverId: ${trip.driverId || 'NONE'}`);
      console.log(`   Current driverName: ${trip.driverName || 'EMPTY'}`);
      
      const updates = {};
      
      // Fix vehicle data
      if (trip.vehicleId && (!trip.vehicleNumber || trip.vehicleNumber === '')) {
        try {
          const vehicle = await db.collection('vehicles').findOne({
            _id: new ObjectId(trip.vehicleId)
          });
          
          if (vehicle) {
            updates.vehicleNumber = vehicle.vehicleNumber || vehicle.name || 'Unknown Vehicle';
            console.log(`   ✅ Found vehicle: ${updates.vehicleNumber}`);
          } else {
            console.log(`   ⚠️  Vehicle not found in database`);
          }
        } catch (e) {
          console.log(`   ❌ Error looking up vehicle: ${e.message}`);
        }
      }
      
      // Fix driver data
      if (trip.driverId && (!trip.driverName || trip.driverName === '')) {
        try {
          let driver = null;
          
          // Try as ObjectId first
          try {
            driver = await db.collection('users').findOne({
              _id: new ObjectId(trip.driverId),
              role: 'driver'
            });
          } catch (e) {
            // Not a valid ObjectId, try as string
            driver = await db.collection('users').findOne({
              _id: trip.driverId,
              role: 'driver'
            });
          }
          
          if (driver) {
            updates.driverName = driver.name || 'Unknown Driver';
            updates.driverPhone = driver.phone || driver.phoneNumber || '';
            console.log(`   ✅ Found driver: ${updates.driverName}`);
          } else {
            console.log(`   ⚠️  Driver not found in database`);
          }
        } catch (e) {
          console.log(`   ❌ Error looking up driver: ${e.message}`);
        }
      }
      
      // Apply updates
      if (Object.keys(updates).length > 0) {
        try {
          updates.updatedAt = new Date();
          
          await db.collection('rosters').updateOne(
            { _id: trip._id },
            { $set: updates }
          );
          
          console.log(`   ✅ Updated trip with:`, updates);
          fixed++;
        } catch (e) {
          console.log(`   ❌ Failed to update: ${e.message}`);
          errors++;
        }
      } else {
        console.log(`   ⚠️  No updates needed (data not found)`);
      }
    }
    
    console.log(`\n\n${'='.repeat(70)}`);
    console.log('SUMMARY');
    console.log('='.repeat(70));
    console.log(`Total trips checked: ${tripsToFix.length}`);
    console.log(`Successfully fixed: ${fixed}`);
    console.log(`Errors: ${errors}`);
    console.log(`Skipped (data not found): ${tripsToFix.length - fixed - errors}`);
    
    if (fixed > 0) {
      console.log(`\n✅ Fixed ${fixed} trips! Vehicle and driver names are now populated.`);
      console.log(`   Refresh your app to see the changes.`);
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

fixMissingNames();
