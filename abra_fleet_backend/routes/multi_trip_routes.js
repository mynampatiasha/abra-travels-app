// File: routes/multi_trip_routes.js
// MULTI-TRIP ASSIGNMENT ENDPOINTS (6-11 trips/day per vehicle)

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const TripModel = require('../models/trip_model');

// Middleware to initialize TripModel
router.use(async (req, res, next) => {
  try {
    // Use the MongoDB client and database from the middleware in index.js
    if (!req.mongoClient || !req.db) {
      return res.status(500).json({
        success: false,
        message: 'Database connection error',
        error: 'MongoDB client or database not available'
      });
    }
    
    req.tripModel = new TripModel(req.db);
    next();
  } catch (error) {
    console.error('Database connection error:', error);
    res.status(500).json({
      success: false,
      message: 'Database connection error',
      error: error.message,
    });
  }
});

/**
 * ✅ GET /api/trips/customer/all
 * Get all trips (active, completed, cancelled) for the authenticated customer
 */
router.get('/customer/all', async (req, res) => {
  try {
    const customerId = req.user.email;
    
    // Find all trips for this customer
    const allTrips = await req.db.collection('trips').find({
      $or: [
        { customerUid: customerId },
        { customerId: customerId },
        { 'customer.uid': customerId },
        { 'customer.customerId': customerId }
      ]
    }).sort({ createdAt: -1 }).toArray();

    res.json({
      success: true,
      data: allTrips.map(trip => ({
        _id: trip._id,
        tripId: trip.tripId || trip.tripNumber,
        tripNumber: trip.tripNumber,
        status: trip.status,
        pickupLocation: trip.pickupLocation,
        dropLocation: trip.dropLocation,
        driverName: trip.driverName || trip.driver?.name,
        driverPhone: trip.driverPhone || trip.driver?.phone,
        vehicleNumber: trip.vehicleNumber || trip.vehicle?.registrationNumber,
        scheduledDate: trip.scheduledDate,
        startTime: trip.startTime,
        endTime: trip.endTime,
        actualStartTime: trip.actualStartTime,
        actualEndTime: trip.actualEndTime,
        distance: trip.distance,
        estimatedDuration: trip.estimatedDuration,
        tripType: trip.tripType,
        organizationName: trip.organizationName,
        createdAt: trip.createdAt,
        updatedAt: trip.updatedAt
      })),
      count: allTrips.length
    });

  } catch (error) {
    console.error('❌ Error getting customer trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get customer trips',
      error: error.message
    });
  }
});

/**
 * ✅ GET /api/trips/customer/active
 * Get active trips for the authenticated customer
 */
router.get('/customer/active', async (req, res) => {
  try {
    console.log('📥 GET /api/trips/customer/active');
    
    if (!req.user || !req.user.email) {
      console.error('❌ No user in request');
      return res.status(401).json({
        success: false,
        message: 'User not authenticated'
      });
    }
    
    const customerId = req.user.email;
    console.log(`🔍 Looking for active trips for customer: ${customerId}`);
    
    // Find active trips for this customer
    const activeTrips = await req.db.collection('trips').find({
      $or: [
        { customerUid: customerId },
        { customerId: customerId },
        { 'customer.uid': customerId }
      ],
      status: { $in: ['ongoing', 'assigned', 'started', 'in_progress'] }
    }).sort({ createdAt: -1 }).toArray();

    console.log(`✅ Found ${activeTrips.length} active trips`);

    res.json({
      success: true,
      data: activeTrips.map(trip => ({
        _id: trip._id,
        tripId: trip.tripId || trip.tripNumber,
        tripNumber: trip.tripNumber,
        status: trip.status,
        pickupLocation: trip.pickupLocation,
        dropLocation: trip.dropLocation,
        driverName: trip.driverName,
        driverPhone: trip.driverPhone,
        vehicleNumber: trip.vehicleNumber,
        scheduledTime: trip.scheduledTime,
        startTime: trip.startTime,
        currentLocation: trip.currentLocation
      })),
      count: activeTrips.length
    });

  } catch (error) {
    console.error('❌ Error getting customer active trips:', error);
    console.error('Stack:', error.stack);
    res.status(500).json({
      success: false,
      message: 'Failed to get active trips',
      error: error.message
    });
  }
});

