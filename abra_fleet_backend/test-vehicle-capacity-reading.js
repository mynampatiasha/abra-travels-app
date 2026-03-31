// Test vehicle capacity reading for route optimization
require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function testVehicleCapacity() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db();
    
    // Get all vehicles
    const vehicles = await db.collection('vehicles').find({}).toArray();
    
    console.log('='*80);
    console.log('VEHICLE CAPACITY TEST FOR ROUTE OPTIMIZATION');
    console.log('='*80);
    console.log(`Total vehicles: ${vehicles.length}\n`);
    
    // Simulate what the Flutter app will do
    for (let i = 0; i < vehicles.length; i++) {
      const vehicle = vehicles[i];
      const vehicleName = vehicle.name || vehicle.vehicleNumber || vehicle.registrationNumber || 'Unknown';
      
      console.log(`\n${i + 1}. Vehicle: ${vehicleName}`);
      console.log(`   ID: ${vehicle._id}`);
      
      // Check capacity - try multiple fields (same logic as Flutter)
      let capacity = 4; // default
      if (vehicle.seatCapacity != null) {
        capacity = vehicle.seatCapacity;
        console.log(`   ✅ Found seatCapacity: ${capacity}`);
      } else if (vehicle.seatingCapacity != null) {
        capacity = vehicle.seatingCapacity;
        console.log(`   ✅ Found seatingCapacity: ${capacity}`);
      } else if (vehicle.capacity != null) {
        if (typeof vehicle.capacity === 'object') {
          capacity = vehicle.capacity.passengers || vehicle.capacity.seating || 4;
          console.log(`   ✅ Found capacity.passengers: ${capacity}`);
        } else if (typeof vehicle.capacity === 'number') {
          capacity = vehicle.capacity;
          console.log(`   ✅ Found capacity (number): ${capacity}`);
        }
      } else {
        console.log(`   ⚠️  Using default capacity: ${capacity}`);
      }
      
      const assigned = (vehicle.assignedCustomers || []).length;
      
      // Check driver
      let hasDriver = false;
      let driverName = 'No Driver';
      
      if (vehicle.assignedDriver != null) {
        if (typeof vehicle.assignedDriver === 'object') {
          hasDriver = vehicle.assignedDriver.driverId != null || vehicle.assignedDriver.name != null;
          driverName = vehicle.assignedDriver.name || 'Driver ID: ' + vehicle.assignedDriver.driverId;
        } else if (typeof vehicle.assignedDriver === 'string' && vehicle.assignedDriver.length > 0) {
          hasDriver = true;
          driverName = vehicle.assignedDriver;
        }
      } else if (vehicle.driverId != null && vehicle.driverId.length > 0) {
        hasDriver = true;
        driverName = 'Driver ID: ' + vehicle.driverId;
      }
      
      const driverSeats = hasDriver ? 1 : 0;
      const available = capacity - driverSeats - assigned;
      
      console.log(`   Driver: ${driverName} (${hasDriver ? 'YES' : 'NO'})`);
      console.log(`   Capacity: ${capacity}`);
      console.log(`   Assigned: ${assigned}`);
      console.log(`   Driver seats: ${driverSeats}`);
      console.log(`   Available: ${available}`);
      
      // Test for 4 customers
      const suitableFor4 = hasDriver && available >= 4;
      console.log(`   Suitable for 4 customers: ${suitableFor4 ? '✅ YES' : '❌ NO'}`);
      
      if (!suitableFor4) {
        if (!hasDriver) {
          console.log(`   Reason: No driver assigned`);
        } else {
          console.log(`   Reason: Only ${available} seats available (need 4)`);
        }
      }
    }
    
    // Summary
    const suitableVehicles = vehicles.filter(v => {
      let capacity = 4;
      if (v.seatCapacity != null) capacity = v.seatCapacity;
      else if (v.seatingCapacity != null) capacity = v.seatingCapacity;
      else if (v.capacity != null) {
        if (typeof v.capacity === 'object') {
          capacity = v.capacity.passengers || v.capacity.seating || 4;
        } else if (typeof v.capacity === 'number') {
          capacity = v.capacity;
        }
      }
      
      const assigned = (v.assignedCustomers || []).length;
      
      let hasDriver = false;
      if (v.assignedDriver != null) {
        if (typeof v.assignedDriver === 'object') {
          hasDriver = v.assignedDriver.driverId != null || v.assignedDriver.name != null;
        } else if (typeof v.assignedDriver === 'string' && v.assignedDriver.length > 0) {
          hasDriver = true;
        }
      } else if (v.driverId != null && v.driverId.length > 0) {
        hasDriver = true;
      }
      
      const driverSeats = hasDriver ? 1 : 0;
      const available = capacity - driverSeats - assigned;
      
      return hasDriver && available >= 4;
    });
    
    console.log('\n' + '='*80);
    console.log('SUMMARY');
    console.log('='*80);
    console.log(`Total vehicles: ${vehicles.length}`);
    console.log(`Suitable for 4 customers: ${suitableVehicles.length}`);
    
    if (suitableVehicles.length > 0) {
      console.log('\n✅ Suitable vehicles:');
      suitableVehicles.forEach((v, i) => {
        const name = v.name || v.vehicleNumber || v.registrationNumber || 'Unknown';
        const driverName = v.assignedDriver?.name || v.assignedDriver || 'Unknown';
        console.log(`   ${i + 1}. ${name} - Driver: ${driverName}`);
      });
    } else {
      console.log('\n❌ No suitable vehicles found!');
      console.log('\nTo fix:');
      console.log('1. Assign drivers to vehicles');
      console.log('2. Ensure vehicles have sufficient capacity');
      console.log('3. Check that vehicles are not fully booked');
    }
    
    console.log('='*80 + '\n');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

testVehicleCapacity();
