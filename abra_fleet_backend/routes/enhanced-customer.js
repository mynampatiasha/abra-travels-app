const express = require('express');
const router = express.Router();
const { body, validationResult, query } = require('express-validator');

// @route   GET /api/customer/dashboard/enhanced-stats
// @desc    Get enhanced customer dashboard statistics
// @access  Private (Customer)
router.get('/dashboard/enhanced-stats', async (req, res) => {
  try {
    const customerId = req.user.email;
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
      default:
        startDate.setDate(endDate.getDate() - 30);
    }

    // Get comprehensive trip statistics
    const tripStats = await req.db.collection('trips').aggregate([
      {
        $match: {
          customerId: customerId,
          createdAt: { $gte: startDate, $lte: endDate }
        }
      },
      {
        $group: {
          _id: null,
          totalTrips: { $sum: 1 },
          completedTrips: {
            $sum: { $cond: [{ $eq: ['$status', 'completed'] }, 1, 0] }
          },
          cancelledTrips: {
            $sum: { $cond: [{ $eq: ['$status', 'cancelled'] }, 1, 0] }
          },
          ongoingTrips: {
            $sum: { $cond: [{ $in: ['$status', ['scheduled', 'in_progress']] }, 1, 0] }
          },
          totalDistance: { $sum: '$distance' },
          totalDuration: { $sum: '$duration' },
          averageRating: { $avg: '$customerRating' }
        }
      }
    ]).toArray();

    // Get roster statistics
    const rosterStats = await req.db.collection('rosters').aggregate([
      {
        $match: {
          customerId: customerId,
          createdAt: { $gte: startDate, $lte: endDate }
        }
      },
      {
        $group: {
          _id: null,
          totalRosters: { $sum: 1 },
          activeRosters: {
            $sum: { $cond: [{ $in: ['$status', ['assigned', 'active']] }, 1, 0] }
          },
          pendingRosters: {
            $sum: { $cond: [{ $eq: ['$status', 'pending'] }, 1, 0] }
          }
        }
      }
    ]).toArray();

    // Get recent activity
    const recentActivity = await req.db.collection('trips').find({
      customerId: customerId
    })
    .sort({ createdAt: -1 })
    .limit(5)
    .toArray();

    // Get upcoming trips
    const upcomingTrips = await req.db.collection('trips').find({
      customerId: customerId,
      status: 'scheduled',
      scheduledDate: { $gte: new Date() }
    })
    .sort({ scheduledDate: 1 })
    .limit(3)
    .toArray();

    // Calculate performance metrics
    const trips = tripStats[0] || {};
    const rosters = rosterStats[0] || {};
    
    const completionRate = trips.totalTrips > 0 
      ? ((trips.completedTrips / trips.totalTrips) * 100).toFixed(1)
      : 0;
    
    const cancellationRate = trips.totalTrips > 0 
      ? ((trips.cancelledTrips / trips.totalTrips) * 100).toFixed(1)
      : 0;

    res.json({
      success: true,
      data: {
        timeframe,
        period: { startDate, endDate },
        summary: {
          totalTrips: trips.totalTrips || 0,
          completedTrips: trips.completedTrips || 0,
          ongoingTrips: trips.ongoingTrips || 0,
          cancelledTrips: trips.cancelledTrips || 0,
          totalRosters: rosters.totalRosters || 0,
          activeRosters: rosters.activeRosters || 0,
          pendingRosters: rosters.pendingRosters || 0
        },
        performance: {
          completionRate: parseFloat(completionRate),
          cancellationRate: parseFloat(cancellationRate),
          averageRating: trips.averageRating ? parseFloat(trips.averageRating.toFixed(2)) : null,
          totalDistance: trips.totalDistance || 0,
          totalDuration: trips.totalDuration || 0
        },
        recentActivity: recentActivity.map(trip => ({
          tripId: trip.tripId,
          status: trip.status,
          date: trip.scheduledDate || trip.createdAt,
          pickup: trip.pickupLocation,
          drop: trip.dropLocation,
          vehicleInfo: trip.vehicleInfo
        })),
        upcomingTrips: upcomingTrips.map(trip => ({
          tripId: trip.tripId,
          scheduledDate: trip.scheduledDate,
          pickup: trip.pickupLocation,
          drop: trip.dropLocation,
          vehicleInfo: trip.vehicleInfo,
          driverInfo: trip.driverInfo
        }))
      }
    });

  } catch (error) {
    console.error('Enhanced customer stats error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while fetching enhanced statistics',
      error: error.message
    });
  }
});

