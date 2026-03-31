// test-approve-leave-notification.js
// Test approving a leave request and check if notification is sent

require('dotenv').config();
const { MongoClient } = require('mongodb');
const admin = require('./config/firebase');

const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME = process.env.DB_NAME || 'abra_fleet';

async function testApproveLeave() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔌 Connecting to MongoDB...');
    await client.connect();
    const db = client.db(DB_NAME);
    
    // Find a pending leave request for Asha
    const leaveRequest = await db.collection('leave_requests').findOne({
      customerEmail: 'asha123@cognizant.com',
      status: 'pending_approval'
    });
    
    if (!leaveRequest) {
      console.log('❌ No pending leave requests found for asha123@cognizant.com');
      console.log('   Please create a leave request first from the customer app');
      return;
    }
    
    console.log('\n✅ Found pending leave request:');
    console.log(`   Customer ID: ${leaveRequest.customerId}`);
    console.log(`   Customer Name: ${leaveRequest.customerName}`);
    console.log(`   Start Date: ${leaveRequest.startDate}`);
    console.log(`   End Date: ${leaveRequest.endDate}`);
    console.log(`   Reason: ${leaveRequest.reason}`);
    
    // Simulate approval
    console.log('\n📝 Simulating leave approval...');
    
    // Update leave request status
    await db.collection('leave_requests').updateOne(
      { _id: leaveRequest._id },
      { 
        $set: { 
          status: 'approved',
          approvedBy: 'Test Admin',
          approvedAt: new Date(),
          updatedAt: new Date()
        }
      }
    );
    
    console.log('✅ Leave request status updated to approved');
    
    // Send notification directly to Firebase RTDB (simulating the fallback)
    console.log('\n📤 Sending notification to customer...');
    
    const notificationId = Date.now().toString();
    const notification = {
      id: notificationId,
      userId: leaveRequest.customerId,
      type: 'leave_approved',
      title: 'Leave Request Approved',
      body: `Good news! Your organization has approved your leave request from ${new Date(leaveRequest.startDate).toDateString()} to ${new Date(leaveRequest.endDate).toDateString()}.`,
      data: {
        leaveRequestId: leaveRequest._id.toString(),
        startDate: new Date(leaveRequest.startDate).toISOString(),
        endDate: new Date(leaveRequest.endDate).toISOString(),
        approvedBy: 'Test Admin',
        approvalNote: 'Approved for testing'
      },
      isRead: false,
      priority: 'high',
      category: 'leave_management',
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
    };
    
    const firebasePath = `notifications/${leaveRequest.customerId}/${notificationId}`;
    console.log(`📍 Firebase path: ${firebasePath}`);
    
    await admin.database().ref(firebasePath).set(notification);
    
    console.log('✅ Notification sent successfully!');
    
    console.log('\n📝 NEXT STEPS:');
    console.log('   1. Open the app as the customer');
    console.log('   2. Click the notification bell');
    console.log('   3. You should see the leave approval notification');
    console.log('   4. The notification should show in the notification screen');
    
  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n🔌 Disconnected from MongoDB\n');
  }
}

testApproveLeave();
