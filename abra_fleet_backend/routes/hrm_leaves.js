// routes/hrm_leaves.js - WITH NOTIFICATION SUPPORT

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const admin = require('../config/firebase'); // Firebase Admin SDK

/**
 * Helper function to send leave status notification to employee
 */
async function sendLeaveStatusNotification(employeeData, leaveData, oldStatus, newStatus, db) {
  try {
    console.log(`📧 Sending leave ${newStatus} notification to ${employeeData.name}`);
    
    // Only send notification if status actually changed and is approved/rejected
    if (oldStatus === newStatus || (newStatus !== 'approved' && newStatus !== 'rejected')) {
      console.log('⏭️  Skipping notification - no significant status change');
      return;
    }
    
    // Prepare notification data
    const notificationData = {
      title: newStatus === 'approved' 
        ? '✅ Leave Request Approved' 
        : '❌ Leave Request Rejected',
      body: newStatus === 'approved'
        ? `Your leave request from ${new Date(leaveData.start_date).toLocaleDateString()} to ${new Date(leaveData.end_date).toLocaleDateString()} has been approved.`
        : `Your leave request from ${new Date(leaveData.start_date).toLocaleDateString()} to ${new Date(leaveData.end_date).toLocaleDateString()} has been rejected.`,
      type: newStatus === 'approved' ? 'leave_approved' : 'leave_rejected',
      leaveId: leaveData._id.toString(),
      startDate: leaveData.start_date,
      endDate: leaveData.end_date,
      reason: leaveData.reason,
      timestamp: new Date().toISOString(),
      read: false
    };
    
    // 1. Store notification in MongoDB
    const notificationsCollection = db.collection('notifications');
    await notificationsCollection.insertOne({
      userId: employeeData._id.toString(),
      userEmail: employeeData.email,
      userName: employeeData.name,
      ...notificationData,
      createdAt: new Date(),
    });
    console.log('✅ Notification stored in MongoDB');
    
    // 2. Send Firebase push notification if employee has FCM token
    if (employeeData.fcmToken) {
      const message = {
        token: employeeData.fcmToken,
        notification: {
          title: notificationData.title,
          body: notificationData.body,
        },
        data: {
          type: notificationData.type,
          leaveId: notificationData.leaveId,
          startDate: notificationData.startDate,
          endDate: notificationData.endDate,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
      };
      
      try {
        await admin.messaging().send(message);
        console.log('✅ Firebase push notification sent');
      } catch (fcmError) {
        console.warn('⚠️  FCM notification failed:', fcmError.message);
        // Don't fail the whole operation if FCM fails
      }
    } else {
      console.log('ℹ️  Employee has no FCM token - notification stored in DB only');
    }
    
    // 3. Send Firebase Realtime Database notification (for web/desktop)
    if (employeeData.firebaseUid) {
      const rtdbRef = admin.database().ref(`notifications/${employeeData.firebaseUid}`);
      const newNotificationRef = rtdbRef.push();
      await newNotificationRef.set({
        ...notificationData,
        id: newNotificationRef.key,
      });
      console.log('✅ Firebase RTDB notification sent');
    }
    
    console.log('✅ All notifications sent successfully');
    
  } catch (error) {
    console.error('❌ Error sending leave notification:', error);
    // Don't throw - we don't want to fail the leave update if notification fails
  }
}

/**
 * GET /api/hrm/leaves
 * Fetch all leave requests with employee details
 */
router.get('/', async (req, res) => {
  console.log('\n📥 GET /api/hrm/leaves - Fetch all leave requests');
  console.log('─'.repeat(80));
  
  try {
    const leavesCollection = req.db.collection('hr_leaves');
    const employeesCollection = req.db.collection('hr_employees');
    
    // Fetch all leave requests
    const leaves = await leavesCollection.find({}).sort({ createdAt: -1 }).toArray();
    console.log(`✅ Found ${leaves.length} leave requests`);
    
    // Enrich with employee details
    const enrichedLeaves = await Promise.all(
      leaves.map(async (leave) => {
        let employeeName = 'Unknown';
        
        try {
          // Find employee by ID
          const employee = await employeesCollection.findOne({
            _id: ObjectId.isValid(leave.employee_id) ? new ObjectId(leave.employee_id) : leave.employee_id
          });
          
          if (employee) {
            employeeName = employee.name;
          }
        } catch (err) {
          console.warn(`⚠️  Could not find employee for leave ${leave._id}:`, err.message);
        }
        
        return {
          ...leave,
          employee_name: employeeName
        };
      })
    );
    
    console.log('✅ Leave requests fetched and enriched successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Leave requests fetched successfully',
      data: enrichedLeaves,
      count: enrichedLeaves.length
    });
    
  } catch (error) {
    console.error('❌ Error fetching leave requests:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch leave requests',
      message: error.message
    });
  }
});

