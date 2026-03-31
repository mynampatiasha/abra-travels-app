// Find driver DRV-852306
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';

async function findDriver() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('🔍 Searching for driver DRV-852306...\n');
    
    const driver = await db.collection('drivers').findOne({ driverId: 'DRV-852306' });
    
    if (driver) {
      console.log('✅ FOUND:');
      console.log(JSON.stringify(driver, null, 2));
    } else {
      console.log('❌ NOT FOUND');
      console.log('\nSearching all drivers...\n');
      const allDrivers = await db.collection('drivers').find({}).limit(10).toArray();
      console.log(`Found ${allDrivers.length} drivers:`);
      allDrivers.forEach((d, i) => {
        console.log(`${i + 1}. ${d.name || 'N/A'} - ID: ${d.driverId || d._id}`);
      });
    }
    
  } catch (error) {
    console.error('Error:', error.message);
  } finally {
    await client.close();
  }
}

findDriver();
