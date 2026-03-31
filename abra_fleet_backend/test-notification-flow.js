// test-notification-flow.js
// Test the complete notification flow for leave requests

require('dotenv').config();
const { MongoClient } = require('mongodb');
const admin = require('./config/firebase');
const { createNotification } = require('./models/notification_model');

const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME = process.env.DB_NAME || 'abra_fleet';

async function testNotificationFlow() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔌 Connecting to MongoDB...');
    await client.connect();
    const db = client.db(DB_NAME);
    
    console.log('\n📊 TESTING NOTIFICATION FLOW');
    console.log('='.repeat(80));
    
    // Get admin user
    const admin = await db.collection('users').findOne({ role: 'admin' });
    if (!admin) {
      console.log('❌ No admin user found!');
      return;
    }
    
    console.log(`\n✅ Found admin: ${admin.email}`);
    console.log(`   Firebase UID: ${admin.firebaseUid}`);
    
    // Get client user (organization)
    const client = await db.collection('users').findOne({ role: 'client' });
    if (!client) {
      console.log('❌ No client user found!');
      return;
    }
    
    console.log(`\n✅ Found client: ${client.email}`);
    console.log(`   Firebase UID: ${client.firebaseUid}`);
    
    // Test 1: Send leave request notification to client
    console.log('\n\n🧪 TEST 1: Customer submits leave request → Client gets notified');
    console.log('─'.repeat(80));
    
    const leaveRequestNotif = await createNotification(db, {
      userId: client.firebaseUid,
      type: 'leave_request',
      title: 'New Leave Request',
      body: 'John Doe has requested leave from Dec 10 to Dec 15, 2025',
      priority: 'high',
      category: 'leave_management',
      data: {
        leaveRequestId: 'test_leave_123',
        customerId: 'test_customer_456',
        customerName: 'John Doe',
        startDate: '2025-12-10',
        endDate: '2025-12-15'
      }
    });
    
    console.log('✅ Notification sent to client');
    console.log(`   Notification ID: ${leaveRequestNotif._id}`);
    console.log('   Expected behavior:');
    console.log('   - 🔊 Client hears notification sound');
    console.log('   - 📱 Floating card appears on client dashboard');
    console.log('   - 🔴 Badge updates on notification bell');
    
    // Test 2: Send leave approval notification to admin
    console.log('\n\n🧪 TEST 2: Client approves leave → Admin gets notified');
    console.log('─'.repeat(80));
    
    const leaveApprovalNotif = await createNotification(db, {
      userId: admin.firebaseUid,
      type: 'leave_approved_admin',
      title: 'Leave Request Approved - Action Required',
      body: 'Leave request approved for John Doe from Dec 10 to Dec 15. Please cancel the associated trips.',
      priority: 'urgent',
      category: 'leave_management',
      data: {
        leaveRequestId: 'test_leave_123',
        customerId: 'test_customer_456',
        customerName: 'John Doe',
        startDate: '2025-12-10',
        endDate: '2025-12-15',
        affectedTripsCount: 5,
        approvedBy: client.email
      }
    });
    
    console.log('✅ Notification sent to admin');
    console.log(`   Notification ID: ${leaveApprovalNotif._id}`);
    console.log('   Expected behavior:');
    console.log('   - 🔊 Admin hears notification sound');
    console.log('   - 🚨 Floating card appears (orange, urgent)');
    console.log('   - 🔴 Badge updates on notification bell');
    console.log('   - 📋 Badge updates on "Trip Cancellation" menu');
    console.log('   - ✅ Click notification → navigates to Trip Cancellation screen');
    
    // Verify notifications in Firebase RTDB
    console.log('\n\n🔍 VERIFYING FIREBASE REALTIME DATABASE');
    console.log('─'.repeat(80));
    
    const clientNotifRef = admin.database().ref(`notifications/${client.firebaseUid}/${leaveRequestNotif._id}`);
    const clientNotifSnapshot = await clientNotifRef.once('value');
    
    if (clientNotifSnapshot.exists()) {
      console.log('✅ Client notification found in Firebase RTDB');
    } else {
      console.log('❌ Client notification NOT found in Firebase RTDB');
    }
    
    const adminNotifRef = admin.database().ref(`notifications/${admin.firebaseUid}/${leaveApprovalNotif._id}`);
    const adminNotifSnapshot = await adminNotifRef.once('value');
    
    if (adminNotifSnapshot.exists()) {
      console.log('✅ Admin notification found in Firebase RTDB');
    } else {
      console.log('❌ Admin notification NOT found in Firebase RTDB');
    }
    
    console.log('\n\n✅ TEST COMPLETE');
    console.log('='.repeat(80));
    console.log('\n📝 NEXT STEPS:');
    console.log('   1. Login as client user');
    console.log('   2. Check notification bell (should show badge)');
    console.log('   3. Click notification bell → opens notification screen');
    console.log('   4. Verify notification card appears');
    console.log('   5. Click "Mark as Read" → badge decreases');
    console.log('\n   6. Login as admin user');
    console.log('   7. Check notification bell (should show badge)');
    console.log('   8. Check "Trip Cancellation" menu (should show badge)');
    console.log('   9. Click notification → navigates to Trip Cancellation');
    
  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n🔌 Disconnected from MongoDB\n');
  }
}

testNotificationFlow();
