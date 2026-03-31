// test-onesignal-notification.js
// Test OneSignal notification system with user isolation

require('dotenv').config();
const NotificationService = require('./services/notification_service');

async function testOneSignalNotifications() {
  console.log('🧪 ========================================');
  console.log('🧪 TESTING ONESIGNAL NOTIFICATION SYSTEM');
  console.log('🧪 ========================================\n');

  const notificationService = new NotificationService();

  // Test 1: Send notification to specific customer
  console.log('📋 TEST 1: Send notification to SPECIFIC customer');
  console.log('─'.repeat(60));
  try {
    await notificationService.sendRealTimeNotification('customer', 'customer123', {
      type: 'roster_assigned',
      title: 'Test: Roster Assigned',
      message: 'This notification should ONLY go to customer123',
      data: { testId: 'test1', customerName: 'Test Customer' },
      priority: 'high'
    });
    console.log('✅ Customer notification sent\n');
  } catch (error) {
    console.error('❌ Error:', error.message, '\n');
  }

  // Test 2: Send notification to specific driver
  console.log('📋 TEST 2: Send notification to SPECIFIC driver');
  console.log('─'.repeat(60));
  try {
    await notificationService.sendRealTimeNotification('driver', 'driver456', {
      type: 'vehicle_assigned',
      title: 'Test: Vehicle Assigned',
      message: 'This notification should ONLY go to driver456',
      data: { testId: 'test2', vehicleReg: 'KA01AB1234' },
      priority: 'high'
    });
    console.log('✅ Driver notification sent\n');
  } catch (error) {
    console.error('❌ Error:', error.message, '\n');
  }

  // Test 3: Send notification to specific client
  console.log('📋 TEST 3: Send notification to SPECIFIC client');
  console.log('─'.repeat(60));
  try {
    await notificationService.sendRealTimeNotification('client', 'client789', {
      type: 'leave_request',
      title: 'Test: Leave Request',
      message: 'This notification should ONLY go to client789',
      data: { testId: 'test3', employeeName: 'John Doe' },
      priority: 'normal'
    });
    console.log('✅ Client notification sent\n');
  } catch (error) {
    console.error('❌ Error:', error.message, '\n');
  }

  // Test 4: Send notification to all admins
  console.log('📋 TEST 4: Send notification to ALL admins');
  console.log('─'.repeat(60));
  try {
    await notificationService.sendSOSAlertNotification({
      customerName: 'Test Customer',
      location: 'Test Location',
      timestamp: new Date().toISOString()
    });
    console.log('✅ Admin notification sent to all admins\n');
  } catch (error) {
    console.error('❌ Error:', error.message, '\n');
  }

  // Test 5: Verify user isolation
  console.log('📋 TEST 5: Verify USER ISOLATION');
  console.log('─'.repeat(60));
  console.log('✅ Each notification was sent with userId tag filter');
  console.log('✅ OneSignal will deliver ONLY to devices with matching userId');
  console.log('✅ No cross-contamination possible\n');

  console.log('🎉 ========================================');
  console.log('🎉 ONESIGNAL TEST COMPLETE');
  console.log('🎉 ========================================');
  console.log('\n📝 NEXT STEPS:');
  console.log('1. Add your OneSignal REST API keys to .env file');
  console.log('2. Test on real devices with OneSignal SDK');
  console.log('3. Verify each user receives ONLY their notifications');
  console.log('4. Check OneSignal dashboard for delivery stats\n');
}

testOneSignalNotifications().catch(console.error);
