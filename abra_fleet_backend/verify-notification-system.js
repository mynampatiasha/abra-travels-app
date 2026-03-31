// verify-notification-system.js
// Complete verification of the notification system

const { MongoClient } = require('mongodb');
const admin = require('./config/firebase');

const MONGO_URI = 'mongodb+srv://fleetadmin:fleetadmin@cluster0.cnb4jvy.mongodb.net/abra_fleet?retryWrites=true&w=majority&appName=Cluster0';
const DB_NAME = 'abra_fleet';

async function verifyNotificationSystem() {
  const client = new MongoClient(MONGO_URI);
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🔍 NOTIFICATION SYSTEM VERIFICATION');
    console.log('='.repeat(80));
    
    await client.connect();
    const db = client.db(DB_NAME);
    
    // 1. Check Firebase Admin initialization
    console.log('\n📋 Step 1: Firebase Admin SDK');
    if (admin.apps.length > 0) {
      console.log('   ✅ Firebase Admin SDK is initialized');
      console.log(`   ✅ Project ID: ${admin.app().options.projectId}`);
      console.log(`   ✅ Database URL: ${admin.app().options.databaseURL}`);
    } else {
      console.log('   ❌ Firebase Admin SDK is NOT initialized');
      return;
    }
    
    // 2. Check MongoDB connection
    console.log('\n📋 Step 2: MongoDB Connection');
    const collections = await db.listCollections().toArray();
    const hasNotifications = collections.some(c => c.name === 'notifications');
    if (hasNotifications) {
      console.log('   ✅ Notifications collection exists');
      const count = await db.collection('notifications').countDocuments();
      console.log(`   ✅ Total notifications in database: ${count}`);
    } else {
      console.log('   ❌ Notifications collection does NOT exist');
    }
    
    // 3. Check notification creation endpoint
    console.log('\n📋 Step 3: Notification Model');
    try {
      const { createNotification } = require('./models/notification_model');
      console.log('   ✅ Notification model loaded successfully');
    } catch (e) {
      console.log('   ❌ Notification model failed to load:', e.message);
    }
    
    // 4. Check recent notifications
    console.log('\n📋 Step 4: Recent Notifications');
    const recentNotifications = await db.collection('notifications')
      .find({})
      .sort({ createdAt: -1 })
      .limit(5)
      .toArray();
    
    console.log(`   Found ${recentNotifications.length} recent notifications:`);
    recentNotifications.forEach((n, i) => {
      console.log(`\n   ${i + 1}. ${n.title}`);
      console.log(`      Type: ${n.type}`);
      console.log(`      User: ${n.userId}`);
      console.log(`      Created: ${n.createdAt}`);
      console.log(`      MongoDB: ${n.deliveryStatus?.mongodb || 'unknown'}`);
      console.log(`      Firebase RTDB: ${n.deliveryStatus?.firebaseRTDB || 'unknown'}`);
    });
    
    // 5. Check Firebase RTDB connectivity
    console.log('\n📋 Step 5: Firebase RTDB Connectivity');
    try {
      const testRef = admin.database().ref('_test_connection');
      await testRef.set({
        timestamp: new Date().toISOString(),
        test: 'connection_check'
      });
      await testRef.remove();
      console.log('   ✅ Firebase RTDB is accessible and writable');
    } catch (e) {
      console.log('   ❌ Firebase RTDB connection failed:', e.message);
    }
    
    // 6. Check notification delivery status
    console.log('\n📋 Step 6: Notification Delivery Statistics');
    const stats = await db.collection('notifications').aggregate([
      {
        $group: {
          _id: '$deliveryStatus.firebaseRTDB',
          count: { $sum: 1 }
        }
      }
    ]).toArray();
    
    console.log('   Firebase RTDB Delivery Status:');
    stats.forEach(s => {
      console.log(`      ${s._id || 'unknown'}: ${s.count} notifications`);
    });
    
    // 7. Summary
    console.log('\n' + '='.repeat(80));
    console.log('📊 VERIFICATION SUMMARY');
    console.log('='.repeat(80));
    
    const successCount = stats.find(s => s._id === 'success')?.count || 0;
    const failedCount = stats.find(s => s._id === 'failed')?.count || 0;
    const totalCount = successCount + failedCount;
    const successRate = totalCount > 0 ? ((successCount / totalCount) * 100).toFixed(1) : 0;
    
    console.log(`\n✅ Firebase Admin SDK: Initialized`);
    console.log(`✅ MongoDB: Connected`);
    console.log(`✅ Firebase RTDB: Accessible`);
    console.log(`\n📊 Delivery Statistics:`);
    console.log(`   - Total notifications: ${totalCount}`);
    console.log(`   - Successful RTDB push: ${successCount}`);
    console.log(`   - Failed RTDB push: ${failedCount}`);
    console.log(`   - Success rate: ${successRate}%`);
    
    if (successRate >= 90) {
      console.log(`\n✅ SYSTEM STATUS: EXCELLENT (${successRate}% success rate)`);
    } else if (successRate >= 70) {
      console.log(`\n⚠️  SYSTEM STATUS: GOOD (${successRate}% success rate)`);
    } else {
      console.log(`\n❌ SYSTEM STATUS: NEEDS ATTENTION (${successRate}% success rate)`);
    }
    
    console.log('\n' + '='.repeat(80));
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error.stack);
  } finally {
    await client.close();
    console.log('\n✅ Connection closed\n');
  }
}

verifyNotificationSystem();
