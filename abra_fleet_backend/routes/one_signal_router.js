// routes/one_signal_router.js - UPDATED: Super admin sees ALL admin notifications
const express = require('express');
const router = express.Router();
const { MongoClient, ObjectId } = require('mongodb');

// MongoDB connection
let db;
MongoClient.connect(process.env.MONGODB_URI, { useUnifiedTopology: true })
  .then(client => {
    console.log('✅ OneSignal Router: Connected to MongoDB');
    db = client.db('abra_fleet');
  })
  .catch(error => console.error('❌ OneSignal Router MongoDB connection error:', error));

// OneSignal Configuration
const ONESIGNAL_CONFIG = {
  appId: process.env.ONESIGNAL_APP_ID || '',
  restApiKey: process.env.ONESIGNAL_REST_API_KEY || '',
  baseUrl: 'https://onesignal.com/api/v1'
};

// ============================================================================
// HELPER: Build flexible user query that works for ALL roles
// ============================================================================
async function buildUserQuery(req) {
  const userId = req.user?.userId || req.user?.id;
  const userEmail = req.user?.email;
  const userRole = req.user?.role;

  console.log('👤 Building query for user:', { userId, email: userEmail, role: userRole });

  // 🔥 SPECIAL: Super admins see ALL admin notifications
  if (userRole === 'super_admin') {
    console.log('👑 SUPER ADMIN detected');
    console.log('   → Showing ALL admin role notifications');
    const query = { userRole: 'admin' };
    console.log('   Query:', JSON.stringify(query));
    return { query, matched: true };
  }

  // 🔥 OPTION: Regular admins can also see all admin notifications
  // Uncomment this if you want ALL admins to see ALL admin notifications
  /*
  if (userRole === 'admin') {
    console.log('👤 ADMIN detected');
    console.log('   → Showing ALL admin role notifications');
    const query = { userRole: 'admin' };
    console.log('   Query:', JSON.stringify(query));
    return { query, matched: true };
  }
  */

  // Step 1: Check what fields exist in the notifications collection
  const sampleNotif = await db.collection('notifications').findOne();
  
  if (!sampleNotif) {
    console.log('⚠️ No notifications exist in database yet');
    return { query: { userId: 'no-match' }, matched: false };
  }

  const notifStructure = {
    hasUserId: !!sampleNotif.userId,
    hasEmail: !!sampleNotif.email,
    hasRecipientEmail: !!sampleNotif.recipientEmail,
    hasTargetRole: !!sampleNotif.targetRole,
    hasTargetUsers: !!sampleNotif.targetUsers,
    hasUserRole: !!sampleNotif.userRole
  };

  console.log('📋 Notification structure:', notifStructure);

  // Step 2: Build flexible query based on available fields
  let query = {};
  let matchConditions = [];

  // Match by userId if it exists in notifications
  if (notifStructure.hasUserId && userId) {
    matchConditions.push({ userId: userId.toString() });
    console.log('   ✓ Added userId match:', userId);
  }

  // Match by email if it exists in notifications
  if (notifStructure.hasEmail && userEmail) {
    matchConditions.push({ email: userEmail });
    console.log('   ✓ Added email match:', userEmail);
  }

  // Match by recipientEmail if it exists
  if (notifStructure.hasRecipientEmail && userEmail) {
    matchConditions.push({ recipientEmail: userEmail });
    console.log('   ✓ Added recipientEmail match:', userEmail);
  }

  // Match by userRole if it exists
  if (notifStructure.hasUserRole && userRole) {
    matchConditions.push({ userRole: userRole });
    console.log('   ✓ Added userRole match:', userRole);
  }

  // Match by targetRole if it exists
  if (notifStructure.hasTargetRole && userRole) {
    matchConditions.push({ targetRole: userRole });
    console.log('   ✓ Added targetRole match:', userRole);
  }

  // Match by targetUsers array if it exists
  if (notifStructure.hasTargetUsers && userId) {
    matchConditions.push({ targetUsers: { $in: [userId] } });
    console.log('   ✓ Added targetUsers match:', userId);
  }

  // Step 3: Combine conditions
  if (matchConditions.length > 0) {
    query = { $or: matchConditions };
    console.log('✅ Built flexible query with', matchConditions.length, 'conditions');
  } else {
    // Fallback: if we can't match anything, return empty result
    console.log('⚠️ No matching conditions found - will return no results');
    query = { userId: 'no-match-found' };
  }

  return { query, matched: matchConditions.length > 0 };
}

