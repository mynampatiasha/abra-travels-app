require('dotenv').config();
const axios = require('axios');

async function testPendingRostersTestMode() {
    console.log('🧪 TESTING PENDING ROSTERS API WITH TEST MODE');
    console.log('==================================================');
    
    try {
        // Test the API endpoint with test mode headers
        console.log('🔍 Testing GET /api/roster/admin/pending with test mode...');
        
        const response = await axios.get('http://localhost:3001/api/roster/admin/pending', {
            timeout: 10000,
            headers: {
                'Content-Type': 'application/json',
                'x-test-firebase-uid': 'admin-test-user'
            }
        });
        
        console.log('✅ API Response Status:', response.status);
        console.log('📊 Response Data Keys:', Object.keys(response.data));
        
        if (response.data.data) {
            console.log('📋 Number of pending rosters:', response.data.data.length);
            console.log('📊 Total count:', response.data.totalCount);
            
            // Show first roster details
            if (response.data.data.length > 0) {
                const firstRoster = response.data.data[0];
                console.log('📋 First roster sample:');
                console.log('  - ID:', firstRoster._id);
                console.log('  - Status:', firstRoster.status);
                console.log('  - Organization:', firstRoster.organization || 'N/A');
                console.log('  - Created:', firstRoster.createdAt);
            }
        }
        
    } catch (error) {
        console.error('❌ API Test Failed:');
        
        if (error.response) {
            console.error('Status:', error.response.status);
            console.error('Status Text:', error.response.statusText);
            console.error('Response Data:', JSON.stringify(error.response.data, null, 2));
        } else if (error.request) {
            console.error('No response received');
        } else {
            console.error('Error:', error.message);
        }
    }
}

testPendingRostersTestMode();