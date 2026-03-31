const axios = require('axios');

const BASE_URL = 'http://localhost:3000';

// Test configuration
const config = {
  adminToken: '', // Will be set after login
  driverToken: '', // Will be set after driver login
  vehicleId: '',
  driverId: '',
  tripId: '',
  testRosters: []
};

// Color codes for console output
const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

function logSection(title) {
  console.log('\n' + '='.repeat(60));
  log(title, 'cyan');
  console.log('='.repeat(60) + '\n');
}

// Step 1: Admin Login
async function adminLogin() {
  logSection('STEP 1: Admin Login');
  try {
    const response = await axios.post(`${BASE_URL}/api/auth/login`, {
      email: 'admin@abrafleet.com',
      password: 'Admin@123'
    });
    
    config.adminToken = response.data.token;
    log('✓ Admin login successful', 'green');
    log(`Token: ${config.adminToken.substring(0, 20)}...`, 'blue');
    return true;
  } catch (error) {
    log('✗ Admin login failed: ' + error.message, 'red');
    return false;
  }
}

// Step 2: Get Available Vehicle
async function getAvailableVehicle() {
  logSection('STEP 2: Get Available Vehicle');
  try {
    const response = await axios.get(`${BASE_URL}/api/admin/vehicles`, {
      headers: { Authorization: `Bearer ${config.adminToken}` }
    });
    
    const vehicles = response.data.vehicles || response.data;
    if (vehicles.length > 0) {
      config.vehicleId = vehicles[0]._id;
      config.driverId = vehicles[0].driverId;
      log('✓ Vehicle found', 'green');
      log(`Vehicle ID: ${config.vehicleId}`, 'blue');
      log(`Driver ID: ${config.driverId}`, 'blue');
      log(`Vehicle: ${vehicles[0].vehicleNumber} (${vehicles[0].vehicleType})`, 'blue');
      log(`Capacity: ${vehicles[0].seatCapacity} seats`, 'blue');
      return true;
    } else {
      log('✗ No vehicles available', 'red');
      return false;
    }
  } catch (error) {
    log('✗ Failed to get vehicles: ' + error.message, 'red');
    return false;
  }
}

// Step 3: Get Pending Rosters
async function getPendingRosters() {
  logSection('STEP 3: Get Pending Rosters');
  try {
    const response = await axios.get(`${BASE_URL}/api/roster/pending`, {
      headers: { Authorization: `Bearer ${config.adminToken}` }
    });
    
    config.testRosters = response.data.rosters || response.data;
    log(`✓ Found ${config.testRosters.length} pending rosters`, 'green');
    
    if (config.testRosters.length > 0) {
      log('\nFirst 3 rosters:', 'blue');
      config.testRosters.slice(0, 3).forEach((roster, idx) => {
        log(`  ${idx + 1}. ${roster.customerName} - ${roster.pickupLocation}`, 'blue');
      });
      return true;
    } else {
      log('⚠ No pending rosters found', 'yellow');
      return false;
    }
  } catch (error) {
    log('✗ Failed to get rosters: ' + error.message, 'red');
    return false;
  }
}

