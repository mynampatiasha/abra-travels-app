#!/usr/bin/env node

/**
 * Endpoint Testing Script - Identifies Broken APIs After Firebase Removal
 * 
 * This script will:
 * 1. Test your server endpoints
 * 2. Identify which ones are broken
 * 3. Show you the exact errors
 * 
 * Usage:
 *   node test-all-endpoints.js
 */

const http = require('http');
const https = require('https');

// Configuration
const BASE_URL = process.env.API_URL || 'http://localhost:3001';
const TEST_EMAIL = process.env.TEST_EMAIL || 'admin@abrafleet.com';
const TEST_PASSWORD = process.env.TEST_PASSWORD || 'admin123';

let authToken = null;

// Colors for console output
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m',
};

function log(color, ...args) {
  console.log(color, ...args, colors.reset);
}

function makeRequest(method, path, body = null, useAuth = true) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, BASE_URL);
    const isHttps = url.protocol === 'https:';
    const client = isHttps ? https : http;

    const headers = {
      'Content-Type': 'application/json',
    };

    if (useAuth && authToken) {
      headers['Authorization'] = `Bearer ${authToken}`;
    }

    if (body) {
      headers['Content-Length'] = Buffer.byteLength(JSON.stringify(body));
    }

    const options = {
      hostname: url.hostname,
      port: url.port || (isHttps ? 443 : 80),
      path: url.pathname + url.search,
      method: method,
      headers: headers,
      timeout: 5000,
    };

    const req = client.request(options, (res) => {
      let data = '';

      res.on('data', (chunk) => {
        data += chunk;
      });

      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: parsed,
          });
        } catch (e) {
          resolve({
            status: res.statusCode,
            headers: res.headers,
            body: data,
          });
        }
      });
    });

    req.on('error', (error) => {
      reject(error);
    });

    req.on('timeout', () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });

    if (body) {
      req.write(JSON.stringify(body));
    }

    req.end();
  });
}

// Test results tracking
const results = {
  passed: [],
  failed: [],
  skipped: [],
};

async function testEndpoint(name, method, path, expectedStatus = 200, body = null, useAuth = true) {
  try {
    log(colors.cyan, `\n🧪 Testing: ${name}`);
    log(colors.blue, `   ${method} ${path}`);

    const response = await makeRequest(method, path, body, useAuth);

    if (response.status === expectedStatus) {
      log(colors.green, `   ✅ PASS - Status: ${response.status}`);
      results.passed.push({ name, method, path, status: response.status });
      return true;
    } else {
      log(colors.red, `   ❌ FAIL - Expected: ${expectedStatus}, Got: ${response.status}`);
      log(colors.yellow, `   Response: ${JSON.stringify(response.body).substring(0, 200)}`);
      results.failed.push({
        name,
        method,
        path,
        expectedStatus,
        actualStatus: response.status,
        error: response.body,
      });
      return false;
    }
  } catch (error) {
    log(colors.red, `   ❌ ERROR - ${error.message}`);
    results.failed.push({
      name,
      method,
      path,
      error: error.message,
    });
    return false;
  }
}

