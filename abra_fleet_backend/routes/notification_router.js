// routes/notification_router.js - COMPLETE FIXED VERSION (ALL FEATURES PRESERVED)
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const { createNotification } = require('../models/notification_model');

// ========== GET NOTIFICATIONS ==========

// @route   GET api/notifications/debug-connection
// @desc    Debug endpoint to check database connection
// @access  Private
router.get('/debug-connection', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;
    
    // Get database info
    const dbName = req.db.databaseName;
    const collections = await req.db.listCollections().toArray();
    const hasNotifications = collections.some(c => c.name === 'notifications');
    
    // Count notifications
    const totalNotifications = hasNotifications ? 
      await req.db.collection('notifications').countDocuments({}) : 0;
    
    // 🔥 FIX: Query by email first, then userId
    const query = {
      $or: [
        { userEmail: userEmail },  // 🔥 PRIMARY
        { userId: userId }          // FALLBACK
      ]
    };
    
    const userNotifications = hasNotifications ?
      await req.db.collection('notifications').countDocuments(query) : 0;
    
    // Sample notification
    const sampleNotification = hasNotifications ?
      await req.db.collection('notifications').findOne(query) : null;
    
    res.json({
      success: true,
      debug: {
        database: dbName,
        hasNotificationsCollection: hasNotifications,
        totalNotifications: totalNotifications,
        userNotifications: userNotifications,
        query: query,
        sampleNotification: sampleNotification ? {
          _id: sampleNotification._id,
          userId: sampleNotification.userId,
          userEmail: sampleNotification.userEmail,
          type: sampleNotification.type,
          title: sampleNotification.title,
          isRead: sampleNotification.isRead,
          createdAt: sampleNotification.createdAt
        } : null,
        jwt: {
          userId: userId,
          userEmail: userEmail,
          role: req.user.role
        }
      }
    });
    
  } catch (err) {
    console.error('❌ Debug error:', err.message);
    res.status(500).json({ success: false, message: err.message });
  }
});

// @route   GET api/notifications
// @desc    Get all notifications for the current user
// @access  Private
router.get('/', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId; // JWT userId
    const userEmail = req.user.email; // JWT email
    const { page = 1, limit = 50, isRead, type, category } = req.query;

    console.log('\n' + '='.repeat(80));
    console.log('📬 FETCHING NOTIFICATIONS');
    console.log('='.repeat(80));
    console.log('JWT userId:', userId);
    console.log('JWT email:', userEmail);
    console.log('JWT role:', req.user.role);
    console.log('');
    
    // 🔥 FIX: Query PRIMARILY by email (most reliable), userId as fallback
    const query = {
      $or: [
        { userEmail: userEmail },  // 🔥 PRIMARY: Email is consistent
        { userId: userId }          // FALLBACK: userId may not match
      ]
    };
    
    if (isRead !== undefined) {
      query.isRead = isRead === 'true';
    }
    if (type) query.type = type;
    if (category) query.category = category;

    console.log('Query:', JSON.stringify(query, null, 2));
    console.log('Database:', req.db.databaseName);
    console.log('');

    const notifications = await req.db.collection('notifications')
      .find(query)
      .sort({ createdAt: -1 })
      .skip((parseInt(page) - 1) * parseInt(limit))
      .limit(parseInt(limit))
      .toArray();

    console.log('Found notifications:', notifications.length);
    if (notifications.length > 0) {
      console.log('First notification:');
      console.log('  _id:', notifications[0]._id);
      console.log('  userId:', notifications[0].userId);
      console.log('  userEmail:', notifications[0].userEmail);
      console.log('  type:', notifications[0].type);
      console.log('  title:', notifications[0].title);
    } else {
      console.log('❌ NO NOTIFICATIONS FOUND!');
      console.log('');
      console.log('Checking total notifications in database...');
      const totalInDb = await req.db.collection('notifications').countDocuments({});
      console.log('Total notifications in database:', totalInDb);
      
      console.log('');
      console.log('Checking if any match by email...');
      const byEmail = await req.db.collection('notifications').countDocuments({ userEmail: userEmail });
      console.log('Notifications with email', userEmail, ':', byEmail);
      
      console.log('');
      console.log('Checking if any match by userId...');
      const byUserId = await req.db.collection('notifications').countDocuments({ userId: userId });
      console.log('Notifications with userId', userId, ':', byUserId);
    }
    console.log('='.repeat(80));
    console.log('');

    const total = await req.db.collection('notifications').countDocuments(query);
    const unreadCount = notifications.filter(n => !n.isRead).length;

    // Return format expected by frontend
    res.json({
      success: true,
      notifications: notifications,
      unreadCount: unreadCount,
      total: total
    });

  } catch (err) {
    console.error('❌ Error fetching notifications:', err.message);
    console.error('Stack:', err.stack);
    res.status(500).json({ success: false, message: 'Failed to fetch notifications' });
  }
});

