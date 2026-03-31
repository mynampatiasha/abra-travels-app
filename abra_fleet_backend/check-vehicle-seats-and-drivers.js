const { MongoClient } = require('mongodb');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

async function checkVehicleSeatsAndDrivers() {
  const mongoUri = process.env.MONGODB_URI;
  
  if (!mongoUri) {
    console.error('❌ MONGODB_URI not found in environment variables');
    return;
  }
  
  const client = new MongoClient(mongoUri);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('='.repeat(80));
    console.log('CHECKING ALL VEHICLES - SEATS & DRIVERS');
    console.log('='.repeat(80) + '\n');
    
    const vehicles = await db.collection('vehicles').find({}).toArray();
    
    console.log(`Total Vehicles: ${vehicles.length}\n`);
    
    let totalSeats = 0;
    let vehiclesWithDrivers = 0;
    let activeVehicles = 0;
    
    for (let i = 0; i < vehicles.length; i++) {
      const vehicle = vehicles[i];
      
      // Count assigned rosters for this vehicle
      const assignedCount = await db.collection('rosters').countDocuments({
        $or: [
          { 'assignedVehicle.vehicleId': vehicle._id },
          { 'assignedVehicle': vehicle._id }
        ],
        status: { $in: ['assigned', 'in_progress', 'active', 'scheduled'] }
      });
      
      const seatCapacity = vehicle.seatingCapacity || vehicle.capacity?.passengers || vehicle.seatCapacity || 0;
      const availableSeats = seatCapacity - assignedCount;
      
      console.log(`${i + 1}. ${vehicle.registrationNumber || vehicle.vehicleNumber}`);
      console.log(`   Seat Capacity: ${seatCapacity}`);
      console.log(`   Assigned: ${assignedCount}`);
      console.log(`   Available: ${availableSeats}`);
      console.log(`   Driver: ${vehicle.assignedDriver ? '✅ Assigned' : '❌ Not Assigned'}`);
      console.log(`   Status: ${vehicle.status || 'N/A'}`);
      console.log(`   Organization: ${vehicle.organizationName || vehicle.companyName || 'N/A'}`);
      
      if (seatCapacity > 0) {
        const visual = '⬜'.repeat(availableSeats) + '🪑'.repeat(assignedCount);
        console.log(`   Visual: ${visual}`);
      }
      
      console.log('');
      
      totalSeats += availableSeats;
      if (vehicle.assignedDriver) vehiclesWithDrivers++;
      if (vehicle.status === 'active') activeVehicles++;
    }
    
    console.log('='.repeat(80));
    console.log('SUMMARY');
    console.log('='.repeat(80));
    console.log(`Total Vehicles: ${vehicles.length}`);
    console.log(`Active Vehicles: ${activeVehicles}`);
    console.log(`Vehicles with Drivers: ${vehiclesWithDrivers}`);
    console.log(`Total Available Seats: ${totalSeats}`);
    console.log('='.repeat(80) + '\n');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

checkVehicleSeatsAndDrivers();
