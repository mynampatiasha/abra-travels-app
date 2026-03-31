// check-notification-userid.js
// Check if admin notifications have the correct userId field

require('dotenv').config();
const { MongoClient } = require('mongodb');

const MONGODB_URI = process.env.MONGODB_URI;
const DB_NAME = process.env.DB_NAME || 'abra_fleet';
const ADMIN_UID = 'FCxbtU52hQYSATfNDIadNhptkWq2';

async function checkNotificationUserId() {
  const client = new MongoClient(MONGODB_URI);
  
  try {
    await client.connect();
    const db = client.db(DB_NAME);
    
    console.log('🔍 Checking notification userId fields...\n');
    console.log(`Expected Admin UID: ${ADMIN_UID}\n`);
    
    // Get leave_approved_admin notifications
    const notifications = await db.collection('notifications').find({
      type: 'leave_approved_admin'
    }).sort({ createdAt: -1 }).limit(10).toArray();
    
    console.log(`Found ${notifications.length} leave_approved_admin notifications:\n`);
    
    notifications.forEach((notif, index) => {
      console.log(`${index + 1}. Notification ID: ${notif._id}`);
      console.log(`   Title: ${notif.title}`);
      console.log(`   userId: ${notif.userId}`);
      console.log(`   Match: ${notif.userId === ADMIN_UID ? '✅ YES' : '❌ NO'}`);
      console.log(`   Created: ${notif.createdAt}`);
      console.log(`   Read: ${notif.isRead ? 'Yes' : 'No'}`);
      console.log('');
    });
    
    // Count matches
    const matchCount = notifications.filter(n => n.userId === ADMIN_UID).length;
    console.log(`\n📊 Summary:`);
    console.log(`   Total: ${notifications.length}`);
    console.log(`   Matching admin UID: ${matchCount}`);
    console.log(`   Not matching: ${notifications.length - matchCount}`);
    
    if (matchCount === 0) {
      console.log('\n❌ PROBLEM FOUND: No notifications have the correct userId!');
      console.log('   The notifications exist but have wrong userId values.');
    } else if (matchCount < notifications.length) {
      console.log('\n⚠️  PARTIAL PROBLEM: Some notifications have wrong userId.');
    } else {
      console.log('\n✅ All notifications have correct userId.');
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    await client.close();
  }
}

checkNotificationUserId();
