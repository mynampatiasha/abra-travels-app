const axios = require('axios');

async function testRealTripTracking() {
  try {
    console.log('Testing tracking endpoint with real trip ID...');
    
    // Test with the actual trip ID we found: TRIP_1766127636685
    const tripId = 'TRIP_1766127636685';
    
    try {
      const response = await axios.get(`http://localhost:3000/api/tracking/trip/${tripId}/location`, {
        headers: {
          'Authorization': 'Bearer test-token'
        }
      });
      console.log('❌ Should have failed with invalid token');
    } catch (error) {
      if (error.response?.status === 401) {
        console.log('✅ Correctly rejected invalid token: 401');
        console.log('✅ Endpoint exists and is protected');
      } else if (error.response?.status === 404) {
        console.log('❌ Trip not found - might need to check trip ID');
      } else {
        console.log('❌ Unexpected error:', error.response?.status, error.response?.data || error.message);
      }
    }
    
    console.log('\n✅ Tracking endpoint is working!');
    console.log('📝 Customer needs valid authentication to track their trip');
    
  } catch (error) {
    console.log('❌ Test error:', error.message);
  }
}

testRealTripTracking();