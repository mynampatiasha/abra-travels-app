// Test admin profile endpoint
require('dotenv').config();
const admin = require('./config/firebase');

async function testAdminProfile() {
  try {
    console.log('\n🧪 Testing admin profile endpoint...');
    console.log('─'.repeat(80));
    
    // Create a custom token for admin@abrafleet.com
    const customToken = await admin.auth().createCustomToken('qnwp8d0clDSSNuSm3ugmXYLSI3K2', {
      email: 'admin@abrafleet.com'
    });
    
    console.log('✅ Custom token created');
    
    // Test the profile endpoint
    const fetch = (await import('node-fetch')).default;
    
    // First, we need to exchange the custom token for an ID token
    // This would normally be done by the client, but for testing we'll simulate it
    console.log('📋 Testing profile endpoint with admin credentials...');
    
    const response = await fetch('http://localhost:3000/api/auth/profile', {
      method: 'GET',
      headers: {
        'Authorization': `Bearer ${customToken}`,
        'Content-Type': 'application/json'
      }
    });
    
    const result = await response.json();
    
    console.log('📋 Profile endpoint response:');
    console.log('   Status:', response.status);
    console.log('   Success:', result.success);
    
    if (result.success && result.user) {
      console.log('   User Email:', result.user.email);
      console.log('   User Role:', result.user.role);
      console.log('   User Name:', result.user.name);
      console.log('   Modules:', result.user.modules);
    } else {
      console.log('   Error:', result.error);
      console.log('   Message:', result.message);
    }
    
    console.log('\n─'.repeat(80) + '\n');
    
    process.exit(0);
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

testAdminProfile();