const admin = require('firebase-admin');
const axios = require('axios');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

const BACKEND_URL = 'http://localhost:3000';

async function testCustomerStats() {
  try {
    console.log('='.repeat(60));
    console.log('TESTING CUSTOMER123 STATS API');
    console.log('='.repeat(60));

    // Step 1: Get Firebase token for customer123@abrafleet.com
    console.log('\n1. Getting Firebase token for customer123@abrafleet.com...');
    const userRecord = await admin.auth().getUserByEmail('customer123@abrafleet.com');
    const customToken = await admin.auth().createCustomToken(userRecord.uid);
    
    // Exchange custom token for ID token
    const tokenResponse = await axios.post(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${process.env.FIREBASE_API_KEY || 'AIzaSyBkCxGFpII8vQon9ygKxL-Zt8vQon9ygKxL'}`,
      {
        token: customToken,
        returnSecureToken: true
      }
    );
    
    const idToken = tokenResponse.data.idToken;
    console.log('✓ Firebase token obtained');
    console.log('User UID:', userRecord.uid);

    // Step 2: Test the stats API endpoint
    console.log('\n2. Testing /api/customer/stats/dashboard endpoint...');
    
    const statsResponse = await axios.get(
      `${BACKEND_URL}/api/customer/stats/dashboard`,
      {
        headers: {
          'Authorization': `Bearer ${idToken}`,
          'Content-Type': 'application/json'
        }
      }
    );

    console.log('\n' + '='.repeat(60));
    console.log('STATS API RESPONSE:');
    console.log('='.repeat(60));
    console.log(JSON.stringify(statsResponse.data, null, 2));

    // Step 3: Analyze the response
    console.log('\n' + '='.repeat(60));
    console.log('STATS ANALYSIS:');
    console.log('='.repeat(60));
    
    const data = statsResponse.data.data || statsResponse.data;
    
    if (data.totalTrips) {
      console.log('\n✓ Total Trips:');
      console.log(`  - Completed: ${data.totalTrips.completed}`);
      console.log(`  - Ongoing: ${data.totalTrips.ongoing}`);
      console.log(`  - Cancelled: ${data.totalTrips.cancelled}`);
      console.log(`  - Total: ${data.totalTrips.total}`);
    } else {
      console.log('\n✗ No totalTrips data found');
    }

    if (data.onTimeDelivery) {
      console.log('\n✓ On-Time Delivery:');
      console.log(`  - On Time: ${data.onTimeDelivery.onTime}`);
      console.log(`  - Delayed: ${data.onTimeDelivery.delayed}`);
    } else {
      console.log('\n✗ No onTimeDelivery data found');
    }

    if (data.totalDistance !== undefined) {
      console.log('\n✓ Total Distance:', data.totalDistance, 'km');
    } else {
      console.log('\n✗ No totalDistance data found');
    }

    if (data.monthlyDistance && data.monthlyDistance.length > 0) {
      console.log('\n✓ Monthly Distance Data:', data.monthlyDistance.length, 'months');
    } else {
      console.log('\n✗ No monthlyDistance data found');
    }

    if (data.weeklyBookings && data.weeklyBookings.length > 0) {
      console.log('\n✓ Weekly Bookings Data:', data.weeklyBookings.length, 'weeks');
    } else {
      console.log('\n✗ No weeklyBookings data found');
    }

    if (data.topRoutes && data.topRoutes.length > 0) {
      console.log('\n✓ Top Routes:');
      data.topRoutes.forEach((route, index) => {
        console.log(`  ${index + 1}. ${route.route} (${route.count} trips)`);
      });
    } else {
      console.log('\n✗ No topRoutes data found');
    }

    console.log('\n' + '='.repeat(60));
    console.log('TEST COMPLETED SUCCESSFULLY');
    console.log('='.repeat(60));

  } catch (error) {
    console.error('\n' + '='.repeat(60));
    console.error('ERROR TESTING CUSTOMER STATS:');
    console.error('='.repeat(60));
    
    if (error.response) {
      console.error('Status:', error.response.status);
      console.error('Data:', JSON.stringify(error.response.data, null, 2));
    } else {
      console.error(error.message);
      console.error(error.stack);
    }
  } finally {
    process.exit(0);
  }
}

testCustomerStats();
