const { MongoClient } = require('mongodb');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function fixDriverNumbers() {
  const mongoUri = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
  const client = new MongoClient(mongoUri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('abra_fleet');
    
    // Find drivers where driverId matches employeeId or has EMP prefix
    const driversToFix = await db.collection('drivers').find({
      $or: [
        { driverId: { $regex: /^EMP\d+$/ } }, // Starts with EMP followed by numbers
        { $expr: { $eq: ['$driverId', '$employment.employeeId'] } } // driverId equals employeeId
      ]
    }).toArray();
    
    console.log(`\n🔍 Found ${driversToFix.length} driver(s) with employee numbers as driver IDs\n`);
    
    if (driversToFix.length === 0) {
      console.log('✅ No drivers need fixing!');
      return;
    }
    
    // Get the highest existing driver number
    const allDrivers = await db.collection('drivers').find({
      driverId: { $regex: /^DRV-\d+$/ }
    }).toArray();
    
    let maxDriverNum = 0;
    allDrivers.forEach(driver => {
      const match = driver.driverId.match(/^DRV-(\d+)$/);
      if (match) {
        const num = parseInt(match[1]);
        if (num > maxDriverNum) maxDriverNum = num;
      }
    });
    
    console.log(`📊 Highest existing driver number: DRV-${maxDriverNum}`);
    console.log('\n🔧 Fixing driver IDs...\n');
    
    // Fix each driver
    for (const driver of driversToFix) {
      maxDriverNum++;
      const newDriverId = `DRV-${maxDriverNum.toString().padStart(6, '0')}`;
      const oldDriverId = driver.driverId;
      
      const firstName = driver.personalInfo?.firstName || 'N/A';
      const lastName = driver.personalInfo?.lastName || 'N/A';
      const employeeId = driver.employment?.employeeId || 'N/A';
      
      console.log(`👤 ${firstName} ${lastName}`);
      console.log(`   Old Driver ID: ${oldDriverId}`);
      console.log(`   Employee ID: ${employeeId}`);
      console.log(`   New Driver ID: ${newDriverId}`);
      
      // Update the driver document
      const result = await db.collection('drivers').updateOne(
        { _id: driver._id },
        { 
          $set: { 
            driverId: newDriverId,
            updatedAt: new Date()
          } 
        }
      );
      
      if (result.modifiedCount > 0) {
        console.log(`   ✅ Updated successfully`);
        
        // Also update any references in other collections
        // Update vehicles
        const vehicleUpdate = await db.collection('vehicles').updateMany(
          { assignedDriver: oldDriverId },
          { $set: { assignedDriver: newDriverId } }
        );
        if (vehicleUpdate.modifiedCount > 0) {
          console.log(`   ✅ Updated ${vehicleUpdate.modifiedCount} vehicle(s)`);
        }
        
        // Update trips
        const tripUpdate = await db.collection('trips').updateMany(
          { driverId: oldDriverId },
          { $set: { driverId: newDriverId } }
        );
        if (tripUpdate.modifiedCount > 0) {
          console.log(`   ✅ Updated ${tripUpdate.modifiedCount} trip(s)`);
        }
        
        // Update rosters
        const rosterUpdate = await db.collection('rosters').updateMany(
          { driverId: oldDriverId },
          { $set: { driverId: newDriverId } }
        );
        if (rosterUpdate.modifiedCount > 0) {
          console.log(`   ✅ Updated ${rosterUpdate.modifiedCount} roster(s)`);
        }
        
        // Update assigned_trips
        const assignedTripUpdate = await db.collection('assigned_trips').updateMany(
          { driverId: oldDriverId },
          { $set: { driverId: newDriverId } }
        );
        if (assignedTripUpdate.modifiedCount > 0) {
          console.log(`   ✅ Updated ${assignedTripUpdate.modifiedCount} assigned trip(s)`);
        }
      } else {
        console.log(`   ❌ Failed to update`);
      }
      
      console.log('');
    }
    
    console.log('='.repeat(80));
    console.log('✅ All driver numbers have been fixed!');
    console.log('='.repeat(80));
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
  }
}

fixDriverNumbers();
