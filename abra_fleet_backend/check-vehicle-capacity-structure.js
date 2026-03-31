require('dotenv').config();
const { MongoClient } = require('mongodb');

async function checkVehicleCapacity() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db('fleet_management');
    const vehicles = await db.collection('vehicles').find({}).limit(5).toArray();
    
    console.log('\n📊 Vehicle Capacity Structures:');
    console.log('='.repeat(60));
    
    vehicles.forEach((vehicle, index) => {
      console.log(`\n${index + 1}. Vehicle: ${vehicle.registrationNumber || vehicle.vehicleId}`);
      console.log(`   Capacity field type: ${typeof vehicle.capacity}`);
      console.log(`   Capacity value:`, JSON.stringify(vehicle.capacity, null, 2));
      console.log(`   SeatingCapacity field:`, vehicle.seatingCapacity);
      
      if (vehicle.capacity) {
        console.log(`   Has 'passengers' key:`, 'passengers' in vehicle.capacity);
        if ('passengers' in vehicle.capacity) {
          console.log(`   Passengers value:`, vehicle.capacity.passengers);
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkVehicleCapacity();
