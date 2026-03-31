// File: routes/live_tracking_routes.js
// ENHANCED LOCATION TRACKING WITH MULTI-TRIP SUPPORT

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');

/**
 * @route   POST /api/tracking/driver/location
 * @desc    Update driver location (works for all active trips)
 * @access  Private (Driver)
 */
router.post('/driver/location', verifyToken, async (req, res) => {
  try {
    const {
      latitude,
      longitude,
      speed,
      heading,
      accuracy,
      altitude,
      vehicleId
    } = req.body;

    if (!latitude || !longitude) {
      return res.status(400).json({
        success: false,
        message: 'Latitude and longitude are required'
      });
    }

    const driverId = req.user.email;
    const timestamp = new Date();

    // GeoJSON format
    const locationData = {
      type: 'Point',
      coordinates: [longitude, latitude]
    };

    const locationUpdate = {
      driverId,
      vehicleId: vehicleId || null,
      location: locationData,
      latitude,
      longitude,
      speed: speed || 0,
      heading: heading || 0,
      accuracy: accuracy || 0,
      altitude: altitude || 0,
      timestamp,
      isOnline: true,
      lastSeen: timestamp
    };

    // Store in location_history
    await req.db.collection('location_history').insertOne(locationUpdate);

    // Update driver's current location
    await req.db.collection('users').updateOne(
      { _id: driverId },
      {
        $set: {
          currentLocation: locationData,
          lastLocationUpdate: timestamp,
          'locationData.latitude': latitude,
          'locationData.longitude': longitude,
          'locationData.speed': speed,
          'locationData.heading': heading,
          'locationData.accuracy': accuracy,
          'locationData.isOnline': true,
          'locationData.lastSeen': timestamp,
          updatedAt: timestamp
        }
      }
    );

    // Update vehicle location
    if (vehicleId) {
      await req.db.collection('vehicles').updateOne(
        { _id: new ObjectId(vehicleId) },
        {
          $set: {
            currentLocation: locationData,
            lastLocationUpdate: timestamp,
            updatedAt: timestamp
          }
        }
      );
    }

    // Find ALL active trips for this driver
    const activeTrips = await req.db.collection('trips').find({
      driverId: driverId,
      status: { $in: ['assigned', 'started', 'in_progress'] }
    }).toArray();

    // Update location for ALL active trips
    const tripUpdatePromises = activeTrips.map(trip =>
      req.db.collection('trips').updateOne(
        { _id: trip._id },
        {
          $set: {
            currentLocation: locationData,
            updatedAt: timestamp
          },
          $push: {
            locationHistory: {
              $each: [locationUpdate],
              $slice: -1000
            }
          }
        }
      )
    );

    await Promise.all(tripUpdatePromises);

    // Broadcast via WebSocket
    const wsServer = req.app.get('wsServer');
    if (wsServer) {
      activeTrips.forEach(trip => {
        wsServer.sendLocationUpdate(trip.tripNumber || trip._id.toString(), {
          tripId: trip.tripNumber || trip._id.toString(),
          driverId,
          vehicleId,
          location: {
            latitude,
            longitude,
            speed,
            heading,
            accuracy,
            timestamp: timestamp.toISOString()
          },
          tripStatus: trip.status
        });
      });
    }

    res.json({
      success: true,
      message: 'Location updated successfully',
      data: {
        updatedTrips: activeTrips.length,
        location: {
          latitude,
          longitude,
          timestamp: timestamp.toISOString()
        }
      }
    });

  } catch (error) {
    console.error('❌ Error updating driver location:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update location',
      error: error.message
    });
  }
});

/**
 * @route   GET /api/tracking/driver/:driverId/location
 * @desc    Get driver's current location
 * @access  Private
 */
router.get('/driver/:driverId/location', verifyToken, async (req, res) => {
  try {
    const { driverId } = req.params;

    const driver = await req.db.collection('users').findOne({ _id: driverId });

    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }

    res.json({
      success: true,
      data: {
        driverId,
        currentLocation: driver.currentLocation,
        locationData: driver.locationData,
        lastUpdate: driver.lastLocationUpdate
      }
    });

  } catch (error) {
    console.error('❌ Error getting driver location:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get driver location',
      error: error.message
    });
  }
});

