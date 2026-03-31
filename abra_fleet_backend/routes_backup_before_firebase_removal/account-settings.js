// routes/account-settings.js
const express = require('express');
const router = express.Router();


// Middleware to verify Firebase token
const verifyToken = async (req, res, next) => {
  try {
    const token = req.headers.authorization?.split('Bearer ')[1];
    if (!token) {
      return res.status(401).json({
        status: 'error',
        message: 'No token provided'
      });
    }
    
    const decodedToken = await admin.auth().verifyIdToken(token);
    req.userId = decodedToken.uid;
    next();
  } catch (error) {
    console.error('Token verification error:', error);
    res.status(401).json({
      status: 'error',
      message: 'Invalid token'
    });
  }
};

// GET - Retrieve notification preferences
router.get('/notification-preferences/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    
    const userDoc = await req.db.collection('users').findOne({
      _id: userId
    });

    if (!userDoc) {
      return res.status(404).json({
        status: 'error',
        message: 'User not found'
      });
    }

    const preferences = userDoc.notificationPreferences || {
      pushNotifications: true,
      emailNotifications: true,
      tripAlerts: true,
      documentAlerts: true
    };

    res.json({
      status: 'success',
      data: preferences
    });
  } catch (error) {
    console.error('Error retrieving notification preferences:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// POST - Update notification preferences
router.post('/notification-preferences/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const { pushNotifications, emailNotifications, tripAlerts, documentAlerts } = req.body;

    const result = await req.db.collection('users').updateOne(
      { _id: userId },
      {
        $set: {
          notificationPreferences: {
            pushNotifications: pushNotifications ?? true,
            emailNotifications: emailNotifications ?? true,
            tripAlerts: tripAlerts ?? true,
            documentAlerts: documentAlerts ?? true
          },
          updatedAt: new Date()
        }
      }
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({
        status: 'error',
        message: 'User not found'
      });
    }

    res.json({
      status: 'success',
      message: 'Notification preferences updated successfully'
    });
  } catch (error) {
    console.error('Error updating notification preferences:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// GET - Retrieve privacy settings
router.get('/privacy-settings/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    
    const userDoc = await req.db.collection('users').findOne({
      _id: userId
    });

    if (!userDoc) {
      return res.status(404).json({
        status: 'error',
        message: 'User not found'
      });
    }

    const settings = userDoc.privacySettings || {
      locationTracking: true,
      dataSharing: false
    };

    res.json({
      status: 'success',
      data: settings
    });
  } catch (error) {
    console.error('Error retrieving privacy settings:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// POST - Update privacy settings
router.post('/privacy-settings/:userId', async (req, res) => {
  try {
    const { userId } = req.params;
    const { locationTracking, dataSharing } = req.body;

    const result = await req.db.collection('users').updateOne(
      { _id: userId },
      {
        $set: {
          privacySettings: {
            locationTracking: locationTracking ?? true,
            dataSharing: dataSharing ?? false
          },
          updatedAt: new Date()
        }
      }
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({
        status: 'error',
        message: 'User not found'
      });
    }

    res.json({
      status: 'success',
      message: 'Privacy settings updated successfully'
    });
  } catch (error) {
    console.error('Error updating privacy settings:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// POST - Submit support issue
router.post('/submit-issue', async (req, res) => {
  try {
    const { driverId, email, issue } = req.body;

    if (!issue || issue.trim().length < 10) {
      return res.status(400).json({
        status: 'error',
        message: 'Issue description must be at least 10 characters'
      });
    }

    const issueDoc = {
      driverId,
      email,
      issue: issue.trim(),
      createdAt: new Date(),
      status: 'open',
      priority: 'normal',
      resolution: null,
      resolvedAt: null
    };

    const result = await req.db.collection('support_issues').insertOne(issueDoc);

    res.json({
      status: 'success',
      message: 'Issue reported successfully',
      issueId: result.insertedId
    });
  } catch (error) {
    console.error('Error submitting support issue:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// GET - Retrieve support issues for a driver
router.get('/support-issues/:driverId', async (req, res) => {
  try {
    const { driverId } = req.params;

    const issues = await req.db
      .collection('support_issues')
      .find({ driverId })
      .sort({ createdAt: -1 })
      .toArray();

    res.json({
      status: 'success',
      data: issues
    });
  } catch (error) {
    console.error('Error retrieving support issues:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// GET - Login history for security
router.get('/login-history/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const loginHistory = await req.db
      .collection('login_history')
      .find({ userId })
      .sort({ timestamp: -1 })
      .limit(20)
      .toArray();

    res.json({
      status: 'success',
      data: loginHistory
    });
  } catch (error) {
    console.error('Error retrieving login history:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// POST - Log login activity
router.post('/log-login', async (req, res) => {
  try {
    const { userId, email, ipAddress, userAgent, device } = req.body;

    await req.db.collection('login_history').insertOne({
      userId,
      email,
      ipAddress: ipAddress || 'unknown',
      userAgent: userAgent || 'unknown',
      device: device || 'unknown',
      timestamp: new Date(),
      status: 'success'
    });

    res.json({
      status: 'success',
      message: 'Login logged successfully'
    });
  } catch (error) {
    console.error('Error logging login:', error);
    // Don't fail the request if logging fails
    res.json({
      status: 'success',
      message: 'Login processed'
    });
  }
});

// GET - Account overview
router.get('/account-overview/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const userDoc = await req.db.collection('users').findOne({
      _id: userId
    });

    if (!userDoc) {
      return res.status(404).json({
        status: 'error',
        message: 'User not found'
      });
    }

    const overview = {
      name: userDoc.name || 'N/A',
      email: userDoc.email || 'N/A',
      phone: userDoc.phoneNumber || 'N/A',
      status: userDoc.status || 'Active',
      createdAt: userDoc.createdAt,
      lastLogin: userDoc.lastLogin,
      notificationPreferences: userDoc.notificationPreferences || {},
      privacySettings: userDoc.privacySettings || {}
    };

    res.json({
      status: 'success',
      data: overview
    });
  } catch (error) {
    console.error('Error retrieving account overview:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// POST - Request account deletion
router.post('/request-account-deletion/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const userDoc = await req.db.collection('users').findOne({
      _id: userId
    });

    if (!userDoc) {
      return res.status(404).json({
        status: 'error',
        message: 'User not found'
      });
    }

    // Create deletion request
    await req.db.collection('deletion_requests').insertOne({
      userId,
      email: userDoc.email,
      requestedAt: new Date(),
      status: 'pending',
      reason: 'User requested account deletion',
      deletionScheduledFor: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) // 30 days
    });

    res.json({
      status: 'success',
      message: 'Account deletion request submitted. Your account will be deleted in 30 days.'
    });
  } catch (error) {
    console.error('Error requesting account deletion:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// POST - Cancel account deletion request
router.post('/cancel-deletion-request/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const result = await req.db.collection('deletion_requests').updateOne(
      { userId, status: 'pending' },
      { $set: { status: 'cancelled', cancelledAt: new Date() } }
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({
        status: 'error',
        message: 'No pending deletion request found'
      });
    }

    res.json({
      status: 'success',
      message: 'Account deletion request cancelled'
    });
  } catch (error) {
    console.error('Error cancelling deletion request:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// GET - Check deletion request status
router.get('/deletion-request-status/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    const delRequest = await req.db.collection('deletion_requests').findOne({
      userId,
      status: 'pending'
    });

    if (!delRequest) {
      return res.json({
        status: 'success',
        data: {
          hasPendingRequest: false
        }
      });
    }

    res.json({
      status: 'success',
      data: {
        hasPendingRequest: true,
        requestedAt: delRequest.requestedAt,
        deletionScheduledFor: delRequest.deletionScheduledFor,
        daysRemaining: Math.ceil(
          (delRequest.deletionScheduledFor - new Date()) / (1000 * 60 * 60 * 24)
        )
      }
    });
  } catch (error) {
    console.error('Error checking deletion status:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// ADMIN - Get all support issues
router.get('/admin/support-issues', async (req, res) => {
  try {
    const issues = await req.db
      .collection('support_issues')
      .find({})
      .sort({ createdAt: -1 })
      .toArray();

    res.json({
      status: 'success',
      data: issues,
      total: issues.length
    });
  } catch (error) {
    console.error('Error retrieving all support issues:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// ADMIN - Update support issue status
router.patch('/admin/support-issues/:issueId', async (req, res) => {
  try {
    const { issueId } = req.params;
    const { status, resolution } = req.body;
    const { ObjectId } = require('mongodb');

    const updateData = {
      status,
      updatedAt: new Date()
    };

    if (resolution) {
      updateData.resolution = resolution;
      updateData.resolvedAt = new Date();
    }

    const result = await req.db.collection('support_issues').updateOne(
      { _id: new ObjectId(issueId) },
      { $set: updateData }
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({
        status: 'error',
        message: 'Issue not found'
      });
    }

    res.json({
      status: 'success',
      message: 'Support issue updated successfully'
    });
  } catch (error) {
    console.error('Error updating support issue:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// GET - Document expiry alerts
router.get('/document-expiry-alerts/:userId', async (req, res) => {
  try {
    const { userId } = req.params;

    // Find driver and check document expiry dates
    const driver = await req.db.collection('drivers').findOne({
      firebaseUid: userId
    });

    if (!driver) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver not found'
      });
    }

    const alerts = [];
    const now = new Date();
    const thirtyDaysFromNow = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);

    // Check license expiry
    if (driver.documents?.license?.expiryDate) {
      const expiryDate = new Date(driver.documents.license.expiryDate);
      if (expiryDate <= thirtyDaysFromNow && expiryDate > now) {
        alerts.push({
          type: 'license',
          message: 'License expiring soon',
          expiryDate: expiryDate,
          daysUntilExpiry: Math.ceil((expiryDate - now) / (1000 * 60 * 60 * 24))
        });
      } else if (expiryDate <= now) {
        alerts.push({
          type: 'license',
          message: 'License has expired',
          expiryDate: expiryDate,
          daysUntilExpiry: 0,
          expired: true
        });
      }
    }

    // Check medical certificate expiry
    if (driver.documents?.medicalCertificate?.expiryDate) {
      const expiryDate = new Date(driver.documents.medicalCertificate.expiryDate);
      if (expiryDate <= thirtyDaysFromNow && expiryDate > now) {
        alerts.push({
          type: 'medicalCertificate',
          message: 'Medical certificate expiring soon',
          expiryDate: expiryDate,
          daysUntilExpiry: Math.ceil((expiryDate - now) / (1000 * 60 * 60 * 24))
        });
      } else if (expiryDate <= now) {
        alerts.push({
          type: 'medicalCertificate',
          message: 'Medical certificate has expired',
          expiryDate: expiryDate,
          daysUntilExpiry: 0,
          expired: true
        });
      }
    }

    res.json({
      status: 'success',
      data: {
        alerts: alerts,
        hasExpiringDocuments: alerts.length > 0
      }
    });
  } catch (error) {
    console.error('Error retrieving document expiry alerts:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

module.exports = router;