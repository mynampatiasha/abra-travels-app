const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const createWebSocketServer = require('../websocket');

let wsServer;

// Initialize WebSocket server
function initWebSocket(server) {
  if (!wsServer) {
    wsServer = createWebSocketServer(server);
  }
  return wsServer;
}

// Middleware to ensure WebSocket is initialized
function checkWebSocketInitialized(req, res, next) {
  if (!wsServer) {
    return res.status(500).json({
      success: false,
      message: 'WebSocket server not initialized'
    });
  }
  next();
}

/**
 * @swagger
 * /api/tracking/location/{tripId}:
 *   post:
 *     summary: Update trip location (for drivers)
 *     tags: [Tracking]
 *     parameters:
 *       - in: path
 *         name: tripId
 *         required: true
 *         schema:
 *           type: string
 *         description: Trip ID or tripId
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - latitude
 *               - longitude
 *             properties:
 *               latitude:
 *                 type: number
 *               longitude:
 *                 type: number
 *               accuracy:
 *                 type: number
 *               speed:
 *                 type: number
 *               heading:
 *                 type: number
 *               timestamp:
 *                 type: string
 *                 format: date-time
 *     responses:
 *       200:
 *         description: Location updated successfully
 *       400:
 *         description: Invalid input
 *       404:
 *         description: Trip not found
 *       500:
 *         description: Server error
 */
router.post('/location/:tripId', checkWebSocketInitialized, async (req, res) => {
  const session = req.mongoClient.startSession();
  try {
    const { tripId } = req.params;
    const { latitude, longitude, accuracy, speed, heading, timestamp } = req.body;

    // Input validation
    if (!latitude || !longitude) {
      return res.status(400).json({
        success: false,
        message: 'Latitude and longitude are required'
      });
    }

    // Start transaction
    session.startTransaction();

    // Find the trip
    const trip = await req.db.collection('trips').findOne(
      {
        $or: [
          { _id: new ObjectId(tripId) },
          { tripId: tripId },
          { tripNumber: tripId } // Backward compatibility
        ]
      },
      { session }
    );

    if (!trip) {
      await session.abortTransaction();
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }

    // Prepare location data
    const locationData = {
      type: 'Point',
      coordinates: [longitude, latitude],
      timestamp: timestamp ? new Date(timestamp) : new Date(),
      accuracy,
      speed,
      heading
    };

    // Update trip with new location
    await req.db.collection('trips').updateOne(
      { _id: trip._id },
      {
        $set: {
          currentLocation: locationData,
          updatedAt: new Date()
        },
        $push: {
          'tracking.locations': {
            $each: [locationData],
            $slice: -1000 // Keep last 1000 locations
          }
        }
      },
      { session }
    );

    // Update vehicle's current location
    if (trip.vehicle?.vehicleId) {
      await req.db.collection('vehicles').updateOne(
        { vehicleId: trip.vehicle.vehicleId },
        {
          $set: {
            currentLocation: locationData,
            updatedAt: new Date()
          }
        },
        { session }
      );
    }

    // Update driver's current location
    if (trip.driver?.driverId) {
      await req.db.collection('drivers').updateOne(
        { driverId: trip.driver.driverId },
        {
          $set: {
            currentLocation: locationData,
            updatedAt: new Date()
          }
        },
        { session }
      );
    }

    await session.commitTransaction();

    // Broadcast location update to all connected clients
    wsServer.sendLocationUpdate(trip.tripId || trip._id.toString(), {
      tripId: trip.tripId || trip._id.toString(),
      location: {
        latitude,
        longitude,
        accuracy,
        speed,
        heading,
        timestamp: locationData.timestamp
      },
      tripStatus: trip.status
    });

    res.json({
      success: true,
      message: 'Location updated successfully'
    });
  } catch (error) {
    await session.abortTransaction();
    console.error('Error updating location:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update location',
      error: error.message
    });
  } finally {
    await session.endSession();
  }
});

/**
 * @swagger
 * /api/tracking/trip/{tripId}/location:
 *   get:
 *     summary: Get current trip location (for customers/admins)
 *     tags: [Tracking]
 *     parameters:
 *       - in: path
 *         name: tripId
 *         required: true
 *         schema:
 *           type: string
 *         description: Trip ID or tripId
 *     responses:
 *       200:
 *         description: Trip location retrieved successfully
 *       404:
 *         description: Trip not found
 *       500:
 *         description: Server error
 */