// @route   GET api/notifications/unread-count
// @desc    Get unread notification count
// @access  Private
router.get('/unread-count', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;
    const { adminOnly } = req.query;

    // 🔥 FIX: Query by email OR userId
    const query = { 
      $or: [
        { userEmail: userEmail },
        { userId: userId }
      ],
      isRead: false 
    };

    if (adminOnly === 'true') {
      const adminTypes = [
        'leave_approved_admin', 'trip_cancelled', 'sos_alert', 
        'driver_report', 'vehicle_maintenance', 'roster_pending',
        'document_expired', 'document_expiring_soon',
      ];
      query.type = { $in: adminTypes };
    }

    const unreadCount = await req.db.collection('notifications').countDocuments(query);

    res.json({ success: true, data: { unreadCount } });

  } catch (err) {
    res.status(500).json({ success: false, message: 'Failed to fetch count' });
  }
});

// ========== MARK AS READ / DELETE ==========

// @route   PUT api/notifications/:id/read
// @desc    Mark a notification as read
// @access  Private
router.put('/:id/read', verifyToken, async (req, res) => {
  try {
    const notificationId = req.params.id;
    const userId = req.user.userId;
    const userEmail = req.user.email;

    console.log('\n📝 MARK NOTIFICATION AS READ');
    console.log('Notification ID:', notificationId);
    console.log('User ID:', userId);
    console.log('User Email:', userEmail);

    if (!ObjectId.isValid(notificationId)) {
      console.log('❌ Invalid ObjectId format');
      return res.status(400).json({ success: false, message: 'Invalid ID' });
    }

    // First, check if notification exists
    const notification = await req.db.collection('notifications').findOne({
      _id: new ObjectId(notificationId)
    });

    if (!notification) {
      console.log('❌ Notification not found in database');
      return res.status(404).json({ success: false, message: 'Notification not found' });
    }

    console.log('Found notification:');
    console.log('  userId:', notification.userId);
    console.log('  userEmail:', notification.userEmail);
    console.log('  type:', notification.type);
    console.log('  isRead:', notification.isRead);

    // Check if notification belongs to user
    const belongsToUser = notification.userEmail === userEmail || notification.userId === userId;
    if (!belongsToUser) {
      console.log('❌ Notification does not belong to this user');
      return res.status(404).json({ success: false, message: 'Notification not found' });
    }

    // 🔥 FIX: Match by email OR userId
    const result = await req.db.collection('notifications').findOneAndUpdate(
      { 
        _id: new ObjectId(notificationId),
        $or: [
          { userEmail: userEmail },
          { userId: userId }
        ]
      },
      { $set: { isRead: true, readAt: new Date() } },
      { returnDocument: 'after' }
    );

    if (!result.value) {
      console.log('❌ Failed to update notification');
      return res.status(404).json({ success: false, message: 'Notification not found' });
    }

    console.log('✅ Notification marked as read successfully');
    res.json({ success: true, message: 'Marked as read', data: result.value });

  } catch (err) {
    console.error('❌ Error updating notification:', err.message);
    res.status(500).json({ success: false, message: 'Error updating notification' });
  }
});

// @route   PUT api/notifications/read-all
// @desc    Mark all notifications as read
// @access  Private
router.put('/read-all', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;

    // 🔥 FIX: Match by email OR userId
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

    res.json({
      success: true,
      message: 'All notifications marked as read',
      data: { modifiedCount: result.modifiedCount }
    });

  } catch (err) {
    res.status(500).json({ success: false, message: 'Error updating notifications' });
  }
});

