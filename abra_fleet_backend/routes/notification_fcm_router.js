// routes/notification_router.js - COMPLETE NOTIFICATION API
// Handles: Device Registration, Push Sending, Notification History

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const notificationService = require('../services/fcm_service');

// ============================================================================
// 📱 REGISTER DEVICE TOKEN
// ============================================================================
// @route   POST /api/notifications/register-device
// @desc    Register or update device token for push notifications
// @access  Private
router.post('/register-device', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📱 DEVICE TOKEN REGISTRATION');
    console.log('='.repeat(80));

    const {
      deviceToken,
      deviceType,    // 'android', 'ios', 'web'
      deviceInfo = {}
    } = req.body;

    const userId = req.user.userId;
    const userEmail = req.user.email;

    // Validation
    if (!deviceToken) {
      return res.status(400).json({
        success: false,
        message: 'Device token is required'
      });
    }

    if (!['android', 'ios', 'web'].includes(deviceType?.toLowerCase())) {
      return res.status(400).json({
        success: false,
        message: 'Invalid device type. Must be: android, ios, or web'
      });
    }

    console.log('User:', userId, userEmail);
    console.log('Device Type:', deviceType);
    console.log('Token Preview:', deviceToken.substring(0, 30) + '...');

    // Check if device already registered
    const existingDevice = await req.db.collection('user_devices').findOne({
      userId: userId,
      deviceToken: deviceToken
    });

    const deviceData = {
      userId: userId,
      userEmail: userEmail,
      deviceToken: deviceToken,
      deviceType: deviceType.toLowerCase(),
      deviceInfo: {
        model: deviceInfo.model || 'Unknown',
        os: deviceInfo.os || deviceType,
        osVersion: deviceInfo.osVersion || 'Unknown',
        appVersion: deviceInfo.appVersion || '1.0.0',
        ...deviceInfo
      },
      isActive: true,
      lastSeen: new Date(),
      registeredAt: existingDevice ? existingDevice.registeredAt : new Date(),
      updatedAt: new Date()
    };

    let result;
    if (existingDevice) {
      // Update existing device
      result = await req.db.collection('user_devices').updateOne(
        { _id: existingDevice._id },
        { $set: deviceData }
      );
      console.log('✅ Device token updated');
    } else {
      // Register new device
      result = await req.db.collection('user_devices').insertOne(deviceData);
      console.log('✅ New device registered');
    }

    // Optional: Subscribe to user-specific topic
    try {
      await notificationService.subscribeToTopic(deviceToken, `user_${userId}`);
      console.log(`✅ Subscribed to topic: user_${userId}`);
    } catch (topicError) {
      console.log('⚠️  Topic subscription failed:', topicError.message);
    }

    console.log('='.repeat(80) + '\n');

    res.json({
      success: true,
      message: existingDevice ? 'Device token updated' : 'Device registered successfully',
      data: {
        deviceId: existingDevice?._id || result.insertedId,
        deviceType: deviceType.toLowerCase(),
        registeredAt: deviceData.registeredAt,
        topic: `user_${userId}`
      }
    });

  } catch (error) {
    console.error('❌ Device registration failed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to register device',
      error: error.message
    });
  }
});

// ============================================================================
// 🔕 UNREGISTER DEVICE
// ============================================================================
// @route   DELETE /api/notifications/unregister-device
// @desc    Remove device token (on logout or app uninstall)
// @access  Private
router.delete('/unregister-device', verifyToken, async (req, res) => {
  try {
    const { deviceToken } = req.body;
    const userId = req.user.userId;

    if (!deviceToken) {
      return res.status(400).json({
        success: false,
        message: 'Device token is required'
      });
    }

    console.log('🔕 Unregistering device:', deviceToken.substring(0, 30) + '...');

    // Mark device as inactive
    const result = await req.db.collection('user_devices').updateOne(
      { userId: userId, deviceToken: deviceToken },
      { $set: { isActive: false, unregisteredAt: new Date() } }
    );

    // Unsubscribe from topics
    try {
      await notificationService.unsubscribeFromTopic(deviceToken, `user_${userId}`);
    } catch (error) {
      console.log('⚠️  Topic unsubscription failed:', error.message);
    }

    res.json({
      success: true,
      message: 'Device unregistered successfully',
      data: { modified: result.modifiedCount }
    });

  } catch (error) {
    console.error('❌ Device unregistration failed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to unregister device',
      error: error.message
    });
  }
});