/**
 * POST /api/hrm/leaves
 * Create a new leave request
 */
router.post('/', async (req, res) => {
  console.log('\n📥 POST /api/hrm/leaves - Create new leave request');
  console.log('─'.repeat(80));
  console.log('Body:', JSON.stringify(req.body, null, 2));
  
  try {
    const { employee_id, start_date, end_date, reason, status } = req.body;
    
    // Validation
    if (!employee_id) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Employee ID is required'
      });
    }
    
    if (!start_date || !end_date) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Start date and end date are required'
      });
    }
    
    if (!reason || reason.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Reason is required'
      });
    }
    
    // Validate dates
    const startDate = new Date(start_date);
    const endDate = new Date(end_date);
    
    if (isNaN(startDate.getTime()) || isNaN(endDate.getTime())) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Invalid date format'
      });
    }
    
    if (endDate < startDate) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'End date must be after or equal to start date'
      });
    }
    
    // Verify employee exists
    const employeesCollection = req.db.collection('hr_employees');
    const employee = await employeesCollection.findOne({
      _id: ObjectId.isValid(employee_id) ? new ObjectId(employee_id) : employee_id
    });
    
    if (!employee) {
      return res.status(404).json({
        success: false,
        error: 'Not found',
        message: 'Employee not found'
      });
    }
    
    console.log('✅ Employee found:', employee.name);
    
    // Create leave request
    const leavesCollection = req.db.collection('hr_leaves');
    
    const newLeave = {
      employee_id: employee_id,
      start_date: startDate.toISOString(),
      end_date: endDate.toISOString(),
      reason: reason.trim(),
      status: status || 'pending',
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: req.user?.email || 'admin'
    };
    
    const result = await leavesCollection.insertOne(newLeave);
    console.log('✅ Leave request created with ID:', result.insertedId);
    
    // Fetch the created leave with employee name
    const createdLeave = await leavesCollection.findOne({ _id: result.insertedId });
    const enrichedLeave = {
      ...createdLeave,
      employee_name: employee.name
    };
    
    console.log('✅ Leave request created successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.status(201).json({
      success: true,
      message: 'Leave request created successfully',
      data: enrichedLeave
    });
    
  } catch (error) {
    console.error('❌ Error creating leave request:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to create leave request',
      message: error.message
    });
  }
});

/**
 * PUT /api/hrm/leaves/:id
 * Update an existing leave request (WITH NOTIFICATION SUPPORT)
 */
