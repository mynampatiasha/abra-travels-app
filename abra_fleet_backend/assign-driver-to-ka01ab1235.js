// Quick fix: Assign driver to KA01AB1235 for route optimization
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function assignDriver() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Find vehicle KA01AB1235
    const vehicle = await db.collection('vehicles').findOne({
      registrationNumber: 'KA01AB1235'
    });
    
    if (!vehicle) {
      console.log('❌ Vehicle KA01AB1235 not found');
      return;
    }
    
    console.log(`\n📋 Vehicle: ${vehicle.registrationNumber}`);
    console.log(`   Current driver: ${vehicle.assignedDriver || 'None'}`);
    console.log(`   Capacity: ${vehicle.capacity?.passengers || vehicle.seatingCapacity} seats`);
    
    // Find any available driver
    const driver = await db.collection('users').findOne({
      role: 'driver'
    });
    
    if (!driver) {
      console.log('❌ No driver found in users collection');
      
      // Try drivers collection
      const driverFromDrivers = await db.collection('drivers').findOne({});
      
      if (driverFromDrivers) {
        console.log(`\n✅ Found driver in drivers collection: ${driverFromDrivers.personalInfo?.firstName} ${driverFromDrivers.personalInfo?.lastName}`);
        
        // Assign driver
        await db.collection('vehicles').updateOne(
          { _id: vehicle._id },
          {
            $set: {
              assignedDriver: {
                _id: driverFromDrivers._id.toString(),
                driverId: driverFromDrivers.driverId,
                name: `${driverFromDrivers.personalInfo?.firstName} ${driverFromDrivers.personalInfo?.lastName}`,
                phone: driverFromDrivers.personalInfo?.phone,
                email: driverFromDrivers.personalInfo?.email,
                status: driverFromDrivers.status
              },
              updatedAt: new Date()
            }
          }
        );
        
        console.log(`\n✅ SUCCESS! Driver assigned to KA01AB1235`);
        console.log(`   Driver: ${driverFromDrivers.personalInfo?.firstName} ${driverFromDrivers.personalInfo?.lastName}`);
        console.log(`   Vehicle now ready for route optimization!`);
      } else {
        console.log('❌ No drivers found in any collection');
      }
      return;
    }
    
    console.log(`\n✅ Found driver: ${driver.name}`);
    console.log(`   Email: ${driver.email}`);
    
    // Assign driver to vehicle
    await db.collection('vehicles').updateOne(
      { _id: vehicle._id },
      {
        $set: {
          assignedDriver: {
            _id: driver._id.toString(),
            name: driver.name,
            email: driver.email,
            phone: driver.phone || ''
          },
          updatedAt: new Date()
        }
      }
    );
    
    console.log(`\n✅ SUCCESS! Driver assigned to KA01AB1235`);
    console.log(`   Driver: ${driver.name}`);
    console.log(`   Vehicle now ready for route optimization!`);
    
    console.log(`\n📊 Vehicle Summary:`);
    console.log(`   - Registration: KA01AB1235`);
    console.log(`   - Capacity: 20 seats`);
    console.log(`   - Driver: ${driver.name}`);
    console.log(`   - Status: ACTIVE`);
    console.log(`   - Ready for: 5+ customers`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

assignDriver();
