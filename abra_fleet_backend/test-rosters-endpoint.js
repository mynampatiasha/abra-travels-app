// Test if the /api/rosters/active-trip endpoint is accessible
const http = require('http');

function testEndpoint() {
  const userId = 'b5aoloVR7xYI6SICibCIWecBaf82';
  const path = `/api/rosters/active-trip/${userId}`;
  
  console.log('🔍 Testing endpoint accessibility...\n');
  console.log(`   URL: http://localhost:3000${path}\n`);
  
  const options = {
    hostname: 'localhost',
    port: 3000,
    path: path,
    method: 'GET',
    headers: {
      'Content-Type': 'application/json'
    }
  };
  
  const req = http.request(options, (res) => {
    console.log(`✅ Response Status: ${res.statusCode}`);
    console.log(`   Status Message: ${res.statusMessage}\n`);
    
    let data = '';
    
    res.on('data', (chunk) => {
      data += chunk;
    });
    
    res.on('end', () => {
      if (res.statusCode === 401) {
        console.log('⚠️  401 Unauthorized - This is expected without a valid token');
        console.log('   The endpoint exists and is protected by authentication ✅\n');
      } else if (res.statusCode === 404) {
        console.log('❌ 404 Not Found - The endpoint is not registered');
        console.log('   Need to check route mounting in index.js\n');
      } else {
        console.log('Response Data:');
        try {
          const parsed = JSON.parse(data);
          console.log(JSON.stringify(parsed, null, 2));
        } catch (e) {
          console.log(data);
        }
      }
    });
  });
  
  req.on('error', (error) => {
    console.error('❌ Error:', error.message);
  });
  
  req.end();
}

// Wait a moment for server to be ready
setTimeout(testEndpoint, 1000);
