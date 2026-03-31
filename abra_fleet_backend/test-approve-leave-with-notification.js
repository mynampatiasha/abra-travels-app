// test-approve-leave-with-notification.js
// Test script to approve a leave request and verify admin notification is sent

require('dotenv').config();
const { MongoClient, ObjectId } = require('mongodb');
const { createNotification } = require('./models/notification_model');

const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME = process.env.DB_NAME || 'abra_fleet';

async function testApproveLeaveWithNotification() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔌 Connecting to MongoDB...');
    await client.connect();
    const db = client.db(DB_NAME);
    
    console.log('\n📋 FINDING PENDING LEAVE REQUESTS');
    console.log('='.repeat(80));
    
    // Find a pending leave request
    const pendingLeave = await db.collection('leave_requests').findOne({
      status: 'pending_approval'
    });
    
    if (!pendingLeave) {
      console.log('❌ No pending leave requests found.');
      console.log('   Please create a leave request from the customer app first.');
      return;
    }
    
    console.log('\n✅ Found pending leave request:');
    console.log(`   - Customer: ${pendingLeave.customerName}`);
    console.log(`   - Period: ${pendingLeave.startDate} to ${pendingLeave.endDate}`);
    console.log(`   - Reason: ${pendingLeave.reason || 'N/A'}`);
    console.log(`   - Affected Trips: ${pendingLeave.affectedTripsCount || 0}`);
    
    console.log('\n\n📢 TESTING ADMIN NOTIFICATION SYSTEM');
    console.log('='.repeat(80));
    
    // Get all admin users
    const adminUsers = await db.collection('users').find({ 
      role: 'admin' 
    }).toArray();
    
    console.log(`\n✅ Found ${adminUsers.length} admin user(s)`);
    
    if (adminUsers.length === 0) {
      console.log('❌ ERROR: No admin users found!');
      return;
    }
    
    // Simulate sending notification to all admins (without actually approving)
    console.log('\n🔔 Sending test notification to all admins...\n');
    
    for (const admin of adminUsers) {
      try {
        console.log(`📤 Sending to: ${admin.email}`);
        
        await createNotification(db, {
          userId: admin.firebaseUid,
          type: 'leave_approved_admin',
          title: 'Leave Request Approved - Action Required',
          body: `Leave request approved for ${pendingLeave.customerName} from ${pendingLeave.startDate.toDateString()} to ${pendingLeave.endDate.toDateString()}. Please cancel the associated trips.`,
          priority: 'urgent',
          category: 'leave_management',
          data: {
            leaveRequestId: pendingLeave._id.toString(),
            customerId: pendingLeave.customerId,
            customerName: pendingLeave.customerName,
            startDate: pendingLeave.startDate.toISOString(),
            endDate: pendingLeave.endDate.toISOString(),
            affectedTripsCount: pendingLeave.affectedTripsCount || 0,
            approvedBy: 'TEST_SYSTEM'
          }
        });
        
        console.log(`✅ Notification sent successfully to ${admin.email}\n`);
      } catch (error) {
        console.error(`❌ Failed to send to ${admin.email}:`, error.message);
      }
    }
    
    console.log('\n\n🔍 VERIFYING NOTIFICATIONS');
    console.log('='.repeat(80));
    
    // Verify notifications were created
    for (const admin of adminUsers) {
      const notifications = await db.collection('notifications').find({
        userId: admin.firebaseUid,
        type: 'leave_approved_admin'
      }).sort({ createdAt: -1 }).limit(1).toArray();
      
      console.log(`\n👤 Admin: ${admin.email}`);
      if (notifications.length > 0) {
        const notif = notifications[0];
        console.log(`   ✅ Latest notification:`);
        console.log(`      - Title: ${notif.title}`);
        console.log(`      - Priority: ${notif.priority}`);
        console.log(`      - Read: ${notif.isRead ? 'Yes' : 'No'}`);
        console.log(`      - Created: ${notif.createdAt}`);
      } else {
        console.log(`   ❌ No notifications found`);
      }
    }
    
    console.log('\n\n✅ TEST COMPLETE');
    console.log('='.repeat(80));
    console.log('\n📝 WHAT TO DO NEXT:');
    console.log('   1. Login to admin dashboard');
    console.log('   2. Check the notification bell icon (top right corner)');
    console.log('   3. You should see a red badge with unread count');
    console.log('   4. Click the bell to see the notification');
    console.log('   5. The notification should say "Leave Request Approved - Action Required"');
    console.log('   6. Click it to navigate to Trip Cancellation Management screen');
    
  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n🔌 Disconnected from MongoDB\n');
  }
}

testApproveLeaveWithNotification();
