// test-vehicle-compatibility-check.js - Test Enhanced Vehicle Compatibility (Org + Shift + Timing)
require('dotenv').config();
const { MongoClient, ObjectId } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function testVehicleCompatibility() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db();
    
    console.log('='*80);
    console.log('🏢 TESTING ENHANCED VEHICLE COMPATIBILITY CHECK');
    console.log('   (Organization + Shift + Timing)');
    console.log('='*80 + '\n');
    
    // Test Case 1: Check existing vehicle assignments with full details
    console.log('📋 TEST CASE 1: Existing Vehicle Assignments with Compatibility Criteria\n');
    
    const vehicles = await db.collection('vehicles').find({}).limit(10).toArray();
    console.log(`Found ${vehicles.length} vehicles\n`);
    
    for (const vehicle of vehicles) {
      console.log(`🚗 Vehicle: ${vehicle.name || vehicle.vehicleNumber}`);
      console.log(`   ID: ${vehicle._id}`);
      console.log(`   Capacity: ${vehicle.seatCapacity || 'Unknown'}`);
      
      // Check for assigned rosters
      const assignedRosters = await db.collection('rosters').find({
        vehicleId: vehicle._id.toString(),
        status: 'assigned'
      }).toArray();
      
      if (assignedRosters.length > 0) {
        console.log(`   👥 Assigned Customers: ${assignedRosters.length}`);
        console.log(`   📊 Capacity Status: ${assignedRosters.length + 1}/${vehicle.seatCapacity || 20} (including driver)`);
        
        // Extract compatibility criteria
        const organizations = new Set();
        const shifts = new Set();
        const loginTimes = new Set();
        const logoutTimes = new Set();
        const rosterTypes = new Set();
        
        console.log(`\n   📋 Customer Details:`);
        assignedRosters.forEach((roster, idx) => {
          const org = roster.organization || roster.organizationName || 'Unknown';
          const shift = roster.shift || roster.shiftType || 'Unknown';
          const loginTime = roster.startTime || roster.officeTime || 'Unknown';
          const logoutTime = roster.endTime || roster.officeEndTime || 'Unknown';
          const rosterType = roster.rosterType || 'both';
          
          organizations.add(org);
          shifts.add(shift);
          loginTimes.add(loginTime);
          logoutTimes.add(logoutTime);
          rosterTypes.add(rosterType);
          
          console.log(`      ${idx + 1}. ${roster.customerName || 'Unknown'}`);
          console.log(`         🏢 Organization: ${org}`);
          console.log(`         🌅 Shift: ${shift}`);
          console.log(`         🕐 Login: ${loginTime}`);
          console.log(`         🕔 Logout: ${logoutTime}`);
          console.log(`         📍 Type: ${rosterType}`);
        });
        
        console.log(`\n   📊 Compatibility Criteria:`);
        console.log(`      🏢 Organizations: ${Array.from(organizations).join(', ')}`);
        console.log(`      🌅 Shifts: ${Array.from(shifts).join(', ')}`);
        console.log(`      🕐 Login Times: ${Array.from(loginTimes).join(', ')}`);
        console.log(`      🕔 Logout Times: ${Array.from(logoutTimes).join(', ')}`);
        console.log(`      📍 Roster Types: ${Array.from(rosterTypes).join(', ')}`);
        
        // Check for compatibility violations
        if (organizations.size > 1) {
          console.log(`\n   ⚠️  WARNING: Multiple organizations detected!`);
          console.log(`   🚫 VIOLATION: ${Array.from(organizations).join(' + ')}`);
        }
        
        if (shifts.size > 1) {
          console.log(`\n   ⚠️  WARNING: Multiple shifts detected!`);
          console.log(`   🚫 VIOLATION: ${Array.from(shifts).join(' + ')}`);
        }
        
        if (loginTimes.size > 1) {
          console.log(`\n   ⚠️  WARNING: Multiple login times detected!`);
          console.log(`   🚫 VIOLATION: ${Array.from(loginTimes).join(' + ')}`);
        }
        
        if (logoutTimes.size > 1) {
          console.log(`\n   ⚠️  WARNING: Multiple logout times detected!`);
          console.log(`   🚫 VIOLATION: ${Array.from(logoutTimes).join(' + ')}`);
        }
        
        if (organizations.size === 1 && shifts.size === 1 && loginTimes.size === 1 && logoutTimes.size === 1) {
          console.log(`\n   ✅ COMPATIBLE: All customers match criteria`);
        }
        
        // Show available capacity
        const availableSeats = (vehicle.seatCapacity || 20) - assignedRosters.length - 1;
        console.log(`\n   🪑 Available Seats: ${availableSeats}`);
        if (availableSeats > 0) {
          console.log(`   📌 Can accept ${availableSeats} more customers with:`);
          console.log(`      🏢 Organization: ${Array.from(organizations)[0]}`);
          console.log(`      🌅 Shift: ${Array.from(shifts)[0]}`);
          console.log(`      🕐 Login: ${Array.from(loginTimes)[0]}`);
          console.log(`      🕔 Logout: ${Array.from(logoutTimes)[0]}`);
        } else {
          console.log(`   🚫 Vehicle is FULL`);
        }
        
      } else {
        console.log(`   ⚪ No assigned customers`);
        console.log(`   📌 Available for any organization/shift/timing`);
      }
      
      console.log('');
    }
    
    // Test Case 2: Analyze pending rosters by compatibility groups
    console.log('\n' + '='*80);
    console.log('📋 TEST CASE 2: Pending Rosters Compatibility Analysis\n');
    
    const pendingRosters = await db.collection('rosters').find({
      status: 'pending_assignment'
    }).limit(30).toArray();
    
    console.log(`Found ${pendingRosters.length} pending rosters\n`);
    
    // Group by compatibility criteria
    const compatibilityGroups = {};
    
    pendingRosters.forEach(roster => {
      const org = roster.organization || roster.organizationName || 'Unknown';
      const shift = roster.shift || roster.shiftType || 'Unknown';
      const loginTime = roster.startTime || roster.officeTime || 'Unknown';
      const logoutTime = roster.endTime || roster.officeEndTime || 'Unknown';
      
      const key = `${org}|${shift}|${loginTime}|${logoutTime}`;
      
      if (!compatibilityGroups[key]) {
        compatibilityGroups[key] = {
          organization: org,
          shift: shift,
          loginTime: loginTime,
          logoutTime: logoutTime,
          customers: []
        };
      }
      
      compatibilityGroups[key].customers.push(roster);
    });
    
    console.log(`📊 Found ${Object.keys(compatibilityGroups).length} compatibility groups:\n`);
    
    Object.entries(compatibilityGroups).forEach(([key, group], idx) => {
      console.log(`${idx + 1}. Compatibility Group (${group.customers.length} customers):`);
      console.log(`   🏢 Organization: ${group.organization}`);
      console.log(`   🌅 Shift: ${group.shift}`);
      console.log(`   🕐 Login Time: ${group.loginTime}`);
      console.log(`   🕔 Logout Time: ${group.logoutTime}`);
      console.log(`   👥 Customers:`);
      
      group.customers.slice(0, 5).forEach((customer, i) => {
        console.log(`      ${i + 1}. ${customer.customerName || customer.employeeDetails?.name || 'Unknown'}`);
      });
      
      if (group.customers.length > 5) {
        console.log(`      ... and ${group.customers.length - 5} more`);
      }
      
      // Calculate vehicles needed
      const vehiclesNeeded = Math.ceil(group.customers.length / 4); // Assuming 4 seats per vehicle
      console.log(`   🚗 Vehicles Needed: ${vehiclesNeeded} (assuming 4 customers per vehicle)`);
      console.log('');
    });
    
    // Test Case 3: Compatibility Conflict Scenarios
    console.log('\n' + '='*80);
    console.log('📋 TEST CASE 3: Compatibility Conflict Scenarios\n');
    
    const vehicleWithAssignments = await db.collection('vehicles').findOne({});
    
    if (vehicleWithAssignments) {
      const existingRosters = await db.collection('rosters').find({
        vehicleId: vehicleWithAssignments._id.toString(),
        status: 'assigned'
      }).toArray();
      
      if (existingRosters.length > 0) {
        const existingOrg = existingRosters[0].organization || existingRosters[0].organizationName || 'TechCorp';
        const existingShift = existingRosters[0].shift || existingRosters[0].shiftType || 'Morning';
        const existingLogin = existingRosters[0].startTime || existingRosters[0].officeTime || '09:00';
        const existingLogout = existingRosters[0].endTime || existingRosters[0].officeEndTime || '18:00';
        
        console.log(`🚗 Testing with vehicle: ${vehicleWithAssignments.name || vehicleWithAssignments.vehicleNumber}`);
        console.log(`   Current Criteria:`);
        console.log(`   🏢 Organization: ${existingOrg}`);
        console.log(`   🌅 Shift: ${existingShift}`);
        console.log(`   🕐 Login: ${existingLogin}`);
        console.log(`   🕔 Logout: ${existingLogout}`);
        console.log(`   👥 Existing Customers: ${existingRosters.length}\n`);
        
        // Scenario A: Perfect Match (should pass)
        console.log('✅ Scenario A: PERFECT MATCH (All criteria match)');
        console.log(`   New customer:`);
        console.log(`   🏢 Organization: ${existingOrg}`);
        console.log(`   🌅 Shift: ${existingShift}`);
        console.log(`   🕐 Login: ${existingLogin}`);
        console.log(`   🕔 Logout: ${existingLogout}`);
        console.log(`   Expected: ✅ PASS - All criteria match\n`);
        
        // Scenario B: Organization Mismatch (should fail)
        const differentOrg = existingOrg === 'TechCorp' ? 'FinanceInc' : 'TechCorp';
        console.log('❌ Scenario B: ORGANIZATION MISMATCH');
        console.log(`   New customer:`);
        console.log(`   🏢 Organization: ${differentOrg} ❌`);
        console.log(`   🌅 Shift: ${existingShift}`);
        console.log(`   🕐 Login: ${existingLogin}`);
        console.log(`   🕔 Logout: ${existingLogout}`);
        console.log(`   Expected: ❌ FAIL - Organization conflict\n`);
        
        // Scenario C: Shift Mismatch (should fail)
        const differentShift = existingShift === 'Morning' ? 'Evening' : 'Morning';
        console.log('❌ Scenario C: SHIFT MISMATCH');
        console.log(`   New customer:`);
        console.log(`   🏢 Organization: ${existingOrg}`);
        console.log(`   🌅 Shift: ${differentShift} ❌`);
        console.log(`   🕐 Login: ${existingLogin}`);
        console.log(`   🕔 Logout: ${existingLogout}`);
        console.log(`   Expected: ❌ FAIL - Shift conflict\n`);
        
        // Scenario D: Login Time Mismatch (should fail)
        console.log('❌ Scenario D: LOGIN TIME MISMATCH');
        console.log(`   New customer:`);
        console.log(`   🏢 Organization: ${existingOrg}`);
        console.log(`   🌅 Shift: ${existingShift}`);
        console.log(`   🕐 Login: 10:00 ❌ (vs ${existingLogin})`);
        console.log(`   🕔 Logout: ${existingLogout}`);
        console.log(`   Expected: ❌ FAIL - Login time conflict\n`);
        
        // Scenario E: Logout Time Mismatch (should fail)
        console.log('❌ Scenario E: LOGOUT TIME MISMATCH');
        console.log(`   New customer:`);
        console.log(`   🏢 Organization: ${existingOrg}`);
        console.log(`   🌅 Shift: ${existingShift}`);
        console.log(`   🕐 Login: ${existingLogin}`);
        console.log(`   🕔 Logout: 19:00 ❌ (vs ${existingLogout})`);
        console.log(`   Expected: ❌ FAIL - Logout time conflict\n`);
      }
    }
    
    // Test Case 4: Recommendations
    console.log('\n' + '='*80);
    console.log('💡 RECOMMENDATIONS\n');
    
    const groupCount = Object.keys(compatibilityGroups).length;
    const totalPending = pendingRosters.length;
    
    if (groupCount > 1) {
      console.log(`⚠️  Multiple compatibility groups detected (${groupCount} groups)`);
      console.log(`   📌 Recommendation: Assign vehicles per compatibility group`);
      console.log(`   📌 Each group needs separate vehicle(s)\n`);
      
      Object.entries(compatibilityGroups).forEach(([key, group], idx) => {
        const vehiclesNeeded = Math.ceil(group.customers.length / 4);
        console.log(`   ${idx + 1}. ${group.organization} - ${group.shift} - ${group.loginTime}-${group.logoutTime}`);
        console.log(`      👥 ${group.customers.length} customers → 🚗 ${vehiclesNeeded} vehicle(s) needed`);
      });
    } else {
      console.log(`✅ Single compatibility group`);
      console.log(`   📌 Can use shared vehicles for all ${totalPending} customers`);
      console.log(`   📌 Estimated vehicles needed: ${Math.ceil(totalPending / 4)}`);
    }
    
    console.log('\n' + '='*80);
    console.log('✅ ENHANCED COMPATIBILITY TEST COMPLETE');
    console.log('='*80);
    
  } catch (error) {
    console.error('❌ Test failed:', error);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n✅ Database connection closed');
  }
}

// Run the test
testVehicleCompatibility();
