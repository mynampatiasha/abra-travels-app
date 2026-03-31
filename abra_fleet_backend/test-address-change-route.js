// Quick test to verify address-change route is accessible
// Run: node test-address-change-route.js

const http = require('http');

console.log('\n🔍 Testing Address Change Route...\n');

// Test if backend is running
const options = {
  hostname: 'localhost',
  port: 3000,
  path: '/api/address-change/customer/current-addresses',
  method: 'GET',
  headers: {
    'Authorization': 'Bearer test_token',
    'Content-Type': 'application/json'
  }
};

const req = http.request(options, (res) => {
  console.log(`Status Code: ${res.statusCode}`);
  
  if (res.statusCode === 404) {
    console.log('❌ Route NOT FOUND (404)');
    console.log('\n💡 Solutions:');
    console.log('   1. Make sure backend is running: node index.js');
    console.log('   2. Check if address_change_router is imported in index.js');
    console.log('   3. Check if route is registered: app.use(\'/api/address-change\', ...)');
    console.log('   4. Restart the backend server\n');
  } else if (res.statusCode === 401) {
    console.log('✅ Route EXISTS (401 = Unauthorized, which is expected without valid token)');
    console.log('   The route is working! The 401 error is normal for this test.\n');
  } else if (res.statusCode === 500) {
    console.log('⚠️  Route EXISTS but has server error (500)');
    console.log('   Check backend logs for details\n');
  } else {
    console.log(`✅ Route responded with status: ${res.statusCode}\n`);
  }

  let data = '';
  res.on('data', (chunk) => {
    data += chunk;
  });

  res.on('end', () => {
    if (data) {
      console.log('Response:', data);
    }
  });
});

req.on('error', (error) => {
  console.log('❌ Cannot connect to backend');
  console.log(`   Error: ${error.message}`);
  console.log('\n💡 Make sure backend is running:');
  console.log('   cd abra_fleet_backend');
  console.log('   node index.js\n');
});

req.end();
