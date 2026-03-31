// check-firebase-notifications.js
// Check if Firebase notifications exist before migration

const admin = require('firebase-admin');
require('dotenv').config();

// Initialize Firebase Admin (if not already initialized)
if (!admin.apps.length) {
  try {
    const serviceAccount = require('./serviceAccountKey.json');
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    console.log('✅ Firebase Admin initialized');
  } catch (error) {
    console.error('❌ Error initializing Firebase Admin:', error.message);
    console.log('\n⚠️  Make sure serviceAccountKey.json exists in abra_fleet_backend folder');
    console.log('   Download it from Firebase Console → Project Settings → Service Accounts');
    process.exit(1);
  }
}

const firestore = admin.firestore();

async function checkFirebaseNotifications() {
  try {
    console.log('🔍 Checking Firebase notifications...\n');
    
    // Check notifications collection
    const snapshot = await firestore.collection('notifications').limit(10).get();
    
    if (snapshot.empty) {
      console.log('❌ No notifications found in Firebase "notifications" collection');
      console.log('\n💡 Possible reasons:');
      console.log('   1. Notifications are in a different collection name');
      console.log('   2. All notifications were already deleted');
      console.log('   3. Notifications were never stored in Firebase');
      return;
    }
    
    console.log(`✅ Found ${snapshot.size} notifications (showing first 10)\n`);
    console.log('Sample notifications:');
    console.log('='.repeat(80));
    
    snapshot.forEach((doc, index) => {
      const data = doc.data();
      console.log(`\n${index + 1}. Notification ID: ${doc.id}`);
      console.log(`   User ID: ${data.userId || data.uid || 'N/A'}`);
      console.log(`   User Role: ${data.userRole || data.role || 'N/A'}`);
      console.log(`   Type: ${data.type || 'N/A'}`);
      console.log(`   Title: ${data.title || 'N/A'}`);
      console.log(`   Message: ${(data.message || data.body || 'N/A').substring(0, 60)}...`);
      console.log(`   Created: ${data.createdAt || data.timestamp || 'N/A'}`);
      console.log(`   Read: ${data.isRead || data.read || false}`);
    });
    
    console.log('\n' + '='.repeat(80));
    
    // Get total count
    const allSnapshot = await firestore.collection('notifications').get();
    console.log(`\n📊 TOTAL NOTIFICATIONS IN FIREBASE: ${allSnapshot.size}`);
    
    // Count by user
    const userCounts = {};
    allSnapshot.forEach(doc => {
      const userId = doc.data().userId || doc.data().uid || 'unknown';
      userCounts[userId] = (userCounts[userId] || 0) + 1;
    });
    
    console.log('\n👥 Notifications by user:');
    Object.entries(userCounts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 10)
      .forEach(([userId, count]) => {
        console.log(`   ${userId}: ${count} notifications`);
      });
    
    console.log('\n✅ Firebase notifications check complete!');
    console.log('\n📋 Next steps:');
    console.log('   1. Run: node migrate-firebase-notifications-to-mongodb.js');
    console.log('   2. Verify: node verify-notification-migration.js');
    
  } catch (error) {
    console.error('❌ Error checking Firebase notifications:', error);
    console.log('\n💡 Troubleshooting:');
    console.log('   - Check if serviceAccountKey.json is valid');
    console.log('   - Check if Firebase project is accessible');
    console.log('   - Check if collection name is "notifications"');
  }
}

checkFirebaseNotifications()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
