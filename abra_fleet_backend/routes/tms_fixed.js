// routes/tms_fixed.js - FIXED TMS Backend with Proper User Filtering
// ============================================================================
// COMPLETE TMS BACKEND - POST FIREBASE REMOVAL
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

const uploadsDir = path.join(__dirname, '../uploads/tickets');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadsDir),
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, uniqueSuffix + path.extname(file.originalname));
  }
});

const fileFilter = (req, file, cb) => {
  const allowedTypes = [
    'image/jpeg', 'image/png', 'image/gif', 'application/pdf',
    'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
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
  limits: { fileSize: 5 * 1024 * 1024 } // 5MB limit
});

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Check if user has admin role
 */
function isAdminRole(role) {
  const adminRoles = [
    'super_admin', 'superadmin', 'super', 'admin',
    'org_admin', 'organization_admin',
    'fleet_manager', 'operations_manager', 'operations',
    'hr_manager', 'finance_admin', 'finance', 'employee'
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
  
  const counterDoc = await db.collection('ticket_counters').findOneAndUpdate(
    { _id: dateKey },
    { $inc: { sequence: 1 } },
    { upsert: true, returnDocument: 'after' }
  );
  
  const sequence = counterDoc.sequence;
  return `${datePrefix}-${String(sequence).padStart(3, '0')}`;
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
    console.log('   Created By:', createdBy.email);
    console.log('   Created By User ID:', createdBy.userId);
    
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
    
    // Handle assignedTo - convert to ObjectId if provided
    let assignedToObjectId = null;
    if (assignedTo) {
      try {
        assignedToObjectId = new ObjectId(assignedTo);
      } catch (error) {
        console.log('⚠️ Invalid assignedTo ID:', assignedTo);
      }
    }

    // Prepare ticket document
    const newTicket = {
      ticketNumber,
      subject,
      message,
      priority: priority.toLowerCase(),
      status: status || 'open',
      assignedTo: assignedToObjectId,
      createdBy: {
        userId: createdBy.userId, // Store the JWT userId (MongoDB _id)
        name: createdBy.name,
        email: createdBy.email,
        role: createdBy.role
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
    
    res.status(201).json({
      success: true,
      message: 'Ticket created successfully',
      data: newTicket
    });
    
  } catch (error) {
    console.error('❌ CREATE TICKET ERROR:', error);
    
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
    const userId = req.user.userId; // This is the MongoDB _id from JWT
    const { status, priority, dateFrom, dateTo, page = 1, limit = 50 } = req.query;
    
    // Convert userId string to ObjectId
    let userObjectId;
    try {
      userObjectId = new ObjectId(userId);
      console.log('   ✅ User ObjectId:', userObjectId);
    } catch (error) {
      console.log('❌ Invalid user ID format:', userId);
      return res.status(400).json({
        success: false,
        error: 'Invalid user ID',
        message: 'User ID format is invalid'
      });
    }
    
    // Build query - show tickets where user is EITHER assignedTo OR createdBy
    const query = {
      $or: [
        { assignedTo: userObjectId },
        { 'createdBy.userId': userId }, // String comparison
        { 'createdBy.userId': userObjectId } // ObjectId comparison
      ]
    };
    
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
  
  try {
    const userRole = req.user.role?.toLowerCase()?.trim()?.replace(' ', '_');
    const isAdmin = isAdminRole(req.user.role);
    
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
    
    if (status && status !== 'all') {
      if (status === 'active') {
        query.status = { $in: ['open', 'in_progress'] };
      } else {
        query.status = status;
      }
    } else {
      query.status = { $ne: 'closed' };
    }
    
    if (priority && priority !== 'all') {
      query.priority = priority;
    }
    
    if (assignedTo && assignedTo !== 'all') {
      if (assignedTo === 'unassigned') {
        query.assignedTo = null;
      } else {
        try {
          query.assignedTo = new ObjectId(assignedTo);
        } catch (error) {
          console.log('⚠️ Invalid assignedTo ID');
        }
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
      .find(query)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(parseInt(limit))
      .toArray();
    
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
 * @route   GET /api/tickets/stats
 * @desc    Get ticket statistics
 * @access  Private
 */
router.get('/stats', async (req, res) => {
  console.log('\n📊 ========== GET TICKET STATS ==========');
  
  try {
    const userId = req.user.userId;
    const isAdmin = isAdminRole(req.user.role);
    
    // Build match query
    let matchQuery = {};
    if (!isAdmin) {
      try {
        const userObjectId = new ObjectId(userId);
        matchQuery = {
          $or: [
            { assignedTo: userObjectId },
            { 'createdBy.userId': userId },
            { 'createdBy.userId': userObjectId }
          ]
        };
      } catch (error) {
        matchQuery = { 'createdBy.userId': userId };
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
        error: 'Ticket not found'
      });
    }
    
    // Check permission
    const isAdmin = isAdminRole(req.user.role);
    const userObjectId = new ObjectId(userId);
    const isAssigned = ticket.assignedTo && ticket.assignedTo.toString() === userObjectId.toString();
    const isCreator = ticket.createdBy && 
                      (ticket.createdBy.userId === userId || 
                       ticket.createdBy.userId?.toString() === userObjectId.toString());
    
    if (!isAdmin && !isAssigned && !isCreator) {
      return res.status(403).json({
        success: false,
        error: 'Access denied',
        message: 'You can only update tickets assigned to you or created by you'
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
    
    await req.db.collection('tickets').updateOne({ _id: ticketId }, updateData);
    
    console.log('✅ Ticket Status Updated');
    
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
 * @route   GET /api/tickets/:id
 * @desc    Get single ticket details
 * @access  Private
 */
router.get('/:id', async (req, res) => {
  console.log('\n📄 ========== GET TICKET DETAILS ==========');
  
  try {
    const ticketId = new ObjectId(req.params.id);
    const userId = req.user.userId;
    
    const ticket = await req.db.collection('tickets').findOne({ _id: ticketId });
    
    if (!ticket) {
      return res.status(404).json({
        success: false,
        error: 'Ticket not found'
      });
    }
    
    // Check permission
    const isAdmin = isAdminRole(req.user.role);
    const userObjectId = new ObjectId(userId);
    const isAssigned = ticket.assignedTo && ticket.assignedTo.toString() === userObjectId.toString();
    const isCreator = ticket.createdBy && 
                      (ticket.createdBy.userId === userId || 
                       ticket.createdBy.userId?.toString() === userObjectId.toString());
    
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

module.exports = router;
