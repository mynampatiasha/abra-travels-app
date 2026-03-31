// Test script for forgot password functionality
const axios = require('axios');

const BASE_URL = 'http://localhost:3000';

async function testForgotPassword() {
  console.log('\n🧪 ========== TESTING FORGOT PASSWORD ==========\n');

  try {
    // Test with a valid email (replace with an actual email from your system)
    const testEmail = 'ashamyuampat24@gmail.com'; // Replace with your test email
    
    console.log(`📧 Sending password reset request for: ${testEmail}`);
    console.log(`🔗 Endpoint: POST ${BASE_URL}/api/auth/forgot-password`);
    console.log('');

    const response = await axios.post(
      `${BASE_URL}/api/auth/forgot-password`,
      { email: testEmail },
      {
        headers: {
          'Content-Type': 'application/json'
        }
      }
    );

    console.log('✅ SUCCESS!');
    console.log('Response:', response.data);
    console.log('');
    console.log('📧 Check your email inbox for the password reset link!');
    console.log('');

  } catch (error) {
    console.log('❌ FAILED!');
    if (error.response) {
      console.log('Status:', error.response.status);
      console.log('Response:', error.response.data);
    } else {
      console.log('Error:', error.message);
    }
  }

  console.log('\n========== TEST COMPLETE ==========\n');
}

// Run the test
testForgotPassword();
