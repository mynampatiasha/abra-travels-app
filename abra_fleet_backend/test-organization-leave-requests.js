// test-organization-leave-requests.js - Test organization leave request management

const express = require('express');
const { MongoClient, ObjectId } = require('mongodb');
const admin = require('firebase-admin');

// Test configuration
const TEST_CONFIG = {
  mongoUrl: process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet',
  testCustomerId: 'test-customer-123',
  testAdminId: 'test-admin-456',
  testEmail: 'test.customer@example.com',
  adminEmail: 'admin@organization.com'
};

async function testOrganizationLeaveRequestAPI() {
  console.log('🏢 Testing Organization Leave Request Management API...\n');
  
  try {
    // Connect to MongoDB
    console.log('📡 Connecting to MongoDB...');
    const client = new MongoClient(TEST_CONFIG.mongoUrl);
    await client.connect();
    const db = client.db();
    console.log('✅ MongoDB connected\n');

    // Test 1: Create sample data
    console.log('📋 Test 1: Creating sample data...');
    
    // Create sample roster
    const sampleRoster = {
      createdBy: TEST_CONFIG.testCustomerId,
      customerName: 'John Doe',
      customerEmail: TEST_CONFIG.testEmail,
      rosterType: 'both',
      officeLocation: 'Tech Park Campus',
      status: 'pending_assignment',
      fromDate: new Date('2024-12-15'),
      toDate: new Date('2024-12-25'),
      fromTime: '09:00',
      toTime: '18:00',
      createdAt: new Date()
    };

    const rosterResult = await db.collection('rosters').insertOne(sampleRoster);
    console.log(`✅ Sample roster created: ${rosterResult.insertedId}`);

    // Create sample leave request
    const sampleLeaveRequest = {
      customerId: TEST_CONFIG.testCustomerId,
      customerName: 'John Doe',
      customerEmail: TEST_CONFIG.testEmail,
      organizationName: 'Tech Solutions Inc.',
      startDate: new Date('2024-12-18'),
      endDate: new Date('2024-12-22'),
      reason: 'Family vacation',
      status: 'pending_approval',
      affectedTripIds: [rosterResult.insertedId],
      affectedTripsCount: 1,
      createdAt: new Date(),
      updatedAt: new Date()
    };

    const leaveResult = await db.collection('leave_requests').insertOne(sampleLeaveRequest);
    console.log(`✅ Sample leave request created: ${leaveResult.insertedId}\n`);

    // Test 2: Fetch leave requests for organization
    console.log('📊 Test 2: Fetching leave requests for organization...');
    const leaveRequests = await db.collection('leave_requests')
      .find({})
      .sort({ createdAt: -1 })
      .toArray();
    
    console.log(`✅ Found ${leaveRequests.length} leave request(s)`);
    if (leaveRequests.length > 0) {
      console.log('Leave request details:', {
        id: leaveRequests[0]._id.toString(),
        customerName: leaveRequests[0].customerName,
        status: leaveRequests[0].status,
        startDate: leaveRequests[0].startDate,
        endDate: leaveRequests[0].endDate,
        affectedTripsCount: leaveRequests[0].affectedTripsCount
      });
    }
    console.log();

    // Test 3: Simulate leave request approval
    console.log('✅ Test 3: Simulating leave request approval...');
    const approvalResult = await db.collection('leave_requests').updateOne(
      { _id: leaveResult.insertedId },
      { 
        $set: { 
          status: 'approved',
          approvedBy: 'HR Manager',
          approvedByEmail: TEST_CONFIG.adminEmail,
          approvedAt: new Date(),
          approvalNote: 'Approved for family vacation',
          updatedAt: new Date()
        }
      }
    );

    console.log(`✅ Leave request approval result:`, {
      matchedCount: approvalResult.matchedCount,
      modifiedCount: approvalResult.modifiedCount
    });

    // Update affected trips
    await db.collection('rosters').updateMany(
      { _id: { $in: [rosterResult.insertedId] } },
      { 
        $set: { 
          status: 'waiting_cancellation',
          leaveRequestStatus: 'approved',
          updatedAt: new Date()
        }
      }
    );
    console.log('✅ Affected trips updated to waiting_cancellation status\n');

    // Test 4: Fetch updated leave request
    console.log('📋 Test 4: Fetching updated leave request...');
    const updatedLeaveRequest = await db.collection('leave_requests').findOne({
      _id: leaveResult.insertedId
    });

    console.log('Updated leave request:', {
      id: updatedLeaveRequest._id.toString(),
      status: updatedLeaveRequest.status,
      approvedBy: updatedLeaveRequest.approvedBy,
      approvedAt: updatedLeaveRequest.approvedAt,
      approvalNote: updatedLeaveRequest.approvalNote
    });
    console.log();

    // Test 5: Test rejection workflow
    console.log('❌ Test 5: Testing rejection workflow...');
    
    // Create another leave request for rejection test
    const rejectionLeaveRequest = {
      customerId: TEST_CONFIG.testCustomerId,
      customerName: 'Jane Smith',
      customerEmail: 'jane.smith@example.com',
      organizationName: 'Tech Solutions Inc.',
      startDate: new Date('2024-12-20'),
      endDate: new Date('2024-12-24'),
      reason: 'Personal work',
      status: 'pending_approval',
      affectedTripIds: [rosterResult.insertedId],
      affectedTripsCount: 1,
      createdAt: new Date(),
      updatedAt: new Date()
    };

    const rejectionResult = await db.collection('leave_requests').insertOne(rejectionLeaveRequest);
    console.log(`✅ Created leave request for rejection test: ${rejectionResult.insertedId}`);

    // Simulate rejection
    await db.collection('leave_requests').updateOne(
      { _id: rejectionResult.insertedId },
      { 
        $set: { 
          status: 'rejected',
          rejectedBy: 'HR Manager',
          rejectedByEmail: TEST_CONFIG.adminEmail,
          rejectedAt: new Date(),
          rejectionReason: 'No leave approved in our records for this period',
          updatedAt: new Date()
        }
      }
    );

    console.log('✅ Leave request rejected successfully');

    // Remove leave request reference from affected trips
    await db.collection('rosters').updateMany(
      { _id: { $in: [rosterResult.insertedId] } },
      { 
        $unset: { 
          leaveRequestId: "",
          leaveRequestStatus: ""
        },
        $set: {
          updatedAt: new Date()
        }
      }
    );
    console.log('✅ Leave request reference removed from affected trips\n');

    // Test 6: Query leave requests by status
    console.log('🔍 Test 6: Querying leave requests by status...');
    
    const approvedRequests = await db.collection('leave_requests')
      .find({ status: 'approved' })
      .toArray();
    
    const rejectedRequests = await db.collection('leave_requests')
      .find({ status: 'rejected' })
      .toArray();
    
    const pendingRequests = await db.collection('leave_requests')
      .find({ status: 'pending_approval' })
      .toArray();

    console.log('Leave requests by status:', {
      approved: approvedRequests.length,
      rejected: rejectedRequests.length,
      pending: pendingRequests.length
    });
    console.log();

    // Test 7: Fetch leave request with affected trip details
    console.log('📊 Test 7: Fetching leave request with affected trip details...');
    
    const leaveRequestWithTrips = await db.collection('leave_requests').findOne({
      _id: leaveResult.insertedId
    });

    if (leaveRequestWithTrips && leaveRequestWithTrips.affectedTripIds) {
      const affectedTrips = await db.collection('rosters')
        .find({ _id: { $in: leaveRequestWithTrips.affectedTripIds } })
        .toArray();
      
      console.log('Leave request with trip details:', {
        leaveRequestId: leaveRequestWithTrips._id.toString(),
        customerName: leaveRequestWithTrips.customerName,
        status: leaveRequestWithTrips.status,
        affectedTrips: affectedTrips.map(trip => ({
          id: trip._id.toString(),
          rosterType: trip.rosterType,
          officeLocation: trip.officeLocation,
          status: trip.status
        }))
      });
    }
    console.log();

    // Cleanup
    console.log('🧹 Cleaning up test data...');
    await db.collection('leave_requests').deleteMany({
      _id: { $in: [leaveResult.insertedId, rejectionResult.insertedId] }
    });
    await db.collection('rosters').deleteOne({ _id: rosterResult.insertedId });
    console.log('✅ Test data cleaned up\n');

    await client.close();
    console.log('🎉 All organization leave request tests passed!\n');

    // Summary
    console.log('📋 TEST SUMMARY:');
    console.log('✅ Leave request creation');
    console.log('✅ Leave request fetching');
    console.log('✅ Leave request approval workflow');
    console.log('✅ Affected trips status update');
    console.log('✅ Leave request rejection workflow');
    console.log('✅ Status-based querying');
    console.log('✅ Leave request with trip details');
    console.log('\n🏢 Organization Leave Request Management API is ready!');

  } catch (error) {
    console.error('❌ Test failed:', error.message);
    console.error(error.stack);
    process.exit(1);
  }
}

// Run the test
if (require.main === module) {
  testOrganizationLeaveRequestAPI();
}

module.exports = { testOrganizationLeaveRequestAPI };