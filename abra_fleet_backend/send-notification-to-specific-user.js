// send-notification-to-specific-user.js
// Clear wrong notifications from client user

require('dotenv').config();
const admin = require('./config/firebase');

const clientUserId = 'bSSJNM9JYafbxwHWgVzejpEiKQV2';

async function clearWrongNotifications() {
  try {
    console.log('🧹 Clearing wrong notifications for client user:', clientUserId);
    
    // Get all notifications for client user
    const notificationsRef = admin.database().ref(`notifications/${clientUserId}`);
    const snapshot = await notificationsRef.once('value');
    
    if (!snapshot.exists()) {
      console.log('✅ No notifications found for client user');
      return;
    }
    
    const notifications = snapshot.val();
    let deletedCount = 0;
    
    // Delete notifications that are NOT meant for client
    const clientNotificationTypes = ['leave_request', 'sos_alert', 'driver_report', 'vehicle_maintenance'];
    
    for (const [notifId, notif] of Object.entries(notifications)) {
      const type = notif.type;
      
      // Delete if it's a customer/admin notification type
      if (!clientNotificationTypes.includes(type)) {
        await notificationsRef.child(notifId).remove();
        console.log(`🗑️  Deleted: ${type} - ${notif.title}`);
        deletedCount++;
      }
    }
    
    console.log(`\n✅ Deleted ${deletedCount} wrong notifications`);
    console.log('\n📝 NEXT STEPS:');
    console.log('   1. Refresh the client notification screen');
    console.log('   2. Only client-relevant notifications should appear');
    
  } catch (error) {
    console.error('❌ ERROR:', error.message);
    console.error(error.stack);
  }
  
  process.exit(0);
}

clearWrongNotifications();