router.get('/trip/:tripId/location', async (req, res) => {
  try {
    const { tripId } = req.params;

    // Find the trip
    const trip = await req.db.collection('trips').findOne({
        $or: [
          { _id: new ObjectId(tripId) },
          { tripId: tripId },
          { tripNumber: tripId } // Backward compatibility
        ]
      });

    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }

    // Return trip location data
    res.json({
      success: true,
      data: {
        tripId: trip.tripId || trip._id.toString(),
        currentLocation: trip.currentLocation || null,
        status: trip.status,
        driver: trip.driver ? {
          name: trip.driver.name,
          phone: trip.driver.phone,
          vehicleNumber: trip.vehicle?.vehicleNumber || 'N/A'
        } : null,
        estimatedArrivalTime: trip.estimatedArrivalTime || null,
        tracking: trip.tracking || null
      }
    });
  } catch (error) {
    console.error('Error getting trip location:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get trip location',
      error: error.message
    });
  }
});

/**
 * @swagger
 * /api/tracking/status/{tripId}:
 *   post:
 *     summary: Update trip status
 *     tags: [Tracking]
 *     parameters:
 *       - in: path
 *         name: tripId
 *         required: true
 *         schema:
 *           type: string
 *         description: Trip ID or tripId
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - status
 *             properties:
 *               status:
 *                 type: string
 *                 enum: [scheduled, in_progress, completed, cancelled, delayed]
 *               statusMessage:
 *                 type: string
 *               estimatedArrivalTime:
 *                 type: string
 *                 format: date-time
 *     responses:
 *       200:
 *         description: Status updated successfully
 *       400:
 *         description: Invalid input
 *       404:
 *         description: Trip not found
 *       500:
 *         description: Server error
 */
router.post('/status/:tripId', checkWebSocketInitialized, async (req, res) => {
  const session = req.mongoClient.startSession();
  try {
    const { tripId } = req.params;
    const { status, statusMessage, estimatedArrivalTime } = req.body;

    // Input validation
    if (!status) {
      return res.status(400).json({
        success: false,
        message: 'Status is required'
      });
    }

    // Start transaction
    session.startTransaction();

    // Find the trip
    const trip = await req.db.collection('trips').findOne(
      {
        $or: [
          { _id: new ObjectId(tripId) },
          { tripId: tripId },
          { tripNumber: tripId } // Backward compatibility
        ]
      },
      { session }
    );

    if (!trip) {
      await session.abortTransaction();
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }

    // Prepare update data
    const updateData = {
      status,
      updatedAt: new Date()
    };

    // Add status message if provided
    if (statusMessage) {
      updateData.statusMessage = statusMessage;
    }

    // Add ETA if provided
    if (estimatedArrivalTime) {
      updateData.estimatedArrivalTime = new Date(estimatedArrivalTime);
    }

    // Update trip status
    await req.db.collection('trips').updateOne(
      { _id: trip._id },
      { $set: updateData },
      { session }
    );

    // If trip is completed, update vehicle and driver status
    if (status === 'completed') {
      // Update vehicle status
      if (trip.vehicle?.vehicleId) {
        await req.db.collection('vehicles').updateOne(
          { vehicleId: trip.vehicle.vehicleId },
          {
            $set: {
              status: 'available',
              currentTrip: null,
              updatedAt: new Date()
            }
          },
          { session }
        );
      }

      // Update driver status
      if (trip.driver?.driverId) {
        await req.db.collection('drivers').updateOne(
          { driverId: trip.driver.driverId },
          {
            $set: {
              status: 'available',
              currentTrip: null,
              updatedAt: new Date()
            }
          },
          { session }
        );
      }
    }

    await session.commitTransaction();

    // Broadcast status update to all connected clients
    const statusUpdate = {
      tripId: trip.tripId || trip._id.toString(),
      status,
      statusMessage,
      estimatedArrivalTime: updateData.estimatedArrivalTime || null,
      timestamp: new Date().toISOString()
    };

    wsServer.sendStatusUpdate(trip.tripId || trip._id.toString(), statusUpdate);

    res.json({
      success: true,
      message: 'Status updated successfully',
      data: statusUpdate
    });
  } catch (error) {
    await session.abortTransaction();
    console.error('Error updating status:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update status',
      error: error.message
    });
  } finally {
    await session.endSession();
  }
});

/**
 * @swagger
 * /api/tracking/eta/{tripId}:
 *   post:
 *     summary: Update trip ETA
 *     tags: [Tracking]
 *     parameters:
 *       - in: path
 *         name: tripId
 *         required: true
 *         schema:
 *           type: string
 *         description: Trip ID or tripId
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - estimatedArrivalTime
 *             properties:
 *               estimatedArrivalTime:
 *                 type: string
 *                 format: date-time
 *               remainingDistance:
 *                 type: number
 *                 description: Remaining distance in kilometers
 *               remainingDuration:
 *                 type: number
 *                 description: Remaining duration in minutes
 *     responses:
 *       200:
 *         description: ETA updated successfully
 *       400:
 *         description: Invalid input
 *       404:
 *         description: Trip not found
 *       500:
 *         description: Server error
 */
