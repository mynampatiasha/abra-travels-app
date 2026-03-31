// Test script to verify user creation flow
const axios = require('axios');

const BASE_URL = 'http://localhost:3000/api';

// Test data
const testUser = {
  name: 'Test User',
  email: 'testuser@example.com',
  phone: '+1234567890',
  password: 'password123',
  role: 'operations',
  customPermissions: {
    'Fleet Management': {
      'View all vehicles': true,
      'Add vehicles': true,
      'Edit vehicles': false,
      'Delete vehicles': false
    },
    'Driver Management': {
      'View drivers': true,
      'Add drivers': false
    }
  }
};

async function testUserCreation() {
  console.log('\n🧪 TESTING USER CREATION FLOW');
  console.log('═'.repeat(80));
  
  try {
    // Step 1: Create user
    console.log('\n1️⃣  Creating user...');
    console.log('   Data:', JSON.stringify(testUser, null, 2));
    
    const createResponse = await axios.post(`${BASE_URL}/user-roles`, testUser);
    
    console.log('\n✅ USER CREATED SUCCESSFULLY');
    console.log('   ID:', createResponse.data._id);
    console.log('   Name:', createResponse.data.name);
    console.log('   Email:', createResponse.data.email);
    console.log('   Role:', createResponse.data.role);
    console.log('   Custom Permissions:', createResponse.data.customPermissions ? 'Yes' : 'No');
    
    const userId = createResponse.data._id;
    
    // Step 2: Fetch the created user
    console.log('\n2️⃣  Fetching created user...');
    const fetchResponse = await axios.get(`${BASE_URL}/user-roles/${userId}`);
    
    console.log('\n✅ USER FETCHED SUCCESSFULLY');
    console.log('   Name:', fetchResponse.data.name);
    console.log('   Email:', fetchResponse.data.email);
    console.log('   Custom Permissions:', JSON.stringify(fetchResponse.data.customPermissions, null, 2));
    
    // Step 3: Update user
    console.log('\n3️⃣  Updating user...');
    const updateData = {
      ...testUser,
      name: 'Updated Test User',
      customPermissions: {
        'Fleet Management': {
          'View all vehicles': true,
          'Add vehicles': true,
          'Edit vehicles': true,
          'Delete vehicles': true
        }
      }
    };
    
    const updateResponse = await axios.put(`${BASE_URL}/user-roles/${userId}`, updateData);
    
    console.log('\n✅ USER UPDATED SUCCESSFULLY');
    console.log('   Name:', updateResponse.data.name);
    console.log('   Custom Permissions:', JSON.stringify(updateResponse.data.customPermissions, null, 2));
    
    // Step 4: Delete user
    console.log('\n4️⃣  Deleting user...');
    await axios.delete(`${BASE_URL}/user-roles/${userId}`);
    
    console.log('\n✅ USER DELETED SUCCESSFULLY');
    
    console.log('\n═'.repeat(80));
    console.log('✅ ALL TESTS PASSED!');
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

// Run test
testUserCreation();
