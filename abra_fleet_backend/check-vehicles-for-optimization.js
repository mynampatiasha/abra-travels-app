// Check vehicles available for route optimization
require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function checkVehicles() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Get all vehicles
    const vehicles = await db.collection('vehicles').find({}).toArray();
    
    console.log('\n' + '='.repeat(80));
    console.log('VEHICLE OPTIMIZATION CHECK');
    console.log('='.repeat(80));
    console.log(`Total vehicles: ${vehicles.length}\n`);
    
    for (let i = 0; i < vehicles.length; i++) {
      const vehicle = vehicles[i];
      console.log(`\n${i + 1}. Vehicle: ${vehicle.name || vehicle.vehicleNumber || 'Unknown'}`);
      console.log(`   ID: ${vehicle._id}`);
      console.log(`   License: ${vehicle.licensePlate || vehicle.registrationNumber || 'N/A'}`);
      console.log(`   Seat Capacity: ${vehicle.seatCapacity || 'N/A'}`);
      console.log(`   Status: ${vehicle.status || 'N/A'}`);
      
      // Check driver assignment
      console.log(`\n   Driver Assignment:`);
      console.log(`   - assignedDriver field: ${JSON.stringify(vehicle.assignedDriver)}`);
      console.log(`   - driverId field: ${vehicle.driverId}`);
      
      let hasDriver = false;
      let driverName = 'No Driver';
      
      if (vehicle.assignedDriver) {
        if (typeof vehicle.assignedDriver === 'object') {
          hasDriver = vehicle.assignedDriver._id || vehicle.assignedDriver.driverId || vehicle.assignedDriver.name;
          driverName = vehicle.assignedDriver.name || 'Driver ID: ' + (vehicle.assignedDriver._id || vehicle.assignedDriver.driverId);
        } else if (typeof vehicle.assignedDriver === 'string' && vehicle.assignedDriver.length > 0) {
          hasDriver = true;
          driverName = vehicle.assignedDriver;
        }
      } else if (vehicle.driverId && vehicle.driverId.length > 0) {
        hasDriver = true;
        driverName = 'Driver ID: ' + vehicle.driverId;
      }
      
      console.log(`   - Has Driver: ${hasDriver ? '✅ YES' : '❌ NO'}`);
      console.log(`   - Driver Name: ${driverName}`);
      
      // Check capacity
      const totalSeats = vehicle.seatCapacity || 4;
      const assignedSeats = (vehicle.assignedCustomers || []).length;
      const availableSeats = totalSeats - (hasDriver ? 1 : 0) - assignedSeats;
      
      console.log(`\n   Capacity:`);
      console.log(`   - Total Seats: ${totalSeats}`);
      console.log(`   - Assigned Customers: ${assignedSeats}`);
      console.log(`   - Available Seats: ${availableSeats}`);
      
      // Check if suitable for 3 customers
      const suitableFor3 = hasDriver && availableSeats >= 3;
      console.log(`\n   Suitable for 3 customers: ${suitableFor3 ? '✅ YES' : '❌ NO'}`);
      
      if (!suitableFor3) {
        console.log(`   Reason: ${!hasDriver ? 'No driver assigned' : `Only ${availableSeats} seats available (need 3)`}`);
      }
      
      console.log(`   ${'─'.repeat(76)}`);
    }
    
    // Summary
    const suitableVehicles = vehicles.filter(v => {
      let hasDriver = false;
      if (v.assignedDriver) {
        if (typeof v.assignedDriver === 'object') {
          hasDriver = v.assignedDriver._id || v.assignedDriver.driverId || v.assignedDriver.name;
        } else if (typeof v.assignedDriver === 'string' && v.assignedDriver.length > 0) {
          hasDriver = true;
        }
      } else if (v.driverId && v.driverId.length > 0) {
        hasDriver = true;
      }
      
      const totalSeats = v.seatCapacity || 4;
      const assignedSeats = (v.assignedCustomers || []).length;
      const availableSeats = totalSeats - (hasDriver ? 1 : 0) - assignedSeats;
      
      return hasDriver && availableSeats >= 3;
    });
    
    console.log('\n' + '='.repeat(80));
    console.log('SUMMARY');
    console.log('='.repeat(80));
    console.log(`Total vehicles: ${vehicles.length}`);
    console.log(`Suitable for 3 customers: ${suitableVehicles.length}`);
    console.log(`Not suitable: ${vehicles.length - suitableVehicles.length}`);
    
    if (suitableVehicles.length === 0) {
      console.log('\n⚠️  WARNING: No vehicles available for route optimization!');
      console.log('\nTo fix this:');
      console.log('1. Assign drivers to vehicles in Vehicle Management');
      console.log('2. Ensure vehicles have sufficient seat capacity');
      console.log('3. Check that vehicles are not fully booked');
    } else {
      console.log('\n✅ Suitable vehicles found:');
      suitableVehicles.forEach((v, i) => {
        const driverName = v.assignedDriver?.name || v.assignedDriver || v.driverId || 'Unknown';
        console.log(`   ${i + 1}. ${v.name || v.vehicleNumber} - Driver: ${driverName}`);
      });
    }
    
    console.log('='.repeat(80) + '\n');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkVehicles();
