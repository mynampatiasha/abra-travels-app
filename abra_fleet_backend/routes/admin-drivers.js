// routes/admin-drivers.js
// COMPLETE FILE - CHUNK 1 of 3
// ============================================================================
// ADMIN DRIVER MANAGEMENT - COMPLETE BACKEND
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { createNotification } = require('../models/notification_model');
const emailService = require('../services/email_service');
const { getDriverWelcomeTemplate, getDriverWelcomeText } = require('../services/email_templates');
const bcrypt = require('bcrypt');
const multer = require('multer');
const path = require('path');
const fs = require('fs').promises;

// Configure multer for document uploads
const storage = multer.diskStorage({
  destination: async (req, file, cb) => {
    const uploadDir = path.join(__dirname, '../uploads/driver-documents');
    try {
      await fs.mkdir(uploadDir, { recursive: true });
      cb(null, uploadDir);
    } catch (error) {
      cb(error, null);
    }
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, file.fieldname + '-' + uniqueSuffix + path.extname(file.originalname));
  }
});

const upload = multer({
  storage: storage,
  limits: {
    fileSize: 10 * 1024 * 1024 // 10MB limit
  },
  fileFilter: (req, file, cb) => {
    // Allow common document and image file extensions
    const allowedExtensions = /jpeg|jpg|png|pdf|doc|docx/;
    const extname = allowedExtensions.test(path.extname(file.originalname).toLowerCase());
    
    // Allow common MIME types for documents and images
    const allowedMimeTypes = [
      'image/jpeg',
      'image/jpg', 
      'image/png',
      'application/pdf',
      'application/msword', // .doc
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document', // .docx
      'application/octet-stream' // Generic binary - some browsers use this
    ];
    
    const mimetypeAllowed = allowedMimeTypes.includes(file.mimetype);

    console.log('📄 File upload validation:');
    console.log('   - Filename:', file.originalname);
    console.log('   - MIME type:', file.mimetype);
    console.log('   - Extension valid:', extname);
    console.log('   - MIME type valid:', mimetypeAllowed);

    if (mimetypeAllowed && extname) {
      return cb(null, true);
    } else {
      console.log('❌ File rejected - Invalid type');
      cb(new Error('Invalid file type. Only JPEG, PNG, PDF, DOC, and DOCX files are allowed.'));
    }
  }
});

