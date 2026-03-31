const { MongoClient } = require('mongodb');
require('dotenv').config();

async function listVehicles() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    const vehicles = await db.collection('vehicles').find({}).toArray();
    
    console.log(`Found ${vehicles.length} vehicles in the database:`);
    console.log('----------------------------------');
    
    vehicles.forEach((vehicle, index) => {
      console.log(`${index + 1}. Vehicle ID: ${vehicle.vehicleId}`);
      console.log(`   Registration: ${vehicle.registrationNumber}`);
      console.log(`   Make/Model: ${vehicle.make} ${vehicle.model}`);
      console.log(`   Status: ${vehicle.status}`);
      console.log(`   Added: ${vehicle.createdAt}`);
      console.log('----------------------------------');
    });
    
  } catch (error) {
    console.error('Error listing vehicles:', error);
  } finally {
    await client.close();
  }
}

listVehicles();