// @route   DELETE api/notifications/:id
// @desc    Delete a notification
// @access  Private
router.delete('/:id', verifyToken, async (req, res) => {
  try {
    const notificationId = req.params.id;
    const userId = req.user.userId;
    const userEmail = req.user.email;

    if (!ObjectId.isValid(notificationId)) {
      return res.status(400).json({ success: false, message: 'Invalid ID' });
    }

    // 🔥 FIX: Match by email OR userId
    const result = await req.db.collection('notifications').findOneAndDelete({
      _id: new ObjectId(notificationId),
      $or: [
        { userEmail: userEmail },
        { userId: userId }
      ]
    });

    if (!result.value) {
      return res.status(404).json({ success: false, message: 'Not found' });
    }

    res.json({ success: true, message: 'Deleted successfully' });

  } catch (err) {
    res.status(500).json({ success: false, message: 'Error deleting notification' });
  }
});

// ========== DOCUMENT EXPIRY NOTIFICATION SYSTEM ==========
// This logic uses FCM via NotificationModel

let documentExpiryCheckRunning = false;
let documentExpiryDb = null;

/**
 * Check all vehicle and driver documents for expiry
 */
async function checkDocumentExpiry() {
  if (documentExpiryCheckRunning) {
    console.log('⏭️  Document expiry check already running, skipping...');
    return;
  }

  documentExpiryCheckRunning = true;
  console.log('\n📄 DOCUMENT EXPIRY CHECK STARTED');

  try {
    const now = new Date();
    const tenDaysFromNow = new Date(now.getTime() + (10 * 24 * 60 * 60 * 1000));

    // Check vehicle documents
    await checkVehicleDocuments(now, tenDaysFromNow);

    // Check driver documents
    await checkDriverDocuments(now, tenDaysFromNow);

    console.log('✅ Document expiry check completed');
  } catch (error) {
    console.error('❌ Error in document expiry check:', error);
  } finally {
    documentExpiryCheckRunning = false;
  }
}

/**
 * Check vehicle documents for expiry
 */
async function checkVehicleDocuments(now, tenDaysFromNow) {
  if (!documentExpiryDb) return;
  
  const vehicles = await documentExpiryDb.collection('vehicles').find({}).toArray();

  for (const vehicle of vehicles) {
    // Check vehicle documents
    if (vehicle.documents && vehicle.documents.length > 0) {
      for (const doc of vehicle.documents) {
        if (doc.expiryDate) {
          await checkAndNotifyDocument(doc, now, tenDaysFromNow, 'vehicle', vehicle);
        }
      }
    }
    // Check driver documents attached to vehicle
    if (vehicle.driverDocuments && vehicle.driverDocuments.length > 0) {
      for (const doc of vehicle.driverDocuments) {
        if (doc.expiryDate) {
          await checkAndNotifyDocument(doc, now, tenDaysFromNow, 'driver', vehicle);
        }
      }
    }
  }
}

/**
 * Check driver documents for expiry
 */
async function checkDriverDocuments(now, tenDaysFromNow) {
  if (!documentExpiryDb) return;
  
  const drivers = await documentExpiryDb.collection('drivers').find({}).toArray();

  for (const driver of drivers) {
    if (driver.documents && driver.documents.length > 0) {
      for (const doc of driver.documents) {
        if (doc.expiryDate) {
          await checkAndNotifyDocument(doc, now, tenDaysFromNow, 'driver', driver);
        }
      }
    }
  }
}

/**
 * Check a single document and send notification if needed
 */
async function checkAndNotifyDocument(doc, now, tenDaysFromNow, type, entity) {
  if (!doc.expiryDate) return;
  
  const expiryDate = new Date(doc.expiryDate);
  if (isNaN(expiryDate.getTime())) return;
  
  const daysUntilExpiry = Math.ceil((expiryDate - now) / (1000 * 60 * 60 * 24));

  let shouldNotify = false;
  let notificationType = '';
  let priority = 'normal';

  if (expiryDate < now) {
    shouldNotify = true;
    notificationType = 'expired';
    priority = 'urgent';
  } else if (expiryDate <= tenDaysFromNow) {
    shouldNotify = true;
    notificationType = 'expiring_soon';
    priority = 'high';
  }

  if (shouldNotify) {
    // Check if notification sent today
    const alreadyNotified = await checkIfAlreadyNotified(doc.id, notificationType);
    if (!alreadyNotified) {
      await sendExpiryNotification(doc, type, entity, notificationType, daysUntilExpiry, priority);
    }
  }
}