router.post('/eta/:tripId', checkWebSocketInitialized, async (req, res) => {
  try {
    const { tripId } = req.params;
    const { estimatedArrivalTime, remainingDistance, remainingDuration } = req.body;

    // Input validation
    if (!estimatedArrivalTime) {
      return res.status(400).json({
        success: false,
        message: 'Estimated arrival time is required'
      });
    }

    // Update trip with new ETA
    const result = await req.db.collection('trips').findOneAndUpdate(
      {
        $or: [
          { _id: new ObjectId(tripId) },
          { tripId: tripId },
          { tripNumber: tripId } // Backward compatibility
        ]
      },
      {
        $set: {
          estimatedArrivalTime: new Date(estimatedArrivalTime),
          ...(remainingDistance !== undefined && { 'tracking.remainingDistance': remainingDistance }),
          ...(remainingDuration !== undefined && { 'tracking.remainingDuration': remainingDuration }),
          updatedAt: new Date()
        }
      },
      { returnDocument: 'after' }
    );

    if (!result.value) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }

    // Broadcast ETA update to all connected clients
    const etaUpdate = {
      tripId: result.value.tripId || result.value._id.toString(),
      estimatedArrivalTime: new Date(estimatedArrivalTime).toISOString(),
      remainingDistance,
      remainingDuration,
      timestamp: new Date().toISOString()
    };

    wsServer.sendEtaUpdate(tripId, etaUpdate);

    res.json({
      success: true,
      message: 'ETA updated successfully',
      data: etaUpdate
    });
  } catch (error) {
    console.error('Error updating ETA:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update ETA',
      error: error.message
    });
  }
});

/**
 * @swagger
 * /api/tracking/emergency/{tripId}:
 *   post:
 *     summary: Send emergency alert
 *     tags: [Tracking]
 *     parameters:
 *       - in: path
 *         name: tripId
 *         required: true
 *         schema:
 *           type: string
 *         description: Trip ID or tripId
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - type
 *             properties:
 *               type:
 *                 type: string
 *                 enum: [accident, breakdown, medical, other]
 *               message:
 *                 type: string
 *               location:
 *                 type: object
 *                 properties:
 *                   latitude:
 *                     type: number
 *                   longitude:
 *                     type: number
 *     responses:
 *       200:
 *         description: Emergency alert sent successfully
 *       400:
 *         description: Invalid input
 *       404:
 *         description: Trip not found
 *       500:
 *         description: Server error
 */
router.post('/emergency/:tripId', checkWebSocketInitialized, async (req, res) => {
  try {
    const { tripId } = req.params;
    const { type, message, location } = req.body;

    // Input validation
    if (!type) {
      return res.status(400).json({
        success: false,
        message: 'Emergency type is required'
      });
    }

    // Find the trip
    const trip = await req.db.collection('trips').findOne({
        $or: [
          { _id: new ObjectId(tripId) },
          { tripId: tripId },
          { tripNumber: tripId } // Backward compatibility
        ]
      });

    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }

    // Create emergency alert
    const alert = {
      type,
      message: message || `Emergency alert: ${type}`,
      location: location || trip.currentLocation,
      timestamp: new Date(),
      status: 'active'
    };

    // Update trip with emergency alert
    await req.db.collection('trips').updateOne(
      { _id: trip._id },
      {
        $push: {
          'alerts': {
            $each: [alert],
            $position: 0
          }
        },
        $set: {
          'status': 'emergency',
          'updatedAt': new Date()
        }
      }
    );

    // Broadcast emergency alert to all connected clients
    const alertData = {
      tripId: trip.tripId || trip._id.toString(),
      alert: {
        ...alert,
        timestamp: alert.timestamp.toISOString()
      },
      tripStatus: 'emergency'
    };

    wsServer.sendEmergencyAlert(trip.tripId || trip._id.toString(), alertData);

    // TODO: Send notifications to admins and emergency contacts

    res.json({
      success: true,
      message: 'Emergency alert sent successfully',
      data: alertData
    });
  } catch (error) {
    console.error('Error sending emergency alert:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to send emergency alert',
      error: error.message
    });
  }
});

module.exports = {
  router,
  initWebSocket
};
