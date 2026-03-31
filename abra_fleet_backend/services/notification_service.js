// ============================================================================
// services/notification_service.js
// COMPLETE NOTIFICATION SERVICE WITH EXTENSIVE DEBUGGING
// ============================================================================
const { getIO } = require('../config/websocket_config');
const { getRedisClient } = require('../config/redis');
const OneSignal = require('onesignal-node');
const { MongoClient } = require('mongodb');

class NotificationService {
  constructor() {
    this.redis = getRedisClient();
    this.mongoClient = null;
    
    // Initialize OneSignal client
    this.oneSignalClient = new OneSignal.Client({
      userAuthKey: process.env.ONESIGNAL_USER_AUTH_KEY,
      app: {
        appAuthKey: process.env.ONESIGNAL_REST_API_KEY,
        appId: process.env.ONESIGNAL_APP_ID
      }
    });
    
    console.log('════════════════════════════════════════════════════════════');
    console.log('✅ NotificationService INITIALIZED');
    console.log('════════════════════════════════════════════════════════════');
    console.log('   OneSignal App ID:', process.env.ONESIGNAL_APP_ID ? '✓ Configured' : '✗ Missing');
    console.log('   OneSignal API Key:', process.env.ONESIGNAL_REST_API_KEY ? '✓ Configured' : '✗ Missing');
    console.log('   MongoDB URI:', process.env.MONGODB_URI ? '✓ Configured' : '✗ Missing');
    console.log('════════════════════════════════════════════════════════════\n');
  }

  // ════════════════════════════════════════════════════════════════════════
  // MONGODB CONNECTION
  // ════════════════════════════════════════════════════════════════════════
  
