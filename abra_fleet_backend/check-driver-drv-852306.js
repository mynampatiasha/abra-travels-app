// Check the actual structure of driver DRV-852306
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = 'abra_fleet';

async function checkDriver() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(DB_NAME);
    
    const driver = await db.collection('drivers').findOne({ driverId: 'DRV-852306' });
    
    if (!driver) {
      console.log('❌ Driver DRV-852306 not found!');
      return;
    }
    
    console.log('📋 Driver DRV-852306 Full Document:\n');
    console.log('='.repeat(80));
    console.log(JSON.stringify(driver, null, 2));
    console.log('='.repeat(80));
    
    console.log('\n📊 Available Fields:');
    console.log(`  - driverId: ${driver.driverId}`);
    console.log(`  - name: ${driver.name || 'NOT FOUND'}`);
    console.log(`  - driverName: ${driver.driverName || 'NOT FOUND'}`);
    console.log(`  - phone: ${driver.phone || 'NOT FOUND'}`);
    console.log(`  - phoneNumber: ${driver.phoneNumber || 'NOT FOUND'}`);
    console.log(`  - contactNumber: ${driver.contactNumber || 'NOT FOUND'}`);
    console.log(`  - mobileNumber: ${driver.mobileNumber || 'NOT FOUND'}`);
    console.log(`  - email: ${driver.email || 'NOT FOUND'}`);
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkDriver();