// ============================================================================
// 📤 SEND NOTIFICATION TO USER
// ============================================================================
// @route   POST /api/notifications/send
// @desc    Send push notification to specific user
// @access  Private (Admin)
router.post('/send', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📤 SENDING NOTIFICATION');
    console.log('='.repeat(80));

    const {
      targetUserId,    // Required
      targetUserEmail, // Optional (for fallback lookup)
      title,           // Required
      body,            // Required
      type = 'general',
      data = {},
      priority = 'high',
      clickAction = null
    } = req.body;

    // Validation
    if (!targetUserId || !title || !body) {
      return res.status(400).json({
        success: false,
        message: 'targetUserId, title, and body are required'
      });
    }

    console.log('Target User:', targetUserId);
    console.log('Title:', title);
    console.log('Type:', type);

    // Get all active devices for this user
    const devices = await req.db.collection('user_devices').find({
      userId: targetUserId,
      isActive: true
    }).toArray();

    if (devices.length === 0) {
      console.log('⚠️  No active devices found for user');
      
      // Still save notification to database
      await saveNotificationToDatabase(req.db, {
        userId: targetUserId,
        userEmail: targetUserEmail,
        title,
        body,
        type,
        data,
        priority,
        deliveryStatus: 'no_devices'
      });

      return res.json({
        success: true,
        message: 'Notification saved but no active devices found',
        data: {
          saved: true,
          devicesSent: 0,
          devicesFound: 0
        }
      });
    }

    console.log(`✅ Found ${devices.length} active device(s)`);

    // Send to all user's devices
    const sendResults = await notificationService.sendToMultiple({
      devices: devices.map(d => ({
        deviceToken: d.deviceToken,
        deviceType: d.deviceType
      })),
      title,
      body,
      data: {
        ...data,
        type: type,
        userId: targetUserId,
        timestamp: new Date().toISOString()
      },
      priority,
      clickAction
    });

    // Save notification to database
    const savedNotification = await saveNotificationToDatabase(req.db, {
      userId: targetUserId,
      userEmail: targetUserEmail,
      title,
      body,
      type,
      data,
      priority,
      deliveryStatus: sendResults.success > 0 ? 'sent' : 'failed',
      devicesSent: sendResults.success,
      devicesFailed: sendResults.failed
    });

    console.log('='.repeat(80) + '\n');

    res.json({
      success: true,
      message: 'Notification sent successfully',
      data: {
        notificationId: savedNotification._id,
        devicesSent: sendResults.success,
        devicesFailed: sendResults.failed,
        totalDevices: devices.length,
        errors: sendResults.errors
      }
    });

  } catch (error) {
    console.error('❌ Send notification failed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to send notification',
      error: error.message
    });
  }
});

