// test-admin-notifications-api.js
// Test the /api/notifications endpoint for admin user

require('dotenv').config();
const admin = require('firebase-admin');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(require('./serviceAccountKey.json')),
    databaseURL: 'https://abrafleet-cec94-default-rtdb.firebaseio.com'
  });
}

const ADMIN_UID = 'FCxbtU52hQYSATfNDIadNhptkWq2'; // admin@abrafleet.com

async function testAdminNotificationsAPI() {
  try {
    console.log('🔍 Testing Admin Notifications API...\n');
    console.log(`Admin UID: ${ADMIN_UID}\n`);
    
    // Generate a custom token for the admin
    console.log('🔑 Generating custom token...');
    const customToken = await admin.auth().createCustomToken(ADMIN_UID);
    console.log('✅ Custom token generated\n');
    
    // Exchange custom token for ID token
    console.log('🔄 Exchanging for ID token...');
    const fetch = (await import('node-fetch')).default;
    const API_KEY = process.env.FIREBASE_API_KEY || 'AIzaSyBqLqLqLqLqLqLqLqLqLqLqLqLqLqLqLqL';
    
    const authResponse = await fetch(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${API_KEY}`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: customToken, returnSecureToken: true })
      }
    );
    
    const authData = await authResponse.json();
    
    if (!authData.idToken) {
      console.error('❌ Failed to get ID token:', authData);
      return;
    }
    
    const idToken = authData.idToken;
    console.log('✅ ID token obtained\n');
    
    // Call the notifications API
    console.log('📡 Calling /api/notifications endpoint...');
    const BASE_URL = process.env.BASE_URL || 'http://localhost:5000';
    
    const notificationsResponse = await fetch(
      `${BASE_URL}/api/notifications?limit=50`,
      {
        headers: {
          'Authorization': `Bearer ${idToken}`,
          'Content-Type': 'application/json'
        }
      }
    );
    
    console.log(`   Status: ${notificationsResponse.status}`);
    
    const notificationsData = await notificationsResponse.json();
    
    if (notificationsData.success) {
      const notifications = notificationsData.data.notifications;
      const pagination = notificationsData.data.pagination;
      
      console.log(`✅ API returned ${notifications.length} notifications\n`);
      console.log('📊 Pagination:', pagination);
      console.log('\n📋 Notifications by type:');
      
      const typeCount = {};
      notifications.forEach(notif => {
        const type = notif.type || 'unknown';
        typeCount[type] = (typeCount[type] || 0) + 1;
      });
      
      Object.entries(typeCount).forEach(([type, count]) => {
        console.log(`   - ${type}: ${count}`);
      });
      
      // Show leave_approved_admin notifications
      const leaveNotifications = notifications.filter(n => n.type === 'leave_approved_admin');
      
      console.log(`\n🔔 Leave Approval Notifications (${leaveNotifications.length}):`);
      leaveNotifications.forEach((notif, index) => {
        console.log(`\n   ${index + 1}. ${notif.title}`);
        console.log(`      - Body: ${notif.body}`);
        console.log(`      - Read: ${notif.isRead ? 'Yes' : 'No'}`);
        console.log(`      - Created: ${notif.createdAt}`);
        console.log(`      - Priority: ${notif.priority}`);
        if (notif.data) {
          console.log(`      - Customer: ${notif.data.customerName}`);
          console.log(`      - Affected Trips: ${notif.data.affectedTripsCount}`);
        }
      });
      
      if (leaveNotifications.length === 0) {
        console.log('   ❌ No leave approval notifications found!');
        console.log('   This is the problem - notifications are in MongoDB but not being returned by API');
      }
      
    } else {
      console.error('❌ API returned error:', notificationsData);
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error.stack);
  } finally {
    process.exit(0);
  }
}

testAdminNotificationsAPI();
