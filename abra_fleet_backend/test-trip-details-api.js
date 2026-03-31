// Test the assigned trips API to see what data is returned
const axios = require('axios');

async function testTripDetails() {
  try {
    console.log('🔍 Testing assigned trips API...\n');
    
    // First, let's try without auth to see the error
    console.log('Step 1: Fetching assigned trips...');
    
    const response = await axios.get('http://localhost:5000/api/roster/admin/assigned-trips', {
      params: {
        status: 'assigned'
      }
    }).catch(err => {
      if (err.response && err.response.status === 401) {
        console.log('⚠️  Need authentication (expected)');
        console.log('\n💡 To test with real data:');
        console.log('1. Open your browser');
        console.log('2. Login as admin');
        console.log('3. Open DevTools → Network tab');
        console.log('4. Look for any API request');
        console.log('5. Copy the Authorization header token');
        console.log('6. Add it to this script\n');
        return null;
      }
      throw err;
    });
    
    if (!response) {
      console.log('❌ Cannot test without authentication');
      console.log('\n🔧 Alternative: Check database directly');
      console.log('   Run: node check-assigned-trips-db.js');
      return;
    }
    
    const trips = response.data.data;
    console.log(`✅ Found ${trips.length} assigned trips\n`);
    
    if (trips.length === 0) {
      console.log('⚠️  No assigned trips found!');
      return;
    }
    
    // Analyze first trip
    const trip = trips[0];
    console.log('📋 First Trip Details:');
    console.log(JSON.stringify(trip, null, 2));
    
    // Check vehicle/driver fields
    console.log('\n🔍 Vehicle/Driver Status:');
    console.log(`   vehicleId: ${trip.vehicleId ? '✅ ' + trip.vehicleId : '❌ EMPTY'}`);
    console.log(`   vehicleNumber: ${trip.vehicleNumber ? '✅ ' + trip.vehicleNumber : '❌ EMPTY'}`);
    console.log(`   driverId: ${trip.driverId ? '✅ ' + trip.driverId : '❌ EMPTY'}`);
    console.log(`   driverName: ${trip.driverName ? '✅ ' + trip.driverName : '❌ EMPTY'}`);
    
    if (!trip.vehicleId && !trip.vehicleNumber && !trip.driverId && !trip.driverName) {
      console.log('\n❌ PROBLEM CONFIRMED!');
      console.log('   This trip has NO vehicle or driver data.');
      console.log('\n💡 This means the trip was never properly assigned through');
      console.log('   the Route Optimization feature.');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    
    if (error.code === 'ECONNREFUSED') {
      console.log('\n💡 Backend is not running!');
      console.log('   Start the backend: cd abra_fleet_backend && node index.js');
    }
  }
}

testTripDetails();
