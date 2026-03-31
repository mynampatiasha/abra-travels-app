// check-all-vehicles-driver-status.js
// Check driver assignment status for ALL vehicles

const { MongoClient } = require('mongodb');

const uri = 'mongodb://localhost:27017';
const dbName = 'abra_fleet';

async function checkAllVehiclesDriverStatus() {
  const client = new MongoClient(uri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(dbName);
    
    console.log('='.repeat(80));
    console.log('CHECKING DRIVER ASSIGNMENT FOR ALL VEHICLES');
    console.log('='.repeat(80));
    
    const vehicles = await db.collection('vehicles').find({}).toArray();
    
    console.log(`\n📊 Total Vehicles: ${vehicles.length}\n`);
    
    let withDriver = 0;
    let withoutDriver = 0;
    let activeWithoutDriver = 0;
    
    for (let i = 0; i < vehicles.length; i++) {
      const vehicle = vehicles[i];
      
      console.log(`${'-'.repeat(80)}`);
      console.log(`VEHICLE ${i + 1}/${vehicles.length}: ${vehicle.registrationNumber || vehicle.vehicleNumber}`);
      console.log(`${'-'.repeat(80)}`);
      
      console.log(`Type: ${vehicle.vehicleType || 'N/A'}`);
      console.log(`Seat Capacity: ${vehicle.seatCapacity || 0}`);
      console.log(`Status: ${vehicle.status || 'N/A'}`);
      console.log(`Organization: ${vehicle.organizationName || vehicle.companyName || 'N/A'}`);
      
      // Check driver assignment
      if (vehicle.assignedDriver) {
        console.log(`✅ Driver: ASSIGNED`);
        if (typeof vehicle.assignedDriver === 'object') {
          console.log(`   Name: ${vehicle.assignedDriver.name || 'Unknown'}`);
          console.log(`   Code: ${vehicle.assignedDriver.driverCode || 'N/A'}`);
          console.log(`   Phone: ${vehicle.assignedDriver.phone || 'N/A'}`);
        } else {
          console.log(`   Driver ID: ${vehicle.assignedDriver}`);
        }
        withDriver++;
      } else {
        console.log(`❌ Driver: NOT ASSIGNED`);
        withoutDriver++;
        
        if (vehicle.status === 'active') {
          activeWithoutDriver++;
          console.log(`   ⚠️  WARNING: Vehicle is ACTIVE but has NO DRIVER!`);
          console.log(`   This vehicle CANNOT be used for route optimization`);
        }
      }
      
      // Overall usability
      const canBeUsed = 
        vehicle.seatCapacity > 0 &&
        vehicle.assignedDriver &&
        vehicle.status === 'active';
      
      console.log(`\n🎯 Can be used: ${canBeUsed ? '✅ YES' : '❌ NO'}`);
      
      if (!canBeUsed) {
        console.log(`Reasons:`);
        if (!vehicle.seatCapacity || vehicle.seatCapacity === 0) {
          console.log(`   ❌ No seat capacity set`);
        }
        if (!vehicle.assignedDriver) {
          console.log(`   ❌ No driver assigned`);
        }
        if (vehicle.status !== 'active') {
          console.log(`   ❌ Status is not active (${vehicle.status})`);
        }
      }
      
      console.log('');
    }
    
    // Summary
    console.log('='.repeat(80));
    console.log('SUMMARY');
    console.log('='.repeat(80));
    console.log(`\nTotal Vehicles: ${vehicles.length}`);
    console.log(`With Driver Assigned: ${withDriver}`);
    console.log(`Without Driver: ${withoutDriver}`);
    console.log(`Active but No Driver: ${activeWithoutDriver}`);
    
    if (withoutDriver > 0) {
      console.log(`\n⚠️  ${withoutDriver} vehicles need driver assignment!`);
      console.log(`\n💡 To fix:`);
      console.log(`   1. Go to Admin → Vehicle Management`);
      console.log(`   2. Click "Edit" on each vehicle without a driver`);
      console.log(`   3. Select a driver from the "Assigned Driver" dropdown`);
      console.log(`   4. Save changes`);
      
      if (activeWithoutDriver > 0) {
        console.log(`\n🚨 CRITICAL: ${activeWithoutDriver} ACTIVE vehicles have no driver!`);
        console.log(`   These vehicles are marked as active but cannot be used`);
        console.log(`   This is why route optimization is not using them`);
      }
    } else {
      console.log(`\n✅ All vehicles have drivers assigned!`);
    }
    
    console.log('\n' + '='.repeat(80) + '\n');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkAllVehiclesDriverStatus();
