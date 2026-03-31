// ============================================================================
// HRM FEEDBACK API ROUTES - MONGODB VERSION
// ============================================================================
// Backend API for Feedback Management System
// Author: Abra Fleet Management System
// Database: MongoDB (Native Driver)
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyJWT } = require('./jwt_router');

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Check if user is admin based on email, department, or position
 */
const isUserAdmin = async (db, userId, userEmail) => {
  try {
    console.log('🔐 Checking admin status for:', userEmail);
    
    // Check by specific admin emails
    const adminEmails = [
      'hr-admin@fleet.abra-travels.com',
      'admin@abrafleet.com',
      'abishek.veeraswamy@abra-travels.com'
    ];
    
    if (adminEmails.includes(userEmail.toLowerCase())) {
      console.log('✅ Admin by email match');
      return true;
    }
    
    // Check all user collections for department/position
    const collections = ['admin_users', 'drivers', 'customers', 'clients', 'employee_admins'];
    
    for (const collectionName of collections) {
      const user = await db.collection(collectionName).findOne({
        email: userEmail.toLowerCase()
      });
      
      if (user) {
        const dept = (user.department || '').toLowerCase();
        const pos = (user.position || '').toLowerCase();
        
        // Check if department contains 'hr' or 'human resources'
        if (dept.includes('hr') || dept.includes('human resources')) {
          console.log('✅ Admin by department:', user.department);
          return true;
        }
        
        // Check if position is managing director
        if (pos.includes('managing director') || pos.includes('md')) {
          console.log('✅ Admin by position:', user.position);
          return true;
        }
      }
    }
    
    console.log('❌ Not an admin');
    return false;
  } catch (error) {
    console.error('❌ Error checking admin status:', error);
    return false;
  }
};

/**
 * Get automated response based on feedback type
 */
const getAutomatedResponse = (feedbackType, userName) => {
  const responses = {
    suggestion: `Dear ${userName},

Thank you for taking the time to share your valuable suggestion with us! 💡

We truly appreciate your input and innovative thinking. Your suggestion has been received and will be carefully reviewed by our team.

We believe that suggestions from our users play a crucial role in our continuous improvement. Our team will analyze your suggestion and get back to you with feedback or implementation plans as soon as possible.

Thank you for helping us grow and improve!

Best regards,
The Management Team`,

    complaint: `Dear ${userName},

We have received your complaint and we sincerely apologize for any inconvenience or concern you've experienced. ⚠️

Your feedback is extremely important to us, and we take all complaints very seriously. Our team is already reviewing your concern and will investigate the matter thoroughly.

We are committed to resolving this issue promptly and will reach out to you with updates and solutions as soon as possible.

Your patience and understanding are greatly appreciated. If you need immediate assistance, please don't hesitate to reach out to management directly.

Thank you for bringing this to our attention.

Best regards,
The Management Team`,

    appreciation: `Dear ${userName},

Thank you so much for your kind words and appreciation! 🎉

It's wonderful to hear positive feedback, and we're thrilled that you took the time to share your experience. Your acknowledgment means a lot to us and motivates our entire team to continue delivering excellence.

We truly appreciate users like you who recognize and celebrate good work. Your positive energy contributes to our wonderful workplace culture.

Thank you once again for your heartwarming message!

Warm regards,
The Management Team`,

    general: `Dear ${userName},

Thank you for your feedback! 📝

We have received your message and our team will review it carefully. Your input is valuable to us and helps us understand your perspective better.

We will get back to you with a response as soon as possible. If your feedback requires any specific action, rest assured that we will address it appropriately.

Thank you for taking the time to share your thoughts with us.

Best regards,
The Management Team`
  };
  
  return responses[feedbackType] || responses.general;
};

/**
 * Truncate subject to 250 characters
 */
const truncateSubject = (subject) => {
  if (!subject) return '';
  return subject.length > 250 ? subject.substring(0, 250) : subject;
};

// ============================================================================
// AUTHENTICATION & ROLE CHECK
// ============================================================================

/**
 * @route   GET /api/hrm/feedback/check-admin
 * @desc    Check if current user is admin
 * @access  Private
 */
router.get('/check-admin', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userId = req.user.userId;
    const userEmail = req.user.email;
    
    const isAdmin = await isUserAdmin(db, userId, userEmail);
    
    return res.json({
      success: true,
      isAdmin: isAdmin
    });
  } catch (error) {
    console.error('❌ Check admin error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to check admin status',
      error: error.message
    });
  }
});

// ============================================================================
// FEEDBACK SUBMISSION
// ============================================================================

/**
 * @route   POST /api/hrm/feedback/submit
 * @desc    Submit new feedback
 * @access  Private
 */
router.post('/submit', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userId = req.user.userId;
    const userEmail = req.user.email;
    const userName = req.user.name || userEmail;
    const userRole = req.user.role; // customers, drivers, clients, employee_admins
    
    const { feedbackType, subject, message, rating } = req.body;
    
    // Validation
    if (!feedbackType || !subject || !message || !rating) {
      return res.status(400).json({
        success: false,
        message: 'All fields are required'
      });
    }
    
    if (!['suggestion', 'complaint', 'appreciation', 'general'].includes(feedbackType)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid feedback type'
      });
    }
    
    if (rating < 1 || rating > 5) {
      return res.status(400).json({
        success: false,
        message: 'Rating must be between 1 and 5'
      });
    }
    
    // Truncate subject
    const safeSubject = truncateSubject(subject);
    
    // Check for duplicate submission (within 1 minute)
    const oneMinuteAgo = new Date(Date.now() - 60000);
    const duplicate = await db.collection('feedback').findOne({
      userEmail: userEmail.toLowerCase(),
      subject: safeSubject,
      createdAt: { $gte: oneMinuteAgo }
    });
    
    if (duplicate) {
      return res.status(409).json({
        success: false,
        message: 'You have already submitted similar feedback recently'
      });
    }
    
    // Insert feedback
    const feedbackDoc = {
      userId,
      userEmail: userEmail.toLowerCase(),
      userName,
      userRole,
      feedbackType,
      subject: safeSubject,
      message,
      rating,
      parentFeedbackId: null,
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    const result = await db.collection('feedback').insertOne(feedbackDoc);
    const feedbackId = result.insertedId;
    
    // Insert automated response
    const autoResponse = getAutomatedResponse(feedbackType, userName);
    
    const autoResponseDoc = {
      userId: null,
      userEmail: 'admin@system',
      userName: 'Automated Response',
      userRole: 'system',
      feedbackType: 'general',
      subject: 'Auto-Reply',
      message: autoResponse,
      rating: 5,
      parentFeedbackId: feedbackId,
      createdAt: new Date(Date.now() + 2000), // 2 seconds later
      updatedAt: new Date(Date.now() + 2000)
    };
    
    await db.collection('feedback').insertOne(autoResponseDoc);
    
    return res.status(201).json({
      success: true,
      message: 'Feedback submitted successfully',
      data: {
        id: feedbackId.toString(),
        feedbackType,
        subject: safeSubject,
        rating
      }
    });
  } catch (error) {
    console.error('❌ Submit feedback error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to submit feedback',
      error: error.message
    });
  }
});

// ============================================================================
// FEEDBACK RETRIEVAL
// ============================================================================

// ============================================================================
// FIXED: MY FEEDBACK ROUTE - WITH DEBUGGING
// ============================================================================

/**
 * @route   GET /api/hrm/feedback/my-feedback
 * @desc    Get current user's feedback history
 * @access  Private
 */
router.get('/my-feedback', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userEmail = req.user.email;
    const userName = req.user.name;
    
    // ========================================
    // DEBUG LOGGING - REMOVE AFTER FIXING
    // ========================================
    console.log('🔍 ========== MY FEEDBACK DEBUG ==========');
    console.log('🔍 User Email from JWT:', userEmail);
    console.log('🔍 User Name from JWT:', userName);
    console.log('🔍 User Role from JWT:', req.user.role);
    console.log('🔍 User ID from JWT:', req.user.userId);
    
    const { dateFrom, dateTo, page = 1, limit = 15 } = req.query;
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    // ========================================
    // FIXED QUERY STRUCTURE
    // ========================================
    // The issue was the query structure - $ne was at the same level as $or
    // This creates a conflict. Now properly structured:
    
    const query = {
      parentFeedbackId: null,
      userEmail: { $ne: 'admin@system' },
      // Match by email OR name
      $or: [
        { userEmail: userEmail ? userEmail.toLowerCase() : '' },
        { userName: userName }
      ]
    };
    
    // Add date filters if provided
    if (dateFrom) {
      query.createdAt = { $gte: new Date(dateFrom) };
    }
    
    if (dateTo) {
      const endDate = new Date(dateTo);
      endDate.setHours(23, 59, 59, 999);
      query.createdAt = { ...query.createdAt, $lte: endDate };
    }
    
    // DEBUG: Log the query
    console.log('🔍 MongoDB Query:', JSON.stringify(query, null, 2));
    
    // Get feedbacks
    const feedbacks = await db.collection('feedback')
      .find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();
    
    // DEBUG: Log results
    console.log('🔍 Feedbacks Found:', feedbacks.length);
    if (feedbacks.length > 0) {
      console.log('🔍 First Feedback:', JSON.stringify(feedbacks[0], null, 2));
    }
    
    // Get reply counts
    const formattedFeedbacks = await Promise.all(
      feedbacks.map(async (fb) => {
        const replyCount = await db.collection('feedback').countDocuments({
          parentFeedbackId: fb._id
        });
        
        return {
          id: fb._id.toString(),
          feedbackType: fb.feedbackType,
          subject: fb.subject,
          message: fb.message,
          rating: fb.rating,
          dateSubmitted: fb.createdAt,
          hasConversation: replyCount > 0,
          source: fb.userRole,
          submitterName: fb.userName // Add this for display
        };
      })
    );
    
    // DEBUG: Log formatted response
    console.log('🔍 Formatted Feedbacks:', formattedFeedbacks.length);
    console.log('🔍 ========== END DEBUG ==========');
    
    return res.json({
      success: true,
      data: formattedFeedbacks
    });
  } catch (error) {
    console.error('❌ Get my feedback error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to fetch feedback',
      error: error.message
    });
  }
});

// ============================================================================
// ALTERNATIVE SIMPLIFIED QUERY (IF ABOVE DOESN'T WORK)
// ============================================================================

/**
 * Use this version if the $or query is still causing issues
 * This version tries email match first, then name match
 */
