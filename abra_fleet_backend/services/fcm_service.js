// services/fcm_service.js - UNIFIED PUSH NOTIFICATION SERVICE
// Supports: Android (FCM), iOS (APNs), Web Push
// Zero cost, production-ready, scalable

const admin = require('firebase-admin');
const webpush = require('web-push'); // npm install web-push

// ============================================================================
// 🔥 FIREBASE ADMIN INITIALIZATION
// ============================================================================
let firebaseInitialized = false;

function initializeFirebase() {
  if (firebaseInitialized) {
    return admin;
  }

  try {
    const serviceAccount = require('../config/abrafleet-cec94-firebase-adminsdk.json');
    
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      databaseURL: "https://abrafleet-cec94-default-rtdb.firebaseio.com"
    });
    
    firebaseInitialized = true;
    console.log('✅ Firebase Admin SDK initialized successfully');
    return admin;
  } catch (error) {
    console.error('❌ Firebase initialization failed:', error.message);
    throw error;
  }
}

// ============================================================================
// 🌐 WEB PUSH (VAPID) CONFIGURATION
// ============================================================================
// Generate VAPID keys once: webpush.generateVAPIDKeys()
// Store these in .env file
const VAPID_PUBLIC_KEY = process.env.VAPID_PUBLIC_KEY || 'GENERATE_ME';
const VAPID_PRIVATE_KEY = process.env.VAPID_PRIVATE_KEY || 'GENERATE_ME';
const VAPID_SUBJECT = process.env.VAPID_SUBJECT || 'mailto:admin@abrafleet.com';

if (VAPID_PUBLIC_KEY !== 'GENERATE_ME') {
  webpush.setVapidDetails(
    VAPID_SUBJECT,
    VAPID_PUBLIC_KEY,
    VAPID_PRIVATE_KEY
  );
  console.log('✅ Web Push (VAPID) configured');
} else {
  console.log('⚠️  Web Push not configured - set VAPID keys in .env');
}

// ============================================================================
// 🎨 LOGGING UTILITIES
// ============================================================================
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m'
};

function logHeader(title) {
  console.log('\n' + '='.repeat(80));
  console.log(`${colors.bright}${colors.cyan}📤 ${title}${colors.reset}`);
  console.log('='.repeat(80));
}

function logSuccess(message, data = null) {
  console.log(`${colors.green}✅ ${message}${colors.reset}`);
  if (data) console.log(colors.green, data, colors.reset);
}

function logError(message, error = null) {
  console.log(`${colors.red}❌ ${message}${colors.reset}`);
  if (error) console.log(colors.red, error, colors.reset);
}

function logInfo(message, data = null) {
  console.log(`${colors.cyan}ℹ️  ${message}${colors.reset}`);
  if (data) console.log(colors.cyan, JSON.stringify(data, null, 2), colors.reset);
}

// ============================================================================
// 📱 MAIN NOTIFICATION SERVICE CLASS
// ============================================================================
class NotificationService {
  constructor() {
    this.firebase = initializeFirebase();
  }

  // ========================================================================
  // 🚀 UNIFIED SEND METHOD - Auto-detects platform
  // ========================================================================
  async send({
    deviceToken,
    deviceType,        // 'android', 'ios', 'web'
    title,
    body,
    data = {},
    priority = 'high',
    sound = 'default',
    badge = 1,
    clickAction = null
  }) {
    logHeader('SENDING PUSH NOTIFICATION');
    
    try {
      logInfo('Notification Details:', {
        deviceType,
        title,
        priority,
        hasDeviceToken: !!deviceToken
      });

      if (!deviceToken) {
        throw new Error('Device token is required');
      }

      let result;
      
      switch (deviceType.toLowerCase()) {
        case 'android':
          result = await this.sendToAndroid({
            deviceToken, title, body, data, priority, sound, clickAction
          });
          break;
          
        case 'ios':
          result = await this.sendToIOS({
            deviceToken, title, body, data, priority, sound, badge, clickAction
          });
          break;
          
        case 'web':
          result = await this.sendToWeb({
            deviceToken, title, body, data, clickAction
          });
          break;
          
        default:
          throw new Error(`Unsupported device type: ${deviceType}`);
      }

      logSuccess('Push notification sent successfully', result);
      return { success: true, result };
      
    } catch (error) {
      logError('Failed to send push notification', error.message);
      return { success: false, error: error.message };
    }
  }

