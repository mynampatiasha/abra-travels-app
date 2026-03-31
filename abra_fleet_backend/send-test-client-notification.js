// send-test-client-notification.js
// Send a test notification to client user

require('dotenv').config();
const { MongoClient } = require('mongodb');
const admin = require('./config/firebase');
const { createNotification } = require('./models/notification_model');

const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME = process.env.DB_NAME || 'abra_fleet';

async function sendTestClientNotification() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    console.log('🔌 Connecting to MongoDB...');
    await client.connect();
    const db = client.db(DB_NAME);
    
    // Get client user
    const clientUser = await db.collection('users').findOne({ role: 'client' });
    if (!clientUser) {
      console.log('❌ No client user found!');
      console.log('   Please create a client user first.');
      return;
    }
    
    console.log(`\n✅ Found client: ${clientUser.email}`);
    console.log(`   Firebase UID: ${clientUser.firebaseUid}`);
    
    console.log('\n🔔 Sending test notification to client...\n');
    
    const notification = await createNotification(db, {
      userId: clientUser.firebaseUid,
      type: 'leave_request',
      title: 'New Leave Request',
      body: 'Test Employee has requested leave from Dec 10 to Dec 15, 2025. Please review and approve.',
      priority: 'high',
      category: 'leave_management',
      data: {
        leaveRequestId: 'test_' + Date.now(),
        customerId: 'test_customer',
        customerName: 'Test Employee',
        startDate: '2025-12-10',
        endDate: '2025-12-15'
      }
    });
    
    console.log('✅ Notification sent successfully!');
    console.log(`   Notification ID: ${notification._id}`);
    console.log('\n📝 NEXT STEPS:');
    console.log('   1. Login as client user');
    console.log('   2. Click the notification bell');
    console.log('   3. You should see the notification');
    console.log('   4. Click refresh button to hear sound');
    console.log('   5. Click notification to mark as read');
    
  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n🔌 Disconnected from MongoDB\n');
  }
}

sendTestClientNotification();