router.get('/my-feedback-alt', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userEmail = req.user.email;
    const userName = req.user.name;
    
    console.log('🔍 Fetching feedback for:', userEmail, userName);
    
    const { dateFrom, dateTo, page = 1, limit = 15 } = req.query;
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    // Build date filter separately
    let dateFilter = {};
    if (dateFrom) {
      dateFilter.$gte = new Date(dateFrom);
    }
    if (dateTo) {
      const endDate = new Date(dateTo);
      endDate.setHours(23, 59, 59, 999);
      dateFilter.$lte = endDate;
    }
    
    // Try email match first
    const emailQuery = {
      userEmail: userEmail ? userEmail.toLowerCase() : '',
      parentFeedbackId: null
    };
    
    if (Object.keys(dateFilter).length > 0) {
      emailQuery.createdAt = dateFilter;
    }
    
    let feedbacks = await db.collection('feedback')
      .find(emailQuery)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();
    
    // If no results by email, try by name
    if (feedbacks.length === 0 && userName) {
      const nameQuery = {
        userName: userName,
        parentFeedbackId: null,
        userEmail: { $ne: 'admin@system' }
      };
      
      if (Object.keys(dateFilter).length > 0) {
        nameQuery.createdAt = dateFilter;
      }
      
      feedbacks = await db.collection('feedback')
        .find(nameQuery)
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(parseInt(limit))
        .toArray();
    }
    
    console.log('🔍 Found feedbacks:', feedbacks.length);
    
    // Format response
    const formattedFeedbacks = await Promise.all(
      feedbacks.map(async (fb) => {
        const replyCount = await db.collection('feedback').countDocuments({
          parentFeedbackId: fb._id
        });
        
        return {
          id: fb._id.toString(),
          feedbackType: fb.feedbackType,
          subject: fb.subject,
          message: fb.message,
          rating: fb.rating,
          dateSubmitted: fb.createdAt,
          hasConversation: replyCount > 0,
          source: fb.userRole,
          submitterName: fb.userName
        };
      })
    );
    
    return res.json({
      success: true,
      data: formattedFeedbacks
    });
  } catch (error) {
    console.error('❌ Get my feedback error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to fetch feedback',
      error: error.message
    });
  }
});

// ============================================================================
// DEBUG ROUTE - CHECK USER INFO FROM JWT
// ============================================================================

/**
 * @route   GET /api/hrm/feedback/debug-user
 * @desc    Check what user info is in JWT token
 * @access  Private
 */
router.get('/debug-user', verifyJWT, async (req, res) => {
  return res.json({
    success: true,
    data: {
      userId: req.user.userId,
      email: req.user.email,
      name: req.user.name,
      role: req.user.role,
      // Show all fields in req.user
      allFields: req.user
    }
  });
});

// ============================================================================
// DEBUG ROUTE - RAW DATABASE CHECK
// ============================================================================

/**
 * @route   GET /api/hrm/feedback/debug-db-check
 * @desc    Check if feedback exists in database for current user
 * @access  Private
 */
