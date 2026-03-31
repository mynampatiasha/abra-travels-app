// Check available vehicles and drivers for customer123
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017';
const DB_NAME = process.env.MONGODB_DB_NAME || 'abra_fleet';

async function checkResources() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(DB_NAME);
    
    // Find customer
    const customer = await db.collection('users').findOne({
      email: 'customer123@abrafleet.com'
    });
    
    console.log('CUSTOMER INFO:');
    console.log(`  Email: ${customer.email}`);
    console.log(`  Name: ${customer.name}`);
    console.log(`  Organization: ${customer.companyName || 'N/A'}\n`);
    
    // Check all vehicles
    const allVehicles = await db.collection('vehicles').find({}).limit(10).toArray();
    console.log(`AVAILABLE VEHICLES (${allVehicles.length}):`);
    allVehicles.forEach(v => {
      console.log(`  - ${v.vehicleNumber} | ${v.vehicleType} | Org: ${v.companyName || 'N/A'} | Status: ${v.status || 'N/A'}`);
    });
    console.log();
    
    // Check all drivers
    const allDrivers = await db.collection('users').find({ role: 'driver' }).limit(10).toArray();
    console.log(`AVAILABLE DRIVERS (${allDrivers.length}):`);
    allDrivers.forEach(d => {
      console.log(`  - ${d.name || d.email} | Org: ${d.companyName || 'N/A'} | Email: ${d.email}`);
    });
    console.log();
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

checkResources().catch(console.error);
