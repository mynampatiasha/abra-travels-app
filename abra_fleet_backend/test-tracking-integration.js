/**
 * Test Script: Live Tracking Integration
 * Tests all tracking endpoints and functionality
 */

const axios = require('axios');

const BASE_URL = 'http://localhost:3000';
let authToken = '';
let driverId = '';
let vehicleId = '';
let tripId = '';

// Test credentials
const DRIVER_CREDENTIALS = {
  email: 'driver@test.com',
  password: 'driver123' // Update with actual password
};

// Color codes for console output
const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[36m',
  magenta: '\x1b[35m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

function logSection(title) {
  console.log('\n' + '='.repeat(60));
  log(title, 'blue');
  console.log('='.repeat(60) + '\n');
}

function logSuccess(message) {
  log(`✅ ${message}`, 'green');
}

function logError(message) {
  log(`❌ ${message}`, 'red');
}

function logInfo(message) {
  log(`ℹ️  ${message}`, 'yellow');
}

// Test 1: Driver Login
async function testDriverLogin() {
  logSection('TEST 1: Driver Login');
  
  try {
    const response = await axios.post(`${BASE_URL}/api/auth/login`, DRIVER_CREDENTIALS);
    
    if (response.data.success && response.data.token) {
      authToken = response.data.token;
      driverId = response.data.user.uid;
      logSuccess('Driver login successful');
      logInfo(`Driver ID: ${driverId}`);
      logInfo(`Token: ${authToken.substring(0, 20)}...`);
      return true;
    } else {
      logError('Login failed - no token received');
      return false;
    }
  } catch (error) {
    logError(`Login failed: ${error.response?.data?.message || error.message}`);
    return false;
  }
}

// Test 2: Get Today's Route
async function testGetTodayRoute() {
  logSection('TEST 2: Get Today\'s Route');
  
  try {
    const response = await axios.get(`${BASE_URL}/api/driver/route/today`, {
      headers: { Authorization: `Bearer ${authToken}` }
    });
    
    if (response.data.success && response.data.data) {
      const route = response.data.data;
      vehicleId = route.vehicle?.id;
      
      logSuccess('Today\'s route fetched successfully');
      logInfo(`Has Route: ${route.hasRoute}`);
      logInfo(`Vehicle: ${route.vehicle?.registrationNumber || 'N/A'}`);
      logInfo(`Customers: ${route.customers?.length || 0}`);
      logInfo(`Total Distance: ${route.routeSummary?.totalDistance || 0} km`);
      
      if (route.customers && route.customers.length > 0) {
        console.log('\nCustomers:');
        route.customers.forEach((customer, index) => {
          console.log(`  ${index + 1}. ${customer.customerName} - ${customer.address}`);
        });
      }
      
      return true;
    } else {
      logError('No route data received');
      return false;
    }
  } catch (error) {
    logError(`Failed to get route: ${error.response?.data?.message || error.message}`);
    return false;
  }
}

// Test 3: Start GPS Tracking
async function testStartTracking() {
  logSection('TEST 3: Start GPS Tracking');
  
  if (!vehicleId) {
    logError('No vehicle ID available - skipping tracking test');
    return false;
  }
  
  try {
    const response = await axios.post(
      `${BASE_URL}/api/tracking/start`,
      {
        driverId: driverId,
        vehicleId: vehicleId
      },
      {
        headers: { Authorization: `Bearer ${authToken}` }
      }
    );
    
    if (response.data.success) {
      tripId = response.data.tripId;
      logSuccess('GPS tracking started successfully');
      logInfo(`Trip ID: ${tripId}`);
      return true;
    } else {
      logError('Failed to start tracking');
      return false;
    }
  } catch (error) {
    logError(`Start tracking failed: ${error.response?.data?.message || error.message}`);
    return false;
  }
}

// Test 4: Update Location
async function testUpdateLocation() {
  logSection('TEST 4: Update Location');
  
  if (!tripId) {
    logError('No trip ID available - skipping location update test');
    return false;
  }
  
  // Simulate location updates
  const locations = [
    { lat: 25.2048, lng: 55.2708, speed: 20, heading: 90 },  // Dubai
    { lat: 25.2058, lng: 55.2718, speed: 25, heading: 95 },  // Moving
    { lat: 25.2068, lng: 55.2728, speed: 30, heading: 100 }  // Moving
  ];
  
  try {
    for (let i = 0; i < locations.length; i++) {
      const location = locations[i];
      
      const response = await axios.post(
        `${BASE_URL}/api/tracking/location`,
        {
          driverId: driverId,
          tripId: tripId,
          lat: location.lat,
          lng: location.lng,
          speed: location.speed,
          heading: location.heading,
          timestamp: new Date().toISOString()
        },
        {
          headers: { Authorization: `Bearer ${authToken}` }
        }
      );
      
      if (response.data.success) {
        logSuccess(`Location update ${i + 1}/${locations.length} successful`);
        logInfo(`Position: ${location.lat}, ${location.lng}`);
        logInfo(`Speed: ${location.speed} m/s, Heading: ${location.heading}°`);
      }
      
      // Wait 1 second between updates
      if (i < locations.length - 1) {
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }
    
    return true;
  } catch (error) {
    logError(`Location update failed: ${error.response?.data?.message || error.message}`);
    return false;
  }
}

// Test 5: Get Trip Location (Customer View)
async function testGetTripLocation() {
  logSection('TEST 5: Get Trip Location (Customer View)');
  
  if (!tripId) {
    logError('No trip ID available - skipping get location test');
    return false;
  }
  
  try {
    const response = await axios.get(
      `${BASE_URL}/api/tracking/trip/${tripId}`,
      {
        headers: { Authorization: `Bearer ${authToken}` }
      }
    );
    
    if (response.data.success && response.data.data) {
      const data = response.data.data;
      
      logSuccess('Trip location fetched successfully');
      
      if (data.driver && data.driver.locationData) {
        const loc = data.driver.locationData;
        logInfo(`Driver Location: ${loc.lat}, ${loc.lng}`);
        logInfo(`Speed: ${(loc.speed * 3.6).toFixed(1)} km/h`);
        logInfo(`Heading: ${loc.heading}°`);
        logInfo(`Online: ${loc.isOnline}`);
        logInfo(`Last Update: ${new Date(loc.timestamp).toLocaleTimeString()}`);
      }
      
      if (data.vehicle) {
        logInfo(`Vehicle: ${data.vehicle.registrationNumber}`);
      }
      
      if (data.customers && data.customers.length > 0) {
        logInfo(`Customers: ${data.customers.length}`);
      }
      
      return true;
    } else {
      logError('No trip location data received');
      return false;
    }
  } catch (error) {
    logError(`Get trip location failed: ${error.response?.data?.message || error.message}`);
    return false;
  }
}

// Test 6: Stop Tracking
async function testStopTracking() {
  logSection('TEST 6: Stop GPS Tracking');
  
  if (!tripId) {
    logError('No trip ID available - skipping stop tracking test');
    return false;
  }
  
  try {
    const response = await axios.post(
      `${BASE_URL}/api/tracking/stop`,
      {
        driverId: driverId,
        tripId: tripId
      },
      {
        headers: { Authorization: `Bearer ${authToken}` }
      }
    );
    
    if (response.data.success) {
      logSuccess('GPS tracking stopped successfully');
      return true;
    } else {
      logError('Failed to stop tracking');
      return false;
    }
  } catch (error) {
    logError(`Stop tracking failed: ${error.response?.data?.message || error.message}`);
    return false;
  }
}

// Test 7: Backend Health Check
async function testBackendHealth() {
  logSection('TEST 7: Backend Health Check');
  
  try {
    const response = await axios.get(`${BASE_URL}/health`);
    
    if (response.data.status === 'ok') {
      logSuccess('Backend is healthy');
      logInfo(`Message: ${response.data.message}`);
      return true;
    } else {
      logError('Backend health check failed');
      return false;
    }
  } catch (error) {
    logError(`Health check failed: ${error.message}`);
    return false;
  }
}

// Run all tests
async function runAllTests() {
  console.log('\n');
  log('🚀 LIVE TRACKING INTEGRATION TEST SUITE', 'magenta');
  log('Testing all tracking endpoints and functionality', 'magenta');
  console.log('\n');
  
  const results = {
    passed: 0,
    failed: 0,
    total: 7
  };
  
  // Run tests in sequence
  const tests = [
    { name: 'Backend Health Check', fn: testBackendHealth },
    { name: 'Driver Login', fn: testDriverLogin },
    { name: 'Get Today\'s Route', fn: testGetTodayRoute },
    { name: 'Start GPS Tracking', fn: testStartTracking },
    { name: 'Update Location', fn: testUpdateLocation },
    { name: 'Get Trip Location', fn: testGetTripLocation },
    { name: 'Stop GPS Tracking', fn: testStopTracking }
  ];
  
  for (const test of tests) {
    const result = await test.fn();
    if (result) {
      results.passed++;
    } else {
      results.failed++;
    }
    
    // Wait between tests
    await new Promise(resolve => setTimeout(resolve, 500));
  }
  
  // Summary
  logSection('TEST SUMMARY');
  log(`Total Tests: ${results.total}`, 'blue');
  log(`Passed: ${results.passed}`, 'green');
  log(`Failed: ${results.failed}`, results.failed > 0 ? 'red' : 'green');
  
  const percentage = ((results.passed / results.total) * 100).toFixed(1);
  log(`Success Rate: ${percentage}%`, percentage === '100.0' ? 'green' : 'yellow');
  
  console.log('\n');
  
  if (results.failed === 0) {
    log('🎉 ALL TESTS PASSED! Tracking integration is working correctly.', 'green');
  } else {
    log('⚠️  Some tests failed. Please check the errors above.', 'yellow');
  }
  
  console.log('\n');
}

// Run the test suite
runAllTests().catch(error => {
  logError(`Test suite failed: ${error.message}`);
  process.exit(1);
});