router.get('/debug-db-check', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userEmail = req.user.email;
    
    // Check total feedback count
    const totalCount = await db.collection('feedback').countDocuments({});
    
    // Check feedback with this exact email
    const exactEmailCount = await db.collection('feedback').countDocuments({
      userEmail: userEmail
    });
    
    // Check feedback with lowercase email
    const lowerEmailCount = await db.collection('feedback').countDocuments({
      userEmail: userEmail ? userEmail.toLowerCase() : ''
    });
    
    // Check feedback without admin@system
    const nonAdminCount = await db.collection('feedback').countDocuments({
      userEmail: { $ne: 'admin@system' }
    });
    
    // Check feedback without parent
    const parentNullCount = await db.collection('feedback').countDocuments({
      parentFeedbackId: null
    });
    
    // Get sample records
    const sampleRecords = await db.collection('feedback')
      .find({})
      .limit(5)
      .toArray();
    
    return res.json({
      success: true,
      data: {
        jwtUserEmail: userEmail,
        jwtUserEmailLower: userEmail ? userEmail.toLowerCase() : '',
        totalFeedbackInDB: totalCount,
        feedbackWithExactEmail: exactEmailCount,
        feedbackWithLowerEmail: lowerEmailCount,
        feedbackNonAdmin: nonAdminCount,
        feedbackWithNullParent: parentNullCount,
        sampleRecords: sampleRecords.map(r => ({
          id: r._id.toString(),
          userEmail: r.userEmail,
          userName: r.userName,
          subject: r.subject,
          parentFeedbackId: r.parentFeedbackId
        }))
      }
    });
  } catch (error) {
    return res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * @route   GET /api/hrm/feedback/all-feedback
 * @desc    Get all feedback (Admin only)
 * @access  Private (Admin)
 */
/**
 * @route   GET /api/hrm/feedback/all-feedback
 * @desc    Get all feedback (Admin only)
 * @access  Private (Admin)
 */
router.get('/all-feedback', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userId = req.user.userId;
    const userEmail = req.user.email;
    
    // Check admin status
    const isAdmin = await isUserAdmin(db, userId, userEmail);
    
    if (!isAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Access denied. Admin privileges required.'
      });
    }
    
    const { source, nameFilter, type, dateFrom, dateTo, search, page = 1, limit = 15 } = req.query;
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    // Build query
    const query = {
      parentFeedbackId: null,
      userEmail: { $ne: 'admin@system' }
    };
    
    if (source && source !== 'all') {
      query.userRole = source;
    }
    
    if (nameFilter) {
      query.userName = nameFilter;
    }
    
    if (type && type !== 'all') {
      query.feedbackType = type;
    }
    
    if (dateFrom) {
      query.createdAt = { ...query.createdAt, $gte: new Date(dateFrom) };
    }
    
    if (dateTo) {
      const endDate = new Date(dateTo);
      endDate.setHours(23, 59, 59, 999);
      query.createdAt = { ...query.createdAt, $lte: endDate };
    }
    
    if (search) {
      query.$or = [
        { userName: { $regex: search, $options: 'i' } },
        { subject: { $regex: search, $options: 'i' } },
        { message: { $regex: search, $options: 'i' } }
      ];
    }
    
    // Get total count
    const totalRecords = await db.collection('feedback').countDocuments(query);
    const totalPages = Math.ceil(totalRecords / parseInt(limit));
    
    // Get feedbacks
    const feedbacks = await db.collection('feedback')
      .find(query)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();
    
    // Format response with ticket info
    const formattedFeedbacks = await Promise.all(
      feedbacks.map(async (fb) => {
        const replyCount = await db.collection('feedback').countDocuments({
          parentFeedbackId: fb._id
        });
        
        // ✅ FIXED: Check for ticket using BOTH old and new field names
        const expectedSubject = `[Feedback Portal] ${fb.subject}`;
        
        const ticket = await db.collection('tickets').findOne({
          $or: [
            // Try new schema (with underscores)
            {
              subject: expectedSubject,
              name: fb.userName,
              status: { $nin: ['Deleted', 'Cancelled', 'Rejected', 'Spam', 'closed'] }
            },
            // Try old schema (camelCase) - for backwards compatibility
            {
              subject: expectedSubject,
              name: fb.userName,
              status: { $nin: ['Deleted', 'Cancelled', 'Rejected', 'Spam', 'closed'] }
            }
          ]
        });
        
        let assignedEmployee = null;
        if (ticket && ticket.assigned_to) {
          const employee = await db.collection('employee_admins').findOne({
            _id: new ObjectId(ticket.assigned_to)
          });
          assignedEmployee = employee ? (employee.name_parson || employee.username) : null;
        }
        
        return {
          id: fb._id.toString(),
          submitterName: fb.userName,
          submitterEmail: fb.userEmail,
          source: fb.userRole,
          feedbackType: fb.feedbackType,
          subject: fb.subject,
          message: fb.message,
          rating: fb.rating,
          dateSubmitted: fb.createdAt,
          hasConversation: replyCount > 0,
          ticketNumber: ticket ? ticket.ticket_number : null,  // ✅ Use ticket_number (underscore)
          ticketStatus: ticket ? ticket.status : null,
          assignedEmployee
        };
      })
    );
    
    return res.json({
      success: true,
      data: formattedFeedbacks,
      pagination: {
        currentPage: parseInt(page),
        totalPages,
        totalRecords,
        limit: parseInt(limit)
      }
    });
  } catch (error) {
    console.error('❌ Get all feedback error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to fetch feedback',
      error: error.message
    });
  }
});

/**
 * @route   GET /api/hrm/feedback/statistics
 * @desc    Get feedback statistics (Admin only)
 * @access  Private (Admin)
 */
