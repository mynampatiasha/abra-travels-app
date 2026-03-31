// Find driver by driver code
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function findDriver() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    const driverCode = 'DRV-842143';
    
    console.log(`\n🔍 Searching for driver with code: ${driverCode}`);
    
    // Try different fields
    const queries = [
      { driverId: driverCode },
      { driverCode: driverCode },
      { employeeId: driverCode },
      { _id: driverCode }
    ];
    
    for (const query of queries) {
      console.log(`\n  Trying query:`, query);
      const driver = await db.collection('users').findOne(query);
      if (driver) {
        console.log('  ✅ Found driver!');
        console.log('  - _id:', driver._id);
        console.log('  - name:', driver.name);
        console.log('  - email:', driver.email);
        console.log('  - role:', driver.role);
        console.log('  - driverId:', driver.driverId);
        console.log('  - driverCode:', driver.driverCode);
        console.log('  - employeeId:', driver.employeeId);
        return;
      }
    }
    
    console.log('\n❌ Driver not found with any query');
    
    // List all drivers
    console.log('\n📋 All drivers in database:');
    const allDrivers = await db.collection('users').find({ role: 'driver' }).limit(5).toArray();
    allDrivers.forEach((driver, idx) => {
      console.log(`\n  ${idx + 1}. ${driver.name || 'Unknown'}`);
      console.log(`     - _id: ${driver._id}`);
      console.log(`     - email: ${driver.email}`);
      console.log(`     - driverId: ${driver.driverId || 'N/A'}`);
      console.log(`     - driverCode: ${driver.driverCode || 'N/A'}`);
      console.log(`     - employeeId: ${driver.employeeId || 'N/A'}`);
    });
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

findDriver();
