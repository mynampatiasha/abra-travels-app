// check-vehicles-via-api.js
// Check all vehicles through the backend API

const axios = require('axios');

const BACKEND_URL = 'http://localhost:3000';

async function checkVehiclesViaAPI() {
  try {
    console.log('='.repeat(80));
    console.log('CHECKING ALL VEHICLES VIA BACKEND API');
    console.log('='.repeat(80));
    
    // Get all vehicles from API
    console.log('\n📡 Fetching vehicles from backend...\n');
    
    const response = await axios.get(`${BACKEND_URL}/api/admin/vehicles`);
    
    if (!response.data || !response.data.success) {
      console.log('❌ Failed to fetch vehicles');
      console.log('Response:', response.data);
      return;
    }
    
    const vehicles = response.data.data || [];
    
    console.log(`📊 Total Vehicles Found: ${vehicles.length}\n`);
    
    if (vehicles.length === 0) {
      console.log('❌ NO VEHICLES IN DATABASE!');
      console.log('\n💡 You need to add vehicles:');
      console.log('   1. Go to Admin → Vehicle Management');
      console.log('   2. Click "Add Vehicle"');
      console.log('   3. Set seat capacity, assign driver, set status to active');
      return;
    }
    
    // Analyze each vehicle
    let availableCount = 0;
    let totalAvailableSeats = 0;
    
    for (let i = 0; i < vehicles.length; i++) {
      const vehicle = vehicles[i];
      
      console.log(`\n${'-'.repeat(80)}`);
      console.log(`VEHICLE ${i + 1}/${vehicles.length}`);
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
      const totalSeats = vehicle.seatCapacity || 0;
      const assignedSeats = vehicle.assignedCustomers?.length || 0;
      const availableSeats = totalSeats - assignedSeats;
      
      console.log(`   Total Seats: ${totalSeats}`);
      console.log(`   Assigned: ${assignedSeats}`);
      console.log(`   Available: ${availableSeats}`);
      
      if (totalSeats > 0) {
        const filledSeats = '🪑'.repeat(Math.min(assignedSeats, totalSeats));
        const emptySeats = '⬜'.repeat(Math.max(0, availableSeats));
        console.log(`   Visual: ${filledSeats}${emptySeats}`);
        
        const percentage = totalSeats > 0 ? ((assignedSeats / totalSeats) * 100).toFixed(0) : 0;
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
      
      // Compatibility Checks
      console.log(`\n✅ Compatibility Checks:`);
      
      const checks = {
        hasCapacity: totalSeats > 0,
        hasDriver: !!vehicle.assignedDriver,
        isActive: vehicle.status === 'active',
        hasAvailableSeats: availableSeats > 0,
        hasOrganization: !!(vehicle.organizationName || vehicle.companyName)
      };
      
      if (!checks.hasCapacity) {
        console.log(`   ❌ PROBLEM: Seat capacity not set (${totalSeats})`);
        console.log(`      Solution: Edit vehicle → Set seat capacity (e.g., 7 for SUV)`);
      } else {
        console.log(`   ✅ Seat capacity: ${totalSeats}`);
      }
      
      if (!checks.hasDriver) {
        console.log(`   ❌ PROBLEM: No driver assigned`);
        console.log(`      Solution: Edit vehicle → Assign a driver`);
      } else {
        console.log(`   ✅ Driver assigned`);
      }
      
      if (!checks.isActive) {
        console.log(`   ❌ PROBLEM: Status is "${vehicle.status}"`);
        console.log(`      Solution: Edit vehicle → Change status to "active"`);
      } else {
        console.log(`   ✅ Status is active`);
      }
      
      if (!checks.hasAvailableSeats) {
        console.log(`   ❌ PROBLEM: Vehicle is FULL (${assignedSeats}/${totalSeats})`);
        console.log(`      Solution: Use another vehicle or wait for trips to complete`);
      } else {
        console.log(`   ✅ Available seats: ${availableSeats}`);
      }
      
      if (!checks.hasOrganization) {
        console.log(`   ⚠️  WARNING: No organization set`);
        console.log(`      May not match customer organizations`);
      } else {
        console.log(`   ✅ Organization: ${vehicle.organizationName || vehicle.companyName}`);
      }
      
      // Overall Status
      console.log(`\n🎯 Overall Status:`);
      const canBeUsed = Object.values(checks).every(check => check === true);
      
      if (canBeUsed) {
        console.log(`   ✅ CAN BE USED FOR ROUTE OPTIMIZATION`);
        console.log(`   Can accommodate ${availableSeats} more customers`);
        availableCount++;
        totalAvailableSeats += availableSeats;
      } else {
        console.log(`   ❌ CANNOT BE USED - Fix problems above`);
      }
    }
    
    // Summary
    console.log(`\n\n${'='.repeat(80)}`);
    console.log('SUMMARY');
    console.log('='.repeat(80));
    
    const activeVehicles = vehicles.filter(v => v.status === 'active').length;
    const withDrivers = vehicles.filter(v => v.assignedDriver).length;
    const withCapacity = vehicles.filter(v => v.seatCapacity > 0).length;
    
    console.log(`\n📊 Statistics:`);
    console.log(`   Total Vehicles: ${vehicles.length}`);
    console.log(`   Active Status: ${activeVehicles}`);
    console.log(`   With Drivers: ${withDrivers}`);
    console.log(`   With Seat Capacity: ${withCapacity}`);
    console.log(`   Available for Use: ${availableCount}`);
    console.log(`   Total Available Seats: ${totalAvailableSeats}`);
    
    console.log(`\n🎯 Analysis:`);
    if (availableCount === 0) {
      console.log(`   ❌ NO VEHICLES AVAILABLE!`);
      console.log(`\n💡 Common Issues:`);
      console.log(`   • Vehicles don't have seat capacity set`);
      console.log(`   • Vehicles don't have drivers assigned`);
      console.log(`   • Vehicles are not marked as "active"`);
      console.log(`   • All vehicles are full`);
      console.log(`\n🔧 Fix in Vehicle Management:`);
      console.log(`   1. Open Admin → Vehicle Management`);
      console.log(`   2. For each vehicle, click Edit`);
      console.log(`   3. Set seat capacity (e.g., 7 for SUV, 4 for sedan)`);
      console.log(`   4. Assign a driver from dropdown`);
      console.log(`   5. Set status to "active"`);
      console.log(`   6. Save changes`);
    } else {
      console.log(`   ✅ ${availableCount} vehicles ready`);
      console.log(`   ✅ Can assign ${totalAvailableSeats} more customers`);
      
      if (availableCount < vehicles.length) {
        const unusable = vehicles.length - availableCount;
        console.log(`\n⚠️  ${unusable} vehicles cannot be used - check problems above`);
      }
    }
    
    console.log(`\n${'='.repeat(80)}`);
    console.log('CHECK COMPLETE');
    console.log('='.repeat(80) + '\n');
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    
    if (error.code === 'ECONNREFUSED') {
      console.log('\n💡 Backend is not running!');
      console.log('   Start backend: cd abra_fleet_backend && node index.js');
    } else if (error.response) {
      console.log('\n📋 Response:', error.response.data);
    }
  }
}

checkVehiclesViaAPI();