async function runTests() {
  console.clear();
  log(colors.bright + colors.magenta, '╔════════════════════════════════════════════════════════════════╗');
  log(colors.bright + colors.magenta, '║     ENDPOINT TESTING SCRIPT - Firebase Removal Diagnosis       ║');
  log(colors.bright + colors.magenta, '╚════════════════════════════════════════════════════════════════╝');
  
  log(colors.cyan, `\n📡 Testing API: ${BASE_URL}`);
  log(colors.cyan, `🔐 Test User: ${TEST_EMAIL}\n`);

  // ============================================================================
  // PHASE 1: Public Endpoints (No Auth Required)
  // ============================================================================
  log(colors.bright + colors.blue, '\n' + '═'.repeat(70));
  log(colors.bright + colors.blue, 'PHASE 1: PUBLIC ENDPOINTS (No Authentication)');
  log(colors.bright + colors.blue, '═'.repeat(70));

  await testEndpoint('Health Check', 'GET', '/health', 200, null, false);
  await testEndpoint('Database Test', 'GET', '/test-db', 200, null, false);

  // ============================================================================
  // PHASE 2: Authentication
  // ============================================================================
  log(colors.bright + colors.blue, '\n' + '═'.repeat(70));
  log(colors.bright + colors.blue, 'PHASE 2: AUTHENTICATION');
  log(colors.bright + colors.blue, '═'.repeat(70));

  // Try to login
  log(colors.yellow, '\n🔑 Attempting login...');
  try {
    const loginResponse = await makeRequest('POST', '/api/auth/login', {
      email: TEST_EMAIL,
      password: TEST_PASSWORD,
    }, false);

    if (loginResponse.status === 200 && loginResponse.body.token) {
      authToken = loginResponse.body.token;
      log(colors.green, '✅ Login successful!');
      log(colors.green, `   Token: ${authToken.substring(0, 30)}...`);
      log(colors.green, `   User: ${loginResponse.body.user?.email || 'Unknown'}`);
      log(colors.green, `   Role: ${loginResponse.body.user?.role || 'Unknown'}`);
      results.passed.push({ name: 'Login', method: 'POST', path: '/api/auth/login' });
    } else {
      log(colors.red, '❌ Login failed!');
      log(colors.yellow, `   Status: ${loginResponse.status}`);
      log(colors.yellow, `   Response: ${JSON.stringify(loginResponse.body)}`);
      results.failed.push({
        name: 'Login',
        method: 'POST',
        path: '/api/auth/login',
        error: loginResponse.body,
      });
      
      log(colors.red, '\n⚠️  Cannot continue without authentication. Stopping tests.');
      log(colors.yellow, '\n💡 To fix:');
      log(colors.yellow, '   1. Make sure your server is running');
      log(colors.yellow, '   2. Create a test user with email: admin@abrafleet.com, password: admin123');
      log(colors.yellow, '   3. Or set TEST_EMAIL and TEST_PASSWORD environment variables');
      return;
    }
  } catch (error) {
    log(colors.red, `❌ Login error: ${error.message}`);
    log(colors.yellow, '\n💡 Make sure your server is running at:', BASE_URL);
    return;
  }

  // Test auth verification
  await testEndpoint('Auth Verification', 'GET', '/api/test-auth', 200);

  // ============================================================================
  // PHASE 3: Driver Endpoints
  // ============================================================================
  log(colors.bright + colors.blue, '\n' + '═'.repeat(70));
  log(colors.bright + colors.blue, 'PHASE 3: DRIVER ENDPOINTS');
  log(colors.bright + colors.blue, '═'.repeat(70));

  await testEndpoint('Driver Dashboard', 'GET', '/api/driver/dashboard', 200);
  await testEndpoint('Driver Trips', 'GET', '/api/driver/trips', 200);
  await testEndpoint('Driver Profile', 'GET', '/api/drivers/profile', 200);
  await testEndpoint('Driver Reports', 'GET', '/api/driver/reports', 200);

  // ============================================================================
  // PHASE 4: Admin Endpoints
  // ============================================================================
  log(colors.bright + colors.blue, '\n' + '═'.repeat(70));
  log(colors.bright + colors.blue, 'PHASE 4: ADMIN ENDPOINTS');
  log(colors.bright + colors.blue, '═'.repeat(70));

  await testEndpoint('Admin Users List', 'GET', '/api/admin/users', 200);
  await testEndpoint('Admin Drivers List', 'GET', '/api/admin/drivers', 200);
  await testEndpoint('Admin Vehicles List', 'GET', '/api/admin/vehicles', 200);
  await testEndpoint('Admin Customers List', 'GET', '/api/admin/customers', 200);
  await testEndpoint('Admin Trips List', 'GET', '/api/admin/trips', 200);

  // ============================================================================
  // PHASE 5: Roster & Assignment Endpoints
  // ============================================================================
  log(colors.bright + colors.blue, '\n' + '═'.repeat(70));
  log(colors.bright + colors.blue, 'PHASE 5: ROSTER & ASSIGNMENT ENDPOINTS');
  log(colors.bright + colors.blue, '═'.repeat(70));

  await testEndpoint('Roster List', 'GET', '/api/roster', 200);
  await testEndpoint('Pending Rosters', 'GET', '/api/assignment/pending-rosters', 200);
  await testEndpoint('Available Vehicles', 'GET', '/api/assignment/available-vehicles', 200);

  // ============================================================================
  // PHASE 6: Other Protected Endpoints
  // ============================================================================
  log(colors.bright + colors.blue, '\n' + '═'.repeat(70));
  log(colors.bright + colors.blue, 'PHASE 6: OTHER PROTECTED ENDPOINTS');
  log(colors.bright + colors.blue, '═'.repeat(70));

  await testEndpoint('Notifications', 'GET', '/api/notifications', 200);
  await testEndpoint('Clients List', 'GET', '/api/clients', 200);
  await testEndpoint('Documents', 'GET', '/api/documents', 200);
  await testEndpoint('Analytics', 'GET', '/api/admin/analytics/overview', 200);
  await testEndpoint('Billing Dashboard', 'GET', '/api/billing/dashboard', 200);

  // ============================================================================
  // FINAL RESULTS
  // ============================================================================
  log(colors.bright + colors.magenta, '\n' + '═'.repeat(70));
  log(colors.bright + colors.magenta, 'TEST RESULTS SUMMARY');
  log(colors.bright + colors.magenta, '═'.repeat(70));

  log(colors.green, `\n✅ PASSED: ${results.passed.length} endpoints`);
  if (results.passed.length > 0) {
    results.passed.forEach(test => {
      log(colors.green, `   ✓ ${test.name}`);
    });
  }

  log(colors.red, `\n❌ FAILED: ${results.failed.length} endpoints`);
  if (results.failed.length > 0) {
    results.failed.forEach(test => {
      log(colors.red, `   ✗ ${test.name} (${test.method} ${test.path})`);
      if (test.expectedStatus && test.actualStatus) {
        log(colors.yellow, `     Expected: ${test.expectedStatus}, Got: ${test.actualStatus}`);
      }
      if (test.error) {
        const errorStr = typeof test.error === 'string' ? test.error : JSON.stringify(test.error);
        log(colors.yellow, `     Error: ${errorStr.substring(0, 100)}...`);
      }
    });
  }

  // ============================================================================
  // RECOMMENDATIONS
  // ============================================================================
  if (results.failed.length > 0) {
    log(colors.bright + colors.yellow, '\n' + '═'.repeat(70));
    log(colors.bright + colors.yellow, 'RECOMMENDATIONS FOR FAILED ENDPOINTS');
    log(colors.bright + colors.yellow, '═'.repeat(70));

    results.failed.forEach(test => {
      log(colors.cyan, `\n🔧 ${test.name}:`);
      
      // Analyze the error and provide specific recommendations
      if (test.actualStatus === 401) {
        log(colors.yellow, '   Issue: Authentication failed');
        log(colors.yellow, '   Fix: Check if JWT token is being sent correctly');
        log(colors.yellow, '        Verify verifyJWT middleware is in place');
      } else if (test.actualStatus === 403) {
        log(colors.yellow, '   Issue: Permission denied');
        log(colors.yellow, '   Fix: Check role-based access controls');
        log(colors.yellow, '        Verify req.user.role is set correctly');
      } else if (test.actualStatus === 404) {
        log(colors.yellow, '   Issue: Endpoint not found');
        log(colors.yellow, '   Fix: Check route is properly mounted in server.js');
      } else if (test.actualStatus === 500) {
        log(colors.yellow, '   Issue: Server error');
        log(colors.yellow, '   Fix: Check server logs for detailed error');
        log(colors.yellow, '        Likely using req.user.uid instead of req.user.email');
      } else if (test.error?.includes('uid')) {
        log(colors.yellow, '   Issue: Firebase UID still in use');
        log(colors.yellow, '   Fix: Replace req.user.uid with req.user.email or req.user.userId');
      } else if (test.error?.includes('customClaims')) {
        log(colors.yellow, '   Issue: Firebase customClaims still in use');
        log(colors.yellow, '   Fix: Replace req.user.customClaims.role with req.user.role');
      }
    });

    log(colors.bright + colors.cyan, '\n' + '═'.repeat(70));
    log(colors.bright + colors.cyan, 'NEXT STEPS');
    log(colors.bright + colors.cyan, '═'.repeat(70));
    log(colors.yellow, '\n1. Check server logs for detailed error messages');
    log(colors.yellow, '2. Review the route files for failed endpoints');
    log(colors.yellow, '3. Look for these common issues:');
    log(colors.yellow, '   - req.user.uid should be req.user.email or req.user.userId');
    log(colors.yellow, '   - Database queries using { uid: ... } should use { email: ... }');
    log(colors.yellow, '   - customClaims checks should use req.user.role');
    log(colors.yellow, '   - Missing verifyJWT middleware');
    log(colors.yellow, '\n4. See firebase-removal-fix-guide.md for detailed solutions\n');
  } else {
    log(colors.bright + colors.green, '\n' + '═'.repeat(70));
    log(colors.bright + colors.green, '🎉 ALL TESTS PASSED! 🎉');
    log(colors.bright + colors.green, '═'.repeat(70));
    log(colors.green, '\n✅ Your API is working correctly after Firebase removal!\n');
  }

  // Save results to file
  const fs = require('fs');
  const resultsFile = 'test-results.json';
  fs.writeFileSync(resultsFile, JSON.stringify(results, null, 2));
  log(colors.cyan, `\n💾 Full results saved to: ${resultsFile}\n`);
}

// Run the tests
runTests().catch(error => {
  log(colors.red, '\n❌ Fatal error running tests:', error.message);
  process.exit(1);
});