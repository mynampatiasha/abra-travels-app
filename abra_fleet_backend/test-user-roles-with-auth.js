// Test user-roles endpoint with authentication simulation
require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const userRoleController = require('./controllers/userRoleController');

async function testUserRolesWithAuth() {
  try {
    console.log('\n🧪 TESTING USER-ROLES CONTROLLER DIRECTLY');
    console.log('═'.repeat(80));
    
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to MongoDB');
    
    // Mock request and response objects
    const req = {
      user: {
        uid: 'test-uid',
        email: 'admin@abrafleet.com',
        role: 'admin'
      }
    };
    
    const res = {
      json: (data) => {
        console.log('\n✅ SUCCESS RESPONSE:');
        console.log('   Status: 200');
        console.log('   Data:', JSON.stringify(data, null, 2));
        return res;
      },
      status: (code) => {
        console.log(`\n❌ ERROR RESPONSE: ${code}`);
        return {
          json: (error) => {
            console.log('   Error:', JSON.stringify(error, null, 2));
          }
        };
      }
    };
    
    console.log('\n1️⃣  Calling getAllUsers controller...');
    await userRoleController.getAllUsers(req, res);
    
    console.log('\n═'.repeat(80));
    console.log('✅ TEST COMPLETED!');
    console.log('═'.repeat(80) + '\n');
    
    await mongoose.disconnect();
    process.exit(0);
  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    console.error('Stack:', error.stack);
    console.error('═'.repeat(80) + '\n');
    process.exit(1);
  }
}

testUserRolesWithAuth();