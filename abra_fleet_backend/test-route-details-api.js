// Test the driver route details API
const axios = require('axios');
const admin = require('firebase-admin');
require('dotenv').config();

const BASE_URL = 'http://localhost:3000';
const DRIVER_UID = 'asha_driver_uid';

async function testRouteDetailsAPI() {
  try {
    console.log('🔐 Getting authentication token...');
    
    // Create custom token
    const customToken = await admin.auth().createCustomToken(DRIVER_UID);
    
    // Sign in with custom token to get ID token
    const signInResponse = await axios.post(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${process.env.FIREBASE_API_KEY || 'AIzaSyDummyKey'}`,
      {
        token: customToken,
        returnSecureToken: true
      }
    );
    
    const idToken = signInResponse.data.idToken;
    console.log('✅ Token obtained\n');
    
    // Test GET /api/driver/route/today
    console.log('📋 Testing Today\'s Route API');
    console.log('   GET /api/driver/route/today');
    
    const response = await axios.get(`${BASE_URL}/api/driver/route/today`, {
      headers: {
        'Authorization': `Bearer ${idToken}`
      }
    });
    
    console.log('   ✅ Success!');
    console.log('\n📊 Response:');
    console.log(JSON.stringify(response.data, null, 2));
    
    if (response.data.data && response.data.data.hasRoute) {
      const route = response.data.data;
      console.log('\n📝 Summary:');
      console.log(`   Vehicle: ${route.vehicle?.registrationNumber}`);
      console.log(`   Total Customers: ${route.routeSummary?.totalCustomers}`);
      console.log(`   Total Distance: ${route.routeSummary?.totalDistance} KM`);
      console.log(`   Customers:`);
      route.customers?.forEach((customer, index) => {
        console.log(`     ${index + 1}. ${customer.name} - ${customer.scheduledTime}`);
        console.log(`        Pickup: ${customer.pickupLocation}`);
        console.log(`        Drop: ${customer.dropLocation}`);
      });
    }
    
  } catch (error) {
    console.error('❌ Error:', error.response?.data || error.message);
  }
}

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: `firebase-adminsdk@${process.env.FIREBASE_PROJECT_ID}.iam.gserviceaccount.com`,
      privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n')
    })
  });
}

testRouteDetailsAPI();
