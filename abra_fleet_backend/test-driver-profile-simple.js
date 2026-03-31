const axios = require('axios');

async function testDriverProfileAPI() {
    try {
        console.log('🔍 Testing Driver Profile API...');
        
        // Test without authentication first to see if route exists
        const response = await axios.get('http://localhost:3001/api/drivers/profile');
        
        console.log('✅ API Response:', response.status);
        console.log('📋 Response Data:', JSON.stringify(response.data, null, 2));
        
    } catch (error) {
        console.log('📊 API Response Status:', error.response?.status);
        console.log('📋 Response Data:', JSON.stringify(error.response?.data, null, 2));
        
        if (error.response?.status === 401) {
            console.log('✅ Route exists but requires authentication (expected)');
        } else {
            console.error('❌ Unexpected error:', error.message);
        }
    }
}

testDriverProfileAPI();