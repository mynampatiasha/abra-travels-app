const admin = require('firebase-admin');
const axios = require('axios');

async function testDriverProfileAPI() {
    try {
        console.log('🔍 Testing Driver Profile API...');
        
        // Create a custom token for the driver
        const driverUid = 'aVIF9Ahluig993fCNyZRrIDC3KO2'; // Rajesh Kumar's UID
        const customToken = await admin.auth().createCustomToken(driverUid, {
            role: 'driver',
            email: 'rajesh.kumar@abrafleet.com'
        });
        
        console.log('✅ Custom token created');
        
        // Test the API endpoint
        const response = await axios.get('http://localhost:3001/api/drivers/profile', {
            headers: {
                'Authorization': `Bearer ${customToken}`,
                'Content-Type': 'application/json'
            }
        });
        
        console.log('✅ API Response:', response.status);
        console.log('📋 Profile Data:', JSON.stringify(response.data, null, 2));
        
    } catch (error) {
        console.error('❌ Error testing API:', error.response?.data || error.message);
    }
}

// Initialize Firebase Admin if not already done
if (!admin.apps.length) {
    admin.initializeApp({
        credential: admin.credential.applicationDefault(),
        projectId: 'abrafleet-cec94'
    });
}

testDriverProfileAPI();