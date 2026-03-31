// routes/customer_approval_router.js - Customer approval routes with email notifications
const express = require('express');
const router = express.Router();

const emailService = require('../services/email_service');

// Middleware to attach database
router.use((req, res, next) => {
  if (!req.db) {
    return res.status(500).json({ msg: 'Database connection not available' });
  }
  next();
});

// @route   POST /api/customer-approval/approve
// @desc    Approve a pending customer and send email notification
// @access  Private (Admin)
router.post('/approve', async (req, res) => {
  try {
    const { customerId } = req.body;
    
    console.log('✅ Customer approval request received');
    console.log('   Customer ID:', customerId);
    console.log('   Requested by:', req.user?.uid);
    
    // Validate input
    if (!customerId) {
      return res.status(400).json({
        success: false,
        message: 'Customer ID is required'
      });
    }
    
    // Fetch the requesting user's role from Firestore
    const requestingUserDoc = await admin.firestore()
      .collection('users')
      .doc(req.user.uid)
      .get();
    
    const requestingUserRole = requestingUserDoc.exists ? requestingUserDoc.data().role : null;
    console.log('   Requesting user role:', requestingUserRole);
    
    // Verify the requesting user is an admin
    if (requestingUserRole !== 'admin') {
      return res.status(403).json({
        success: false,
        message: 'Only administrators can approve customers'
      });
    }
    
    // Get customer details from Firestore
    const customerDoc = await admin.firestore()
      .collection('users')
      .doc(customerId)
      .get();
    
    if (!customerDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Customer not found'
      });
    }
    
    const customerData = customerDoc.data();
    const customerName = customerData.name || 'Customer';
    const customerEmail = customerData.email;
    const companyName = customerData.companyName || 'your organization';
    
    // Generate password reset link for the customer
    let passwordResetLink = null;
    try {
      passwordResetLink = await admin.auth().generatePasswordResetLink(customerEmail);
      console.log('✅ Password reset link generated');
    } catch (linkError) {
      console.error('⚠️ Failed to generate password reset link:', linkError.message);
      // Continue even if link generation fails
    }
    
    // Update customer status in Firestore
    await admin.firestore().collection('users').doc(customerId).update({
      status: 'Active',
      isPendingApproval: false,
      approvedAt: admin.firestore.FieldValue.serverTimestamp(),
      approvedBy: req.user.uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      passwordSetupRequired: true, // Flag to indicate password needs to be set
    });
    
    console.log('✅ Customer status updated to Active');
    
    // Send in-app notification to Firebase RTDB
    try {
      const notificationRef = admin.database()
        .ref(`notifications/${customerId}`)
        .push();

      await notificationRef.set({
        id: notificationRef.key,
        userId: customerId,
        type: 'account_approved',
        category: 'account',
        title: '🎉 Welcome to Abra Travels!',
        message: `Great news, ${customerName}! Your account has been approved by the administrator. You can now access all features and start using Abra Travels services for ${companyName}. We're excited to have you on board!`,
        priority: 'high',
        isRead: false,
        createdAt: new Date().toISOString(),
        metadata: {
          action: 'account_activated',
          companyName: companyName,
        },
      });

      console.log('✅ In-app notification sent to customer');
    } catch (notifError) {
      console.error('⚠️ Failed to send in-app notification:', notifError);
      // Don't fail the approval if notification fails
    }
    
    // DELETE customer registration notifications for all admins
    try {
      console.log('🧹 Cleaning up customer registration notifications for admins...');
      
      // Get all admin users
      const adminsSnapshot = await admin.firestore()
        .collection('users')
        .where('role', '==', 'admin')
        .get();
      
      const adminIds = adminsSnapshot.docs.map(doc => doc.id);
      console.log(`   Found ${adminIds.length} admin users`);
      
      let deletedCount = 0;
      
      // For each admin, find and delete notifications about this customer
      for (const adminId of adminIds) {
        const notificationsRef = admin.database().ref(`notifications/${adminId}`);
        const snapshot = await notificationsRef
          .orderByChild('type')
          .equalTo('customer_registration')
          .once('value');
        
        if (snapshot.exists()) {
          const notifications = snapshot.val();
          
          // Delete notifications that match this customer
          for (const [notifId, notifData] of Object.entries(notifications)) {
            // Check if this notification is about the approved customer
            const notifCustomerId = notifData.metadata?.customerId || notifData.data?.customerId;
            const notifCustomerEmail = notifData.metadata?.customerEmail || notifData.data?.customerEmail;
            
            if (notifCustomerId === customerId || notifCustomerEmail === customerEmail) {
              await notificationsRef.child(notifId).remove();
              deletedCount++;
              console.log(`   ✅ Deleted notification ${notifId} for admin ${adminId}`);
            }
          }
        }
      }
      
      console.log(`✅ Cleaned up ${deletedCount} customer registration notifications`);
      
      // Also delete from MongoDB if you're storing notifications there
      try {
        const mongoResult = await req.db.collection('notifications').deleteMany({
          type: 'customer_registration',
          $or: [
            { 'metadata.customerId': customerId },
            { 'data.customerId': customerId },
            { 'metadata.customerEmail': customerEmail },
            { 'data.customerEmail': customerEmail }
          ]
        });
        console.log(`✅ Deleted ${mongoResult.deletedCount} notifications from MongoDB`);
      } catch (mongoError) {
        console.error('⚠️ Failed to delete from MongoDB:', mongoError.message);
      }
      
    } catch (cleanupError) {
      console.error('⚠️ Failed to cleanup notifications:', cleanupError);
      // Don't fail the approval if cleanup fails
    }
    
    // Send email notification with password setup link
    let emailResult = { success: false };
    if (customerEmail) {
      emailResult = await emailService.sendCustomerApprovalEmail({
        email: customerEmail,
        name: customerName,
        companyName: companyName,
        passwordResetLink: passwordResetLink, // Include the password reset link
      });
      
      if (emailResult.success) {
        console.log('✅ Email notification with password setup link sent successfully');
      } else {
        console.warn('⚠️ Email notification failed:', emailResult.error);
      }
    }
    
    res.json({
      success: true,
      message: 'Customer approved successfully',
      emailSent: emailResult.success,
      customer: {
        id: customerId,
        name: customerName,
        email: customerEmail,
        companyName: companyName,
      }
    });
    
  } catch (error) {
    console.error('❌ Error approving customer:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to approve customer',
      error: error.message
    });
  }
});

