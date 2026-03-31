// test-admin-leave-notification.js
// Test script to verify admin notifications for approved leave requests

require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME = process.env.DB_NAME || 'abra_fleet';

async function testAdminLeaveNotification() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔌 Connecting to MongoDB...');
    await client.connect();
    const db = client.db(DB_NAME);
    
    console.log('\n📊 CHECKING ADMIN USERS');
    console.log('='.repeat(80));
    
    // Get all admin users
    const adminUsers = await db.collection('users').find({ 
      role: 'admin' 
    }).toArray();
    
    console.log(`\n✅ Found ${adminUsers.length} admin user(s):`);
    adminUsers.forEach((admin, index) => {
      console.log(`\n${index + 1}. Admin User:`);
      console.log(`   - Email: ${admin.email}`);
      console.log(`   - Firebase UID: ${admin.firebaseUid}`);
      console.log(`   - Name: ${admin.firstName} ${admin.lastName}`);
      console.log(`   - Role: ${admin.role}`);
    });
    
    if (adminUsers.length === 0) {
      console.log('\n❌ ERROR: No admin users found!');
      console.log('   Please create an admin user first.');
      return;
    }
    
    console.log('\n\n📬 CHECKING ADMIN NOTIFICATIONS');
    console.log('='.repeat(80));
    
    // Check notifications for each admin
    for (const admin of adminUsers) {
      console.log(`\n👤 Admin: ${admin.email}`);
      console.log('─'.repeat(60));
      
      const notifications = await db.collection('notifications').find({
        userId: admin.firebaseUid,
        type: 'leave_approved_admin'
      }).sort({ createdAt: -1 }).limit(5).toArray();
      
      console.log(`   Total leave approval notifications: ${notifications.length}`);
      
      if (notifications.length > 0) {
        console.log('\n   Recent notifications:');
        notifications.forEach((notif, index) => {
          console.log(`\n   ${index + 1}. ${notif.title}`);
          console.log(`      - Body: ${notif.body}`);
          console.log(`      - Priority: ${notif.priority}`);
          console.log(`      - Read: ${notif.isRead ? 'Yes' : 'No'}`);
          console.log(`      - Created: ${notif.createdAt}`);
          if (notif.data) {
            console.log(`      - Customer: ${notif.data.customerName}`);
            console.log(`      - Leave Period: ${notif.data.startDate} to ${notif.data.endDate}`);
            console.log(`      - Affected Trips: ${notif.data.affectedTripsCount}`);
          }
        });
      } else {
        console.log('   ⚠️  No leave approval notifications found for this admin');
      }
      
      // Check unread count
      const unreadCount = await db.collection('notifications').countDocuments({
        userId: admin.firebaseUid,
        isRead: false
      });
      console.log(`\n   📊 Unread notifications: ${unreadCount}`);
    }
    
    console.log('\n\n🔍 CHECKING LEAVE REQUESTS');
    console.log('='.repeat(80));
    
    // Check recent approved leave requests
    const approvedLeaves = await db.collection('leave_requests').find({
      status: 'approved'
    }).sort({ approvedAt: -1 }).limit(3).toArray();
    
    console.log(`\n✅ Found ${approvedLeaves.length} approved leave request(s):`);
    approvedLeaves.forEach((leave, index) => {
      console.log(`\n${index + 1}. Leave Request:`);
      console.log(`   - Customer: ${leave.customerName}`);
      console.log(`   - Period: ${leave.startDate} to ${leave.endDate}`);
      console.log(`   - Approved By: ${leave.approvedBy}`);
      console.log(`   - Approved At: ${leave.approvedAt}`);
      console.log(`   - Affected Trips: ${leave.affectedTripsCount || 0}`);
    });
    
    console.log('\n\n✅ TEST COMPLETE');
    console.log('='.repeat(80));
    console.log('\n📝 SUMMARY:');
    console.log(`   - Admin users in system: ${adminUsers.length}`);
    console.log(`   - Approved leave requests: ${approvedLeaves.length}`);
    console.log('\n💡 NEXT STEPS:');
    console.log('   1. If no notifications found, approve a leave request from client portal');
    console.log('   2. Check admin dashboard notification bell (top right)');
    console.log('   3. Verify notification appears in admin notifications screen');
    console.log('   4. Check "Trip Cancellation Management" screen for approved leaves');
    
  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n🔌 Disconnected from MongoDB\n');
  }
}

testAdminLeaveNotification();
