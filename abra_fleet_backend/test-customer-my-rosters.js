const admin = require('./config/firebase');
const axios = require('axios');

async function testCustomerMyRosters() {
  try {
    console.log('🧪 Testing customer my-rosters endpoint\n');
    
    // Get Firebase token for customer123@abrafleet.com
    const customToken = await admin.auth().createCustomToken('b5aoloVR7xYI6SICibCIWecBaf82');
    console.log('✅ Custom token created for customer');
    
    // Exchange custom token for ID token (simulate what the app does)
    const tokenResponse = await axios.post(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=AIzaSyBQ5F_6J_8VDMbf7b4U_wIk_Z0HdYDRaDo`,
      {
        token: customToken,
        returnSecureToken: true
      }
    );
    
    const idToken = tokenResponse.data.idToken;
    console.log('✅ ID token obtained');
    console.log('   Token preview:', idToken.substring(0, 50) + '...');
    
    // Test the my-rosters endpoint
    console.log('\n🔍 Testing /api/roster/customer/my-rosters');
    const response = await axios.get('http://localhost:3001/api/roster/customer/my-rosters', {
      headers: {
        'Authorization': `Bearer ${idToken}`,
        'Content-Type': 'application/json'
      }
    });
    
    console.log('✅ Request successful!');
    console.log('   Status:', response.status);
    console.log('   Data:', JSON.stringify(response.data, null, 2));
    
  } catch (error) {
    console.error('❌ Test failed:');
    if (error.response) {
      console.error('   Status:', error.response.status);
      console.error('   Data:', error.response.data);
      console.error('   Headers:', error.response.headers);
    } else {
      console.error('   Error:', error.message);
    }
  }
}

testCustomerMyRosters();