const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

/**
 * @swagger
 * components:
 *   schemas:
 *     Trip:
 *       type: object
 *       required:
 *         - customerId
 *         - vehicleId
 *         - driverId
 *         - startLocation
 *         - endLocation
 *         - startTime
 *       properties:
 *         _id:
 *           type: string
 *           description: The auto-generated ID of the trip
 *         tripId:
 *           type: string
 *           description: The trip ID
 *         customer:
 *           type: object
 *           properties:
 *             customerId:
 *               type: string
 *             name:
 *               type: object
 *               properties:
 *                 firstName:
 *                   type: string
 *                 lastName:
 *                   type: string
 *             contactInfo:
 *               type: object
 *               properties:
 *                 phone:
 *                   type: string
 *         vehicle:
 *           type: object
 *           properties:
 *             vehicleId:
 *               type: string
 *             make:
 *               type: string
 *             model:
 *               type: string
 *             registrationNumber:
 *               type: string
 *         driver:
 *           type: object
 *           properties:
 *             driverId:
 *               type: string
 *             name:
 *               type: object
 *               properties:
 *                 firstName:
 *                   type: string
 *                 lastName:
 *                   type: string
 *         startLocation:
 *           type: object
 *           properties:
 *             name:
 *               type: string
 *             address:
 *               type: string
 *             coordinates:
 *               type: object
 *               properties:
 *                 lat:
 *                   type: number
 *                 lng:
 *                   type: number
 *         endLocation:
 *           type: object
 *           properties:
 *             name:
 *               type: string
 *             address:
 *               type: string
 *             coordinates:
 *               type: object
 *               properties:
 *                 lat:
 *                   type: number
 *                 lng:
 *                   type: number
 *         waypoints:
 *           type: array
 *           items:
 *             type: object
 *             properties:
 *               name:
 *                 type: string
 *               address:
 *                 type: string
 *               coordinates:
 *                 type: object
 *                 properties:
 *                   lat:
 *                     type: number
 *                   lng:
 *                     type: number
 *               stopType:
 *                 type: string
 *                 enum: [pickup, dropoff, stopover]
 *               sequence:
 *                 type: number
 *         startTime:
 *           type: string
 *           format: date-time
 *           description: Scheduled start time of the trip
 *         endTime:
 *           type: string
 *           format: date-time
 *           description: Actual end time of the trip
 *         status:
 *           type: string
 *           enum: [scheduled, in_progress, completed, cancelled, delayed]
 *           default: scheduled
 *         distance:
 *           type: number
 *           description: Distance in kilometers
 *         duration:
 *           type: number
 *           description: Estimated duration in minutes
 *         fare:
 *           type: number
 *           description: Total fare for the trip
 *         notes:
 *           type: array
 *           items:
 *             type: object
 *             properties:
 *               content:
 *                 type: string
 *               createdAt:
 *                 type: string
 *                 format: date-time
 *               createdBy:
 *                 type: string
 *         createdAt:
 *           type: string
 *           format: date-time
 *         updatedAt:
 *           type: string
 *           format: date-time
 */

/**
 * @swagger
 * tags:
 *   name: Trips
 *   description: Trip management endpoints
 */

// Middleware to handle database connection
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
    next();
  } catch (error) {
    console.error('Database connection error:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Database connection error',
      error: error.message 
    });
  }
});

/**
 * @swagger
 * /api/admin/trips:
 *   post:
 *     summary: Create a new trip
 *     tags: [Trips]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             $ref: '#/components/schemas/Trip'
 *     responses:
 *       201:
 *         description: Trip created successfully
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                 message:
 *                   type: string
 *                 data:
 *                   $ref: '#/components/schemas/Trip'
 *       400:
 *         description: Invalid input
 *       500:
 *         description: Server error
 */
