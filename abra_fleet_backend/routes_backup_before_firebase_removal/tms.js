// routes/tms.js - Ticket Management System API
// ============================================================================
// COMPLETE TMS BACKEND WITH ALL FEATURES
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// ============================================================================
// FILE UPLOAD CONFIGURATION
// ============================================================================

// Create uploads directory if it doesn't exist
const uploadsDir = path.join(__dirname, '../uploads/tickets');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

// Configure multer for file uploads
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadsDir);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, uniqueSuffix + path.extname(file.originalname));
  }
});

const fileFilter = (req, file, cb) => {
  const allowedTypes = [
    'image/jpeg',
    'image/png',
    'image/gif',
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'text/plain'
  ];
  
  if (allowedTypes.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error('Invalid file type. Only JPG, PNG, GIF, PDF, DOC, DOCX, TXT allowed.'), false);
  }
};

const upload = multer({
  storage: storage,
  fileFilter: fileFilter,
  limits: {
    fileSize: 5 * 1024 * 1024 // 5MB limit
  }
});

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Get MongoDB user _id from User ID - checks both users and admin_users collections
 */
async function getUserMongoId(db, firebaseUid) {
  try {
    // First try to use as ObjectId directly (for backward compatibility)
    if (ObjectId.isValid(firebaseUid)) {
      // Check users collection first
      let user = await db.collection('users').findOne({ _id: new ObjectId(firebaseUid) });
      if (user) return user._id;
      
      // Check admin_users collection
      user = await db.collection('admin_users').findOne({ _id: new ObjectId(firebaseUid) });
      if (user) return user._id;
    }
    
    // Try to find by User ID in users collection
    let user = await db.collection('users').findOne({ firebaseUid });
    if (user) return user._id;
    
    // Try to find by User ID in admin_users collection
    user = await db.collection('admin_users').findOne({ firebaseUid });
    if (user) return user._id;
    
    throw new Error('User not found in database');
  } catch (error) {
    console.error('❌ Error getting user MongoDB ID:', error.message);
    throw error;
  }
}

/**
 * Check if user has admin role
 */
function isAdminRole(role) {
  const adminRoles = [
    'super_admin', 'superadmin', 'super', 'admin',
    'org_admin', 'organization_admin',
    'fleet_manager', 'operations_manager', 'operations',
    'hr_manager', 'finance_admin', 'finance'
  ];
  
  const normalizedRole = role?.toLowerCase()?.trim()?.replace(' ', '_');
  return adminRoles.includes(normalizedRole);
}

/**
 * Generate unique ticket number with atomic counter
 */
async function generateTicketNumber(db) {
  const year = new Date().getFullYear();
  const today = new Date();
  const month = String(today.getMonth() + 1).padStart(2, '0');
  const day = String(today.getDate()).padStart(2, '0');
  
  const dateKey = `${year}-${month}-${day}`;
  const datePrefix = `TKT-${year}-${month}${day}`;
  
  // Use MongoDB's findOneAndUpdate with upsert for atomic counter
  const counterDoc = await db.collection('ticket_counters').findOneAndUpdate(
    { _id: dateKey },
    { $inc: { sequence: 1 } },
    { 
      upsert: true, 
      returnDocument: 'after'
    }
  );
  
  const sequence = counterDoc.sequence;
  const ticketNumber = `${datePrefix}-${String(sequence).padStart(3, '0')}`;
  
  // Additional safety check (though should not be needed with atomic counter)
  const existingTicket = await db.collection('tickets').findOne({ ticketNumber });
  if (existingTicket) {
    // If somehow still duplicate, add timestamp suffix
    const timestamp = Date.now().toString().slice(-4);
    return `${datePrefix}-${String(sequence).padStart(3, '0')}-${timestamp}`;
  }
  
  return ticketNumber;
}

/**
 * Send notification to Firebase (for real-time updates)
 */