// ============================================================================
// HEALTH CHECK
// ============================================================================
router.get('/health', (req, res) => {
  res.json({
    success: true,
    message: 'OneSignal notification service is running',
    timestamp: new Date().toISOString(),
    config: {
      appId: ONESIGNAL_CONFIG.appId ? 'configured' : 'missing',
      restApiKey: ONESIGNAL_CONFIG.restApiKey ? 'configured' : 'missing',
      database: db ? 'connected' : 'disconnected'
    }
  });
});

// ============================================================================
// REGISTER DEVICE
// ============================================================================
router.post('/register-device', async (req, res) => {
  try {
    const { playerId, deviceType, deviceModel, osVersion, appVersion, tags } = req.body;
    const userId = req.user?.userId || req.user?.id;

    if (!playerId) {
      return res.status(400).json({
        success: false,
        message: 'Player ID is required'
      });
    }

    console.log(`📱 Registering device for user ${userId}, playerId: ${playerId}`);

    const deviceRegistration = {
      userId,
      playerId,
      deviceType: deviceType || 'unknown',
      deviceModel: deviceModel || 'unknown',
      osVersion: osVersion || 'unknown',
      appVersion: appVersion || '1.0.0',
      tags: tags || {},
      registeredAt: new Date(),
      lastActive: new Date()
    };

    await db.collection('onesignal_devices').updateOne(
      { playerId },
      { $set: deviceRegistration },
      { upsert: true }
    );

    res.json({
      success: true,
      message: 'Device registered successfully',
      data: { playerId }
    });
  } catch (error) {
    console.error('❌ Error registering device:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to register device',
      error: error.message
    });
  }
});

// ============================================================================
// 🔥 GET NOTIFICATIONS - Works for ALL roles automatically
// ============================================================================
router.get('/notifications', async (req, res) => {
  try {
    const userId = req.user?.userId || req.user?.id;
    
    if (!userId) {
      return res.status(401).json({
        success: false,
        message: 'User not authenticated'
      });
    }

    console.log('=================================================');
    console.log('📊 FETCHING NOTIFICATIONS');
    console.log('=================================================');

    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 50;
    const skip = (page - 1) * limit;

    // 🔥 Build smart query that adapts to your data structure
    const { query: baseQuery, matched } = await buildUserQuery(req);

    if (!matched && req.user?.role !== 'admin' && req.user?.role !== 'super_admin') {
      console.log('⚠️ No matching criteria found for user');
    }

    // Apply additional filters from query params
    let query = { ...baseQuery };
    
    if (req.query.isRead !== undefined) {
      query.isRead = req.query.isRead === 'true';
    }
    
    if (req.query.type) {
      query.type = req.query.type;
    }
    
    if (req.query.category) {
      query.category = req.query.category;
    }

    console.log('📋 Final query:', JSON.stringify(query, null, 2));

    // Fetch notifications
    const notifications = await db.collection('notifications')
      .find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .toArray();

    const total = await db.collection('notifications').countDocuments(query);
    
    // Count unread
    const unreadQuery = { ...query, isRead: false };
    const unreadCount = await db.collection('notifications').countDocuments(unreadQuery);

    console.log('✅ Results:', {
      found: notifications.length,
      total,
      unreadCount
    });

    res.json({
      success: true,
      data: {
        notifications,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        },
        unreadCount
      }
    });
  } catch (error) {
    console.error('❌ Error fetching notifications:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch notifications',
      error: error.message
    });
  }
});

// ============================================================================
// GET NOTIFICATION STATS
// ============================================================================
router.get('/stats', async (req, res) => {
  try {
    const userId = req.user?.userId || req.user?.id;

    if (!userId) {
      return res.status(401).json({
        success: false,
        message: 'User not authenticated'
      });
    }

    console.log(`📊 Fetching stats for user: ${userId}`);

    const { query } = await buildUserQuery(req);

    const total = await db.collection('notifications').countDocuments(query);
    const unread = await db.collection('notifications').countDocuments({
      ...query,
      isRead: false
    });
    const read = total - unread;

    res.json({
      success: true,
      data: { total, unread, read }
    });
  } catch (error) {
    console.error('❌ Error fetching stats:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch stats',
      error: error.message
    });
  }
});

