// routes/maintenance_router.js - Maintenance management routes
const express = require('express');
const router = express.Router();
const { body, validationResult, param, query } = require('express-validator');
const emailService = require('../services/email_service');

// Validation middleware for maintenance scheduling
const validateMaintenanceSchedule = [
  body('vehicleId').notEmpty().withMessage('Vehicle ID is required'),
  body('maintenanceType').notEmpty().withMessage('Maintenance type is required'),
  body('scheduledDate').isISO8601().withMessage('Valid scheduled date is required'),
  body('vendorEmail').isEmail().withMessage('Valid vendor email is required'),
  body('vendorName').notEmpty().withMessage('Vendor name is required'),
  body('description').optional().isLength({ max: 500 }).withMessage('Description must be less than 500 characters'),
  body('estimatedCost').optional().isFloat({ min: 0 }).withMessage('Estimated cost must be a positive number'),
];

// Validation middleware for maintenance reports
const validateMaintenanceReport = [
  body('vehicleId').notEmpty().withMessage('Vehicle ID is required'),
  body('maintenanceType').notEmpty().withMessage('Maintenance type is required'),
  body('completedDate').isISO8601().withMessage('Valid completion date is required'),
  body('vendorName').notEmpty().withMessage('Vendor name is required'),
  body('actualCost').isFloat({ min: 0 }).withMessage('Actual cost must be a positive number'),
  body('description').notEmpty().withMessage('Description is required'),
  body('status').isIn(['completed', 'pending', 'in_progress', 'cancelled']).withMessage('Invalid status'),
];

// Helper function to handle validation errors
function handleValidationErrors(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      success: false,
      message: 'Validation error',
      errors: errors.array().map(err => err.msg)
    });
  }
  next();
}