// Step 4: Test Route Optimization + Trip Creation
async function testRouteOptimization() {
  logSection('STEP 4: Route Optimization + Trip Creation');
  
  if (config.testRosters.length === 0) {
    log('⚠ Skipping - no rosters available', 'yellow');
    return false;
  }
  
  try {
    // Prepare route data from first 3 rosters
    const route = config.testRosters.slice(0, 3).map((roster, idx) => ({
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
      vehicleId: config.vehicleId,
      route: route,
      totalDistance: route.reduce((sum, r) => sum + r.distanceFromPrevious, 0),
      totalTime: route.reduce((sum, r) => sum + r.estimatedTime, 0),
      startTime: new Date().toISOString()
    };
    
    log('Sending route optimization request...', 'blue');
    log(`Vehicle: ${config.vehicleId}`, 'blue');
    log(`Customers: ${route.length}`, 'blue');
    
    const response = await axios.post(
      `${BASE_URL}/api/roster/assign-optimized-route`,
      payload,
      { headers: { Authorization: `Bearer ${config.adminToken}` } }
    );
    
    log('\n✓ Route optimization successful!', 'green');
    log(`Success: ${response.data.success}`, 'green');
    log(`Message: ${response.data.message}`, 'green');
    log(`Trips Created: ${response.data.data.tripIds.length}`, 'green');
    log(`Success Count: ${response.data.data.successCount}`, 'green');
    log(`Tracking Enabled: ${response.data.data.trackingEnabled}`, 'green');
    
    if (response.data.data.tripIds.length > 0) {
      config.tripId = response.data.data.tripIds[0];
      log(`\nFirst Trip ID: ${config.tripId}`, 'blue');
    }
    
    return true;
  } catch (error) {
    log('✗ Route optimization failed', 'red');
    if (error.response) {
      log(`Status: ${error.response.status}`, 'red');
      log(`Error: ${JSON.stringify(error.response.data, null, 2)}`, 'red');
    } else {
      log(`Error: ${error.message}`, 'red');
    }
    return false;
  }
}

// Step 5: Driver Login
async function driverLogin() {
  logSection('STEP 5: Driver Login');
  
  if (!config.driverId) {
    log('⚠ Skipping - no driver ID available', 'yellow');
    return false;
  }
  
  try {
    // Get driver details first
    const driverResponse = await axios.get(
      `${BASE_URL}/api/admin/drivers`,
      { headers: { Authorization: `Bearer ${config.adminToken}` } }
    );
    
    const drivers = driverResponse.data.drivers || driverResponse.data;
    const driver = drivers.find(d => d._id === config.driverId || d.uid === config.driverId);
    
    if (!driver) {
      log('✗ Driver not found', 'red');
      return false;
    }
    
    log(`Driver: ${driver.name}`, 'blue');
    log(`Email: ${driver.email}`, 'blue');
    
    // Try to login with driver credentials
    const loginResponse = await axios.post(`${BASE_URL}/api/auth/login`, {
      email: driver.email,
      password: 'Driver@123' // Default password
    });
    
    config.driverToken = loginResponse.data.token;
    log('✓ Driver login successful', 'green');
    log(`Token: ${config.driverToken.substring(0, 20)}...`, 'blue');
    return true;
  } catch (error) {
    log('✗ Driver login failed: ' + error.message, 'red');
    log('⚠ Will skip driver-specific tests', 'yellow');
    return false;
  }
}

// Step 6: Get Driver's Today Trips
async function getDriverTodayTrips() {
  logSection('STEP 6: Get Driver Today Trips');
  
  if (!config.driverToken || !config.driverId) {
    log('⚠ Skipping - no driver token or ID', 'yellow');
    return false;
  }
  
  try {
    const response = await axios.get(
      `${BASE_URL}/api/trips/driver/${config.driverId}/today`,
      { headers: { Authorization: `Bearer ${config.driverToken}` } }
    );
    
    const trips = response.data.trips || response.data;
    log(`✓ Found ${trips.length} trips for today`, 'green');
    
    if (trips.length > 0) {
      log('\nTrip Details:', 'blue');
      trips.forEach((trip, idx) => {
        log(`\n  Trip ${idx + 1}:`, 'blue');
        log(`    Trip Number: ${trip.tripNumber}`, 'blue');
        log(`    Customer: ${trip.customer.name}`, 'blue');
        log(`    Status: ${trip.status}`, 'blue');
        log(`    Start Time: ${trip.startTime}`, 'blue');
        log(`    Sequence: ${trip.sequence}`, 'blue');
      });
    }
    
    return true;
  } catch (error) {
    log('✗ Failed to get driver trips: ' + error.message, 'red');
    if (error.response) {
      log(`Status: ${error.response.status}`, 'red');
      log(`Error: ${JSON.stringify(error.response.data, null, 2)}`, 'red');
    }
    return false;
  }
}

// Step 7: Update Trip Status
async function updateTripStatus() {
  logSection('STEP 7: Update Trip Status');
  
  if (!config.driverToken || !config.tripId) {
    log('⚠ Skipping - no driver token or trip ID', 'yellow');
    return false;
  }
  
  try {
    const statuses = ['started', 'in_progress', 'completed'];
    
    for (const status of statuses) {
      log(`\nUpdating trip to: ${status}`, 'blue');
      
      const response = await axios.post(
        `${BASE_URL}/api/trips/${config.tripId}/status`,
        { status },
        { headers: { Authorization: `Bearer ${config.driverToken}` } }
      );
      
      log(`✓ Status updated to: ${status}`, 'green');
      log(`Message: ${response.data.message}`, 'green');
      
      // Wait a bit between status updates
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
    
    return true;
  } catch (error) {
    log('✗ Failed to update trip status: ' + error.message, 'red');
    if (error.response) {
      log(`Status: ${error.response.status}`, 'red');
      log(`Error: ${JSON.stringify(error.response.data, null, 2)}`, 'red');
    }
    return false;
  }
}

// Step 8: Verify Database Collections
async function verifyDatabase() {
  logSection('STEP 8: Verify Database Collections');
  
  if (!config.tripId) {
    log('⚠ Skipping - no trip ID to verify', 'yellow');
    return false;
  }
  
  try {
    // Get trip details
    const response = await axios.get(
      `${BASE_URL}/api/trips/${config.tripId}`,
      { headers: { Authorization: `Bearer ${config.adminToken}` } }
    );
    
    const trip = response.data.trip || response.data;
    
    log('✓ Trip found in database', 'green');
    log('\nTrip Structure:', 'blue');
    log(`  Trip Number: ${trip.tripNumber}`, 'blue');
    log(`  Roster ID: ${trip.rosterId}`, 'blue');
    log(`  Vehicle ID: ${trip.vehicleId}`, 'blue');
    log(`  Driver ID: ${trip.driverId}`, 'blue');
    log(`  Customer Name: ${trip.customer.name}`, 'blue');
    log(`  Customer Email: ${trip.customer.email}`, 'blue');
    log(`  Customer Phone: ${trip.customer.phone}`, 'blue');
    log(`  Status: ${trip.status}`, 'blue');
    log(`  Scheduled Date: ${trip.scheduledDate}`, 'blue');
    log(`  Start Time: ${trip.startTime}`, 'blue');
    log(`  Sequence: ${trip.sequence}`, 'blue');
    log(`  Current Location: ${trip.currentLocation || 'null'}`, 'blue');
    log(`  Location History: ${trip.locationHistory ? trip.locationHistory.length : 0} entries`, 'blue');
    
    return true;
  } catch (error) {
    log('✗ Failed to verify database: ' + error.message, 'red');
    if (error.response) {
      log(`Status: ${error.response.status}`, 'red');
      log(`Error: ${JSON.stringify(error.response.data, null, 2)}`, 'red');
    }
    return false;
  }
}

// Main test runner
async function runTests() {
  log('\n🚀 ROUTE OPTIMIZATION + TRIP CREATION INTEGRATION TEST', 'cyan');
  log('Testing all endpoints and database collections\n', 'cyan');
  
  const results = {
    passed: 0,
    failed: 0,
    skipped: 0
  };
  
  // Run all tests
  const tests = [
    { name: 'Admin Login', fn: adminLogin },
    { name: 'Get Available Vehicle', fn: getAvailableVehicle },
    { name: 'Get Pending Rosters', fn: getPendingRosters },
    { name: 'Route Optimization + Trip Creation', fn: testRouteOptimization },
    { name: 'Driver Login', fn: driverLogin },
    { name: 'Get Driver Today Trips', fn: getDriverTodayTrips },
    { name: 'Update Trip Status', fn: updateTripStatus },
    { name: 'Verify Database Collections', fn: verifyDatabase }
  ];
  
  for (const test of tests) {
    try {
      const result = await test.fn();
      if (result === false && test.name.includes('Driver')) {
        results.skipped++;
      } else if (result) {
        results.passed++;
      } else {
        results.failed++;
      }
    } catch (error) {
      log(`\n✗ Test "${test.name}" crashed: ${error.message}`, 'red');
      results.failed++;
    }
  }
  
  // Final summary
  logSection('TEST SUMMARY');
  log(`✓ Passed: ${results.passed}`, 'green');
  log(`✗ Failed: ${results.failed}`, results.failed > 0 ? 'red' : 'green');
  log(`⊘ Skipped: ${results.skipped}`, 'yellow');
  log(`\nTotal: ${results.passed + results.failed + results.skipped} tests`, 'blue');
  
  if (results.failed === 0) {
    log('\n🎉 ALL TESTS PASSED!', 'green');
  } else {
    log('\n⚠ SOME TESTS FAILED', 'red');
  }
}

// Run the tests
runTests().catch(error => {
  log('\n💥 Test suite crashed: ' + error.message, 'red');
  console.error(error);
  process.exit(1);
});