async function sendTicketNotification(type, ticketData, recipientId) {
  try {
    const admin = require('../config/firebase');
    const db = admin.database();
    
    const notificationRef = db.ref(`notifications/${recipientId}`).push();
    await notificationRef.set({
      type: type, // 'new_ticket', 'ticket_assigned', 'ticket_updated', 'ticket_closed'
      ticketId: ticketData._id?.toString(),
      ticketNumber: ticketData.ticketNumber,
      subject: ticketData.subject,
      priority: ticketData.priority,
      message: getNotificationMessage(type, ticketData),
      timestamp: Date.now(),
      read: false
    });
    
    console.log(`✅ Notification sent to ${recipientId}`);
  } catch (error) {
    console.error('❌ Failed to send notification:', error.message);
  }
}

/**
 * Get notification message based on type
 */
function getNotificationMessage(type, ticketData) {
  const messages = {
    'new_ticket': `New ticket "${ticketData.subject}" has been created`,
    'ticket_assigned': `Ticket "${ticketData.subject}" has been assigned to you`,
    'ticket_updated': `Ticket "${ticketData.subject}" status updated to ${ticketData.status}`,
    'ticket_closed': `Ticket "${ticketData.subject}" has been closed`
  };
  return messages[type] || 'Ticket notification';
}

// ============================================================================
// ROUTES
// ============================================================================

/**
 * @route   POST /api/tickets
 * @desc    Create new ticket
 * @access  Private (authenticated users)
 */
