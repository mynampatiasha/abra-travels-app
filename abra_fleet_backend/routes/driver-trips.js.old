// File: routes/driver/trips.js
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

// Get driver's active trip
router.get('/active', async (req, res) => {
  try {
    const driverId = req.user.email; // From Firebase auth token
    const db = req.db;

    // Find active trip for this driver
    const activeTrip = await db.collection('trips').findOne({
      driverId: driverId,
      status: { $in: ['in_progress', 'started', 'on_route', 'delayed', 'waiting'] },
    });

    if (!activeTrip) {
      return res.json({
        status: 'success',
        data: null,
        message: 'No active trip found'
      });
    }

    // Get additional details if needed (customer info, vehicle info)
    const customer = await db.collection('customers').findOne({
      _id: new ObjectId(activeTrip.customerId)
    });

    const vehicle = await db.collection('vehicles').findOne({
      _id: new ObjectId(activeTrip.vehicleId)
    });

    res.json({
      status: 'success',
      data: {
        trip: {
          id: activeTrip._id,
          tripNumber: activeTrip.tripNumber || `TR-${activeTrip._id.toString().slice(-4).toUpperCase()}`,
          from: activeTrip.pickupLocation || activeTrip.origin,
          to: activeTrip.dropoffLocation || activeTrip.destination,
          distance: activeTrip.distance || 0,
          customers: activeTrip.passengers || activeTrip.customerCount || 1,
          status: activeTrip.status,
          startTime: activeTrip.startTime,
          estimatedEndTime: activeTrip.estimatedEndTime,
          currentLocation: activeTrip.currentLocation
        },
        customer: customer ? {
          name: customer.name,
          phone: customer.phone
        } : null,
        vehicle: vehicle ? {
          registrationNumber: vehicle.registrationNumber,
          model: vehicle.model
        } : null
      }
    });
  } catch (error) {
    console.error('Error fetching active trip:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to fetch active trip',
      error: error.message
    });
  }
});

// Update trip status
router.patch('/update-status', async (req, res) => {
  try {
    const driverId = req.user.email;
    const { tripId, status } = req.body;
    const db = req.db;

    // Validate status
    const validStatuses = ['in_progress', 'on_route', 'delayed', 'waiting', 'completed'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({
        status: 'error',
        message: `Invalid status. Valid statuses are: ${validStatuses.join(', ')}`
      });
    }

    if (!tripId) {
      return res.status(400).json({
        status: 'error',
        message: 'Trip ID is required'
      });
    }

    // Verify trip belongs to driver and is active
    const trip = await db.collection('trips').findOne({
      _id: new ObjectId(tripId),
      driverId: driverId,
      status: { $in: ['in_progress', 'started', 'on_route', 'delayed', 'waiting'] }
    });

    if (!trip) {
      return res.status(404).json({
        status: 'error',
        message: 'Active trip not found or unauthorized'
      });
    }

    // Update trip status
    const updateData = {
      status: status,
      lastStatusUpdate: new Date(),
      updatedAt: new Date()
    };

    // Add status history
    const statusHistory = {
      status: status,
      timestamp: new Date(),
      updatedBy: driverId,
      previousStatus: trip.status
    };

    await db.collection('trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: updateData,
        $push: {
          statusHistory: statusHistory
        }
      }
    );

    // Notify via WebSocket
    const wsServer = req.app.get('wsServer');
    if (wsServer) {
      wsServer.clients.forEach((client) => {
        if (client.readyState === 1) { // WebSocket.OPEN
          client.send(JSON.stringify({
            type: 'trip_status_updated',
            tripId: tripId,
            driverId: driverId,
            status: status,
            previousStatus: trip.status,
            timestamp: new Date()
          }));
        }
      });
    }

    res.json({
      status: 'success',
      message: 'Trip status updated successfully',
      data: {
        tripId,
        status,
        previousStatus: trip.status,
        updatedAt: updateData.updatedAt
      }
    });
  } catch (error) {
    console.error('Error updating trip status:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to update trip status',
      error: error.message
    });
  }
});

// Share location with customer
router.post('/share-location', async (req, res) => {
  try {
    const driverId = req.user.email;
    const { tripId, latitude, longitude } = req.body;
    const db = req.db;

    if (!tripId || !latitude || !longitude) {
      return res.status(400).json({
        status: 'error',
        message: 'Trip ID and location coordinates are required'
      });
    }

    // Verify trip belongs to driver
    const trip = await db.collection('trips').findOne({
      _id: new ObjectId(tripId),
      driverId: driverId,
      status: { $in: ['in_progress', 'started', 'on_route', 'delayed', 'waiting'] }
    });

    if (!trip) {
      return res.status(404).json({
        status: 'error',
        message: 'Active trip not found'
      });
    }

    // Update trip with current location
    await db.collection('trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: {
          currentLocation: {
            type: 'Point',
            coordinates: [longitude, latitude]
          },
          lastLocationUpdate: new Date(),
          locationShared: true
        }
      }
    );

    // Send notification to customer (implement based on your notification system)
    const wsServer = req.app.get('wsServer');
    if (wsServer && trip.customerId) {
      wsServer.clients.forEach((client) => {
        if (client.readyState === 1) { // WebSocket.OPEN
          client.send(JSON.stringify({
            type: 'location_update',
            tripId: tripId,
            customerId: trip.customerId,
            location: { latitude, longitude },
            timestamp: new Date()
          }));
        }
      });
    }

    res.json({
      status: 'success',
      message: 'Location shared successfully',
      data: {
        tripId,
        location: { latitude, longitude },
        timestamp: new Date()
      }
    });
  } catch (error) {
    console.error('Error sharing location:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to share location',
      error: error.message
    });
  }
});

