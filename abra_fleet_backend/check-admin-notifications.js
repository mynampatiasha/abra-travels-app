// check-admin-notifications.js
// Check if admin users are set up correctly to receive notifications

require('dotenv').config();
const admin = require('./config/firebase');
const { MongoClient } = require('mongodb');

async function checkAdminNotifications() {
  const mongoClient = new MongoClient(process.env.MONGODB_URI);
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🔍 CHECKING ADMIN NOTIFICATION SETUP');
    console.log('='.repeat(80));
    
    await mongoClient.connect();
    const db = mongoClient.db('abrafleet');
    
    // Step 1: Check admin users in MongoDB
    console.log('\n📋 Step 1: Checking admin users in MongoDB...');
    const adminUsers = await db.collection('users').find({ role: 'admin' }).toArray();
    
    console.log(`✅ Found ${adminUsers.length} admin user(s) in MongoDB:`);
    adminUsers.forEach(admin => {
      console.log(`   - ${admin.name || 'Unknown'} (${admin.email})`);
      console.log(`     Firebase UID: ${admin.firebaseUid}`);
      console.log(`     Role: ${admin.role}`);
    });
    
    if (adminUsers.length === 0) {
      console.log('\n❌ ERROR: No admin users found!');
      console.log('   This is why admins are not receiving notifications.');
      console.log('\n💡 Solution: Run fix-admin-role.js to set admin role');
      return;
    }
    
    // Step 2: Check Firebase RTDB notifications for each admin
    console.log('\n📋 Step 2: Checking Firebase RTDB notifications...');
    for (const adminUser of adminUsers) {
      const notificationsRef = admin.database().ref(`notifications/${adminUser.firebaseUid}`);
      const snapshot = await notificationsRef.once('value');
      const notifications = snapshot.val();
      
      if (notifications) {
        const notifArray = Object.values(notifications);
        const leaveNotifs = notifArray.filter(n => n.type === 'leave_approved_admin');
        console.log(`\n   ${adminUser.email}:`);
        console.log(`   - Total notifications: ${notifArray.length}`);
        console.log(`   - Leave approval notifications: ${leaveNotifs.length}`);
        
        if (leaveNotifs.length > 0) {
          console.log(`   - Latest leave notification:`);
          const latest = leaveNotifs[leaveNotifs.length - 1];
          console.log(`     Title: ${latest.title}`);
          console.log(`     Created: ${latest.createdAt}`);
          console.log(`     Read: ${latest.isRead}`);
        }
      } else {
        console.log(`\n   ${adminUser.email}: No notifications in Firebase RTDB`);
      }
    }
    
    // Step 3: Check MongoDB notifications
    console.log('\n📋 Step 3: Checking MongoDB notifications...');
    for (const adminUser of adminUsers) {
      const notifications = await db.collection('notifications').find({
        userId: adminUser.firebaseUid,
        type: 'leave_approved_admin'
      }).sort({ createdAt: -1 }).limit(5).toArray();
      
      console.log(`\n   ${adminUser.email}:`);
      console.log(`   - Leave approval notifications in MongoDB: ${notifications.length}`);
      
      if (notifications.length > 0) {
        console.log(`   - Latest notification:`);
        const latest = notifications[0];
        console.log(`     Title: ${latest.title}`);
        console.log(`     Created: ${latest.createdAt}`);
        console.log(`     Read: ${latest.isRead}`);
      }
    }
    
    // Step 4: Check recent leave approvals
    console.log('\n📋 Step 4: Checking recent leave approvals...');
    const recentApprovals = await db.collection('leave_requests').find({
      status: 'approved'
    }).sort({ approvedAt: -1 }).limit(5).toArray();
    
    console.log(`✅ Found ${recentApprovals.length} recent approved leave request(s):`);
    recentApprovals.forEach(leave => {
      console.log(`\n   - Customer: ${leave.customerName}`);
      console.log(`     Approved by: ${leave.approvedBy}`);
      console.log(`     Approved at: ${leave.approvedAt}`);
      console.log(`     Affected trips: ${leave.affectedTripsCount}`);
    });
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ CHECK COMPLETED');
    console.log('='.repeat(80));
    
    // Summary
    console.log('\n📊 SUMMARY:');
    console.log(`   Admin users in MongoDB: ${adminUsers.length}`);
    console.log(`   Recent leave approvals: ${recentApprovals.length}`);
    
    if (adminUsers.length === 0) {
      console.log('\n❌ ISSUE: No admin users found');
      console.log('   Run: node fix-admin-role.js');
    } else {
      console.log('\n✅ Admin users are configured correctly');
      console.log('   If notifications are not showing, check:');
      console.log('   1. Backend logs when leave is approved');
      console.log('   2. Firebase RTDB console');
      console.log('   3. Admin notification screen filtering');
    }
    
  } catch (error) {
    console.error('❌ Error:', error);
    console.error(error.stack);
  } finally {
    await mongoClient.close();
    process.exit(0);
  }
}

checkAdminNotifications();
