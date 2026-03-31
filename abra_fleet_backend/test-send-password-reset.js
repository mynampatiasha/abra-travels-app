// Test script for send password reset email endpoint
const axios = require('axios');

const BASE_URL = 'http://localhost:3000';

async function testSendPasswordReset() {
  console.log('\n🧪 ========== TESTING SEND PASSWORD RESET EMAIL ==========\n');
  
  try {
    // Test with driver ID EMP002
    const driverId = 'EMP002';
    
    console.log(`📧 Sending password reset email to driver: ${driverId}`);
    
    const response = await axios.post(
      `${BASE_URL}/api/admin/drivers/${driverId}/send-password-reset`,
      {},
      {
        headers: {
          'Content-Type': 'application/json',
          // Add your auth token here if needed
          // 'Authorization': 'Bearer YOUR_TOKEN'
        }
      }
    );
    
    console.log('\n✅ SUCCESS!');
    console.log('Response:', JSON.stringify(response.data, null, 2));
    
  } catch (error) {
    console.error('\n❌ ERROR!');
    if (error.response) {
      console.error('Status:', error.response.status);
      console.error('Response:', JSON.stringify(error.response.data, null, 2));
    } else {
      console.error('Error:', error.message);
    }
  }
  
  console.log('\n========== TEST COMPLETE ==========\n');
}

// Run the test
testSendPasswordReset();