/**
 * ✅ POST /api/trips/assign-from-roster
 * Create trip from roster assignment (called after route optimization)
 */
router.post('/assign-from-roster', async (req, res) => {
  try {
    const {
      rosterId,
      vehicleId,
      driverId,
      customerId,
      customerName,
      customerEmail,
      customerPhone,
      pickupLocation,
      dropLocation,
      scheduledDate,
      startTime,
      endTime,
      distance,
      estimatedDuration,
      tripType,
      sequence,
      organizationId,
      organizationName,
    } = req.body;

    // Validate required fields
    if (!rosterId || !vehicleId || !driverId || !customerId || !scheduledDate || !startTime || !endTime) {
      return res.status(400).json({
        success: false,
        message: 'Missing required fields',
      });
    }

    // ✅ CRITICAL: Check if vehicle can take this trip
    const validation = await req.tripModel.canVehicleTakeTrip(
      vehicleId,
      scheduledDate,
      startTime,
      endTime
    );

    if (!validation.canTakeTrip) {
      return res.status(409).json({
        success: false,
        message: validation.reason,
        currentTrips: validation.currentTrips,
        conflictingTrip: validation.conflictingTrip,
      });
    }

    // Create trip
    const trip = await req.tripModel.createFromRosterAssignment({
      rosterId,
      vehicleId,
      driverId,
      customerId,
      customerName,
      customerEmail,
      customerPhone,
      pickupLocation,
      dropLocation,
      scheduledDate,
      startTime,
      endTime,
      distance,
      estimatedDuration,
      tripType,
      sequence,
      organizationId,
      organizationName,
      assignedBy: req.user?.id || 'system',
    });

    // Update roster status to "assigned"
    await req.db.collection('roster_requests').updateOne(
      { _id: new ObjectId(rosterId) },
      {
        $set: {
          status: 'assigned',
          assignedVehicle: vehicleId,
          assignedDriver: driverId,
          tripId: trip._id.toString(),
          updatedAt: new Date(),
        },
      }
    );

    res.status(201).json({
      success: true,
      message: 'Trip assigned successfully',
      data: trip,
      vehicleTrips: validation.currentTrips + 1,
    });
  } catch (error) {
    console.error('Error assigning trip:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to assign trip',
      error: error.message,
    });
  }
});

/**
 * ✅ GET /api/trips/vehicle/:vehicleId/date/:date
 * Get all trips for a vehicle on a specific date
 */
router.get('/vehicle/:vehicleId/date/:date', async (req, res) => {
  try {
    const { vehicleId, date } = req.params;

    const trips = await req.tripModel.getVehicleTripsForDate(vehicleId, date);

    res.json({
      success: true,
      data: trips,
      count: trips.length,
      date,
      vehicleId,
    });
  } catch (error) {
    console.error('Error getting vehicle trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get vehicle trips',
      error: error.message,
    });
  }
});

/**
 * ✅ GET /api/trips/driver/:driverId/today
 * Get today's trips for driver (used in driver dashboard)
 */
router.get('/driver/:driverId/today', async (req, res) => {
  try {
    const { driverId } = req.params;

    const trips = await req.tripModel.getDriverTodayTrips(driverId);

    // Get vehicle details for each trip
    const tripsWithDetails = await Promise.all(
      trips.map(async (trip) => {
        const vehicle = await req.db.collection('vehicles').findOne(
          { _id: new ObjectId(trip.vehicleId) }
        );

        return {
          ...trip,
          vehicle: vehicle
            ? {
                registrationNumber: vehicle.registrationNumber,
                model: vehicle.model,
                make: vehicle.make,
              }
            : null,
        };
      })
    );

    res.json({
      success: true,
      data: tripsWithDetails,
      count: tripsWithDetails.length,
      summary: {
        totalCustomers: tripsWithDetails.length,
        totalDistance: tripsWithDetails.reduce((sum, t) => sum + (t.distance || 0), 0),
        completedCount: tripsWithDetails.filter(t => t.status === 'completed').length,
      },
    });
  } catch (error) {
    console.error('Error getting driver today trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get driver trips',
      error: error.message,
    });
  }
});

/**
 * ✅ POST /api/trips/:tripId/status
 * Update trip status (assigned → started → in_progress → completed)
 */