// End trip
router.post('/end-trip', async (req, res) => {
  try {
    const driverId = req.user.email;
    const { tripId, endLocation, finalOdometer } = req.body;
    const db = req.db;

    if (!tripId) {
      return res.status(400).json({
        status: 'error',
        message: 'Trip ID is required'
      });
    }

    // Verify trip belongs to driver and is active
    const trip = await db.collection('trips').findOne({
      _id: new ObjectId(tripId),
      driverId: driverId,
      status: { $in: ['in_progress', 'started', 'on_route', 'delayed', 'waiting'] }
    });

    if (!trip) {
      return res.status(404).json({
        status: 'error',
        message: 'Active trip not found or already completed'
      });
    }

    const endTime = new Date();
    const duration = endTime - new Date(trip.startTime);

    // Update trip status
    const updateData = {
      status: 'completed',
      endTime: endTime,
      duration: duration,
      completedAt: endTime
    };

    if (endLocation) {
      updateData.endLocation = endLocation;
    }

    if (finalOdometer) {
      updateData.finalOdometer = finalOdometer;
      updateData.actualDistance = finalOdometer - (trip.startOdometer || 0);
    }

    // Add to status history
    const statusHistory = {
      status: 'completed',
      timestamp: endTime,
      updatedBy: driverId,
      previousStatus: trip.status
    };

    await db.collection('trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: updateData,
        $push: {
          statusHistory: statusHistory
        }
      }
    );

    // Update vehicle availability
    if (trip.vehicleId) {
      await db.collection('vehicles').updateOne(
        { _id: new ObjectId(trip.vehicleId) },
        { 
          $set: { 
            status: 'available',
            currentTripId: null,
            lastTripEndTime: endTime
          } 
        }
      );
    }

    // Update driver availability
    await db.collection('drivers').updateOne(
      { email: driverId  },
      {
        $set: {
          status: 'available',
          currentTripId: null,
          lastTripEndTime: endTime
        },
        $inc: {
          totalTrips: 1,
          totalDistance: updateData.actualDistance || trip.distance || 0
        }
      }
    );

    // Notify via WebSocket
    const wsServer = req.app.get('wsServer');
    if (wsServer) {
      wsServer.clients.forEach((client) => {
        if (client.readyState === 1) {
          client.send(JSON.stringify({
            type: 'trip_ended',
            tripId: tripId,
            driverId: driverId,
            endTime: endTime,
            duration: Math.round(duration / 1000 / 60) // minutes
          }));
        }
      });
    }

    res.json({
      status: 'success',
      message: 'Trip ended successfully',
      data: {
        tripId,
        endTime,
        duration: Math.round(duration / 1000 / 60), // minutes
        ...updateData
      }
    });
  } catch (error) {
    console.error('Error ending trip:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to end trip',
      error: error.message
    });
  }
});

// Get trip details
router.get('/:tripId', async (req, res) => {
  try {
    const driverId = req.user.email;
    const { tripId } = req.params;
    const db = req.db;

    const trip = await db.collection('trips').findOne({
      _id: new ObjectId(tripId),
      driverId: driverId
    });

    if (!trip) {
      return res.status(404).json({
        status: 'error',
        message: 'Trip not found'
      });
    }

    res.json({
      status: 'success',
      data: trip
    });
  } catch (error) {
    console.error('Error fetching trip details:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to fetch trip details',
      error: error.message
    });
  }
});

// Get driver's trip history
router.get('/history', async (req, res) => {
  try {
    const driverId = req.user.email;
    const { page = 1, limit = 20, status } = req.query;
    const db = req.db;

    const query = { driverId: driverId };
    if (status) {
      query.status = status;
    }

    const trips = await db.collection('trips')
      .find(query)
      .sort({ startTime: -1 })
      .skip((page - 1) * limit)
      .limit(parseInt(limit))
      .toArray();

    const total = await db.collection('trips').countDocuments(query);

    res.json({
      status: 'success',
      data: {
        trips,
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total,
          totalPages: Math.ceil(total / limit)
        }
      }
    });
  } catch (error) {
    console.error('Error fetching trip history:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to fetch trip history',
      error: error.message
    });
  }
});

// Update trip location (continuous tracking)
router.post('/update-location', async (req, res) => {
  try {
    const driverId = req.user.email;
    const { tripId, latitude, longitude, speed, heading } = req.body;
    const db = req.db;

    if (!tripId || !latitude || !longitude) {
      return res.status(400).json({
        status: 'error',
        message: 'Trip ID and location coordinates are required'
      });
    }

    const locationData = {
      type: 'Point',
      coordinates: [longitude, latitude],
      timestamp: new Date()
    };

    if (speed !== undefined) locationData.speed = speed;
    if (heading !== undefined) locationData.heading = heading;

    // Update trip location
    await db.collection('trips').updateOne(
      { 
        _id: new ObjectId(tripId),
        driverId: driverId 
      },
      {
        $set: {
          currentLocation: locationData,
          lastLocationUpdate: new Date()
        },
        $push: {
          locationHistory: {
            $each: [locationData],
            $slice: -100 // Keep last 100 locations
          }
        }
      }
    );

    // Broadcast to WebSocket clients
    const wsServer = req.app.get('wsServer');
    if (wsServer) {
      wsServer.clients.forEach((client) => {
        if (client.readyState === 1) {
          client.send(JSON.stringify({
            type: 'driver_location_update',
            tripId: tripId,
            driverId: driverId,
            location: { latitude, longitude, speed, heading },
            timestamp: new Date()
          }));
        }
      });
    }

    res.json({
      status: 'success',
      message: 'Location updated successfully'
    });
  } catch (error) {
    console.error('Error updating location:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to update location',
      error: error.message
    });
  }
});

module.exports = router;