// check-why-only-3-assigned.js
// Diagnose why only 3 customers were assigned when more are pending

const { MongoClient } = require('mongodb');

const uri = 'mongodb://localhost:27017';
const dbName = 'abra_fleet';

async function diagnoseAssignmentIssue() {
  const client = new MongoClient(uri);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db(dbName);
    
    console.log('='.repeat(80));
    console.log('DIAGNOSING: WHY ONLY 3 CUSTOMERS WERE ASSIGNED');
    console.log('='.repeat(80));
    
    // 1. Check pending rosters
    console.log('\n1️⃣  PENDING ROSTERS (Waiting for Assignment):\n');
    const pendingRosters = await db.collection('rosters').find({
      status: 'pending_assignment'
    }).toArray();
    
    console.log(`Total Pending: ${pendingRosters.length}`);
    
    if (pendingRosters.length > 0) {
      console.log('\nSample pending customers:');
      pendingRosters.slice(0, 5).forEach((r, i) => {
        console.log(`   ${i + 1}. ${r.customerName || r.employeeDetails?.name} (${r.customerEmail})`);
        console.log(`      Organization: ${r.organizationName || 'N/A'}`);
      });
      if (pendingRosters.length > 5) {
        console.log(`   ... and ${pendingRosters.length - 5} more`);
      }
    }
    
    // 2. Check assigned rosters
    console.log('\n\n2️⃣  ASSIGNED ROSTERS (Already Assigned):\n');
    const assignedRosters = await db.collection('rosters').find({
      status: 'assigned'
    }).toArray();
    
    console.log(`Total Assigned: ${assignedRosters.length}`);
    
    if (assignedRosters.length > 0) {
      console.log('\nAssigned customers:');
      assignedRosters.forEach((r, i) => {
        console.log(`   ${i + 1}. ${r.customerName || r.employeeDetails?.name}`);
        console.log(`      Vehicle: ${r.assignedVehicle?.registrationNumber || 'N/A'}`);
        console.log(`      Driver: ${r.assignedDriver?.name || 'N/A'}`);
        console.log(`      Organization: ${r.organizationName || 'N/A'}`);
      });
    }
    
    // 3. Check vehicles
    console.log('\n\n3️⃣  VEHICLES STATUS:\n');
    const vehicles = await db.collection('vehicles').find({}).toArray();
    
    console.log(`Total Vehicles: ${vehicles.length}`);
    
    let usableVehicles = 0;
    let totalAvailableSeats = 0;
    
    for (const vehicle of vehicles) {
      const hasCapacity = vehicle.seatCapacity > 0 || vehicle.capacity?.passengers > 0;
      const hasDriver = !!(vehicle.assignedDriver || vehicle.driver || vehicle.driverId);
      const isActive = vehicle.status && vehicle.status.toLowerCase() === 'active';
      
      const seatCapacity = vehicle.seatCapacity || vehicle.capacity?.passengers || 0;
      
      // Count assigned rosters for this vehicle
      const assignedCount = await db.collection('rosters').countDocuments({
        $or: [
          { 'assignedVehicle.vehicleId': vehicle._id },
          { 'assignedVehicle': vehicle._id },
          { 'vehicleId': vehicle._id.toString() }
        ],
        status: 'assigned'
      });
      
      const availableSeats = seatCapacity - assignedCount;
      
      if (hasCapacity && hasDriver && isActive && availableSeats > 0) {
        usableVehicles++;
        totalAvailableSeats += availableSeats;
      }
      
      console.log(`\n   ${vehicle.registrationNumber || vehicle.vehicleNumber}:`);
      console.log(`      Capacity: ${seatCapacity} | Assigned: ${assignedCount} | Available: ${availableSeats}`);
      console.log(`      Driver: ${hasDriver ? '✅' : '❌'} | Active: ${isActive ? '✅' : '❌'}`);
      console.log(`      Can Use: ${hasCapacity && hasDriver && isActive && availableSeats > 0 ? '✅ YES' : '❌ NO'}`);
    }
    
    console.log(`\n   Summary:`);
    console.log(`      Usable Vehicles: ${usableVehicles}`);
    console.log(`      Total Available Seats: ${totalAvailableSeats}`);
    
    // 4. Analysis
    console.log('\n\n4️⃣  ANALYSIS:\n');
    
    if (assignedRosters.length === 3 && pendingRosters.length > 0) {
      console.log(`❌ PROBLEM CONFIRMED: Only 3 customers assigned, but ${pendingRosters.length} are still pending!`);
      
      console.log('\n🔍 Possible Reasons:\n');
      
      // Check organization mismatch
      const assignedOrgs = new Set(assignedRosters.map(r => r.organizationName));
      const pendingOrgs = new Set(pendingRosters.map(r => r.organizationName));
      const vehicleOrgs = new Set(vehicles.map(v => v.organizationName || v.companyName));
      
      console.log(`   Organizations in assigned rosters: ${Array.from(assignedOrgs).join(', ')}`);
      console.log(`   Organizations in pending rosters: ${Array.from(pendingOrgs).join(', ')}`);
      console.log(`   Organizations in vehicles: ${Array.from(vehicleOrgs).join(', ')}`);
      
      // Check if organizations match
      const pendingOrgsArray = Array.from(pendingOrgs);
      const vehicleOrgsArray = Array.from(vehicleOrgs);
      
      const mismatch = pendingOrgsArray.some(org => !vehicleOrgsArray.includes(org));
      
      if (mismatch) {
        console.log(`\n   ⚠️  ORGANIZATION MISMATCH DETECTED!`);
        console.log(`   Pending customers have organizations that don't match any vehicle`);
        console.log(`\n   Solution:`);
        console.log(`   1. Check vehicle organizations in Vehicle Management`);
        console.log(`   2. Make sure vehicles have same organization as customers`);
        console.log(`   3. Or add vehicles for the missing organizations`);
      }
      
      // Check if only one vehicle was used
      const vehiclesUsed = new Set(assignedRosters.map(r => r.assignedVehicle?.registrationNumber));
      if (vehiclesUsed.size === 1) {
        console.log(`\n   ⚠️  ONLY 1 VEHICLE WAS USED!`);
        console.log(`   Vehicle: ${Array.from(vehiclesUsed)[0]}`);
        console.log(`   This suggests other vehicles couldn't be used`);
        console.log(`\n   Possible reasons:`);
        console.log(`   - Other vehicles don't have drivers assigned`);
        console.log(`   - Other vehicles have wrong organization`);
        console.log(`   - Other vehicles are not active`);
      }
      
      // Check if route optimization was stopped early
      if (usableVehicles > 1 && totalAvailableSeats > 3) {
        console.log(`\n   ⚠️  ROUTE OPTIMIZATION STOPPED EARLY!`);
        console.log(`   You have ${usableVehicles} usable vehicles with ${totalAvailableSeats} available seats`);
        console.log(`   But only 3 customers were assigned`);
        console.log(`\n   This could mean:`);
        console.log(`   - Route optimization encountered an error`);
        console.log(`   - Only 3 customers were selected for assignment`);
        console.log(`   - Organization/shift/timing mismatch for other customers`);
      }
      
    } else if (pendingRosters.length === 0) {
      console.log(`✅ All customers have been assigned!`);
      console.log(`   No pending rosters remaining`);
    } else {
      console.log(`📊 Current Status:`);
      console.log(`   Assigned: ${assignedRosters.length}`);
      console.log(`   Pending: ${pendingRosters.length}`);
      console.log(`   Available Seats: ${totalAvailableSeats}`);
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('RECOMMENDATIONS');
    console.log('='.repeat(80));
    
    if (pendingRosters.length > 0 && totalAvailableSeats > 0) {
      console.log('\n💡 To assign more customers:\n');
      console.log('1. Go to Admin → Customer Management → Pending Rosters');
      console.log('2. Select MORE customers (not just 3)');
      console.log('3. Click "Route Optimization"');
      console.log('4. System will assign them to available vehicles');
      console.log('\nOR');
      console.log('\n1. Select ALL pending customers');
      console.log('2. Run route optimization');
      console.log('3. System will distribute across all available vehicles');
    }
    
    console.log('\n' + '='.repeat(80) + '\n');
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

diagnoseAssignmentIssue();
