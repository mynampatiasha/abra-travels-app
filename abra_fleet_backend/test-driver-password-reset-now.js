// Test driver password reset endpoint
const axios = require('axios');

async function testPasswordReset() {
  const BASE_URL = 'http://localhost:3001';
  const driverId = 'DRV-234567'; // The driver ID from your error
  
  console.log('🧪 Testing Driver Password Reset');
  console.log('='.repeat(50));
  console.log('Driver ID:', driverId);
  console.log('Endpoint:', `${BASE_URL}/api/admin/drivers/${driverId}/send-password-reset`);
  
  try {
    const response = await axios.post(
      `${BASE_URL}/api/admin/drivers/${driverId}/send-password-reset`,
      {},
      {
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer eyJhbGciOiJSUzI1NiIsImtpZCI6Ijk4OGQ1YTM3OWI3OGJkZjFlNTBhNDA5MTEzZjJiMGM3NWU0NTJlNDciLCJ0eXAiOiJKV1QifQ.eyJyb2xlIjoiYWRtaW4iLCJpc3MiOiJodHRwczovL3NlY3VyZXRva2VuLmdvb2dsZS5jb20vYWJyYWZsZWV0LWNlYzk0IiwiYXVkIjoiYWJyYWZsZWV0LWNlYzk0IiwiYXV0aF90aW1lIjoxNzY2Mzk0MDQ1LCJ1c2VyX2lkIjoicW53cDhkMGNsRFNTTnVTbTN1Z21YWUxTSTNLMiIsInN1YiI6InFud3A4ZDBjbERTU051U20zdWdtWFlMU0kzSzIiLCJpYXQiOjE3NjY0MDMxNzMsImV4cCI6MTc2NjQwNjc3MywiZW1haWwiOiJhZG1pbkBhYnJhZmxlZXQuY29tIiwiZW1haWxfdmVyaWZpZWQiOmZhbHNlLCJmaXJlYmFzZSI6eyJpZGVudGl0aWVzIjp7ImVtYWlsIjpbImFkbWluQGFicmFmbGVldC5jb20iXX0sInNpZ25faW5fcHJvdmlkZXIiOiJwYXNzd29yZCJ9fQ.TzMvWnEOmKwr0grYYIPLGy0I5iEifXsFPyF7RbwzwNe10dkhfgku3VQZPf6WQLU5jMOKHmOBqOTZCYNo9Fm8aEaxLzub8yzYRMsWxEWPYrQ0jNBrwbUamsy-Mx2jumkqRb9TOTB-ENYUuA1SxsxyXv88FZsBFEdZwuVmgReSfk599M97qf5bezWXN0-RKhS8wQRedWDimFWtGC7xYFNK6dvnyG9vJCBYWHX8dwSJ6vCwkBaU2A25Or02zVP_MNOWG78Kf4MTYLxUY9UD6ShHwmxsrCVxSKExxBKOd5fC_BfmaYU1a3kcF1xnifQdAYFGvjVIN3oUnwCp4CmJ3maAsg'
        }
      }
    );
    
    console.log('✅ Success!');
    console.log('Status:', response.status);
    console.log('Response:', response.data);
    
  } catch (error) {
    console.log('❌ Error occurred:');
    console.log('Status:', error.response?.status);
    console.log('Status Text:', error.response?.statusText);
    console.log('Response Data:', error.response?.data);
    console.log('Error Message:', error.message);
    
    if (error.response?.data) {
      console.log('\nDetailed Error:');
      console.log(JSON.stringify(error.response.data, null, 2));
    }
  }
}

testPasswordReset();