// Test script for Driver Dashboard APIs
const axios = require('axios');
const admin = require('./config/firebase');

const BASE_URL = 'http://localhost:3000';

// Test driver credentials - update with actual driver from your database
const TEST_DRIVER_EMAIL = 'driver@test.com'; // Update this
const TEST_DRIVER_UID = 'driver_firebase_uid'; // Will be fetched automatically

async function getDriverToken() {
  try {
    // Create a custom token for testing
    const customToken = await admin.auth().createCustomToken(TEST_DRIVER_UID);
    console.log('✅ Custom token created for driver');
    return customToken;
  } catch (error) {
    console.error('❌ Error creating token:', error.message);
    throw error;
  }
}

async function testDriverDashboardAPIs() {
  console.log('\n' + '='.repeat(80));
  console.log('🧪 DRIVER DASHBOARD API TESTS');
  console.log('='.repeat(80) + '\n');

  try {
    // Get authentication token
    console.log('🔐 Getting authentication token...');
    const token = await getDriverToken();
    const headers = { Authorization: `Bearer ${token}` };
    console.log('✅ Token obtained\n');

    // Test 1: Dashboard Stats
    console.log('1️⃣  Testing Dashboard Stats API');
    console.log('   GET /api/driver/dashboard/stats');
    try {
      const statsResponse = await axios.get(`${BASE_URL}/api/driver/dashboard/stats`, { headers });
      console.log('   ✅ Success:', JSON.stringify(statsResponse.data, null, 2));
    } catch (error) {
      console.log('   ❌ Failed:', error.response?.data || error.message);
    }
    console.log('');

    // Test 2: Vehicle Check
    console.log('2️⃣  Testing Vehicle Check API');
    console.log('   GET /api/driver/dashboard/vehicle-check');
    try {
      const vehicleResponse = await axios.get(`${BASE_URL}/api/driver/dashboard/vehicle-check`, { headers });
      console.log('   ✅ Success:', JSON.stringify(vehicleResponse.data, null, 2));
    } catch (error) {
      console.log('   ❌ Failed:', error.response?.data || error.message);
    }
    console.log('');

    // Test 3: Active Trip
    console.log('3️⃣  Testing Active Trip API');
    console.log('   GET /api/driver/trips/active');
    try {
      const tripResponse = await axios.get(`${BASE_URL}/api/driver/trips/active`, { headers });
      console.log('   ✅ Success:', JSON.stringify(tripResponse.data, null, 2));
      
      // If there's an active trip, test status update
      if (tripResponse.data.data && tripResponse.data.data.trip) {
        const tripId = tripResponse.data.data.trip.id;
        console.log('\n   📝 Testing Trip Status Update...');
        try {
          const updateResponse = await axios.patch(
            `${BASE_URL}/api/driver/trips/update-status`,
            { tripId, status: 'on_route' },
            { headers }
          );
          console.log('   ✅ Status Update Success:', updateResponse.data);
        } catch (error) {
          console.log('   ❌ Status Update Failed:', error.response?.data || error.message);
        }
      }
    } catch (error) {
      console.log('   ❌ Failed:', error.response?.data || error.message);
    }
    console.log('');

    // Test 4: Performance Summary
    console.log('4️⃣  Testing Performance Summary API');
    console.log('   GET /api/driver/reports/performance-summary');
    try {
      const perfResponse = await axios.get(`${BASE_URL}/api/driver/reports/performance-summary`, { headers });
      console.log('   ✅ Success:', JSON.stringify(perfResponse.data, null, 2));
    } catch (error) {
      console.log('   ❌ Failed:', error.response?.data || error.message);
    }
    console.log('');

    // Test 5: Daily Analytics
    console.log('5️⃣  Testing Daily Analytics API');
    console.log('   GET /api/driver/reports/daily-analytics');
    try {
      const analyticsResponse = await axios.get(`${BASE_URL}/api/driver/reports/daily-analytics`, { headers });
      console.log('   ✅ Success:', JSON.stringify(analyticsResponse.data, null, 2));
    } catch (error) {
      console.log('   ❌ Failed:', error.response?.data || error.message);
    }
    console.log('');

    // Test 6: Filtered Trips
    console.log('6️⃣  Testing Filtered Trips API');
    const startDate = new Date();
    startDate.setDate(startDate.getDate() - 7); // Last 7 days
    console.log(`   GET /api/driver/reports/trips?startDate=${startDate.toISOString()}`);
    try {
      const tripsResponse = await axios.get(
        `${BASE_URL}/api/driver/reports/trips?startDate=${startDate.toISOString()}`,
        { headers }
      );
      console.log('   ✅ Success:', JSON.stringify(tripsResponse.data, null, 2));
    } catch (error) {
      console.log('   ❌ Failed:', error.response?.data || error.message);
    }
    console.log('');

    // Test 7: Generate Report
    console.log('7️⃣  Testing Generate Report API');
    console.log('   POST /api/driver/reports/generate');
    try {
      const reportResponse = await axios.post(
        `${BASE_URL}/api/driver/reports/generate`,
        { type: 'daily' },
        { headers }
      );
      console.log('   ✅ Success:', JSON.stringify(reportResponse.data, null, 2));
      
      // If report generated, test download
      if (reportResponse.data.data && reportResponse.data.data.reportId) {
        const reportId = reportResponse.data.data.reportId;
        console.log('\n   📥 Testing Report Download...');
        console.log(`   GET /api/driver/reports/download/${reportId}`);
        try {
          const downloadResponse = await axios.get(
            `${BASE_URL}/api/driver/reports/download/${reportId}`,
            { headers, responseType: 'arraybuffer' }
          );
          console.log('   ✅ Download Success - PDF Size:', downloadResponse.data.length, 'bytes');
        } catch (error) {
          console.log('   ❌ Download Failed:', error.response?.data || error.message);
        }
      }
    } catch (error) {
      console.log('   ❌ Failed:', error.response?.data || error.message);
    }
    console.log('');

    // Test 8: Share Location
    console.log('8️⃣  Testing Share Location API');
    console.log('   POST /api/driver/trips/share-location');
    try {
      // This will fail if no active trip, but that's expected
      const locationResponse = await axios.post(
        `${BASE_URL}/api/driver/trips/share-location`,
        {
          tripId: 'test_trip_id',
          latitude: 28.4595,
          longitude: 77.0688
        },
        { headers }
      );
      console.log('   ✅ Success:', locationResponse.data);
    } catch (error) {
      console.log('   ⚠️  Expected failure (no active trip):', error.response?.data?.message || error.message);
    }
    console.log('');

    console.log('='.repeat(80));
    console.log('🎉 ALL TESTS COMPLETED!');
    console.log('='.repeat(80) + '\n');

  } catch (error) {
    console.error('\n❌ Test suite failed:', error.message);
    console.error('Stack:', error.stack);
  }
}

// Run tests
console.log('\n🚀 Starting Driver Dashboard API Tests...\n');
console.log('⚠️  Make sure:');
console.log('   1. Backend server is running (node index.js)');
console.log('   2. MongoDB is connected');
console.log('   3. Update TEST_DRIVER_UID with a real driver UID\n');

testDriverDashboardAPIs().then(() => {
  console.log('✅ Test script completed');
  process.exit(0);
}).catch((error) => {
  console.error('❌ Test script failed:', error);
  process.exit(1);
});
