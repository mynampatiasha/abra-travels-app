// Test the trip cancellation endpoint with a real admin token
const axios = require('axios');
const admin = require('./config/firebase');
require('dotenv').config();

const API_URL = process.env.API_URL || 'http://localhost:3000';

async function testWithAdminToken() {
  console.log('🧪 Testing Trip Cancellation Endpoint with Admin Token\n');
  
  try {
    // Get an admin user to create a token
    const users = await admin.auth().listUsers(10);
    const adminUser = users.users.find(u => u.email && u.email.includes('admin'));
    
    if (!adminUser) {
      console.log('❌ No admin user found. Please create an admin user first.');
      return;
    }
    
    console.log(`✅ Found admin user: ${adminUser.email}`);
    
    // Create a custom token
    const customToken = await admin.auth().createCustomToken(adminUser.uid);
    console.log('✅ Created custom token');
    
    // Exchange for ID token (this would normally be done by the client)
    // For testing, we'll use the UID directly
    console.log(`\n📡 Testing endpoint: GET ${API_URL}/api/roster/admin/approved-leave-requests`);
    console.log(`👤 User: ${adminUser.email} (${adminUser.uid})\n`);
    
    // Create a test token (in production, this comes from Firebase Auth)
    const testToken = await admin.auth().createCustomToken(adminUser.uid);
    
    // Make the request
    const response = await axios.get(
      `${API_URL}/api/roster/admin/approved-leave-requests`,
      {
        headers: {
          'Authorization': `Bearer ${testToken}`
        },
        validateStatus: () => true
      }
    );
    
    console.log('📊 Response Status:', response.status);
    console.log('📊 Response Data:', JSON.stringify(response.data, null, 2));
    
    if (response.status === 200) {
      console.log('\n✅ SUCCESS! Endpoint is working correctly');
      console.log(`📋 Found ${response.data.count || 0} approved leave requests`);
      
      if (response.data.data && response.data.data.length > 0) {
        console.log('\n📝 Sample Leave Request:');
        const sample = response.data.data[0];
        console.log(`   - Customer: ${sample.customerName}`);
        console.log(`   - Leave Period: ${sample.startDate} to ${sample.endDate}`);
        console.log(`   - Affected Trips: ${sample.affectedTripsCount}`);
      }
    } else if (response.status === 401) {
      console.log('\n⚠️  Authentication issue - but endpoint exists');
      console.log('💡 This might be a token format issue');
    } else {
      console.log('\n❌ Unexpected response');
    }
    
  } catch (error) {
    if (error.code === 'ECONNREFUSED') {
      console.log('❌ Backend server is not running!');
      console.log('💡 Start it with: node abra_fleet_backend/index.js');
    } else {
      console.log('❌ Error:', error.message);
      if (error.response) {
        console.log('Response:', error.response.data);
      }
    }
  }
}

testWithAdminToken();
