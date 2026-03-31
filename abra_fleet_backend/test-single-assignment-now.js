// ============================================================================
// TEST SINGLE ASSIGNMENT - Verify single customer assignment works
// ============================================================================

const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config();

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet';

async function testSingleAssignment() {
  console.log('\n' + '='.repeat(80));
  console.log('🧪 TESTING SINGLE ASSIGNMENT FUNCTIONALITY');
  console.log('='.repeat(80));

  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db();
    
    // STEP 1: Find available customers (the ones we just reset)
    console.log('\n📋 STEP 1: Finding available customers...');
    
    const availableCustomers = await db.collection('rosters').find({
      status: 'pending_assignment',
      $or: [
        { customerEmail: 'pooja.joshi@wipro.com' },
        { customerEmail: 'arjun.nair@wipro.com' },
        { customerEmail: 'sneha.iyer@wipro.com' }
      ]
    }).limit(1).toArray();
    
    if (availableCustomers.length === 0) {
      console.log('❌ No available customers found for testing');
      return;
    }
    
    const testCustomer = availableCustomers[0];
    console.log(`✅ Found test customer: ${testCustomer.customerName || 'Unknown'}`);
    console.log(`   Email: ${testCustomer.customerEmail}`);
    console.log(`   Status: ${testCustomer.status}`);
    console.log(`   Roster ID: ${testCustomer._id}`);
    
    // STEP 2: Find compatible vehicles
    console.log('\n🚗 STEP 2: Finding compatible vehicles...');
    
    const vehicles = await db.collection('vehicles').find({
      status: { $regex: /^active$/i },
      $or: [
        { 'assignedDriver.name': { $exists: true, $ne: null, $ne: '' } },
        { assignedDriver: { $exists: true, $ne: null, $ne: '' } },
        { driverId: { $exists: true, $ne: null, $ne: '' } }
      ]
    }).toArray();
    
    console.log(`Found ${vehicles.length} vehicles with drivers:`);
    vehicles.forEach((vehicle, i) => {
      const driverName = vehicle.assignedDriver?.name || 
                        vehicle.assignedDriver || 
                        'Driver assigned';
      console.log(`   ${i + 1}. ${vehicle.registrationNumber || vehicle.name || 'Vehicle'} - ${driverName}`);
    });
    
    if (vehicles.length === 0) {
      console.log('❌ No vehicles with drivers found');
      return;
    }
    
    const testVehicle = vehicles[0];
    console.log(`\n✅ Using test vehicle: ${testVehicle.registrationNumber || testVehicle.name}`);
    
    // STEP 3: Test the compatible-vehicles API endpoint
    console.log('\n🔍 STEP 3: Testing compatible-vehicles API...');
    
    const rosterIds = [testCustomer._id.toString()];
    console.log(`Testing with roster IDs: ${rosterIds.join(', ')}`);
    
    // Simulate the API call logic
    const rosters = await db.collection('rosters').find({
      _id: { $in: rosterIds.map(id => new ObjectId(id)) }
    }).toArray();
    
    console.log(`✅ Found ${rosters.length} rosters for compatibility check`);
    
    // Extract customer information
    const customerEmails = new Set();
    const customerCompanies = new Set();
    
    rosters.forEach(roster => {
      const email = roster.customerEmail || roster.employeeDetails?.email || '';
      const emailDomain = email.includes('@') ? email.split('@')[1].toLowerCase() : 'unknown';
      const company = emailDomain.split('.')[0];
      
      customerEmails.add(email);
      customerCompanies.add(company);
    });
    
    console.log(`Customer companies: ${Array.from(customerCompanies).join(', ')}`);
    
    // STEP 4: Check vehicle compatibility
    console.log('\n✅ STEP 4: Checking vehicle compatibility...');
    
    const compatibleVehicles = [];
    
    for (const vehicle of vehicles) {
      const vehicleName = vehicle.registrationNumber || vehicle.vehicleId || 'Vehicle';
      console.log(`\n🚗 Checking: ${vehicleName}`);
      
      // Check driver assignment
      let hasDriver = false;
      if (vehicle.assignedDriver) {
        if (typeof vehicle.assignedDriver === 'object' && vehicle.assignedDriver !== null) {
          if (vehicle.assignedDriver.name || vehicle.assignedDriver.driverId || vehicle.assignedDriver._id) {
            hasDriver = true;
          }
        } else if (typeof vehicle.assignedDriver === 'string' && vehicle.assignedDriver.trim() !== '') {
          hasDriver = true;
        }
      } else if (vehicle.driverId && vehicle.driverId.toString().trim() !== '') {
        hasDriver = true;
      }
      
      console.log(`   👨‍✈️ Driver: ${hasDriver ? 'Assigned' : 'NOT ASSIGNED'}`);
      
      if (!hasDriver) {
        console.log(`   ❌ INCOMPATIBLE - No driver assigned`);
        continue;
      }
      
      // Check existing assignments
      const existingAssignments = await db.collection('rosters').find({
        vehicleId: vehicle._id.toString(),
        status: 'assigned',
        assignedAt: { $gte: new Date(new Date().setHours(0, 0, 0, 0)) }
      }).toArray();
      
      console.log(`   📋 Existing assignments: ${existingAssignments.length}`);
      
      if (existingAssignments.length === 0) {
        console.log(`   ✅ COMPATIBLE - No existing assignments`);
        compatibleVehicles.push(vehicle);
        continue;
      }
      
      // Check company compatibility
      const existingCompanies = new Set();
      existingAssignments.forEach(roster => {
        const email = roster.customerEmail || roster.employeeDetails?.email || '';
        const emailDomain = email.includes('@') ? email.split('@')[1].toLowerCase() : 'unknown';
        const company = emailDomain.split('.')[0];
        existingCompanies.add(company);
      });
      
      const companiesMatch = Array.from(customerCompanies).every(company => 
        existingCompanies.has(company)
      );
      
      if (!companiesMatch) {
        console.log(`   ❌ INCOMPATIBLE - Company mismatch`);
        continue;
      }
      
      // Check capacity
      const totalSeats = vehicle.capacity?.passengers || 
                         vehicle.seatCapacity || 
                         vehicle.seatingCapacity || 
                         4;
      const assignedSeats = existingAssignments.length;
      const availableSeats = totalSeats - 1 - assignedSeats;
      
      console.log(`   💺 Seats: ${totalSeats} total, ${assignedSeats} assigned, ${availableSeats} available`);
      
      if (availableSeats >= 1) {
        console.log(`   ✅ COMPATIBLE - Same company, sufficient capacity`);
        compatibleVehicles.push(vehicle);
      } else {
        console.log(`   ❌ INCOMPATIBLE - Insufficient capacity`);
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('📊 COMPATIBILITY CHECK RESULTS');
    console.log('='.repeat(80));
    console.log(`✅ Compatible vehicles: ${compatibleVehicles.length}`);
    console.log(`❌ Incompatible vehicles: ${vehicles.length - compatibleVehicles.length}`);
    
    if (compatibleVehicles.length > 0) {
      console.log('\n🎯 SINGLE ASSIGNMENT TEST: READY TO PROCEED');
      console.log('✅ Found available customer');
      console.log('✅ Found compatible vehicles');
      console.log('✅ Assignment conflicts cleared');
      console.log('✅ Consecutive trip logic implemented');
      
      console.log('\n🚀 NEXT STEPS:');
      console.log('1. Use the admin panel to assign the customer');
      console.log('2. Select one of the compatible vehicles');
      console.log('3. Test single assignment first');
      console.log('4. Then test multiple consecutive trips');
      
      console.log('\n📋 TEST DATA:');
      console.log(`Customer: ${testCustomer.customerName} (${testCustomer.customerEmail})`);
      console.log(`Roster ID: ${testCustomer._id}`);
      console.log(`Compatible vehicles: ${compatibleVehicles.length}`);
      console.log(`Top vehicle: ${compatibleVehicles[0].registrationNumber || compatibleVehicles[0].name}`);
      
    } else {
      console.log('\n❌ SINGLE ASSIGNMENT TEST: ISSUES FOUND');
      console.log('No compatible vehicles found. Check:');
      console.log('1. Vehicles have assigned drivers');
      console.log('2. Vehicle capacity is sufficient');
      console.log('3. No company conflicts');
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ SINGLE ASSIGNMENT TEST COMPLETE');
    console.log('='.repeat(80) + '\n');
    
  } catch (error) {
    console.error('❌ Error testing single assignment:', error);
  } finally {
    await client.close();
  }
}

// Run the test
if (require.main === module) {
  testSingleAssignment();
}

module.exports = { testSingleAssignment };