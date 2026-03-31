// check-vehicles-for-compatibility.js - Check why no vehicles are compatible
const { MongoClient } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function checkVehicles() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB');
    
    const db = client.db();
    
    // Check all vehicles
    console.log('\n' + '='.repeat(80));
    console.log('🚗 CHECKING ALL VEHICLES');
    console.log('='.repeat(80));
    
    const allVehicles = await db.collection('vehicles').find({}).toArray();
    console.log(`\n📊 Total vehicles in database: ${allVehicles.length}`);
    
    if (allVehicles.length === 0) {
      console.log('❌ NO VEHICLES FOUND IN DATABASE!');
      console.log('\n💡 Solution: Add vehicles through the admin panel or import them.');
      return;
    }
    
    // Check active vehicles (case-insensitive)
    const activeVehicles = await db.collection('vehicles').find({ status: { $regex: /^active$/i } }).toArray();
    console.log(`✅ Active vehicles: ${activeVehicles.length}`);
    
    // Check vehicles with drivers (case-insensitive)
    const vehiclesWithDrivers = await db.collection('vehicles').find({
      status: { $regex: /^active$/i },
      assignedDriver: { $exists: true, $ne: null }
    }).toArray();
    console.log(`✅ Active vehicles with assigned drivers: ${vehiclesWithDrivers.length}`);
    
    // Show details of all vehicles
    console.log('\n📋 Vehicle Details:');
    console.log('='.repeat(80));
    
    for (let i = 0; i < allVehicles.length; i++) {
      const v = allVehicles[i];
      console.log(`\n${i + 1}. ${v.name || v.vehicleNumber || 'Unknown'}`);
      console.log(`   ID: ${v._id}`);
      console.log(`   Status: ${v.status || 'N/A'}`);
      console.log(`   License Plate: ${v.licensePlate || v.registrationNumber || 'N/A'}`);
      console.log(`   Seat Capacity: ${v.seatCapacity || v.seatingCapacity || 'N/A'}`);
      console.log(`   Assigned Driver: ${v.assignedDriver ? JSON.stringify(v.assignedDriver) : 'NONE'}`);
      console.log(`   Driver ID: ${v.driverId || 'N/A'}`);
      
      // Check if this vehicle is compatible (case-insensitive)
      const isActive = v.status && v.status.toLowerCase() === 'active';
      const hasDriver = v.assignedDriver && v.assignedDriver !== null;
      const isCompatible = isActive && hasDriver;
      
      if (isCompatible) {
        console.log(`   ✅ COMPATIBLE`);
      } else {
        console.log(`   ❌ INCOMPATIBLE:`);
        if (!isActive) console.log(`      - Status is not 'active' (current: ${v.status})`);
        if (!hasDriver) console.log(`      - No assigned driver`);
      }
    }
    
    // Check if there are any drivers in the system
    console.log('\n' + '='.repeat(80));
    console.log('👤 CHECKING DRIVERS');
    console.log('='.repeat(80));
    
    const allDrivers = await db.collection('users').find({ role: 'driver' }).toArray();
    console.log(`\n📊 Total drivers in database: ${allDrivers.length}`);
    
    if (allDrivers.length === 0) {
      console.log('❌ NO DRIVERS FOUND IN DATABASE!');
      console.log('\n💡 Solution: Add drivers through the admin panel.');
    } else {
      console.log('\n📋 Driver Details:');
      for (let i = 0; i < Math.min(allDrivers.length, 5); i++) {
        const d = allDrivers[i];
        console.log(`   ${i + 1}. ${d.name || 'Unknown'} (${d.email || 'N/A'})`);
        console.log(`      ID: ${d._id}`);
        console.log(`      Status: ${d.status || 'N/A'}`);
      }
      if (allDrivers.length > 5) {
        console.log(`   ... and ${allDrivers.length - 5} more drivers`);
      }
    }
    
    // Provide recommendations
    console.log('\n' + '='.repeat(80));
    console.log('💡 RECOMMENDATIONS');
    console.log('='.repeat(80));
    
    if (vehiclesWithDrivers.length === 0) {
      console.log('\n❌ NO COMPATIBLE VEHICLES FOUND');
      console.log('\nTo fix this:');
      
      if (allVehicles.length === 0) {
        console.log('1. Add vehicles through Admin Panel → Vehicle Management');
      } else if (activeVehicles.length === 0) {
        console.log('1. Set vehicle status to "active" in Admin Panel');
      } else if (allDrivers.length === 0) {
        console.log('1. Add drivers through Admin Panel → Driver Management');
      } else {
        console.log('1. Assign drivers to vehicles:');
        console.log('   - Go to Admin Panel → Vehicle Management');
        console.log('   - Edit each vehicle');
        console.log('   - Select a driver from the dropdown');
        console.log('   - Save the vehicle');
      }
    } else {
      console.log(`\n✅ ${vehiclesWithDrivers.length} compatible vehicles found!`);
      console.log('\nThese vehicles are ready for route optimization.');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed');
  }
}

checkVehicles();
