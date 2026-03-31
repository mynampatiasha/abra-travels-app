// Fix vehicle driver assignment
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function fixVehicleDriver() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    const vehicleId = '68ddeb3f4eff4fbe00488ec8';
    
    // Find the vehicle
    const vehicle = await db.collection('vehicles').findOne({
      _id: new ObjectId(vehicleId)
    });
    
    if (!vehicle) {
      console.log('❌ Vehicle not found');
      return;
    }
    
    console.log(`\n📋 Current vehicle data:`);
    console.log(`  - Vehicle: ${vehicle.registrationNumber}`);
    console.log(`  - Current assignedDriver: ${vehicle.assignedDriver}`);
    
    // Find any driver
    const driver = await db.collection('users').findOne({
      role: 'driver'
    });
    
    if (!driver) {
      console.log('❌ No active driver found');
      return;
    }
    
    console.log(`\n✅ Found active driver:`);
    console.log(`  - Name: ${driver.name}`);
    console.log(`  - Email: ${driver.email}`);
    console.log(`  - ID: ${driver._id}`);
    
    // Update vehicle with correct driver reference
    const result = await db.collection('vehicles').updateOne(
      { _id: new ObjectId(vehicleId) },
      { 
        $set: { 
          assignedDriver: driver._id.toString(),
          assignedDriverId: driver._id.toString(),
          assignedDriverName: driver.name,
          assignedDriverEmail: driver.email,
          updatedAt: new Date()
        } 
      }
    );
    
    if (result.modifiedCount > 0) {
      console.log('\n✅ Vehicle updated successfully!');
      console.log(`  - Vehicle ${vehicle.registrationNumber} now assigned to ${driver.name}`);
      
      // Verify the update
      const updatedVehicle = await db.collection('vehicles').findOne({
        _id: new ObjectId(vehicleId)
      });
      
      console.log(`\n📋 Updated vehicle data:`);
      console.log(`  - assignedDriver: ${updatedVehicle.assignedDriver}`);
      console.log(`  - assignedDriverId: ${updatedVehicle.assignedDriverId}`);
      console.log(`  - assignedDriverName: ${updatedVehicle.assignedDriverName}`);
      console.log(`  - assignedDriverEmail: ${updatedVehicle.assignedDriverEmail}`);
      
      console.log('\n✅ You can now use this vehicle for route optimization!');
    } else {
      console.log('\n⚠️  No changes made');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

fixVehicleDriver();