  // ========================================================================
  // 🤖 ANDROID (FCM) - Firebase Cloud Messaging with HIGH PRIORITY
  // ========================================================================
  async sendToAndroid({
    deviceToken,
    title,
    body,
    data = {},
    priority = 'high',
    sound = 'default',
    clickAction = null
  }) {
    logInfo('Sending to Android via FCM...');

    const message = {
      token: deviceToken,
      notification: {
        title: title,
        body: body,
        sound: sound
      },
      data: {
        ...data,
        click_action: clickAction || 'FLUTTER_NOTIFICATION_CLICK',
        // Add any custom data for navigation
        notificationId: data.notificationId || Date.now().toString(),
        type: data.type || 'general',
        timestamp: new Date().toISOString()
      },
      android: {
        priority: 'high', // 🔥 CRITICAL: High priority for immediate delivery
        notification: {
          sound: sound,
          clickAction: clickAction || 'FLUTTER_NOTIFICATION_CLICK',
          channelId: 'high_priority_channel', // 🔥 CRITICAL: Must match Flutter channel
          color: '#0D47A1',
          icon: 'ic_launcher', // Your app's notification icon
          tag: data.type || 'general', // Groups similar notifications
          priority: 'max', // 🔥 CRITICAL: Max priority for heads-up
          defaultSound: true,
          defaultVibrateTimings: true,
          defaultLightSettings: true,
          visibility: 'public', // Show on lock screen
        },
        ttl: 3600 * 1000, // 1 hour in milliseconds
        collapseKey: data.type || 'default'
      }
    };

    try {
      const response = await admin.messaging().send(message);
      logSuccess('Android FCM sent', { messageId: response });
      return { platform: 'android', messageId: response };
    } catch (error) {
      logError('Android FCM failed', error.message);
      throw error;
    }
  }

  // ========================================================================
  // 🍎 iOS (APNs) - Apple Push Notification service
  // ========================================================================
  async sendToIOS({
    deviceToken,
    title,
    body,
    data = {},
    priority = 'high',
    sound = 'default',
    badge = 1,
    clickAction = null
  }) {
    logInfo('Sending to iOS via APNs...');

    // ⚠️ NOTE: APNs requires Apple Developer Account setup
    // For now, this will use FCM which handles APNs automatically
    // When you add Apple credentials, this will work seamlessly

    const message = {
      token: deviceToken,
      notification: {
        title: title,
        body: body
      },
      data: {
        ...data,
        click_action: clickAction || 'FLUTTER_NOTIFICATION_CLICK',
        notificationId: data.notificationId || Date.now().toString(),
        type: data.type || 'general',
        timestamp: new Date().toISOString()
      },
      apns: {
        headers: {
          'apns-priority': priority === 'high' ? '10' : '5',
          'apns-expiration': (Math.floor(Date.now() / 1000) + 3600).toString()
        },
        payload: {
          aps: {
            alert: {
              title: title,
              body: body
            },
            sound: sound,
            badge: badge,
            'content-available': 1, // Background updates
            'mutable-content': 1,   // For notification extensions
            category: data.type || 'GENERAL'
          },
          // Custom data
          ...data
        }
      }
    };

    try {
      const response = await admin.messaging().send(message);
      logSuccess('iOS APNs sent', { messageId: response });
      return { platform: 'ios', messageId: response };
    } catch (error) {
      logError('iOS APNs failed', error.message);
      
      // If APNs not configured, log helpful message
      if (error.code === 'messaging/invalid-apns-credentials') {
        console.log('');
        console.log('⚠️  APNs not configured yet. To enable iOS push:');
        console.log('   1. Get APNs Auth Key from Apple Developer Portal');
        console.log('   2. Add it to Firebase Console → Project Settings → Cloud Messaging');
        console.log('   3. iOS push will work automatically');
        console.log('');
      }
      
      throw error;
    }
  }

  // ========================================================================
  // 🌐 WEB PUSH - For browser notifications
  // ========================================================================
  async sendToWeb({
    deviceToken, // This is the subscription object from browser
    title,
    body,
    data = {},
    clickAction = null
  }) {
    logInfo('Sending Web Push...');

    if (VAPID_PUBLIC_KEY === 'GENERATE_ME') {
      throw new Error('Web Push not configured - set VAPID keys in .env');
    }

    const payload = JSON.stringify({
      title: title,
      body: body,
      icon: '/icons/notification-icon.png', // Your app icon
      badge: '/icons/badge-icon.png',
      data: {
        ...data,
        url: clickAction || '/',
        timestamp: new Date().toISOString()
      },
      actions: [
        {
          action: 'open',
          title: 'View'
        },
        {
          action: 'close',
          title: 'Close'
        }
      ]
    });

    try {
      // deviceToken for web is the entire subscription object
      const subscription = typeof deviceToken === 'string' 
        ? JSON.parse(deviceToken) 
        : deviceToken;

      const response = await webpush.sendNotification(subscription, payload);
      logSuccess('Web Push sent', { statusCode: response.statusCode });
      return { platform: 'web', statusCode: response.statusCode };
    } catch (error) {
      logError('Web Push failed', error.message);
      throw error;
    }
  }