  async getMongoConnection() {
    try {
      if (!this.mongoClient) {
        console.log('📊 Connecting to MongoDB...');
        this.mongoClient = await MongoClient.connect(process.env.MONGODB_URI);
        console.log('✅ MongoDB connection established');
      }
      return this.mongoClient.db('abra_fleet');
    } catch (error) {
      console.error('❌ MongoDB connection error:', error);
      throw error;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // CORE NOTIFICATION SENDING
  // ════════════════════════════════════════════════════════════════════════

  /**
   * Send real-time notification via WebSocket + OneSignal + MongoDB
   * 🔒 CRITICAL: Each user receives ONLY their own notifications
   */
  async sendRealTimeNotification(userType, userId, notification) {
    try {
      console.log('════════════════════════════════════════════════════════════');
      console.log('📤 SENDING REAL-TIME NOTIFICATION');
      console.log('════════════════════════════════════════════════════════════');
      console.log('Timestamp:', new Date().toISOString());
      console.log('Target User Type:', userType);
      console.log('Target User ID:', userId);
      console.log('User ID Type:', typeof userId);
      console.log('Notification Details:');
      console.log('   Type:', notification.type);
      console.log('   Title:', notification.title);
      console.log('   Message:', notification.message?.substring(0, 50) + '...');
      console.log('   Priority:', notification.priority || 'normal');
      console.log('   Category:', notification.category || 'system');

      const notificationData = {
        id: this.generateNotificationId(),
        type: notification.type,
        title: notification.title,
        message: notification.message,
        body: notification.message, // Alias
        data: notification.data || {},
        priority: notification.priority || 'normal',
        category: notification.category || 'system',
        timestamp: new Date().toISOString(),
        read: false,
      };

      console.log('Generated Notification ID:', notificationData.id);

      // STEP 1: Store in MongoDB (Most Important)
      console.log('\n📝 STEP 1/4: Storing in MongoDB...');
      const mongoResult = await this.storeNotificationInMongoDB(
        userId, 
        userType, 
        notificationData
      );
      console.log('✅ MongoDB storage complete');
      console.log('   Inserted ID:', mongoResult?.insertedId);

      // STEP 2: Store in Redis
      console.log('\n📝 STEP 2/4: Storing in Redis...');
      await this.storeNotification(userType, userId, notificationData);
      console.log('✅ Redis storage complete');

      // STEP 3: Send via WebSocket
      console.log('\n📝 STEP 3/4: Sending via WebSocket...');
      await this.sendViaWebSocket(userType, userId, notificationData);
      console.log('✅ WebSocket send complete');

      // STEP 4: Send via OneSignal
      console.log('\n📝 STEP 4/4: Sending via OneSignal...');
      await this.sendOneSignalPushNotification(userId, userType, notificationData);
      console.log('✅ OneSignal send complete');

      console.log('\n════════════════════════════════════════════════════════════');
      console.log('✅ NOTIFICATION SENT SUCCESSFULLY');
      console.log('════════════════════════════════════════════════════════════');
      console.log('Summary:');
      console.log('   Notification ID:', notificationData.id);
      console.log('   MongoDB ID:', mongoResult?.insertedId);
      console.log('   User:', `${userType}:${userId}`);
      console.log('   Type:', notification.type);
      console.log('   Status: ALL SYSTEMS SENT ✓');
      console.log('════════════════════════════════════════════════════════════\n');

      return notificationData;
    } catch (error) {
      console.error('❌ ERROR IN sendRealTimeNotification:');
      console.error('   User:', `${userType}:${userId}`);
      console.error('   Notification Type:', notification.type);
      console.error('   Error Message:', error.message);
      console.error('   Stack Trace:', error.stack);
      throw error;
    }
  }

  /**
   * Send notification via WebSocket
   */
  async sendViaWebSocket(userType, userId, notificationData) {
    try {
      const io = getIO();
      
      console.log('   📡 WebSocket Send Details:');
      console.log('      User Type:', userType);
      console.log('      User ID:', userId);
      
      switch (userType) {
        case 'admin':
        case 'super_admin':
          io.to('admin-room').emit('notification', notificationData);
          console.log('      ✓ Emitted to room: admin-room');
          break;
        case 'driver':
          io.to(`driver-${userId}`).emit('notification', notificationData);
          console.log(`      ✓ Emitted to room: driver-${userId}`);
          break;
        case 'customer':
          io.to(`customer-${userId}`).emit('notification', notificationData);
          console.log(`      ✓ Emitted to room: customer-${userId}`);
          break;
        case 'client':
          io.to(`client-${userId}`).emit('notification', notificationData);
          console.log(`      ✓ Emitted to room: client-${userId}`);
          break;
        case 'all_admins':
          io.to('admin-room').emit('notification', notificationData);
          console.log('      ✓ Emitted to room: admin-room (broadcast)');
          break;
        case 'all_drivers':
          io.to('driver-room').emit('notification', notificationData);
          console.log('      ✓ Emitted to room: driver-room (broadcast)');
          break;
        default:
          console.warn(`      ⚠️  Unknown user type: ${userType}`);
      }
    } catch (error) {
      console.error('      ❌ WebSocket error:', error.message);
      // Don't throw - this is not critical
    }
  }

  /**
   * Send push notification via OneSignal
   * 🔒 CRITICAL: Uses userId tag to target ONLY the specific user
   */
  async sendOneSignalPushNotification(userId, userRole, notificationData) {
    try {
      if (!this.oneSignalClient) {
        console.log('      ⚠️  OneSignal client not configured, skipping push');
        return null;
      }

      console.log('   📲 OneSignal Push Details:');
      console.log('      Target userId:', userId);
      console.log('      Target userId type:', typeof userId);
      console.log('      Target userRole:', userRole);
      console.log('      Filter: tag.userId =', userId);
      console.log('      Notification ID:', notificationData.id);

      const oneSignalNotification = {
        contents: { en: notificationData.message },
        headings: { en: notificationData.title },
        data: {
          ...notificationData.data,
          notificationId: notificationData.id,
          type: notificationData.type,
          priority: notificationData.priority,
          timestamp: notificationData.timestamp
        },
        // 🔒 CRITICAL: Target ONLY this specific user using userId tag
        filters: [
          { field: 'tag', key: 'userId', relation: '=', value: userId.toString() }
        ],
        priority: notificationData.priority === 'urgent' ? 10 : 
                 notificationData.priority === 'high' ? 8 : 5,
        ios_badgeType: 'Increase',
        ios_badgeCount: 1,
        android_channel_id: this.getAndroidChannelId(notificationData.priority),
        android_sound: 'notification',
        ios_sound: 'notification.mp3'
      };

      console.log('      OneSignal Payload:');
      console.log('         Filters:', JSON.stringify(oneSignalNotification.filters));
      console.log('         Priority:', oneSignalNotification.priority);

      const response = await this.oneSignalClient.createNotification(oneSignalNotification);
      
      console.log('      ✅ OneSignal Response:');
      console.log('         Recipients:', response.body.recipients || 0);
      console.log('         OneSignal ID:', response.body.id);
      console.log('         Errors:', response.body.errors || 'None');
      
      if (response.body.recipients === 0) {
        console.warn('      ⚠️  WARNING: 0 recipients! User may not have devices registered.');
      }
      
      return response;
    } catch (error) {
      console.error('      ❌ OneSignal error:', error.message);
      console.error('         Error details:', error);
      return null; // Don't throw - notification already stored
    }
  }

/**
   * Store notification in MongoDB
   * 🔥 CRITICAL: This is the source of truth for notifications
   * ✅ FIXES APPLIED:
   *    1. Added expiresAt field (30 days from now) — required by API query filter
   *    2. Added drivers collection lookup for driver userEmail resolution
   *    3. Passes through expiresAt from notificationData if already set (e.g. from checkDocumentExpiry)
   */
  // 📌 REPLACE the entire storeNotificationInMongoDB method (both copies if duplicated)
  //    in notification_service.js with this single method.
  //    It starts at:  async storeNotificationInMongoDB(userId, userRole, notificationData) {
  //    It ends at the closing brace + the blank line before the next method.
  // =====================================================================
  async storeNotificationInMongoDB(userId, userRole, notificationData) {
    try {
      console.log('   💾 MongoDB Storage Details:');
      console.log('      Database: abra_fleet');
      console.log('      Collection: notifications');
      console.log('      Target userId:', userId);
      console.log('      userId type:', typeof userId);
      console.log('      Target userRole:', userRole);
      
      const db = await this.getMongoConnection();
      const { ObjectId } = require('mongodb');
      
      // ✅ FIX: Resolve userEmail if not already provided
      let userEmail = notificationData.userEmail;
      
      if (!userEmail && userId) {
        const isValidObjectId = ObjectId.isValid(userId);
        const queryId = isValidObjectId ? new ObjectId(userId) : userId;

        // Search order: employee_admins → drivers → users
        // This covers all three user types in the system
        const user =
          await db.collection('employee_admins').findOne({ _id: queryId }) ||
          await db.collection('drivers').findOne({ _id: queryId }) ||
          await db.collection('users').findOne({ _id: queryId });
        
        if (user) {
          userEmail = user.email;
          console.log('      ✅ Retrieved userEmail:', userEmail);
        } else {
          console.warn('      ⚠️  Could not find user email for userId:', userId);
        }
      }

      // ✅ FIX: Calculate expiresAt
      //    If checkDocumentExpiry (or any caller) already set it, honour that value.
      //    Otherwise default to 30 days from now.
      const expiresAt = notificationData.expiresAt
        ? new Date(notificationData.expiresAt)
        : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
      
      const notification = {
        // 🔥 CRITICAL: User identification — must match JWT userId
        userId: userId.toString(),
        userEmail: userEmail || null,       // ✅ FIX: userEmail included
        userRole: userRole,
        
        // Notification content
        type: notificationData.type,
        title: notificationData.title,
        message: notificationData.message,
        body: notificationData.message,     // Alias for compatibility
        
        // Additional data
        data: notificationData.data || {},
        priority: notificationData.priority || 'normal',
        category: notificationData.category || 'system',
        
        // Status
        isRead: false,
        readAt: null,
        
        // Timestamps
        createdAt: new Date(),
        updatedAt: new Date(),
        expiresAt: expiresAt,               // ✅ FIX: expiresAt included — API filters on this
        
        // Reference
        notificationId: notificationData.id
      };
      
      console.log('      Document to insert:');
      console.log('         userId:', notification.userId, '(type:', typeof notification.userId + ')');
      console.log('         userEmail:', notification.userEmail);
      console.log('         userRole:', notification.userRole);
      console.log('         type:', notification.type);
      console.log('         title:', notification.title);
      console.log('         isRead:', notification.isRead);
      console.log('         category:', notification.category);
      console.log('         expiresAt:', notification.expiresAt);
      
      const result = await db.collection('notifications').insertOne(notification);
      
      console.log('      ✅ MongoDB Insert Success:');
      console.log('         Inserted ID:', result.insertedId);
      console.log('         Acknowledged:', result.acknowledged);
      
      // 🔍 VERIFICATION
      console.log('      🔍 VERIFICATION: Querying back...');
      const verification = await db.collection('notifications').findOne({ 
        _id: result.insertedId 
      });
      
      if (verification) {
        console.log('      ✅ VERIFICATION PASSED');
        console.log('         Found by _id: YES');
        console.log('         Stored userId:', verification.userId);
        console.log('         Stored userEmail:', verification.userEmail);
        console.log('         Stored expiresAt:', verification.expiresAt);
        console.log('         userId type:', typeof verification.userId);
        console.log('         Match check:', verification.userId === userId.toString() ? '✓ MATCH' : '✗ MISMATCH');
        console.log('         Stored userRole:', verification.userRole);
        console.log('         Stored type:', verification.type);
        
        // Can it be found by userId?
        const byUserId = await db.collection('notifications').findOne({ 
          userId: userId.toString() 
        });
        console.log('         Can be found by userId query:', byUserId ? '✓ YES' : '✗ NO');
        
        // Can it be found by userEmail?
        if (userEmail) {
          const byUserEmail = await db.collection('notifications').findOne({ 
            userEmail: userEmail 
          });
          console.log('         Can be found by userEmail query:', byUserEmail ? '✓ YES' : '✗ NO');
        }
      } else {
        console.error('      ❌ VERIFICATION FAILED: Cannot find notification in database!');
      }
      
      return result;
    } catch (error) {
      console.error('      ❌ MongoDB Storage Error:');
      console.error('         Error message:', error.message);
      console.error('         Error code:', error.code);
      console.error('         Stack trace:', error.stack);
      throw error;
    }
  }

  /**
   * Store notification in Redis for quick access
   */
  async storeNotification(userType, userId, notification) {
    try {
      const key = `notifications:${userType}:${userId}`;
      
      console.log('   📦 Redis Storage Details:');
      console.log('      Key:', key);
      
      await this.redis.lpush(key, JSON.stringify(notification));
      await this.redis.ltrim(key, 0, 99); // Keep last 100
      await this.redis.expire(key, 30 * 24 * 60 * 60); // 30 days
      await this.updateUnreadCount(userType, userId, 1);
      
      console.log('      ✓ Stored in Redis');
      console.log('      ✓ Unread count updated');
    } catch (error) {
      console.error('      ❌ Redis storage error:', error.message);
      // Don't throw - not critical
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // BULK NOTIFICATIONS
  // ════════════════════════════════════════════════════════════════════════

  /**
   * Send notification to all users with specific role
   * 🔒 CRITICAL: Fetches users from DB and sends individually
   */
  async sendNotificationToRole(userRole, notification) {
    try {
      console.log('════════════════════════════════════════════════════════════');
      console.log(`📢 BULK SEND TO ROLE: ${userRole}`);
      console.log('════════════════════════════════════════════════════════════');
      console.log('Notification Type:', notification.type);
      console.log('Title:', notification.title);
      
      const db = await this.getMongoConnection();
      
      // Get all users with this role
      const users = await db.collection('users').find({ role: userRole }).toArray();
      
      console.log(`\nFound ${users.length} users with role '${userRole}':`);
      users.forEach((user, index) => {
        console.log(`   ${index + 1}. ID: ${user._id} | Email: ${user.email || 'N/A'} | Name: ${user.name || 'N/A'}`);
      });
      
      if (users.length === 0) {
        console.log('\n⚠️  No users found with this role');
        console.log('════════════════════════════════════════════════════════════\n');
        return { success: true, sent: 0, failed: 0 };
      }
      
      console.log('\n📤 Sending to each user individually...\n');
      
      // Send to each user
      const results = { sent: 0, failed: 0, errors: [] };
      
      for (const user of users) {
        try {
          console.log(`   → Sending to user ${user._id}...`);
          await this.sendRealTimeNotification(
            userRole,
            user._id.toString(),
            notification
          );
          results.sent++;
          console.log(`   ✅ Success for user ${user._id}\n`);
        } catch (error) {
          results.failed++;
          results.errors.push({
            userId: user._id.toString(),
            error: error.message
          });
          console.error(`   ❌ Failed for user ${user._id}:`, error.message, '\n');
        }
      }
      
      console.log('════════════════════════════════════════════════════════════');
      console.log('📊 BULK SEND SUMMARY:');
      console.log('════════════════════════════════════════════════════════════');
      console.log(`   Target Role: ${userRole}`);
      console.log(`   Total Users: ${users.length}`);
      console.log(`   ✅ Sent: ${results.sent}`);
      console.log(`   ❌ Failed: ${results.failed}`);
      if (results.errors.length > 0) {
        console.log('\n   Errors:');
        results.errors.forEach(err => {
          console.log(`      - User ${err.userId}: ${err.error}`);
        });
      }
      console.log('════════════════════════════════════════════════════════════\n');
      
      return { success: true, ...results };
    } catch (error) {
      console.error(`❌ Error in sendNotificationToRole:`, error);
      throw error;
    }
  }

  /**
   * Send bulk notifications to specific users
   */
  async sendBulkNotifications(recipients, notification) {
    try {
      console.log('════════════════════════════════════════════════════════════');
      console.log(`📢 BULK SEND TO ${recipients.length} SPECIFIC USERS`);
      console.log('════════════════════════════════════════════════════════════');
      
      const promises = recipients.map((recipient, index) => {
        console.log(`   ${index + 1}. ${recipient.userType}:${recipient.userId}`);
        return this.sendRealTimeNotification(
          recipient.userType,
          recipient.userId,
          notification
        );
      });
      
      const results = await Promise.allSettled(promises);
      
      const successful = results.filter(r => r.status === 'fulfilled').length;
      const failed = results.filter(r => r.status === 'rejected').length;
      
      console.log('\n📊 Results:');
      console.log(`   ✅ Sent: ${successful}`);
      console.log(`   ❌ Failed: ${failed}`);
      console.log('════════════════════════════════════════════════════════════\n');
      
      return { success: true, sent: successful, failed };
    } catch (error) {
      console.error('❌ Error in sendBulkNotifications:', error);
      return { success: false, error: error.message };
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // PREDEFINED NOTIFICATION TYPES
  // ════════════════════════════════════════════════════════════════════════

  async sendRosterAssignedNotification(driverId, rosterData) {
    console.log(`🚗 [ROSTER_ASSIGNED] Sending to driver: ${driverId}`);
    return this.sendRealTimeNotification('driver', driverId, {
      type: 'roster_assigned',
      title: 'New Roster Assigned',
      message: `You have been assigned roster for ${rosterData.customerName}`,
      data: rosterData,
      priority: 'high',
      category: 'roster'
    });
  }

  async sendLeaveApprovedNotification(userId, leaveData) {
    console.log(`✅ [LEAVE_APPROVED] Sending to user: ${userId}`);
    return this.sendRealTimeNotification('customer', userId, {
      type: 'leave_approved',
      title: 'Leave Request Approved',
      message: `Your leave request has been approved`,
      data: leaveData,
      priority: 'normal',
      category: 'leave_management'
    });
  }

  async sendTripStartedNotification(customerId, tripData) {
    console.log(`🚀 [TRIP_STARTED] Sending to customer: ${customerId}`);
    return this.sendRealTimeNotification('customer', customerId, {
      type: 'trip_started',
      title: 'Trip Started',
      message: `Your trip has started. Driver: ${tripData.driverName}`,
      data: tripData,
      priority: 'high',
      category: 'trip'
    });
  }

  async sendSOSAlertNotification(alertData) {
    console.log(`🚨 [SOS_ALERT] Sending to all admins`);
    return this.sendNotificationToRole('admin', {
      type: 'sos_alert',
      title: '🚨 SOS ALERT',
      message: `Emergency from ${alertData.customerName} at ${alertData.location}`,
      data: alertData,
      priority: 'urgent',
      category: 'emergency'
    });
  }

  async sendTripCancelledNotification(driverId, tripData) {
    console.log(`❌ [TRIP_CANCELLED] Sending to driver: ${driverId}`);
    return this.sendRealTimeNotification('driver', driverId, {
      type: 'trip_cancelled',
      title: 'Trip Cancelled',
      message: `Trip ${tripData.tripNumber} has been cancelled`,
      data: tripData,
      priority: 'high',
      category: 'trip'
    });
  }

  async sendVehicleAssignedNotification(driverId, vehicleData) {
    console.log(`🚗 [VEHICLE_ASSIGNED] Sending to driver: ${driverId}`);
    return this.sendRealTimeNotification('driver', driverId, {
      type: 'vehicle_assigned',
      title: 'Vehicle Assigned',
      message: `Vehicle ${vehicleData.registrationNumber} assigned to you`,
      data: vehicleData,
      priority: 'high',
      category: 'vehicle'
    });
  }

  async sendAddressChangeRequestNotification(customerData) {
    console.log(`📍 [ADDRESS_CHANGE] Sending to all admins`);
    return this.sendNotificationToRole('admin', {
      type: 'address_change_request',
      title: 'Address Change Request',
      message: `${customerData.name} has requested an address change`,
      data: customerData,
      priority: 'normal',
      category: 'customer_management'
    });
  }

  async sendMaintenanceReminderNotification(adminId, vehicleData) {
    console.log(`🔧 [MAINTENANCE] Sending to admin: ${adminId}`);
    return this.sendRealTimeNotification('admin', adminId, {
      type: 'maintenance_reminder',
      title: 'Maintenance Due',
      message: `Vehicle ${vehicleData.registrationNumber} is due for maintenance`,
      data: vehicleData,
      priority: 'normal',
      category: 'maintenance'
    });
  }

  // ════════════════════════════════════════════════════════════════════════
  // REDIS OPERATIONS
  // ════════════════════════════════════════════════════════════════════════

  async getNotifications(userType, userId, limit = 20, offset = 0) {
    try {
      const key = `notifications:${userType}:${userId}`;
      const notifications = await this.redis.lrange(key, offset, offset + limit - 1);
      return notifications.map(n => JSON.parse(n));
    } catch (error) {
      console.error('Error getting notifications from Redis:', error);
      return [];
    }
  }

  async markAsRead(userType, userId, notificationId) {
    try {
      const notifications = await this.getNotifications(userType, userId, 100);
      const updated = notifications.map(n => {
        if (n.id === notificationId && !n.read) {
          n.read = true;
          this.updateUnreadCount(userType, userId, -1);
        }
        return n;
      });

      const key = `notifications:${userType}:${userId}`;
      await this.redis.del(key);
      
      for (const notification of updated.reverse()) {
        await this.redis.lpush(key, JSON.stringify(notification));
      }

      return true;
    } catch (error) {
      console.error('Error marking as read:', error);
      return false;
    }
  }

  async getUnreadCount(userType, userId) {
    try {
      const key = `unread_count:${userType}:${userId}`;
      const count = await this.redis.get(key);
      return parseInt(count || 0);
    } catch (error) {
      return 0;
    }
  }

  async updateUnreadCount(userType, userId, increment) {
    try {
      const key = `unread_count:${userType}:${userId}`;
      const newCount = await this.redis.incrby(key, increment);
      
      if (newCount < 0) {
        await this.redis.set(key, 0);
        return 0;
      }
      
      const io = getIO();
      const targetRoom = userType === 'admin' ? 'admin-room' : 
                        userType === 'driver' ? `driver-${userId}` : 
                        `customer-${userId}`;
      
      io.to(targetRoom).emit('unread_count_update', {
        count: Math.max(0, newCount),
        timestamp: new Date().toISOString(),
      });
      
      return Math.max(0, newCount);
    } catch (error) {
      return 0;
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // UTILITY METHODS
  // ════════════════════════════════════════════════════════════════════════

  generateNotificationId() {
    return `notif_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  getAndroidChannelId(priority) {
    const channels = {
      urgent: 'urgent_notifications',
      high: 'high_priority_notifications',
      normal: 'default_notifications',
      low: 'low_priority_notifications'
    };
    return channels[priority] || 'default_notifications';
  }

  mapPriorityToUrgency(priority) {
    const mapping = {
      low: 'low',
      normal: 'normal',
      high: 'high',
      urgent: 'high'
    };
    return mapping[priority] || 'normal';
  }

  generateEmailTemplate(notification) {
    return `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>${notification.title}</title>
        <style>
          body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; }
          .container { max-width: 600px; margin: 0 auto; padding: 20px; }
          .header { background: #007bff; color: white; padding: 20px; text-align: center; }
          .content { padding: 20px; background: #f9f9f9; }
          .footer { padding: 20px; text-align: center; color: #666; font-size: 12px; }
        </style>
      </head>
      <body>
        <div class="container">
          <div class="header">
            <h1>Abra Fleet Management</h1>
          </div>
          <div class="content">
            <h2>${notification.title}</h2>
            <p>${notification.message}</p>
            ${notification.data ? `<p><strong>Details:</strong> ${JSON.stringify(notification.data, null, 2)}</p>` : ''}
          </div>
          <div class="footer">
            <p>This is an automated message from Abra Fleet Management System.</p>
          </div>
        </div>
      </body>
      </html>
    `;
  }

  // ════════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ════════════════════════════════════════════════════════════════════════

  async close() {
    if (this.mongoClient) {
      await this.mongoClient.close();
      console.log('🔌 MongoDB connection closed');
    }
  }
}

// Export singleton instance
module.exports = new NotificationService();