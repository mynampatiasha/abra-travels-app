// routes/admin_trip_verification_router.js
// ============================================================================
// ADMIN TRIP VERIFICATION & REPORTS - Simple & Working
// ============================================================================
// Features:
// ✅ Fetch trips with filters (date, driver, vehicle, status)
// ✅ Get trip details by ID
// ✅ Access odometer photos (admin permission)
// ✅ Real data from roster-assigned-trips collection
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const { GridFSBucket } = require('mongodb');

// ============================================================================
// @route   GET /api/admin/trips/verification
// @desc    Get all trips with filters for verification
// @access  Private (Admin only)
// ============================================================================
router.get('/trips/verification', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📋 ADMIN: FETCHING TRIPS FOR VERIFICATION');
    console.log('='.repeat(80));
    
    // Check if user is admin
    const userRole = req.user.role || req.user.userRole;
    if (!['admin', 'super_admin'].includes(userRole)) {
      return res.status(403).json({
        success: false,
        message: 'Access denied. Admin privileges required.'
      });
    }
    
    // Parse filters from query params
    const {
      startDate,
      endDate,
      driverId,
      vehicleId,
      status,
      limit = 100,
      skip = 0
    } = req.query;
    
    console.log('🔍 Filters:', {
      startDate,
      endDate,
      driverId,
      vehicleId,
      status
    });
    
    // Build query
    const query = {};
    
    // Date filter
    if (startDate || endDate) {
      query.scheduledDate = {};
      if (startDate) query.scheduledDate.$gte = startDate;
      if (endDate) query.scheduledDate.$lte = endDate;
    }
    
    // Driver filter
    if (driverId && ObjectId.isValid(driverId)) {
      query.driverId = new ObjectId(driverId);
    }
    
    // Vehicle filter
    if (vehicleId && ObjectId.isValid(vehicleId)) {
      query.vehicleId = new ObjectId(vehicleId);
    }
    
    // Status filter
    if (status && status !== 'all') {
      query.status = status;
    }
    
    // Only fetch trips that have been started (have odometer data)
    query.startOdometer = { $exists: true };
    
    console.log('📝 Query:', JSON.stringify(query, null, 2));
    
    // Fetch trips
    const trips = await req.db.collection('roster-assigned-trips')
      .find(query)
      .sort({ scheduledDate: -1, actualStartTime: -1 })
      .limit(parseInt(limit))
      .skip(parseInt(skip))
      .toArray();
    
    console.log(`✅ Found ${trips.length} trip(s)`);
    
    // Transform data for frontend
    const processedTrips = trips.map(trip => ({
      id: trip._id.toString(),
      tripNumber: trip.tripNumber || trip.tripGroupId,
      tripGroupId: trip.tripGroupId,
      
      // Driver info
      driverId: trip.driverId?.toString(),
      driverName: trip.driverName,
      driverEmail: trip.driverEmail,
      driverPhone: trip.driverPhone,
      
      // Vehicle info
      vehicleId: trip.vehicleId?.toString(),
      vehicleNumber: trip.vehicleNumber,
      vehicleName: trip.vehicleName,
      
      // Trip details
      scheduledDate: trip.scheduledDate,
      startTime: trip.startTime,
      endTime: trip.endTime,
      status: trip.status,
      
      // Odometer data
      startOdometer: trip.startOdometer ? {
        reading: trip.startOdometer.reading,
        photoId: trip.startOdometer.photoId?.toString(),
        timestamp: trip.startOdometer.timestamp
      } : null,
      
      endOdometer: trip.endOdometer ? {
        reading: trip.endOdometer.reading,
        photoId: trip.endOdometer.photoId?.toString(),
        timestamp: trip.endOdometer.timestamp
      } : null,
      
      // Distance
      actualDistance: trip.actualDistance,
      totalDistance: trip.totalDistance,
      
      // Stops
      totalStops: trip.totalStops || trip.stops?.length || 0,
      stops: trip.stops || [],
      
      // Feedback
      customerFeedback: trip.customerFeedback,
      feedbackSubmitted: trip.feedbackSubmitted || false,
      
      // Timestamps
      actualStartTime: trip.actualStartTime,
      actualEndTime: trip.actualEndTime,
      createdAt: trip.createdAt,
      updatedAt: trip.updatedAt
    }));
    
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: `Found ${processedTrips.length} trip(s)`,
      data: processedTrips,
      count: processedTrips.length,
      filters: {
        startDate,
        endDate,
        driverId,
        vehicleId,
        status
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch trips',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/trips/:tripId/details
// @desc    Get detailed trip information
// @access  Private (Admin only)
// ============================================================================
router.get('/trips/:tripId/details', verifyToken, async (req, res) => {
  try {
    console.log(`\n📋 ADMIN: Fetching trip details for ${req.params.tripId}`);
    
    // Check admin role
    const userRole = req.user.role || req.user.userRole;
    if (!['admin', 'super_admin'].includes(userRole)) {
      return res.status(403).json({
        success: false,
        message: 'Access denied. Admin privileges required.'
      });
    }
    
    const { tripId } = req.params;
    
    if (!ObjectId.isValid(tripId)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid trip ID'
      });
    }
    
    const trip = await req.db.collection('roster-assigned-trips').findOne({
      _id: new ObjectId(tripId)
    });
    
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }
    
    console.log(`✅ Trip found: ${trip.tripNumber || tripId}`);
    
    res.json({
      success: true,
      data: trip
    });
    
  } catch (error) {
    console.error('❌ Error fetching trip details:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch trip details',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/odometer-photo/:photoId
// @desc    Get odometer photo from GridFS (Admin access)
// @access  Private (Admin only)
// ============================================================================
router.get('/odometer-photo/:photoId', verifyToken, async (req, res) => {
  try {
    console.log(`\n📸 ADMIN: Fetching photo ${req.params.photoId}`);
    
    // Check admin role
    const userRole = req.user.role || req.user.userRole;
    if (!['admin', 'super_admin'].includes(userRole)) {
      return res.status(403).json({
        success: false,
        message: 'Access denied. Admin privileges required.'
      });
    }
    
    const { photoId } = req.params;
    
    if (!ObjectId.isValid(photoId)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid photo ID'
      });
    }
    
    const bucket = new GridFSBucket(req.db, {
      bucketName: 'odometer_photos'
    });
    
    const downloadStream = bucket.openDownloadStream(new ObjectId(photoId));
    
    downloadStream.on('error', (error) => {
      console.error('❌ Error streaming photo:', error);
      res.status(404).json({
        success: false,
        message: 'Photo not found'
      });
    });
    
    downloadStream.on('file', (file) => {
      console.log(`✅ Streaming photo: ${file.filename}`);
    });
    
    res.set('Content-Type', 'image/jpeg');
    downloadStream.pipe(res);
    
  } catch (error) {
    console.error('❌ Error fetching photo:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch photo',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/drivers/list
// @desc    Get list of all drivers (for filter dropdown)
// @access  Private (Admin only)
// ============================================================================
router.get('/drivers/list', verifyToken, async (req, res) => {
  try {
    const userRole = req.user.role || req.user.userRole;
    if (!['admin', 'super_admin'].includes(userRole)) {
      return res.status(403).json({
        success: false,
        message: 'Access denied'
      });
    }
    
    const drivers = await req.db.collection('drivers')
      .find({}, {
        projection: {
          _id: 1,
          driverId: 1,
          'personalInfo.name': 1,
          name: 1
        }
      })
      .toArray();
    
    const driverList = drivers.map(d => ({
      id: d._id.toString(),
      driverId: d.driverId,
      name: d.personalInfo?.name || d.name || 'Unknown'
    }));
    
    res.json({
      success: true,
      data: driverList
    });
    
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to fetch drivers',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/vehicles/list
// @desc    Get list of all vehicles (for filter dropdown)
// @access  Private (Admin only)
// ============================================================================
router.get('/vehicles/list', verifyToken, async (req, res) => {
  try {
    const userRole = req.user.role || req.user.userRole;
    if (!['admin', 'super_admin'].includes(userRole)) {
      return res.status(403).json({
        success: false,
        message: 'Access denied'
      });
    }
    
    const vehicles = await req.db.collection('vehicles')
      .find({}, {
        projection: {
          _id: 1,
          registrationNumber: 1,
          vehicleNumber: 1,
          name: 1
        }
      })
      .toArray();
    
    const vehicleList = vehicles.map(v => ({
      id: v._id.toString(),
      number: v.registrationNumber || v.vehicleNumber,
      name: v.name
    }));
    
    res.json({
      success: true,
      data: vehicleList
    });
    
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to fetch vehicles',
      error: error.message
    });
  }
});

module.exports = router;