router.post('/', upload.single('attachment'), async (req, res) => {
  console.log('\n🎫 ========== CREATE NEW TICKET ==========');
  
  try {
    const { subject, message, priority, assignedTo, status } = req.body;
    const createdBy = req.user;
    
    console.log('📝 Ticket Details:');
    console.log('   Subject:', subject);
    console.log('   Priority:', priority);
    console.log('   Assigned To:', assignedTo);
    console.log('   Created By:', createdBy.email);
    
    // Validation
    if (!subject || !message || !priority) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'Please provide subject, message, and priority'
      });
    }
    
    // Generate unique ticket number
    const ticketNumber = await generateTicketNumber(req.db);
    console.log('🎫 Generated Ticket Number:', ticketNumber);
    
    // Get MongoDB user ID for assignedTo if provided
    let assignedToObjectId = null;
    if (assignedTo) {
      try {
        // First try to use as ObjectId directly
        assignedToObjectId = new ObjectId(assignedTo);
      } catch (error) {
        // If not valid ObjectId, try to find user by User ID in both collections
        let assignedUser = await req.db.collection('users').findOne({ firebaseUid: assignedTo });
        if (!assignedUser) {
          assignedUser = await req.db.collection('admin_users').findOne({ firebaseUid: assignedTo });
        }
        
        if (assignedUser) {
          assignedToObjectId = assignedUser._id;
        } else {
          console.log('⚠️ Assigned user not found in either collection:', assignedTo);
        }
      }
    }

    // Get MongoDB user ID for createdBy using dual collection lookup
    let createdByObjectId = null;
    try {
      // First try to use as ObjectId directly
      createdByObjectId = new ObjectId(createdBy.uid);
    } catch (error) {
      // If not valid ObjectId, try to find user by User ID in both collections
      let createdByUser = await req.db.collection('users').findOne({ firebaseUid: createdBy.uid });
      if (!createdByUser) {
        createdByUser = await req.db.collection('admin_users').findOne({ firebaseUid: createdBy.uid });
      }
      
      if (createdByUser) {
        createdByObjectId = createdByUser._id;
      } else {
        console.log('⚠️ Created by user not found in either collection:', createdBy.uid);
        // For backward compatibility, store User ID as string
        createdByObjectId = createdBy.uid;
      }
    }

    // Prepare ticket document
    const newTicket = {
      ticketNumber,
      subject,
      message,
      priority: priority.toLowerCase(), // low, medium, high
      status: status || 'open', // open, in_progress, closed
      assignedTo: assignedToObjectId,
      createdBy: {
        id: createdByObjectId,
        firebaseUid: createdBy.uid, // Store User ID for reference
        name: createdBy.name,
        email: createdBy.email
      },
      attachment: req.file ? {
        filename: req.file.filename,
        originalName: req.file.originalname,
        size: req.file.size,
        mimetype: req.file.mimetype,
        path: `/uploads/tickets/${req.file.filename}`
      } : null,
      createdAt: new Date(),
      updatedAt: new Date(),
      history: [{
        action: 'created',
        by: createdBy.email,
        timestamp: new Date(),
        note: 'Ticket created'
      }]
    };
    
    // Insert ticket
    const result = await req.db.collection('tickets').insertOne(newTicket);
    newTicket._id = result.insertedId;
    
    console.log('✅ Ticket Created Successfully:', ticketNumber);
    
    // Send notification to assigned employee (if any)
    if (assignedToObjectId) {
      // Convert ObjectId to string for Firebase notification
      const assignedToId = assignedToObjectId.toString();
      await sendTicketNotification('ticket_assigned', newTicket, assignedToId);
    }
    
    // Send notification to admins about new ticket
    const admins = await req.db.collection('users')
      .find({ role: 'super_admin' })
      .toArray();
    
    for (const admin of admins) {
      await sendTicketNotification('new_ticket', newTicket, admin._id.toString());
    }
    
    res.status(201).json({
      success: true,
      message: 'Ticket created successfully',
      data: newTicket
    });
    
  } catch (error) {
    console.error('❌ CREATE TICKET ERROR:', error);
    
    // Delete uploaded file if ticket creation failed
    if (req.file) {
      fs.unlinkSync(req.file.path);
    }
    
    res.status(500).json({
      success: false,
      error: 'Failed to create ticket',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/tickets/my
 * @desc    Get tickets assigned to current user OR created by current user
 * @access  Private
 */
router.get('/my', async (req, res) => {
  console.log('\n📋 ========== GET MY TICKETS ==========');
  console.log('   User ID:', req.user.userId);
  console.log('   User Role:', req.user.role);
  console.log('   User Email:', req.user.email);
  
  try {
    // Get user's MongoDB _id
    let userId;
    let userFirebaseUid = req.user.userId;
    
    try {
      userId = await getUserMongoId(req.db, req.user.userId);
      console.log('   MongoDB User ID:', userId);
    } catch (error) {
      console.log('⚠️ User not found in MongoDB, using Firebase UID');
      userId = null;
    }
    
    const { status, priority, dateFrom, dateTo, page = 1, limit = 50 } = req.query;
    
    // Build query - show tickets where user is EITHER assignedTo OR createdBy
    const query = {
      $or: []
    };
    
    // Add assignedTo condition if we have MongoDB user ID
    if (userId) {
      query.$or.push({ assignedTo: userId });
    }
    
    // Add createdBy conditions (check both MongoDB ID and Firebase UID)
    if (userId) {
      query.$or.push({ 'createdBy.id': userId });
    }
    query.$or.push({ 'createdBy.firebaseUid': userFirebaseUid });
    
    // If no conditions were added, return empty result
    if (query.$or.length === 0) {
      console.log('❌ No valid user identifiers found');
      return res.json({
        success: true,
        data: [],
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total: 0,
          pages: 0
        }
      });
    }
    
    // Apply filters
    if (status && status !== 'all') {
      if (status === 'active') {
        query.status = { $in: ['open', 'in_progress'] };
      } else {
        query.status = status;
      }
    } else {
      // Default: exclude closed tickets
      query.status = { $ne: 'closed' };
    }
    
    if (priority && priority !== 'all') {
      query.priority = priority;
    }
    
    if (dateFrom || dateTo) {
      query.createdAt = {};
      if (dateFrom) query.createdAt.$gte = new Date(dateFrom);
      if (dateTo) query.createdAt.$lte = new Date(dateTo + 'T23:59:59.999Z');
    }
    
    console.log('🔍 Query:', JSON.stringify(query, null, 2));
    
    // Execute query with pagination
    const tickets = await req.db.collection('tickets')
      .find(query)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(parseInt(limit))
      .toArray();
    
    // Get total count
    const totalCount = await req.db.collection('tickets').countDocuments(query);
    
    console.log(`✅ Found ${tickets.length} tickets for user`);
    tickets.forEach((ticket) => {
      console.log(`   - ${ticket.ticketNumber}: ${ticket.subject} (${ticket.status})`);
      console.log(`     Assigned To: ${ticket.assignedTo}`);
      console.log(`     Created By: ${ticket.createdBy?.email || 'N/A'}`);
    });
    
    res.json({
      success: true,
      data: tickets,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalCount,
        pages: Math.ceil(totalCount / limit)
      }
    });
    
  } catch (error) {
    console.error('❌ GET MY TICKETS ERROR:', error);
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch tickets',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/tickets/all
 * @desc    Get all tickets (admin only)
 * @access  Private (admin)
 */
router.get('/all', async (req, res) => {
  console.log('\n📋 ========== GET ALL TICKETS ==========');
  console.log('   User Role:', req.user.role);
  console.log('   User Email:', req.user.email);
  
  try {
    // Check admin permission - accept multiple admin role names
    const adminRoles = [
      'super_admin', 'superadmin', 'super', 'admin', 'employee',
      'org_admin', 'organization_admin',
      'fleet_manager', 'operations_manager', 'operations',
      'hr_manager', 'finance_admin', 'finance'
    ];
    
    const userRole = req.user.role?.toLowerCase()?.trim()?.replace(' ', '_');
    const isAdmin = adminRoles.includes(userRole);
    
    console.log('   Normalized Role:', userRole);
    console.log('   Is Admin:', isAdmin);
    
    if (!isAdmin) {
      console.log('   ❌ Access denied - not an admin role');
      return res.status(403).json({
        success: false,
        error: 'Access denied',
        message: 'Only administrators can view all tickets',
        userRole: req.user.role
      });
    }
    
    const { status, priority, assignedTo, dateFrom, dateTo, page = 1, limit = 50 } = req.query;
    
    // Build query
    const query = {};
    
    // Apply filters
    if (status && status !== 'all') {
      if (status === 'active') {
        query.status = { $in: ['open', 'in_progress'] };
      } else {
        query.status = status;
      }
    } else {
      // Default: exclude closed tickets
      query.status = { $ne: 'closed' };
    }
    
    if (priority && priority !== 'all') {
      query.priority = priority;
    }
    
    if (assignedTo && assignedTo !== 'all') {
      if (assignedTo === 'unassigned') {
        query.assignedTo = null;
      } else {
        query.assignedTo = new ObjectId(assignedTo);
      }
    }
    
    if (dateFrom || dateTo) {
      query.createdAt = {};
      if (dateFrom) query.createdAt.$gte = new Date(dateFrom);
      if (dateTo) query.createdAt.$lte = new Date(dateTo + 'T23:59:59.999Z');
    }
    
    console.log('🔍 Query:', JSON.stringify(query, null, 2));
    
    // Execute query with pagination
    const tickets = await req.db.collection('tickets')
      .aggregate([
        { $match: query },
        {
          $lookup: {
            from: 'users',
            localField: 'assignedTo',
            foreignField: '_id',
            as: 'assignedToUser'
          }
        },
        {
          $addFields: {
            assignedToName: { $arrayElemAt: ['$assignedToUser.name', 0] }
          }
        },
        { $sort: { createdAt: -1 } },
        { $skip: (page - 1) * limit },
        { $limit: parseInt(limit) }
      ])
      .toArray();
    
    // Get total count
    const totalCount = await req.db.collection('tickets').countDocuments(query);
    
    console.log(`✅ Found ${tickets.length} tickets`);
    
    res.json({
      success: true,
      data: tickets,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalCount,
        pages: Math.ceil(totalCount / limit)
      }
    });
    
  } catch (error) {
    console.error('❌ GET ALL TICKETS ERROR:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch tickets',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/tickets/closed
 * @desc    Get closed tickets
 * @access  Private
 */
router.get('/closed', async (req, res) => {
  console.log('\n📋 ========== GET CLOSED TICKETS ==========');
  
  try {
    const { assignedTo, dateFrom, dateTo, page = 1, limit = 50 } = req.query;
    
    // Build query
    const query = { status: 'closed' };
    
    // Check if user is admin
    const adminRoles = [
      'super_admin', 'superadmin', 'super', 'admin', 'employee', 'employee',
      'org_admin', 'organization_admin',
      'fleet_manager', 'operations_manager', 'operations',
      'hr_manager', 'finance_admin', 'finance'
    ];
    
    const userRole = req.user.role?.toLowerCase()?.trim()?.replace(' ', '_');
    const isAdmin = adminRoles.includes(userRole);
    
    // For non-admins, show only their tickets
    if (!isAdmin) {
      try {
        const userId = await getUserMongoId(req.db, req.user.userId);
        query.assignedTo = userId;
      } catch (error) {
        // If user not found in MongoDB, try User ID in createdBy field
        query['createdBy.firebaseUid'] = req.user.userId;
      }
    } else if (assignedTo && assignedTo !== 'all') {
      try {
        // First try as ObjectId
        query.assignedTo = new ObjectId(assignedTo);
      } catch (error) {
        // If not valid ObjectId, try to find user by User ID in both collections
        let assignedUser = await req.db.collection('users').findOne({ firebaseUid: assignedTo });
        if (!assignedUser) {
          assignedUser = await req.db.collection('admin_users').findOne({ firebaseUid: assignedTo });
        }
        if (assignedUser) {
          query.assignedTo = assignedUser._id;
        }
      }
    }
    
    if (dateFrom || dateTo) {
      query.updatedAt = {}; // Use updatedAt for closed date
      if (dateFrom) query.updatedAt.$gte = new Date(dateFrom);
      if (dateTo) query.updatedAt.$lte = new Date(dateTo + 'T23:59:59.999Z');
    }
    
    console.log('🔍 Query:', JSON.stringify(query, null, 2));
    
    // Execute query with pagination
    const tickets = await req.db.collection('tickets')
      .find(query)
      .sort({ updatedAt: -1 })
      .skip((page - 1) * limit)
      .limit(parseInt(limit))
      .toArray();
    
    // Get total count
    const totalCount = await req.db.collection('tickets').countDocuments(query);
    
    console.log(`✅ Found ${tickets.length} closed tickets`);
    
    res.json({
      success: true,
      data: tickets,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalCount,
        pages: Math.ceil(totalCount / limit)
      }
    });
    
  } catch (error) {
    console.error('❌ GET CLOSED TICKETS ERROR:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch closed tickets',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/tickets/stats
 * @desc    Get ticket statistics
 * @access  Private
 */
router.get('/stats', async (req, res) => {
  console.log('\n📊 ========== GET TICKET STATS ==========');
  
  try {
    const userId = req.user.userId;
    
    // Check if user is admin
    const adminRoles = [
      'super_admin', 'superadmin', 'super', 'admin', 'employee', 'employee',
      'org_admin', 'organization_admin',
      'fleet_manager', 'operations_manager', 'operations',
      'hr_manager', 'finance_admin', 'finance'
    ];
    
    const userRole = req.user.role?.toLowerCase()?.trim()?.replace(' ', '_');
    const isAdmin = adminRoles.includes(userRole);
    
    // Build match query with dual collection support
    let matchQuery = {};
    if (!isAdmin) {
      try {
        const userId = await getUserMongoId(req.db, req.user.userId);
        matchQuery = { assignedTo: userId };
      } catch (error) {
        // If user not found in MongoDB, try User ID in createdBy field
        matchQuery = { 'createdBy.firebaseUid': req.user.userId };
      }
    }
    
    // Get statistics
    const stats = await req.db.collection('tickets').aggregate([
      { $match: matchQuery },
      {
        $group: {
          _id: null,
          total: { $sum: 1 },
          open: { $sum: { $cond: [{ $eq: ['$status', 'open'] }, 1, 0] } },
          inProgress: { $sum: { $cond: [{ $eq: ['$status', 'in_progress'] }, 1, 0] } },
          closed: { $sum: { $cond: [{ $eq: ['$status', 'closed'] }, 1, 0] } },
          highPriority: { $sum: { $cond: [{ $eq: ['$priority', 'high'] }, 1, 0] } },
          unassigned: { $sum: { $cond: [{ $eq: ['$assignedTo', null] }, 1, 0] } }
        }
      }
    ]).toArray();
    
    const result = stats[0] || {
      total: 0,
      open: 0,
      inProgress: 0,
      closed: 0,
      highPriority: 0,
      unassigned: 0
    };
    
    console.log('📊 Stats:', result);
    
    res.json({
      success: true,
      data: result
    });
    
  } catch (error) {
    console.error('❌ GET STATS ERROR:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch statistics',
      message: error.message
    });
  }
});

/**
 * @route   PUT /api/tickets/:id/status
 * @desc    Update ticket status
 * @access  Private
 */
router.put('/:id/status', async (req, res) => {
  console.log('\n🔄 ========== UPDATE TICKET STATUS ==========');
  
  try {
    const ticketId = new ObjectId(req.params.id);
    const { status, note } = req.body;
    const userId = req.user.userId;
    const userEmail = req.user.email;
    
    console.log('🎫 Ticket ID:', ticketId);
    console.log('📝 New Status:', status);
    console.log('👤 Updated By:', userEmail);
    
    // Validation
    const validStatuses = ['open', 'in_progress', 'closed'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid status',
        message: `Status must be one of: ${validStatuses.join(', ')}`
      });
    }
    
    // Get ticket
    const ticket = await req.db.collection('tickets').findOne({ _id: ticketId });
    if (!ticket) {
      return res.status(404).json({
        success: false,
        error: 'Ticket not found',
        message: 'The requested ticket does not exist'
      });
    }
    
    // Check permission
    const adminRoles = [
      'super_admin', 'superadmin', 'super', 'admin', 'employee',
      'org_admin', 'organization_admin',
      'fleet_manager', 'operations_manager', 'operations',
      'hr_manager', 'finance_admin', 'finance'
    ];
    
    const userRole = req.user.role?.toLowerCase()?.trim()?.replace(' ', '_');
    const isAdmin = adminRoles.includes(userRole);
    
    // Check if user is assigned to this ticket
    let isAssigned = false;
    if (ticket.assignedTo) {
      try {
        const userMongoId = await getUserMongoId(req.db, userId);
        isAssigned = ticket.assignedTo.toString() === userMongoId.toString();
      } catch (error) {
        // If user not found in MongoDB, check User ID
        isAssigned = false;
      }
    }
    
    if (!isAdmin && !isAssigned) {
      return res.status(403).json({
        success: false,
        error: 'Access denied',
        message: 'You can only update tickets assigned to you'
      });
    }
    
    // Update ticket
    const updateData = {
      $set: {
        status,
        updatedAt: new Date()
      },
      $push: {
        history: {
          action: `status_changed_to_${status}`,
          by: userEmail,
          timestamp: new Date(),
          note: note || `Status updated to ${status}`
        }
      }
    };
    
    const result = await req.db.collection('tickets').updateOne(
      { _id: ticketId },
      updateData
    );
    
    if (result.modifiedCount === 0) {
      return res.status(400).json({
        success: false,
        error: 'Update failed',
        message: 'Ticket was not updated'
      });
    }
    
    console.log('✅ Ticket Status Updated');
    
    // Send notification
    if (ticket.createdBy && ticket.createdBy.id) {
      const createdById = ticket.createdBy.firebaseUid || ticket.createdBy.id.toString();
      await sendTicketNotification('ticket_updated', { ...ticket, status }, createdById);
    }
    
    res.json({
      success: true,
      message: 'Ticket status updated successfully',
      data: { status }
    });
    
  } catch (error) {
    console.error('❌ UPDATE STATUS ERROR:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update ticket status',
      message: error.message
    });
  }
});

/**
 * @route   PUT /api/tickets/:id/assign
 * @desc    Reassign ticket (admin only)
 * @access  Private (admin)
 */
router.put('/:id/assign', async (req, res) => {
  console.log('\n👤 ========== REASSIGN TICKET ==========');
  
  try {
    // Check admin permission - accept multiple admin role names
    const adminRoles = [
      'super_admin', 'superadmin', 'super', 'admin', 'employee',
      'org_admin', 'organization_admin',
      'fleet_manager', 'operations_manager', 'operations',
      'hr_manager', 'finance_admin', 'finance'
    ];
    
    const userRole = req.user.role?.toLowerCase()?.trim()?.replace(' ', '_');
    const isAdmin = adminRoles.includes(userRole);
    
    if (!isAdmin) {
      return res.status(403).json({
        success: false,
        error: 'Access denied',
        message: 'Only administrators can reassign tickets'
      });
    }
    
    const ticketId = new ObjectId(req.params.id);
    const { assignedTo, note } = req.body;
    const userEmail = req.user.email;
    
    console.log('🎫 Ticket ID:', ticketId);
    console.log('👤 New Assignee:', assignedTo || 'Unassigned');
    
    // Get ticket
    const ticket = await req.db.collection('tickets').findOne({ _id: ticketId });
    if (!ticket) {
      return res.status(404).json({
        success: false,
        error: 'Ticket not found',
        message: 'The requested ticket does not exist'
      });
    }
    
    // Handle assignedTo ObjectId conversion with dual collection support
    let assignedToObjectId = null;
    if (assignedTo) {
      try {
        // First try to use as ObjectId directly
        assignedToObjectId = new ObjectId(assignedTo);
      } catch (error) {
        // If not valid ObjectId, try to find user by User ID in both collections
        let assignedUser = await req.db.collection('users').findOne({ firebaseUid: assignedTo });
        if (!assignedUser) {
          assignedUser = await req.db.collection('admin_users').findOne({ firebaseUid: assignedTo });
        }
        
        if (assignedUser) {
          assignedToObjectId = assignedUser._id;
        } else {
          return res.status(400).json({
            success: false,
            error: 'Invalid assignee',
            message: 'The specified user could not be found in either collection'
          });
        }
      }
    }
    
    // Update ticket
    const updateData = {
      $set: {
        assignedTo: assignedToObjectId,
        updatedAt: new Date()
      },
      $push: {
        history: {
          action: 'reassigned',
          by: userEmail,
          timestamp: new Date(),
          note: note || `Ticket reassigned to ${assignedTo || 'unassigned'}`
        }
      }
    };
    
    const result = await req.db.collection('tickets').updateOne(
      { _id: ticketId },
      updateData
    );
    
    if (result.modifiedCount === 0) {
      return res.status(400).json({
        success: false,
        error: 'Update failed',
        message: 'Ticket was not updated'
      });
    }
    
    console.log('✅ Ticket Reassigned');
    
    // Send notification to new assignee
    if (assignedToObjectId) {
      await sendTicketNotification('ticket_assigned', ticket, assignedToObjectId.toString());
    }
    
    res.json({
      success: true,
      message: 'Ticket reassigned successfully'
    });
    
  } catch (error) {
    console.error('❌ REASSIGN ERROR:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to reassign ticket',
      message: error.message
    });
  }
});

/**
 * @route   DELETE /api/tickets/:id
 * @desc    Delete ticket (admin only)
 * @access  Private (admin)
 */
router.delete('/:id', async (req, res) => {
  console.log('\n🗑️  ========== DELETE TICKET ==========');
  
  try {
    // Check admin permission - accept multiple admin role names
    const adminRoles = [
      'super_admin', 'superadmin', 'super', 'admin', 'employee',
      'org_admin', 'organization_admin',
      'fleet_manager', 'operations_manager', 'operations',
      'hr_manager', 'finance_admin', 'finance'
    ];
    
    const userRole = req.user.role?.toLowerCase()?.trim()?.replace(' ', '_');
    const isAdmin = adminRoles.includes(userRole);
    
    if (!isAdmin) {
      return res.status(403).json({
        success: false,
        error: 'Access denied',
        message: 'Only administrators can delete tickets'
      });
    }
    
    const ticketId = new ObjectId(req.params.id);
    
    console.log('🎫 Deleting Ticket ID:', ticketId);
    
    // Get ticket to delete attachment file
    const ticket = await req.db.collection('tickets').findOne({ _id: ticketId });
    if (!ticket) {
      return res.status(404).json({
        success: false,
        error: 'Ticket not found',
        message: 'The requested ticket does not exist'
      });
    }
    
    // Delete attachment file if exists
    if (ticket.attachment) {
      const filePath = path.join(__dirname, '..', ticket.attachment.path);
      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        console.log('🗑️  Deleted attachment file');
      }
    }
    
    // Delete ticket
    const result = await req.db.collection('tickets').deleteOne({ _id: ticketId });
    
    if (result.deletedCount === 0) {
      return res.status(400).json({
        success: false,
        error: 'Delete failed',
        message: 'Ticket was not deleted'
      });
    }
    
    console.log('✅ Ticket Deleted Successfully');
    
    res.json({
      success: true,
      message: 'Ticket deleted successfully'
    });
    
  } catch (error) {
    console.error('❌ DELETE ERROR:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete ticket',
      message: error.message
    });
  }
});

/**
 * @route   GET /api/tickets/:id
 * @desc    Get single ticket details
 * @access  Private
 */
router.get('/:id', async (req, res) => {
  console.log('\n📄 ========== GET TICKET DETAILS ==========');
  
  try {
    const ticketId = new ObjectId(req.params.id);
    const userId = req.user.userId;
    
    console.log('🎫 Ticket ID:', ticketId);
    
    // Get ticket
    const ticket = await req.db.collection('tickets').findOne({ _id: ticketId });
    
    if (!ticket) {
      return res.status(404).json({
        success: false,
        error: 'Ticket not found',
        message: 'The requested ticket does not exist'
      });
    }
    
    // Check permission
    const adminRoles = [
      'super_admin', 'superadmin', 'super', 'admin', 'employee',
      'org_admin', 'organization_admin',
      'fleet_manager', 'operations_manager', 'operations',
      'hr_manager', 'finance_admin', 'finance'
    ];
    
    const userRole = req.user.role?.toLowerCase()?.trim()?.replace(' ', '_');
    const isAdmin = adminRoles.includes(userRole);
    
    // Check if user is assigned to this ticket
    let isAssigned = false;
    if (ticket.assignedTo) {
      try {
        const userMongoId = await getUserMongoId(req.db, userId);
        isAssigned = ticket.assignedTo.toString() === userMongoId.toString();
      } catch (error) {
        // If user not found in MongoDB, check User ID
        isAssigned = false;
      }
    }
    
    // Check if user is the creator
    let isCreator = false;
    if (ticket.createdBy) {
      if (ticket.createdBy.firebaseUid) {
        isCreator = ticket.createdBy.firebaseUid === userId;
      } else if (ticket.createdBy.id) {
        try {
          const userMongoId = await getUserMongoId(req.db, userId);
          isCreator = ticket.createdBy.id.toString() === userMongoId.toString();
        } catch (error) {
          isCreator = ticket.createdBy.id === userId;
        }
      }
    }
    
    if (!isAdmin && !isAssigned && !isCreator) {
      return res.status(403).json({
        success: false,
        error: 'Access denied',
        message: 'You do not have permission to view this ticket'
      });
    }
    
    console.log('✅ Ticket Found:', ticket.ticketNumber);
    
    res.json({
      success: true,
      data: ticket
    });
    
  } catch (error) {
    console.error('❌ GET TICKET ERROR:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch ticket',
      message: error.message
    });
  }
});

// ============================================================================
// NOTE: Employee list is fetched from /api/users endpoint
// This ensures we only get admin users (not drivers, customers, clients)
// ============================================================================

module.exports = router;