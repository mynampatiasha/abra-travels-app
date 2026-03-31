// test-single-user-login.js - Test single user login to debug JWT integration
const axios = require('axios');
require('dotenv').config();

const BASE_URL = process.env.BASE_URL || 'http://localhost:3001';

async function testSingleUserLogin() {
  console.log('\n🧪 TESTING SINGLE USER LOGIN - CUSTOMER');
  console.log('═'.repeat(50));
  
  try {
    console.log('📡 Testing customer login...');
    
    const loginResponse = await axios.post(`${BASE_URL}/api/auth/login`, {
      email: 'testcustomer@abrafleet.com',
      password: 'password123'
    });
    
    console.log('\n📋 LOGIN RESPONSE:');
    console.log('Success:', loginResponse.data.success);
    console.log('Message:', loginResponse.data.message);
    
    if (loginResponse.data.success) {
      const user = loginResponse.data.data.user;
      const token = loginResponse.data.data.token;
      
      console.log('\n👤 USER DATA:');
      console.log('ID:', user.id);
      console.log('Email:', user.email);
      console.log('Name:', user.name);
      console.log('Role:', user.role);
      console.log('Collection:', user.collectionName);
      console.log('CustomerId:', user.customerId || 'MISSING');
      console.log('DriverId:', user.driverId || 'null');
      console.log('ClientId:', user.clientId || 'null');
      console.log('EmployeeId:', user.employeeId || 'null');
      
      console.log('\n🔑 JWT TOKEN PAYLOAD:');
      const tokenParts = token.split('.');
      if (tokenParts.length === 3) {
        const payload = JSON.parse(Buffer.from(tokenParts[1], 'base64').toString());
        console.log('UserId:', payload.userId);
        console.log('Email:', payload.email);
        console.log('Role:', payload.role);
        console.log('CustomerId:', payload.customerId || 'MISSING');
        console.log('DriverId:', payload.driverId || 'null');
        console.log('ClientId:', payload.clientId || 'null');
        console.log('EmployeeId:', payload.employeeId || 'null');
      }
    } else {
      console.log('❌ Login failed:', loginResponse.data.message);
    }
    
  } catch (error) {
    console.error('❌ ERROR:', error.response?.data?.message || error.message);
  }
}

testSingleUserLogin().catch(console.error);