router.post('/', async (req, res) => {
  const session = req.mongoClient.startSession();
  try {
    const {
      customerId,
      vehicleId,
      driverId,
      startLocation,
      endLocation,
      waypoints = [],
      startTime,
      endTime,
      status = 'scheduled',
      distance,
      duration,
      fare = 0,
      notes = []
    } = req.body;

    // Input validation
    if (!customerId || !vehicleId || !driverId || !startLocation || !endLocation || !startTime) {
      return res.status(400).json({
        success: false,
        message: 'Missing required fields: customerId, vehicleId, driverId, startLocation, endLocation, and startTime are required'
      });
    }

    // Start transaction
    session.startTransaction();

    // Get customer details
    const customer = await req.db.collection('customers').findOne(
      { $or: [{ _id: customerId }, { customerId }] },
      { session }
    );

    if (!customer) {
      await session.abortTransaction();
      return res.status(404).json({
        success: false,
        message: 'Customer not found'
      });
    }

    // Get vehicle details
    const vehicle = await req.db.collection('vehicles').findOne(
      { $or: [{ _id: vehicleId }, { vehicleId }] },
      { session }
    );

    if (!vehicle) {
      await session.abortTransaction();
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found'
      });
    }

    // Get driver details
    const driver = await req.db.collection('drivers').findOne(
      { $or: [{ _id: driverId }, { driverId }] },
      { session }
    );

    if (!driver) {
      await session.abortTransaction();
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }

    // Generate trip ID in new format: Trip-XXXXX
    const generateTripId = () => {
      const randomNumbers = Math.floor(Math.random() * 100000).toString().padStart(5, '0');
      return `Trip-${randomNumbers}`;
    };
    const tripId = generateTripId();

    // Prepare trip data
    const tripData = {
      tripId,
      customer: {
        customerId: customer.customerId || customer._id.toString(),
        name: customer.name,
        contactInfo: customer.contactInfo
      },
      vehicle: {
        vehicleId: vehicle.vehicleId || vehicle._id.toString(),
        make: vehicle.make,
        model: vehicle.model,
        registrationNumber: vehicle.registrationNumber
      },
      driver: {
        driverId: driver.driverId || driver._id.toString(),
        name: driver.name
      },
      startLocation,
      endLocation,
      waypoints: waypoints.map((wp, index) => ({
        ...wp,
        sequence: wp.sequence || index + 1,
        status: 'pending'
      })),
      startTime: new Date(startTime),
      endTime: endTime ? new Date(endTime) : null,
      status,
      distance,
      duration,
      fare,
      notes: [
        ...notes,
        {
          content: `Trip created by ${req.user?.name || 'system'}`,
          createdAt: new Date(),
          createdBy: req.user?.id || 'system'
        }
      ],
      createdAt: new Date(),
      updatedAt: new Date()
    };

    // Insert trip
    const result = await req.db.collection('trips').insertOne(tripData, { session });
    const newTrip = {
      ...tripData,
      _id: result.insertedId
    };

    // Update vehicle status to 'on_trip' if trip is in progress
    if (status === 'in_progress') {
      await req.db.collection('vehicles').updateOne(
        { _id: vehicle._id },
        { 
          $set: { 
            status: 'on_trip',
            currentTrip: tripId,
            updatedAt: new Date()
          } 
        },
        { session }
      );
    }

    // Update driver status to 'on_trip' if trip is in progress
    if (status === 'in_progress') {
      await req.db.collection('drivers').updateOne(
        { _id: driver._id },
        { 
          $set: { 
            status: 'on_trip',
            currentTrip: tripId,
            updatedAt: new Date()
          } 
        },
        { session }
      );
    }

    await session.commitTransaction();
    
    res.status(201).json({
      success: true,
      message: 'Trip created successfully',
      data: newTrip
    });
  } catch (error) {
    await session.abortTransaction();
    console.error('Error creating trip:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create trip',
      error: error.message
    });
  } finally {
    await session.endSession();
  }
});

/**
 * @swagger
 * /api/admin/trips:
 *   get:
 *     summary: Get all trips with filters
 *     tags: [Trips]
 *     parameters:
 *       - in: query
 *         name: status
 *         schema:
 *           type: string
 *           enum: [scheduled, in_progress, completed, cancelled, delayed]
 *         description: Filter trips by status
 *       - in: query
 *         name: customerId
 *         schema:
 *           type: string
 *         description: Filter trips by customer ID
 *       - in: query
 *         name: driverId
 *         schema:
 *           type: string
 *         description: Filter trips by driver ID
 *       - in: query
 *         name: vehicleId
 *         schema:
 *           type: string
 *         description: Filter trips by vehicle ID
 *       - in: query
 *         name: startDate
 *         schema:
 *           type: string
 *           format: date
 *         description: Filter trips after this date (ISO format)
 *       - in: query
 *         name: endDate
 *         schema:
 *           type: string
 *           format: date
 *         description: Filter trips before this date (ISO format)
 *       - in: query
 *         name: page
 *         schema:
 *           type: integer
 *           default: 1
 *         description: Page number for pagination
 *       - in: query
 *         name: limit
 *         schema:
 *           type: integer
 *           default: 10
 *           maximum: 100
 *         description: Number of items per page
 *     responses:
 *       200:
 *         description: List of trips
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                 data:
 *                   type: array
 *                   items:
 *                     $ref: '#/components/schemas/Trip'
 *                 pagination:
 *                   $ref: '#/components/schemas/Pagination'
 *       500:
 *         description: Server error
 */
