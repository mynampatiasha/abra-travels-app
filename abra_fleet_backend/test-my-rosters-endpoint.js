require('dotenv').config();
const admin = require('firebase-admin');
const axios = require('axios');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n')
    })
  });
}

async function testMyRostersEndpoint() {
  try {
    console.log('🧪 Testing /api/roster/customer/my-rosters endpoint\n');
    
    // Get Firebase token for Priya Sharma
    const uid = 'VSCJkbM0AEhupcIMsCXJr3oFeYo1';
    const token = await admin.auth().createCustomToken(uid);
    const idToken = await admin.auth().verifyIdToken(token);
    
    console.log('✅ Firebase UID:', uid);
    console.log('✅ Token created\n');
    
    // Call the endpoint
    const response = await axios.get('http://localhost:3000/api/roster/customer/my-rosters', {
      headers: {
        'Authorization': `Bearer ${token}`
      }
    });
    
    console.log('📊 Response Status:', response.status);
    console.log('📊 Response Data:', JSON.stringify(response.data, null, 2));
    console.log('\n✅ Test completed successfully!');
    
    if (response.data.count > 0) {
      console.log(`\n🎉 SUCCESS! Found ${response.data.count} roster(s) for Priya Sharma`);
    } else {
      console.log('\n⚠️ No rosters found - this might be an issue');
    }
    
  } catch (error) {
    console.error('❌ Test failed:', error.response?.data || error.message);
  }
  
  process.exit(0);
}

testMyRostersEndpoint();