router.get('/statistics', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userId = req.user.userId;
    const userEmail = req.user.email;
    
    // Check admin status
    const isAdmin = await isUserAdmin(db, userId, userEmail);
    
    if (!isAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Access denied. Admin privileges required.'
      });
    }
    
    const { source, nameFilter, type, dateFrom, dateTo } = req.query;
    
    // Build query
    const query = {
      parentFeedbackId: null,
      userEmail: { $ne: 'admin@system' }
    };
    
    if (source && source !== 'all') {
      query.userRole = source;
    }
    
    if (nameFilter) {
      query.userName = nameFilter;
    }
    
    if (type && type !== 'all') {
      query.feedbackType = type;
    }
    
    if (dateFrom) {
      query.createdAt = { ...query.createdAt, $gte: new Date(dateFrom) };
    }
    
    if (dateTo) {
      const endDate = new Date(dateTo);
      endDate.setHours(23, 59, 59, 999);
      query.createdAt = { ...query.createdAt, $lte: endDate };
    }
    
    // Get statistics by source
    const sourceStats = await db.collection('feedback').aggregate([
      { $match: query },
      {
        $group: {
          _id: '$userRole',
          count: { $sum: 1 }
        }
      }
    ]).toArray();
    
    // Get statistics by type
    const typeStats = await db.collection('feedback').aggregate([
      { $match: query },
      {
        $group: {
          _id: {
            feedbackType: '$feedbackType',
            userRole: '$userRole'
          },
          count: { $sum: 1 }
        }
      }
    ]).toArray();
    
    // ============================================================================
    // FIXED: Format source statistics with CORRECT role mapping
    // ============================================================================
    // Database uses singular: "customer", "driver", "client", "employee_admin"
    // But frontend expects plural: "customers", "drivers", "clients", "employeeAdmins"
    
    const sourceData = {
      customers: 0,
      drivers: 0,
      clients: 0,
      employeeAdmins: 0
    };
    
    sourceStats.forEach(stat => {
      const role = stat._id;
      const count = stat.count;
      
      // Map singular database values to plural frontend keys
      if (role === 'customer' || role === 'customers') {
        sourceData.customers = count;
      } else if (role === 'driver' || role === 'drivers') {
        sourceData.drivers = count;
      } else if (role === 'client' || role === 'clients') {
        sourceData.clients = count;
      } else if (role === 'employee_admin' || role === 'employee_admins' || role === 'super_admin') {
        sourceData.employeeAdmins += count; // Use += to handle both employee_admin and super_admin
      }
      
      // Debug logging
      console.log(`📊 Role: ${role} → Count: ${count}`);
    });
    
    console.log('📊 Final source stats:', sourceData);
    
    // ============================================================================
    // FIXED: Format type statistics with CORRECT role mapping
    // ============================================================================
    
    const typeData = {
      customers: { suggestion: 0, complaint: 0, appreciation: 0, general: 0 },
      drivers: { suggestion: 0, complaint: 0, appreciation: 0, general: 0 },
      clients: { suggestion: 0, complaint: 0, appreciation: 0, general: 0 },
      employeeAdmins: { suggestion: 0, complaint: 0, appreciation: 0, general: 0 },
      overall: { suggestion: 0, complaint: 0, appreciation: 0, general: 0 }
    };
    
    typeStats.forEach(stat => {
      const role = stat._id.userRole;
      const feedbackType = stat._id.feedbackType;
      const count = stat.count;
      
      // Map to correct category
      let category = null;
      if (role === 'customer' || role === 'customers') {
        category = 'customers';
      } else if (role === 'driver' || role === 'drivers') {
        category = 'drivers';
      } else if (role === 'client' || role === 'clients') {
        category = 'clients';
      } else if (role === 'employee_admin' || role === 'employee_admins' || role === 'super_admin') {
        category = 'employeeAdmins';
      }
      
      if (category) {
        typeData[category][feedbackType] = (typeData[category][feedbackType] || 0) + count;
      }
      
      // Update overall
      typeData.overall[feedbackType] = (typeData.overall[feedbackType] || 0) + count;
      
      // Debug logging
      console.log(`📊 Role: ${role}, Type: ${feedbackType} → Count: ${count}`);
    });
    
    console.log('📊 Final type stats:', typeData);
    
    return res.json({
      success: true,
      data: {
        bySource: sourceData,
        byType: typeData
      }
    });
  } catch (error) {
    console.error('❌ Get statistics error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to fetch statistics',
      error: error.message
    });
  }
});

/**
 * @route   GET /api/hrm/feedback/user-names
 * @desc    Get user names for filter dropdown (Admin only)
 * @access  Private (Admin)
 */
router.get('/user-names', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userId = req.user.userId;
    const userEmail = req.user.email;
    
    // Check admin status
    const isAdmin = await isUserAdmin(db, userId, userEmail);
    
    if (!isAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Access denied. Admin privileges required.'
      });
    }
    
    const { source } = req.query;
    
    const query = {
      userEmail: { $ne: 'admin@system' }
    };
    
    if (source && source !== 'all') {
      query.userRole = source;
    }
    
    const names = await db.collection('feedback')
      .find(query, { projection: { userName: 1, userRole: 1 } })
      .toArray();
    
    // Group by role
    const groupedNames = {
      customers: [],
      drivers: [],
      clients: [],
      employeeAdmins: []
    };
    
    const uniqueNames = new Set();
    
    names.forEach(item => {
      if (item.userName && !uniqueNames.has(item.userName)) {
        uniqueNames.add(item.userName);
        
        if (item.userRole === 'customers') groupedNames.customers.push(item.userName);
        else if (item.userRole === 'drivers') groupedNames.drivers.push(item.userName);
        else if (item.userRole === 'clients') groupedNames.clients.push(item.userName);
        else if (item.userRole === 'employee_admins') groupedNames.employeeAdmins.push(item.userName);
      }
    });
    
    // Sort arrays
    groupedNames.customers.sort();
    groupedNames.drivers.sort();
    groupedNames.clients.sort();
    groupedNames.employeeAdmins.sort();
    
    return res.json({
      success: true,
      data: groupedNames
    });
  } catch (error) {
    console.error('❌ Get user names error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to fetch user names',
      error: error.message
    });
  }
});

/**
 * @route   GET /api/hrm/feedback/my-statistics
 * @desc    Get personal feedback statistics
 * @access  Private
 */
router.get('/my-statistics', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userEmail = req.user.email;
    const userName = req.user.name;
    
    const { dateFrom, dateTo } = req.query;
    
    // Build query
    const query = {
      $or: [
        { userEmail: userEmail.toLowerCase() },
        { userName: userName }
      ],
      parentFeedbackId: null,
      userEmail: { $ne: 'admin@system' }
    };
    
    if (dateFrom) {
      query.createdAt = { ...query.createdAt, $gte: new Date(dateFrom) };
    }
    
    if (dateTo) {
      const endDate = new Date(dateTo);
      endDate.setHours(23, 59, 59, 999);
      query.createdAt = { ...query.createdAt, $lte: endDate };
    }
    
    // Get total count
    const totalCount = await db.collection('feedback').countDocuments(query);
    
    // Get feedbacks with replies
    const feedbacks = await db.collection('feedback')
      .find(query, { projection: { _id: 1 } })
      .toArray();
    
    let respondedCount = 0;
    
    for (const fb of feedbacks) {
      const hasReplies = await db.collection('feedback').findOne({
        parentFeedbackId: fb._id
      });
      
      if (hasReplies) {
        respondedCount++;
      }
    }
    
    const pendingCount = totalCount - respondedCount;
    
    return res.json({
      success: true,
      data: {
        totalCount,
        respondedCount,
        pendingCount
      }
    });
  } catch (error) {
    console.error('❌ Get my statistics error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to fetch statistics',
      error: error.message
    });
  }
});