// @route   POST /api/customer-approval/reject
// @desc    Reject a pending customer and send email notification
// @access  Private (Admin)
router.post('/reject', async (req, res) => {
  try {
    const { customerId, reason } = req.body;
    
    console.log('❌ Customer rejection request received');
    console.log('   Customer ID:', customerId);
    console.log('   Reason:', reason);
    console.log('   Requested by:', req.user?.uid);
    
    // Validate input
    if (!customerId) {
      return res.status(400).json({
        success: false,
        message: 'Customer ID is required'
      });
    }
    
    // Fetch the requesting user's role from Firestore
    const requestingUserDoc = await admin.firestore()
      .collection('users')
      .doc(req.user.uid)
      .get();
    
    const requestingUserRole = requestingUserDoc.exists ? requestingUserDoc.data().role : null;
    console.log('   Requesting user role:', requestingUserRole);
    
    // Verify the requesting user is an admin
    if (requestingUserRole !== 'admin') {
      return res.status(403).json({
        success: false,
        message: 'Only administrators can reject customers'
      });
    }
    
    // Get customer details from Firestore
    const customerDoc = await admin.firestore()
      .collection('users')
      .doc(customerId)
      .get();
    
    if (!customerDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Customer not found'
      });
    }
    
    const customerData = customerDoc.data();
    const customerName = customerData.name || 'Customer';
    const customerEmail = customerData.email;
    
    // Update customer status in Firestore
    await admin.firestore().collection('users').doc(customerId).update({
      status: 'Rejected',
      isPendingApproval: false,
      rejectionReason: reason || 'Not specified',
      rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
      rejectedBy: req.user.uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    
    console.log('✅ Customer status updated to Rejected');
    
    // DELETE customer registration notifications for all admins
    try {
      console.log('🧹 Cleaning up customer registration notifications for admins...');
      
      // Get all admin users
      const adminsSnapshot = await admin.firestore()
        .collection('users')
        .where('role', '==', 'admin')
        .get();
      
      const adminIds = adminsSnapshot.docs.map(doc => doc.id);
      console.log(`   Found ${adminIds.length} admin users`);
      
      let deletedCount = 0;
      
      // For each admin, find and delete notifications about this customer
      for (const adminId of adminIds) {
        const notificationsRef = admin.database().ref(`notifications/${adminId}`);
        const snapshot = await notificationsRef
          .orderByChild('type')
          .equalTo('customer_registration')
          .once('value');
        
        if (snapshot.exists()) {
          const notifications = snapshot.val();
          
          // Delete notifications that match this customer
          for (const [notifId, notifData] of Object.entries(notifications)) {
            const notifCustomerId = notifData.metadata?.customerId || notifData.data?.customerId;
            const notifCustomerEmail = notifData.metadata?.customerEmail || notifData.data?.customerEmail;
            
            if (notifCustomerId === customerId || notifCustomerEmail === customerEmail) {
              await notificationsRef.child(notifId).remove();
              deletedCount++;
              console.log(`   ✅ Deleted notification ${notifId} for admin ${adminId}`);
            }
          }
        }
      }
      
      console.log(`✅ Cleaned up ${deletedCount} customer registration notifications`);
      
      // Also delete from MongoDB
      try {
        const mongoResult = await req.db.collection('notifications').deleteMany({
          type: 'customer_registration',
          $or: [
            { 'metadata.customerId': customerId },
            { 'data.customerId': customerId },
            { 'metadata.customerEmail': customerEmail },
            { 'data.customerEmail': customerEmail }
          ]
        });
        console.log(`✅ Deleted ${mongoResult.deletedCount} notifications from MongoDB`);
      } catch (mongoError) {
        console.error('⚠️ Failed to delete from MongoDB:', mongoError.message);
      }
      
    } catch (cleanupError) {
      console.error('⚠️ Failed to cleanup notifications:', cleanupError);
      // Don't fail the rejection if cleanup fails
    }
    
    // Send email notification
    let emailResult = { success: false };
    if (customerEmail) {
      emailResult = await emailService.sendCustomerRejectionEmail({
        email: customerEmail,
        name: customerName,
        reason: reason || 'Not specified',
      });
      
      if (emailResult.success) {
        console.log('✅ Rejection email sent successfully');
      } else {
        console.warn('⚠️ Rejection email failed:', emailResult.error);
      }
    }
    
    res.json({
      success: true,
      message: 'Customer rejected successfully',
      emailSent: emailResult.success,
      customer: {
        id: customerId,
        name: customerName,
        email: customerEmail,
      }
    });
    
  } catch (error) {
    console.error('❌ Error rejecting customer:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to reject customer',
      error: error.message
    });
  }
});

