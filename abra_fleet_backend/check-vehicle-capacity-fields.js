const { MongoClient } = require('mongodb');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function checkVehicleCapacityFields() {
  const mongoUri = process.env.MONGODB_URI;
  
  if (!mongoUri) {
    console.error('❌ MONGODB_URI not found');
    return;
  }
  
  const client = new MongoClient(mongoUri);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('Checking first vehicle structure...\n');
    
    const vehicle = await db.collection('vehicles').findOne({});
    
    if (!vehicle) {
      console.log('❌ No vehicles found');
      return;
    }
    
    console.log('Vehicle:', vehicle.registrationNumber || vehicle.vehicleNumber);
    console.log('\nAll fields in vehicle document:');
    console.log(JSON.stringify(vehicle, null, 2));
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

checkVehicleCapacityFields();