// @route   POST /api/customer/feedback/submit
// @desc    Submit customer feedback for trip or service
// @access  Private (Customer)
router.post('/feedback/submit', [
  body('type').isIn(['trip', 'service', 'driver', 'vehicle']).withMessage('Invalid feedback type'),
  body('rating').isInt({ min: 1, max: 5 }).withMessage('Rating must be between 1-5'),
  body('comment').optional().isLength({ max: 500 }).withMessage('Comment too long'),
  body('tripId').optional().notEmpty().withMessage('Trip ID required for trip feedback'),
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: errors.array().map(err => err.msg)
      });
    }

    const customerId = req.user.email;
    const { type, rating, comment, tripId, driverId, vehicleId, category } = req.body;

    // Validate trip exists if tripId provided
    if (tripId) {
      const trip = await req.db.collection('trips').findOne({
        tripId: tripId,
        customerId: customerId
      });

      if (!trip) {
        return res.status(404).json({
          success: false,
          message: 'Trip not found or access denied'
        });
      }
    }

    // Create feedback document
    const feedbackData = {
      customerId,
      customerEmail: req.user.email,
      type,
      rating,
      comment: comment || '',
      tripId: tripId || null,
      driverId: driverId || null,
      vehicleId: vehicleId || null,
      category: category || 'general',
      status: 'submitted',
      createdAt: new Date(),
      updatedAt: new Date()
    };

    // Insert feedback
    const result = await req.db.collection('feedback').insertOne(feedbackData);

    // Update trip rating if applicable
    if (tripId && type === 'trip') {
      await req.db.collection('trips').updateOne(
        { tripId: tripId },
        { 
          $set: { 
            customerRating: rating,
            customerFeedback: comment,
            feedbackSubmittedAt: new Date()
          }
        }
      );
    }

    // Update driver rating if applicable
    if (driverId && type === 'driver') {
      await req.db.collection('drivers').updateOne(
        { driverId: driverId },
        { 
          $push: { 
            ratings: {
              customerId,
              rating,
              comment,
              submittedAt: new Date()
            }
          }
        }
      );
    }

    res.status(201).json({
      success: true,
      message: 'Feedback submitted successfully',
      data: {
        feedbackId: result.insertedId,
        ...feedbackData
      }
    });

  } catch (error) {
    console.error('Submit feedback error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while submitting feedback',
      error: error.message
    });
  }
});

// @route   GET /api/customer/preferences
// @desc    Get customer preferences and settings
// @access  Private (Customer)
router.get('/preferences', async (req, res) => {
  try {
    const customerId = req.user.email;

    // Get customer preferences
    let preferences = await req.db.collection('customer_preferences').findOne({
      customerId: customerId
    });

    // Create default preferences if none exist
    if (!preferences) {
      const defaultPreferences = {
        customerId,
        notifications: {
          email: true,
          sms: true,
          push: true,
          tripReminders: true,
          statusUpdates: true,
          promotions: false
        },
        privacy: {
          shareLocation: true,
          shareContactInfo: false,
          allowRating: true
        },
        booking: {
          defaultPickupLocation: null,
          defaultDropLocation: null,
          preferredVehicleType: null,
          preferredDriver: null,
          autoConfirmBookings: false
        },
        accessibility: {
          wheelchairAccess: false,
          visualImpairment: false,
          hearingImpairment: false,
          specialRequests: ''
        },
        createdAt: new Date(),
        updatedAt: new Date()
      };

      const result = await req.db.collection('customer_preferences').insertOne(defaultPreferences);
      preferences = { ...defaultPreferences, _id: result.insertedId };
    }

    res.json({
      success: true,
      data: preferences
    });

  } catch (error) {
    console.error('Get preferences error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while fetching preferences',
      error: error.message
    });
  }
});