// ============================================================================
// MARK AS READ
// ============================================================================
router.put('/mark-read/:notificationId', async (req, res) => {
  try {
    const { notificationId } = req.params;
    const userId = req.user?.userId || req.user?.id;
    const userRole = req.user?.role;

    if (!userId) {
      return res.status(401).json({
        success: false,
        message: 'User not authenticated'
      });
    }

    console.log(`✓ Marking notification ${notificationId} as read for user ${userId}`);

    // Super admins can mark any admin notification as read
    let updateQuery;
    if (userRole === 'super_admin') {
      updateQuery = {
        _id: new ObjectId(notificationId),
        userRole: 'admin'
      };
    } else {
      const { query: userQuery } = await buildUserQuery(req);
      updateQuery = {
        _id: new ObjectId(notificationId),
        $or: userQuery.$or || [{ userId: userId.toString() }]
      };
    }
    
    const result = await db.collection('notifications').updateOne(
      updateQuery,
      { $set: { isRead: true, readAt: new Date() } }
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Notification not found or access denied'
      });
    }

    res.json({
      success: true,
      message: 'Notification marked as read'
    });
  } catch (error) {
    console.error('❌ Error marking notification as read:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to mark notification as read',
      error: error.message
    });
  }
});

// ============================================================================
// MARK ALL AS READ
// ============================================================================
router.put('/mark-all-read', async (req, res) => {
  try {
    const userId = req.user?.userId || req.user?.id;

    if (!userId) {
      return res.status(401).json({
        success: false,
        message: 'User not authenticated'
      });
    }

    console.log(`✓ Marking all notifications as read for user ${userId}`);

    const { query: userQuery } = await buildUserQuery(req);
    const query = { ...userQuery, isRead: false };

    const result = await db.collection('notifications').updateMany(
      query,
      { $set: { isRead: true, readAt: new Date() } }
    );

    res.json({
      success: true,
      message: `${result.modifiedCount} notifications marked as read`
    });
  } catch (error) {
    console.error('❌ Error marking all notifications as read:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to mark all notifications as read',
      error: error.message
    });
  }
});

// ============================================================================
// DELETE NOTIFICATION
// ============================================================================
router.delete('/notifications/:notificationId', async (req, res) => {
  try {
    const { notificationId } = req.params;
    const userId = req.user?.userId || req.user?.id;
    const userRole = req.user?.role;

    if (!userId) {
      return res.status(401).json({
        success: false,
        message: 'User not authenticated'
      });
    }

    console.log(`🗑️ Deleting notification ${notificationId} for user ${userId}`);

    // Super admins can delete any admin notification
    let deleteQuery;
    if (userRole === 'super_admin') {
      deleteQuery = {
        _id: new ObjectId(notificationId),
        userRole: 'admin'
      };
    } else {
      const { query: userQuery } = await buildUserQuery(req);
      deleteQuery = {
        _id: new ObjectId(notificationId),
        $or: userQuery.$or || [{ userId: userId.toString() }]
      };
    }

    const result = await db.collection('notifications').deleteOne(deleteQuery);

    if (result.deletedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Notification not found or access denied'
      });
    }

    res.json({
      success: true,
      message: 'Notification deleted successfully'
    });
  } catch (error) {
    console.error('❌ Error deleting notification:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete notification',
      error: error.message
    });
  }
});

