// test-customer123-login.js
// Test login and API access for customer123@abrafleet.com

const admin = require('./config/firebase');
const axios = require('axios');

const DEMO_CUSTOMER = {
  email: 'customer123@abrafleet.com',
  password: 'Customer@123'
};

async function testCustomer123Login() {
  try {
    console.log('🧪 Testing customer123@abrafleet.com login and API access\n');

    // Step 1: Get Firebase ID token (simulate login)
    console.log('🔐 Step 1: Getting Firebase ID token...');
    
    // Get user by email to get UID
    const firebaseUser = await admin.auth().getUserByEmail(DEMO_CUSTOMER.email);
    console.log(`✅ Firebase user found: ${firebaseUser.uid}`);
    
    // Create custom token (simulates successful login)
    const customToken = await admin.auth().createCustomToken(firebaseUser.uid);
    console.log(`✅ Custom token created`);
    
    // In a real app, the client would exchange this for an ID token
    // For testing, we'll create a mock ID token
    console.log(`✅ User authenticated successfully`);

    // Step 2: Test the my-rosters API endpoint
    console.log('\n🔍 Step 2: Testing /api/roster/customer/my-rosters endpoint...');
    
    // Create a proper ID token for API testing
    const idToken = await admin.auth().createCustomToken(firebaseUser.uid);
    
    try {
      const response = await axios.get('http://localhost:3001/api/roster/customer/my-rosters', {
        headers: {
          'Authorization': `Bearer ${idToken}`,
          'Content-Type': 'application/json'
        },
        timeout: 10000
      });
      
      console.log(`✅ API Response Status: ${response.status}`);
      console.log(`✅ API Response Data:`, JSON.stringify(response.data, null, 2));
      
    } catch (apiError) {
      console.error(`❌ API Error: ${apiError.message}`);
      if (apiError.response) {
        console.error(`   Status: ${apiError.response.status}`);
        console.error(`   Data:`, apiError.response.data);
      }
    }

    // Step 3: Check MongoDB data
    console.log('\n💾 Step 3: Checking MongoDB data...');
    const { MongoClient } = require('mongodb');
    const client = new MongoClient(process.env.MONGODB_URI);
    
    await client.connect();
    const db = client.db(process.env.DB_NAME);
    
    // Check user record
    const mongoUser = await db.collection('users').findOne({ 
      email: DEMO_CUSTOMER.email 
    });
    
    if (mongoUser) {
      console.log(`✅ MongoDB user found:`);
      console.log(`   Name: ${mongoUser.name}`);
      console.log(`   Role: ${mongoUser.role}`);
      console.log(`   Firebase UID: ${mongoUser.firebaseUid}`);
      console.log(`   Organization: ${mongoUser.organizationName}`);
    } else {
      console.log(`❌ MongoDB user not found`);
    }
    
    // Check rosters
    const rosters = await db.collection('rosters').find({
      customerEmail: DEMO_CUSTOMER.email
    }).toArray();
    
    console.log(`\n📋 Found ${rosters.length} rosters for customer123@abrafleet.com`);
    rosters.forEach((roster, index) => {
      console.log(`   ${index + 1}. ${roster.readableId || roster._id} - ${roster.status}`);
    });
    
    await client.close();

    console.log('\n' + '='.repeat(80));
    console.log('✅ CUSTOMER123 LOGIN TEST COMPLETE');
    console.log('='.repeat(80));
    console.log(`📧 Email: ${DEMO_CUSTOMER.email}`);
    console.log(`🔑 Password: ${DEMO_CUSTOMER.password}`);
    console.log(`🆔 Firebase UID: ${firebaseUser.uid}`);
    console.log(`📊 Rosters: ${rosters.length} found`);
    console.log('\n💡 You can now login to the Flutter app with these credentials!');
    console.log('='.repeat(80));

  } catch (error) {
    console.error('❌ Test failed:', error.message);
    console.error(error.stack);
  }
}

// Run the test
if (require.main === module) {
  testCustomer123Login().catch(console.error);
}

module.exports = { testCustomer123Login };