// Check KA01AB1235 driver assignment
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function checkVehicleDriver() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Get vehicle
    const vehicle = await db.collection('vehicles').findOne({
      registrationNumber: 'KA01AB1235'
    });
    
    if (!vehicle) {
      console.log('❌ Vehicle not found');
      return;
    }
    
    console.log(`\n📋 Vehicle KA01AB1235:`);
    console.log(`   - _id: ${vehicle._id}`);
    console.log(`   - assignedDriver value: ${JSON.stringify(vehicle.assignedDriver)}`);
    console.log(`   - assignedDriver type: ${typeof vehicle.assignedDriver}`);
    
    // Check if it's an object or string
    if (typeof vehicle.assignedDriver === 'object' && vehicle.assignedDriver !== null) {
      console.log(`\n✅ assignedDriver is already an object:`);
      console.log(JSON.stringify(vehicle.assignedDriver, null, 2));
    } else if (typeof vehicle.assignedDriver === 'string') {
      console.log(`\n🔍 assignedDriver is a string: "${vehicle.assignedDriver}"`);
      console.log(`   Checking if this driver exists...`);
      
      // Check in drivers collection
      const driver = await db.collection('drivers').findOne({
        driverId: vehicle.assignedDriver
      });
      
      if (driver) {
        console.log(`   ✅ Driver found in drivers collection!`);
        console.log(`      - Name: ${driver.personalInfo?.firstName} ${driver.personalInfo?.lastName}`);
        console.log(`      - Email: ${driver.personalInfo?.email}`);
      } else {
        console.log(`   ❌ Driver NOT found in drivers collection`);
        console.log(`   Checking users collection...`);
        
        const userDriver = await db.collection('users').findOne({
          $or: [
            { _id: vehicle.assignedDriver },
            { driverId: vehicle.assignedDriver }
          ]
        });
        
        if (userDriver) {
          console.log(`   ✅ Driver found in users collection!`);
          console.log(`      - Name: ${userDriver.name}`);
          console.log(`      - Email: ${userDriver.email}`);
        } else {
          console.log(`   ❌ Driver NOT found in users collection either`);
        }
      }
    } else {
      console.log(`\n⚠️  assignedDriver is null or undefined`);
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkVehicleDriver();