// ============================================================================
// SEND NOTIFICATION - Creates notifications with proper targeting
// ============================================================================
router.post('/send', async (req, res) => {
  try {
    const { 
      targetUsers,      // Array of userIds
      targetEmails,     // Array of emails  
      targetRole,       // Single role string
      title, 
      message, 
      type, 
      category, 
      priority, 
      data, 
      additionalData 
    } = req.body;
    const senderId = req.user?.userId || req.user?.id;

    console.log(`📤 Sending notification: ${title}`);

    if (!title || !message) {
      return res.status(400).json({
        success: false,
        message: 'Title and message are required'
      });
    }

    const notification = {
      title,
      message,
      type: type || 'system',
      category: category || 'general',
      priority: priority || 'normal',
      data: data || {},
      additionalData: additionalData || {},
      senderId,
      createdAt: new Date(),
      isRead: false
    };

    let insertedNotifications = [];
    let recipientUsers = [];

    // 🔥 Method 1: Target specific users by userId
    if (targetUsers && Array.isArray(targetUsers) && targetUsers.length > 0) {
      const users = await db.collection('users')
        .find({ _id: { $in: targetUsers.map(id => new ObjectId(id)) } })
        .toArray();
      
      recipientUsers.push(...users);
      console.log(`✓ Found ${users.length} users by userId`);
    }

    // 🔥 Method 2: Target specific users by email
    if (targetEmails && Array.isArray(targetEmails) && targetEmails.length > 0) {
      const users = await db.collection('users')
        .find({ email: { $in: targetEmails } })
        .toArray();
      
      recipientUsers.push(...users);
      console.log(`✓ Found ${users.length} users by email`);
    }

    // 🔥 Method 3: Target by role
    if (targetRole) {
      const users = await db.collection('users')
        .find({ role: targetRole })
        .toArray();
      
      recipientUsers.push(...users);
      console.log(`✓ Found ${users.length} users with role '${targetRole}'`);
    }

    // Remove duplicates
    recipientUsers = recipientUsers.filter((user, index, self) =>
      index === self.findIndex(u => u._id.toString() === user._id.toString())
    );

    console.log(`📬 Total unique recipients: ${recipientUsers.length}`);

    if (recipientUsers.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'No target users found'
      });
    }

    // Create notifications with ALL relevant fields for flexible querying
    const notifications = recipientUsers.map(user => ({
      ...notification,
      // Include multiple identifiers so queries can match flexibly
      userId: user._id.toString(),
      email: user.email || null,
      userRole: user.role || targetRole,  // 🔥 Important: store userRole
      targetRole: targetRole || null,
      targetUsers: targetUsers || null
    }));

    const result = await db.collection('notifications').insertMany(notifications);
    insertedNotifications = Object.values(result.insertedIds);

    console.log(`✅ Created ${insertedNotifications.length} notifications`);

    res.json({
      success: true,
      message: 'Notification sent successfully',
      data: {
        notificationIds: insertedNotifications,
        recipients: insertedNotifications.length
      }
    });
  } catch (error) {
    console.error('❌ Error sending notification:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to send notification',
      error: error.message
    });
  }
});

// ============================================================================
// SEND TEMPLATED NOTIFICATION
// ============================================================================
router.post('/send-template', async (req, res) => {
  try {
    const { targetUsers, targetEmails, targetRole, templateKey, templateData } = req.body;

    const templates = {
      'roster_assigned': {
        title: '🚗 New Roster Assignment',
        message: 'You have been assigned to {vehicleNumber} for {date}',
        type: 'roster_assigned',
        category: 'roster',
        priority: 'high'
      },
      'leave_approved': {
        title: '✅ Leave Request Approved',
        message: 'Your leave request from {startDate} to {endDate} has been approved',
        type: 'leave_approved',
        category: 'leave_management',
        priority: 'normal'
      },
      'trip_cancelled': {
        title: '🚫 Trip Cancelled',
        message: 'Trip {tripId} has been cancelled. Reason: {reason}',
        type: 'trip_cancelled',
        category: 'trip',
        priority: 'high'
      },
      'sos_alert': {
        title: '🚨 SOS ALERT',
        message: 'Emergency alert from {driverName} at {location}',
        type: 'sos_alert',
        category: 'emergency',
        priority: 'urgent'
      }
    };

    const template = templates[templateKey];
    if (!template) {
      return res.status(400).json({
        success: false,
        message: 'Invalid template key'
      });
    }

    let title = template.title;
    let message = template.message;
    if (templateData) {
      Object.keys(templateData).forEach(key => {
        const placeholder = `{${key}}`;
        title = title.replace(placeholder, templateData[key]);
        message = message.replace(placeholder, templateData[key]);
      });
    }

    // Use the main send endpoint
    return router.post('/send', {
      ...req,
      body: {
        targetUsers,
        targetEmails,
        targetRole,
        title,
        message,
        type: template.type,
        category: template.category,
        priority: template.priority,
        data: templateData
      }
    }, res);

  } catch (error) {
    console.error('❌ Error sending templated notification:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to send templated notification',
      error: error.message
    });
  }
});