// ============================================================================
// 📢 SEND BROADCAST NOTIFICATION
// ============================================================================
// @route   POST /api/notifications/broadcast
// @desc    Send notification to all users or specific role
// @access  Private (Admin)
router.post('/broadcast', verifyToken, async (req, res) => {
  try {
    // Check if user is admin
    if (!['admin', 'super_admin'].includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        message: 'Only admins can send broadcast notifications'
      });
    }

    const {
      title,
      body,
      targetRole = null, // Optional: 'driver', 'customer', 'admin', null for all
      type = 'broadcast',
      data = {},
      priority = 'normal'
    } = req.body;

    console.log('\n' + '='.repeat(80));
    console.log('📢 BROADCASTING NOTIFICATION');
    console.log('='.repeat(80));
    console.log('Target Role:', targetRole || 'ALL USERS');
    console.log('Title:', title);

    // Build user filter
    const userFilter = { status: 'active' };
    if (targetRole) {
      userFilter.role = targetRole;
    }

    // Get target users
    const users = await req.db.collection('users').find(userFilter).toArray();
    console.log(`✅ Found ${users.length} target user(s)`);

    // Get all active devices for these users
    const userIds = users.map(u => u._id.toString());
    const devices = await req.db.collection('user_devices').find({
      userId: { $in: userIds },
      isActive: true
    }).toArray();

    console.log(`✅ Found ${devices.length} active device(s)`);

    if (devices.length === 0) {
      return res.json({
        success: true,
        message: 'No active devices found',
        data: { devicesSent: 0 }
      });
    }

    // Send to all devices
    const sendResults = await notificationService.sendToMultiple({
      devices: devices.map(d => ({
        deviceToken: d.deviceToken,
        deviceType: d.deviceType
      })),
      title,
      body,
      data: {
        ...data,
        type: type,
        targetRole: targetRole || 'all',
        timestamp: new Date().toISOString()
      },
      priority
    });

    // Save broadcast notification record
    await req.db.collection('broadcast_notifications').insertOne({
      title,
      body,
      type,
      targetRole: targetRole || 'all',
      data,
      priority,
      sentBy: req.user.userId,
      targetUsers: users.length,
      devicesSent: sendResults.success,
      devicesFailed: sendResults.failed,
      createdAt: new Date()
    });

    console.log('='.repeat(80) + '\n');

    res.json({
      success: true,
      message: 'Broadcast notification sent',
      data: {
        targetUsers: users.length,
        devicesSent: sendResults.success,
        devicesFailed: sendResults.failed,
        errors: sendResults.errors
      }
    });

  } catch (error) {
    console.error('❌ Broadcast failed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to send broadcast',
      error: error.message
    });
  }
});

// ============================================================================
// 📱 GET USER DEVICES
// ============================================================================
// @route   GET /api/notifications/devices
// @desc    Get all registered devices for current user
// @access  Private
router.get('/devices', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;

    const devices = await req.db.collection('user_devices').find({
      userId: userId,
      isActive: true
    }).toArray();

    res.json({
      success: true,
      devices: devices,
      count: devices.length
    });

  } catch (error) {
    console.error('❌ Get devices failed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get devices',
      error: error.message
    });
  }
});

// ============================================================================
// 📥 GET CURRENT USER NOTIFICATIONS
// ============================================================================
// @route   GET /api/notifications
// @desc    Get notification history for current user
// @access  Private
router.get('/', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;
    const { limit = 50, skip = 0, unreadOnly = false } = req.query;

    console.log('\n' + '='.repeat(80));
    console.log('📬 FETCHING NOTIFICATIONS');
    console.log('='.repeat(80));
    console.log('JWT userId:', userId);
    console.log('JWT email:', userEmail);
    console.log('JWT role:', req.user.role);

    // 🔥 FIX: Query by email OR userId
    const filter = {
      $or: [
        { userEmail: userEmail },
        { userId: userId }
      ],
      expiresAt: { $gt: new Date() }
    };

    if (unreadOnly === 'true') {
      filter.isRead = false;
    }

    console.log('Query:', JSON.stringify(filter, null, 2));

    const notifications = await req.db.collection('notifications')
      .find(filter)
      .sort({ createdAt: -1 })
      .skip(parseInt(skip))
      .limit(parseInt(limit))
      .toArray();

    console.log('Found notifications:', notifications.length);
    
    // 🔥 ENRICH NOTIFICATIONS WITH CURRENT TRIP STATUS
    // For trip assignment notifications, fetch the current driverResponse from the trip
    for (const notification of notifications) {
      const notifType = notification.type;
      const tripId = notification.data?.tripId;
      
      if (tripId && (notifType === 'trip_assigned' || notifType === 'client_trip_assigned')) {
        try {
          // Check roster_assigned_trips first
          let trip = await req.db.collection('roster_assigned_trips').findOne({
            _id: new ObjectId(tripId)
          });
          
          // If not found, check client_trips
          if (!trip) {
            trip = await req.db.collection('client_trips').findOne({
              _id: new ObjectId(tripId)
            });
          }
          
          // Update notification data with current trip response
          if (trip && trip.driverResponse) {
            notification.data.driverResponse = trip.driverResponse;
            notification.data.driverResponseTime = trip.driverResponseTime;
            notification.data.driverResponseNotes = trip.driverResponseNotes;
            notification.data.tripStatus = trip.status;
            console.log(`  ✅ Enriched notification ${notification._id} with driverResponse: ${trip.driverResponse}`);
          }
        } catch (enrichError) {
          console.log(`  ⚠️  Failed to enrich notification ${notification._id}:`, enrichError.message);
        }
      }
    }
    
    if (notifications.length > 0) {
      console.log('First notification:');
      console.log('  type:', notifications[0].type);
      console.log('  title:', notifications[0].title);
      console.log('  driverResponse:', notifications[0].data?.driverResponse || 'none');
    }
    console.log('='.repeat(80) + '\n');

    const unreadCount = await req.db.collection('notifications').countDocuments({
      $or: [
        { userEmail: userEmail },
        { userId: userId }
      ],
      isRead: false,
      expiresAt: { $gt: new Date() }
    });

    res.json({
      success: true,
      notifications: notifications,
      unreadCount: unreadCount,
      total: notifications.length
    });

  } catch (error) {
    console.error('❌ Get notifications failed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get notifications',
      error: error.message
    });
  }
});