// ============================================================================
// @route   GET /api/admin/drivers/profile
// @desc    Get current driver's profile (for authenticated drivers)
// @access  Private (Driver)
// ============================================================================
router.get('/profile', async (req, res) => {
  try {
    console.log('🔍 Driver profile request received');
    console.log('   - User:', req.user);
    console.log('   - Headers:', req.headers.authorization ? 'Authorization header present' : 'No auth header');
    
    const user = req.user;
    if (!user) {
      console.log('❌ No authenticated user found');
      return res.status(401).json({
        success: false,
        message: 'Authentication required'
      });
    }
    
    console.log('✅ Authenticated user found:', user.userId);
    console.log('   - Email:', user.email);
    console.log('   - Role:', user.role);
    console.log('   - Driver ID from token:', user.driverId);
    
    let driver = await req.db.collection('drivers').findOne({
      $or: [
        { _id: new ObjectId(user.userId) },
        { driverId: user.driverId },
        { firebaseUid: user.userId },
        { uid: user.userId },
        { 'personalInfo.email': user.email }
      ]
    });
    
    if (!driver) {
      console.log('❌ Driver not found in drivers collection');
      return res.status(404).json({
        success: false,
        message: 'Driver profile not found'
      });
    }
    
    console.log('✅ Driver found:', driver.driverId);
    
    let assignedVehicle = null;
    if (driver.assignedVehicle) {
      assignedVehicle = await req.db.collection('vehicles').findOne(
        { vehicleId: driver.assignedVehicle },
        { 
          projection: { 
            vehicleId: 1, 
            registrationNumber: 1, 
            make: 1, 
            model: 1,
            type: 1,
            status: 1
          } 
        }
      );
      console.log('✅ Assigned vehicle found:', assignedVehicle?.vehicleId);
    }
    
    const recentTrips = await req.db.collection('trips')
      .find({ driverId: driver.driverId })
      .sort({ startTime: -1 })
      .limit(5)
      .toArray();
    
    const totalTrips = await req.db.collection('trips')
      .countDocuments({ driverId: driver.driverId });
    
    const completedTrips = await req.db.collection('trips')
      .countDocuments({ 
        driverId: driver.driverId, 
        status: 'completed' 
      });
    
    const profileData = {
      _id: driver._id,
      firebaseUid: driver.firebaseUid || driver.uid,
      name: `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim(),
      email: driver.personalInfo?.email,
      phoneNumber: driver.personalInfo?.phone,
      role: 'driver',
      status: driver.status || 'active',
      driverId: driver.driverId,
      personalInfo: driver.personalInfo,
      license: driver.license,
      emergencyContact: driver.emergencyContact,
      address: driver.address,
      assignedVehicle,
      stats: {
        totalTrips,
        completedTrips,
        completionRate: totalTrips > 0 ? Math.round((completedTrips / totalTrips) * 100) : 0
      },
      recentTrips,
      joinedDate: driver.joinedDate || driver.createdAt,
      createdAt: driver.createdAt,
      updatedAt: driver.updatedAt
    };
    
    console.log('✅ Profile data prepared successfully');
    
    res.json({
      success: true,
      data: profileData
    });
  } catch (error) {
    console.error('❌ Error fetching driver profile:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch driver profile',
      error: error.message
    });
  }
});

// ============================================================================
// @route   PUT /api/admin/drivers/profile
// @desc    Update current driver's profile
// @access  Private (Driver)
// ============================================================================
router.put('/profile', async (req, res) => {
  try {
    const user = req.user;
    if (!user) {
      return res.status(401).json({
        success: false,
        message: 'Authentication required'
      });
    }

    const driver = await req.db.collection('drivers').findOne({
      $or: [
        { _id: new ObjectId(user.userId) },
        { driverId: user.driverId },
        { 'personalInfo.email': user.email }
      ]
    });

    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }

    const updateOperations = {
      $set: {
        updatedAt: new Date()
      }
    };

    // Update allowed fields only
    if (req.body.personalInfo) {
      const allowedPersonalFields = ['phone', 'bloodGroup', 'dateOfBirth'];
      Object.keys(req.body.personalInfo).forEach(key => {
        if (allowedPersonalFields.includes(key)) {
          updateOperations.$set[`personalInfo.${key}`] = req.body.personalInfo[key];
        }
      });
    }

    if (req.body.address) {
      Object.keys(req.body.address).forEach(key => {
        updateOperations.$set[`address.${key}`] = req.body.address[key];
      });
    }

    if (req.body.emergencyContact) {
      Object.keys(req.body.emergencyContact).forEach(key => {
        updateOperations.$set[`emergencyContact.${key}`] = req.body.emergencyContact[key];
      });
    }

    const result = await req.db.collection('drivers').updateOne(
      { _id: driver._id },
      updateOperations
    );

    if (result.modifiedCount === 0) {
      return res.status(400).json({
        success: false,
        message: 'No changes were made'
      });
    }

    const updatedDriver = await req.db.collection('drivers').findOne({ _id: driver._id });

    res.json({
      success: true,
      message: 'Profile updated successfully',
      data: updatedDriver
    });
  } catch (error) {
    console.error('❌ Error updating driver profile:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update profile',
      error: error.message
    });
  }
});

// ============================================================================
// @route   PUT /api/admin/drivers/profile/:id
// @desc    Update driver profile by ID
// @access  Private (Driver)
// ============================================================================
router.put('/profile/:id', async (req, res) => {
  try {
    console.log('🔄 Driver profile update request received for ID:', req.params.id);
    console.log('   - Request body:', req.body);
    
    const user = req.user;
    if (!user) {
      console.log('❌ No authenticated user found');
      return res.status(401).json({
        success: false,
        message: 'Authentication required'
      });
    }

    // Find the driver by ID
    const driverId = req.params.id;
    let driver = null;

    // Try to find by ObjectId or driverId
    if (ObjectId.isValid(driverId)) {
      driver = await req.db.collection('drivers').findOne({
        $or: [
          { _id: new ObjectId(driverId) },
          { driverId: driverId }
        ]
      });
    } else {
      driver = await req.db.collection('drivers').findOne({ driverId: driverId });
    }

    if (!driver) {
      console.log('❌ Driver not found with ID:', driverId);
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }

    console.log('✅ Driver found:', driver.driverId);

    // Build update operations
    const updateOperations = {
      $set: {
        updatedAt: new Date()
      }
    };

    // Update name fields
    if (req.body.name) {
      const nameParts = req.body.name.trim().split(' ');
      updateOperations.$set['personalInfo.firstName'] = nameParts[0] || '';
      updateOperations.$set['personalInfo.lastName'] = nameParts.slice(1).join(' ') || '';
    }

    // Update email
    if (req.body.email) {
      updateOperations.$set['personalInfo.email'] = req.body.email;
    }

    // Update phone
    if (req.body.phoneNumber) {
      updateOperations.$set['personalInfo.phone'] = req.body.phoneNumber;
    }

    // Update personal info fields
    if (req.body.personalInfo) {
      Object.keys(req.body.personalInfo).forEach(key => {
        updateOperations.$set[`personalInfo.${key}`] = req.body.personalInfo[key];
      });
    }

    // Update address
    if (req.body.address) {
      Object.keys(req.body.address).forEach(key => {
        updateOperations.$set[`address.${key}`] = req.body.address[key];
      });
    }

    // Update emergency contact
    if (req.body.emergencyContact) {
      Object.keys(req.body.emergencyContact).forEach(key => {
        updateOperations.$set[`emergencyContact.${key}`] = req.body.emergencyContact[key];
      });
    }

    console.log('📝 Update operations:', JSON.stringify(updateOperations, null, 2));

    // Perform the update
    const result = await req.db.collection('drivers').updateOne(
      { _id: driver._id },
      updateOperations
    );

    console.log('✅ Update result:', result);

    if (result.modifiedCount === 0) {
      console.log('⚠️ No changes were made');
      return res.status(400).json({
        success: false,
        message: 'No changes were made'
      });
    }

    // Fetch the updated driver
    const updatedDriver = await req.db.collection('drivers').findOne({ _id: driver._id });

    console.log('✅ Profile updated successfully');

    res.json({
      success: true,
      message: 'Profile updated successfully',
      data: updatedDriver
    });
  } catch (error) {
    console.error('❌ Error updating driver profile:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update profile',
      error: error.message
    });
  }
});

// ============================================================================
// @route   PUT /api/admin/drivers/profile/:id
// @desc    Update driver profile by ID
// @access  Private (Driver)
// ============================================================================
router.put('/profile/:id', async (req, res) => {
  try {
    console.log('🔄 PUT /api/drivers/profile/:id - Update driver profile');
    console.log('   - Driver ID:', req.params.id);
    console.log('   - Request body:', req.body);

    const user = req.user;
    if (!user) {
      return res.status(401).json({
        success: false,
        message: 'Authentication required'
      });
    }

    // Find driver by ID
    let driverQuery = {};
    if (ObjectId.isValid(req.params.id)) {
      driverQuery = { _id: new ObjectId(req.params.id) };
    } else {
      driverQuery = { driverId: req.params.id };
    }

    const driver = await req.db.collection('drivers').findOne(driverQuery);

    if (!driver) {
      console.log('❌ Driver not found');
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }

    console.log('✅ Driver found:', driver.driverId);

    const updateOperations = {
      $set: {
        updatedAt: new Date()
      }
    };

    // Update name fields
    if (req.body.name) {
      const nameParts = req.body.name.trim().split(' ');
      updateOperations.$set['personalInfo.firstName'] = nameParts[0] || '';
      updateOperations.$set['personalInfo.lastName'] = nameParts.slice(1).join(' ') || '';
    }

    // Update email
    if (req.body.email) {
      updateOperations.$set['personalInfo.email'] = req.body.email;
    }

    // Update phone
    if (req.body.phoneNumber) {
      updateOperations.$set['personalInfo.phone'] = req.body.phoneNumber;
    }

    // Update personal info fields
    if (req.body.personalInfo) {
      Object.keys(req.body.personalInfo).forEach(key => {
        updateOperations.$set[`personalInfo.${key}`] = req.body.personalInfo[key];
      });
    }

    // Update address
    if (req.body.address) {
      Object.keys(req.body.address).forEach(key => {
        updateOperations.$set[`address.${key}`] = req.body.address[key];
      });
    }

    // Update emergency contact
    if (req.body.emergencyContact) {
      Object.keys(req.body.emergencyContact).forEach(key => {
        updateOperations.$set[`emergencyContact.${key}`] = req.body.emergencyContact[key];
      });
    }

    console.log('📝 Update operations:', JSON.stringify(updateOperations, null, 2));

    const result = await req.db.collection('drivers').updateOne(
      { _id: driver._id },
      updateOperations
    );

    if (result.modifiedCount === 0) {
      console.log('⚠️ No changes were made');
      return res.status(400).json({
        success: false,
        message: 'No changes were made'
      });
    }

    const updatedDriver = await req.db.collection('drivers').findOne({ _id: driver._id });

    console.log('✅ Profile updated successfully');

    res.json({
      success: true,
      message: 'Profile updated successfully',
      data: updatedDriver
    });
  } catch (error) {
    console.error('❌ Error updating driver profile:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update profile',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/drivers
// @desc    Get all drivers with optional filters
// @access  Private (Admin)
// ============================================================================
// ============================================================================
// @route   GET /api/admin/drivers
// @desc    Get all drivers with optional filters
// @access  Private (Admin)
// ============================================================================
// ============================================================================
// @route   GET /api/admin/drivers
// @desc    Get all drivers with optional filters
// @access  Private (Admin)
// ============================================================================
router.get('/', async (req, res) => {
  try {
    const { status, page = 1, limit = 20, search, fullDetails } = req.query;
    
    console.log(`📡 GET /api/admin/drivers - page=${page}, limit=${limit}, fullDetails=${fullDetails}`);
    const startTime = Date.now();
    
    let filter = {};
    // ✅ FIX: Default to active drivers only (exclude soft-deleted drivers)
    if (status && status !== 'All') {
      filter.status = status;
    } else {
      // No status specified - default to active drivers only
      filter.status = 'active';
    }
    // If status === 'All', no filter is applied (shows all including inactive)
    
    console.log(`   Filter applied: ${JSON.stringify(filter)}`);
    
    if (search) {
      filter.$or = [
        { driverId: { $regex: search, $options: 'i' } },
        { 'personalInfo.phone': { $regex: search, $options: 'i' } },
        { 'personalInfo.email': { $regex: search, $options: 'i' } },
        { 'personalInfo.firstName': { $regex: search, $options: 'i' } },
        { 'personalInfo.lastName': { $regex: search, $options: 'i' } }
      ];
    }
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const drivers = await req.db.collection('drivers').aggregate([
      { $match: filter },
      { $sort: { createdAt: -1 } },
      { $skip: skip },
      { $limit: parseInt(limit) },
      {
        $lookup: {
          from: 'vehicles',
          localField: 'assignedVehicle',
          foreignField: '_id',
          as: 'vehicleData'
        }
      },
      {
        $project: {
          _id: 1,
          driverId: 1,
          firebaseUid: 1,
          name: {
            $concat: [
              { $ifNull: ['$personalInfo.firstName', ''] },
              ' ',
              { $ifNull: ['$personalInfo.lastName', ''] }
            ]
          },
          email: '$personalInfo.email',
          phone: '$personalInfo.phone',
          status: 1,
          personalInfo: 1,
          license: 1,
          emergencyContact: 1,
          address: 1,
          employment: 1,
          bankDetails: 1,
          documents: { $ifNull: ['$documents', []] },
          vehicleData: 1,
          assignedVehicle: 1,
          vehicleNumber: 1,
          joinedDate: { $ifNull: ['$joinedDate', '$createdAt'] },
          createdAt: 1,
          updatedAt: 1,
          rating: 1,
          feedbackStats: 1
        }
      }
    ]).toArray();
    
    const totalCount = await req.db.collection('drivers').countDocuments(filter);
    
    console.log(`✅ Fetched ${drivers.length} drivers in ${Date.now() - startTime}ms`);
    
    if (fullDetails === 'true') {
      console.log('📊 fullDetails=true: Adding trip statistics and feedback...');
      
      const driversWithFullDetails = await Promise.all(
        drivers.map(async (driver) => {
          // ✅ FIX: Count trips from BOTH collections
          const tripsCount = await req.db.collection('trips')
            .countDocuments({ driverId: driver.driverId });
          
          const rosterTripsCount = await req.db.collection('roster-assigned-trips')
            .countDocuments({ driverId: driver._id });
          
          const totalTrips = tripsCount + rosterTripsCount;
          
          const completedTrips = await req.db.collection('trips')
            .countDocuments({ driverId: driver.driverId, status: 'completed' });
          
          const completedRosterTrips = await req.db.collection('roster-assigned-trips')
            .countDocuments({ driverId: driver._id, status: { $in: ['completed', 'done', 'finished'] } });
          
          const totalCompletedTrips = completedTrips + completedRosterTrips;

          // Fetch feedback
          const feedbackAgg = await req.db.collection('driver_feedback').aggregate([
            { 
              $match: { 
                driverId: driver._id,
                feedbackType: 'driver_trip_feedback'
              } 
            },
            {
              $group: {
                _id: null,
                averageRating: { $avg: '$rating' },
                totalFeedback: { $sum: 1 },
                rating5Stars: { $sum: { $cond: [{ $eq: ['$rating', 5] }, 1, 0] } },
                rating4Stars: { $sum: { $cond: [{ $eq: ['$rating', 4] }, 1, 0] } },
                rating3Stars: { $sum: { $cond: [{ $eq: ['$rating', 3] }, 1, 0] } },
                rating2Stars: { $sum: { $cond: [{ $eq: ['$rating', 2] }, 1, 0] } },
                rating1Stars: { $sum: { $cond: [{ $eq: ['$rating', 1] }, 1, 0] } }
              }
            }
          ]).toArray();

          const feedbackData = feedbackAgg[0] || { 
            averageRating: 0, 
            totalFeedback: 0,
            rating5Stars: 0,
            rating4Stars: 0,
            rating3Stars: 0,
            rating2Stars: 0,
            rating1Stars: 0
          };

          const vehicleObj = Array.isArray(driver.vehicleData) && driver.vehicleData.length > 0
            ? driver.vehicleData[0]
            : (driver.assignedVehicle && typeof driver.assignedVehicle === 'object' ? driver.assignedVehicle : null);

          const vehicleDisplay = vehicleObj
            ? (vehicleObj.registrationNumber || vehicleObj.vehicleNumber || vehicleObj.vehicleId || null)
            : (driver.vehicleNumber || null);

          let licenseExpiry = null;
          if (driver.license?.expiryDate) {
            try {
              licenseExpiry = new Date(driver.license.expiryDate).toISOString().split('T')[0];
            } catch(e) { 
              licenseExpiry = driver.license.expiryDate; 
            }
          }

          return {
            ...driver,
            assignedVehicle: vehicleObj || null,
            vehicleNumber: vehicleDisplay,
            totalTrips: totalTrips,  // ✅ FIXED
            completedTrips: totalCompletedTrips,  // ✅ FIXED
            licenseNumber: driver.license?.licenseNumber,
            licenseExpiry: licenseExpiry,
            rating: feedbackData.averageRating > 0 ? Math.round(feedbackData.averageRating * 10) / 10 : (driver.rating ?? driver.feedbackStats?.averageRating ?? null),
            feedbackStats: {
              totalFeedback: feedbackData.totalFeedback,
              averageRating: feedbackData.averageRating > 0 ? Math.round(feedbackData.averageRating * 10) / 10 : 0,
              rating5Stars: feedbackData.rating5Stars,
              rating4Stars: feedbackData.rating4Stars,
              rating3Stars: feedbackData.rating3Stars,
              rating2Stars: feedbackData.rating2Stars,
              rating1Stars: feedbackData.rating1Stars,
              ...(driver.feedbackStats || {})
            }
          };
        })
      );
      
      console.log(`✅ Full details complete in ${Date.now() - startTime}ms`);
      
      return res.json({
        success: true,
        data: driversWithFullDetails,
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total: totalCount,
          pages: Math.ceil(totalCount / parseInt(limit))
        },
        summary: {
          total: totalCount,
          active: await req.db.collection('drivers').countDocuments({ status: 'active' }),
          onLeave: await req.db.collection('drivers').countDocuments({ status: 'on_leave' }),
          inactive: await req.db.collection('drivers').countDocuments({ status: 'inactive' })
        }
      });
    }
    
    // ✅ DEFAULT RESPONSE WITH TRIP COUNTS
    const driversFormatted = await Promise.all(drivers.map(async (driver) => {
      // ✅ FIX: Count trips from BOTH collections
      const tripsCount = await req.db.collection('trips')
        .countDocuments({ driverId: driver.driverId });
      
      const rosterTripsCount = await req.db.collection('roster-assigned-trips')
        .countDocuments({ driverId: driver._id });
      
      const totalTrips = tripsCount + rosterTripsCount;
      
      const completedTrips = await req.db.collection('trips')
        .countDocuments({ driverId: driver.driverId, status: 'completed' });
      
      const completedRosterTrips = await req.db.collection('roster-assigned-trips')
        .countDocuments({ driverId: driver._id, status: { $in: ['completed', 'done', 'finished'] } });
      
      const totalCompletedTrips = completedTrips + completedRosterTrips;

      // Fetch feedback
      const feedbackAgg = await req.db.collection('driver_feedback').aggregate([
        { 
          $match: { 
            driverId: driver._id,
            feedbackType: 'driver_trip_feedback'
          } 
        },
        {
          $group: {
            _id: null,
            averageRating: { $avg: '$rating' },
            totalFeedback: { $sum: 1 }
          }
        }
      ]).toArray();

      const feedbackData = feedbackAgg[0] || { averageRating: 0, totalFeedback: 0 };

      const vehicleObj = Array.isArray(driver.vehicleData) && driver.vehicleData.length > 0
        ? driver.vehicleData[0]
        : (driver.assignedVehicle && typeof driver.assignedVehicle === 'object' ? driver.assignedVehicle : null);

      const vehicleDisplay = vehicleObj
        ? (vehicleObj.registrationNumber || vehicleObj.vehicleNumber || vehicleObj.vehicleId || null)
        : (driver.vehicleNumber || null);

      let licenseExpiry = null;
      if (driver.license?.expiryDate) {
        try {
          licenseExpiry = new Date(driver.license.expiryDate).toISOString().split('T')[0];
        } catch (e) {
          licenseExpiry = driver.license.expiryDate;
        }
      }

      return {
        _id: driver._id?.toString(),
        driverId: driver.driverId,
        name: driver.name || `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim() || 'N/A',
        phone: driver.phone || driver.personalInfo?.phone || 'N/A',
        email: driver.email || driver.personalInfo?.email || 'N/A',
        status: driver.status,
        assignedVehicle: vehicleObj || null,
        vehicleNumber: vehicleDisplay,
        documents: driver.documents || [],
        licenseNumber: driver.license?.licenseNumber || 'N/A',
        licenseExpiry: licenseExpiry,
        joinedDate: driver.joinedDate,
        rating: feedbackData.averageRating > 0 ? Math.round(feedbackData.averageRating * 10) / 10 : (driver.rating ?? driver.feedbackStats?.averageRating ?? null),
        feedbackStats: {
          totalFeedback: feedbackData.totalFeedback,
          averageRating: feedbackData.averageRating > 0 ? Math.round(feedbackData.averageRating * 10) / 10 : 0,
          ...(driver.feedbackStats || {})
        },
        totalTrips: totalTrips,  // ✅ FIXED
        completedTrips: totalCompletedTrips,  // ✅ FIXED
      };
    }));
    
    console.log(`✅ Response ready in ${Date.now() - startTime}ms`);
    
    res.json({
      success: true,
      data: driversFormatted,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalCount,
        pages: Math.ceil(totalCount / parseInt(limit))
      },
      summary: {
        total: totalCount,
        active: await req.db.collection('drivers').countDocuments({ status: 'active' }),
        onLeave: await req.db.collection('drivers').countDocuments({ status: 'on_leave' }),
        inactive: await req.db.collection('drivers').countDocuments({ status: 'inactive' })
      }
    });
  } catch (error) {
    console.error('❌ Error fetching drivers:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch drivers',
      error: error.message
    });
  }
});