// @route   POST /api/customer-approval/bulk-approve
// @desc    Bulk approve multiple pending customers
// @access  Private (Admin)
router.post('/bulk-approve', async (req, res) => {
  try {
    const { customerIds } = req.body;
    
    console.log('✅ Bulk approval request received');
    console.log('   Customer count:', customerIds?.length);
    console.log('   Requested by:', req.user?.uid);
    
    // Validate input
    if (!customerIds || !Array.isArray(customerIds) || customerIds.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Customer IDs array is required'
      });
    }
    
    // Verify the requesting user is an admin
    if (req.user?.role !== 'admin') {
      return res.status(403).json({
        success: false,
        message: 'Only administrators can approve customers'
      });
    }
    
    const results = [];
    let successCount = 0;
    let failCount = 0;
    
    for (const customerId of customerIds) {
      try {
        // Get customer details
        const customerDoc = await admin.firestore()
          .collection('users')
          .doc(customerId)
          .get();
        
        if (!customerDoc.exists) {
          results.push({
            customerId,
            success: false,
            error: 'Customer not found'
          });
          failCount++;
          continue;
        }
        
        const customerData = customerDoc.data();
        const customerName = customerData.name || 'Customer';
        const customerEmail = customerData.email;
        const companyName = customerData.companyName || 'your organization';
        
        // Update status
        await admin.firestore().collection('users').doc(customerId).update({
          status: 'Active',
          isPendingApproval: false,
          approvedAt: admin.firestore.FieldValue.serverTimestamp(),
          approvedBy: req.user.uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        // Send in-app notification
        try {
          const notificationRef = admin.database()
            .ref(`notifications/${customerId}`)
            .push();

          await notificationRef.set({
            id: notificationRef.key,
            userId: customerId,
            type: 'account_approved',
            category: 'account',
            title: '🎉 Welcome to Abra Travels!',
            message: `Great news, ${customerName}! Your account has been approved. You can now access all features.`,
            priority: 'high',
            isRead: false,
            createdAt: new Date().toISOString(),
            metadata: {
              action: 'account_activated',
              companyName: companyName,
            },
          });
        } catch (notifError) {
          console.error('⚠️ Failed to send in-app notification:', notifError);
        }
        
        // Send email
        let emailSent = false;
        if (customerEmail) {
          const emailResult = await emailService.sendCustomerApprovalEmail({
            email: customerEmail,
            name: customerName,
            companyName: companyName,
          });
          emailSent = emailResult.success;
        }
        
        // Cleanup notifications for this customer
        try {
          const adminsSnapshot = await admin.firestore()
            .collection('users')
            .where('role', '==', 'admin')
            .get();
          
          const adminIds = adminsSnapshot.docs.map(doc => doc.id);
          
          for (const adminId of adminIds) {
            const notificationsRef = admin.database().ref(`notifications/${adminId}`);
            const snapshot = await notificationsRef
              .orderByChild('type')
              .equalTo('customer_registration')
              .once('value');
            
            if (snapshot.exists()) {
              const notifications = snapshot.val();
              
              for (const [notifId, notifData] of Object.entries(notifications)) {
                const notifCustomerId = notifData.metadata?.customerId || notifData.data?.customerId;
                const notifCustomerEmail = notifData.metadata?.customerEmail || notifData.data?.customerEmail;
                
                if (notifCustomerId === customerId || notifCustomerEmail === customerEmail) {
                  await notificationsRef.child(notifId).remove();
                }
              }
            }
          }
          
          // Delete from MongoDB
          await req.db.collection('notifications').deleteMany({
            type: 'customer_registration',
            $or: [
              { 'metadata.customerId': customerId },
              { 'data.customerId': customerId },
              { 'metadata.customerEmail': customerEmail },
              { 'data.customerEmail': customerEmail }
            ]
          });
        } catch (cleanupError) {
          console.error('⚠️ Failed to cleanup notifications:', cleanupError);
        }
        
        results.push({
          customerId,
          success: true,
          emailSent,
          customerName,
          customerEmail,
        });
        successCount++;
        
      } catch (error) {
        console.error(`❌ Error approving customer ${customerId}:`, error);
        results.push({
          customerId,
          success: false,
          error: error.message
        });
        failCount++;
      }
    }
    
    console.log(`✅ Bulk approval complete: ${successCount} succeeded, ${failCount} failed`);
    
    res.json({
      success: true,
      message: `Processed ${customerIds.length} customers`,
      successCount,
      failCount,
      results
    });
    
  } catch (error) {
    console.error('❌ Error in bulk approval:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to process bulk approval',
      error: error.message
    });
  }
});