// ============================================================================
// � GET UNREAD NOTIFICATION COUNT
// ============================================================================
// @route   GET /api/notifications/unread-count
// @desc    Get count of unread notifications for current user
// @access  Private
router.get('/unread-count', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;

    console.log('\n📊 Getting unread count for:', userEmail);

    const unreadCount = await req.db.collection('notifications').countDocuments({
      $or: [
        { userEmail: userEmail },
        { userId: userId }
      ],
      isRead: false,
      expiresAt: { $gt: new Date() }
    });

    console.log('✅ Unread count:', unreadCount);

    res.json({
      success: true,
      unreadCount: unreadCount
    });

  } catch (error) {
    console.error('❌ Get unread count failed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get unread count',
      error: error.message
    });
  }
});

// ============================================================================
// 📥 GET USER NOTIFICATIONS (BY USER ID)
// ============================================================================
// @route   GET /api/notifications/user/:userId
// @desc    Get notification history for a user
// @access  Private
router.get('/user/:userId', verifyToken, async (req, res) => {
  try {
    const { userId } = req.params;
    const { limit = 50, skip = 0, unreadOnly = false } = req.query;

    // Check authorization
    if (req.user.userId !== userId && !['admin', 'super_admin'].includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to view these notifications'
      });
    }

    const filter = {
      userId: userId,
      expiresAt: { $gt: new Date() }
    };

    if (unreadOnly === 'true') {
      filter.isRead = false;
    }

    const notifications = await req.db.collection('notifications')
      .find(filter)
      .sort({ createdAt: -1 })
      .skip(parseInt(skip))
      .limit(parseInt(limit))
      .toArray();

    const unreadCount = await req.db.collection('notifications').countDocuments({
      userId: userId,
      isRead: false,
      expiresAt: { $gt: new Date() }
    });

    res.json({
      success: true,
      data: {
        notifications,
        unreadCount,
        total: notifications.length
      }
    });

  } catch (error) {
    console.error('❌ Get notifications failed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get notifications',
      error: error.message
    });
  }
});

// ============================================================================
// ============================================================================
// ✅ MARK NOTIFICATION AS READ - UPDATED
// ============================================================================
// @route   PUT /api/notifications/:notificationId/read
// @desc    Mark notification as read
// @access  Private
router.put('/:notificationId/read', verifyToken, async (req, res) => {
  try {
    const { notificationId } = req.params;
    const userId = req.user.userId;
    const userEmail = req.user.email;

    console.log('📖 Marking notification as read:', notificationId);
    console.log('   userId:', userId);
    console.log('   userEmail:', userEmail);

    const result = await req.db.collection('notifications').updateOne(
      { 
        _id: new ObjectId(notificationId),
        $or: [
          { userEmail: userEmail },
          { userId: userId }
        ]
      },
      { $set: { isRead: true, readAt: new Date() } }
    );

    console.log('   matchedCount:', result.matchedCount);
    console.log('   modifiedCount:', result.modifiedCount);

    if (result.matchedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Notification not found'
      });
    }

    res.json({
      success: true,
      message: 'Notification marked as read'
    });

  } catch (error) {
    console.error('❌ Mark as read failed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to mark notification as read',
      error: error.message
    });
  }
});

