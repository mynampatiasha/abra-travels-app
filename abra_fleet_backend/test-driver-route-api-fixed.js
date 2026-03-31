const { MongoClient } = require('mongodb');
const admin = require('firebase-admin');
const axios = require('axios');
require('dotenv').config();

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
  });
}

const MONGODB_URI = process.env.MONGODB_URI;
const API_URL = 'http://localhost:3000';

async function testDriverRouteAPI() {
  const driverEmail = 'drivertest@gmail.com';
  
  console.log('\n🧪 Testing Driver Route API (Fixed Version)');
  console.log('='.repeat(60));
  
  try {
    // Get Firebase user and token
    const firebaseUser = await admin.auth().getUserByEmail(driverEmail);
    const token = await admin.auth().createCustomToken(firebaseUser.uid);
    
    // Sign in to get ID token
    const signInResponse = await axios.post(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${process.env.FIREBASE_API_KEY}`,
      {
        token: token,
        returnSecureToken: true
      }
    );
    
    const idToken = signInResponse.data.idToken;
    console.log('✅ Got Firebase ID token');
    
    // Call the driver route API
    console.log('\n📡 Calling /api/driver/route/today...');
    const response = await axios.get(
      `${API_URL}/api/driver/route/today`,
      {
        headers: {
          'Authorization': `Bearer ${idToken}`
        }
      }
    );
    
    console.log('\n📊 API Response:');
    console.log(JSON.stringify(response.data, null, 2));
    
    if (response.data.status === 'success' && response.data.data.hasRoute) {
      const data = response.data.data;
      console.log('\n✅ SUCCESS! Route data received:');
      console.log(`   Vehicle: ${data.vehicle?.registrationNumber || 'N/A'}`);
      console.log(`   Total Customers: ${data.routeSummary?.totalCustomers || 0}`);
      console.log(`   Customers:`);
      data.customers?.forEach((customer, index) => {
        console.log(`      ${index + 1}. ${customer.name} - ${customer.phone}`);
        console.log(`         Pickup: ${customer.pickupLocation}`);
        console.log(`         Drop: ${customer.dropLocation}`);
        console.log(`         Time: ${customer.scheduledTime || 'N/A'}`);
      });
    } else {
      console.log('\n⚠️  No route found or API returned error');
    }
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    if (error.response) {
      console.error('Response data:', error.response.data);
    }
  }
}

testDriverRouteAPI();