router.get('/', async (req, res) => {
  try {
    const { 
      status, 
      customerId, 
      driverId, 
      vehicleId, 
      startDate, 
      endDate, 
      page = 1, 
      limit = 10 
    } = req.query;

    const pageNum = parseInt(page, 10) || 1;
    const limitNum = Math.min(parseInt(limit, 10) || 10, 100);
    const skip = (pageNum - 1) * limitNum;

    // Build query
    const query = {};
    
    if (status) {
      query.status = status;
    }
    
    if (customerId) {
      query['customer.customerId'] = customerId;
    }
    
    if (driverId) {
      query['driver.driverId'] = driverId;
    }
    
    if (vehicleId) {
      query['vehicle.vehicleId'] = vehicleId;
    }
    
    if (startDate || endDate) {
      query.startTime = {};
      if (startDate) {
        query.startTime.$gte = new Date(startDate);
      }
      if (endDate) {
        query.startTime.$lte = new Date(endDate);
      }
    }

    // Get total count for pagination
    const total = await req.db.collection('trips').countDocuments(query);
    
    // Get paginated trips
    const trips = await req.db.collection('trips')
      .find(query)
      .sort({ startTime: -1 })
      .skip(skip)
      .limit(limitNum)
      .toArray();

    res.json({
      success: true,
      data: trips,
      pagination: {
        page: pageNum,
        limit: limitNum,
        total,
        pages: Math.ceil(total / limitNum)
      }
    });
  } catch (error) {
    console.error('Error getting trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get trips',
      error: error.message
    });
  }
});

/**
 * @swagger
 * /api/admin/trips/{id}:
 *   get:
 *     summary: Get trip by ID
 *     tags: [Trips]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: string
 *         description: Trip ID or tripId
 *     responses:
 *       200:
 *         description: Trip details
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                 data:
 *                   $ref: '#/components/schemas/Trip'
 *       404:
 *         description: Trip not found
 *       500:
 *         description: Server error
 */
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    const trip = await req.db.collection('trips').findOne({
      $or: [
        { _id: new ObjectId(id) },
        { tripId: id },
        { tripNumber: id } // Backward compatibility
      ]
    });

    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }

    res.json({
      success: true,
      data: trip
    });
  } catch (error) {
    console.error('Error getting trip:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get trip',
      error: error.message
    });
  }
});

/**
 * @swagger
 * /api/admin/trips/{id}:
 *   put:
 *     summary: Update a trip
 *     tags: [Trips]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: string
 *         description: Trip ID or tripId
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             $ref: '#/components/schemas/Trip'
 *     responses:
 *       200:
 *         description: Trip updated successfully
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                 message:
 *                   type: string
 *                 data:
 *                   $ref: '#/components/schemas/Trip'
 *       400:
 *         description: Invalid input
 *       404:
 *         description: Trip not found
 *       500:
 *         description: Server error
 */