// ============================================================================
// CONVERSATION/THREAD METHODS
// ============================================================================

/**
 * @route   GET /api/hrm/feedback/conversation/:feedbackId
 * @desc    Get conversation thread
 * @access  Private
 */
router.get('/conversation/:feedbackId', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const { feedbackId } = req.params;
    const userId = req.user.userId;
    const userEmail = req.user.email;
    
    // Get the clicked feedback
    const feedback = await db.collection('feedback').findOne({
      _id: new ObjectId(feedbackId)
    });
    
    if (!feedback) {
      return res.status(404).json({
        success: false,
        message: 'Feedback not found'
      });
    }
    
    // Check access permission
    const isAdmin = await isUserAdmin(db, userId, userEmail);
    
    if (!isAdmin && feedback.userEmail !== userEmail.toLowerCase() && feedback.userName !== req.user.name) {
      return res.status(403).json({
        success: false,
        message: 'Access denied. You can only view your own feedback.'
      });
    }
    
    // Determine thread ID
    const threadId = feedback.parentFeedbackId || feedback._id;
    
    // Get all messages in thread
    const messages = await db.collection('feedback')
      .find({
        $or: [
          { _id: threadId },
          { parentFeedbackId: threadId }
        ]
      })
      .sort({ createdAt: 1 })
      .toArray();
    
    let originalSubject = '';
    
    // Format messages
    const formattedMessages = messages.map(msg => {
      // Capture original subject
      if (!msg.parentFeedbackId && msg.subject && !originalSubject) {
        originalSubject = msg.subject;
      }
      
      const isAdminMessage = msg.userEmail === 'admin@system' || msg.userName === 'Automated Response';
      
      return {
        id: msg._id.toString(),
        sender: msg.userName,
        senderEmail: msg.userEmail,
        message: msg.message,
        subject: !msg.parentFeedbackId ? msg.subject : '',
        rating: (!msg.parentFeedbackId && !isAdminMessage) ? msg.rating : 0,
        date: msg.createdAt,
        isAdmin: isAdminMessage,
        type: isAdminMessage ? 'admin' : 'user'
      };
    });
    
    return res.json({
      success: true,
      data: {
        messages: formattedMessages,
        subject: originalSubject,
        threadId: threadId.toString(),
        totalMessages: formattedMessages.length
      }
    });
  } catch (error) {
    console.error('❌ Get conversation error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to fetch conversation',
      error: error.message
    });
  }
});

/**
 * @route   POST /api/hrm/feedback/reply
 * @desc    Send reply to feedback thread
 * @access  Private
 */
router.post('/reply', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userId = req.user.userId;
    const userEmail = req.user.email;
    const userName = req.user.name || userEmail;
    const { threadId, message } = req.body;
    
    // Validation
    if (!threadId || !message || message.trim() === '') {
      return res.status(400).json({
        success: false,
        message: 'Thread ID and message are required'
      });
    }
    
    // Check if thread exists
    const thread = await db.collection('feedback').findOne({
      _id: new ObjectId(threadId)
    });
    
    if (!thread) {
      return res.status(404).json({
        success: false,
        message: 'Thread not found'
      });
    }
    
    // Determine sender info
    const isAdmin = await isUserAdmin(db, userId, userEmail);
    const senderEmail = isAdmin ? 'admin@system' : userEmail.toLowerCase();
    const senderName = isAdmin ? 'System Admin' : userName;
    
    // Insert reply
    const replyDoc = {
      userId,
      userEmail: senderEmail,
      userName: senderName,
      userRole: 'general',
      feedbackType: 'general',
      subject: 'Reply',
      message: message.trim(),
      rating: 5,
      parentFeedbackId: new ObjectId(threadId),
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    const result = await db.collection('feedback').insertOne(replyDoc);
    
    return res.status(201).json({
      success: true,
      message: 'Reply sent successfully',
      data: {
        id: result.insertedId.toString(),
        sender: senderName,
        message: message.trim(),
        threadId
      }
    });
  } catch (error) {
    console.error('❌ Send reply error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to send reply',
      error: error.message
    });
  }
});

// ============================================================================
// TICKET MANAGEMENT (Admin only)
// ============================================================================

/**
 * @route   GET /api/hrm/feedback/employees-list
 * @desc    Get employees for ticket assignment
 * @access  Private (Admin)
 */
