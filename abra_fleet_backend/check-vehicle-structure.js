// Check actual vehicle structure
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.MONGODB_DB_NAME || 'abra_fleet';

async function checkStructure() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db(DB_NAME);
    
    // Get one vehicle to see structure
    const vehicle = await db.collection('vehicles').findOne({});
    console.log('VEHICLE STRUCTURE:');
    console.log(JSON.stringify(vehicle, null, 2));
    console.log('\n');
    
    // Get one driver
    const driver = await db.collection('users').findOne({ role: 'driver' });
    console.log('DRIVER STRUCTURE:');
    console.log(JSON.stringify(driver, null, 2));
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

checkStructure().catch(console.error);
