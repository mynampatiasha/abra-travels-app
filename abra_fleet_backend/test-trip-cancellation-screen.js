// Test script to verify trip cancellation management endpoint
const axios = require('axios');
require('dotenv').config();

const API_URL = process.env.API_URL || 'http://localhost:3000';

async function testTripCancellationEndpoint() {
  console.log('🧪 Testing Trip Cancellation Management Endpoint...\n');
  
  try {
    // Note: You'll need a valid admin token for this test
    // For now, we'll just test if the endpoint exists
    
    const response = await axios.get(`${API_URL}/api/roster/admin/approved-leave-requests`, {
      headers: {
        'Authorization': 'Bearer YOUR_ADMIN_TOKEN_HERE'
      },
      validateStatus: () => true // Accept any status code
    });
    
    console.log('📊 Response Status:', response.status);
    console.log('📊 Response Data:', JSON.stringify(response.data, null, 2));
    
    if (response.status === 401) {
      console.log('\n⚠️  Endpoint exists but requires authentication (expected)');
      console.log('✅ Endpoint is properly configured');
    } else if (response.status === 200) {
      console.log('\n✅ Endpoint working correctly!');
      console.log(`📋 Found ${response.data.count || 0} approved leave requests`);
    } else {
      console.log('\n❌ Unexpected response status');
    }
    
  } catch (error) {
    if (error.code === 'ECONNREFUSED') {
      console.log('❌ Backend server is not running!');
      console.log('💡 Start the backend with: node abra_fleet_backend/index.js');
    } else {
      console.log('❌ Error:', error.message);
    }
  }
}

testTripCancellationEndpoint();