router.get('/employees-list', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userId = req.user.userId;
    const userEmail = req.user.email;
    
    // Check admin status
    const isAdmin = await isUserAdmin(db, userId, userEmail);
    
    if (!isAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Access denied. Admin privileges required.'
      });
    }
    
    // Get active employees
    const employees = await db.collection('employee_admins')
      .find(
        { status: 'active' },
        { projection: { _id: 1, name: 1, email: 1 } }
      )
      .sort({ name: 1 })
      .toArray();
    
    const formattedEmployees = employees.map(emp => ({
      id: emp._id.toString(),
      name: emp.name,
      email: emp.email
    }));
    
    return res.json({
      success: true,
      data: formattedEmployees
    });
  } catch (error) {
    console.error('❌ Get employees error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to fetch employees',
      error: error.message
    });
  }
});

/**
 * @route   GET /api/hrm/feedback/check-ticket
 * @desc    Check if ticket already exists for feedback
 * @access  Private (Admin)
 */
router.get('/check-ticket', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userId = req.user.userId;
    const userEmail = req.user.email;
    
    // Check admin status
    const isAdmin = await isUserAdmin(db, userId, userEmail);
    
    if (!isAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Access denied. Admin privileges required.'
      });
    }
    
    const { feedbackId, submitterName, subject } = req.query;
    
    const expectedSubject = `[Feedback Portal] ${subject}`;
    
    // Check for existing ticket
    const ticket = await db.collection('tickets').findOne({
      name: submitterName,
      subject: expectedSubject,
      status: { $nin: ['Deleted', 'Cancelled', 'Rejected', 'Spam'] }
    });
    
    if (ticket) {
      let assignedName = 'Unknown Employee';
      
      if (ticket.assignedTo) {
        const employee = await db.collection('employee_admins').findOne({
          _id: new ObjectId(ticket.assignedTo)
        });
        
        if (employee) {
          assignedName = employee.name;
        }
      }
      
      return res.json({
        success: true,
        data: {
          exists: true,
          ticketNumber: ticket.ticketNumber,
          assignedName,
          status: ticket.status
        }
      });
    }
    
    return res.json({
      success: true,
      data: {
        exists: false
      }
    });
  } catch (error) {
    console.error('❌ Check ticket error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to check ticket',
      error: error.message
    });
  }
});

/**
 * @route   POST /api/hrm/feedback/create-ticket
 * @desc    Create ticket from feedback
 * @access  Private (Admin)
 */
router.post('/create-ticket', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userId = req.user.userId;
    const userEmail = req.user.email;
    
    console.log('🎫 Creating ticket from feedback:', req.body.feedbackId);
    
    // Check admin status
    const isAdmin = await isUserAdmin(db, userId, userEmail);
    
    if (!isAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Access denied. Admin privileges required.'
      });
    }
    
    const { feedbackId, assignedTo } = req.body;
    
    // Validation
    if (!feedbackId || !assignedTo) {
      return res.status(400).json({
        success: false,
        message: 'Feedback ID and assigned employee are required'
      });
    }
    
    // Get feedback details
    const feedback = await db.collection('feedback').findOne({
      _id: new ObjectId(feedbackId)
    });
    
    if (!feedback) {
      return res.status(404).json({
        success: false,
        message: 'Feedback not found'
      });
    }
    
    // Get assigned employee details
    const assignedEmployee = await db.collection('employee_admins').findOne({
      _id: new ObjectId(assignedTo)
    });
    
    if (!assignedEmployee) {
      return res.status(404).json({
        success: false,
        message: 'Assigned employee not found'
      });
    }
    
    // Get current employee (creator) details
    const currentEmployee = await db.collection('employee_admins').findOne({
      email: userEmail.toLowerCase(),
      status: 'active'
    });
    
    if (!currentEmployee) {
      return res.status(404).json({
        success: false,
        message: 'Your employee account not found'
      });
    }
    
    // ✅ GENERATE SEQUENTIAL TICKET NUMBER (exactly like TMS)
    const lastTicket = await db.collection('tickets')
      .findOne({}, { sort: { created_at: -1 } });

    let nextId = 1;
    if (lastTicket && lastTicket.ticket_number) {
      // Extract the number from TICKET20260001 -> 0001
      const lastNumber = parseInt(lastTicket.ticket_number.replace(/\D/g, '').slice(-4));
      if (!isNaN(lastNumber)) {
        nextId = lastNumber + 1;
      }
    }

    const ticket_number = `TICKET${new Date().getFullYear()}${String(nextId).padStart(4, '0')}`;
    
    console.log('📋 Generated ticket number:', ticket_number);
    
    // Build ticket subject and message
    const ticketSubject = `[Feedback Portal] ${feedback.subject}`;
    
    const messageBody = `🌟 FEEDBACK ESCALATION TICKET
==================================================
📌 ORIGINAL SUBJECT
${feedback.subject}

📝 MESSAGE CONTENT
${feedback.message}

⭐ RATING: ${feedback.rating}/5
📧 FROM: ${feedback.userName} (${feedback.userEmail})
🏷️ TYPE: ${feedback.feedbackType}
📅 SUBMITTED: ${feedback.createdAt.toISOString()}
`;
    
    // Determine priority based on feedback type
    let priority = 'medium';
    if (feedback.feedbackType === 'complaint') {
      priority = 'high';
    } else if (feedback.feedbackType === 'suggestion') {
      priority = 'low';
    }
    
    // Set timeline (default 24 hours for feedback tickets)
    const timelineMinutes = 1440; // 24 hours
    const deadline = new Date();
    deadline.setMinutes(deadline.getMinutes() + timelineMinutes);
    
    // ✅ CREATE TICKET WITH EXACT TMS SCHEMA
    const ticketDoc = {
      ticket_number,
      name: feedback.userName,
      creator_email: currentEmployee.email,
      assigned_email: assignedEmployee.email.toLowerCase(),
      subject: ticketSubject,
      message: messageBody,
      status: 'Open',
      priority,
      timeline: timelineMinutes,
      deadline,
      attachment: null,
      assigned_to: new ObjectId(assignedTo),
      created_by: currentEmployee._id,
      created_at: new Date(),
      updated_at: new Date()
    };
    
    console.log('💾 Inserting ticket:', {
      ticket_number,
      assigned_to: assignedEmployee.name_parson || assignedEmployee.username,
      assigned_email: assignedEmployee.email
    });
    
    // Insert ticket
    const result = await db.collection('tickets').insertOne(ticketDoc);
    
    console.log('✅ Ticket created successfully:', result.insertedId);
    
    return res.status(201).json({
      success: true,
      message: `Ticket ${ticket_number} created successfully!`,
      data: {
        ticketId: result.insertedId.toString(),
        ticketNumber: ticket_number
      }
    });
  } catch (error) {
    console.error('❌ Create ticket error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to create ticket',
      error: error.message
    });
  }
});

