// send_test_to_admin_fixed.js - FIXED: Loads .env file
require('dotenv').config(); // ← THIS IS THE FIX!

const notificationService = require('./services/notification_service');

async function sendTestNotification() {
  try {
    console.log('════════════════════════════════════════════════════════════');
    console.log('🧪 SENDING TEST NOTIFICATION TO YOUR ADMIN USER');
    console.log('════════════════════════════════════════════════════════════\n');

    // Check environment variables
    console.log('Environment Check:');
    console.log('   MONGODB_URI:', process.env.MONGODB_URI ? '✓ Loaded' : '✗ Missing');
    console.log('   ONESIGNAL_APP_ID:', process.env.ONESIGNAL_APP_ID ? '✓ Loaded' : '✗ Missing');
    console.log('');

    if (!process.env.MONGODB_URI) {
      console.error('❌ MONGODB_URI not found in .env file!');
      console.error('   Make sure .env file exists in the same directory');
      process.exit(1);
    }

    // YOUR userId from JWT token
    const yourUserId = '6958bb76aa7823cfd6ff72c2';
    const yourRole = 'super_admin';

    console.log('Target User:');
    console.log('   userId:', yourUserId);
    console.log('   role:', yourRole);
    console.log('\n📤 Sending notification...\n');

    // Send notification directly to your userId
    await notificationService.sendRealTimeNotification(
      'admin', // userType
      yourUserId, // YOUR userId
      {
        type: 'system',
        title: '🧪 Direct Test Notification',
        message: 'This notification was sent directly to YOUR userId: ' + yourUserId,
        priority: 'high',
        category: 'test',
        data: {
          testId: Date.now(),
          source: 'direct_test_script',
          targetUserId: yourUserId
        }
      }
    );

    console.log('\n════════════════════════════════════════════════════════════');
    console.log('✅ TEST NOTIFICATION SENT SUCCESSFULLY!');
    console.log('════════════════════════════════════════════════════════════');
    console.log('\nNow:');
    console.log('1. ✓ Check backend logs above for MongoDB verification');
    console.log('2. ✓ Open Flutter app');
    console.log('3. ✓ Click refresh (↻) on notifications screen');
    console.log('4. ✓ You should see 1 notification!');
    console.log('\nIf still not showing:');
    console.log('   → Click the bug icon (🐛) in Flutter app');
    console.log('   → Check diagnostic output');
    console.log('\n');

    // Close connection
    await notificationService.close();
    process.exit(0);

  } catch (error) {
    console.error('\n❌ Error sending test notification:', error.message);
    console.error('\nStack trace:', error.stack);
    process.exit(1);
  }
}

// Run it
sendTestNotification();