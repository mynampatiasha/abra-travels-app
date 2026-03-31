require('dotenv').config();
const axios = require('axios');

async function testPendingRostersAPI() {
    console.log('🧪 TESTING PENDING ROSTERS API ENDPOINT');
    console.log('==================================================');
    
    try {
        // Test the actual API endpoint
        console.log('🔍 Testing GET /api/roster/admin/pending');
        
        const response = await axios.get('http://localhost:3001/api/roster/admin/pending', {
            timeout: 10000,
            headers: {
                'Content-Type': 'application/json'
            }
        });
        
        console.log('✅ API Response Status:', response.status);
        console.log('📊 Response Data:', JSON.stringify(response.data, null, 2));
        
    } catch (error) {
        console.error('❌ API Test Failed:');
        
        if (error.response) {
            // Server responded with error status
            console.error('Status:', error.response.status);
            console.error('Status Text:', error.response.statusText);
            console.error('Response Data:', error.response.data);
            console.error('Response Headers:', error.response.headers);
        } else if (error.request) {
            // Request was made but no response received
            console.error('No response received:', error.request);
        } else {
            // Something else happened
            console.error('Error:', error.message);
        }
        
        console.error('Full error:', error);
    }
}

testPendingRostersAPI();