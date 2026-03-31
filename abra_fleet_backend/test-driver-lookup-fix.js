// Test if the driver lookup fix works
const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function testDriverLookup() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    const vehicleId = '68ddeb3f4eff4fbe00488ec8';
    
    // Get vehicle
    const vehicle = await db.collection('vehicles').findOne({
      _id: new ObjectId(vehicleId)
    });
    
    console.log(`\n📋 Vehicle: ${vehicle.registrationNumber}`);
    console.log(`   assignedDriver: ${vehicle.assignedDriver}`);
    
    // Simulate the backend lookup logic
    let driver = null;
    const driverId = vehicle.assignedDriver;
    
    console.log(`\n🔍 Testing driver lookup logic...`);
    
    // Try users collection first
    console.log(`\n1️⃣ Checking users collection...`);
    try {
      driver = await db.collection('users').findOne({
        _id: new ObjectId(driverId)
      });
    } catch (e) {
      driver = await db.collection('users').findOne({
        $or: [
          { driverId: driverId },
          { driverCode: driverId },
          { employeeId: driverId },
          { _id: driverId }
        ]
      });
    }
    
    if (driver) {
      console.log(`   ✅ Found in users collection`);
    } else {
      console.log(`   ❌ Not found in users collection`);
    }
    
    // Try drivers collection
    if (!driver) {
      console.log(`\n2️⃣ Checking drivers collection...`);
      try {
        driver = await db.collection('drivers').findOne({
          _id: new ObjectId(driverId)
        });
      } catch (e) {
        driver = await db.collection('drivers').findOne({
          $or: [
            { driverId: driverId },
            { driverCode: driverId },
            { employeeId: driverId },
            { _id: driverId }
          ]
        });
      }
      
      if (driver) {
        console.log(`   ✅ Found in drivers collection!`);
        console.log(`\n📋 Driver Details:`);
        console.log(`   - _id: ${driver._id}`);
        console.log(`   - driverId: ${driver.driverId}`);
        console.log(`   - Name: ${driver.personalInfo?.firstName} ${driver.personalInfo?.lastName}`);
        console.log(`   - Email: ${driver.personalInfo?.email}`);
        console.log(`   - Phone: ${driver.personalInfo?.phone}`);
        console.log(`   - Status: ${driver.status}`);
        
        // Normalize driver data
        const normalizedDriver = {
          _id: driver._id,
          name: `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim() || 'Unknown Driver',
          email: driver.personalInfo?.email || '',
          phone: driver.personalInfo?.phone || '',
          driverId: driver.driverId,
          status: driver.status
        };
        
        console.log(`\n✅ Normalized Driver Data:`);
        console.log(JSON.stringify(normalizedDriver, null, 2));
        
        console.log(`\n✅ SUCCESS! The backend will now be able to find this driver!`);
      } else {
        console.log(`   ❌ Not found in drivers collection`);
      }
    }
    
    if (!driver) {
      console.log(`\n❌ FAILED: Driver not found in any collection`);
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

testDriverLookup();
