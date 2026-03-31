// models/notification_model.js - COMPLETE OneSignal Integration
const { ObjectId } = require('mongodb');
const axios = require('axios'); // 🔥 REQUIRED: npm install axios

// Color codes for console (works in most terminals)
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  magenta: '\x1b[35m',
  cyan: '\x1b[36m'
};

class NotificationModel {
  constructor(db) {
    this.collection = db.collection('notifications');
    this.usersCollection = db.collection('users');
    
    // Create indexes for efficient querying
    this.collection.createIndex({ userId: 1, createdAt: -1 });
    this.collection.createIndex({ userEmail: 1, createdAt: -1 });
    this.collection.createIndex({ userRole: 1, createdAt: -1 });
    this.collection.createIndex({ status: 1, createdAt: -1 });
    this.collection.createIndex({ type: 1, userId: 1 });
    this.collection.createIndex({ isRead: 1, userId: 1 });
    
    console.log(`${colors.green}✅ NotificationModel initialized (FCM mode)${colors.reset}`);
  }

  // 🎯 MAIN NOTIFICATION CREATION METHOD
  async create(notificationData) {
    const startTime = Date.now();
    const sessionId = `NOTIF-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
    
    this.logHeader('NOTIFICATION CREATION SESSION STARTED', sessionId);
    
    try {
      // STEP 1: Validate Input
      this.logStep(1, 'Validating Input Data', sessionId);
      const validation = this.validateNotificationData(notificationData);
      if (!validation.valid) {
        this.logError('Validation Failed', validation.errors, sessionId);
        throw new Error(`Validation failed: ${validation.errors.join(', ')}`);
      }
      this.logSuccess('Input validation passed', sessionId);
      
      // STEP 2: Prepare Notification Object
      this.logStep(2, 'Preparing Notification Object', sessionId);
      const notification = this.prepareNotificationObject(notificationData);
      this.logInfo('Notification Details:', {
        userId: notification.userId,
        userEmail: notification.userEmail,
        userRole: notification.userRole,
        type: notification.type,
        title: notification.title,
        priority: notification.priority,
        category: notification.category,
        channels: notificationData.channels || ['database']
      }, sessionId);
      
      // STEP 3: Save to MongoDB
      this.logStep(3, 'Saving to MongoDB', sessionId);
      const mongoResult = await this.saveToMongoDB(notification, sessionId);
      
      // STEP 4: Send via FCM (if requested)
      let fcmResult = { sent: 0, failed: 0 };
      if (notificationData.channels?.includes('fcm') || notificationData.channels?.includes('push')) {
        this.logStep(4, 'Sending Push Notification via FCM', sessionId);
        fcmResult = await this.sendViaFCM(notification, mongoResult.insertedId, sessionId);
      } else {
        this.logInfo('Skipping FCM - not in channels list', null, sessionId);
      }
      
      // STEP 5: Summary
      this.logSummary(sessionId, startTime, {
        notificationId: mongoResult.insertedId.toString(),
        userId: notification.userId,
        userEmail: notification.userEmail,
        type: notification.type,
        mongoSaved: true,
        fcmSent: fcmResult.sent,
        fcmFailed: fcmResult.failed
      });
      
      return { ...notification, _id: mongoResult.insertedId };
      
    } catch (error) {
      this.logFatalError('Notification Creation Failed', error, sessionId);
      throw error;
    }
  }

  // 📝 Validate notification data
  validateNotificationData(data) {
    const errors = [];
    
    if (!data.userId) errors.push('userId is required');
    if (!data.type) errors.push('type is required');
    if (!data.title) errors.push('title is required');
    if (!data.body) errors.push('body is required');
    
    if (data.userId && typeof data.userId !== 'string') {
      errors.push('userId must be a string');
    }
    
    if (data.priority && !['low', 'normal', 'high', 'urgent'].includes(data.priority)) {
      errors.push('priority must be: low, normal, high, or urgent');
    }
    
    // 🔥 Warn if FCM requested but userId missing
    if ((data.channels?.includes('fcm') || data.channels?.includes('push')) && !data.userId) {
      errors.push('userId is required for FCM notifications');
    }
    
    return {
      valid: errors.length === 0,
      errors
    };
  }

  // 📦 Prepare notification object
  prepareNotificationObject(data) {
    const now = new Date();
    return {
      userId: data.userId,
      userEmail: data.userEmail || null,        // 🔥 CRITICAL: Store email
      userRole: data.userRole || null,          // 🔥 CRITICAL: Store role
      type: data.type,
      title: data.title,
      body: data.body,
      data: data.data || {},
      metadata: {
        rosterId: data.rosterId || data.metadata?.rosterId || null,
        driverId: data.driverId || data.metadata?.driverId || null,
        vehicleId: data.vehicleId || data.metadata?.vehicleId || null,
        ...data.metadata
      },
      isRead: false,
      readAt: null,
      priority: data.priority || 'normal',
      category: data.category || 'general',
      createdAt: now,
      expiresAt: data.expiresAt || new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000),
      deliveryStatus: {
        mongodb: 'pending',
        fcm: 'pending'
      }
    };
  }

  // 💾 Save to MongoDB
  async saveToMongoDB(notification, sessionId) {
    try {
      this.logInfo('MongoDB Operation:', {
        collection: 'notifications',
        operation: 'insertOne'
      }, sessionId);
      
      const result = await this.collection.insertOne(notification);
      
      this.logSuccess(`MongoDB Save Successful`, {
        insertedId: result.insertedId.toString(),
        acknowledged: result.acknowledged
      }, sessionId);
      
      // Update delivery status
      await this.collection.updateOne(
        { _id: result.insertedId },
        { $set: { 'deliveryStatus.mongodb': 'success' } }
      );
      
      return result;
    } catch (error) {
      this.logError('MongoDB Save Failed', {
        error: error.message,
        code: error.code
      }, sessionId);
      
      throw error;
    }
  }

  // 📤 Send via FCM
  // 📤 Send via FCM
async sendViaFCM(notification, notificationId, sessionId) {
  const notificationService = require('../services/fcm_service');
  
  const results = {
    sent: 0,
    failed: 0,
    errors: []
  };
  
  try {
    // 🔥 FIX: Query by BOTH userId AND userEmail for maximum compatibility
    const query = {
      isActive: true,
      $or: [
        { userId: notification.userId },
        { userEmail: notification.userEmail }
      ]
    };
    
    this.logInfo('Querying user_devices with:', query, sessionId);
    
    // Get user's devices
    const devices = await this.collection.db.collection('user_devices').find(query).toArray();

    if (devices.length === 0) {
      this.logError('No devices found for user', {
        userId: notification.userId,
        userEmail: notification.userEmail,
        query: query
      }, sessionId);
      
      await this.collection.updateOne(
        { _id: notificationId },
        { $set: { 'deliveryStatus.fcm': 'no_devices' } }
      );
      return results;
    }

    this.logInfo(`Found ${devices.length} device(s) for user ${notification.userId}`, null, sessionId);

    // Send via FCM
    const sendResults = await notificationService.sendToMultiple({
      devices: devices.map(d => ({
        deviceToken: d.deviceToken,
        deviceType: d.deviceType
      })),
      title: notification.title,
      body: notification.body,
      data: notification.data,
      priority: notification.priority
    });

    await this.collection.updateOne(
      { _id: notificationId },
      { 
        $set: {
          'deliveryStatus.fcm': sendResults.success > 0 ? 'success' : 'failed',
          'fcmResponse': sendResults
        }
      }
    );

    results.sent = sendResults.success;
    results.failed = sendResults.failed;
    
    this.logSuccess(`FCM sent to ${sendResults.success} device(s)`, null, sessionId);
    
    return results;
  } catch (error) {
    this.logError('FCM send failed', error.message, sessionId);
    
    await this.collection.updateOne(
      { _id: notificationId },
      { 
        $set: {
          'deliveryStatus.fcm': 'failed',
          'fcmError': error.message
        }
      }
    );
    
    results.failed = 1;
    results.errors.push(error.message);
    return results;
  }
}

  // 🎨 Logging Methods with Colors and Structure
  logHeader(title, sessionId) {
    console.log('\n' + '='.repeat(100));
    console.log(`${colors.bright}${colors.cyan}🔔 ${title}${colors.reset}`);
    console.log(`${colors.cyan}Session ID: ${sessionId}${colors.reset}`);
    console.log(`${colors.cyan}Timestamp: ${new Date().toISOString()}${colors.reset}`);
    console.log('='.repeat(100) + '\n');
  }

  logStep(stepNumber, title, sessionId) {
    console.log(`\n${colors.bright}${colors.blue}📍 STEP ${stepNumber}: ${title}${colors.reset}`);
    console.log(`${colors.blue}${'─'.repeat(80)}${colors.reset}`);
  }

  logSuccess(message, data = null, sessionId) {
    console.log(`${colors.green}✅ ${message}${colors.reset}`);
    if (data) {
      console.log(`${colors.green}${JSON.stringify(data, null, 2)}${colors.reset}`);
    }
  }

  logError(message, data = null, sessionId) {
    console.log(`${colors.red}❌ ERROR: ${message}${colors.reset}`);
    if (data) {
      console.log(`${colors.red}${JSON.stringify(data, null, 2)}${colors.reset}`);
    }
  }

  logWarning(message, data = null, sessionId) {
    console.log(`${colors.yellow}⚠️  WARNING: ${message}${colors.reset}`);
    if (data) {
      console.log(`${colors.yellow}${JSON.stringify(data, null, 2)}${colors.reset}`);
    }
  }

  logInfo(message, data = null, sessionId) {
    console.log(`${colors.cyan}ℹ️  ${message}${colors.reset}`);
    if (data) {
      console.log(`${colors.cyan}${JSON.stringify(data, null, 2)}${colors.reset}`);
    }
  }

  logFatalError(message, error, sessionId) {
    console.log('\n' + '❌'.repeat(50));
    console.log(`${colors.bright}${colors.red}💥 FATAL ERROR: ${message}${colors.reset}`);
    console.log(`${colors.red}Session ID: ${sessionId}${colors.reset}`);
    console.log(`${colors.red}Error Message: ${error.message}${colors.reset}`);
    console.log(`${colors.red}Stack Trace:${colors.reset}`);
    console.log(`${colors.red}${error.stack}${colors.reset}`);
    console.log('❌'.repeat(50) + '\n');
  }

  logSummary(sessionId, startTime, summary) {
    const duration = Date.now() - startTime;
    console.log('\n' + '='.repeat(100));
    console.log(`${colors.bright}${colors.green}✅ NOTIFICATION SESSION COMPLETED${colors.reset}`);
    console.log('='.repeat(100));
    console.log(`${colors.green}Session ID: ${sessionId}${colors.reset}`);
    console.log(`${colors.green}Duration: ${duration}ms${colors.reset}`);
    console.log(`${colors.green}Notification ID: ${summary.notificationId}${colors.reset}`);
    console.log(`${colors.green}User ID: ${summary.userId}${colors.reset}`);
    console.log(`${colors.green}User Email: ${summary.userEmail}${colors.reset}`);
    console.log(`${colors.green}Type: ${summary.type}${colors.reset}`);
    console.log('\n📊 DELIVERY STATUS:');
    console.log(`${colors.green}  ✅ MongoDB: ${summary.mongoSaved ? 'Saved' : 'Failed'}${colors.reset}`);
    console.log(`${colors.green}  📤 FCM Sent: ${summary.fcmSent || 0}${colors.reset}`);
    console.log(`${colors.green}  ❌ FCM Failed: ${summary.fcmFailed || 0}${colors.reset}`);
    console.log('='.repeat(100) + '\n');
  }

  // Additional helper methods
  async getByUserId(userId, options = {}) {
    const { limit = 50, skip = 0, unreadOnly = false } = options;
    
    const filter = {
      userId: userId,
      expiresAt: { $gt: new Date() }
    };
    
    if (unreadOnly) {
      filter.isRead = false;
    }
    
    return await this.collection
      .find(filter)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .toArray();
  }

  async getByUserEmail(userEmail, options = {}) {
    const { limit = 50, skip = 0, unreadOnly = false } = options;
    
    const filter = {
      userEmail: userEmail,
      expiresAt: { $gt: new Date() }
    };
    
    if (unreadOnly) {
      filter.isRead = false;
    }
    
    return await this.collection
      .find(filter)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .toArray();
  }

  async markAsRead(notificationId, userId) {
    return await this.collection.updateOne(
      { _id: new ObjectId(notificationId), userId: userId },
      { $set: { isRead: true, readAt: new Date() } }
    );
  }

  async markAllAsRead(userId) {
    return await this.collection.updateMany(
      { userId: userId, isRead: false },
      { $set: { isRead: true, readAt: new Date() } }
    );
  }

  async delete(notificationId, userId) {
    return await this.collection.deleteOne({
      _id: new ObjectId(notificationId),
      userId: userId
    });
  }

  async getUnreadCount(userId) {
    return await this.collection.countDocuments({
      userId: userId,
      isRead: false,
      expiresAt: { $gt: new Date() }
    });
  }
}

// Helper function
async function createNotification(db, notificationData) {
  const notificationModel = new NotificationModel(db);
  return await notificationModel.create(notificationData);
}

module.exports = NotificationModel;
module.exports.createNotification = createNotification;