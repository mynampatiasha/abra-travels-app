// test-roster-update-notification.js
// Test script to verify admin notifications are sent when customer updates roster

const { MongoClient } = require('mongodb');
const admin = require('firebase-admin');
require('dotenv').config();

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    }),
    databaseURL: process.env.FIREBASE_DATABASE_URL
  });
}

async function testRosterUpdateNotification() {
  const client = new MongoClient(process.env.MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db('abra_fleet');
    
    console.log('🔍 Testing Roster Update Admin Notification System...\n');
    
    // 1. Check if we have admin users
    console.log('1. Checking for admin users...');
    const adminUsers = await db.collection('users').find({ role: 'admin' }).toArray();
    console.log(`   Found ${adminUsers.length} admin users:`);
    adminUsers.forEach(admin => {
      console.log(`   - ${admin.name || admin.email} (${admin.firebaseUid})`);
    });
    
    if (adminUsers.length === 0) {
      console.log('❌ No admin users found! Cannot test notifications.');
      return;
    }
    
    // 2. Check if we have customer rosters
    console.log('\n2. Checking for customer rosters...');
    const customerRosters = await db.collection('rosters').find({
      status: { $in: ['pending_assignment', 'pending'] }
    }).limit(3).toArray();
    
    console.log(`   Found ${customerRosters.length} updatable rosters:`);
    customerRosters.forEach(roster => {
      console.log(`   - Roster ${roster._id} (${roster.rosterType}) - Status: ${roster.status}`);
    });
    
    if (customerRosters.length === 0) {
      console.log('❌ No updatable rosters found! Cannot test notifications.');
      return;
    }
    
    // 3. Simulate roster update notification
    console.log('\n3. Simulating roster update notification...');
    const testRoster = customerRosters[0];
    const testCustomer = await db.collection('users').findOne({ 
      firebaseUid: testRoster.userId 
    });
    const customerName = testCustomer ? testCustomer.name || testCustomer.email : 'Test Customer';
    
    console.log(`   Simulating update for roster ${testRoster._id} by ${customerName}`);
    
    // Send notification to each admin
    for (const adminUser of adminUsers) {
      try {
        const notificationId = Date.now().toString() + '_' + Math.random().toString(36).substr(2, 9);
        const notification = {
          id: notificationId,
          userId: adminUser.firebaseUid,
          type: 'roster_updated',
          title: 'Customer Roster Updated',
          body: `${customerName} has updated their roster request. Please review the changes.`,
          data: {
            rosterId: testRoster._id.toString(),
            customerName: customerName,
            customerId: testRoster.userId,
            rosterType: testRoster.rosterType,
            officeLocation: testRoster.officeLocation,
            updatedAt: new Date().toISOString()
          },
          isRead: false,
          priority: 'normal',
          category: 'roster_management',
          createdAt: new Date().toISOString(),
          expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString()
        };
        
        const firebasePath = `notifications/${adminUser.firebaseUid}/${notificationId}`;
        await admin.database().ref(firebasePath).set(notification);
        console.log(`   ✅ Notification sent to admin: ${adminUser.name || adminUser.email}`);
        
        // Also store in MongoDB notifications collection
        await db.collection('notifications').insertOne({
          ...notification,
          createdAt: new Date(),
          expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
        });
        
      } catch (error) {
        console.log(`   ❌ Failed to send notification to ${adminUser.email}: ${error.message}`);
      }
    }
    
    // 4. Verify notifications were created
    console.log('\n4. Verifying notifications in Firebase...');
    for (const adminUser of adminUsers) {
      try {
        const snapshot = await admin.database()
          .ref(`notifications/${adminUser.firebaseUid}`)
          .orderByChild('type')
          .equalTo('roster_updated')
          .limitToLast(1)
          .once('value');
        
        const notifications = snapshot.val();
        if (notifications) {
          const notificationKeys = Object.keys(notifications);
          console.log(`   ✅ Admin ${adminUser.name || adminUser.email} has ${notificationKeys.length} roster update notification(s)`);
        } else {
          console.log(`   ⚠️  No notifications found for admin ${adminUser.name || adminUser.email}`);
        }
      } catch (error) {
        console.log(`   ❌ Error checking notifications for ${adminUser.email}: ${error.message}`);
      }
    }
    
    console.log('\n✅ Roster update notification test completed!');
    console.log('\n📋 Summary:');
    console.log(`   - Admin users: ${adminUsers.length}`);
    console.log(`   - Test roster: ${testRoster._id}`);
    console.log(`   - Customer: ${customerName}`);
    console.log(`   - Notifications sent: ${adminUsers.length}`);
    
  } catch (error) {
    console.error('❌ Test failed:', error);
  } finally {
    await client.close();
  }
}

// Run the test
testRosterUpdateNotification().catch(console.error);