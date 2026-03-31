// Test driver location endpoint
const axios = require('axios');

async function testDriverLocationEndpoint() {
  try {
    console.log('Testing driver location endpoint...\n');

    // Test without auth (should fail)
    console.log('1. Testing without authentication:');
    try {
      const response = await axios.post('http://localhost:3000/api/tracking/driver/location', {
        latitude: 12.9716,
        longitude: 77.5946,
        speed: 0,
        heading: 0,
        accuracy: 10
      });
      console.log('❌ Should have failed without auth');
    } catch (error) {
      if (error.response) {
        console.log(`✅ Correctly rejected: ${error.response.status} - ${error.response.data.message}`);
      } else {
        console.log(`❌ Network error: ${error.message}`);
      }
    }

    console.log('\n2. Checking if backend is running:');
    try {
      const response = await axios.get('http://localhost:3000/health');
      console.log(`✅ Backend is running: ${response.data.message}`);
    } catch (error) {
      console.log(`❌ Backend not accessible: ${error.message}`);
    }

  } catch (error) {
    console.error('Test failed:', error.message);
  }
}

testDriverLocationEndpoint();