  // ========================================================================
  // 📊 BULK SEND - Send to multiple devices
  // ========================================================================
  async sendToMultiple({
    devices, // Array of { deviceToken, deviceType }
    title,
    body,
    data = {},
    priority = 'high'
  }) {
    logHeader('SENDING BULK NOTIFICATIONS');
    logInfo(`Sending to ${devices.length} device(s)`);

    const results = {
      success: 0,
      failed: 0,
      errors: []
    };

    // Send in parallel for better performance
    const promises = devices.map(async (device) => {
      try {
        await this.send({
          deviceToken: device.deviceToken,
          deviceType: device.deviceType,
          title,
          body,
          data,
          priority
        });
        results.success++;
      } catch (error) {
        results.failed++;
        results.errors.push({
          device: device.deviceToken.substring(0, 20) + '...',
          error: error.message
        });
      }
    });

    await Promise.all(promises);

    logSuccess(`Bulk send completed: ${results.success} success, ${results.failed} failed`);
    return results;
  }

  // ========================================================================
  // 🎯 SEND BY TOPIC - Send to all subscribers of a topic
  // ========================================================================
  async sendToTopic({
    topic,
    title,
    body,
    data = {},
    priority = 'high'
  }) {
    logHeader('SENDING TOPIC NOTIFICATION');
    logInfo(`Topic: ${topic}`);

    const message = {
      topic: topic,
      notification: {
        title: title,
        body: body
      },
      data: {
        ...data,
        timestamp: new Date().toISOString()
      },
      android: {
        priority: priority,
        notification: {
          channelId: 'high_priority_channel',
          sound: 'default'
        }
      },
      apns: {
        headers: {
          'apns-priority': priority === 'high' ? '10' : '5'
        },
        payload: {
          aps: {
            alert: { title, body },
            sound: 'default'
          }
        }
      }
    };

    try {
      const response = await admin.messaging().send(message);
      logSuccess('Topic notification sent', { messageId: response });
      return { success: true, messageId: response };
    } catch (error) {
      logError('Topic notification failed', error.message);
      throw error;
    }
  }

  // ========================================================================
  // 📌 TOPIC SUBSCRIPTION MANAGEMENT
  // ========================================================================
  async subscribeToTopic(deviceTokens, topic) {
    try {
      const tokens = Array.isArray(deviceTokens) ? deviceTokens : [deviceTokens];
      const response = await admin.messaging().subscribeToTopic(tokens, topic);
      logSuccess(`Subscribed ${response.successCount} devices to topic: ${topic}`);
      return response;
    } catch (error) {
      logError('Topic subscription failed', error.message);
      throw error;
    }
  }

  async unsubscribeFromTopic(deviceTokens, topic) {
    try {
      const tokens = Array.isArray(deviceTokens) ? deviceTokens : [deviceTokens];
      const response = await admin.messaging().unsubscribeFromTopic(tokens, topic);
      logSuccess(`Unsubscribed ${response.successCount} devices from topic: ${topic}`);
      return response;
    } catch (error) {
      logError('Topic unsubscription failed', error.message);
      throw error;
    }
  }
}

// ============================================================================
// 📤 EXPORT SINGLETON INSTANCE
// ============================================================================
const notificationService = new NotificationService();

module.exports = notificationService;
module.exports.NotificationService = NotificationService;

// ============================================================================
// 🔧 VAPID KEY GENERATOR (Run once to generate keys)
// ============================================================================
// Uncomment and run this function ONCE to generate your VAPID keys
// Then add the keys to your .env file

/*
async function generateVAPIDKeys() {
  const vapidKeys = webpush.generateVAPIDKeys();
  console.log('\n' + '='.repeat(80));
  console.log('🔑 GENERATED VAPID KEYS - ADD THESE TO YOUR .env FILE:');
  console.log('='.repeat(80));
  console.log(`VAPID_PUBLIC_KEY=${vapidKeys.publicKey}`);
  console.log(`VAPID_PRIVATE_KEY=${vapidKeys.privateKey}`);
  console.log(`VAPID_SUBJECT=mailto:admin@abrafleet.com`);
  console.log('='.repeat(80) + '\n');
}

// Run this once: generateVAPIDKeys();
*/