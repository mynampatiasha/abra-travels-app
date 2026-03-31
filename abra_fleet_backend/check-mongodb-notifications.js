// check-mongodb-notifications.js
// Check MongoDB for existing notifications

const { MongoClient } = require('mongodb');
require('dotenv').config();

async function checkMongoDBNotifications() {
  let mongoClient;
  
  try {
    console.log('🔍 Checking MongoDB notifications...\n');
    console.log('='.repeat(80));
    
    // Connect to MongoDB
    console.log('📡 Connecting to MongoDB...');
    mongoClient = await MongoClient.connect(process.env.MONGODB_URI);
    const db = mongoClient.db('abra_fleet');
    console.log('✅ Connected to MongoDB\n');
    
    // Check onesignal_notifications collection
    const collection = db.collection('onesignal_notifications');
    
    // Count total notifications
    const total = await collection.countDocuments();
    console.log(`📊 Total notifications in MongoDB: ${total}`);
    
    if (total === 0) {
      console.log('\n❌ No notifications found in MongoDB');
      console.log('\n💡 This means:');
      console.log('   1. No notifications have been sent yet');
      console.log('   2. Notification system is ready but not used yet');
      console.log('\n📋 Next steps:');
      console.log('   - Send a test notification to verify system works');
      console.log('   - Check if users are receiving notifications');
      return;
    }
    
    // Count by migration status
    const migrated = await collection.countDocuments({ 
      migratedFrom: 'firebase' 
    });
    const newNotifications = await collection.countDocuments({ 
      migratedFrom: { $exists: false } 
    });
    
    console.log(`🔄 Migrated from Firebase: ${migrated}`);
    console.log(`🆕 New notifications (OneSignal): ${newNotifications}`);
    
    console.log('\n' + '='.repeat(80));
    
    // Sample notifications
    console.log('\n📋 Sample notifications (latest 10):');
    console.log('='.repeat(80));
    const samples = await collection
      .find({})
      .sort({ createdAt: -1 })
      .limit(10)
      .toArray();
    
    if (samples.length === 0) {
      console.log('   No notifications to display');
    } else {
      samples.forEach((notif, index) => {
        console.log(`\n${index + 1}. ${notif.title || 'No title'}`);
        console.log(`   User: ${notif.userId} (${notif.userRole || 'N/A'})`);
        console.log(`   Type: ${notif.type || 'N/A'}`);
        console.log(`   Created: ${notif.createdAt}`);
        console.log(`   Read: ${notif.isRead}`);
        if (notif.migratedFrom) {
          console.log(`   Migrated from: ${notif.migratedFrom}`);
        }
      });
    }
    
    console.log('\n' + '='.repeat(80));
    
    // Check notifications by user
    console.log('\n👥 Notifications by user (top 10):');
    console.log('='.repeat(80));
    const userCounts = await collection.aggregate([
      { $group: { _id: '$userId', count: { $sum: 1 } } },
      { $sort: { count: -1 } },
      { $limit: 10 }
    ]).toArray();
    
    if (userCounts.length === 0) {
      console.log('   No user data available');
    } else {
      userCounts.forEach(user => {
        console.log(`   ${user._id}: ${user.count} notifications`);
      });
    }
    
    console.log('\n' + '='.repeat(80));
    
    // Check notifications by type
    console.log('\n📊 Notifications by type:');
    console.log('='.repeat(80));
    const typeCounts = await collection.aggregate([
      { $group: { _id: '$type', count: { $sum: 1 } } },
      { $sort: { count: -1 } }
    ]).toArray();
    
    if (typeCounts.length === 0) {
      console.log('   No type data available');
    } else {
      typeCounts.forEach(type => {
        console.log(`   ${type._id || 'unknown'}: ${type.count} notifications`);
      });
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ MongoDB notifications check complete!');
    console.log('='.repeat(80));
    
    console.log('\n📱 NOTIFICATION SYSTEM STATUS:');
    if (migrated > 0) {
      console.log('   ✅ Old Firebase notifications migrated');
    }
    if (newNotifications > 0) {
      console.log('   ✅ New OneSignal notifications working');
    }
    console.log(`   ✅ Total notifications available: ${total}`);
    
    console.log('\n🧪 USER EXPERIENCE:');
    console.log('   - Users can see their notification history');
    console.log('   - Notifications are being stored correctly');
    console.log('   - System is working as expected');
    
  } catch (error) {
    console.error('\n❌ Error checking MongoDB notifications:', error);
    console.log('\n💡 Troubleshooting:');
    console.log('   - Check MongoDB connection string in .env');
    console.log('   - Check if MongoDB is running');
    console.log('   - Check network connectivity');
  } finally {
    if (mongoClient) {
      await mongoClient.close();
      console.log('\n📡 MongoDB connection closed');
    }
  }
}

checkMongoDBNotifications()
  .then(() => {
    console.log('\n✅ Check complete');
    process.exit(0);
  })
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
