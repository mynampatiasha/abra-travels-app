const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

async function verifyRosterAssignmentData() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db('fleet_management');
    
    console.log('🔍 CHECKING ASSIGNED ROSTERS DATA STRUCTURE');
    console.log('='.repeat(80) + '\n');
    
    // Get all assigned rosters
    const assignedRosters = await db.collection('rosters').find({
      status: 'assigned'
    }).limit(5).toArray();
    
    console.log(`📊 Found ${assignedRosters.length} assigned rosters\n`);
    
    if (assignedRosters.length === 0) {
      console.log('⚠️  No assigned rosters found in database');
      console.log('💡 This means rosters have not been assigned yet\n');
      return;
    }
    
    // Check each roster's data structure
    assignedRosters.forEach((roster, index) => {
      console.log(`\n${'='.repeat(80)}`);
      console.log(`📋 ROSTER ${index + 1}: ${roster.customerName || 'Unknown'}`);
      console.log('='.repeat(80));
      
      // Customer Details
      console.log('\n👤 CUSTOMER DETAILS:');
      console.log(`   ✓ Customer Name: ${roster.customerName || '❌ MISSING'}`);
      console.log(`   ✓ Customer Email: ${roster.customerEmail || '❌ MISSING'}`);
      console.log(`   ✓ Customer Phone: ${roster.employeeDetails?.phone || roster.customerPhone || '❌ MISSING'}`);
      console.log(`   ✓ Office Location: ${roster.officeLocation || '❌ MISSING'}`);
      console.log(`   ✓ Roster Type: ${roster.rosterType || '❌ MISSING'}`);
      console.log(`   ✓ Start Time: ${roster.startTime || '❌ MISSING'}`);
      console.log(`   ✓ End Time: ${roster.endTime || '❌ MISSING'}`);
      
      // Pickup/Drop Locations
      console.log('\n📍 LOCATION DETAILS:');
      console.log(`   ✓ Login Pickup Address: ${roster.loginPickupAddress || '❌ MISSING'}`);
      console.log(`   ✓ Logout Drop Address: ${roster.logoutDropAddress || '❌ MISSING'}`);
      if (roster.loginPickupLocation) {
        console.log(`   ✓ Login Pickup Coordinates: (${roster.loginPickupLocation.latitude}, ${roster.loginPickupLocation.longitude})`);
      } else {
        console.log(`   ❌ Login Pickup Coordinates: MISSING`);
      }
      if (roster.logoutDropLocation) {
        console.log(`   ✓ Logout Drop Coordinates: (${roster.logoutDropLocation.latitude}, ${roster.logoutDropLocation.longitude})`);
      } else {
        console.log(`   ❌ Logout Drop Coordinates: MISSING`);
      }
      
      // Vehicle Details
      console.log('\n🚗 VEHICLE DETAILS:');
      console.log(`   ✓ Vehicle ID: ${roster.vehicleId || '❌ MISSING'}`);
      console.log(`   ✓ Vehicle Number: ${roster.vehicleNumber || '❌ MISSING'}`);
      
      // Driver Details
      console.log('\n👨‍✈️ DRIVER DETAILS:');
      console.log(`   ✓ Driver ID: ${roster.driverId || '❌ MISSING'}`);
      console.log(`   ✓ Driver Name: ${roster.driverName || '❌ MISSING'}`);
      console.log(`   ✓ Driver Phone: ${roster.driverPhone || '❌ MISSING'}`);
      
      // Assignment Details
      console.log('\n📅 ASSIGNMENT DETAILS:');
      console.log(`   ✓ Status: ${roster.status}`);
      console.log(`   ✓ Assigned At: ${roster.assignedAt || '❌ MISSING'}`);
      console.log(`   ✓ Assigned By: ${roster.assignedBy || '❌ MISSING'}`);
      console.log(`   ✓ Pickup Sequence: ${roster.pickupSequence || '❌ MISSING'}`);
      console.log(`   ✓ Optimized Pickup Time: ${roster.optimizedPickupTime || '❌ MISSING'}`);
      
      // Route Details
      if (roster.routeDetails) {
        console.log('\n🗺️ ROUTE DETAILS:');
        console.log(`   ✓ Total Distance: ${roster.routeDetails.totalDistance || '❌ MISSING'} km`);
        console.log(`   ✓ Total Time: ${roster.routeDetails.totalTime || '❌ MISSING'} mins`);
        console.log(`   ✓ Sequence: ${roster.routeDetails.sequence || '❌ MISSING'}`);
      } else {
        console.log('\n❌ ROUTE DETAILS: MISSING');
      }
      
      // Check for missing critical fields
      const missingFields = [];
      if (!roster.customerName) missingFields.push('customerName');
      if (!roster.customerEmail) missingFields.push('customerEmail');
      if (!roster.vehicleId) missingFields.push('vehicleId');
      if (!roster.vehicleNumber) missingFields.push('vehicleNumber');
      if (!roster.driverId) missingFields.push('driverId');
      if (!roster.driverName) missingFields.push('driverName');
      if (!roster.driverPhone) missingFields.push('driverPhone');
      if (!roster.loginPickupLocation) missingFields.push('loginPickupLocation');
      if (!roster.logoutDropLocation) missingFields.push('logoutDropLocation');
      
      if (missingFields.length > 0) {
        console.log('\n⚠️  MISSING CRITICAL FIELDS:');
        missingFields.forEach(field => console.log(`   ❌ ${field}`));
      } else {
        console.log('\n✅ ALL CRITICAL FIELDS PRESENT');
      }
    });
    
    console.log('\n' + '='.repeat(80));
    console.log('📊 SUMMARY');
    console.log('='.repeat(80));
    
    // Count rosters with complete data
    let completeRosters = 0;
    let incompleteRosters = 0;
    
    assignedRosters.forEach(roster => {
      const hasAllFields = roster.customerName && roster.customerEmail && 
                          roster.vehicleId && roster.vehicleNumber &&
                          roster.driverId && roster.driverName && roster.driverPhone &&
                          roster.loginPickupLocation && roster.logoutDropLocation;
      
      if (hasAllFields) {
        completeRosters++;
      } else {
        incompleteRosters++;
      }
    });
    
    console.log(`\n✅ Complete Rosters: ${completeRosters}`);
    console.log(`⚠️  Incomplete Rosters: ${incompleteRosters}`);
    
    if (incompleteRosters > 0) {
      console.log('\n⚠️  ISSUE DETECTED: Some rosters are missing critical data!');
      console.log('💡 This means the assignment process is not saving all required fields.');
    } else {
      console.log('\n✅ All assigned rosters have complete data!');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await client.close();
  }
}

verifyRosterAssignmentData();
