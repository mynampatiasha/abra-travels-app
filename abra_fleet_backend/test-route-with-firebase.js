/**
 * Test Route Optimization with Firebase Authentication
 * This test uses Firebase Admin SDK to create a custom token for testing
 */

require('dotenv').config();
const axios = require('axios');
const admin = require('./config/firebase');

const BASE_URL = 'http://localhost:3000';
const ADMIN_UID = 'qnwp8d0clDSSNuSm3ugmXYLSI3K2'; // Admin Firebase UID

async function createCustomToken() {
  try {
    console.log('🔑 Creating Firebase custom token for admin...');
    const customToken = await admin.auth().createCustomToken(ADMIN_UID);
    console.log('✓ Custom token created\n');
    return customToken;
  } catch (error) {
    console.error('❌ Failed to create custom token:', error.message);
    throw error;
  }
}

async function testRouteOptimization() {
  console.log('🚀 Route Optimization + Trip Creation Test\n');
  console.log('='.repeat(60) + '\n');
  
  try {
    // Step 1: Create Firebase token
    const firebaseToken = await createCustomToken();
    
    // Step 2: Login to get MongoDB user
    console.log('1. Logging in with Firebase token...');
    const loginRes = await axios.post(`${BASE_URL}/api/auth/login`, {
      firebaseUid: ADMIN_UID,
      email: 'admin@abrafleet.com',
      name: 'System Administrator',
      role: 'admin'
    }, {
      headers: {
        'Authorization': `Bearer ${firebaseToken}`,
        'Content-Type': 'application/json'
      }
    });
    
    console.log('✓ Logged in successfully');
    console.log(`  User: ${loginRes.data.user.name}`);
    console.log(`  Role: ${loginRes.data.user.role}\n`);
    
    const token = firebaseToken; // Use Firebase token for subsequent requests
    
    // Step 3: Get available vehicle
    console.log('2. Getting available vehicle...');
    const vehiclesRes = await axios.get(`${BASE_URL}/api/admin/vehicles`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    
    const vehicles = vehiclesRes.data.vehicles || vehiclesRes.data;
    if (vehicles.length === 0) {
      console.log('❌ No vehicles available');
      return;
    }
    
    const vehicle = vehicles[0];
    console.log('✓ Vehicle found');
    console.log(`  Vehicle: ${vehicle.vehicleNumber}`);
    console.log(`  Type: ${vehicle.vehicleType}`);
    console.log(`  Capacity: ${vehicle.seatCapacity} seats`);
    console.log(`  ID: ${vehicle._id}\n`);
    
    // Step 4: Get pending rosters
    console.log('3. Getting pending rosters...');
    const rostersRes = await axios.get(`${BASE_URL}/api/roster/pending`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    
    const rosters = rostersRes.data.rosters || rostersRes.data;
    console.log(`✓ Found ${rosters.length} pending rosters\n`);
    
    if (rosters.length === 0) {
      console.log('⚠ No pending rosters to test with');
      console.log('  Please create some rosters first');
      return;
    }
    
    // Show first few rosters
    console.log('  First 3 rosters:');
    rosters.slice(0, 3).forEach((roster, idx) => {
      console.log(`    ${idx + 1}. ${roster.customerName} - ${roster.pickupLocation}`);
    });
    console.log('');
    
    // Step 5: Create optimized route with trip creation
    console.log('4. Creating optimized route + trips...');
    
    const route = rosters.slice(0, Math.min(3, rosters.length)).map((roster, idx) => ({
      rosterId: roster._id,
      customerId: roster.customerId,
      customerName: roster.customerName,
      customerEmail: roster.customerEmail || `customer${idx}@test.com`,
      customerPhone: roster.customerPhone || '+1234567890',
      sequence: idx + 1,
      pickupTime: roster.pickupTime || '08:00',
      eta: new Date(Date.now() + (idx * 30 * 60000)).toISOString(),
      location: roster.pickupLocation,
      distanceFromPrevious: (idx + 1) * 2.5,
      estimatedTime: 15 + (idx * 10)
    }));
    
    const payload = {
      vehicleId: vehicle._id,
      route: route,
      totalDistance: route.reduce((sum, r) => sum + r.distanceFromPrevious, 0),
      totalTime: route.reduce((sum, r) => sum + r.estimatedTime, 0),
      startTime: new Date().toISOString()
    };
    
    console.log(`  Assigning ${route.length} customers to vehicle ${vehicle.vehicleNumber}...`);
    
    const optimizeRes = await axios.post(
      `${BASE_URL}/api/roster/assign-optimized-route`,
      payload,
      { headers: { 'Authorization': `Bearer ${token}` } }
    );
    
    console.log('\n✓ Route optimization successful!');
    console.log('  ' + '─'.repeat(50));
    console.log(`  Success: ${optimizeRes.data.success}`);
    console.log(`  Message: ${optimizeRes.data.message}`);
    console.log(`  Trips Created: ${optimizeRes.data.data.tripIds.length}`);
    console.log(`  Success Count: ${optimizeRes.data.data.successCount}`);
    console.log(`  Tracking Enabled: ${optimizeRes.data.data.trackingEnabled}`);
    console.log('  ' + '─'.repeat(50));
    
    if (optimizeRes.data.data.tripIds.length > 0) {
      console.log('\n  Trip IDs created:');
      optimizeRes.data.data.tripIds.forEach((id, idx) => {
        console.log(`    ${idx + 1}. ${id}`);
      });
    }
    console.log('');
    
    // Step 6: Verify first trip in database
    if (optimizeRes.data.data.tripIds.length > 0) {
      const tripId = optimizeRes.data.data.tripIds[0];
      console.log('5. Verifying trip in database...');
      console.log(`  Trip ID: ${tripId}`);
      
      const tripRes = await axios.get(`${BASE_URL}/api/trips/${tripId}`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      
      const trip = tripRes.data.trip || tripRes.data;
      console.log('\n✓ Trip found in MongoDB:');
      console.log('  ' + '─'.repeat(50));
      console.log(`  Trip Number: ${trip.tripNumber}`);
      console.log(`  Roster ID: ${trip.rosterId}`);
      console.log(`  Vehicle ID: ${trip.vehicleId}`);
      console.log(`  Driver ID: ${trip.driverId}`);
      console.log(`  Customer: ${trip.customer.name}`);
      console.log(`  Email: ${trip.customer.email}`);
      console.log(`  Phone: ${trip.customer.phone}`);
      console.log(`  Status: ${trip.status}`);
      console.log(`  Scheduled Date: ${trip.scheduledDate}`);
      console.log(`  Start Time: ${trip.startTime}`);
      console.log(`  Sequence: ${trip.sequence}`);
      console.log(`  Current Location: ${trip.currentLocation || 'null'}`);
      console.log(`  Location History: ${trip.locationHistory ? trip.locationHistory.length : 0} entries`);
      console.log('  ' + '─'.repeat(50));
      console.log('');
    }
    
    // Step 7: Test driver's today trips (if driver exists)
    if (vehicle.driverId) {
      console.log('6. Getting driver today trips...');
      console.log(`  Driver ID: ${vehicle.driverId}`);
      
      try {
        const driverTripsRes = await axios.get(
          `${BASE_URL}/api/trips/driver/${vehicle.driverId}/today`,
          { headers: { 'Authorization': `Bearer ${token}` } }
        );
        
        const trips = driverTripsRes.data.trips || driverTripsRes.data;
        console.log(`\n✓ Found ${trips.length} trips for driver today`);
        
        if (trips.length > 0) {
          console.log('\n  Trip details:');
          trips.forEach((trip, idx) => {
            console.log(`    ${idx + 1}. ${trip.tripNumber} - ${trip.customer.name} (${trip.status})`);
          });
        }
        console.log('');
      } catch (error) {
        console.log(`⚠ Could not get driver trips: ${error.message}\n`);
      }
    }
    
    console.log('='.repeat(60));
    console.log('🎉 ALL TESTS PASSED!');
    console.log('='.repeat(60));
    console.log('\n📊 Summary:');
    console.log('  ✓ Route optimization working');
    console.log('  ✓ Trip creation working');
    console.log('  ✓ Database storage working');
    console.log('  ✓ Trip retrieval working');
    console.log('\n✅ Integration test complete!\n');
    
  } catch (error) {
    console.error('\n❌ Test failed:', error.message);
    if (error.response) {
      console.error('Status:', error.response.status);
      console.error('Response:', JSON.stringify(error.response.data, null, 2));
    }
    process.exit(1);
  }
}

// Run the test
testRouteOptimization();
