// test-organization-vehicle-check.js - Test Organization Segregation in Vehicle Assignment
require('dotenv').config();
const { MongoClient, ObjectId } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function testOrganizationVehicleCheck() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    console.log('✅ Connected to MongoDB\n');
    
    const db = client.db();
    
    console.log('='*80);
    console.log('🏢 TESTING ORGANIZATION SEGREGATION IN VEHICLE ASSIGNMENT');
    console.log('='*80 + '\n');
    
    // Test Case 1: Check existing vehicle assignments
    console.log('📋 TEST CASE 1: Checking Existing Vehicle Assignments\n');
    
    const vehicles = await db.collection('vehicles').find({}).toArray();
    console.log(`Found ${vehicles.length} vehicles\n`);
    
    for (const vehicle of vehicles.slice(0, 5)) { // Check first 5 vehicles
      console.log(`🚗 Vehicle: ${vehicle.name || vehicle.vehicleNumber}`);
      console.log(`   ID: ${vehicle._id}`);
      
      // Check for assigned rosters
      const assignedRosters = await db.collection('rosters').find({
        vehicleId: vehicle._id.toString(),
        status: 'assigned'
      }).toArray();
      
      if (assignedRosters.length > 0) {
        console.log(`   👥 Assigned Customers: ${assignedRosters.length}`);
        
        // Extract organizations
        const organizations = new Set();
        assignedRosters.forEach(roster => {
          const org = roster.organization || 
                     roster.organizationName || 
                     roster.companyName || 
                     roster.company ||
                     roster.employeeDetails?.organization ||
                     'Unknown';
          organizations.add(org);
        });
        
        console.log(`   🏢 Organizations: ${Array.from(organizations).join(', ')}`);
        
        if (organizations.size > 1) {
          console.log(`   ⚠️  WARNING: Multiple organizations detected!`);
          console.log(`   🚫 VIOLATION: ${Array.from(organizations).join(' + ')}`);
        } else {
          console.log(`   ✅ Single organization: ${Array.from(organizations)[0]}`);
        }
        
        // Show customer details
        console.log(`   📊 Customer Details:`);
        assignedRosters.forEach((roster, idx) => {
          const org = roster.organization || roster.organizationName || 'Unknown';
          console.log(`      ${idx + 1}. ${roster.customerName} (${org})`);
        });
      } else {
        console.log(`   ⚪ No assigned customers`);
      }
      
      console.log('');
    }
    
    // Test Case 2: Simulate organization conflict detection
    console.log('\n' + '='*80);
    console.log('📋 TEST CASE 2: Simulating Organization Conflict Detection\n');
    
    // Find a vehicle with existing assignments
    const vehicleWithAssignments = await db.collection('vehicles').findOne({});
    
    if (vehicleWithAssignments) {
      const existingRosters = await db.collection('rosters').find({
        vehicleId: vehicleWithAssignments._id.toString(),
        status: 'assigned'
      }).toArray();
      
      if (existingRosters.length > 0) {
        const existingOrg = existingRosters[0].organization || 
                           existingRosters[0].organizationName || 
                           'TechCorp';
        
        console.log(`🚗 Testing with vehicle: ${vehicleWithAssignments.name || vehicleWithAssignments.vehicleNumber}`);
        console.log(`   Current organization: ${existingOrg}`);
        console.log(`   Existing customers: ${existingRosters.length}\n`);
        
        // Scenario A: Same organization (should pass)
        console.log('✅ Scenario A: Adding customer from SAME organization');
        console.log(`   New customer organization: ${existingOrg}`);
        console.log(`   Expected: ✅ PASS - Same organization allowed\n`);
        
        // Scenario B: Different organization (should fail)
        const differentOrg = existingOrg === 'TechCorp' ? 'FinanceInc' : 'TechCorp';
        console.log('❌ Scenario B: Adding customer from DIFFERENT organization');
        console.log(`   Existing: ${existingOrg}`);
        console.log(`   New: ${differentOrg}`);
        console.log(`   Expected: ❌ FAIL - Organization conflict detected\n`);
      }
    }
    
    // Test Case 3: Check pending rosters by organization
    console.log('\n' + '='*80);
    console.log('📋 TEST CASE 3: Analyzing Pending Rosters by Organization\n');
    
    const pendingRosters = await db.collection('rosters').find({
      status: 'pending_assignment'
    }).limit(20).toArray();
    
    console.log(`Found ${pendingRosters.length} pending rosters\n`);
    
    // Group by organization
    const orgGroups = {};
    pendingRosters.forEach(roster => {
      const org = roster.organization || 
                 roster.organizationName || 
                 roster.companyName || 
                 roster.company ||
                 roster.employeeDetails?.organization ||
                 'Unknown Organization';
      
      if (!orgGroups[org]) {
        orgGroups[org] = [];
      }
      orgGroups[org].push(roster);
    });
    
    console.log(`📊 Organization Distribution:`);
    Object.entries(orgGroups).forEach(([org, rosters]) => {
      console.log(`   🏢 ${org}: ${rosters.length} customers`);
      rosters.slice(0, 3).forEach(r => {
        console.log(`      - ${r.customerName || r.employeeDetails?.name || 'Unknown'}`);
      });
      if (rosters.length > 3) {
        console.log(`      ... and ${rosters.length - 3} more`);
      }
    });
    
    // Test Case 4: Recommendations
    console.log('\n' + '='*80);
    console.log('💡 RECOMMENDATIONS\n');
    
    const orgCount = Object.keys(orgGroups).length;
    const totalPending = pendingRosters.length;
    
    if (orgCount > 1) {
      console.log(`⚠️  Multiple organizations detected (${orgCount} organizations)`);
      console.log(`   📌 Recommendation: Assign vehicles per organization`);
      console.log(`   📌 Each organization should get separate vehicle(s)\n`);
      
      Object.entries(orgGroups).forEach(([org, rosters]) => {
        const vehiclesNeeded = Math.ceil(rosters.length / 4); // Assuming 4 seats per vehicle
        console.log(`   🚗 ${org}: Needs ${vehiclesNeeded} vehicle(s) for ${rosters.length} customers`);
      });
    } else {
      console.log(`✅ Single organization: ${Object.keys(orgGroups)[0]}`);
      console.log(`   📌 Can use shared vehicles for all ${totalPending} customers`);
    }
    
    console.log('\n' + '='*80);
    console.log('✅ ORGANIZATION SEGREGATION TEST COMPLETE');
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
testOrganizationVehicleCheck();
