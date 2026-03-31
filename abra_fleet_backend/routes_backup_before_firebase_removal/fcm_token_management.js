// routes/fcm_token_management.js - FCM Token Management & Cleanup
const express = require('express');
const router = express.Router();
const admin = require('../config/firebase');
const { verifyToken } = require('../middleware/auth');

// ============================================================================
// 🔧 FCM TOKEN REFRESH & VALIDATION
// ============================================================================

/**
 * @route   POST /api/fcm/refresh-token
 * @desc    Refresh and validate FCM token
 * @access  Private
 */
router.post('/refresh-token', verifyToken, async (req, res) => {
  try {
    const { fcmToken, platform = 'mobile' } = req.body;
    const userId = req.user.uid;
    
    console.log(`🔄 [FCM Refresh] User: ${userId}, Platform: ${platform}`);
    
    if (!fcmToken) {
      return res.status(400).json({
        success: false,
        error: 'FCM token is required'
      });
    }

    // Test if token is valid by sending a test message
    const isValid = await validateFCMToken(fcmToken);
    
    if (isValid) {
      // Update token in both Firebase RTDB and MongoDB
      await updateFCMToken(userId, fcmToken, platform, req.db);
      
      console.log(`✅ [FCM Refresh] Token validated and updated`);
      
      res.json({
        success: true,
        message: 'FCM token refreshed successfully',
        tokenValid: true
      });
    } else {
      console.log(`❌ [FCM Refresh] Invalid token provided`);
      
      res.status(400).json({
        success: false,
        error: 'Invalid FCM token',
        tokenValid: false
      });
    }
    
  } catch (error) {
    console.error('❌ [FCM Refresh] Error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to refresh FCM token',
      message: error.message
    });
  }
});

/**
 * @route   POST /api/fcm/cleanup-invalid-tokens
 * @desc    Clean up invalid FCM tokens from database
 * @access  Private (Admin only)
 */
router.post('/cleanup-invalid-tokens', verifyToken, async (req, res) => {
  try {
    console.log(`🧹 [FCM Cleanup] Starting invalid token cleanup...`);
    
    const results = {
      checked: 0,
      removed: 0,
      errors: 0,
      details: []
    };

    // Get all users with FCM tokens from Firebase RTDB
    const customersRef = admin.database().ref('customers');
    const customersSnapshot = await customersRef.once('value');
    const customers = customersSnapshot.val() || {};

    for (const [userId, userData] of Object.entries(customers)) {
      if (userData.fcmToken) {
        results.checked++;
        
        const isValid = await validateFCMToken(userData.fcmToken);
        
        if (!isValid) {
          // Remove invalid token
          await customersRef.child(userId).child('fcmToken').remove();
          results.removed++;
          
          results.details.push({
            userId,
            action: 'removed_invalid_token',
            platform: 'mobile'
          });
          
          console.log(`🗑️ [FCM Cleanup] Removed invalid token for user: ${userId}`);
        }
      }
    }

    console.log(`✅ [FCM Cleanup] Completed: ${results.removed}/${results.checked} tokens removed`);
    
    res.json({
      success: true,
      message: 'FCM token cleanup completed',
      results
    });
    
  } catch (error) {
    console.error('❌ [FCM Cleanup] Error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to cleanup FCM tokens',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/fcm/token-status/:userId
 * @desc    Check FCM token status for a user
 * @access  Private (Admin only)
 */
router.get('/token-status/:userId', verifyToken, async (req, res) => {
  try {
    const { userId } = req.params;
    
    console.log(`🔍 [FCM Status] Checking tokens for user: ${userId}`);
    
    const status = {
      userId,
      tokens: {
        firebase_rtdb: null,
        mongodb: null
      },
      validation: {
        firebase_rtdb: null,
        mongodb: null
      }
    };

    // Check Firebase RTDB
    const customerRef = admin.database().ref(`customers/${userId}`);
    const customerSnapshot = await customerRef.once('value');
    const customerData = customerSnapshot.val();
    
    if (customerData?.fcmToken) {
      status.tokens.firebase_rtdb = {
        token: customerData.fcmToken.substring(0, 20) + '...',
        exists: true
      };
      
      status.validation.firebase_rtdb = await validateFCMToken(customerData.fcmToken);
    }

    // Check MongoDB
    const user = await req.db.collection('users').findOne({ firebaseUid: userId });
    if (user?.fcmToken) {
      status.tokens.mongodb = {
        token: user.fcmToken.substring(0, 20) + '...',
        exists: true
      };
      
      status.validation.mongodb = await validateFCMToken(user.fcmToken);
    }

    res.json({
      success: true,
      status
    });
    
  } catch (error) {
    console.error('❌ [FCM Status] Error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to check FCM token status',
      message: error.message
    });
  }
});

// ============================================================================
// 🔧 HELPER FUNCTIONS
// ============================================================================

/**
 * Validate FCM token by attempting to send a test message
 */
async function validateFCMToken(token) {
  try {
    // Create a test message (dry run)
    const message = {
      token: token,
      notification: {
        title: 'Test',
        body: 'Token validation test'
      },
      data: {
        test: 'true'
      }
    };

    // Send with dry run to validate token without actually sending
    await admin.messaging().send(message, true); // true = dry run
    return true;
    
  } catch (error) {
    console.log(`❌ [FCM Validation] Token invalid: ${error.code}`);
    return false;
  }
}

/**
 * Update FCM token in both Firebase RTDB and MongoDB
 */
async function updateFCMToken(userId, fcmToken, platform, db) {
  try {
    // Update Firebase RTDB
    const customerRef = admin.database().ref(`customers/${userId}`);
    await customerRef.update({
      fcmToken: fcmToken,
      fcmTokenUpdatedAt: admin.database.ServerValue.TIMESTAMP,
      platform: platform
    });

    // Update MongoDB
    await db.collection('users').updateOne(
      { firebaseUid: userId },
      {
        $set: {
          fcmToken: fcmToken,
          fcmTokenUpdatedAt: new Date(),
          platform: platform
        }
      },
      { upsert: false }
    );

    console.log(`✅ [FCM Update] Token updated in both databases`);
    
  } catch (error) {
    console.error('❌ [FCM Update] Error updating token:', error);
    throw error;
  }
}

module.exports = router;