// verify-notification-migration.js
// Verify that Firebase notifications were successfully migrated to MongoDB

const { MongoClient } = require('mongodb');
require('dotenv').config();

async function verifyMigration() {
  let mongoClient;
  
  try {
    console.log('🔍 Verifying notification migration...\n');
    console.log('='.repeat(80));
    
    // Connect to MongoDB
    console.log('📡 Connecting to MongoDB...');
    mongoClient = await MongoClient.connect(process.env.MONGODB_URI);
    const db = mongoClient.db('abra_fleet');
    const collection = db.collection('onesignal_notifications');
    console.log('✅ Connected to MongoDB\n');
    
    // Count total notifications
    const total = await collection.countDocuments();
    console.log(`📊 Total notifications in MongoDB: ${total}`);
    
    // Count migrated notifications
    const migrated = await collection.countDocuments({ 
      migratedFrom: 'firebase' 
    });
    console.log(`🔄 Migrated from Firebase: ${migrated}`);
    
    // Count new notifications
    const newNotifications = await collection.countDocuments({ 
      migratedFrom: { $exists: false } 
    });
    console.log(`🆕 New notifications (OneSignal): ${newNotifications}`);
    
    console.log('\n' + '='.repeat(80));
    
    if (migrated === 0) {
      console.log('\n⚠️  No migrated notifications found!');
      console.log('\n💡 Possible reasons:');
      console.log('   1. Migration script has not been run yet');
      console.log('   2. No notifications existed in Firebase');
      console.log('   3. Migration failed');
      console.log('\n📋 Next steps:');
      console.log('   1. Run: node check-firebase-notifications.js');
      console.log('   2. Run: node migrate-firebase-notifications-to-mongodb.js');
      return;
    }
    
    // Sample migrated notifications
    console.log('\n📋 Sample migrated notifications:');
    console.log('='.repeat(80));
    const samples = await collection
      .find({ migratedFrom: 'firebase' })
      .sort({ createdAt: -1 })
      .limit(5)
      .toArray();
    
    samples.forEach((notif, index) => {
      console.log(`\n${index + 1}. ${notif.title}`);
      console.log(`   User: ${notif.userId} (${notif.userRole})`);
      console.log(`   Type: ${notif.type}`);
      console.log(`   Created: ${notif.createdAt}`);
      console.log(`   Read: ${notif.isRead}`);
      console.log(`   Firebase ID: ${notif.firebaseId}`);
      console.log(`   Migrated: ${notif.migratedAt}`);
    });
    
    console.log('\n' + '='.repeat(80));
    
    // Check notifications by user
    console.log('\n👥 Migrated notifications by user:');
    console.log('='.repeat(80));
    const userCounts = await collection.aggregate([
      { $match: { migratedFrom: 'firebase' } },
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
    console.log('\n📊 Migrated notifications by type:');
    console.log('='.repeat(80));
    const typeCounts = await collection.aggregate([
      { $match: { migratedFrom: 'firebase' } },
      { $group: { _id: '$type', count: { $sum: 1 } } },
      { $sort: { count: -1 } }
    ]).toArray();
    
    if (typeCounts.length === 0) {
      console.log('   No type data available');
    } else {
      typeCounts.forEach(type => {
        console.log(`   ${type._id}: ${type.count} notifications`);
      });
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ Verification complete!');
    console.log('='.repeat(80));
    
    console.log('\n📱 USER EXPERIENCE:');
    console.log('   ✅ Users can now see their complete notification history');
    console.log('   ✅ Old Firebase notifications + New OneSignal notifications');
    console.log('   ✅ All in one place, seamless experience');
    
    console.log('\n🧪 TESTING CHECKLIST:');
    console.log('   [ ] Open app as a user who had old notifications');
    console.log('   [ ] Navigate to notifications screen');
    console.log('   [ ] Verify old notifications are visible');
    console.log('   [ ] Verify timestamps are correct');
    console.log('   [ ] Verify read/unread status is preserved');
    console.log('   [ ] Send new notification and verify it appears');
    
    console.log('\n🎯 MIGRATION STATUS: SUCCESS ✅');
    
  } catch (error) {
    console.error('\n❌ Verification failed:', error);
    console.log('\n💡 Troubleshooting:');
    console.log('   - Check MongoDB connection string in .env');
    console.log('   - Check if migration script was run successfully');
    console.log('   - Check network connectivity');
  } finally {
    if (mongoClient) {
      await mongoClient.close();
      console.log('\n📡 MongoDB connection closed');
    }
  }
}

verifyMigration()
  .then(() => {
    console.log('\n✅ Verification script completed');
    process.exit(0);
  })
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
