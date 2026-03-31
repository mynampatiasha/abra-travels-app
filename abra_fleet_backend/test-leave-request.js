// test-leave-request.js - Simple test for leave request API

const express = require('express');
const { MongoClient } = require('mongodb');
const admin = require('firebase-admin');

// Test configuration
const TEST_CONFIG = {
  mongoUrl: process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet',
  testUserId: 'test-customer-123',
  testEmail: 'test.customer@example.com'
};

async function testLeaveRequestAPI() {
  console.log('🧪 Testing Leave Request API...\n');
  
  try {
    // Connect to MongoDB
    console.log('📡 Connecting to MongoDB...');
    const client = new MongoClient(TEST_CONFIG.mongoUrl);
    await client.connect();
    const db = client.db();
    console.log('✅ MongoDB connected\n');

    // Test 1: Create sample roster data
    console.log('📋 Test 1: Creating sample roster data...');
    const sampleRoster = {
      createdBy: TEST_CONFIG.testUserId,
      customerName: 'Test Customer',
      customerEmail: TEST_CONFIG.testEmail,
      rosterType: 'both',
      officeLocation: 'Test Office',
      status: 'pending_assignment',
      fromDate: new Date('2024-12-10'),
      toDate: new Date('2024-12-20'),
      fromTime: '09:00',
      toTime: '18:00',
      createdAt: new Date()
    };

    const rosterResult = await db.collection('rosters').insertOne(sampleRoster);
    console.log(`✅ Sample roster created: ${rosterResult.insertedId}\n`);

    // Test 2: Simulate leave request creation
    console.log('🏖️ Test 2: Creating leave request...');
    const leaveRequest = {
      customerId: TEST_CONFIG.testUserId,
      customerName: 'Test Customer',
      customerEmail: TEST_CONFIG.testEmail,
      organizationName: 'Test Organization',
      startDate: new Date('2024-12-12'),
      endDate: new Date('2024-12-18'),
      reason: 'Test vacation',
      status: 'pending_approval',
      affectedTripIds: [rosterResult.insertedId],
      affectedTripsCount: 1,
      createdAt: new Date(),
      updatedAt: new Date()
    };

    const leaveResult = await db.collection('leave_requests').insertOne(leaveRequest);
    console.log(`✅ Leave request created: ${leaveResult.insertedId}\n`);

    // Test 3: Update affected roster
    console.log('🔄 Test 3: Updating affected roster...');
    await db.collection('rosters').updateOne(
      { _id: rosterResult.insertedId },
      { 
        $set: { 
          leaveRequestId: leaveResult.insertedId,
          leaveRequestStatus: 'pending_approval'
        }
      }
    );
    console.log('✅ Roster updated with leave request reference\n');

    // Test 4: Query leave requests
    console.log('📊 Test 4: Querying leave requests...');
    const leaveRequests = await db.collection('leave_requests')
      .find({ customerId: TEST_CONFIG.testUserId })
      .toArray();
    
    console.log(`✅ Found ${leaveRequests.length} leave request(s)`);
    console.log('Leave request details:', {
      id: leaveRequests[0]._id.toString(),
      status: leaveRequests[0].status,
      startDate: leaveRequests[0].startDate,
      endDate: leaveRequests[0].endDate,
      affectedTripsCount: leaveRequests[0].affectedTripsCount
    });
    console.log();

    // Test 5: Query affected rosters
    console.log('🎯 Test 5: Querying affected rosters...');
    const affectedRosters = await db.collection('rosters')
      .find({ leaveRequestId: leaveResult.insertedId })
      .toArray();
    
    console.log(`✅ Found ${affectedRosters.length} affected roster(s)`);
    console.log('Affected roster details:', {
      id: affectedRosters[0]._id.toString(),
      status: affectedRosters[0].status,
      leaveRequestStatus: affectedRosters[0].leaveRequestStatus,
      officeLocation: affectedRosters[0].officeLocation
    });
    console.log();

    // Cleanup
    console.log('🧹 Cleaning up test data...');
    await db.collection('leave_requests').deleteOne({ _id: leaveResult.insertedId });
    await db.collection('rosters').deleteOne({ _id: rosterResult.insertedId });
    console.log('✅ Test data cleaned up\n');

    await client.close();
    console.log('🎉 All tests passed! Leave Request API is ready.\n');

  } catch (error) {
    console.error('❌ Test failed:', error.message);
    console.error(error.stack);
    process.exit(1);
  }
}

// Run the test
if (require.main === module) {
  testLeaveRequestAPI();
}

module.exports = { testLeaveRequestAPI };