router.put('/:id', async (req, res) => {
  const session = req.mongoClient.startSession();
  try {
    const { id } = req.params;
    const updateData = req.body;

    // Start transaction
    session.startTransaction();

    // Find the trip
    const trip = await req.db.collection('trips').findOne(
      {
        $or: [
          { _id: new ObjectId(id) },
          { tripId: id },
          { tripNumber: id } // Backward compatibility
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
    const updateFields = {
      ...updateData,
      updatedAt: new Date()
    };

    // If updating status, handle related updates
    if (updateData.status && updateData.status !== trip.status) {
      // Handle vehicle status updates
      if (updateData.status === 'in_progress') {
        // Set previous vehicle to available if changing from in_progress
        if (trip.status === 'in_progress' && trip.vehicle) {
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

        // Set new vehicle to on_trip
        if (updateData.vehicleId) {
          await req.db.collection('vehicles').updateOne(
            { vehicleId: updateData.vehicleId },
            { 
              $set: { 
                status: 'on_trip',
                currentTrip: trip.tripId,
                updatedAt: new Date()
              } 
            },
            { session }
          );
        }
      } else if (trip.status === 'in_progress' && updateData.status !== 'in_progress') {
        // Set vehicle to available if changing from in_progress
        if (trip.vehicle) {
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
      }

      // Handle driver status updates (similar to vehicle updates)
      if (updateData.status === 'in_progress' && updateData.driverId) {
        // Set previous driver to available if changing from in_progress
        if (trip.status === 'in_progress' && trip.driver) {
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

        // Set new driver to on_trip
        await req.db.collection('drivers').updateOne(
          { driverId: updateData.driverId },
          { 
            $set: { 
              status: 'on_trip',
              currentTrip: trip.tripId,
              updatedAt: new Date()
            } 
          },
          { session }
        );
      } else if (trip.status === 'in_progress' && updateData.status !== 'in_progress' && trip.driver) {
        // Set driver to available if changing from in_progress
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

    // Update trip
    const result = await req.db.collection('trips').findOneAndUpdate(
      { _id: trip._id },
      { $set: updateFields },
      { returnDocument: 'after', session }
    );

    await session.commitTransaction();
    
    res.json({
      success: true,
      message: 'Trip updated successfully',
      data: result.value
    });
  } catch (error) {
    await session.abortTransaction();
    console.error('Error updating trip:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update trip',
      error: error.message
    });
  } finally {
    await session.endSession();
  }
});

/**
 * @swagger
 * /api/admin/trips/{id}:
 *   delete:
 *     summary: Cancel a trip
 *     tags: [Trips]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: string
 *         description: Trip ID or tripId
 *     responses:
 *       200:
 *         description: Trip cancelled successfully
 *       404:
 *         description: Trip not found
 *       500:
 *         description: Server error
 */
router.delete('/:id', async (req, res) => {
  const session = req.mongoClient.startSession();
  try {
    const { id } = req.params;

    // Start transaction
    session.startTransaction();

    // Find the trip
    const trip = await req.db.collection('trips').findOne(
      {
        $or: [
          { _id: new ObjectId(id) },
          { tripId: id },
          { tripNumber: id } // Backward compatibility
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

    // Update trip status to cancelled
    await req.db.collection('trips').updateOne(
      { _id: trip._id },
      { 
        $set: { 
          status: 'cancelled',
          updatedAt: new Date()
        } 
      },
      { session }
    );

    // If trip was in progress, update vehicle and driver status
    if (trip.status === 'in_progress') {
      if (trip.vehicle) {
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

      if (trip.driver) {
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
    
    res.json({
      success: true,
      message: 'Trip cancelled successfully'
    });
  } catch (error) {
    await session.abortTransaction();
    console.error('Error cancelling trip:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to cancel trip',
      error: error.message
    });
  } finally {
    await session.endSession();
  }
});

/**
 * @swagger
 * /api/admin/trips/{id}/status:
 *   get:
 *     summary: Get trip status
 *     tags: [Trips]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: string
 *         description: Trip ID or tripId
 *     responses:
 *       200:
 *         description: Trip status
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                 data:
 *                   type: object
 *                   properties:
 *                     status:
 *                       type: string
 *                     lastUpdated:
 *                       type: string
 *                       format: date-time
 *                     currentLocation:
 *                       type: object
 *                       properties:
 *                         lat:
 *                           type: number
 *                         lng:
 *                           type: number
 *                         timestamp:
 *                           type: string
 *                           format: date-time
 *                     nextWaypoint:
 *                       type: object
 *                       properties:
 *                         name:
 *                           type: string
 *                         address:
 *                           type: string
 *                         sequence:
 *                           type: number
 *       404:
 *         description: Trip not found
 *       500:
 *         description: Server error
 */
router.get('/:id/status', async (req, res) => {
  try {
    const { id } = req.params;

    const trip = await req.db.collection('trips').findOne({
      $or: [
        { _id: new ObjectId(id) },
        { tripId: id },
        { tripNumber: id } // Backward compatibility
      ]
    });

    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }

    // In a real application, you would get the current location from a real-time tracking service
    const response = {
      status: trip.status,
      lastUpdated: trip.updatedAt || new Date(),
      currentLocation: trip.currentLocation || null,
      nextWaypoint: trip.waypoints?.find(wp => wp.status === 'pending') || null
    };

    res.json({
      success: true,
      data: response
    });
  } catch (error) {
    console.error('Error getting trip status:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get trip status',
      error: error.message
    });
  }
});

/**
 * @swagger
 * /api/admin/trips/{id}/route:
 *   get:
 *     summary: Get trip route details
 *     tags: [Trips]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: string
 *         description: Trip ID or tripId
 *     responses:
 *       200:
 *         description: Trip route details
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                 data:
 *                   type: object
 *                   properties:
 *                     waypoints:
 *                       type: array
 *                       items:
 *                         $ref: '#/components/schemas/Waypoint'
 *                     polyline:
 *                       type: string
 *                       description: Encoded polyline for the route
 *                     distance:
 *                       type: number
 *                       description: Total distance in kilometers
 *                     duration:
 *                       type: number
 *                       description: Total duration in minutes
 *       404:
 *         description: Trip not found
 *       500:
 *         description: Server error
 */
router.get('/:id/route', async (req, res) => {
  try {
    const { id } = req.params;

    const trip = await req.db.collection('trips').findOne({
      $or: [
        { _id: new ObjectId(id) },
        { tripId: id },
        { tripNumber: id } // Backward compatibility
      ]
    });

    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }

    // In a real application, you would calculate the route using a mapping service
    // For this example, we'll return a simplified response
    const response = {
      waypoints: trip.waypoints || [],
      polyline: 'sample-encoded-polyline',
      distance: trip.distance || 0,
      duration: trip.duration || 0
    };

    res.json({
      success: true,
      data: response
    });
  } catch (error) {
    console.error('Error getting trip route:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get trip route',
      error: error.message
    });
  }
});

module.exports = router;
