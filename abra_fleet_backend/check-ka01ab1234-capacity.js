const { MongoClient } = require('mongodb');

async function checkVehicleCapacity() {
  const client = await MongoClient.connect('mongodb://localhost:27017');
  const db = client.db('abra_fleet');
  
  console.log('\n🔍 Checking KA01AB1234 Vehicle Capacity...\n');
  
  const vehicle = await db.collection('vehicles').findOne({ 
    registrationNumber: 'KA01AB1234' 
  });
  
  if (!vehicle) {
    console.log('❌ Vehicle not found');
    client.close();
    return;
  }
  
  console.log('Vehicle Data Structure:');
  console.log('======================');
  console.log('Registration:', vehicle.registrationNumber);
  console.log('Vehicle ID:', vehicle.vehicleId);
  console.log('\nCapacity Fields:');
  console.log('  - vehicle.seatingCapacity:', vehicle.seatingCapacity);
  console.log('  - vehicle.capacity:', JSON.stringify(vehicle.capacity, null, 2));
  console.log('  - vehicle.capacity?.passengers:', vehicle.capacity?.passengers);
  console.log('  - vehicle.seatCapacity:', vehicle.seatCapacity);
  
  console.log('\nAll Vehicle Fields:');
  console.log(JSON.stringify(vehicle, null, 2));
  
  // Check assigned rosters
  const assignedRosters = await db.collection('rosters').find({
    vehicleId: vehicle._id.toString(),
    status: { $in: ['assigned', 'active', 'in_progress'] }
  }).toArray();
  
  console.log('\n📊 Assigned Rosters:', assignedRosters.length);
  
  client.close();
}

checkVehicleCapacity().catch(console.error);
