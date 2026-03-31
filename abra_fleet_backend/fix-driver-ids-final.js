const { MongoClient } = require('mongodb');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function fixDriverIds() {
  const mongoUri = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
  const client = new MongoClient(mongoUri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Find drivers with problematic IDs:
    // 1. IDs starting with EMP (employee number format)
    // 2. IDs that are undefined/null
    // 3. IDs that don't follow DRV-XXXXXX format
    const driversToFix = await db.collection('drivers').find({
      $or: [
        { driverId: { $regex: /^EMP/i } }, // Starts with EMP
        { driverId: null },
        { driverId: { $exists: false } },
        { driverId: '' },
        { driverId: { $not: { $regex: /^DRV-\d{6}$/ } } } // Doesn't match DRV-XXXXXX
      ]
    }).toArray();
    
    console.log(`\n🔍 Found ${driversToFix.length} driver(s) with invalid driver IDs\n`);
    
    if (driversToFix.length === 0) {
      console.log('✅ All drivers have valid driver IDs!');
      return;
    }
    
    // Get the highest existing driver number
    const allDrivers = await db.collection('drivers').find({
      driverId: { $regex: /^DRV-\d{6}$/ }
    }).toArray();
    
    let maxDriverNum = 0;
    allDrivers.forEach(driver => {
      const match = driver.driverId.match(/^DRV-(\d+)$/);
      if (match) {
        const num = parseInt(match[1]);
        if (num > maxDriverNum) maxDriverNum = num;
      }
    });
    
    console.log(`📊 Highest existing driver number: DRV-${maxDriverNum.toString().padStart(6, '0')}`);
    console.log('\n🔧 Fixing driver IDs...\n');
    console.log('='.repeat(80));
    
    // Fix each driver
    for (const driver of driversToFix) {
      maxDriverNum++;
      const newDriverId = `DRV-${maxDriverNum.toString().padStart(6, '0')}`;
      const oldDriverId = driver.driverId || 'undefined';
      
      const firstName = driver.personalInfo?.firstName || 'Unknown';
      const lastName = driver.personalInfo?.lastName || '';
      const fullName = `${firstName} ${lastName}`.trim();
      
      console.log(`\n👤 ${fullName}`);
      console.log(`   Old Driver ID: ${oldDriverId}`);
      console.log(`   New Driver ID: ${newDriverId}`);
      
      // Update the driver document
      const result = await db.collection('drivers').updateOne(
        { _id: driver._id },
        { 
          $set: { 
            driverId: newDriverId,
            updatedAt: new Date()
          },
          $unset: {
            employment: "" // Remove employment field as drivers don't have employee IDs
          }
        }
      );
      
      if (result.modifiedCount > 0) {
        console.log(`   ✅ Driver ID updated successfully`);
        
        // Update references in other collections only if oldDriverId was valid
        if (oldDriverId && oldDriverId !== 'undefined' && oldDriverId !== '') {
          // Update vehicles
          const vehicleUpdate = await db.collection('vehicles').updateMany(
            { assignedDriver: oldDriverId },
            { $set: { assignedDriver: newDriverId, updatedAt: new Date() } }
          );
          if (vehicleUpdate.modifiedCount > 0) {
            console.log(`   ✅ Updated ${vehicleUpdate.modifiedCount} vehicle(s)`);
          }
          
          // Update trips
          const tripUpdate = await db.collection('trips').updateMany(
            { driverId: oldDriverId },
            { $set: { driverId: newDriverId, updatedAt: new Date() } }
          );
          if (tripUpdate.modifiedCount > 0) {
            console.log(`   ✅ Updated ${tripUpdate.modifiedCount} trip(s)`);
          }
          
          // Update rosters
          const rosterUpdate = await db.collection('rosters').updateMany(
            { driverId: oldDriverId },
            { $set: { driverId: newDriverId, updatedAt: new Date() } }
          );
          if (rosterUpdate.modifiedCount > 0) {
            console.log(`   ✅ Updated ${rosterUpdate.modifiedCount} roster(s)`);
          }
          
          // Update assigned_trips
          const assignedTripUpdate = await db.collection('assigned_trips').updateMany(
            { driverId: oldDriverId },
            { $set: { driverId: newDriverId, updatedAt: new Date() } }
          );
          if (assignedTripUpdate.modifiedCount > 0) {
            console.log(`   ✅ Updated ${assignedTripUpdate.modifiedCount} assigned trip(s)`);
          }
        }
      } else {
        console.log(`   ❌ Failed to update`);
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ All driver IDs have been standardized to DRV-XXXXXX format!');
    console.log('✅ Employment fields removed (drivers don\'t have employee IDs)');
    console.log('='.repeat(80));
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
  }
}

fixDriverIds();
