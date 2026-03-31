const { MongoClient } = require('mongodb');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function checkAssignedCustomers() {
  const mongoUri = process.env.MONGODB_URI;
  
  if (!mongoUri) {
    console.error('❌ MONGODB_URI not found');
    return;
  }
  
  const client = new MongoClient(mongoUri);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('Checking assignedCustomers array in vehicles...\n');
    
    const vehicles = await db.collection('vehicles').find({}).toArray();
    
    for (const vehicle of vehicles) {
      const regNum = vehicle.registrationNumber || vehicle.vehicleNumber;
      const assignedCustomers = vehicle.assignedCustomers || [];
      
      console.log(`${regNum}:`);
      console.log(`  assignedCustomers array length: ${assignedCustomers.length}`);
      
      if (assignedCustomers.length > 0) {
        console.log(`  ⚠️  Vehicle has ${assignedCustomers.length} entries in assignedCustomers array`);
        console.log(`  First few entries:`, JSON.stringify(assignedCustomers.slice(0, 3), null, 2));
      } else {
        console.log(`  ✅ Empty - no assigned customers`);
      }
      console.log('');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

checkAssignedCustomers();
