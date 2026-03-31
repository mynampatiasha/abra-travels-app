// routes/password_reset_router.js - Password reset via email
const express = require('express');
const router = express.Router();
const admin = require('../config/firebase'); // ✅ ADD THIS LINE

const emailService = require('../services/email_service');

// @route   POST /api/auth/forgot-password
// @desc    Send password reset email
// @access  Public
router.post('/forgot-password', async (req, res) => {
  try {
    const { email } = req.body;

    console.log('\n' + '='.repeat(80));
    console.log('🔐 PASSWORD RESET REQUEST');
    console.log('='.repeat(80));
    console.log('📧 Email:', email);
    console.log('🕐 Timestamp:', new Date().toISOString());
    console.log('-'.repeat(80));

    // Validate email
    if (!email || !email.trim()) {
      console.log('❌ FAILED: Email is required');
      console.log('='.repeat(80) + '\n');
      return res.status(400).json({
        success: false,
        message: 'Email address is required'
      });
    }

    const trimmedEmail = email.trim().toLowerCase();

    // Check if user exists in Firebase Auth
    let userRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(trimmedEmail);
      console.log('✅ User found in Firebase Auth');
      console.log('   UID:', userRecord.uid);
      console.log('   Email:', userRecord.email);
    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        console.log('❌ FAILED: User not found');
        console.log('='.repeat(80) + '\n');
        return res.status(404).json({
          success: false,
          message: 'No account found with this email address'
        });
      }
      throw error;
    }

    // Check if user exists in Firestore
    const userDoc = await admin.firestore()
      .collection('users')
      .doc(userRecord.uid)
      .get();

    if (!userDoc.exists) {
      console.log('⚠️ WARNING: User exists in Auth but not in Firestore');
    }

    const userData = userDoc.data() || {};
    const userName = userData.name || userRecord.displayName || 'User';

    console.log('-'.repeat(80));
    console.log('🔗 Generating password reset link...');

    // Generate password reset link using Firebase Admin SDK
    const passwordResetLink = await admin.auth().generatePasswordResetLink(trimmedEmail);
    
    console.log('✅ Password reset link generated');
    console.log('   Link length:', passwordResetLink.length, 'characters');
    console.log('   Link preview:', passwordResetLink.substring(0, 60) + '...');
    console.log('-'.repeat(80));
    console.log('📧 Sending password reset email...');

    // Send email using NodeMailer
    const emailResult = await emailService.sendPasswordResetEmail({
      email: trimmedEmail,
      name: userName,
      resetLink: passwordResetLink
    });

    if (emailResult.success) {
      console.log('='.repeat(80));
      console.log('✅ SUCCESS: Password reset email sent');
      console.log('   Message ID:', emailResult.messageId);
      console.log('   Recipient:', trimmedEmail);
      console.log('='.repeat(80) + '\n');

      res.json({
        success: true,
        message: 'Password reset email sent successfully. Please check your inbox.'
      });
    } else {
      console.log('='.repeat(80));
      console.log('❌ FAILED: Email sending failed');
      console.log('   Error:', emailResult.error);
      console.log('='.repeat(80) + '\n');

      res.status(500).json({
        success: false,
        message: 'Failed to send password reset email. Please try again later.'
      });
    }

  } catch (error) {
    console.log('='.repeat(80));
    console.log('❌ ERROR: Password reset failed');
    console.log('   Error:', error.message);
    console.log('   Stack:', error.stack);
    console.log('='.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      message: 'An error occurred while processing your request',
      error: error.message
    });
  }
});

module.exports = router;
