// Test script to simulate the exact frontend route assignment request
const axios = require('axios');
require('dotenv').config();

const BASE_URL = process.env.API_BASE_URL || 'http://localhost:3001';

async function testFrontendRouteAssignment() {
  try {
    console.log('\n🧪 TESTING FRONTEND ROUTE ASSIGNMENT');
    console.log('='.repeat(60));
    
    // Get admin token (simulate frontend login)
    console.log('🔐 Getting admin token...');
    const loginResponse = await axios.post(`${BASE_URL}/api/auth/login`, {
      email: 'admin@abrafleet.com',
      password: 'admin123'
    });
    
    const token = loginResponse.data.token;
    console.log('✅ Admin token obtained');
    
    // Get a vehicle with assigned driver
    console.log('\n🚗 Getting vehicle with driver...');
    const vehiclesResponse = await axios.get(`${BASE_URL}/api/admin/vehicles`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    
    const vehicleWithDriver = vehiclesResponse.data.data.find(v => 
      v.assignedDriver && 
      v.assignedDriver.name && 
      v.seatCapacity > 0
    );
    
    if (!vehicleWithDriver) {
      console.log('❌ No vehicle with assigned driver found');
      return;
    }
    
    console.log(`✅ Found vehicle: ${vehicleWithDriver.registrationNumber}`);
    console.log(`   Driver: ${vehicleWithDriver.assignedDriver.name}`);
    console.log(`   Seats: ${vehicleWithDriver.seatCapacity}`);
    
    // Get pending rosters
    console.log('\n📋 Getting pending rosters...');
    const rostersResponse = await axios.get(`${BASE_URL}/api/roster/pending`, {
      headers: { Authorization: `Bearer ${token}` }
    });
    
    const pendingRosters = rostersResponse.data.data || [];
    console.log(`✅ Found ${pendingRosters.length} pending rosters`);
    
    if (pendingRosters.length === 0) {
      console.log('❌ No pending rosters found');
      return;
    }
    
    // Take first roster for testing
    const testRoster = pendingRosters[0];
    console.log(`   Testing with: ${testRoster.customerName || 'Unknown Customer'}`);
    
    // Create the exact payload that frontend sends
    const routePayload = {
      vehicleId: vehicleWithDriver._id,
      route: [
        {
          rosterId: testRoster._id,
          customerId: testRoster.customerId || testRoster.customerEmail,
          customerName: testRoster.customerName || 'Unknown Customer',
          customerEmail: testRoster.customerEmail || '',
          customerPhone: testRoster.customerPhone || '',
          sequence: 1,
          pickupTime: '08:30',
          eta: new Date(Date.now() + 30 * 60 * 1000).toISOString(), // 30 mins from now
          location: testRoster.pickupLocation || testRoster.officeLocation || 'Test Location',
          distanceFromPrevious: 1.5,
          estimatedTime: 30
        }
      ],
      totalDistance: 1.5,
      totalTime: 30,
      startTime: new Date().toISOString()
    };
    
    console.log('\n📤 Sending route assignment request...');
    console.log('   Payload:', JSON.stringify(routePayload, null, 2));
    
    // Make the assignment request
    const assignmentResponse = await axios.post(
      `${BASE_URL}/api/roster/assign-optimized-route`,
      routePayload,
      {
        headers: { 
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      }
    );
    
    console.log('\n✅ ASSIGNMENT RESPONSE:');
    console.log('   Status:', assignmentResponse.status);
    console.log('   Success:', assignmentResponse.data.success);
    console.log('   Message:', assignmentResponse.data.message);
    
    if (assignmentResponse.data.success) {
      console.log('   🎉 Assignment succeeded!');
      if (assignmentResponse.data.data) {
        console.log('   Results:', assignmentResponse.data.data.results?.length || 0, 'customers assigned');
        console.log('   Errors:', assignmentResponse.data.data.errors?.length || 0, 'errors');
      }
    } else {
      console.log('   ❌ Assignment failed');
      if (assignmentResponse.data.advice) {
        console.log('   Advice:', assignmentResponse.data.advice);
      }
      if (assignmentResponse.data.data?.errors) {
        console.log('   Errors:', assignmentResponse.data.data.errors);
      }
    }
    
  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    if (error.response) {
      console.error('   Status:', error.response.status);
      console.error('   Response:', JSON.stringify(error.response.data, null, 2));
    }
  }
}

testFrontendRouteAssignment();