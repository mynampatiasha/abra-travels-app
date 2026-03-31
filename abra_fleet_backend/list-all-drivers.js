const { MongoClient } = require('mongodb');
require('dotenv').config();

async function listAllDrivers() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db();
    const drivers = await db.collection('drivers').find({}).toArray();
    
    console.log(`📊 Total drivers in database: ${drivers.length}\n`);
    
    if (drivers.length === 0) {
      console.log('❌ No drivers found in database');
    } else {
      console.log('Drivers:');
      drivers.forEach((driver, index) => {
        console.log(`\n${index + 1}. Driver ID: ${driver.driverId}`);
        console.log(`   Name: ${driver.name || 'N/A'}`);
        console.log(`   Email: ${driver.email || driver.personalInfo?.email || 'N/A'}`);
        console.log(`   Phone: ${driver.phone || driver.personalInfo?.phone || 'N/A'}`);
        console.log(`   Status: ${driver.status || 'N/A'}`);
        console.log(`   Firebase UID: ${driver.uid || 'N/A'}`);
      });
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

listAllDrivers();