// ============================================================================
// EXPORT METHODS
// ============================================================================

/**
 * @route   GET /api/hrm/feedback/export/all
 * @desc    Export all feedback to CSV (Admin only)
 * @access  Private (Admin)
 */
router.get('/export/all', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userId = req.user.userId;
    const userEmail = req.user.email;
    
    // Check admin status
    const isAdmin = await isUserAdmin(db, userId, userEmail);
    
    if (!isAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Access denied. Admin privileges required.'
      });
    }
    
    const { source, nameFilter, type, dateFrom, dateTo } = req.query;
    
    // Build query
    const query = {
      parentFeedbackId: null,
      userEmail: { $ne: 'admin@system' }
    };
    
    if (source && source !== 'all') {
      query.userRole = source;
    }
    
    if (nameFilter) {
      query.userName = nameFilter;
    }
    
    if (type && type !== 'all') {
      query.feedbackType = type;
    }
    
    if (dateFrom) {
      query.createdAt = { ...query.createdAt, $gte: new Date(dateFrom) };
    }
    
    if (dateTo) {
      const endDate = new Date(dateTo);
      endDate.setHours(23, 59, 59, 999);
      query.createdAt = { ...query.createdAt, $lte: endDate };
    }
    
    // Get feedbacks
    const feedbacks = await db.collection('feedback')
      .find(query)
      .sort({ createdAt: -1 })
      .toArray();
    
    // Generate CSV
    let csv = 'ID,Name,Email,Source,Type,Subject,Message,Rating,Date\n';
    
    feedbacks.forEach(fb => {
      const row = [
        fb._id.toString(),
        `"${fb.userName.replace(/"/g, '""')}"`,
        fb.userEmail,
        fb.userRole,
        fb.feedbackType,
        `"${fb.subject.replace(/"/g, '""')}"`,
        `"${fb.message.replace(/"/g, '""')}"`,
        fb.rating,
        fb.createdAt.toISOString()
      ];
      csv += row.join(',') + '\n';
    });
    
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename="all_feedback.csv"');
    return res.send(csv);
  } catch (error) {
    console.error('❌ Export all feedback error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to export feedback',
      error: error.message
    });
  }
});

/**
 * @route   GET /api/hrm/feedback/export/my-feedback
 * @desc    Export personal feedback to CSV
 * @access  Private
 */
router.get('/export/my-feedback', verifyJWT, async (req, res) => {
  try {
    const db = req.db;
    const userEmail = req.user.email;
    const userName = req.user.name;
    
    const { dateFrom, dateTo } = req.query;
    
    // Build query
    const query = {
      $or: [
        { userEmail: userEmail.toLowerCase() },
        { userName: userName }
      ],
      parentFeedbackId: null,
      userEmail: { $ne: 'admin@system' }
    };
    
    if (dateFrom) {
      query.createdAt = { ...query.createdAt, $gte: new Date(dateFrom) };
    }
    
    if (dateTo) {
      const endDate = new Date(dateTo);
      endDate.setHours(23, 59, 59, 999);
      query.createdAt = { ...query.createdAt, $lte: endDate };
    }
    
    // Get feedbacks
    const feedbacks = await db.collection('feedback')
      .find(query)
      .sort({ createdAt: -1 })
      .toArray();
    
    // Generate CSV
    let csv = 'ID,Type,Subject,Message,Rating,Date\n';
    
    feedbacks.forEach(fb => {
      const row = [
        fb._id.toString(),
        fb.feedbackType,
        `"${fb.subject.replace(/"/g, '""')}"`,
        `"${fb.message.replace(/"/g, '""')}"`,
        fb.rating,
        fb.createdAt.toISOString()
      ];
      csv += row.join(',') + '\n';
    });
    
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename="my_feedback.csv"');
    return res.send(csv);
  } catch (error) {
    console.error('❌ Export my feedback error:', error);
    return res.status(500).json({
      success: false,
      message: 'Failed to export feedback',
      error: error.message
    });
  }
});

module.exports = router;