// @route   PUT /api/customer/preferences
// @desc    Update customer preferences
// @access  Private (Customer)
router.put('/preferences', [
  body('notifications').optional().isObject().withMessage('Notifications must be an object'),
  body('privacy').optional().isObject().withMessage('Privacy must be an object'),
  body('booking').optional().isObject().withMessage('Booking must be an object'),
  body('accessibility').optional().isObject().withMessage('Accessibility must be an object'),
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: errors.array().map(err => err.msg)
      });
    }

    const customerId = req.user.email;
    const updateData = {
      ...req.body,
      updatedAt: new Date()
    };

    // Update preferences
    const result = await req.db.collection('customer_preferences').updateOne(
      { customerId: customerId },
      { $set: updateData },
      { upsert: true }
    );

    // Get updated preferences
    const updatedPreferences = await req.db.collection('customer_preferences').findOne({
      customerId: customerId
    });

    res.json({
      success: true,
      message: 'Preferences updated successfully',
      data: updatedPreferences
    });

  } catch (error) {
    console.error('Update preferences error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while updating preferences',
      error: error.message
    });
  }
});

// @route   GET /api/customer/trip-history/detailed
// @desc    Get detailed trip history with analytics
// @access  Private (Customer)
router.get('/trip-history/detailed', [
  query('page').optional().isInt({ min: 1 }).withMessage('Page must be positive integer'),
  query('limit').optional().isInt({ min: 1, max: 50 }).withMessage('Limit must be 1-50'),
  query('status').optional().isIn(['all', 'completed', 'cancelled', 'scheduled', 'in_progress']),
  query('dateFrom').optional().isISO8601().withMessage('Invalid date format'),
  query('dateTo').optional().isISO8601().withMessage('Invalid date format'),
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: errors.array().map(err => err.msg)
      });
    }

    const customerId = req.user.email;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const skip = (page - 1) * limit;

    // Build filter
    let filter = { customerId: customerId };
    
    if (req.query.status && req.query.status !== 'all') {
      filter.status = req.query.status;
    }
    
    if (req.query.dateFrom || req.query.dateTo) {
      filter.scheduledDate = {};
      if (req.query.dateFrom) {
        filter.scheduledDate.$gte = new Date(req.query.dateFrom);
      }
      if (req.query.dateTo) {
        filter.scheduledDate.$lte = new Date(req.query.dateTo);
      }
    }

    // Get trips with detailed information
    const trips = await req.db.collection('trips').find(filter)
      .sort({ scheduledDate: -1 })
      .skip(skip)
      .limit(limit)
      .toArray();

    // Get total count
    const total = await req.db.collection('trips').countDocuments(filter);

    // Enhance trips with additional details
    const enhancedTrips = await Promise.all(
      trips.map(async (trip) => {
        // Get driver details if available
        let driverDetails = null;
        if (trip.driverId) {
          driverDetails = await req.db.collection('drivers').findOne(
            { driverId: trip.driverId },
            { projection: { 'personalInfo.firstName': 1, 'personalInfo.lastName': 1, 'personalInfo.phone': 1 } }
          );
        }

        // Get vehicle details if available
        let vehicleDetails = null;
        if (trip.vehicleId) {
          vehicleDetails = await req.db.collection('vehicles').findOne(
            { vehicleId: trip.vehicleId },
            { projection: { registrationNumber: 1, make: 1, model: 1, type: 1 } }
          );
        }

        return {
          ...trip,
          driverDetails: driverDetails ? {
            name: `${driverDetails.personalInfo?.firstName || ''} ${driverDetails.personalInfo?.lastName || ''}`.trim(),
            phone: driverDetails.personalInfo?.phone
          } : null,
          vehicleDetails: vehicleDetails ? {
            registrationNumber: vehicleDetails.registrationNumber,
            makeModel: `${vehicleDetails.make || ''} ${vehicleDetails.model || ''}`.trim(),
            type: vehicleDetails.type
          } : null
        };
      })
    );

    res.json({
      success: true,
      data: {
        trips: enhancedTrips,
        pagination: {
          current: page,
          pages: Math.ceil(total / limit),
          total,
          limit
        },
        summary: {
          totalTrips: total,
          completedTrips: enhancedTrips.filter(t => t.status === 'completed').length,
          cancelledTrips: enhancedTrips.filter(t => t.status === 'cancelled').length,
          scheduledTrips: enhancedTrips.filter(t => t.status === 'scheduled').length
        }
      }
    });

  } catch (error) {
    console.error('Detailed trip history error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while fetching trip history',
      error: error.message
    });
  }
});

module.exports = router;