require('dotenv').config();
const axios = require('axios');
const admin = require('firebase-admin');

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.FIREBASE_PROJECT_ID
  });
}

async function testPendingRostersWithAuth() {
    console.log('🧪 TESTING PENDING ROSTERS API WITH AUTHENTICATION');
    console.log('==================================================');
    
    try {
        // Create a custom token for testing (admin user)
        console.log('🔑 Creating admin test token...');
        
        const customToken = await admin.auth().createCustomToken('admin-test-user', {
            role: 'admin',
            email: 'admin@abrafleet.com'
        });
        
        console.log('✅ Custom token created');
        
        // Test the API endpoint with authentication
        console.log('🔍 Testing GET /api/roster/admin/pending with auth...');
        
        const response = await axios.get('http://localhost:3001/api/roster/admin/pending', {
            timeout: 10000,
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${customToken}`
            }
        });
        
        console.log('✅ API Response Status:', response.status);
        console.log('📊 Response Data Keys:', Object.keys(response.data));
        
        if (response.data.data) {
            console.log('📋 Number of pending rosters:', response.data.data.length);
            console.log('📊 Total count:', response.data.totalCount);
        }
        
    } catch (error) {
        console.error('❌ API Test Failed:');
        
        if (error.response) {
            console.error('Status:', error.response.status);
            console.error('Status Text:', error.response.statusText);
            console.error('Response Data:', error.response.data);
        } else if (error.request) {
            console.error('No response received:', error.request);
        } else {
            console.error('Error:', error.message);
        }
    }
}

testPendingRostersWithAuth();