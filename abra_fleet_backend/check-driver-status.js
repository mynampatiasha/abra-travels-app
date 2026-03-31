// Check driver status
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function checkDrivers() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Find all drivers
    const drivers = await db.collection('users').find({ role: 'driver' }).toArray();
    
    console.log(`\n📋 Found ${drivers.length} drivers:`);
    
    drivers.forEach((driver, idx) => {
      console.log(`\n${idx + 1}. ${driver.name || 'Unknown'}`);
      console.log(`   - _id: ${driver._id}`);
      console.log(`   - email: ${driver.email}`);
      console.log(`   - status: ${driver.status || 'N/A'}`);
      console.log(`   - isAvailable: ${driver.isAvailable}`);
      console.log(`   - role: ${driver.role}`);
    });
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkDrivers();
