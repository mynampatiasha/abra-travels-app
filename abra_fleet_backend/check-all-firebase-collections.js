// check-all-firebase-collections.js
// Check all Firebase collections for notifications

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
    process.exit(1);
  }
}

const firestore = admin.firestore();

async function checkAllCollections() {
  try {
    console.log('🔍 Checking all Firebase collections for notifications...\n');
    console.log('='.repeat(80));
    
    // List of possible notification collection names
    const possibleCollections = [
      'notifications',
      'user_notifications',
      'userNotifications',
      'Notifications',
      'fcm_notifications',
      'fcmNotifications',
      'push_notifications',
      'pushNotifications'
    ];
    
    let foundNotifications = false;
    
    for (const collectionName of possibleCollections) {
      try {
        console.log(`\n📂 Checking collection: "${collectionName}"`);
        const snapshot = await firestore.collection(collectionName).limit(5).get();
        
        if (!snapshot.empty) {
          console.log(`   ✅ Found ${snapshot.size} documents (showing first 5)`);
          foundNotifications = true;
          
          snapshot.forEach((doc, index) => {
            const data = doc.data();
            console.log(`\n   ${index + 1}. Document ID: ${doc.id}`);
            console.log(`      Fields: ${Object.keys(data).join(', ')}`);
            if (data.userId || data.uid) {
              console.log(`      User: ${data.userId || data.uid}`);
            }
            if (data.title) {
              console.log(`      Title: ${data.title}`);
            }
            if (data.type) {
              console.log(`      Type: ${data.type}`);
            }
          });
          
          // Get total count
          const allSnapshot = await firestore.collection(collectionName).get();
          console.log(`\n   📊 Total documents in "${collectionName}": ${allSnapshot.size}`);
        } else {
          console.log(`   ❌ Empty or doesn't exist`);
        }
      } catch (error) {
        console.log(`   ❌ Error: ${error.message}`);
      }
    }
    
    console.log('\n' + '='.repeat(80));
    
    if (!foundNotifications) {
      console.log('\n❌ No notifications found in any Firebase collection');
      console.log('\n💡 This means:');
      console.log('   1. Notifications were never stored in Firebase');
      console.log('   2. Notifications were already deleted');
      console.log('   3. Notifications are in a custom collection name');
      console.log('\n📋 Next steps:');
      console.log('   - Check Firebase Console manually');
      console.log('   - Look for any collection with notification-like data');
      console.log('   - If found, update migration script with correct collection name');
    } else {
      console.log('\n✅ Found notifications in Firebase!');
      console.log('\n📋 Next steps:');
      console.log('   1. Note the collection name(s) with notifications');
      console.log('   2. Update migration script if needed');
      console.log('   3. Run: node migrate-firebase-notifications-to-mongodb.js');
    }
    
  } catch (error) {
    console.error('❌ Error checking Firebase collections:', error);
  }
}

checkAllCollections()
  .then(() => process.exit(0))
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