// @route   POST /api/maintenance/schedule
// @desc    Schedule maintenance and send email to vendor
// @access  Private (Admin)
router.post('/schedule', validateMaintenanceSchedule, handleValidationErrors, async (req, res) => {
  try {
    const {
      vehicleId,
      maintenanceType,
      scheduledDate,
      vendorEmail,
      vendorName,
      vendorPhone,
      description,
      estimatedCost,
      priority
    } = req.body;

    console.log('\n🔧 ========== SCHEDULE MAINTENANCE ==========');
    console.log('Vehicle ID:', vehicleId);
    console.log('Maintenance Type:', maintenanceType);
    console.log('Scheduled Date:', scheduledDate);
    console.log('Vendor Email:', vendorEmail);
    console.log('Vendor Name:', vendorName);
    console.log('===========================================');

    // Get vehicle details
    const { ObjectId } = require('mongodb');
    let vehicle;
    
    console.log('🔍 Looking for vehicle with ID:', vehicleId);
    
    // Try to find vehicle by different identifiers
    try {
      // First try as MongoDB ObjectId
      if (ObjectId.isValid(vehicleId)) {
        console.log('   Trying as MongoDB ObjectId...');
        vehicle = await req.db.collection('vehicles').findOne({
          _id: new ObjectId(vehicleId)
        });
      }
      
      // If not found, try other identifiers
      if (!vehicle) {
        console.log('   Trying as vehicleId/registrationNumber/vehicleNumber...');
        vehicle = await req.db.collection('vehicles').findOne({
          $or: [
            { vehicleId: vehicleId },
            { registrationNumber: vehicleId },
            { vehicleNumber: vehicleId },
            { 'registrationNumber': { $regex: vehicleId, $options: 'i' } },
            { 'vehicleNumber': { $regex: vehicleId, $options: 'i' } },
            { 'vehicleId': { $regex: vehicleId, $options: 'i' } }
          ]
        });
      }
      
      // If still not found, try a broader search
      if (!vehicle) {
        console.log('   Trying broader search...');
        const allVehicles = await req.db.collection('vehicles').find({}).limit(10).toArray();
        console.log('   Available vehicles:', allVehicles.map(v => ({
          _id: v._id,
          vehicleId: v.vehicleId,
          registrationNumber: v.registrationNumber,
          vehicleNumber: v.vehicleNumber
        })));
        
        // Try to find by partial match
        vehicle = allVehicles.find(v => 
          (v.vehicleId && v.vehicleId.includes(vehicleId)) ||
          (v.registrationNumber && v.registrationNumber.includes(vehicleId)) ||
          (v.vehicleNumber && v.vehicleNumber.includes(vehicleId))
        );
      }
    } catch (error) {
      console.log('❌ Error finding vehicle:', error.message);
    }
    
    if (vehicle) {
      console.log('✅ Found vehicle:', vehicle.registrationNumber || vehicle.vehicleNumber);
    } else {
      console.log('❌ Vehicle not found with ID:', vehicleId);
    }

    if (!vehicle) {
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found'
      });
    }

    // Create maintenance schedule record
    const maintenanceSchedule = {
      vehicleId: vehicle._id,
      vehicleNumber: vehicle.registrationNumber || vehicle.vehicleNumber,
      vehicleMake: vehicle.make || '',
      vehicleModel: vehicle.model || '',
      maintenanceType,
      scheduledDate: new Date(scheduledDate),
      vendorEmail,
      vendorName,
      vendorPhone: vendorPhone || '',
      description: description || '',
      estimatedCost: estimatedCost || 0,
      priority: priority || 'medium',
      status: 'scheduled',
      emailSent: false,
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: { email: req.user?.uid || 'system',
        email: req.user?.email || 'system',
        name: req.user?.name || req.user?.email || 'System'
       }
    };

    // Insert into database
    const result = await req.db.collection('maintenance_schedules').insertOne(maintenanceSchedule);
    
    if (!result.insertedId) {
      throw new Error('Failed to create maintenance schedule');
    }

    console.log('✅ Maintenance schedule created with ID:', result.insertedId);

    // Send email to vendor
    try {
      console.log('📧 Sending email to vendor...');
      
      const emailSubject = `🔧 Maintenance Request - ${vehicle.registrationNumber || vehicle.vehicleNumber}`;
      
      const emailHtml = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { font-family: Arial, sans-serif; line-height: 1.6; color: #333; margin: 0; padding: 0; }
    .container { max-width: 600px; margin: 0 auto; padding: 20px; }
    .header { background: linear-gradient(135deg, #0D47A1 0%, #1565C0 100%); color: white; padding: 30px; text-align: center; border-radius: 10px 10px 0 0; }
    .content { background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px; }
    .info-box { background: white; padding: 15px; border-left: 4px solid #0D47A1; margin: 20px 0; }
    .urgent-box { background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0; }
    .footer { text-align: center; color: #666; font-size: 12px; margin-top: 30px; }
    .button { display: inline-block; background: #0D47A1; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; margin: 20px 0; font-weight: bold; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🔧 Maintenance Request</h1>
      <p>Abra Travels Fleet Management</p>
    </div>
    <div class="content">
      <p>Dear <strong>${vendorName}</strong>,</p>
      
      <p>We have a maintenance request for one of our vehicles. Please review the details below and confirm your availability.</p>
      
      <div class="info-box">
        <h3>🚗 Vehicle Details:</h3>
        <p><strong>Vehicle Number:</strong> ${vehicle.registrationNumber || vehicle.vehicleNumber}</p>
        <p><strong>Make & Model:</strong> ${vehicle.make || ''} ${vehicle.model || ''}</p>
        <p><strong>Vehicle Type:</strong> ${vehicle.type || vehicle.vehicleType || 'N/A'}</p>
      </div>
      
      <div class="info-box">
        <h3>🔧 Maintenance Details:</h3>
        <p><strong>Type:</strong> ${maintenanceType}</p>
        <p><strong>Scheduled Date:</strong> ${new Date(scheduledDate).toLocaleDateString('en-US', { 
          weekday: 'long', 
          year: 'numeric', 
          month: 'long', 
          day: 'numeric' 
        })}</p>
        <p><strong>Priority:</strong> ${priority?.toUpperCase() || 'MEDIUM'}</p>
        ${estimatedCost ? `<p><strong>Estimated Budget:</strong> ₹${estimatedCost}</p>` : ''}
        ${description ? `<p><strong>Description:</strong> ${description}</p>` : ''}
      </div>
      
      ${priority === 'high' || priority === 'urgent' ? `
      <div class="urgent-box">
        <h3>⚠️ URGENT REQUEST</h3>
        <p>This maintenance request has been marked as ${priority?.toUpperCase()}. Please prioritize this request and respond as soon as possible.</p>
      </div>
      ` : ''}
      
      <p><strong>Next Steps:</strong></p>
      <ul>
        <li>Review the maintenance requirements</li>
        <li>Confirm your availability for the scheduled date</li>
        <li>Contact us to discuss any specific requirements</li>
        <li>Provide a detailed quote if requested</li>
      </ul>
      
      <p><strong>Contact Information:</strong></p>
      <p>📧 Email: ${process.env.SMTP_USER}<br>
      📞 Phone: +91 9876543210<br>
      🏢 Abra Travels Fleet Management</p>
      
      <p>Please confirm receipt of this request and your availability at your earliest convenience.</p>
      
      <p>Thank you for your continued partnership.</p>
      
      <p>Best regards,<br><strong>Abra Travels Maintenance Team</strong></p>
    </div>
    <div class="footer">
      <p>© ${new Date().getFullYear()} Abra Travels. All rights reserved.</p>
      <p>This is an automated maintenance request from Abra Travels Fleet Management System</p>
    </div>
  </div>
</body>
</html>
      `;

      const emailText = `
🔧 Maintenance Request - Abra Travels

Dear ${vendorName},

We have a maintenance request for one of our vehicles. Please review the details below:

🚗 Vehicle Details:
- Vehicle Number: ${vehicle.registrationNumber || vehicle.vehicleNumber}
- Make & Model: ${vehicle.make || ''} ${vehicle.model || ''}
- Vehicle Type: ${vehicle.type || vehicle.vehicleType || 'N/A'}

🔧 Maintenance Details:
- Type: ${maintenanceType}
- Scheduled Date: ${new Date(scheduledDate).toLocaleDateString()}
- Priority: ${priority?.toUpperCase() || 'MEDIUM'}
${estimatedCost ? `- Estimated Budget: ₹${estimatedCost}` : ''}
${description ? `- Description: ${description}` : ''}

${priority === 'high' || priority === 'urgent' ? `
⚠️ URGENT REQUEST
This maintenance request has been marked as ${priority?.toUpperCase()}. Please prioritize this request and respond as soon as possible.
` : ''}

Next Steps:
- Review the maintenance requirements
- Confirm your availability for the scheduled date
- Contact us to discuss any specific requirements
- Provide a detailed quote if requested

Contact Information:
Email: ${process.env.SMTP_USER}
Phone: +91 9876543210
Abra Travels Fleet Management

Please confirm receipt of this request and your availability at your earliest convenience.

Thank you for your continued partnership.

Best regards,
Abra Travels Maintenance Team

© ${new Date().getFullYear()} Abra Travels. All rights reserved.
      `;

      const emailResult = await emailService.sendEmail(
        vendorEmail,
        emailSubject,
        emailText,
        emailHtml
      );

      if (emailResult.success) {
        console.log('✅ Email sent successfully to vendor');
        
        // Update the maintenance schedule to mark email as sent
        await req.db.collection('maintenance_schedules').updateOne(
          { _id: result.insertedId },
          { 
            $set: { 
              emailSent: true, 
              emailSentAt: new Date(),
              emailMessageId: emailResult.messageId
            } 
          }
        );
      } else {
        console.log('❌ Failed to send email to vendor:', emailResult.error);
      }

    } catch (emailError) {
      console.error('❌ Email sending error:', emailError);
      // Don't fail the entire request if email fails
    }

    // Get the created maintenance schedule
    const createdSchedule = await req.db.collection('maintenance_schedules').findOne({
      _id: result.insertedId
    });

    console.log('===========================================\n');

    res.status(201).json({
      success: true,
      message: 'Maintenance scheduled successfully and vendor notified',
      data: createdSchedule
    });

  } catch (error) {
    console.error('❌ Schedule maintenance error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while scheduling maintenance',
      error: error.message
    });
  }
});

// @route   GET /api/maintenance/schedules
// @desc    Get all maintenance schedules
// @access  Private (Admin)
router.get('/schedules', async (req, res) => {
  try {
    const { page = 1, limit = 10, status, vehicleId } = req.query;
    const skip = (parseInt(page) - 1) * parseInt(limit);

    // Build filter
    let filter = {};
    if (status) filter.status = status;
    if (vehicleId) filter.vehicleId = vehicleId;

    const schedules = await req.db.collection('maintenance_schedules')
      .find(filter)
      .sort({ scheduledDate: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();

    const total = await req.db.collection('maintenance_schedules').countDocuments(filter);

    res.json({
      success: true,
      data: schedules,
      pagination: {
        current: parseInt(page),
        pages: Math.ceil(total / parseInt(limit)),
        total,
        limit: parseInt(limit)
      }
    });

  } catch (error) {
    console.error('Get maintenance schedules error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while fetching maintenance schedules'
    });
  }
});

// @route   POST /api/maintenance/reports
// @desc    Create a maintenance report
// @access  Private (Admin)
router.post('/reports', validateMaintenanceReport, handleValidationErrors, async (req, res) => {
  try {
    const {
      vehicleId,
      maintenanceType,
      completedDate,
      vendorName,
      vendorEmail,
      actualCost,
      description,
      status,
      partsReplaced,
      nextMaintenanceDue,
      warrantyInfo,
      invoiceNumber
    } = req.body;

    console.log('\n📋 ========== CREATE MAINTENANCE REPORT ==========');
    console.log('Vehicle ID:', vehicleId);
    console.log('Maintenance Type:', maintenanceType);
    console.log('Completed Date:', completedDate);
    console.log('Vendor:', vendorName);
    console.log('Cost:', actualCost);
    console.log('===============================================');

    // Get vehicle details
    const { ObjectId } = require('mongodb');
    let vehicle;
    
    console.log('🔍 Looking for vehicle with ID:', vehicleId);
    
    // Try to find vehicle by different identifiers
    try {
      // First try as MongoDB ObjectId
      if (ObjectId.isValid(vehicleId)) {
        console.log('   Trying as MongoDB ObjectId...');
        vehicle = await req.db.collection('vehicles').findOne({
          _id: new ObjectId(vehicleId)
        });
      }
      
      // If not found, try other identifiers
      if (!vehicle) {
        console.log('   Trying as vehicleId/registrationNumber/vehicleNumber...');
        vehicle = await req.db.collection('vehicles').findOne({
          $or: [
            { vehicleId: vehicleId },
            { registrationNumber: vehicleId },
            { vehicleNumber: vehicleId },
            { 'registrationNumber': { $regex: vehicleId, $options: 'i' } },
            { 'vehicleNumber': { $regex: vehicleId, $options: 'i' } },
            { 'vehicleId': { $regex: vehicleId, $options: 'i' } }
          ]
        });
      }
      
      // If still not found, try a broader search
      if (!vehicle) {
        console.log('   Trying broader search...');
        const allVehicles = await req.db.collection('vehicles').find({}).limit(10).toArray();
        console.log('   Available vehicles:', allVehicles.map(v => ({
          _id: v._id,
          vehicleId: v.vehicleId,
          registrationNumber: v.registrationNumber,
          vehicleNumber: v.vehicleNumber
        })));
        
        // Try to find by partial match
        vehicle = allVehicles.find(v => 
          (v.vehicleId && v.vehicleId.includes(vehicleId)) ||
          (v.registrationNumber && v.registrationNumber.includes(vehicleId)) ||
          (v.vehicleNumber && v.vehicleNumber.includes(vehicleId))
        );
      }
    } catch (error) {
      console.log('❌ Error finding vehicle:', error.message);
    }

    if (!vehicle) {
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found'
      });
    }

    // Create maintenance report
    const maintenanceReport = {
      vehicleId: vehicle._id,
      vehicleNumber: vehicle.registrationNumber || vehicle.vehicleNumber,
      vehicleMake: vehicle.make || '',
      vehicleModel: vehicle.model || '',
      maintenanceType,
      completedDate: new Date(completedDate),
      vendorName,
      vendorEmail: vendorEmail || '',
      actualCost: parseFloat(actualCost),
      description,
      status,
      partsReplaced: partsReplaced || [],
      nextMaintenanceDue: nextMaintenanceDue ? new Date(nextMaintenanceDue) : null,
      warrantyInfo: warrantyInfo || '',
      invoiceNumber: invoiceNumber || '',
      createdAt: new Date(),
      updatedAt: new Date(),
      createdBy: { email: req.user?.uid || 'system',
        email: req.user?.email || 'system',
        name: req.user?.name || req.user?.email || 'System'
       }
    };

    // Insert into database
    const result = await req.db.collection('maintenance_reports').insertOne(maintenanceReport);
    
    if (!result.insertedId) {
      throw new Error('Failed to create maintenance report');
    }

    console.log('✅ Maintenance report created with ID:', result.insertedId);

    // Update vehicle's last maintenance date if completed
    if (status === 'completed') {
      await req.db.collection('vehicles').updateOne(
        { _id: vehicle._id },
        {
          $set: {
            'maintenance.lastServiceDate': new Date(completedDate),
            'maintenance.nextServiceDue': nextMaintenanceDue ? new Date(nextMaintenanceDue) : null,
            updatedAt: new Date()
          }
        }
      );
      console.log('✅ Vehicle maintenance dates updated');
    }

    // Get the created report
    const createdReport = await req.db.collection('maintenance_reports').findOne({
      _id: result.insertedId
    });

    console.log('===============================================\n');

    res.status(201).json({
      success: true,
      message: 'Maintenance report created successfully',
      data: createdReport
    });

  } catch (error) {
    console.error('❌ Create maintenance report error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while creating maintenance report',
      error: error.message
    });
  }
});

// @route   GET /api/maintenance/reports
// @desc    Get all maintenance reports
// @access  Private (Admin)
router.get('/reports', async (req, res) => {
  try {
    const { page = 1, limit = 10, status, vehicleId, maintenanceType } = req.query;
    const skip = (parseInt(page) - 1) * parseInt(limit);

    // Build filter
    let filter = {};
    if (status) filter.status = status;
    if (vehicleId) filter.vehicleId = vehicleId;
    if (maintenanceType) filter.maintenanceType = maintenanceType;

    const reports = await req.db.collection('maintenance_reports')
      .find(filter)
      .sort({ completedDate: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();

    const total = await req.db.collection('maintenance_reports').countDocuments(filter);

    res.json({
      success: true,
      data: reports,
      pagination: {
        current: parseInt(page),
        pages: Math.ceil(total / parseInt(limit)),
        total,
        limit: parseInt(limit)
      }
    });

  } catch (error) {
    console.error('Get maintenance reports error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while fetching maintenance reports'
    });
  }
});

// @route   PUT /api/maintenance/reports/:id
// @desc    Update a maintenance report
// @access  Private (Admin)
router.put('/reports/:id', [
  param('id').isMongoId().withMessage('Invalid report ID'),
  ...validateMaintenanceReport
], handleValidationErrors, async (req, res) => {
  try {
    const { ObjectId } = require('mongodb');
    const reportId = new ObjectId(req.params.id);

    // Check if report exists
    const existingReport = await req.db.collection('maintenance_reports').findOne({
      _id: reportId
    });

    if (!existingReport) {
      return res.status(404).json({
        success: false,
        message: 'Maintenance report not found'
      });
    }

    // Prepare update data
    const updateData = {
      ...req.body,
      completedDate: new Date(req.body.completedDate),
      actualCost: parseFloat(req.body.actualCost),
      nextMaintenanceDue: req.body.nextMaintenanceDue ? new Date(req.body.nextMaintenanceDue) : null,
      updatedAt: new Date(),
      updatedBy: { email: req.user?.uid || 'system',
        email: req.user?.email || 'system',
        name: req.user?.name || req.user?.email || 'System'
       }
    };

    const result = await req.db.collection('maintenance_reports').updateOne(
      { _id: reportId },
      { $set: updateData }
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Maintenance report not found'
      });
    }

    // Get updated report
    const updatedReport = await req.db.collection('maintenance_reports').findOne({
      _id: reportId
    });

    res.json({
      success: true,
      message: 'Maintenance report updated successfully',
      data: updatedReport
    });

  } catch (error) {
    console.error('Update maintenance report error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while updating maintenance report'
    });
  }
});

// @route   DELETE /api/maintenance/reports/:id
// @desc    Delete a maintenance report
// @access  Private (Admin)
router.delete('/reports/:id', [
  param('id').isMongoId().withMessage('Invalid report ID')
], async (req, res) => {
  try {
    const { ObjectId } = require('mongodb');
    const reportId = new ObjectId(req.params.id);

    const result = await req.db.collection('maintenance_reports').deleteOne({
      _id: reportId
    });

    if (result.deletedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Maintenance report not found'
      });
    }

    res.json({
      success: true,
      message: 'Maintenance report deleted successfully'
    });

  } catch (error) {
    console.error('Delete maintenance report error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while deleting maintenance report'
    });
  }
});

// @route   GET /api/maintenance/analytics
// @desc    Get maintenance analytics and statistics
// @access  Private (Admin)
router.get('/analytics', async (req, res) => {
  try {
    const { timeframe = '30d' } = req.query;
    
    // Calculate date range
    const endDate = new Date();
    const startDate = new Date();
    
    switch (timeframe) {
      case '7d':
        startDate.setDate(endDate.getDate() - 7);
        break;
      case '30d':
        startDate.setDate(endDate.getDate() - 30);
        break;
      case '90d':
        startDate.setDate(endDate.getDate() - 90);
        break;
      case '1y':
        startDate.setFullYear(endDate.getFullYear() - 1);
        break;
      default:
        startDate.setDate(endDate.getDate() - 30);
    }

    // Get maintenance statistics
    const [
      totalReports,
      completedReports,
      pendingReports,
      totalCost,
      maintenanceByType,
      maintenanceByVendor,
      monthlyTrend
    ] = await Promise.all([
      // Total reports
      req.db.collection('maintenance_reports').countDocuments({
        completedDate: { $gte: startDate, $lte: endDate }
      }),
      
      // Completed reports
      req.db.collection('maintenance_reports').countDocuments({
        completedDate: { $gte: startDate, $lte: endDate },
        status: 'completed'
      }),
      
      // Pending reports
      req.db.collection('maintenance_reports').countDocuments({
        status: { $in: ['pending', 'in_progress'] }
      }),
      
      // Total cost
      req.db.collection('maintenance_reports').aggregate([
        {
          $match: {
            completedDate: { $gte: startDate, $lte: endDate },
            status: 'completed'
          }
        },
        {
          $group: {
            _id: null,
            totalCost: { $sum: '$actualCost' }
          }
        }
      ]).toArray(),
      
      // Maintenance by type
      req.db.collection('maintenance_reports').aggregate([
        {
          $match: {
            completedDate: { $gte: startDate, $lte: endDate }
          }
        },
        {
          $group: {
            _id: '$maintenanceType',
            count: { $sum: 1 },
            totalCost: { $sum: '$actualCost' }
          }
        },
        { $sort: { count: -1 } }
      ]).toArray(),
      
      // Maintenance by vendor
      req.db.collection('maintenance_reports').aggregate([
        {
          $match: {
            completedDate: { $gte: startDate, $lte: endDate }
          }
        },
        {
          $group: {
            _id: '$vendorName',
            count: { $sum: 1 },
            totalCost: { $sum: '$actualCost' }
          }
        },
        { $sort: { count: -1 } },
        { $limit: 10 }
      ]).toArray(),
      
      // Monthly trend
      req.db.collection('maintenance_reports').aggregate([
        {
          $match: {
            completedDate: { $gte: startDate, $lte: endDate }
          }
        },
        {
          $group: {
            _id: {
              year: { $year: '$completedDate' },
              month: { $month: '$completedDate' }
            },
            count: { $sum: 1 },
            totalCost: { $sum: '$actualCost' }
          }
        },
        { $sort: { '_id.year': 1, '_id.month': 1 } }
      ]).toArray()
    ]);

    res.json({
      success: true,
      data: {
        timeframe,
        period: { startDate, endDate },
        overview: {
          totalReports,
          completedReports,
          pendingReports,
          totalCost: totalCost[0]?.totalCost || 0,
          averageCost: completedReports > 0 ? (totalCost[0]?.totalCost || 0) / completedReports : 0
        },
        breakdowns: {
          byType: maintenanceByType,
          byVendor: maintenanceByVendor
        },
        trends: {
          monthly: monthlyTrend
        }
      }
    });

  } catch (error) {
    console.error('Maintenance analytics error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while fetching maintenance analytics'
    });
  }
});

module.exports = router;