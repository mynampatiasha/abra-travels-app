// check-all-vehicles-seat-availability.js
// Check seat availability for EVERY vehicle in the database

const { MongoClient } = require('mongodb');

const uri = 'mongodb://localhost:27017';
const dbName = 'abra_fleet';

async function checkAllVehicleSeats() {
  const client = new MongoClient(uri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(dbName);
    
    console.log('='.repeat(80));
    console.log('CHECKING SEAT AVAILABILITY FOR ALL VEHICLES');
    console.log('='.repeat(80));
    
    // Get ALL vehicles
    const allVehicles = await db.collection('vehicles').find({}).toArray();
    
    console.log(`\n📊 Total Vehicles in Database: ${allVehicles.length}\n`);
    
    if (allVehicles.length === 0) {
      console.log('❌ NO VEHICLES FOUND IN DATABASE!');
      console.log('\n💡 You need to add vehicles first:');
      console.log('   1. Go to Admin → Vehicle Management');
      console.log('   2. Click "Add Vehicle"');
      console.log('   3. Fill in vehicle details');
      return;
    }
    
    // Check each vehicle
    for (let i = 0; i < allVehicles.length; i++) {
      const vehicle = allVehicles[i];
      
      console.log(`\n${'-'.repeat(80)}`);
      console.log(`VEHICLE ${i + 1}/${allVehicles.length}`);
      console.log(`${'-'.repeat(80)}`);
      
      // Basic Info
      console.log(`📋 Basic Information:`);
      console.log(`   Registration: ${vehicle.registrationNumber || vehicle.vehicleNumber || 'N/A'}`);
      console.log(`   Name: ${vehicle.name || 'N/A'}`);
      console.log(`   Type: ${vehicle.vehicleType || 'N/A'}`);
      console.log(`   Status: ${vehicle.status || 'N/A'}`);
      console.log(`   Organization: ${vehicle.organizationName || vehicle.companyName || 'N/A'}`);
      
      // Seat Capacity
      console.log(`\n💺 Seat Capacity:`);
      console.log(`   Total Seats: ${vehicle.seatCapacity || 'NOT SET'}`);
      
      // Check assigned rosters
      const assignedRosters = await db.collection('rosters').find({
        $or: [
          { 'assignedVehicle.vehicleId': vehicle._id },
          { 'assignedVehicle': vehicle._id },
          { 'vehicleId': vehicle._id.toString() }
        ],
        status: { $in: ['assigned', 'in_progress', 'active', 'scheduled'] }
      }).toArray();
      
      const assignedCount = assignedRosters.length;
      const totalSeats = vehicle.seatCapacity || 0;
      const availableSeats = totalSeats - assignedCount;
      
      console.log(`   Assigned Customers: ${assignedCount}`);
      console.log(`   Available Seats: ${availableSeats}`);
      
      // Visual representation
      if (totalSeats > 0) {
        const filledSeats = '🪑'.repeat(Math.min(assignedCount, totalSeats));
        const emptySeats = '⬜'.repeat(Math.max(0, totalSeats - assignedCount));
        console.log(`   Visual: ${filledSeats}${emptySeats}`);
        
        const percentage = ((assignedCount / totalSeats) * 100).toFixed(0);
        console.log(`   Occupancy: ${percentage}%`);
      }
      
      // Driver Info
      console.log(`\n👤 Driver Information:`);
      if (vehicle.assignedDriver) {
        if (typeof vehicle.assignedDriver === 'object') {
          console.log(`   Driver: ${vehicle.assignedDriver.name || 'Unknown'}`);
          console.log(`   Phone: ${vehicle.assignedDriver.phone || 'N/A'}`);
        } else {
          console.log(`   Driver ID: ${vehicle.assignedDriver}`);
        }
      } else {
        console.log(`   Driver: ❌ NO DRIVER ASSIGNED`);
      }
      
      // Compatibility Check
      console.log(`\n✅ Compatibility Checks:`);
      
      // Check 1: Has seat capacity defined
      if (!vehicle.seatCapacity || vehicle.seatCapacity === 0) {
        console.log(`   ❌ PROBLEM: Seat capacity not set!`);
        console.log(`      Solution: Edit vehicle and set seat capacity`);
      } else {
        console.log(`   ✅ Seat capacity defined: ${vehicle.seatCapacity}`);
      }
      
      // Check 2: Has driver assigned
      if (!vehicle.assignedDriver) {
        console.log(`   ❌ PROBLEM: No driver assigned!`);
        console.log(`      Solution: Assign a driver to this vehicle`);
      } else {
        console.log(`   ✅ Driver assigned`);
      }
      
      // Check 3: Vehicle status
      if (vehicle.status !== 'active') {
        console.log(`   ❌ PROBLEM: Vehicle status is "${vehicle.status}"!`);
        console.log(`      Solution: Change status to "active"`);
      } else {
        console.log(`   ✅ Vehicle is active`);
      }
      
      // Check 4: Has available seats
      if (availableSeats <= 0) {
        console.log(`   ❌ PROBLEM: Vehicle is FULL (${assignedCount}/${totalSeats} seats used)!`);
        console.log(`      Solution: Wait for trips to complete or use another vehicle`);
      } else {
        console.log(`   ✅ Has available seats: ${availableSeats}/${totalSeats}`);
      }
      
      // Check 5: Organization set
      if (!vehicle.organizationName && !vehicle.companyName) {
        console.log(`   ⚠️  WARNING: No organization set`);
        console.log(`      This vehicle may not match customer organizations`);
      } else {
        console.log(`   ✅ Organization set: ${vehicle.organizationName || vehicle.companyName}`);
      }
      
      // Overall Status
      console.log(`\n🎯 Overall Status:`);
      const canBeUsed = 
        vehicle.seatCapacity > 0 &&
        vehicle.assignedDriver &&
        vehicle.status === 'active' &&
        availableSeats > 0;
      
      if (canBeUsed) {
        console.log(`   ✅ CAN BE USED FOR ROUTE OPTIMIZATION`);
        console.log(`   Available for ${availableSeats} more customers`);
      } else {
        console.log(`   ❌ CANNOT BE USED - See problems above`);
      }
      
      // Show assigned customers if any
      if (assignedRosters.length > 0) {
        console.log(`\n📋 Assigned Customers:`);
        for (let j = 0; j < Math.min(assignedRosters.length, 5); j++) {
          const roster = assignedRosters[j];
          console.log(`   ${j + 1}. ${roster.customerName || roster.employeeDetails?.name || 'Unknown'}`);
          console.log(`      Email: ${roster.customerEmail || roster.employeeDetails?.email || 'N/A'}`);
        }
        if (assignedRosters.length > 5) {
          console.log(`   ... and ${assignedRosters.length - 5} more`);
        }
      }
    }
    
    // Summary
    console.log(`\n\n${'='.repeat(80)}`);
    console.log('SUMMARY');
    console.log('='.repeat(80));
    
    const activeVehicles = allVehicles.filter(v => v.status === 'active').length;
    const withDrivers = allVehicles.filter(v => v.assignedDriver).length;
    const withCapacity = allVehicles.filter(v => v.seatCapacity > 0).length;
    
    // Calculate available vehicles
    let availableVehicles = 0;
    let totalAvailableSeats = 0;
    
    for (const vehicle of allVehicles) {
      const assignedCount = await db.collection('rosters').countDocuments({
        $or: [
          { 'assignedVehicle.vehicleId': vehicle._id },
          { 'assignedVehicle': vehicle._id },
          { 'vehicleId': vehicle._id.toString() }
        ],
        status: { $in: ['assigned', 'in_progress', 'active', 'scheduled'] }
      });
      
      const totalSeats = vehicle.seatCapacity || 0;
      const availableSeats = totalSeats - assignedCount;
      
      const canBeUsed = 
        vehicle.seatCapacity > 0 &&
        vehicle.assignedDriver &&
        vehicle.status === 'active' &&
        availableSeats > 0;
      
      if (canBeUsed) {
        availableVehicles++;
        totalAvailableSeats += availableSeats;
      }
    }
    
    console.log(`\n📊 Vehicle Statistics:`);
    console.log(`   Total Vehicles: ${allVehicles.length}`);
    console.log(`   Active Status: ${activeVehicles}`);
    console.log(`   With Drivers: ${withDrivers}`);
    console.log(`   With Seat Capacity: ${withCapacity}`);
    console.log(`   Available for Use: ${availableVehicles}`);
    console.log(`   Total Available Seats: ${totalAvailableSeats}`);
    
    console.log(`\n🎯 What This Means:`);
    if (availableVehicles === 0) {
      console.log(`   ❌ NO VEHICLES AVAILABLE for route optimization!`);
      console.log(`\n💡 Common Reasons:`);
      console.log(`   1. All vehicles are full`);
      console.log(`   2. Vehicles don't have drivers assigned`);
      console.log(`   3. Vehicles are not active`);
      console.log(`   4. Seat capacity not set`);
      console.log(`\n🔧 Solutions:`);
      console.log(`   1. Go to Vehicle Management`);
      console.log(`   2. Check each vehicle's status`);
      console.log(`   3. Assign drivers to vehicles`);
      console.log(`   4. Set seat capacity for each vehicle`);
      console.log(`   5. Make sure vehicles are marked as "active"`);
    } else {
      console.log(`   ✅ ${availableVehicles} vehicles available`);
      console.log(`   ✅ Can accommodate ${totalAvailableSeats} more customers`);
      console.log(`\n💡 If only 3 customers were assigned:`);
      console.log(`   - Check if customers belong to same organization as vehicles`);
      console.log(`   - Check if customer email domains match vehicle organizations`);
      console.log(`   - Check route optimization settings`);
    }
    
    console.log(`\n${'='.repeat(80)}`);
    console.log('CHECK COMPLETE');
    console.log('='.repeat(80) + '\n');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

checkAllVehicleSeats();
