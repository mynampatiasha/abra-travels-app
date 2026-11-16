with open('routes/customer_approval_router.js', 'w', encoding='utf-8') as f:
    f.write('''// routes/customer_approval_router.js - Customer approval routes with email notifications
const express = require('express');
const router = express.Router();
const emailService = require('../services/email_service');
const { ObjectId } = require('mongodb');

// Middleware to attach database
router.use((req, res, next) => {
  if (!req.db) {
    return res.status(500).json({ msg: 'Database connection not available' });
  }
  next();
});

// @route   POST /api/customer-approval/approve
// @desc    Approve a pending customer and send email notification
// @access  Private (Admin or Pending_Approvals permission)
router.post('/approve', async (req, res) => {
  try {
    const { customerId } = req.body;
    
    console.log('? Customer approval request received');
    console.log('   Customer ID:', customerId);
    console.log('   Requested by:', req.user?.uid);
    
    // Validate input
    if (!customerId) {
      return res.status(400).json({
        success: false,
        message: 'Customer ID is required'
      });
    }
    
    // Verify the requesting user is an admin OR has pending_approvals permission
    const role = req.user?.role;
    const permissions = req.user?.permissions || {};
    if (role !== 'admin' && role !== 'super_admin' && !permissions['pending_approvals']) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to approve customers'
      });
    }
    
    // Get customer details from MongoDB
    const customer = await req.db.collection('customers').findOne({
      _id: new ObjectId(customerId)
    });
    
    if (!customer) {
      return res.status(404).json({
        success: false,
        message: 'Customer not found'
      });
    }
    
    const customerName = customer.name || 'Customer';
    const customerEmail = customer.email;
    const companyName = customer.companyName || 'your organization';
    
    // Update customer in MongoDB if not already updated by frontend
    await req.db.collection('customers').updateOne(
      { _id: new ObjectId(customerId) },
      { 
        $set: { 
          status: 'active',
          isActive: true,
          approvedAt: new Date().toISOString()
        } 
      }
    );
    
    console.log('?? Calling email service...');
    
    // Send welcome email WITHOUT password setup link
    const emailResult = await emailService.sendCustomerApprovalEmail({
      email: customerEmail,
      name: customerName,
      companyName: companyName
    });
    
    if (emailResult.success) {
      return res.json({
        success: true,
        message: 'Customer approved and email sent successfully',
        emailSent: true,
        messageId: emailResult.messageId
      });
    } else {
      return res.status(500).json({
        success: false,
        message: 'Customer approved but failed to send email',
        emailSent: false,
        error: emailResult.error
      });
    }
  } catch (error) {
    console.error('? Error in approve customer route:', error);
    res.status(500).json({
      success: false,
      message: 'Server error during customer approval',
      error: error.message
    });
  }
});

module.exports = router;
''')
print('Success')
