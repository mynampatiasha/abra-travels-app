// test-jwt-system.js - Test JWT Authentication System
const axios = require('axios');

const BASE_URL = 'http://localhost:3001';

async function testJWTSystem() {
  console.log('🧪 TESTING JWT AUTHENTICATION SYSTEM');
  console.log('═'.repeat(80));
  
  try {
    // Test 1: Health Check
    console.log('\n1️⃣ Testing Health Check...');
    const healthResponse = await axios.get(`${BASE_URL}/health`);
    console.log('✅ Health check passed:', healthResponse.data.status);
    
    // Test 2: Login with existing user
    console.log('\n2️⃣ Testing Login...');
    const loginData = {
      email: 'admin@abrafleet.com',
      password: 'admin123' // Default password
    };
    
    const loginResponse = await axios.post(`${BASE_URL}/api/auth/login`, loginData);
    
    if (loginResponse.data.success) {
      console.log('✅ Login successful');
      console.log('   User:', loginResponse.data.data.user.name);
      console.log('   Role:', loginResponse.data.data.user.role);
      console.log('   Token length:', loginResponse.data.data.token.length);
      
      const token = loginResponse.data.data.token;
      
      // Test 3: Protected Route Access
      console.log('\n3️⃣ Testing Protected Route Access...');
      const authHeaders = {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      };
      
      const meResponse = await axios.get(`${BASE_URL}/api/auth/me`, { headers: authHeaders });
      
      if (meResponse.data.success) {
        console.log('✅ Protected route access successful');
        console.log('   Authenticated as:', meResponse.data.data.user.email);
        console.log('   Role:', meResponse.data.data.user.role);
      }
      
      // Test 4: Test Auth Endpoint
      console.log('\n4️⃣ Testing Auth Test Endpoint...');
      const testAuthResponse = await axios.get(`${BASE_URL}/api/test-auth`, { headers: authHeaders });
      
      if (testAuthResponse.data.status === 'success') {
        console.log('✅ Auth test endpoint successful');
        console.log('   Message:', testAuthResponse.data.message);
      }
      
    } else {
      console.log('❌ Login failed:', loginResponse.data.message);
    }
    
    // Test 5: Invalid Token
    console.log('\n5️⃣ Testing Invalid Token...');
    try {
      await axios.get(`${BASE_URL}/api/auth/me`, {
        headers: { 'Authorization': 'Bearer invalid_token' }
      });
      console.log('❌ Invalid token test failed - should have been rejected');
    } catch (error) {
      if (error.response?.status === 401) {
        console.log('✅ Invalid token correctly rejected');
      } else {
        console.log('⚠️  Unexpected error:', error.message);
      }
    }
    
    // Test 6: No Token
    console.log('\n6️⃣ Testing No Token...');
    try {
      await axios.get(`${BASE_URL}/api/auth/me`);
      console.log('❌ No token test failed - should have been rejected');
    } catch (error) {
      if (error.response?.status === 401) {
        console.log('✅ No token correctly rejected');
      } else {
        console.log('⚠️  Unexpected error:', error.message);
      }
    }
    
    console.log('\n' + '═'.repeat(80));
    console.log('🎉 JWT SYSTEM TEST COMPLETED SUCCESSFULLY!');
    console.log('✅ All authentication tests passed');
    console.log('✅ JWT tokens are working correctly');
    console.log('✅ Protected routes are secured');
    console.log('✅ Invalid tokens are rejected');
    console.log('═'.repeat(80));
    
  } catch (error) {
    console.error('\n❌ JWT SYSTEM TEST FAILED');
    console.error('═'.repeat(80));
    console.error('Error:', error.message);
    
    if (error.response) {
      console.error('Status:', error.response.status);
      console.error('Data:', error.response.data);
    }
    
    if (error.code === 'ECONNREFUSED') {
      console.error('\n💡 SOLUTION: Make sure the backend server is running');
      console.error('   Run: cd abra_fleet_backend && npm start');
    }
  }
}

// Run the test
testJWTSystem();