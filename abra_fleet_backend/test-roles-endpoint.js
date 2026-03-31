// Test script to verify roles endpoint
const axios = require('axios');

const BASE_URL = 'http://localhost:3000/api';

async function testRolesEndpoint() {
  console.log('\n🧪 TESTING ROLES ENDPOINT');
  console.log('═'.repeat(80));
  
  try {
    console.log('\n1️⃣  Fetching roles (no auth)...');
    const response = await axios.get(`${BASE_URL}/roles`);
    
    console.log('\n✅ ROLES FETCHED SUCCESSFULLY');
    console.log('   Status:', response.status);
    console.log('   Count:', response.data.length);
    console.log('\n📋 Roles:');
    response.data.forEach(role => {
      console.log(`   ${role.icon} ${role.title} (${role.id})`);
      console.log(`      Color: ${role.color}`);
      console.log(`      Permissions: ${Object.keys(role.permissions).length} modules`);
    });
    
    console.log('\n═'.repeat(80));
    console.log('✅ TEST PASSED!');
    console.log('═'.repeat(80) + '\n');
    
  } catch (error) {
    console.error('\n❌ TEST FAILED!');
    console.error('═'.repeat(80));
    
    if (error.response) {
      console.error('Status:', error.response.status);
      console.error('Error:', JSON.stringify(error.response.data, null, 2));
    } else {
      console.error('Error:', error.message);
    }
    
    console.error('═'.repeat(80) + '\n');
    process.exit(1);
  }
}

testRolesEndpoint();
