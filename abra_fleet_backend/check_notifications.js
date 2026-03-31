// check_notifications_fixed.js - FIXED: Loads .env file
require('dotenv').config(); // ← THIS IS THE FIX!

const { MongoClient, ObjectId } = require('mongodb');

async function checkNotifications() {
  try {
    console.log('════════════════════════════════════════════════════════════');
    console.log('🔍 CHECKING NOTIFICATION DATABASE');
    console.log('════════════════════════════════════════════════════════════\n');

    console.log('Environment Check:');
    console.log('   MONGODB_URI:', process.env.MONGODB_URI ? '✓ Loaded' : '✗ Missing');
    console.log('');

    if (!process.env.MONGODB_URI) {
      console.error('❌ MONGODB_URI not found in .env file!');
      process.exit(1);
    }

    const client = await MongoClient.connect(process.env.MONGODB_URI);
    const db = client.db('abra_fleet');

    // 1. Total count
    const total = await db.collection('notifications').countDocuments();
    console.log('1️⃣ TOTAL NOTIFICATIONS IN DATABASE:', total);

    if (total === 0) {
      console.log('\n❌ NO NOTIFICATIONS IN DATABASE!');
      console.log('   → Run send_test_to_admin_fixed.js to create one');
      await client.close();
      process.exit(0);
    }

    // 2. Check what userIds exist
    const userIds = await db.collection('notifications').distinct('userId');
    console.log('\n2️⃣ UNIQUE USER IDs IN NOTIFICATIONS:', userIds.length);
    console.log('Sample userIds:');
    userIds.slice(0, 10).forEach((id, index) => {
      console.log(`   ${index + 1}. ${id} (type: ${typeof id})`);
    });

    // 3. Your specific userId
    const yourUserId = '6958bb76aa7823cfd6ff72c2';
    console.log('\n3️⃣ YOUR USER ID:', yourUserId);
    console.log('Type:', typeof yourUserId);
    console.log('Does it exist in list?', userIds.includes(yourUserId) ? '✅ YES' : '❌ NO');

    // 4. Check if your userId exists in notifications
    const yourNotifications = await db.collection('notifications').find({
      userId: yourUserId
    }).toArray();
    console.log('\n4️⃣ NOTIFICATIONS FOR YOUR USER ID:', yourNotifications.length);

    if (yourNotifications.length > 0) {
      console.log('✅ Found notifications! First one:');
      console.log(JSON.stringify(yourNotifications[0], null, 2));
    } else {
      console.log('❌ NO NOTIFICATIONS found for your userId');
      
      // Check if we can find with super_admin role
      const roleNotifications = await db.collection('notifications').find({
        userRole: 'super_admin'
      }).toArray();
      console.log('\n5️⃣ NOTIFICATIONS FOR super_admin ROLE:', roleNotifications.length);
      
      if (roleNotifications.length > 0) {
        console.log('Sample notification for super_admin:');
        console.log(JSON.stringify(roleNotifications[0], null, 2));
      }

      // Check admin role
      const adminNotifications = await db.collection('notifications').find({
        userRole: 'admin'
      }).toArray();
      console.log('\n6️⃣ NOTIFICATIONS FOR admin ROLE:', adminNotifications.length);
      
      if (adminNotifications.length > 0) {
        console.log('Sample notification for admin:');
        console.log(JSON.stringify(adminNotifications[0], null, 2));
      }
    }

    // 7. Show sample of what exists
    console.log('\n7️⃣ SAMPLE NOTIFICATIONS (first 5):');
    const samples = await db.collection('notifications')
      .find({})
      .sort({ createdAt: -1 })
      .limit(5)
      .toArray();

    samples.forEach((notif, index) => {
      console.log(`\n   Notification ${index + 1}:`);
      console.log('      _id:', notif._id);
      console.log('      userId:', notif.userId, '(type:', typeof notif.userId + ')');
      console.log('      userRole:', notif.userRole);
      console.log('      type:', notif.type);
      console.log('      title:', notif.title);
      console.log('      createdAt:', notif.createdAt);
      console.log('      Match your userId?', notif.userId === yourUserId ? '✅ YES' : '❌ NO');
    });

    await client.close();

    console.log('\n════════════════════════════════════════════════════════════');
    console.log('🎯 DIAGNOSIS:');
    console.log('════════════════════════════════════════════════════════════');
    
    if (yourNotifications.length > 0) {
      console.log('✅ YOU HAVE NOTIFICATIONS IN DATABASE');
      console.log(`   → Found ${yourNotifications.length} notification(s)`);
      console.log('   → Problem is in frontend or API query');
      console.log('   → Run diagnostic in Flutter app (🐛 icon)');
    } else {
      console.log('⚠️  NO NOTIFICATIONS FOR YOUR USER ID');
      console.log('   → Notifications exist but for different userIds');
      console.log('   → Run: node send_test_to_admin_fixed.js');
      console.log('   → This will create notification for your userId');
    }
    console.log('════════════════════════════════════════════════════════════\n');

  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error('Stack:', error.stack);
    process.exit(1);
  }
}

checkNotifications();