router.post('/:tripId/status', async (req, res) => {
  try {
    const { tripId } = req.params;
    const { status, notes } = req.body;

    if (!['assigned', 'started', 'in_progress', 'completed', 'cancelled'].includes(status)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid status. Must be: assigned, started, in_progress, completed, or cancelled',
      });
    }

    const trip = await req.tripModel.updateStatus(tripId, status, { notes });

    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found',
      });
    }

    res.json({
      success: true,
      message: `Trip status updated to ${status}`,
      data: trip,
    });
  } catch (error) {
    console.error('Error updating trip status:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update trip status',
      error: error.message,
    });
  }
});

/**
 * ✅ POST /api/trips/:tripId/location
 * Share driver location (real-time tracking)
 */
router.post('/:tripId/location', async (req, res) => {
  try {
    const { tripId } = req.params;
    const { latitude, longitude, speed, heading } = req.body;

    if (!latitude || !longitude) {
      return res.status(400).json({
        success: false,
        message: 'Latitude and longitude are required',
      });
    }

    const trip = await req.tripModel.updateLocation(tripId, {
      latitude,
      longitude,
      speed,
      heading,
    });

    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found',
      });
    }

    res.json({
      success: true,
      message: 'Location updated successfully',
      data: {
        tripId: trip.tripId || trip.tripNumber,
        currentLocation: trip.currentLocation,
      },
    });
  } catch (error) {
    console.error('Error updating location:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update location',
      error: error.message,
    });
  }
});

/**
 * ✅ GET /api/trips/check-availability
 * Check if vehicle is available for a time slot
 */
router.get('/check-availability', async (req, res) => {
  try {
    const { vehicleId, scheduledDate, startTime, endTime } = req.query;

    if (!vehicleId || !scheduledDate || !startTime || !endTime) {
      return res.status(400).json({
        success: false,
        message: 'Missing required parameters: vehicleId, scheduledDate, startTime, endTime',
      });
    }

    const validation = await req.tripModel.canVehicleTakeTrip(
      vehicleId,
      scheduledDate,
      startTime,
      endTime
    );

    res.json({
      success: true,
      data: validation,
    });
  } catch (error) {
    console.error('Error checking availability:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to check availability',
      error: error.message,
    });
  }
});

/**
 * ✅ POST /api/trips/batch-assign
 * Batch create trips (used in route optimization)
 */
router.post('/batch-assign', async (req, res) => {
  const session = client.startSession();
  try {
    const { trips } = req.body;

    if (!Array.isArray(trips) || trips.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Trips array is required',
      });
    }

    session.startTransaction();

    const results = [];
    const errors = [];

    for (const tripData of trips) {
      try {
        // Validate time slot
        const validation = await req.tripModel.canVehicleTakeTrip(
          tripData.vehicleId,
          tripData.scheduledDate,
          tripData.startTime,
          tripData.endTime
        );

        if (!validation.canTakeTrip) {
          errors.push({
            rosterId: tripData.rosterId,
            reason: validation.reason,
          });
          continue;
        }

        // Create trip
        const trip = await req.tripModel.createFromRosterAssignment({
          ...tripData,
          assignedBy: req.user?.id || 'system',
        });

        results.push(trip);
      } catch (error) {
        errors.push({
          rosterId: tripData.rosterId,
          error: error.message,
        });
      }
    }

    await session.commitTransaction();

    res.status(201).json({
      success: true,
      message: `Assigned ${results.length} trips successfully`,
      data: {
        successful: results,
        failed: errors,
      },
      stats: {
        total: trips.length,
        successful: results.length,
        failed: errors.length,
      },
    });
  } catch (error) {
    await session.abortTransaction();
    console.error('Error batch assigning trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to batch assign trips',
      error: error.message,
    });
  } finally {
    await session.endSession();
  }
});

/**
 * ✅ GET /api/trips/statistics
 * Get trip statistics (for dashboard)
 */
router.get('/statistics', async (req, res) => {
  try {
    const { driverId, vehicleId, dateFrom, dateTo } = req.query;

    const stats = await req.tripModel.getTripStatistics({
      driverId,
      vehicleId,
      dateFrom,
      dateTo,
    });

    res.json({
      success: true,
      data: stats,
    });
  } catch (error) {
    console.error('Error getting trip statistics:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get trip statistics',
      error: error.message,
    });
  }
});

module.exports = router;