// CONTINUES IN CHUNK 2...
// CHUNK 2 of 3: GET BY ID, CREATE, UPDATE, DELETE, STATISTICS

// ============================================================================
// @route   GET /api/admin/drivers/stats
// @desc    Get driver statistics (alias for /statistics)
// @access  Private (Admin)
// ============================================================================
router.get('/stats', async (req, res) => {
  try {
    console.log('\n📊 Fetching driver stats...');
    
    const totalDrivers = await req.db.collection('drivers').countDocuments();
    const activeDrivers = await req.db.collection('drivers').countDocuments({ status: 'active' });
    const onLeaveDrivers = await req.db.collection('drivers').countDocuments({ status: 'on_leave' });
    const inactiveDrivers = await req.db.collection('drivers').countDocuments({ status: 'inactive' });
    
    const stats = {
      total: totalDrivers,
      active: activeDrivers,
      onLeave: onLeaveDrivers,
      inactive: inactiveDrivers
    };
    
    console.log('✅ Stats compiled successfully:', stats);
    
    res.json({
      success: true,
      data: stats
    });
  } catch (error) {
    console.error('❌ Error fetching stats:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch stats',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/drivers/statistics
// @desc    Get driver statistics and analytics
// @access  Private (Admin)
// ============================================================================
router.get('/statistics', async (req, res) => {
  try {
    console.log('\n📊 Fetching driver statistics...');
    
    const totalDrivers = await req.db.collection('drivers').countDocuments();
    const activeDrivers = await req.db.collection('drivers').countDocuments({ status: 'active' });
    const onLeaveDrivers = await req.db.collection('drivers').countDocuments({ status: 'on_leave' });
    const inactiveDrivers = await req.db.collection('drivers').countDocuments({ status: 'inactive' });
    
    // Drivers with assigned vehicles
    const driversWithVehicles = await req.db.collection('drivers').countDocuments({
      assignedVehicle: { $ne: null }
    });
    
    // Drivers without vehicles
    const driversWithoutVehicles = totalDrivers - driversWithVehicles;
    
    // Get top rated drivers
    const topRatedDrivers = await req.db.collection('drivers').find({
      'feedbackStats.averageRating': { $gte: 4.5 },
      'feedbackStats.totalFeedback': { $gte: 5 }
    })
    .sort({ 'feedbackStats.averageRating': -1 })
    .limit(10)
    .project({
      driverId: 1,
      'personalInfo.firstName': 1,
      'personalInfo.lastName': 1,
      name: 1,
      'feedbackStats.averageRating': 1,
      'feedbackStats.totalFeedback': 1
    })
    .toArray();
    
    // Drivers with expiring licenses (within 30 days)
    const thirtyDaysFromNow = new Date();
    thirtyDaysFromNow.setDate(thirtyDaysFromNow.getDate() + 30);
    
    const expiringLicenses = await req.db.collection('drivers').countDocuments({
      'license.expiryDate': {
        $gte: new Date(),
        $lte: thirtyDaysFromNow
      }
    });
    
    // Expired licenses
    const expiredLicenses = await req.db.collection('drivers').countDocuments({
      'license.expiryDate': { $lt: new Date() }
    });
    
    // Recent hires (last 30 days)
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
    
    const recentHires = await req.db.collection('drivers').countDocuments({
      createdAt: { $gte: thirtyDaysAgo }
    });
    
    // Average rating across all drivers
    const ratingStats = await req.db.collection('drivers').aggregate([
      {
        $match: {
          'feedbackStats.averageRating': { $exists: true, $ne: null }
        }
      },
      {
        $group: {
          _id: null,
          avgRating: { $avg: '$feedbackStats.averageRating' },
          totalDriversWithRating: { $sum: 1 }
        }
      }
    ]).toArray();
    
    const stats = {
      overview: {
        total: totalDrivers,
        active: activeDrivers,
        onLeave: onLeaveDrivers,
        inactive: inactiveDrivers,
        recentHires: recentHires
      },
      vehicles: {
        withVehicle: driversWithVehicles,
        withoutVehicle: driversWithoutVehicles,
        assignmentRate: totalDrivers > 0 ? Math.round((driversWithVehicles / totalDrivers) * 100) : 0
      },
      licenses: {
        expiringSoon: expiringLicenses,
        expired: expiredLicenses,
        valid: totalDrivers - expiringLicenses - expiredLicenses
      },
      performance: {
        averageRating: ratingStats.length > 0 ? Math.round(ratingStats[0].avgRating * 100) / 100 : 0,
        driversWithRatings: ratingStats.length > 0 ? ratingStats[0].totalDriversWithRating : 0,
        topRatedDrivers: topRatedDrivers.map(d => ({
          id: d._id.toString(),
          driverId: d.driverId,
          name: d.name || `${d.personalInfo?.firstName || ''} ${d.personalInfo?.lastName || ''}`.trim(),
          rating: d.feedbackStats?.averageRating || 0,
          totalFeedback: d.feedbackStats?.totalFeedback || 0
        }))
      }
    };
    
    console.log('✅ Statistics compiled successfully');
    
    res.json({
      success: true,
      data: stats
    });
  } catch (error) {
    console.error('❌ Error fetching statistics:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch statistics',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/drivers/:id
// @desc    Get driver by ID
// @access  Private (Admin)
// ============================================================================
// ============================================================================
// @route   GET /api/admin/drivers/:id
// @desc    Get comprehensive driver details for view dialog
// @access  Private (Admin)
// ============================================================================
// ============================================================================
// @route   GET /api/admin/drivers/:id
// @desc    Get comprehensive driver details for view dialog
// @access  Private (Admin)
// ============================================================================
router.get('/:id', async (req, res) => {
  try {
    const query = {};
    query.driverId = req.params.id;
    
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      query.$or = [
        { driverId: req.params.id },
        { _id: new ObjectId(req.params.id) }
      ];
    }
    
    const driver = await req.db.collection('drivers').findOne(query);
    
    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    // Get assigned vehicle details
    let assignedVehicle = null;
    if (driver.assignedVehicle) {
      const vehicleQuery = { 
        $or: [
          { _id: driver.assignedVehicle },
          { _id: ObjectId.isValid(driver.assignedVehicle?.toString()) ? new ObjectId(driver.assignedVehicle.toString()) : null },
          { vehicleId: driver.assignedVehicle?.toString() },
          { vehicleNumber: driver.assignedVehicle?.toString() },
          { registrationNumber: driver.assignedVehicle?.toString() },
        ]
      };
      assignedVehicle = await req.db.collection('vehicles').findOne(
        vehicleQuery,
        { projection: { vehicleId: 1, registrationNumber: 1, vehicleNumber: 1, make: 1, model: 1, type: 1, status: 1, capacity: 1 } }
      );
    }
    
    // ✅ Get trip history from BOTH collections
    const trips = await req.db.collection('trips')
      .find({ driverId: driver.driverId })
      .sort({ startTime: -1 })
      .limit(10)
      .toArray();
    
    const rosterTrips = await req.db.collection('roster-assigned-trips')
      .find({ driverId: driver._id })
      .sort({ scheduledDate: -1 })
      .limit(10)
      .toArray();
    
    // Combine and sort all trips
    const allRecentTrips = [...trips, ...rosterTrips]
      .sort((a, b) => {
        const dateA = new Date(a.startTime || a.scheduledDate);
        const dateB = new Date(b.startTime || b.scheduledDate);
        return dateB - dateA;
      })
      .slice(0, 10);
    
    // Get performance metrics
    const totalTrips = await req.db.collection('trips')
      .countDocuments({ driverId: driver.driverId });
    
    const totalRosterTrips = await req.db.collection('roster-assigned-trips')
      .countDocuments({ driverId: driver._id });
    
    const completedTrips = await req.db.collection('trips')
      .countDocuments({ 
        driverId: driver.driverId, 
        status: 'completed' 
      });
    
    const completedRosterTrips = await req.db.collection('roster-assigned-trips')
      .countDocuments({ 
        driverId: driver._id, 
        status: { $in: ['completed', 'done', 'finished'] }
      });
    
    const totalAllTrips = totalTrips + totalRosterTrips;
    const totalAllCompleted = completedTrips + completedRosterTrips;
    
    // Get feedback stats
    const feedbackAgg = await req.db.collection('driver_feedback').aggregate([
      { 
        $match: { 
          driverId: driver._id,
          feedbackType: 'driver_trip_feedback'
        } 
      },
      {
        $group: {
          _id: null,
          averageRating: { $avg: '$rating' },
          totalFeedback: { $sum: 1 },
          rating5Stars: { $sum: { $cond: [{ $eq: ['$rating', 5] }, 1, 0] } },
          rating4Stars: { $sum: { $cond: [{ $eq: ['$rating', 4] }, 1, 0] } },
          rating3Stars: { $sum: { $cond: [{ $eq: ['$rating', 3] }, 1, 0] } },
          rating2Stars: { $sum: { $cond: [{ $eq: ['$rating', 2] }, 1, 0] } },
          rating1Stars: { $sum: { $cond: [{ $eq: ['$rating', 1] }, 1, 0] } }
        }
      }
    ]).toArray();

    const feedbackData = feedbackAgg[0] || { 
      averageRating: 0, 
      totalFeedback: 0,
      rating5Stars: 0,
      rating4Stars: 0,
      rating3Stars: 0,
      rating2Stars: 0,
      rating1Stars: 0
    };
    
    // ✅ Build comprehensive response
    const response = {
      // Basic Info
      _id: driver._id,
      driverId: driver.driverId,
      firebaseUid: driver.firebaseUid || driver.uid,
      status: driver.status,
      
      // Personal Information
      personalInfo: {
        firstName: driver.personalInfo?.firstName || '',
        lastName: driver.personalInfo?.lastName || '',
        fullName: `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim(),
        email: driver.personalInfo?.email || '',
        phone: driver.personalInfo?.phone || '',
        dateOfBirth: driver.personalInfo?.dateOfBirth || null,
        gender: driver.personalInfo?.gender || null,
        bloodGroup: driver.personalInfo?.bloodGroup || null,
        nationality: driver.personalInfo?.nationality || null
      },
      
      // License Information
      license: {
        licenseNumber: driver.license?.licenseNumber || 'N/A',
        type: driver.license?.type || 'N/A',
        issueDate: driver.license?.issueDate || null,
        expiryDate: driver.license?.expiryDate || null,
        issuingAuthority: driver.license?.issuingAuthority || 'N/A',
        // ✅ Check if license is expired
        isExpired: driver.license?.expiryDate ? new Date(driver.license.expiryDate) < new Date() : false,
        // ✅ Check if expiring soon (within 30 days)
        isExpiringSoon: driver.license?.expiryDate ? 
          (new Date(driver.license.expiryDate) < new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) && 
           new Date(driver.license.expiryDate) >= new Date()) : false
      },
      
      // Emergency Contact
      emergencyContact: driver.emergencyContact || null,
      
      // Address
      address: driver.address || null,
      
      // Employment Details
      employment: driver.employment || null,
      
      // Bank Details
      bankDetails: driver.bankDetails || null,
      
      // Vehicle Assignment
      assignedVehicle: assignedVehicle ? {
        _id: assignedVehicle._id,
        vehicleId: assignedVehicle.vehicleId,
        vehicleNumber: assignedVehicle.vehicleNumber || assignedVehicle.registrationNumber,
        registrationNumber: assignedVehicle.registrationNumber,
        make: assignedVehicle.make,
        model: assignedVehicle.model,
        type: assignedVehicle.type,
        status: assignedVehicle.status,
        capacity: assignedVehicle.capacity
      } : null,
      
      // Documents
      documents: driver.documents || [],
      
      // Performance Stats
      stats: {
        totalTrips: totalAllTrips,
        completedTrips: totalAllCompleted,
        ongoingTrips: totalAllTrips - totalAllCompleted,
        completionRate: totalAllTrips > 0 ? Math.round((totalAllCompleted / totalAllTrips) * 100) : 0
      },
      
      // Feedback Stats
      feedbackStats: {
        averageRating: feedbackData.averageRating > 0 ? Math.round(feedbackData.averageRating * 10) / 10 : 0,
        totalFeedback: feedbackData.totalFeedback,
        rating5Stars: feedbackData.rating5Stars,
        rating4Stars: feedbackData.rating4Stars,
        rating3Stars: feedbackData.rating3Stars,
        rating2Stars: feedbackData.rating2Stars,
        rating1Stars: feedbackData.rating1Stars
      },
      
      // Recent Trips
      recentTrips: allRecentTrips.map(trip => ({
        tripId: trip._id,
        tripNumber: trip.tripNumber,
        scheduledDate: trip.scheduledDate || trip.startTime,
        status: trip.status,
        vehicleNumber: trip.vehicleNumber,
        totalStops: trip.stops?.length || 0,
        completedStops: trip.stops?.filter(s => s.status === 'completed').length || 0
      })),
      
      // Dates
      joinedDate: driver.joinedDate || driver.createdAt,
      createdAt: driver.createdAt,
      updatedAt: driver.updatedAt
    };
    
    res.json({
      success: true,
      data: response
    });
  } catch (error) {
    console.error('❌ Error fetching driver details:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch driver details',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/admin/drivers
// @desc    Create a new driver
// @access  Private (Admin)
// ============================================================================
router.post('/', async (req, res) => {
  try {
    console.log('\n🆕 Creating new driver...');
    console.log('Request body:', JSON.stringify(req.body, null, 2));
    
    const {
      personalInfo,
      license,
      emergencyContact,
      address,
      employment,
      bankDetails,
      password
    } = req.body;
    
    // Validation
    if (!personalInfo?.email || !personalInfo?.phone || !personalInfo?.firstName || !personalInfo?.lastName) {
      return res.status(400).json({
        success: false,
        message: 'Missing required personal information fields'
      });
    }
    
    // Check if driver already exists
    const existingDriver = await req.db.collection('drivers').findOne({
      $or: [
        { 'personalInfo.email': personalInfo.email },
        { 'personalInfo.phone': personalInfo.phone }
      ]
    });
    
    if (existingDriver) {
      return res.status(400).json({
        success: false,
        message: 'Driver with this email or phone already exists'
      });
    }
    
    // Generate driver ID
    const driverCount = await req.db.collection('drivers').countDocuments();
    const driverId = `DRV-${String(driverCount + 100001).padStart(6, '0')}`;
    
    // Hash password
    const hashedPassword = password ? await bcrypt.hash(password, 10) : null;
    
    const newDriver = {
      driverId,
      personalInfo: {
        firstName: personalInfo.firstName,
        lastName: personalInfo.lastName,
        email: personalInfo.email,
        phone: personalInfo.phone,
        dateOfBirth: personalInfo.dateOfBirth ? new Date(personalInfo.dateOfBirth) : null,
        gender: personalInfo.gender || null,
        bloodGroup: personalInfo.bloodGroup || null,
        nationality: personalInfo.nationality || null
      },
      license: license ? {
        licenseNumber: license.licenseNumber,
        type: license.type,
        issueDate: license.issueDate ? new Date(license.issueDate) : null,
        expiryDate: license.expiryDate ? new Date(license.expiryDate) : null,
        issuingAuthority: license.issuingAuthority || null
      } : null,
      emergencyContact: emergencyContact || null,
      address: address || null,
      employment: employment || null,
      bankDetails: bankDetails || null,
      password: hashedPassword,
      status: 'active',
      assignedVehicle: null,
      vehicleNumber: null,
      documents: [],
      feedbackStats: {
        totalFeedback: 0,
        averageRating: 0,
        rating5Stars: 0,
        rating4Stars: 0,
        rating3Stars: 0,
        rating2Stars: 0,
        rating1Stars: 0,
        totalRatingPoints: 0
      },
      rating: null,
      totalTrips: 0,
      completedTrips: 0,
      joinedDate: new Date(),
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    const result = await req.db.collection('drivers').insertOne(newDriver);
    
    console.log('✅ Driver created:', driverId);
    
    // Send welcome email
    if (personalInfo.email) {
      try {
        const emailHtml = getDriverWelcomeTemplate({
          name: `${personalInfo.firstName} ${personalInfo.lastName}`,
          email: personalInfo.email,
          driverId: driverId,
          tempPassword: password || 'Please contact admin for password'
        });
        
        const emailText = getDriverWelcomeText({
          name: `${personalInfo.firstName} ${personalInfo.lastName}`,
          email: personalInfo.email,
          driverId: driverId,
          tempPassword: password || 'Please contact admin for password'
        });
        
        await emailService.sendEmail({
          to: personalInfo.email,
          subject: 'Welcome to Abra Fleet - Driver Account Created',
          html: emailHtml,
          text: emailText
        });
        
        console.log('✅ Welcome email sent to:', personalInfo.email);
      } catch (emailError) {
        console.error('⚠️ Failed to send welcome email:', emailError.message);
      }
    }
    
    res.status(201).json({
      success: true,
      message: 'Driver created successfully',
      data: {
        _id: result.insertedId.toString(),
        driverId: driverId,
        ...newDriver
      }
    });
  } catch (error) {
    console.error('❌ Error creating driver:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create driver',
      error: error.message
    });
  }
});

// ============================================================================
// @route   PUT /api/admin/drivers/:id
// @desc    Update driver information
// @access  Private (Admin)
// ============================================================================
router.put('/:id', async (req, res) => {
  try {
    const query = { driverId: req.params.id };
    
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      query.$or = [
        { driverId: req.params.id },
        { _id: new ObjectId(req.params.id) }
      ];
    }
    
    const updateOperations = {
      $set: {
        updatedAt: new Date()
      }
    };
    
    if (req.body.personalInfo) {
      Object.keys(req.body.personalInfo).forEach(key => {
        if (key === 'dateOfBirth') {
          updateOperations.$set[`personalInfo.${key}`] = new Date(req.body.personalInfo[key]);
        } else {
          updateOperations.$set[`personalInfo.${key}`] = req.body.personalInfo[key];
        }
      });
    }
    
    if (req.body.license) {
      Object.keys(req.body.license).forEach(key => {
        if (key === 'issueDate' || key === 'expiryDate') {
          updateOperations.$set[`license.${key}`] = new Date(req.body.license[key]);
        } else {
          updateOperations.$set[`license.${key}`] = req.body.license[key];
        }
      });
    }
    
    if (req.body.emergencyContact) {
      Object.keys(req.body.emergencyContact).forEach(key => {
        updateOperations.$set[`emergencyContact.${key}`] = req.body.emergencyContact[key];
      });
    }
    
    if (req.body.address) {
      Object.keys(req.body.address).forEach(key => {
        updateOperations.$set[`address.${key}`] = req.body.address[key];
      });
    }
    
    if (req.body.employment) {
      Object.keys(req.body.employment).forEach(key => {
        updateOperations.$set[`employment.${key}`] = req.body.employment[key];
      });
    }
    
    if (req.body.bankDetails) {
      Object.keys(req.body.bankDetails).forEach(key => {
        updateOperations.$set[`bankDetails.${key}`] = req.body.bankDetails[key];
      });
    }
    
    const directFields = ['status', 'name', 'email', 'phone'];
    directFields.forEach(field => {
      if (req.body[field] !== undefined) {
        updateOperations.$set[field] = req.body[field];
      }
    });
    
    if (req.body.name) {
      const nameParts = req.body.name.split(' ');
      updateOperations.$set['personalInfo.firstName'] = nameParts[0];
      updateOperations.$set['personalInfo.lastName'] = nameParts.slice(1).join(' ') || '';
    }
    if (req.body.email) {
      updateOperations.$set['personalInfo.email'] = req.body.email;
    }
    if (req.body.phone) {
      updateOperations.$set['personalInfo.phone'] = req.body.phone;
    }
    
    const result = await req.db.collection('drivers').updateOne(
      query,
      updateOperations
    );
    
    if (result.matchedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    const updatedDriver = await req.db.collection('drivers').findOne(query);
    
    res.json({
      success: true,
      message: 'Driver updated successfully',
      data: updatedDriver
    });
  } catch (error) {
    console.error('❌ Error updating driver:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update driver',
      error: error.message
    });
  }
});


// ============================================================================
// @route   DELETE /api/admin/drivers/:id
// @desc    Delete/deactivate a driver
// @access  Private (Admin)
// ============================================================================
router.delete('/:id', async (req, res) => {
  try {
    console.log(`\n🗑️ [Driver Delete] Attempting to delete driver: ${req.params.id}`);
    
    // Build query to find driver - prioritize _id first, then fallback to driverId
    let driver;
    
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      // Valid ObjectId format - try _id first
      console.log(`   Trying _id lookup first...`);
      driver = await req.db.collection('drivers').findOne({ _id: new ObjectId(req.params.id) });
      
      // Fallback to driverId if not found by _id
      if (!driver) {
        console.log(`   Not found by _id, trying driverId...`);
        driver = await req.db.collection('drivers').findOne({ driverId: req.params.id });
      }
    } else {
      // Not a valid ObjectId - use driverId directly
      console.log(`   Using driverId lookup...`);
      driver = await req.db.collection('drivers').findOne({ driverId: req.params.id });
    }
    
    if (!driver) {
      console.log(`❌ [Driver Delete] Driver not found: ${req.params.id}`);
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    console.log(`✅ [Driver Delete] Found driver: ${driver.driverId}, status: ${driver.status}`);
    console.log(`   Driver name: ${driver.personalInfo?.firstName} ${driver.personalInfo?.lastName}`);
    console.log(`   Assigned vehicle: ${driver.assignedVehicle || 'None'}`);
    
    // ✅ FIX: More flexible vehicle assignment check
    if (driver.assignedVehicle) {
      console.log(`🔍 [Driver Delete] Checking vehicle assignment...`);
      
      // Try multiple ways to find the vehicle
      const vehicleQuery = {
        $or: [
          { _id: driver.assignedVehicle },
          { _id: ObjectId.isValid(driver.assignedVehicle?.toString()) ? new ObjectId(driver.assignedVehicle.toString()) : null },
          { vehicleId: driver.assignedVehicle?.toString() },
          { registrationNumber: driver.assignedVehicle?.toString() }
        ]
      };
      
      const vehicle = await req.db.collection('vehicles').findOne(vehicleQuery);
      
      if (vehicle) {
        console.log(`   Found vehicle: ${vehicle.vehicleId || vehicle.registrationNumber}`);
        console.log(`   Vehicle's assigned driver: ${JSON.stringify(vehicle.assignedDriver)}`);
        
        // Check if THIS driver is actually assigned to the vehicle
        const isDriverAssigned = vehicle.assignedDriver && (
          vehicle.assignedDriver._id?.toString() === driver._id.toString() ||
          vehicle.assignedDriver.driverId === driver.driverId
        );
        
        if (isDriverAssigned) {
          console.log(`❌ [Driver Delete] Driver has active vehicle assignment`);
          return res.status(400).json({
            success: false,
            message: `Cannot delete driver with active vehicle assignment (${vehicle.vehicleId || vehicle.registrationNumber}). Please unassign the vehicle first.`
          });
        } else {
          console.log(`⚠️ [Driver Delete] Vehicle found but driver not assigned to it (stale reference)`);
        }
      } else {
        console.log(`⚠️ [Driver Delete] Vehicle not found in database (stale reference)`);
      }
    }
    
    // Check for active rosters
    console.log(`🔍 [Driver Delete] Checking active rosters...`);
    const activeRosters = await req.db.collection('rosters').countDocuments({
      driverId: driver.driverId,
      status: { $in: ['pending', 'approved', 'in_progress'] }
    });
    
    if (activeRosters > 0) {
      console.log(`❌ [Driver Delete] Driver has ${activeRosters} active rosters`);
      return res.status(400).json({
        success: false,
        message: `Cannot delete driver with ${activeRosters} active roster(s). Please reassign or complete them first.`
      });
    }
    console.log(`   ✅ No active rosters`);
    
    // Check for active trips
    console.log(`🔍 [Driver Delete] Checking active trips...`);
    const activeTrips = await req.db.collection('trips').countDocuments({
      driverId: driver.driverId,
      status: { $in: ['scheduled', 'in_progress', 'started', 'assigned'] }
    });
    
    // Also check roster-assigned-trips collection
    const activeRosterTrips = await req.db.collection('roster-assigned-trips').countDocuments({
      driverId: driver._id,
      status: { $in: ['scheduled', 'in_progress', 'started', 'assigned'] }
    });
    
    const totalActiveTrips = activeTrips + activeRosterTrips;
    
    if (totalActiveTrips > 0) {
      console.log(`❌ [Driver Delete] Driver has ${totalActiveTrips} active trips`);
      return res.status(400).json({
        success: false,
        message: `Cannot delete driver with ${totalActiveTrips} active trip(s). Please reassign or complete them first.`
      });
    }
    console.log(`   ✅ No active trips`);
    
    // ✅ PERFORM SOFT DELETE
    console.log(`🗑️ [Driver Delete] Soft deleting driver: ${driver.driverId}`);
    const updateResult = await req.db.collection('drivers').updateOne(
      { _id: driver._id },
      { 
        $set: { 
          status: 'inactive',
          deletedAt: new Date(),
          updatedAt: new Date()
        } 
      }
    );
    
    console.log(`   Update result: matchedCount=${updateResult.matchedCount}, modifiedCount=${updateResult.modifiedCount}`);
    
    if (updateResult.modifiedCount === 0) {
      console.log(`⚠️ [Driver Delete] No documents modified`);
      return res.status(400).json({
        success: false,
        message: 'Driver status could not be updated'
      });
    }
    
    // Clean up vehicle assignment if exists
    if (driver.assignedVehicle) {
      console.log(`🧹 [Driver Delete] Cleaning up vehicle assignment...`);
      const vehicleUpdateResult = await req.db.collection('vehicles').updateMany(
        { 
          $or: [
            { _id: driver.assignedVehicle },
            { _id: ObjectId.isValid(driver.assignedVehicle?.toString()) ? new ObjectId(driver.assignedVehicle.toString()) : null },
            { vehicleId: driver.assignedVehicle?.toString() },
            { 'assignedDriver._id': driver._id },
            { 'assignedDriver.driverId': driver.driverId }
          ]
        },
        { 
          $set: { 
            assignedDriver: null, 
            updatedAt: new Date() 
          } 
        }
      );
      console.log(`   Vehicles updated: ${vehicleUpdateResult.modifiedCount}`);
    }
    
    console.log(`✅ [Driver Delete] Successfully deactivated driver: ${driver.driverId}\n`);
    
    res.json({
      success: true,
      message: 'Driver deactivated successfully'
    });
    
  } catch (error) {
    console.error('❌ [Driver Delete] Error:', error);
    console.error('   Stack:', error.stack);
    res.status(500).json({
      success: false,
      message: 'Failed to deactivate driver',
      error: error.message
    });
  }
});

// CONTINUES IN CHUNK 3...
// CHUNK 3 of 3: VEHICLE ASSIGNMENT + DOCUMENTS + PASSWORD RESET + ADDITIONAL ROUTES

// ============================================================================
// @route   POST /api/admin/drivers/:id/assign-vehicle
// @desc    Assign vehicle to driver
// @access  Private (Admin)
// ============================================================================
router.post('/:id/assign-vehicle', async (req, res) => {
  const session = req.db.client.startSession();
  
  try {
    const { vehicleId } = req.body;
    
    console.log('=== ASSIGN VEHICLE REQUEST ===');
    console.log('Driver ID:', req.params.id);
    console.log('Vehicle ID:', vehicleId);
    
    if (!vehicleId) {
      return res.status(400).json({
        success: false,
        message: 'Vehicle ID is required'
      });
    }
    
    await session.withTransaction(async () => {
      const driver = await req.db.collection('drivers').findOne(
        { driverId: req.params.id },
        { session }
      );
      
      if (!driver) {
        throw new Error('Driver not found');
      }
      
      let vehicle = await req.db.collection('vehicles').findOne(
        { vehicleId: vehicleId },
        { session }
      );
      
      if (!vehicle && /^[0-9a-fA-F]{24}$/.test(vehicleId)) {
        vehicle = await req.db.collection('vehicles').findOne(
          { _id: new ObjectId(vehicleId) },
          { session }
        );
      }
      
      if (!vehicle) {
        throw new Error('Vehicle not found');
      }
      
      if (vehicle.assignedDriver && 
          typeof vehicle.assignedDriver === 'object' && 
          vehicle.assignedDriver._id?.toString() !== driver._id.toString()) {
        throw new Error(`Vehicle is already assigned to another driver`);
      }
      
      if (driver.assignedVehicle && 
          driver.assignedVehicle.toString() !== vehicle._id.toString()) {
        await req.db.collection('vehicles').updateOne(
          { 
            $or: [
              { _id: new ObjectId(driver.assignedVehicle) },
              { vehicleId: driver.assignedVehicle }
            ]
          },
          { 
            $set: { 
              assignedDriver: null,
              updatedAt: new Date()
            } 
          },
          { session }
        );
      }
      
      await req.db.collection('drivers').updateOne(
        { _id: driver._id },
        { 
          $set: { 
            assignedVehicle: vehicle._id,
            vehicleNumber: vehicle.registrationNumber || vehicle.vehicleNumber,
            updatedAt: new Date()
          } 
        },
        { session }
      );
      
      await req.db.collection('vehicles').updateOne(
        { _id: vehicle._id },
        { 
          $set: { 
            assignedDriver: {
              _id: driver._id,
              driverId: driver.driverId,
              name: `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim(),
              email: driver.personalInfo?.email || driver.email,
              phone: driver.personalInfo?.phone || driver.phone
            },
            status: 'active',
            updatedAt: new Date()
          } 
        },
        { session }
      );
      
      try {
        const targetUserId = driver.firebaseUid || driver.uid || driver.driverId;
        
        await createNotification(req.db, {
          userId: targetUserId, 
          type: 'vehicle_assigned', 
          title: 'New Vehicle Assigned 🚗',
          body: `You have been assigned to ${vehicle.make || 'Vehicle'} ${vehicle.model || ''} (${vehicle.registrationNumber})`,
          data: {
            vehicleId: vehicle._id.toString(),
            vehicleName: `${vehicle.make || ''} ${vehicle.model || ''}`.trim(),
            registrationNumber: vehicle.registrationNumber
          },
          priority: 'high',
          category: 'system'
        });
      } catch (notifyError) {
        console.error('❌ Failed to send driver notification:', notifyError.message);
      }
    });
    
    await session.endSession();
    console.log('=== ASSIGNMENT SUCCESSFUL ===');
    
    res.json({
      success: true,
      message: 'Vehicle assigned to driver successfully'
    });
    
  } catch (error) {
    await session.endSession();
    console.error('=== ASSIGN VEHICLE ERROR ===');
    console.error('Error:', error.message);
    
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to assign vehicle to driver'
    });
  }
});

// ============================================================================
// @route   POST /api/admin/drivers/:id/unassign-vehicle
// @desc    Unassign vehicle from driver
// @access  Private (Admin)
// ============================================================================
router.post('/:id/unassign-vehicle', async (req, res) => {
  const session = req.db.client.startSession();
  
  try {
    await session.withTransaction(async () => {
      const driver = await req.db.collection('drivers').findOne(
        { 
          $or: [
            { driverId: req.params.id },
            { _id: new ObjectId(req.params.id) }
          ]
        },
        { session }
      );
      
      if (!driver) {
        throw new Error('Driver not found');
      }
      
      if (!driver.assignedVehicle) {
        throw new Error('Driver does not have an assigned vehicle');
      }
      
      const vehicleObjectId = driver.assignedVehicle;
      
      await req.db.collection('drivers').updateOne(
        { _id: driver._id },
        { 
          $set: { 
            assignedVehicle: null,
            vehicleNumber: null,
            updatedAt: new Date()
          } 
        },
        { session }
      );
      
      await req.db.collection('vehicles').updateOne(
        { _id: vehicleObjectId },
        { 
          $set: { 
            assignedDriver: null,
            updatedAt: new Date()
          } 
        },
        { session }
      );
    });
    
    await session.endSession();
    
    res.json({
      success: true,
      message: 'Vehicle unassigned from driver successfully'
    });
  } catch (error) {
    await session.endSession();
    
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to unassign vehicle from driver'
    });
  }
});

// ============================================================================
// @route   GET /api/admin/drivers/:id/trips
// @desc    Get driver's trip history with pagination and filters
// @access  Private (Admin)
// ============================================================================
router.get('/:id/trips', async (req, res) => {
  try {
    const { page = 1, limit = 10, status, startDate, endDate } = req.query;
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    let driverQuery = { driverId: req.params.id };
    
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      driverQuery = {
        $or: [
          { driverId: req.params.id },
          { _id: new ObjectId(req.params.id) }
        ]
      };
    }
    
    const driver = await req.db.collection('drivers').findOne(driverQuery);
    
    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    const query = { driverId: driver.driverId };
    
    if (status) {
      query.status = status;
    }
    
    if (startDate || endDate) {
      query.startTime = {};
      if (startDate) query.startTime.$gte = new Date(startDate);
      if (endDate) query.startTime.$lte = new Date(endDate);
    }
    
    const trips = await req.db.collection('trips')
      .find(query)
      .sort({ startTime: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();
    
    const totalTrips = await req.db.collection('trips').countDocuments(query);
    
    const stats = {
      total: totalTrips,
      completed: await req.db.collection('trips').countDocuments({ 
        ...query, 
        status: 'completed' 
      }),
      inProgress: await req.db.collection('trips').countDocuments({ 
        ...query, 
        status: 'in_progress' 
      }),
      cancelled: await req.db.collection('trips').countDocuments({ 
        ...query, 
        status: 'cancelled' 
      })
    };
    
    res.json({
      success: true,
      data: trips,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalTrips,
        pages: Math.ceil(totalTrips / parseInt(limit))
      },
      stats
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to fetch driver trips',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/admin/drivers/:id/documents
// @desc    Upload driver document
// @access  Private (Admin)
// ============================================================================
router.post('/:id/documents', upload.single('document'), async (req, res) => {
  try {
    const { documentType, documentName, expiryDate } = req.body;
    
    if (!documentType || !documentName) {
      return res.status(400).json({
        success: false,
        message: 'Document type and name are required'
      });
    }
    
    const driverQuery = { driverId: req.params.id };
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      driverQuery.$or = [
        { driverId: req.params.id },
        { _id: new ObjectId(req.params.id) }
      ];
    }
    
    const driver = await req.db.collection('drivers').findOne(driverQuery);
    
    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    const newDocument = {
      id: new ObjectId().toString(),
      documentType,
      documentName,
      documentUrl: req.file ? `/uploads/driver-documents/${req.file.filename}` : '',
      fileName: req.file ? req.file.filename : '',
      expiryDate: expiryDate ? new Date(expiryDate) : null,
      uploadedAt: new Date(),
      uploadedBy: req.user?.uid || 'admin'
    };
    
    await req.db.collection('drivers').updateOne(
      { _id: driver._id },
      { 
        $push: { documents: newDocument },
        $set: { updatedAt: new Date() }
      }
    );
    
    res.json({
      success: true,
      message: 'Document added successfully',
      data: newDocument
    });
  } catch (error) {
    console.error('Error adding driver document:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to add document',
      error: error.message
    });
  }
});

// ============================================================================
// @route   DELETE /api/admin/drivers/:id/documents/:documentId
// @desc    Delete driver document
// @access  Private (Admin)
// ============================================================================
router.delete('/:id/documents/:documentId', async (req, res) => {
  try {
    const driverQuery = { driverId: req.params.id };
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      driverQuery.$or = [
        { driverId: req.params.id },
        { _id: new ObjectId(req.params.id) }
      ];
    }
    
    const driver = await req.db.collection('drivers').findOne(driverQuery);
    
    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    const result = await req.db.collection('drivers').updateOne(
      { _id: driver._id },
      { 
        $pull: { documents: { id: req.params.documentId } },
        $set: { updatedAt: new Date() }
      }
    );
    
    if (result.modifiedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Document not found'
      });
    }
    
    res.json({
      success: true,
      message: 'Document deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting driver document:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete document',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/admin/drivers/:id/send-password-reset
// @desc    Send password reset email to driver
// @access  Private (Admin)
// ============================================================================
router.post('/:id/send-password-reset', async (req, res) => {
  console.log('\n📧 ========== SEND PASSWORD RESET EMAIL ==========');
  console.log('🔍 Step 1: Request received');
  console.log('   Driver ID:', req.params.id);
  
  try {
    console.log('\n🔍 Step 2: Building driver query...');
    const driverQuery = { driverId: req.params.id };
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      driverQuery.$or = [
        { driverId: req.params.id },
        { _id: new ObjectId(req.params.id) }
      ];
    }
    console.log('   Query:', JSON.stringify(driverQuery, null, 2));
    
    console.log('\n🔍 Step 3: Searching for driver in database...');
    const driver = await req.db.collection('drivers').findOne(driverQuery);
    console.log('   Driver found:', driver ? 'YES' : 'NO');
    
    if (!driver) {
      console.log('❌ Driver not found in database');
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    console.log('   Driver data:', JSON.stringify({
      driverId: driver.driverId,
      personalInfo: driver.personalInfo,
      hasEmail: !!driver.personalInfo?.email
    }, null, 2));
    
    const email = driver.personalInfo?.email;
    const firstName = driver.personalInfo?.firstName;
    const lastName = driver.personalInfo?.lastName;
    
    console.log('\n🔍 Step 4: Validating email...');
    console.log('   Email:', email);
    console.log('   First Name:', firstName);
    console.log('   Last Name:', lastName);
    
    if (!email || email === 'N/A') {
      console.log('❌ Driver does not have a valid email address');
      return res.status(400).json({
        success: false,
        message: 'Driver does not have a valid email address'
      });
    }
    
    console.log('✅ Driver found:', firstName, lastName);
    console.log('📧 Email:', email);
    
    console.log('\n🔍 Step 5: Generating password reset link...');
    
    try {
      // Generate a temporary password reset token (valid for 24 hours)
      const resetToken = require('crypto').randomBytes(32).toString('hex');
      const resetTokenExpiry = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24 hours
      
      // Store reset token in driver document
      await req.db.collection('drivers').updateOne(
        { _id: driver._id },
        {
          $set: {
            passwordResetToken: resetToken,
            passwordResetExpiry: resetTokenExpiry,
            updatedAt: new Date()
          }
        }
      );
      
      // Create password reset link
      const resetLink = `${process.env.FRONTEND_URL || 'http://localhost:3000'}/reset-password?token=${resetToken}&email=${encodeURIComponent(email)}`;
      
      console.log('✅ Password reset link generated successfully');
      console.log('   Link length:', resetLink.length);
      console.log('   Link preview:', resetLink.substring(0, 50) + '...');
      
      console.log('\n🔍 Step 6: Preparing email templates...');
      const emailHtml = getDriverWelcomeTemplate(
        firstName,
        lastName,
        email,
        driver.driverId,
        resetLink
      );
      
      const emailText = getDriverWelcomeText(
        firstName,
        lastName,
        email,
        driver.driverId,
        resetLink
      );
      
      console.log('✅ Email templates generated');
      console.log('   HTML length:', emailHtml.length);
      console.log('   Text length:', emailText.length);
      
      console.log('\n🔍 Step 7: Sending email via email service...');
      console.log('   To:', email);
      console.log('   Subject: Password Reset - Abra Travels');
      
      await emailService.sendEmail(
        email,
        'Password Reset - Abra Travels',
        emailText,
        emailHtml
      );
      
      console.log('✅ Password reset email sent successfully');
      console.log('========== EMAIL SENT COMPLETE ==========\n');
      
      res.json({
        success: true,
        message: `Password reset email sent successfully to ${email}`
      });
      
    } catch (emailError) {
      console.error('\n❌ Email Error:');
      console.error('   Error name:', emailError.name);
      console.error('   Error message:', emailError.message);
      console.error('   Error code:', emailError.code);
      throw emailError;
    }
    
  } catch (error) {
    console.error('\n❌ ========== SEND PASSWORD RESET FAILED ==========');
    console.error('Error type:', error.constructor.name);
    console.error('Error name:', error.name);
    console.error('Error message:', error.message);
    console.error('Error code:', error.code);
    console.error('Stack trace:', error.stack);
    console.error('========== ERROR END ==========\n');
    
    res.status(500).json({
      success: false,
      message: 'Failed to send password reset email',
      error: error.message,
      errorCode: error.code,
      errorName: error.name
    });
  }
});

// ============================================================================
// @route   POST /api/admin/drivers/bulk-import
// @desc    Bulk import drivers from CSV
// @access  Private (Admin)
// ============================================================================
router.post('/bulk-import', async (req, res) => {
  console.log('\n🚗 ========== BULK DRIVER IMPORT STARTED ==========');
  console.log('📥 Request body:', JSON.stringify(req.body, null, 2));
  
  try {
    const { drivers } = req.body;
    
    if (!drivers || !Array.isArray(drivers) || drivers.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'No driver data provided'
      });
    }
    
    console.log(`📊 Processing ${drivers.length} drivers for bulk import`);
    
    const results = {
      successful: [],
      failed: [],
      skipped: []
    };
    
    for (let i = 0; i < drivers.length; i++) {
      const driverData = drivers[i];
      console.log(`\n📋 Processing driver ${i + 1}/${drivers.length}: ${driverData.firstName} ${driverData.lastName}`);
      
      try {
        const driverCount = await req.db.collection('drivers').countDocuments();
        const driverId = `DRV-${String(driverCount + 100001).padStart(6, '0')}`;
        
        const existingDriver = await req.db.collection('drivers').findOne({
          $or: [
            { 'personalInfo.phone': driverData.phone },
            { 'personalInfo.email': driverData.email },
            { 'license.licenseNumber': driverData.licenseNumber }
          ]
        });
        
        if (existingDriver) {
          console.log(`⚠️  Driver already exists: ${driverData.email}`);
          results.skipped.push({
            data: driverData,
            reason: 'Driver with same phone, email, or license already exists'
          });
          continue;
        }
        
        const newDriver = {
          driverId,
          name: `${driverData.firstName} ${driverData.lastName}`,
          email: driverData.email,
          phone: driverData.phone,
          personalInfo: {
            firstName: driverData.firstName,
            lastName: driverData.lastName,
            phone: driverData.phone,
            email: driverData.email,
            dateOfBirth: driverData.dob ? new Date(driverData.dob) : null,
            bloodGroup: driverData.bloodGroup,
            gender: driverData.gender
          },
          license: {
            licenseNumber: driverData.licenseNumber,
            type: driverData.licenseType,
            issueDate: new Date(driverData.issueDate),
            expiryDate: new Date(driverData.expiryDate),
            issuingAuthority: driverData.issuingAuthority
          },
          emergencyContact: driverData.emergencyContactName ? {
            name: driverData.emergencyContactName,
            relationship: driverData.emergencyContactRelationship,
            phone: driverData.emergencyContactPhone
          } : null,
          address: driverData.street ? {
            street: driverData.street,
            city: driverData.city,
            state: driverData.state,
            postalCode: driverData.postalCode,
            country: driverData.country
          } : null,
          status: driverData.status || 'active',
          assignedVehicle: null,
          vehicleNumber: null,
          documents: [],
          feedbackStats: {
            totalFeedback: 0,
            averageRating: 0,
            rating5Stars: 0,
            rating4Stars: 0,
            rating3Stars: 0,
            rating2Stars: 0,
            rating1Stars: 0
          },
          joinedDate: new Date(),
          createdAt: new Date(),
          updatedAt: new Date()
        };
        
        const result = await req.db.collection('drivers').insertOne(newDriver);
        console.log(`✅ Driver inserted: ${result.insertedId}`);
        
        try {
          const resetToken = require('crypto').randomBytes(32).toString('hex');
          const resetLink = `${process.env.FRONTEND_URL}/reset-password?token=${resetToken}&email=${encodeURIComponent(driverData.email)}`;
          
          const emailHtml = getDriverWelcomeTemplate(
            driverData.firstName,
            driverData.lastName,
            driverData.email,
            driverId,
            resetLink
          );
          const emailText = getDriverWelcomeText(
            driverData.firstName,
            driverData.lastName,
            driverData.email,
            driverId,
            resetLink
          );
          
          await emailService.sendEmail(
            driverData.email,
            'Welcome to Abra Travels - Set Your Password',
            emailText,
            emailHtml
          );
          console.log(`✅ Welcome email sent to: ${driverData.email}`);
        } catch (emailError) {
          console.error(`❌ Failed to send email to ${driverData.email}:`, emailError.message);
        }
        
        results.successful.push({
          driverId,
          name: `${driverData.firstName} ${driverData.lastName}`,
          email: driverData.email
        });
        
      } catch (error) {
        console.error(`❌ Failed to process driver ${driverData.firstName} ${driverData.lastName}:`, error.message);
        results.failed.push({
          data: driverData,
          error: error.message
        });
      }
    }
    
    console.log('\n✅ ========== BULK DRIVER IMPORT COMPLETED ==========');
    console.log(`📊 Results: ${results.successful.length} successful, ${results.failed.length} failed, ${results.skipped.length} skipped`);
    
    res.status(201).json({
      success: true,
      message: `Bulk import completed. ${results.successful.length} drivers imported successfully.`,
      results
    });
    
  } catch (error) {
    console.error('\n❌ ========== BULK DRIVER IMPORT FAILED ==========');
    console.error('Error:', error.message);
    console.error('Stack:', error.stack);
    
    res.status(500).json({
      success: false,
      message: 'Failed to process bulk driver import',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/admin/drivers/:id/reset-password
// @desc    Verify reset token and update password
// @access  Public
// ============================================================================
router.post('/:id/reset-password', async (req, res) => {
  try {
    const { token, newPassword } = req.body;
    
    if (!token || !newPassword) {
      return res.status(400).json({
        success: false,
        message: 'Token and new password are required'
      });
    }
    
    const driver = await req.db.collection('drivers').findOne({
      passwordResetToken: token,
      passwordResetExpiry: { $gt: new Date() }
    });
    
    if (!driver) {
      return res.status(400).json({
        success: false,
        message: 'Invalid or expired reset token'
      });
    }
    
    const hashedPassword = await bcrypt.hash(newPassword, 10);
    
    await req.db.collection('drivers').updateOne(
      { _id: driver._id },
      {
        $set: {
          password: hashedPassword,
          updatedAt: new Date()
        },
        $unset: {
          passwordResetToken: '',
          passwordResetExpiry: ''
        }
      }
    );
    
    res.json({
      success: true,
      message: 'Password reset successfully'
    });
  } catch (error) {
    console.error('Error resetting password:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to reset password',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/drivers/:id/feedback
// @desc    Get driver feedback/ratings
// @access  Private (Admin)
// ============================================================================
router.get('/:id/feedback', async (req, res) => {
  try {
    const { page = 1, limit = 10 } = req.query;
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const driverQuery = { driverId: req.params.id };
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      driverQuery.$or = [
        { driverId: req.params.id },
        { _id: new ObjectId(req.params.id) }
      ];
    }
    
    const driver = await req.db.collection('drivers').findOne(driverQuery);
    
    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    const feedback = await req.db.collection('driver_feedback')
      .find({ 
        driverId: driver._id,
        feedbackType: 'driver_trip_feedback'
      })
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();
    
    const totalFeedback = await req.db.collection('driver_feedback')
      .countDocuments({ 
        driverId: driver._id,
        feedbackType: 'driver_trip_feedback'
      });
    
    const feedbackStats = await req.db.collection('driver_feedback').aggregate([
      { 
        $match: { 
          driverId: driver._id,
          feedbackType: 'driver_trip_feedback'
        } 
      },
      {
        $group: {
          _id: null,
          averageRating: { $avg: '$rating' },
          totalFeedback: { $sum: 1 },
          rating5Stars: { $sum: { $cond: [{ $eq: ['$rating', 5] }, 1, 0] } },
          rating4Stars: { $sum: { $cond: [{ $eq: ['$rating', 4] }, 1, 0] } },
          rating3Stars: { $sum: { $cond: [{ $eq: ['$rating', 3] }, 1, 0] } },
          rating2Stars: { $sum: { $cond: [{ $eq: ['$rating', 2] }, 1, 0] } },
          rating1Stars: { $sum: { $cond: [{ $eq: ['$rating', 1] }, 1, 0] } }
        }
      }
    ]).toArray();
    
    res.json({
      success: true,
      data: feedback,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalFeedback,
        pages: Math.ceil(totalFeedback / parseInt(limit))
      },
      stats: feedbackStats[0] || {
        averageRating: 0,
        totalFeedback: 0,
        rating5Stars: 0,
        rating4Stars: 0,
        rating3Stars: 0,
        rating2Stars: 0,
        rating1Stars: 0
      }
    });
  } catch (error) {
    console.error('Error fetching driver feedback:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch driver feedback',
      error: error.message
    });
  }
});

module.exports = router;

// ============================================================================
// END OF COMPLETE ADMIN-DRIVERS.JS FILE
// ============================================================================