/**
 * @route   GET /api/tracking/trip/:tripId/location
 * @desc    Get current location for a specific trip
 * @access  Private
 */
router.get('/trip/:tripId/location', verifyToken, async (req, res) => {
  try {
    const { tripId } = req.params;

    const trip = await req.db.collection('trips').findOne({
      $or: [
        { _id: new ObjectId(tripId) },
        { tripNumber: tripId }
      ]
    });

    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }

    // Get driver details
    const driver = await req.db.collection('users').findOne({
      _id: trip.driverId
    });

    res.json({
      success: true,
      data: {
        tripId: trip.tripNumber || trip._id.toString(),
        currentLocation: trip.currentLocation,
        driver: driver ? {
          name: driver.name,
          phone: driver.phone,
          currentLocation: driver.currentLocation,
          locationData: driver.locationData,
          lastUpdate: driver.lastLocationUpdate
        } : null,
        status: trip.status,
        lastUpdate: trip.updatedAt
      }
    });

  } catch (error) {
    console.error('❌ Error getting trip location:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get trip location',
      error: error.message
    });
  }
});

/**
 * @route   GET /api/tracking/driver/:driverId/active-trips
 * @desc    Get all active trips for a driver
 * @access  Private
 */
router.get('/driver/:driverId/active-trips', verifyToken, async (req, res) => {
  try {
    const { driverId } = req.params;

    const trips = await req.db.collection('trips').find({
      driverId: driverId,
      status: { $in: ['assigned', 'started', 'in_progress'] }
    }).sort({ sequence: 1 }).toArray();

    res.json({
      success: true,
      data: {
        trips: trips.map(trip => ({
          tripId: trip.tripNumber || trip._id.toString(),
          rosterId: trip.rosterId,
          customerName: trip.customer?.name,
          sequence: trip.sequence,
          status: trip.status,
          pickupLocation: trip.pickupLocation,
          dropLocation: trip.dropLocation,
          currentLocation: trip.currentLocation,
          startTime: trip.startTime,
          scheduledDate: trip.scheduledDate
        })),
        count: trips.length
      }
    });

  } catch (error) {
    console.error('❌ Error getting active trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get active trips',
      error: error.message
    });
  }
});

/**
 * @route   GET /api/tracking/all-active-drivers
 * @desc    Get all active drivers (for admin map)
 * @access  Private (Admin)
 */
router.get('/all-active-drivers', verifyToken, async (req, res) => {
  try {
    const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);

    const activeDrivers = await req.db.collection('users').find({
      role: 'driver',
      'locationData.isOnline': true,
      lastLocationUpdate: { $gte: fiveMinutesAgo }
    }).toArray();

    res.json({
      success: true,
      data: {
        drivers: activeDrivers.map(driver => ({
          driverId: driver._id,
          name: driver.name,
          phone: driver.phone,
          email: driver.email,
          currentLocation: driver.currentLocation,
          locationData: driver.locationData,
          lastUpdate: driver.lastLocationUpdate
        })),
        count: activeDrivers.length
      }
    });

  } catch (error) {
    console.error('❌ Error getting active drivers:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get active drivers',
      error: error.message
    });
  }
});

/**
 * @route   POST /api/tracking/heartbeat
 * @desc    Driver heartbeat to mark as online
 * @access  Private (Driver)
 */
router.post('/heartbeat', verifyToken, async (req, res) => {
  try {
    const driverId = req.user.email;

    await req.db.collection('users').updateOne(
      { _id: driverId },
      {
        $set: {
          'locationData.isOnline': true,
          'locationData.lastSeen': new Date(),
          lastLocationUpdate: new Date()
        }
      }
    );

    res.json({
      success: true,
      message: 'Heartbeat received'
    });

  } catch (error) {
    console.error('❌ Heartbeat error:', error);
    res.status(500).json({
      success: false,
      message: 'Heartbeat failed',
      error: error.message
    });
  }
});

module.exports = router;