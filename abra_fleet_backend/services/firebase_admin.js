// services/firebase_admin.js - Firebase Admin SDK for Push Notifications
const admin = require('firebase-admin');

let firebaseInitialized = false;

// Initialize Firebase Admin SDK
function initializeFirebase() {
  if (firebaseInitialized) {
    console.log('✅ Firebase Admin already initialized');
    return;
  }

  try {
    // Check if service account file exists
    const serviceAccountPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH || './config/firebase-service-account.json';
    
    try {
      const serviceAccount = require(serviceAccountPath);
      
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
      });
      
      firebaseInitialized = true;
      console.log('✅ Firebase Admin SDK initialized successfully');
    } catch (fileError) {
      console.warn('⚠️  Firebase service account file not found:', serviceAccountPath);
      console.warn('⚠️  Push notifications will be disabled');
      console.warn('💡 To enable: Add firebase-service-account.json to config folder');
    }
  } catch (error) {
    console.error('❌ Firebase Admin initialization error:', error.message);
    console.warn('⚠️  Push notifications will be disabled');
  }
}

/**
 * Send push notification to a user
 * @param {string} userId - User ID or email
 * @param {string} title - Notification title
 * @param {string} message - Notification message
 * @param {object} data - Additional data payload
 * @param {object} db - MongoDB database instance
 */
async function sendPushNotification(userId, title, message, data = {}, db) {
  if (!firebaseInitialized) {
    console.log('⚠️  Firebase not initialized - skipping push notification');
    return { success: false, reason: 'Firebase not initialized' };
  }

  try {
    console.log(`📱 Sending push notification to user: ${userId}`);
    
    // Get user's FCM token from database
    const user = await db.collection('users').findOne({
      $or: [
        { _id: userId },
        { email: userId },
        { uid: userId }
      ]
    });
    
    if (!user) {
      console.log(`⚠️  User not found: ${userId}`);
      return { success: false, reason: 'User not found' };
    }
    
    if (!user.fcmToken) {
      console.log(`⚠️  No FCM token for user: ${user.name || userId}`);
      return { success: false, reason: 'No FCM token' };
    }

    // Prepare notification payload
    const payload = {
      notification: {
        title: title,
        body: message,
      },
      data: {
        ...data,
        timestamp: new Date().toISOString(),
        click_action: 'FLUTTER_NOTIFICATION_CLICK'
      },
      token: user.fcmToken,
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'high_importance_channel'
        }
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1
          }
        }
      }
    };

    // Send notification
    const response = await admin.messaging().send(payload);
    
    console.log(`✅ Push notification sent successfully: ${response}`);
    
    return {
      success: true,
      messageId: response,
      userId: userId,
      userName: user.name
    };
  } catch (error) {
    console.error(`❌ Push notification failed for ${userId}:`, error.message);
    
    // Handle invalid token
    if (error.code === 'messaging/invalid-registration-token' ||
        error.code === 'messaging/registration-token-not-registered') {
      console.log(`🗑️  Removing invalid FCM token for user: ${userId}`);
      
      // Remove invalid token from database
      await db.collection('users').updateOne(
        { $or: [{ _id: userId }, { email: userId }] },
        { $unset: { fcmToken: '' } }
      );
    }
    
    return {
      success: false,
      error: error.message,
      code: error.code
    };
  }
}

/**
 * Send push notification to multiple users
 * @param {Array} userIds - Array of user IDs
 * @param {string} title - Notification title
 * @param {string} message - Notification message
 * @param {object} data - Additional data payload
 * @param {object} db - MongoDB database instance
 */
async function sendBulkPushNotifications(userIds, title, message, data = {}, db) {
  if (!firebaseInitialized) {
    console.log('⚠️  Firebase not initialized - skipping bulk push notifications');
    return { success: false, reason: 'Firebase not initialized' };
  }

  console.log(`📱 Sending bulk push notifications to ${userIds.length} users`);
  
  const results = {
    successful: 0,
    failed: 0,
    errors: []
  };

  for (const userId of userIds) {
    const result = await sendPushNotification(userId, title, message, data, db);
    
    if (result.success) {
      results.successful++;
    } else {
      results.failed++;
      results.errors.push({
        userId: userId,
        reason: result.reason || result.error
      });
    }
  }

  console.log(`✅ Bulk push notifications complete: ${results.successful} sent, ${results.failed} failed`);
  
  return results;
}

/**
 * Update user's FCM token
 * @param {string} userId - User ID
 * @param {string} fcmToken - FCM token
 * @param {object} db - MongoDB database instance
 */
async function updateFCMToken(userId, fcmToken, db) {
  try {
    await db.collection('users').updateOne(
      { $or: [{ _id: userId }, { email: userId }, { uid: userId }] },
      {
        $set: {
          fcmToken: fcmToken,
          fcmTokenUpdatedAt: new Date()
        }
      }
    );
    
    console.log(`✅ FCM token updated for user: ${userId}`);
    return { success: true };
  } catch (error) {
    console.error(`❌ FCM token update failed:`, error);
    return { success: false, error: error.message };
  }
}

module.exports = {
  initializeFirebase,
  sendPushNotification,
  sendBulkPushNotifications,
  updateFCMToken
};
