// send-test-to-deepak-v2.js
// Login as Deepak → call /api/notifications/test → triggers WebSocket + FCM + MongoDB
require('dotenv').config({ path: '.env' });

async function run() {
  const BASE = 'http://localhost:3001';

  // Step 1: Login as Deepak
  console.log('🔐 Logging in as Deepak Joshi...');
  const loginRes = await fetch(`${BASE}/api/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email:    'deepak.joshi@abrafleet.com',
      password: 'abrafleet123',
    }),
  });
  const loginData = await loginRes.json();

  if (!loginData.success) {
    console.error('❌ Login failed:', loginData);
    return;
  }

  const token  = loginData.data?.token || loginData.token;
  const userId = loginData.data?.user?.id || loginData.user?.id;
  console.log('✅ Logged in. User ID:', userId);
  console.log('   Token (first 40):', token.substring(0, 40) + '...');

  // Step 2: Call /api/notifications/test — sends to self (Deepak)
  console.log('\n📤 Sending test notification via /api/notifications/test ...');
  const testRes = await fetch(`${BASE}/api/notifications/test`, {
    method: 'POST',
    headers: {
      'Content-Type':  'application/json',
      'Authorization': `Bearer ${token}`,
    },
  });
  const testData = await testRes.json();
  console.log('✅ /test response:', JSON.stringify(testData, null, 2));

  // Step 3: Also send a custom notification via /api/notifications/send
  console.log('\n📤 Sending custom notification via /api/notifications/send ...');
  const sendRes = await fetch(`${BASE}/api/notifications/send`, {
    method: 'POST',
    headers: {
      'Content-Type':  'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({
      targetUserId:    userId,
      targetUserEmail: 'deepak.joshi@abrafleet.com',
      title:           '🔔 Test Floating Notification',
      body:            'Hello Deepak! This is a live test. If you see this floating banner — push notifications are working! ✅',
      type:            'test',
      priority:        'high',
      data: {
        source: 'manual_test',
        sentAt: new Date().toISOString(),
      },
    }),
  });
  const sendData = await sendRes.json();
  console.log('✅ /send response:', JSON.stringify(sendData, null, 2));

  console.log('\n📋 Done. Check:');
  console.log('   📱 Phone app  → floating banner should appear at top');
  console.log('   🌐 Web app    → floating banner should appear at top');
  console.log('   🔔 Notification bell → should show new unread notification');
}

run().catch(console.error);
