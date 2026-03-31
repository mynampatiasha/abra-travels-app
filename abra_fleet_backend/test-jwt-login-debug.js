// test-jwt-login-debug.js - Debug JWT login issue
const axios = require('axios');

async function testJWTLogin() {
  console.log('\n🔐 JWT LOGIN DEBUG TEST');
  console.log('='.repeat(80));
  
  const baseURL = 'http://localhost:3001';
  
  try {
    // Test 1: Check if server is running
    console.log('\n📡 STEP 1: Testing server health...');
    try {
      const healthResponse = await axios.get(`${baseURL}/health`);
      console.log('✅ Server is running');
      console.log('   Status:', healthResponse.data.status);
      console.log('   MongoDB:', healthResponse.data.mongodb);
    } catch (error) {
      console.log('❌ Server health check failed:', error.message);
      if (error.code === 'ECONNREFUSED') {
        console.log('❌ CRITICAL: Backend server is not running!');
        console.log('   Please start the backend server first:');
        console.log('   cd abra_fleet_backend && npm start');
        return;
      }
    }
    
    // Test 2: Check if JWT auth endpoint exists
    console.log('\n📡 STEP 2: Testing JWT auth endpoint...');
    try {
      const loginData = {
        email: 'admin@abrafleet.com',
        password: 'admin123'
      };
      
      console.log('   Attempting login with:', loginData.email);
      console.log('   URL:', `${baseURL}/api/auth/login`);
      
      const response = await axios.post(`${baseURL}/api/auth/login`, loginData, {
        headers: {
          'Content-Type': 'application/json'
        },
        timeout: 10000
      });
      
      console.log('✅ JWT Login successful!');
      console.log('   Status:', response.status);
      console.log('   Response:', JSON.stringify(response.data, null, 2));
      
      if (response.data.data && response.data.data.token) {
        console.log('✅ JWT Token received');
        console.log('   Token length:', response.data.data.token.length);
        
        // Test 3: Verify token works
        console.log('\n📡 STEP 3: Testing token verification...');
        const verifyResponse = await axios.get(`${baseURL}/api/auth/me`, {
          headers: {
            'Authorization': `Bearer ${response.data.data.token}`,
            'Content-Type': 'application/json'
          }
        });
        
        console.log('✅ Token verification successful!');
        console.log('   User data:', JSON.stringify(verifyResponse.data, null, 2));
      }
      
    } catch (error) {
      console.log('❌ JWT Login failed');
      console.log('   Status:', error.response?.status);
      console.log('   Status Text:', error.response?.statusText);
      console.log('   Error Message:', error.message);
      
      if (error.response?.data) {
        console.log('   Response Data:', JSON.stringify(error.response.data, null, 2));
      }
      
      if (error.response?.status === 404) {
        console.log('\n❌ CRITICAL: JWT auth endpoint not found!');
        console.log('   This means the JWT router is not properly mounted');
        console.log('   Check if /api/auth routes are registered in index.js');
      }
    }
    
    // Test 4: Check what routes are available
    console.log('\n📡 STEP 4: Testing available endpoints...');
    const testEndpoints = [
      '/api/auth/login',
      '/auth/login',
      '/api/jwt/login',
      '/jwt/login'
    ];
    
    for (const endpoint of testEndpoints) {
      try {
        await axios.post(`${baseURL}${endpoint}`, {
          email: 'test@test.com',
          password: 'test'
        });
        console.log(`✅ Endpoint exists: ${endpoint}`);
      } catch (error) {
        if (error.response?.status === 401 || error.response?.status === 400) {
          console.log(`✅ Endpoint exists: ${endpoint} (auth error expected)`);
        } else if (error.response?.status === 404) {
          console.log(`❌ Endpoint not found: ${endpoint}`);
        } else {
          console.log(`⚠️  Endpoint ${endpoint}: ${error.response?.status || error.message}`);
        }
      }
    }
    
  } catch (error) {
    console.error('❌ CRITICAL ERROR:', error.message);
  }
  
  console.log('\n' + '='.repeat(80));
}

// Run the test
testJWTLogin().catch(console.error);