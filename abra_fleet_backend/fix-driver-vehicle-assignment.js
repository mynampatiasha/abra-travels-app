// Fix driver's vehicle assignment to match roster vehicle
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI;

async function fixDriverVehicle() {
  const client = new MongoClient(MONGODB_URI);

  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');

    const db = client.db('abra_fleet');

    // The rosters have vehicle KA01AB1240, so let's assign that to the driver
    const vehicleNumber = 'KA01AB1240';

    // Verify vehicle exists (use registrationNumber field)
    const vehicle = await db.collection('vehicles').findOne({
      registrationNumber: vehicleNumber
    });

    if (!vehicle) {
      console.log('❌ Vehicle not found:', vehicleNumber);
      return;
    }

    console.log('✅ Found vehicle:', vehicle.vehicleNumber, '-', vehicle.model);

    // Update driver's assigned vehicle
    const result = await db.collection('drivers').updateOne(
      { driverId: 'DRV-852306' },
      { 
        $set: { 
          assignedVehicle: vehicleNumber,
          vehicleNumber: vehicleNumber
        } 
      }
    );

    if (result.modifiedCount > 0) {
      console.log('✅ Updated driver DRV-852306 with vehicle:', vehicleNumber);
    } else {
      console.log('⚠️  No changes made (driver may already have this vehicle)');
    }

    // Verify the update
    const updatedDriver = await db.collection('drivers').findOne({
      driverId: 'DRV-852306'
    });

    console.log('\n📊 Updated Driver Info:');
    console.log('  Driver ID:', updatedDriver.driverId);
    console.log('  Assigned Vehicle:', updatedDriver.assignedVehicle);
    console.log('  Vehicle Number:', updatedDriver.vehicleNumber);

    console.log('\n✅ Fix complete! The driver dashboard should now show vehicle details.');

  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

fixDriverVehicle();
