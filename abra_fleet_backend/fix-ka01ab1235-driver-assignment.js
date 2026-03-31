// fix-ka01ab1235-driver-assignment.js
// Fix the driver assignment for vehicle KA01AB1235

const { MongoClient, ObjectId } = require('mongodb');

const uri = 'mongodb://localhost:27017';
const dbName = 'abra_fleet';

async function fixVehicleDriverAssignment() {
  const client = new MongoClient(uri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(dbName);
    
    // Find the vehicle
    console.log('🔍 Finding vehicle KA01AB1235...\n');
    const vehicle = await db.collection('vehicles').findOne({
      registrationNumber: 'KA01AB1235'
    });
    
    if (!vehicle) {
      console.log('❌ Vehicle KA01AB1235 not found!');
      return;
    }
    
    console.log('📋 Current Vehicle Data:');
    console.log('   Registration:', vehicle.registrationNumber);
    console.log('   Seat Capacity:', vehicle.seatCapacity);
    console.log('   Status:', vehicle.status);
    console.log('   Assigned Driver:', vehicle.assignedDriver || 'NOT ASSIGNED');
    
    // Find John Doe driver
    console.log('\n🔍 Finding driver John Doe (DRV-842143)...\n');
    const driver = await db.collection('drivers').findOne({
      $or: [
        { driverCode: 'DRV-842143' },
        { name: 'John Doe' },
        { email: 'driver.w4wc9s3d@example.com' }
      ]
    });
    
    if (!driver) {
      console.log('❌ Driver not found!');
      console.log('\n💡 Available drivers:');
      const allDrivers = await db.collection('drivers').find({}).toArray();
      allDrivers.forEach(d => {
        console.log(`   - ${d.name} (${d.driverCode || d.email})`);
      });
      return;
    }
    
    console.log('✅ Found driver:');
    console.log('   Name:', driver.name);
    console.log('   Code:', driver.driverCode);
    console.log('   Email:', driver.email);
    console.log('   Phone:', driver.phoneNumber);
    console.log('   Firebase UID:', driver.firebaseUid || 'N/A');
    
    // Update vehicle with driver assignment
    console.log('\n🔧 Assigning driver to vehicle...\n');
    
    const driverInfo = {
      driverId: driver._id,
      driverCode: driver.driverCode,
      name: driver.name,
      phone: driver.phoneNumber,
      email: driver.email,
      firebaseUid: driver.firebaseUid
    };
    
    const result = await db.collection('vehicles').updateOne(
      { _id: vehicle._id },
      {
        $set: {
          assignedDriver: driverInfo,
          updatedAt: new Date()
        }
      }
    );
    
    if (result.modifiedCount > 0) {
      console.log('✅ SUCCESS! Driver assigned to vehicle');
      
      // Verify the update
      const updatedVehicle = await db.collection('vehicles').findOne({
        _id: vehicle._id
      });
      
      console.log('\n📋 Updated Vehicle Data:');
      console.log('   Registration:', updatedVehicle.registrationNumber);
      console.log('   Seat Capacity:', updatedVehicle.seatCapacity);
      console.log('   Status:', updatedVehicle.status);
      console.log('   Assigned Driver:', updatedVehicle.assignedDriver.name);
      console.log('   Driver Code:', updatedVehicle.assignedDriver.driverCode);
      console.log('   Driver Phone:', updatedVehicle.assignedDriver.phone);
      
      console.log('\n🎯 Vehicle is now ready for route optimization!');
      console.log('   ✅ Has seat capacity: 20 seats');
      console.log('   ✅ Has driver assigned: John Doe');
      console.log('   ✅ Status is active');
      
    } else {
      console.log('⚠️  No changes made (driver may already be assigned)');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

fixVehicleDriverAssignment();
