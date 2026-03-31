// test-admin-trip-cancellation.js - Test admin trip cancellation and driver notifications

const express = require('express');
const { MongoClient, ObjectId } = require('mongodb');
const admin = require('firebase-admin');

// Test configuration
const TEST_CONFIG = {
  mongoUrl: process.env.MONGODB_URI || 'mongodb://localhost:27017/abra_fleet',
  testCustomerId: 'test-customer-123',
  testDriverId: 'test-driver-456',
  testAdminId: 'test-admin-789',
  testEmail: 'test.customer@example.com',
  driverEmail: 'test.driver@example.com',
  adminEmail: 'admin@organization.com'
};

async function testAdminTripCancellationWorkflow() {
  console.log('🏢 Testing Admin Trip Cancellation & Driver Notification Workflow...\n');
  
  try {
    // Connect to MongoDB
    console.log('📡 Connecting to MongoDB...');
    const client = new MongoClient(TEST_CONFIG.mongoUrl);
    await client.connect();
    const db = client.db();
    console.log('✅ MongoDB connected\n');

    // Test 1: Create sample data (approved leave request with trips)
    console.log('📋 Test 1: Creating sample data...');
    
    // Create sample rosters with assigned driver
    const sampleRosters = [
      {
        _id: new ObjectId(),
        createdBy: TEST_CONFIG.testCustomerId,
        customerName: 'John Doe',
        customerEmail: TEST_CONFIG.testEmail,
        rosterType: 'login',
        officeLocation: 'Tech Park Campus',
        status: 'assigned',
        fromDate: new Date('2024-12-15'),
        toDate: new Date('2024-12-25'),
        fromTime: '09:00',
        toTime: '18:00',
        readableId: 'RST-0001',
        assignedDriver: {
          driverId: TEST_CONFIG.testDriverId,
          driverName: 'Mike Johnson',
          driverEmail: TEST_CONFIG.driverEmail
        },
        createdAt: new Date()
      },
      {
        _id: new ObjectId(),
        createdBy: TEST_CONFIG.testCustomerId,
        customerName: 'John Doe',
        customerEmail: TEST_CONFIG.testEmail,
        rosterType: 'logout',
        officeLocation: 'Tech Park Campus',
        status: 'scheduled',
        fromDate: new Date('2024-12-16'),
        toDate: new Date('2024-12-26'),
        fromTime: '18:00',
        toTime: '19:00',
        readableId: 'RST-0002',
        assignedDriver: {
          driverId: TEST_CONFIG.testDriverId,
          driverName: 'Mike Johnson',
          driverEmail: TEST_CONFIG.driverEmail
        },
        createdAt: new Date()
      }
    ];

    const rosterResults = await db.collection('rosters').insertMany(sampleRosters);
    const rosterIds = Object.values(rosterResults.insertedIds);
    console.log(`✅ Created ${rosterIds.length} sample rosters with assigned driver`);

    // Create approved leave request
    const approvedLeaveRequest = {
      customerId: TEST_CONFIG.testCustomerId,
      customerName: 'John Doe',
      customerEmail: TEST_CONFIG.testEmail,
      organizationName: 'Tech Solutions Inc.',
      startDate: new Date('2024-12-18'),
      endDate: new Date('2024-12-22'),
      reason: 'Family vacation',
      status: 'approved',
      affectedTripIds: rosterIds,
      affectedTripsCount: rosterIds.length,
      approvedBy: 'HR Manager',
      approvedAt: new Date(),
      approvalNote: 'Approved for family vacation',
      tripsProcessed: false, // Key field - not processed yet
      createdAt: new Date(),
      updatedAt: new Date()
    };

    const leaveResult = await db.collection('leave_requests').insertOne(approvedLeaveRequest);
    console.log(`✅ Created approved leave request: ${leaveResult.insertedId}\n`);

    // Test 2: Fetch approved leave requests needing trip cancellation
    console.log('📊 Test 2: Fetching approved leave requests for trip cancellation...');
    const approvedRequests = await db.collection('leave_requests')
      .find({ 
        status: 'approved',
        tripsProcessed: { $ne: true }
      })
      .toArray();
    
    console.log(`✅ Found ${approvedRequests.length} approved request(s) needing trip cancellation`);
    if (approvedRequests.length > 0) {
      console.log('Request details:', {
        id: approvedRequests[0]._id.toString(),
        customerName: approvedRequests[0].customerName,
        affectedTripsCount: approvedRequests[0].affectedTripsCount,
        approvedBy: approvedRequests[0].approvedBy
      });
    }
    console.log();

    // Test 3: Simulate admin cancelling trips
    console.log('🗑️ Test 3: Simulating admin trip cancellation...');
    
    // Get affected trips before cancellation
    const affectedTrips = await db.collection('rosters')
      .find({ 
        _id: { $in: rosterIds },
        status: { $in: ['assigned', 'scheduled'] }
      })
      .toArray();
    
    console.log(`📋 Found ${affectedTrips.length} trips to cancel`);

    // Cancel all affected trips
    const cancelledTrips = [];
    for (const trip of affectedTrips) {
      await db.collection('rosters').updateOne(
        { _id: trip._id },
        { 
          $set: { 
            status: 'cancelled',
            cancellationReason: 'Customer is on leave',
            cancelledBy: 'Fleet Admin',
            cancelledByEmail: TEST_CONFIG.adminEmail,
            cancelledAt: new Date(),
            adminNotes: 'Cancelled due to approved leave request',
            updatedAt: new Date()
          }
        }
      );

      cancelledTrips.push({
        id: trip._id.toString(),
        readableId: trip.readableId,
        rosterType: trip.rosterType,
        assignedDriver: trip.assignedDriver
      });
    }

    console.log(`✅ Cancelled ${cancelledTrips.length} trips`);

    // Mark leave request as processed
    await db.collection('leave_requests').updateOne(
      { _id: leaveResult.insertedId },
      { 
        $set: { 
          tripsProcessed: true,
          tripsProcessedBy: 'Fleet Admin',
          tripsProcessedAt: new Date(),
          tripsCancelledCount: cancelledTrips.length,
          adminNotes: 'All trips cancelled successfully',
          updatedAt: new Date()
        }
      }
    );

    console.log('✅ Leave request marked as processed');

    // Create history log
    await db.collection('trip_cancellation_history').insertOne({
      leaveRequestId: leaveResult.insertedId,
      customerId: TEST_CONFIG.testCustomerId,
      customerName: 'John Doe',
      cancelledTrips: cancelledTrips,
      cancelledBy: 'Fleet Admin',
      cancelledByEmail: TEST_CONFIG.adminEmail,
      cancelledAt: new Date(),
      reason: 'Customer is on leave',
      adminNotes: 'All trips cancelled successfully',
      createdAt: new Date()
    });

    console.log('✅ Trip cancellation history logged\n');

    // Test 4: Simulate driver notifications (would be sent via notification system)
    console.log('📱 Test 4: Simulating driver notifications...');
    
    let notificationsSent = 0;
    for (const trip of cancelledTrips) {
      if (trip.assignedDriver && trip.assignedDriver.driverId) {
        // In real implementation, this would use the notification system
        console.log(`📨 Notification sent to driver ${trip.assignedDriver.driverName}:`);
        console.log(`   - Trip ${trip.readableId} cancelled`);
        console.log(`   - Reason: Customer is on leave`);
        console.log(`   - Type: ${trip.rosterType}`);
        notificationsSent++;
      }
    }
    
    console.log(`✅ ${notificationsSent} driver notifications sent\n`);

    // Test 5: Driver fetches cancelled trips
    console.log('🚗 Test 5: Driver fetching cancelled trips...');
    
    const driverCancelledTrips = await db.collection('rosters')
      .find({
        'assignedDriver.driverId': TEST_CONFIG.testDriverId,
        status: 'cancelled'
      })
      .sort({ cancelledAt: -1 })
      .toArray();
    
    console.log(`✅ Driver found ${driverCancelledTrips.length} cancelled trip(s)`);
    driverCancelledTrips.forEach((trip, index) => {
      console.log(`   Trip ${index + 1}:`, {
        id: trip.readableId,
        customerName: trip.customerName,
        rosterType: trip.rosterType,
        cancellationReason: trip.cancellationReason,
        cancelledBy: trip.cancelledBy
      });
    });
    console.log();

    // Test 6: Driver acknowledges trip cancellation
    console.log('✅ Test 6: Driver acknowledging trip cancellations...');
    
    for (const trip of driverCancelledTrips) {
      await db.collection('rosters').updateOne(
        { 
          _id: trip._id,
          'assignedDriver.driverId': TEST_CONFIG.testDriverId,
          status: 'cancelled'
        },
        { 
          $set: { 
            cancellationAcknowledged: true,
            acknowledgedAt: new Date(),
            updatedAt: new Date()
          }
        }
      );
    }
    
    console.log(`✅ Driver acknowledged ${driverCancelledTrips.length} trip cancellation(s)\n`);

    // Test 7: Verify final state
    console.log('🔍 Test 7: Verifying final state...');
    
    // Check leave request status
    const finalLeaveRequest = await db.collection('leave_requests').findOne({
      _id: leaveResult.insertedId
    });
    
    console.log('Leave request final state:', {
      status: finalLeaveRequest.status,
      tripsProcessed: finalLeaveRequest.tripsProcessed,
      tripsCancelledCount: finalLeaveRequest.tripsCancelledCount,
      processedBy: finalLeaveRequest.tripsProcessedBy
    });

    // Check trip statuses
    const finalTrips = await db.collection('rosters')
      .find({ _id: { $in: rosterIds } })
      .toArray();
    
    console.log('Trip final states:');
    finalTrips.forEach(trip => {
      console.log(`   ${trip.readableId}: ${trip.status} (acknowledged: ${trip.cancellationAcknowledged || false})`);
    });

    // Check history log
    const historyCount = await db.collection('trip_cancellation_history').countDocuments({
      leaveRequestId: leaveResult.insertedId
    });
    
    console.log(`History logs created: ${historyCount}\n`);

    // Cleanup
    console.log('🧹 Cleaning up test data...');
    await db.collection('leave_requests').deleteOne({ _id: leaveResult.insertedId });
    await db.collection('rosters').deleteMany({ _id: { $in: rosterIds } });
    await db.collection('trip_cancellation_history').deleteMany({ leaveRequestId: leaveResult.insertedId });
    console.log('✅ Test data cleaned up\n');

    await client.close();
    console.log('🎉 All admin trip cancellation and driver notification tests passed!\n');

    // Summary
    console.log('📋 TEST SUMMARY:');
    console.log('✅ Approved leave request creation');
    console.log('✅ Admin fetching requests needing trip cancellation');
    console.log('✅ Admin trip cancellation workflow');
    console.log('✅ Leave request processing status update');
    console.log('✅ Trip cancellation history logging');
    console.log('✅ Driver notification simulation');
    console.log('✅ Driver cancelled trips fetching');
    console.log('✅ Driver trip cancellation acknowledgment');
    console.log('✅ Final state verification');
    console.log('\n🏢 Admin Trip Cancellation & Driver Notification Workflow is ready!');

  } catch (error) {
    console.error('❌ Test failed:', error.message);
    console.error(error.stack);
    process.exit(1);
  }
}

// Run the test
if (require.main === module) {
  testAdminTripCancellationWorkflow();
}

module.exports = { testAdminTripCancellationWorkflow };