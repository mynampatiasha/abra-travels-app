const axios = require('axios');

const BASE_URL = 'http://localhost:3000';

async function quickTest() {
  console.log('🚀 Quick Route Optimization Test\n');
  
  try {
    // 1. Login as admin
    console.log('1. Logging in as admin...');
    console.log('   Email: admin@abrafleet.com');
    console.log('   Password: Admin@123');
    
    const loginRes = await axios.post(`${BASE_URL}/api/auth/login`, {
      email: 'admin@abrafleet.com',
      password: 'Admin@123'
    }, {
      headers: {
        'Content-Type': 'application/json'
      }
    });
    
    console.log('   Response status:', loginRes.status);
    console.log('   Response data:', JSON.stringify(loginRes.data, null, 2));
    
    const token = loginRes.data.token || loginRes.data.data?.token;
    if (!token) {
      throw new Error('No token received from login');
    }
    console.log('✓ Logged in successfully');
    console.log(`  Token: ${token.substring(0, 30)}...\n`);
    
    // 2. Get a vehicle
    console.log('2. Getting available vehicle...');
    const vehiclesRes = await axios.get(`${BASE_URL}/api/admin/vehicles`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    const vehicles = vehiclesRes.data.vehicles || vehiclesRes.data;
    const vehicle = vehicles[0];
    console.log(`✓ Vehicle: ${vehicle.vehicleNumber} (ID: ${vehicle._id})\n`);
    
    // 3. Get pending rosters
    console.log('3. Getting pending rosters...');
    const rostersRes = await axios.get(`${BASE_URL}/api/roster/pending`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    const rosters = rostersRes.data.rosters || rostersRes.data;
    console.log(`✓ Found ${rosters.length} pending rosters\n`);
    
    if (rosters.length === 0) {
      console.log('⚠ No pending rosters to test with');
      return;
    }
    
    // 4. Create optimized route
    console.log('4. Creating optimized route with trip creation...');
    const route = rosters.slice(0, 3).map((roster, idx) => ({
      rosterId: roster._id,
      customerId: roster.customerId,
      customerName: roster.customerName,
      customerEmail: roster.customerEmail || `test${idx}@test.com`,
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
    
    const optimizeRes = await axios.post(
      `${BASE_URL}/api/roster/assign-optimized-route`,
      payload,
      { headers: { Authorization: `Bearer ${token}` } }
    );
    
    console.log('✓ Route optimization successful!');
    console.log(`  Message: ${optimizeRes.data.message}`);
    console.log(`  Trips Created: ${optimizeRes.data.data.tripIds.length}`);
    console.log(`  Success Count: ${optimizeRes.data.data.successCount}`);
    console.log(`  Tracking Enabled: ${optimizeRes.data.data.trackingEnabled}`);
    console.log(`  Trip IDs: ${optimizeRes.data.data.tripIds.join(', ')}\n`);
    
    // 5. Verify trip in database
    if (optimizeRes.data.data.tripIds.length > 0) {
      const tripId = optimizeRes.data.data.tripIds[0];
      console.log('5. Verifying trip in database...');
      
      const tripRes = await axios.get(`${BASE_URL}/api/trips/${tripId}`, {
        headers: { Authorization: `Bearer ${token}` }
      });
      
      const trip = tripRes.data.trip || tripRes.data;
      console.log('✓ Trip found in database:');
      console.log(`  Trip Number: ${trip.tripNumber}`);
      console.log(`  Customer: ${trip.customer.name}`);
      console.log(`  Status: ${trip.status}`);
      console.log(`  Sequence: ${trip.sequence}`);
      console.log(`  Start Time: ${trip.startTime}\n`);
    }
    
    console.log('🎉 All tests passed!');
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    if (error.response) {
      console.error('Response:', error.response.data);
    }
  }
}

quickTest();
