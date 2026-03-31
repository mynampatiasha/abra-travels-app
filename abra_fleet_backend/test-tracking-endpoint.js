const axios = require('axios');

async function testTrackingEndpoint() {
  try {
    console.log('Testing tracking endpoint...');
    
    // Test the endpoint that was failing
    const response = await axios.get('http://localhost:3000/api/tracking/trip/trip_VSCJkbM0AEhupcIMsCXJr3oFeYo1/location', {
      headers: {
        'Authorization': 'Bearer test-token'
      }
    });
    
    console.log('✅ Success:', response.data);
  } catch (error) {
    console.log('❌ Error:', error.response?.status, error.response?.data || error.message);
  }
}

testTrackingEndpoint();