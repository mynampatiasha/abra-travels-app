// Test the active-trip endpoint
const axios = require('axios');

async function testActiveTrip() {
  try {
    const userId = 'b5aoloVR7xYI6SICibCIWecBaf82'; // customer123@abrafleet.com
    const url = `http://localhost:3000/api/rosters/active-trip/${userId}`;
    
    console.log(`🔍 Testing endpoint: ${url}\n`);
    
    // Note: In production, you'd need a valid JWT token
    // For testing, we'll try without auth first to see the error
    const response = await axios.get(url, {
      headers: {
        'Authorization': 'Bearer test-token' // Replace with actual token if needed
      }
    });
    
    console.log('✅ Response Status:', response.status);
    console.log('✅ Response Data:');
    console.log(JSON.stringify(response.data, null, 2));
    
  } catch (error) {
    if (error.response) {
      console.log('❌ Error Status:', error.response.status);
      console.log('❌ Error Data:', error.response.data);
    } else {
      console.error('❌ Error:', error.message);
    }
  }
}

testActiveTrip();
