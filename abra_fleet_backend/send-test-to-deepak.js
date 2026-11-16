// send-test-to-deepak.js
// Sends a test floating notification to deepak.joshi@abrafleet.com
// Works via: MongoDB (stored) + WebSocket (real-time if app is open)
// FCM push will fire once they register a device token by logging in

const { MongoClient, ObjectId } = require('mongodb');
require('dotenv').config({ path: '.env' });

async function sendNotification() {
  const client = await MongoClient.connect(process.env.MONGODB_URI);
  const db = client.db('abra_fleet');

  // Deepak's driver record ID
  const userId   = '6958bb76aa7823cfd6ff72d0';
  const userRole = 'driver';
  const userEmail = 'deepak.joshi@abrafleet.com';

  const notification = {
    userId:    userId,
    userEmail: userEmail,
    userRole:  userRole,

    // Notification content
    type:     'test',
    title:    '🔔 Test Notification',
    message:  'Hello Deepak! This is a real-time test notification from Abra Fleet. Floating banner should appear now.',
    body:     'Hello Deepak! This is a real-time test notification from Abra Fleet. Floating banner should appear now.',

    data: {
      type:   'test',
      source: 'manual_test',
      sentAt: new Date().toISOString(),
    },

    priority: 'high',
    category: 'system',
    isRead:   false,
    readAt:   null,

    createdAt:  new Date(),
    updatedAt:  new Date(),
    expiresAt:  new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days

    notificationId: `notif_${Date.now()}_test`,
  };

  // 1. Store in MongoDB
  const result = await db.collection('notifications').insertOne(notification);
  console.log('✅ Notification stored in MongoDB');
  console.log('   Inserted ID:', result.insertedId.toString());

  // 2. Try WebSocket delivery (if backend is running)
  try {
    const http = require('http');
    const payload = JSON.stringify({
      targetUserId:    userId,
      targetUserEmail: userEmail,
      title:           notification.title,
      body:            notification.message,
      type:            'test',
      priority:        'high',
      data:            notification.data,
    });

    // Login first to get a JWT token
    const loginPayload = JSON.stringify({
      email:    'deepak.joshi@abrafleet.com',
      password: 'abrafleet123',
    });

    const loginReq = await fetch('http://localhost:3001/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: loginPayload,
    });
    const loginData = await loginReq.json();

    if (!loginData.success || !loginData.token) {
      console.log('⚠️  Could not login to get JWT. Trying admin login...');
      throw new Error('Login failed: ' + JSON.stringify(loginData));
    }

    const token = loginData.token;
    console.log('✅ Logged in, got JWT token');

    // Send via /api/notifications/test (sends to self)
    const sendRes = await fetch('http://localhost:3001/api/notifications/test', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`,
      },
    });
    const sendData = await sendRes.json();
    console.log('✅ WebSocket + FCM push triggered via /api/notifications/test');
    console.log('   Response:', JSON.stringify(sendData, null, 2));

  } catch (err) {
    console.log('⚠️  WebSocket/API delivery skipped:', err.message);
    console.log('   Notification is saved in MongoDB — will appear when user opens the app.');
  }

  await client.close();
  console.log('\n📋 Summary:');
  console.log('   User:    Deepak Joshi (deepak.joshi@abrafleet.com)');
  console.log('   Role:    driver');
  console.log('   MongoDB: ✅ Saved');
  console.log('   Push:    Will deliver when device token is registered (user logs in on device)');
}

sendNotification().catch(console.error);
