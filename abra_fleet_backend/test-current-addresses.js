const axios = require('axios');

const BASE_URL = 'http://localhost:3000';

// Replace with a valid customer Firebase token
const CUSTOMER_TOKEN = 'YOUR_CUSTOMER_TOKEN_HERE';

async function testCurrentAddresses() {
  try {
    console.log('🧪 Testing Get Current Addresses Endpoint...\n');
    
    const response = await axios.get(
      `${BASE_URL}/api/address-change/customer/current-addresses`,
      {
        headers: {
          'Authorization': `Bearer ${CUSTOMER_TOKEN}`,
          'Content-Type': 'application/json'
        }
      }
    );
    
    console.log('✅ Success!');
    console.log('Response:', JSON.stringify(response.data, null, 2));
    
  } catch (error) {
    console.error('❌ Error:', error.response?.data || error.message);
  }
}

testCurrentAddresses();
