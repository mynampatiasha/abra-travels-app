// Test script to verify API configuration
const admin = require('./config/firebase');
const axios = require('axios');

async function testApiConfig() {
  try {
    console.log('🧪 Testing API configuration\n');
    
    // Test localhost endpoint
    console.log('🔍 Testing localhost endpoint...');
    const response = await axios.get('http://localhost:3000/health');
    console.log('✅ Localhost endpoint working:', response.status);
    console.log('   Response:', response.data);
    
    // Test active trip endpoint
    console.log('\n🔍 Testing active trip endpoint...');
    const customToken = await admin.auth().createCustomToken('b5aoloVR7xYI6SICibCIWecBaf82');
    
    const tokenResponse = await axios.post(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=AIzaSyBQ5F_6J_8VDMbf7b4U_wIk_Z0HdYDRaDo`,
      {
        token: customToken,
        returnSecureToken: true
      }
    );
    
    const idToken = tokenResponse.data.idToken;
    
    const activeTripResponse = await axios.get(
      'http://localhost:3000/api/rosters/active-trip/b5aoloVR7xYI6SICibCIWecBaf82',
      {
        headers: {
          'Authorization': `Bearer ${idToken}`,
          'Content-Type': 'application/json'
        }
      }
    );
    
    console.log('✅ Active trip endpoint working:', activeTripResponse.status);
    console.log('   Response:', JSON.stringify(activeTripResponse.data, null, 2));
    
  } catch (error) {
    console.error('❌ Test failed:');
    if (error.response) {
      console.error('   Status:', error.response.status);
      console.error('   Data:', error.response.data);
    } else {
      console.error('   Error:', error.message);
    }
  }
}

testApiConfig();