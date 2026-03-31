// routes/user_management_router.js - User management routes for admin
const express = require('express');
const router = express.Router();


// Middleware to attach database
router.use((req, res, next) => {
  if (!req.db) {
    return res.status(500).json({ msg: 'Database connection not available' });
  }
  next();
});

// @route   POST /api/users/update-password
// @desc    Update user password (admin only, no current password required)
// @access  Private (Admin)
router.post('/update-password', async (req, res) => {
  try {
    const { userId, newPassword } = req.body;
    
    console.log('🔐 Password update request received');
    console.log('   User ID:', userId);
    console.log('   Requested by:', req.user?.uid);
    
    // Validate input
    if (!userId || !newPassword) {
      return res.status(400).json({
        success: false,
        message: 'User ID and new password are required'
      });
    }
    
    // Validate password strength
    if (newPassword.length < 6) {
      return res.status(400).json({
        success: false,
        message: 'Password must be at least 6 characters long'
      });
    }
    
    // Verify the requesting user is an admin
    if (req.user?.role !== 'admin') {
      return res.status(403).json({
        success: false,
        message: 'Only administrators can update user passwords'
      });
    }
    
    // Update password using Firebase Admin SDK
    await admin.auth().updateUser(userId, {
      password: newPassword
    });
    
    console.log('✅ Password updated successfully for user:', userId);
    
    // Log the password change in Firestore
    await admin.firestore().collection('password_changes').add({
      userId: userId,
      changedBy: req.user.userId,
      changedAt: admin.firestore.FieldValue.serverTimestamp(),
      method: 'admin_update'
    });
    
    res.json({
      success: true,
      message: 'Password updated successfully'
    });
    
  } catch (error) {
    console.error('❌ Error updating password:', error);
    
    // Handle specific Firebase errors
    if (error.code === 'auth/user-not-found') {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    res.status(500).json({
      success: false,
      message: 'Failed to update password',
      error: error.message
    });
  }
});

// @route   POST /api/users/process-password-queue
// @desc    Process queued password update requests
// @access  Private (Admin/System)
router.post('/process-password-queue', async (req, res) => {
  try {
    console.log('🔄 Processing password update queue...');
    
    // Get pending password updates from Firestore
    const queueSnapshot = await admin.firestore()
      .collection('password_update_queue')
      .where('status', '==', 'pending')
      .limit(10)
      .get();
    
    if (queueSnapshot.empty) {
      return res.json({
        success: true,
        message: 'No pending password updates',
        processed: 0
      });
    }
    
    let processed = 0;
    let failed = 0;
    const results = [];
    
    for (const doc of queueSnapshot.docs) {
      const data = doc.data();
      
      try {
        // Update password using Firebase Admin SDK
        await admin.auth().updateUser(data.userId, {
          password: data.newPassword
        });
        
        // Mark as completed
        await doc.ref.update({
          status: 'completed',
          completedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        
        // Log the change
        await admin.firestore().collection('password_changes').add({
          userId: data.userId,
          changedBy: data.requestedBy,
          changedAt: admin.firestore.FieldValue.serverTimestamp(),
          method: 'queue_processing'
        });
        
        processed++;
        results.push({
          userId: data.userId,
          email: data.email,
          status: 'success'
        });
        
        console.log(`✅ Password updated for: ${data.email}`);
        
      } catch (error) {
        console.error(`❌ Failed to update password for ${data.email}:`, error);
        
        // Mark as failed
        await doc.ref.update({
          status: 'failed',
          error: error.message,
          failedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        
        failed++;
        results.push({
          userId: data.userId,
          email: data.email,
          status: 'failed',
          error: error.message
        });
      }
    }
    
    console.log(`✅ Queue processing complete: ${processed} succeeded, ${failed} failed`);
    
    res.json({
      success: true,
      message: `Processed ${processed + failed} password updates`,
      processed,
      failed,
      results
    });
    
  } catch (error) {
    console.error('❌ Error processing password queue:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to process password queue',
      error: error.message
    });
  }
});

module.exports = router;
