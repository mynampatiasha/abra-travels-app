// Test script to verify monthly distance data for customer123@abrafleet.com
const admin = require('firebase-admin');
const axios = require('axios');

async function testCustomer123MonthlyDistance() {
  try {
    console.log('🧪 Testing monthly distance data for customer123@abrafleet.com\n');
    
    // Get Firebase token for customer123@abrafleet.com
    const customToken = await admin.auth().createCustomToken('b5aoloVR7xYI6SICibCIWecBaf82');
    const idTokenResponse = await axios.post(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${process.env.FIREBASE_API_KEY}`,
      {
        token: customToken,
        returnSecureToken: true
      }
    );
    
    const idToken = idTokenResponse.data.idToken;
    console.log('✅ Firebase token obtained');
    console.log('   Token preview:', idToken.substring(0, 50) + '...');
    
    // Test the dashboard API endpoint
    console.log('\n🔍 Testing /api/customer/stats/dashboard');
    const response = await axios.get('http://localhost:3001/api/customer/stats/dashboard', {
      headers: {
        'Authorization': `Bearer ${idToken}`,
        'Content-Type': 'application/json'
      }
    });
    
    if (response.data.success) {
      const data = response.data.data;
      
      console.log('\n📊 MONTHLY DISTANCE DATA:');
      console.log('   Total Distance:', data.totalDistance, 'km');
      
      if (data.monthlyDistance && data.monthlyDistance.length > 0) {
        console.log('   Monthly Breakdown:');
        data.monthlyDistance.forEach((month, index) => {
          console.log(`   ${index + 1}. ${month.month}: ${month.distance} km`);
        });
        
        // Calculate total from monthly data
        const monthlyTotal = data.monthlyDistance.reduce((sum, month) => sum + month.distance, 0);
        console.log(`   Monthly Total: ${monthlyTotal} km`);
        
        // Verify data consistency
        if (Math.abs(data.totalDistance - monthlyTotal) < 0.1) {
          console.log('   ✅ Data consistency: PASS');
        } else {
          console.log('   ⚠️ Data consistency: Monthly total doesn\'t match overall total');
        }
      } else {
        console.log('   ❌ No monthly distance data found');
      }
      
      console.log('\n📋 FULL RESPONSE DATA:');
      console.log('   Total Trips:', JSON.stringify(data.totalTrips, null, 2));
      console.log('   Recent Trip:', JSON.stringify(data.recentTrip, null, 2));
      console.log('   Last Updated:', data.lastUpdated);
      
    } else {
      console.log('❌ API call failed:', response.data.message);
    }
    
  } catch (error) {
    console.error('❌ Error testing monthly distance data:');
    if (error.response) {
      console.error('   Status:', error.response.status);
      console.error('   Data:', error.response.data);
    } else {
      console.error('   Error:', error.message);
    }
  }
}

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    }),
  });
}

testCustomer123MonthlyDistance();