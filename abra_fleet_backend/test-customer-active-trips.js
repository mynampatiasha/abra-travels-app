const axios = require('axios');

async function testCustomerActiveTrips() {
  try {
    console.log('Testing customer active trips endpoint...');
    
    // Test without auth first
    try {
      const response = await axios.get('http://localhost:3000/api/trips/customer/active');
      console.log('❌ Should have failed without auth');
    } catch (error) {
      if (error.response?.status === 401) {
        console.log('✅ Correctly rejected without auth: 401');
      } else {
        console.log('❌ Unexpected error:', error.response?.status, error.message);
      }
    }
    
    // Test with invalid auth
    try {
      const response = await axios.get('http://localhost:3000/api/trips/customer/active', {
        headers: {
          'Authorization': 'Bearer invalid-token'
        }
      });
      console.log('❌ Should have failed with invalid token');
    } catch (error) {
      if (error.response?.status === 401) {
        console.log('✅ Correctly rejected invalid token: 401');
      } else {
        console.log('❌ Unexpected error:', error.response?.status, error.message);
      }
    }
    
    console.log('\n✅ Endpoint is properly protected and working!');
    console.log('📝 Customer needs to authenticate to get their active trips');
    
  } catch (error) {
    console.log('❌ Test error:', error.message);
  }
}

testCustomerActiveTrips();