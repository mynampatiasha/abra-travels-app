// Test script to debug assign-optimized-route endpoint
const axios = require('axios');

const BASE_URL = 'http://localhost:3000';

// Test data from the logs
const testData = {
  vehicleId: '68ddeb3f4eff4fbe00488ec8',
  route: [
    {
      rosterId: '693a57a81f77993e2eb68929',
      customerId: 'test-customer-1',
      customerName: 'Asha',
      customerEmail: 'asha123@cognizant.com',
      customerPhone: '1234567890',
      sequence: 1,
      pickupTime: '12:08',
      eta: new Date().toISOString(),
      location: { lat: 12.995789, lng: 77.669990 },
      distanceFromPrevious: 0,
      estimatedTime: 0
    }
  ],
  totalDistance: 5.184651844857277,
  totalTime: 13,
  startTime: '2025-12-11T12:08:44.154'
};

async function testAssignOptimizedRoute() {
  try {
    console.log('🧪 Testing assign-optimized-route endpoint...');
    console.log('📋 Test Data:', JSON.stringify(testData, null, 2));
    
    // First, get a valid auth token
    console.log('\n🔐 Step 1: Getting auth token...');
    const loginResponse = await axios.post(`${BASE_URL}/api/auth/login`, {
      email: 'admin@abrafleet.com',
      password: 'admin123'
    });
    
    const token = loginResponse.data.token;
    console.log('✅ Got auth token');
    
    // Test the endpoint
    console.log('\n🚀 Step 2: Testing assign-optimized-route...');
    const response = await axios.post(
      `${BASE_URL}/api/roster/assign-optimized-route`,
      testData,
      {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      }
    );
    
    console.log('\n✅ SUCCESS!');
    console.log('Response:', JSON.stringify(response.data, null, 2));
    
  } catch (error) {
    console.error('\n❌ ERROR!');
    if (error.response) {
      console.error('Status:', error.response.status);
      console.error('Data:', JSON.stringify(error.response.data, null, 2));
    } else {
      console.error('Error:', error.message);
    }
  }
}

testAssignOptimizedRoute();