router.put('/:id', async (req, res) => {
  console.log('\n📥 PUT /api/hrm/leaves/:id - Update leave request');
  console.log('─'.repeat(80));
  console.log('Leave ID:', req.params.id);
  console.log('Body:', JSON.stringify(req.body, null, 2));
  
  try {
    const { id } = req.params;
    const { employee_id, start_date, end_date, reason, status } = req.body;
    
    // Validate ID
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Invalid leave request ID'
      });
    }
    
    // Validation
    if (!employee_id) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Employee ID is required'
      });
    }
    
    if (!start_date || !end_date) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Start date and end date are required'
      });
    }
    
    if (!reason || reason.trim() === '') {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Reason is required'
      });
    }
    
    // Validate dates
    const startDate = new Date(start_date);
    const endDate = new Date(end_date);
    
    if (isNaN(startDate.getTime()) || isNaN(endDate.getTime())) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Invalid date format'
      });
    }
    
    if (endDate < startDate) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'End date must be after or equal to start date'
      });
    }
    
    const leavesCollection = req.db.collection('hr_leaves');
    
    // ✅ FETCH OLD LEAVE DATA BEFORE UPDATING (to detect status change)
    const oldLeave = await leavesCollection.findOne({ _id: new ObjectId(id) });
    
    if (!oldLeave) {
      return res.status(404).json({
        success: false,
        error: 'Not found',
        message: 'Leave request not found'
      });
    }
    
    const oldStatus = oldLeave.status;
    console.log('📌 Old status:', oldStatus, '→ New status:', status);
    
    // Verify employee exists
    const employeesCollection = req.db.collection('hr_employees');
    const employee = await employeesCollection.findOne({
      _id: ObjectId.isValid(employee_id) ? new ObjectId(employee_id) : employee_id
    });
    
    if (!employee) {
      return res.status(404).json({
        success: false,
        error: 'Not found',
        message: 'Employee not found'
      });
    }
    
    console.log('✅ Employee found:', employee.name);
    
    // Update leave request
    const updateData = {
      employee_id: employee_id,
      start_date: startDate.toISOString(),
      end_date: endDate.toISOString(),
      reason: reason.trim(),
      status: status || 'pending',
      updatedAt: new Date(),
      updatedBy: req.user?.email || 'admin'
    };
    
    const result = await leavesCollection.updateOne(
      { _id: new ObjectId(id) },
      { $set: updateData }
    );
    
    console.log('✅ Leave request updated successfully');
    
    // Fetch updated leave with employee name
    const updatedLeave = await leavesCollection.findOne({ _id: new ObjectId(id) });
    const enrichedLeave = {
      ...updatedLeave,
      employee_name: employee.name
    };
    
    // ✅ SEND NOTIFICATION IF STATUS CHANGED TO APPROVED/REJECTED
    if (oldStatus !== status && (status === 'approved' || status === 'rejected')) {
      console.log('🔔 Status changed - sending notification to employee...');
      await sendLeaveStatusNotification(employee, updatedLeave, oldStatus, status, req.db);
    }
    
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Leave request updated successfully',
      data: enrichedLeave,
      notificationSent: oldStatus !== status && (status === 'approved' || status === 'rejected')
    });
    
  } catch (error) {
    console.error('❌ Error updating leave request:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to update leave request',
      message: error.message
    });
  }
});

/**
 * DELETE /api/hrm/leaves/:id
 * Delete a leave request
 */
router.delete('/:id', async (req, res) => {
  console.log('\n📥 DELETE /api/hrm/leaves/:id - Delete leave request');
  console.log('─'.repeat(80));
  console.log('Leave ID:', req.params.id);
  
  try {
    const { id } = req.params;
    
    // Validate ID
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Invalid leave request ID'
      });
    }
    
    const leavesCollection = req.db.collection('hr_leaves');
    
    // Check if leave exists
    const leave = await leavesCollection.findOne({ _id: new ObjectId(id) });
    
    if (!leave) {
      return res.status(404).json({
        success: false,
        error: 'Not found',
        message: 'Leave request not found'
      });
    }
    
    // Delete leave request
    const result = await leavesCollection.deleteOne({ _id: new ObjectId(id) });
    
    console.log('✅ Leave request deleted successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Leave request deleted successfully',
      deletedCount: result.deletedCount
    });
    
  } catch (error) {
    console.error('❌ Error deleting leave request:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to delete leave request',
      message: error.message
    });
  }
});

/**
 * GET /api/hrm/leaves/:id
 * Get a single leave request by ID
 */
router.get('/:id', async (req, res) => {
  console.log('\n📥 GET /api/hrm/leaves/:id - Get single leave request');
  console.log('─'.repeat(80));
  console.log('Leave ID:', req.params.id);
  
  try {
    const { id } = req.params;
    
    // Validate ID
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Invalid leave request ID'
      });
    }
    
    const leavesCollection = req.db.collection('hr_leaves');
    const employeesCollection = req.db.collection('hr_employees');
    
    // Fetch leave request
    const leave = await leavesCollection.findOne({ _id: new ObjectId(id) });
    
    if (!leave) {
      return res.status(404).json({
        success: false,
        error: 'Not found',
        message: 'Leave request not found'
      });
    }
    
    // Enrich with employee details
    let employeeName = 'Unknown';
    try {
      const employee = await employeesCollection.findOne({
        _id: ObjectId.isValid(leave.employee_id) ? new ObjectId(leave.employee_id) : leave.employee_id
      });
      
      if (employee) {
        employeeName = employee.name;
      }
    } catch (err) {
      console.warn('⚠️  Could not find employee:', err.message);
    }
    
    const enrichedLeave = {
      ...leave,
      employee_name: employeeName
    };
    
    console.log('✅ Leave request fetched successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Leave request fetched successfully',
      data: enrichedLeave
    });
    
  } catch (error) {
    console.error('❌ Error fetching leave request:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch leave request',
      message: error.message
    });
  }
});

module.exports = router;