/**
 * Check if notification was already sent today
 */
async function checkIfAlreadyNotified(documentId, notificationType) {
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const existingNotification = await documentExpiryDb.collection('notifications').findOne({
    'data.documentId': documentId,
    type: `document_${notificationType}`,
    createdAt: { $gte: today }
  });

  return existingNotification !== null;
}

/**
 * Send expiry notification to admin users using FCM
 */
async function sendExpiryNotification(doc, type, entity, notificationType, daysUntilExpiry, priority) {
  try {
    const adminUsers = await getAdminUsers();
    if (adminUsers.length === 0) return;

    const entityName = type === 'vehicle' 
      ? `${entity.registrationNumber || entity.vehicleId}` 
      : `${entity.personalInfo?.firstName || ''} ${entity.personalInfo?.lastName || ''}`.trim();

    const title = notificationType === 'expired'
      ? `⚠️ ${type === 'vehicle' ? 'Vehicle' : 'Driver'} Document Expired`
      : `⏰ ${type === 'vehicle' ? 'Vehicle' : 'Driver'} Document Expiring Soon`;

    const body = notificationType === 'expired'
      ? `${doc.documentName || doc.documentType} for ${entityName} has expired!`
      : `${doc.documentName || doc.documentType} for ${entityName} expires in ${daysUntilExpiry} day(s)`;

    // Send to each admin via NotificationModel (which handles FCM)
    for (const adminUser of adminUsers) {
      try {
        await createNotification(documentExpiryDb, {
          userId: adminUser.uid,
          userEmail: adminUser.email,
          userRole: 'admin',
          type: `document_${notificationType}`,
          title: title,
          body: body,
          priority: priority,
          category: 'document_management',
          data: {
            documentId: doc.id,
            documentName: doc.documentName || doc.documentType,
            expiryDate: doc.expiryDate,
            entityType: type,
            entityName: entityName
          },
          channels: ['fcm', 'database'] // Send via FCM + save to DB
        });
        console.log(`      ✅ Expiry Alert sent to admin: ${adminUser.email}`);
      } catch (error) {
        console.error(`      ❌ Failed to send to admin ${adminUser.email}:`, error.message);
      }
    }
  } catch (error) {
    console.error(`   ❌ Error sending expiry notification:`, error);
  }
}

/**
 * Get all admin users from MongoDB (Auth Agnostic)
 */
async function getAdminUsers() {
  try {
    if (!documentExpiryDb) return [];

    // Find admins in both collections
    const [adminUsers, employeeAdmins] = await Promise.all([
      documentExpiryDb.collection('admin_users').find({ 
        $or: [{ role: 'admin' }, { role: 'super_admin' }]
      }).toArray(),
      documentExpiryDb.collection('employee_admins').find({ 
        $or: [{ role: 'admin' }, { role: 'super_admin' }]
      }).toArray()
    ]);

    const allAdmins = [...adminUsers, ...employeeAdmins];

    return allAdmins.map(user => ({
      uid: user.firebaseUid || user._id.toString(), // Support both Auth types
      email: user.email,
      displayName: user.name
    }));
  } catch (error) {
    console.error('Error fetching admin users:', error);
    return [];
  }
}

/**
 * Start scheduled document expiry checks (every 6 hours)
 */
function startDocumentExpiryChecks(db) {
  if (!db) {
    console.error('❌ Cannot start expiry checks: DB missing');
    return;
  }
  documentExpiryDb = db;
  
  // Run after 10 seconds
  setTimeout(() => checkDocumentExpiry(), 10000);
  
  // Then every 6 hours
  setInterval(() => checkDocumentExpiry(), 6 * 60 * 60 * 1000);
  
  console.log('🕐 Document expiry checks scheduled (every 6 hrs)');
}

// Manual trigger (Admin only)
router.post('/check-document-expiry', verifyToken, async (req, res) => {
  try {
    if (req.user.role !== 'admin' && req.user.role !== 'super_admin') {
      return res.status(403).json({ success: false, message: 'Admins only' });
    }
    
    checkDocumentExpiry(); // Run background
    
    res.json({ success: true, message: 'Document check started' });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;
module.exports.startDocumentExpiryChecks = startDocumentExpiryChecks;