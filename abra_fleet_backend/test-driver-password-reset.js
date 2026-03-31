// Test script to send password reset email to a driver
const axios = require('axios');

const BASE_URL = 'http://localhost:3000';

async function testDriverPasswordReset() {
  try {
    console.log('\n🧪 ========== TESTING DRIVER PASSWORD RESET EMAIL ==========\n');
    
    // Test with driver EMP015 (has email: ashamyuampat24@gmail.com)
    const driverId = 'EMP015';
    
    console.log(`📧 Sending password reset email to driver: ${driverId}`);
    console.log(`🔗 Endpoint: POST ${BASE_URL}/api/admin/drivers/${driverId}/send-password-reset`);
    console.log('');
    
    const response = await axios.post(
      `${BASE_URL}/api/admin/drivers/${driverId}/send-password-reset`,
      {},
      {
        headers: {
          'Content-Type': 'application/json'
        }
      }
    );
    
    console.log('✅ SUCCESS!');
    console.log('📊 Response Status:', response.status);
    console.log('📦 Response Data:', JSON.stringify(response.data, null, 2));
    console.log('');
    console.log('✉️  Check the driver\'s email inbox: ashamyuampat24@gmail.com');
    console.log('📬 Also check spam/junk folder');
    console.log('');
    
  } catch (error) {
    console.error('\n❌ ERROR!');
    console.error('Status:', error.response?.status);
    console.error('Error Message:', error.response?.data?.message || error.message);
    console.error('Error Details:', JSON.stringify(error.response?.data, null, 2));
    console.error('');
  }
  
  console.log('========== TEST COMPLETE ==========\n');
}

// Run the test
testDriverPasswordReset();