// @route   GET /api/customer-approval/pending
// @desc    Get all pending customer approvals
// @access  Private (Admin)
router.get('/pending', async (req, res) => {
  try {
    console.log('📥 Fetching pending customers');
    console.log('   Requested by:', req.user?.uid);
    
    // Verify the requesting user is an admin
    if (req.user?.role !== 'admin') {
      return res.status(403).json({
        success: false,
        message: 'Only administrators can view pending customers'
      });
    }
    
    const snapshot = await admin.firestore()
      .collection('users')
      .where('isPendingApproval', '==', true)
      .orderBy('registrationDate', 'desc')
      .get();
    
    const pendingCustomers = snapshot.docs.map(doc => ({
      id: doc.id,
      ...doc.data()
    }));
    
    console.log(`✅ Found ${pendingCustomers.length} pending customers`);
    
    res.json({
      success: true,
      count: pendingCustomers.length,
      customers: pendingCustomers
    });
    
  } catch (error) {
    console.error('❌ Error fetching pending customers:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch pending customers',
      error: error.message
    });
  }
});

module.exports = router;


// @route   POST /api/customer-approval/send-welcome-email
// @desc    Send welcome email with password setup link (for admin-created customers)
// @access  Private (Admin)
router.post('/send-welcome-email', async (req, res) => {
  console.log('\n' + '='.repeat(80));
  console.log('📧 BACKEND - SEND WELCOME EMAIL ENDPOINT');
  console.log('='.repeat(80));
  console.log('🔹 Timestamp:', new Date().toISOString());
  console.log('🔹 Request Method:', req.method);
  console.log('🔹 Request Path:', req.path);
  console.log('-'.repeat(80));
  
  try {
    const { customerId, customerEmail, customerName, companyName } = req.body;
    
    console.log('📦 Request Body:');
    console.log('   Customer ID:', customerId);
    console.log('   Customer Email:', customerEmail);
    console.log('   Customer Name:', customerName);
    console.log('   Company Name:', companyName || 'N/A');
    console.log('-'.repeat(80));
    
    // Validate input
    if (!customerId || !customerEmail || !customerName) {
      console.log('❌ VALIDATION FAILED: Missing required fields');
      console.log('   customerId:', customerId ? 'PROVIDED' : 'MISSING');
      console.log('   customerEmail:', customerEmail ? 'PROVIDED' : 'MISSING');
      console.log('   customerName:', customerName ? 'PROVIDED' : 'MISSING');
      console.log('='.repeat(80) + '\n');
      return res.status(400).json({
        success: false,
        message: 'Customer ID, email, and name are required'
      });
    }
    
    console.log('✅ Validation passed');
    console.log('-'.repeat(80));
    console.log('🔐 Generating Firebase password reset link...');
    
    // Generate password reset link for the customer
    let passwordResetLink = null;
    try {
      passwordResetLink = await admin.auth().generatePasswordResetLink(customerEmail);
      console.log('✅ Password reset link generated successfully');
      console.log('   Link length:', passwordResetLink.length, 'characters');
      console.log('   Link preview:', passwordResetLink.substring(0, 50) + '...');
    } catch (linkError) {
      console.log('='.repeat(80));
      console.log('❌ FAILED: Could not generate password reset link');
      console.log('🔹 Error Code:', linkError.code);
      console.log('🔹 Error Message:', linkError.message);
      console.log('='.repeat(80) + '\n');
      return res.status(500).json({
        success: false,
        message: 'Failed to generate password reset link',
        error: linkError.message
      });
    }
    
    console.log('-'.repeat(80));
    console.log('📧 Calling email service...');
    
    // Send welcome email with password setup link
    const emailResult = await emailService.sendCustomerApprovalEmail({
      email: customerEmail,
      name: customerName,
      companyName: companyName || 'N/A',
      passwordResetLink: passwordResetLink,
    });
    
    console.log('-'.repeat(80));
    console.log('📬 Email Service Result:');
    console.log('   Success:', emailResult.success);
    console.log('   Message ID:', emailResult.messageId || 'N/A');
    console.log('   Error:', emailResult.error || 'None');
    
    if (emailResult.success) {
      console.log('='.repeat(80));
      console.log('✅ SUCCESS: Welcome email sent successfully');
      console.log('🔹 Recipient:', customerEmail);
      console.log('🔹 Message ID:', emailResult.messageId);
      console.log('='.repeat(80) + '\n');
      return res.json({
        success: true,
        message: 'Welcome email sent successfully',
        emailSent: true,
        messageId: emailResult.messageId
      });
    } else {
      console.log('='.repeat(80));
      console.log('⚠️ WARNING: Email service returned failure');
      console.log('🔹 Error:', emailResult.error);
      console.log('='.repeat(80) + '\n');
      return res.status(500).json({
        success: false,
        message: 'Failed to send email',
        emailSent: false,
        error: emailResult.error
      });
    }
    
  } catch (error) {
    console.log('='.repeat(80));
    console.log('❌ EXCEPTION: Unexpected error in welcome email endpoint');
    console.log('🔹 Error:', error.message);
    console.log('🔹 Stack:', error.stack);
    console.log('='.repeat(80) + '\n');
    res.status(500).json({
      success: false,
      message: 'Failed to send welcome email',
      error: error.message
    });
  }
});