// ============================================================================
// ✅ MARK ALL AS READ - UPDATED
// ============================================================================
// @route   PUT /api/notifications/mark-all-read
// @desc    Mark all notifications as read for a user
// @access  Private
router.put('/mark-all-read', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;

    console.log('📖 Marking all notifications as read');
    console.log('   userId:', userId);
    console.log('   userEmail:', userEmail);

    const result = await req.db.collection('notifications').updateMany(
      { 
        $or: [
          { userEmail: userEmail },
          { userId: userId }
        ],
        isRead: false 
      },
      { $set: { isRead: true, readAt: new Date() } }
    );

    console.log('   Modified:', result.modifiedCount);

    res.json({
      success: true,
      message: `Marked ${result.modifiedCount} notifications as read`,
      data: { modified: result.modifiedCount }
    });

  } catch (error) {
    console.error('❌ Mark all as read failed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to mark all as read',
      error: error.message
    });
  }
});

// ============================================================================
// 🗑️ DELETE NOTIFICATION - UPDATED
// ============================================================================
// @route   DELETE /api/notifications/:notificationId
// @desc    Delete a notification
// @access  Private
router.delete('/:notificationId', verifyToken, async (req, res) => {
  try {
    const { notificationId } = req.params;
    const userId = req.user.userId;
    const userEmail = req.user.email;

    console.log('🗑️ Deleting notification:', notificationId);
    console.log('   userId:', userId);
    console.log('   userEmail:', userEmail);

    const result = await req.db.collection('notifications').deleteOne({
      _id: new ObjectId(notificationId),
      $or: [
        { userEmail: userEmail },
        { userId: userId }
      ]
    });

    console.log('   deletedCount:', result.deletedCount);

    if (result.deletedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Notification not found'
      });
    }

    res.json({
      success: true,
      message: 'Notification deleted successfully'
    });

  } catch (error) {
    console.error('❌ Delete notification failed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete notification',
      error: error.message
    });
  }
});

// ============================================================================
// 🧪 TEST NOTIFICATION
// ============================================================================
// @route   POST /api/notifications/test
// @desc    Send test notification to current user
// @access  Private
router.post('/test', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;

    console.log('\n🧪 Sending test notification to:', userId);

    // Get user's devices
    const devices = await req.db.collection('user_devices').find({
      userId: userId,
      isActive: true
    }).toArray();

    if (devices.length === 0) {
      return res.json({
        success: false,
        message: 'No active devices found. Please register your device first.',
        hint: 'Call POST /api/notifications/register-device with your device token'
      });
    }

    // Send test notification
    const sendResults = await notificationService.sendToMultiple({
      devices: devices.map(d => ({
        deviceToken: d.deviceToken,
        deviceType: d.deviceType
      })),
      title: '🎉 Test Notification',
      body: 'Your push notifications are working perfectly!',
      data: {
        type: 'test',
        timestamp: new Date().toISOString()
      },
      priority: 'high'
    });

    res.json({
      success: true,
      message: 'Test notification sent!',
      data: {
        devicesSent: sendResults.success,
        devicesFailed: sendResults.failed,
        devices: devices.map(d => ({
          type: d.deviceType,
          model: d.deviceInfo?.model
        }))
      }
    });

  } catch (error) {
    console.error('❌ Test notification failed:', error);
    res.status(500).json({
      success: false,
      message: 'Test failed',
      error: error.message
    });
  }
});

// ============================================================================
// 💾 HELPER FUNCTION - Save Notification to Database
// ============================================================================
async function saveNotificationToDatabase(db, notificationData) {
  const notification = {
    userId: notificationData.userId,
    userEmail: notificationData.userEmail || null,
    title: notificationData.title,
    body: notificationData.body,
    type: notificationData.type || 'general',
    data: notificationData.data || {},
    priority: notificationData.priority || 'normal',
    isRead: false,
    readAt: null,
    deliveryStatus: notificationData.deliveryStatus || 'sent',
    devicesSent: notificationData.devicesSent || 0,
    devicesFailed: notificationData.devicesFailed || 0,
    createdAt: new Date(),
    expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) // 30 days
  };

  const result = await db.collection('notifications').insertOne(notification);
  return { ...notification, _id: result.insertedId };
}

module.exports = router;