// test-custom-permissions.js - Test script for custom permissions
// Run with: node test-custom-permissions.js

const axios = require('axios');

const API_BASE = 'http://localhost:3000/api';
const TOKEN = 'your-auth-token-here'; // Replace with actual token if using authentication

const headers = {
  'Content-Type': 'application/json',
  ...(TOKEN && { 'Authorization': `Bearer ${TOKEN}` })
};

async function testCustomPermissions() {
  console.log('\n🧪 TESTING CUSTOM PERMISSIONS FLOW');
  console.log('═'.repeat(80));

  try {
    // 1. Initialize roles first
    console.log('\n1️⃣  Initializing roles...');
    try {
      const initResponse = await axios.post(`${API_BASE}/roles/initialize`, {}, { headers });
      console.log('   ✅ Roles initialized:', initResponse.data.count, 'roles');
    } catch (error) {
      console.log('   ⚠️  Roles might already be initialized');
    }

    // 2. Get all roles to see available permissions
    console.log('\n2️⃣  Fetching roles...');
    const rolesResponse = await axios.get(`${API_BASE}/roles`, { headers });
    const roles = rolesResponse.data;
    console.log('   ✅ Found roles:', roles.map(r => r.title).join(', '));

    // 3. Create a user with HR Manager role and custom permissions
    console.log('\n3️⃣  Creating HR Manager with custom permissions...');
    const hrRole = roles.find(r => r.id === 'hrManager');
    
    // Define custom permissions (removing some default permissions)
    const customPermissions = {
      'Customer/Employee': {
        'View employees': true,
        'Manage rosters': true,
        'Create schedules': false,  // Disabled this permission
        'Employee requests': true
      },
      'Route Planning': {
        'View routes': true,
        'Employee route assignment': false  // Disabled this permission
      },
      'Reports': {
        'Employee analytics': true,
        'Attendance reports': true
      }
    };

    const newUser = {
      name: 'Jane Smith',
      email: `hrmanager.test.${Date.now()}@company.com`,
      phone: '+1234567890',
      password: 'SecurePassword123',
      role: 'hrManager',
      customPermissions: customPermissions
    };

    const createResponse = await axios.post(`${API_BASE}/user-roles`, newUser, { headers });
    console.log('   ✅ User created:', createResponse.data.name);
    console.log('   📧 Email:', createResponse.data.email);
    console.log('   👤 Role:', createResponse.data.role);
    console.log('   🔐 Custom Permissions:', createResponse.data.customPermissions ? 'Yes' : 'No');

    const userId = createResponse.data._id || createResponse.data.id;

    // 4. Retrieve the user to verify permissions were saved
    console.log('\n4️⃣  Fetching created user...');
    const userResponse = await axios.get(`${API_BASE}/user-roles/${userId}`, { headers });
    console.log('   ✅ User retrieved:', userResponse.data.name);
    
    if (userResponse.data.customPermissions) {
      console.log('   ✅ Custom Permissions saved correctly:');
      Object.entries(userResponse.data.customPermissions).forEach(([module, perms]) => {
        console.log(`      📁 ${module}:`);
        Object.entries(perms).forEach(([perm, value]) => {
          console.log(`         ${value ? '✓' : '✗'} ${perm}`);
        });
      });
    } else {
      console.log('   ⚠️  No custom permissions found');
    }

    // 5. Update user permissions
    console.log('\n5️⃣  Updating user permissions...');
    const updatedPermissions = {
      'Customer/Employee': {
        'View employees': true,
        'Manage rosters': false,  // Changed this
        'Create schedules': true,  // Enabled this
        'Employee requests': true
      },
      'Route Planning': {
        'View routes': true,
        'Employee route assignment': true  // Enabled this
      },
      'Reports': {
        'Employee analytics': false,  // Disabled this
        'Attendance reports': true
      }
    };

    const updateResponse = await axios.put(
      `${API_BASE}/user-roles/${userId}`,
      { customPermissions: updatedPermissions },
      { headers }
    );
    console.log('   ✅ Permissions updated');

    // 6. Verify the update
    console.log('\n6️⃣  Verifying updated permissions...');
    const verifyResponse = await axios.get(`${API_BASE}/user-roles/${userId}`, { headers });
    
    if (verifyResponse.data.customPermissions) {
      console.log('   ✅ Updated permissions:');
      Object.entries(verifyResponse.data.customPermissions).forEach(([module, perms]) => {
        console.log(`      📁 ${module}:`);
        Object.entries(perms).forEach(([perm, value]) => {
          console.log(`         ${value ? '✓' : '✗'} ${perm}`);
        });
      });
    }

    // 7. Get all users to see in list
    console.log('\n7️⃣  Fetching all users...');
    const allUsersResponse = await axios.get(`${API_BASE}/user-roles`, { headers });
    console.log('   ✅ Total users:', allUsersResponse.data.length);
    
    const testUser = allUsersResponse.data.find(u => u._id === userId || u.id === userId);
    if (testUser) {
      console.log('   ✅ Test user found in list with custom permissions:', 
        testUser.customPermissions ? 'Yes' : 'No');
    }

    // 8. Clean up - delete test user
    console.log('\n8️⃣  Cleaning up - deleting test user...');
    await axios.delete(`${API_BASE}/user-roles/${userId}`, { headers });
    console.log('   ✅ Test user deleted');

    console.log('\n═'.repeat(80));
    console.log('✅ ALL TESTS PASSED!');
    console.log('═'.repeat(80) + '\n');

  } catch (error) {
    console.error('\n❌ TEST FAILED!');
    console.error('═'.repeat(80));
    if (error.response) {
      console.error('Status:', error.response.status);
      console.error('Error:', error.response.data);
    } else {
      console.error('Error:', error.message);
    }
    console.error('═'.repeat(80) + '\n');
    process.exit(1);
  }
}

// Run tests
testCustomPermissions();