// ============================================================================
// 🔍 DIAGNOSTIC ENDPOINT - Debug notification fetching
// ============================================================================
router.get('/debug/notifications', async (req, res) => {
  try {
    const userId = req.user?.userId || req.user?.id;
    const userEmail = req.user?.email;
    const userRole = req.user?.role;

    console.log('=================================================');
    console.log('🔍 NOTIFICATION DEBUG DIAGNOSTICS');
    console.log('=================================================');

    // 1. Check authenticated user
    console.log('\n1️⃣ AUTHENTICATED USER INFO:');
    console.log('   req.user:', JSON.stringify(req.user, null, 2));
    console.log('   - userId:', userId);
    console.log('   - email:', userEmail);
    console.log('   - role:', userRole);

    // 2. Check total notifications in database
    const totalNotifications = await db.collection('notifications').countDocuments();
    console.log('\n2️⃣ DATABASE STATUS:');
    console.log('   - Total notifications in DB:', totalNotifications);

    // 3. Check sample notification structure
    const sampleNotif = await db.collection('notifications').findOne();
    console.log('\n3️⃣ SAMPLE NOTIFICATION:');
    if (sampleNotif) {
      console.log('   Structure:', {
        _id: sampleNotif._id,
        userId: sampleNotif.userId,
        userRole: sampleNotif.userRole,
        email: sampleNotif.email,
        recipientEmail: sampleNotif.recipientEmail,
        targetRole: sampleNotif.targetRole,
        type: sampleNotif.type,
        title: sampleNotif.title
      });
    } else {
      console.log('   ⚠️ No notifications found in database');
    }

    // 4. Check unique userIds in notifications
    const uniqueUserIds = await db.collection('notifications').distinct('userId');
    console.log('\n4️⃣ UNIQUE USER IDs IN NOTIFICATIONS:');
    console.log('   Count:', uniqueUserIds.length);
    console.log('   Sample values:', uniqueUserIds.slice(0, 5));
    console.log('   Does it include current userId?', uniqueUserIds.includes(userId));

    // 5. Check by userRole (for super_admin)
    const byUserRole = await db.collection('notifications')
      .countDocuments({ userRole: 'admin' });
    console.log('\n5️⃣ NOTIFICATIONS WITH userRole="admin":', byUserRole);

    // 6. Try different query approaches
    console.log('\n6️⃣ TESTING DIFFERENT QUERIES:');
    
    // Query 1: By userId
    const byUserId = await db.collection('notifications')
      .countDocuments({ userId: userId });
    console.log('   - By userId:', byUserId, 'notifications');

    // Query 2: By userRole (for super_admin)
    if (userRole === 'super_admin') {
      const byRole = await db.collection('notifications')
        .countDocuments({ userRole: 'admin' });
      console.log('   - By userRole="admin" (super_admin sees these):', byRole, 'notifications');
    }

    // 7. Recommendation
    console.log('\n7️⃣ RECOMMENDATION:');
    if (userRole === 'super_admin' && byUserRole > 0) {
      console.log('   ✅ super_admin should see', byUserRole, 'admin notifications');
    } else if (byUserId > 0) {
      console.log('   ✅ userId match works - use this field');
    } else {
      console.log('   ❌ No matching criteria found');
    }

    console.log('=================================================\n');

    // Return diagnostic data
    res.json({
      success: true,
      diagnostics: {
        user: {
          userId,
          email: userEmail,
          role: userRole
        },
        database: {
          totalNotifications,
          uniqueUserIds: uniqueUserIds.length,
          adminNotifications: byUserRole
        },
        matches: {
          byUserId,
          byUserRole: byUserRole,
          shouldSeeAsSuperAdmin: userRole === 'super_admin' ? byUserRole : 0
        },
        sampleNotification: sampleNotif ? {
          userId: sampleNotif.userId,
          userRole: sampleNotif.userRole,
          email: sampleNotif.email,
          type: sampleNotif.type
        } : null
      }
    });

  } catch (error) {
    console.error('❌ Diagnostic error:', error);
    res.status(500).json({
      success: false,
      message: 'Diagnostic failed',
      error: error.message
    });
  }
});

module.exports = router;