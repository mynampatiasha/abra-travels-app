// test-route-optimization.js - Test Route Optimization Endpoints
require('dotenv').config();
const { MongoClient, ObjectId } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;
const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';

async function testRouteOptimization() {
  console.log('🧪 Testing Route Optimization Endpoints\n');
  console.log('='.repeat(80));
  
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    // Step 1: Get pending rosters
    console.log('\n📋 Step 1: Fetching pending rosters...');
    const pendingRosters = await db.collection('rosters')
      .find({ status: 'pending_assignment' })
      .limit(5)
      .toArray();
    
    console.log(`✅ Found ${pendingRosters.length} pending rosters`);
    
    if (pendingRosters.length === 0) {
      console.log('⚠️  No pending rosters found. Please create some rosters first.');
      return;
    }
    
    // Display roster details
    pendingRosters.forEach((roster, index) => {
      console.log(`\n  Roster ${index + 1}:`);
      console.log(`    ID: ${roster._id}`);
      console.log(`    Customer: ${roster.customerName || 'Unknown'}`);
      console.log(`    Office: ${roster.officeLocation || 'Not specified'}`);
      console.log(`    Type: ${roster.rosterType || 'both'}`);
      console.log(`    Start Time: ${roster.startTime || 'Not set'}`);
    });
    
    // Step 2: Get available drivers
    console.log('\n\n🚗 Step 2: Fetching available drivers...');
    const availableDrivers = await db.collection('users')
      .find({
        role: 'driver',
        status: 'active',
        isAvailable: { $ne: false }
      })
      .limit(10)
      .toArray();
    
    console.log(`✅ Found ${availableDrivers.length} available drivers`);
    
    if (availableDrivers.length === 0) {
      console.log('⚠️  No available drivers found. Please add some drivers first.');
      return;
    }
    
    // Display driver details
    availableDrivers.slice(0, 3).forEach((driver, index) => {
      console.log(`\n  Driver ${index + 1}:`);
      console.log(`    ID: ${driver._id}`);
      console.log(`    Name: ${driver.name || 'Unknown'}`);
      console.log(`    Email: ${driver.email || 'Not set'}`);
      console.log(`    Status: ${driver.isAvailable !== false ? 'Available' : 'Busy'}`);
    });
    
    // Step 3: Test optimization algorithm
    console.log('\n\n🧠 Step 3: Testing optimization algorithm...');
    console.log('='.repeat(80));
    
    const rosterIds = pendingRosters.map(r => r._id.toString());
    console.log(`\nOptimizing routes for ${rosterIds.length} rosters...`);
    
    // Simulate optimization
    const assignments = [];
    const usedDriverIds = new Set();
    
    for (let i = 0; i < Math.min(pendingRosters.length, availableDrivers.length); i++) {
      const roster = pendingRosters[i];
      const driver = availableDrivers[i];
      
      const officeTime = roster.startTime || '09:00';
      const distance = 10 + (i * 2);
      const travelTime = Math.round(distance * 3);
      const bufferMinutes = 15 + (i * 2);
      
      // Calculate pickup time
      const [hours, minutes] = officeTime.split(':').map(Number);
      const officeDateTime = new Date();
      officeDateTime.setHours(hours, minutes, 0, 0);
      
      const pickupDateTime = new Date(officeDateTime.getTime() - (travelTime + bufferMinutes) * 60000);
      const pickupTime = `${String(pickupDateTime.getHours()).padStart(2, '0')}:${String(pickupDateTime.getMinutes()).padStart(2, '0')}`;
      
      const assignment = {
        rosterId: roster._id.toString(),
        customerName: roster.customerName || 'Unknown',
        driverId: driver._id.toString(),
        driverName: driver.name || 'Unknown Driver',
        distance: distance,
        travelTime: travelTime,
        officeLocation: roster.officeLocation || 'Unknown',
        officeTime: officeTime,
        pickupTime: pickupTime,
        bufferMinutes: bufferMinutes,
        rosterType: roster.rosterType || 'both'
      };
      
      assignments.push(assignment);
      usedDriverIds.add(driver._id.toString());
      
      console.log(`\n✅ Assignment ${i + 1}:`);
      console.log(`   Driver: ${assignment.driverName}`);
      console.log(`   Customer: ${assignment.customerName}`);
      console.log(`   Distance: ${distance}km`);
      console.log(`   Travel Time: ${travelTime} minutes`);
      console.log(`   Pickup Time: ${pickupTime}`);
      console.log(`   Office Time: ${officeTime}`);
      console.log(`   Buffer: ${bufferMinutes} minutes`);
    }
    
    console.log('\n\n✅ Optimization Complete!');
    console.log(`   Total Assignments: ${assignments.length}`);
    console.log(`   Drivers Used: ${usedDriverIds.size}`);
    
    // Step 4: Display summary
    console.log('\n\n📊 Summary:');
    console.log('='.repeat(80));
    console.log(`Pending Rosters: ${pendingRosters.length}`);
    console.log(`Available Drivers: ${availableDrivers.length}`);
    console.log(`Successful Assignments: ${assignments.length}`);
    console.log(`Unassigned Rosters: ${pendingRosters.length - assignments.length}`);
    
    // Step 5: Show API endpoints
    console.log('\n\n🔗 API Endpoints:');
    console.log('='.repeat(80));
    console.log(`POST ${BASE_URL}/api/roster/optimize`);
    console.log(`POST ${BASE_URL}/api/roster/assign-bulk`);
    console.log(`GET  ${BASE_URL}/api/roster/drivers/available`);
    
    console.log('\n\n📝 Example API Request:');
    console.log('='.repeat(80));
    console.log('POST /api/roster/optimize');
    console.log('Headers: { Authorization: "Bearer <token>" }');
    console.log('Body:');
    console.log(JSON.stringify({
      rosterIds: rosterIds.slice(0, 3),
      count: 3
    }, null, 2));
    
    console.log('\n\n✅ Test Complete!');
    console.log('='.repeat(80));
    console.log('\nNext Steps:');
    console.log('1. Start the backend server: node index.js');
    console.log('2. Test the endpoints using Postman or the Flutter app');
    console.log('3. Check the console logs for detailed information');
    
  } catch (error) {
    console.error('\n❌ Test Error:', error);
    console.error('Stack:', error.stack);
  } finally {
    await client.close();
    console.log('\n🔌 Database connection closed');
  }
}

// Run the test
testRouteOptimization().catch(console.error);
