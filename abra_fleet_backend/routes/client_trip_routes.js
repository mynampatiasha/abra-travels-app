// routes/client_trip_routes.js - CLIENT TRIP MANAGEMENT WITH FCM NOTIFICATIONS
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const { createNotification } = require('../models/notification_model');

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

function generateTripNumber() {
  const timestamp = Date.now().toString().slice(-8);
  const random = Math.floor(Math.random() * 1000).toString().padStart(3, '0');
  return `CLIENT-TRIP-${timestamp}-${random}`;
}

function calculateETA(distance) {
  const averageSpeed = 30;
  const timeInHours = distance / averageSpeed;
  const timeInMinutes = Math.ceil(timeInHours * 60);
  return Math.max(timeInMinutes, 15);
}

function formatTime(date) {
  if (!date) return 'N/A';
  const d = new Date(date);
  return d.toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true
  });
}

// ============================================================================
// @route   POST /api/client-trips/create
// @desc    Client creates a trip request (no vehicle selection)
// @access  Private (Client)
// ============================================================================
router.post('/create', verifyToken, async (req, res) => {
  let session = null;
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🚀 CLIENT TRIP REQUEST CREATION');
    console.log('='.repeat(80));
    
    if (!req.mongoClient || !req.db) {
      return res.status(500).json({
        success: false,
        message: 'Database connection error',
        error: 'MongoDB not initialized'
      });
    }
    
    session = req.mongoClient.startSession();
    await session.startTransaction();
    
    const {
      clientName,
      clientEmail,
      clientPhone,
      startPoint,
      endPoint,
      distance,
      scheduledPickupTime,
      scheduledDropTime,
      notes
    } = req.body;
    
    // Validate required fields
    if (!clientName || !clientEmail || !clientPhone) {
      return res.status(400).json({
        success: false,
        message: '❌ Client name, email, and phone are required',
        error: 'MISSING_CLIENT_DETAILS'
      });
    }
    
    if (!startPoint || !endPoint || !distance) {
      return res.status(400).json({
        success: false,
        message: '❌ Pickup location, drop location, and distance are required',
        error: 'MISSING_LOCATION_DETAILS'
      });
    }
    
    console.log('📋 Client Trip Request Details:');
    console.log(`   👤 Client Name: ${clientName}`);
    console.log(`   📧 Client Email: ${clientEmail}`);
    console.log(`   📱 Client Phone: ${clientPhone}`);
    console.log(`   📍 Start: ${startPoint.latitude}, ${startPoint.longitude}`);
    console.log(`   📍 End: ${endPoint.latitude}, ${endPoint.longitude}`);
    console.log(`   📏 Distance: ${distance} km`);
    
    // Generate trip details
    const tripNumber = generateTripNumber();
    const estimatedDuration = calculateETA(distance);
    const currentTime = new Date();
    const pickupTime = scheduledPickupTime ? new Date(scheduledPickupTime) : new Date(currentTime.getTime() + 30 * 60000);
    const estimatedEndTime = new Date(pickupTime.getTime() + estimatedDuration * 60000);
    
    console.log(`🎫 Trip Number: ${tripNumber}`);
    console.log(`⏰ Pickup Time: ${formatTime(pickupTime)}`);
    console.log(`🏁 Estimated End: ${formatTime(estimatedEndTime)}`);
    console.log(`⏱️  Duration: ${estimatedDuration} minutes`);
    
    // Get client user ID from token
    const clientUserId = req.user.userId || req.user.id || req.user._id;
    
    // Create trip document in client_created_trips collection
    const tripData = {
      tripNumber,
      
      // Client Details
      clientId: clientUserId ? clientUserId.toString() : null,
      clientName: clientName,
      clientEmail: clientEmail,
      clientPhone: clientPhone,
      
      // Trip Details
      pickupLocation: {
        address: startPoint.address || `${startPoint.latitude}, ${startPoint.longitude}`,
        coordinates: {
          type: 'Point',
          coordinates: [startPoint.longitude, startPoint.latitude]
        },
        latitude: startPoint.latitude,
        longitude: startPoint.longitude
      },
      dropLocation: {
        address: endPoint.address || `${endPoint.latitude}, ${endPoint.longitude}`,
        coordinates: {
          type: 'Point',
          coordinates: [endPoint.longitude, endPoint.latitude]
        },
        latitude: endPoint.latitude,
        longitude: endPoint.longitude
      },
      
      scheduledPickupTime: pickupTime,
      scheduledDropTime: scheduledDropTime ? new Date(scheduledDropTime) : null,
      estimatedEndTime: estimatedEndTime,
      estimatedDuration: estimatedDuration,
      
      distance: parseFloat(distance),
      actualDistance: null,
      
      // Assignment Details (null initially)
      vehicleId: null,
      vehicleNumber: null,
      driverId: null,
      driverName: null,
      driverEmail: null,
      driverPhone: null,
      driverFirebaseUid: null,
      
      // Status and Timestamps
      status: 'pending_assignment', // Client trip starts as pending
      tripType: 'client_request',
      
      createdAt: currentTime,
      updatedAt: currentTime,
      createdBy: clientUserId ? clientUserId.toString() : null,
      
      assignedAt: null,
      acceptedAt: null,
      actualStartTime: null,
      actualEndTime: null,
      actualDuration: null,
      
      statusHistory: {
        pending_assignment: currentTime
      },
      
      // Driver Response
      driverResponse: null,
      driverResponseTime: null,
      driverResponseNotes: null,
      
      // Admin Confirmation
      adminConfirmed: false,
      adminConfirmedAt: null,
      adminConfirmedBy: null,
      
      currentLocation: null,
      locationHistory: [],
      
      notes: notes || 'Trip requested by client',
      
      startOdometer: null,
      endOdometer: null
    };
    
    const tripResult = await req.db.collection('client_created_trips').insertOne(tripData, { session });
    const tripId = tripResult.insertedId.toString();
    
    console.log(`✅ Client trip request created: ${tripId}`);
    
    // ============================================================================
    // SEND FCM NOTIFICATION TO ALL ADMINS
    // ============================================================================
    
    let adminNotificationsSent = 0;
    
    try {
      console.log('📤 Sending notifications to all admins...');
      
      const adminUsers = await req.db.collection('employee_admins').find({
        role: { $in: ['admin', 'super_admin'] },
        status: 'active'
      }, { session }).toArray();
      
      console.log(`   Found ${adminUsers.length} admin(s)`);
      
      for (const admin of adminUsers) {
        if (!admin.email) {
          console.log(`   ⚠️  Skipping admin ${admin._id} - no email`);
          continue;
        }
        
        const adminNotificationData = {
          userId: admin._id.toString(),
          userEmail: admin.email,
          userRole: admin.role,
          title: '🚗 New Client Trip Request',
          body: `${clientName} has requested a trip.\n\n` +
                `📧 Email: ${clientEmail}\n` +
                `📱 Phone: ${clientPhone}\n` +
                `📍 From: ${startPoint.address || 'Pickup Location'}\n` +
                `📍 To: ${endPoint.address || 'Drop Location'}\n` +
                `📏 Distance: ${distance} km\n` +
                `⏰ Pickup Time: ${formatTime(pickupTime)}\n\n` +
                `Please assign a vehicle and driver to this trip.`,
          type: 'client_trip_request',
          data: {
            tripId: tripId,
            tripNumber: tripNumber,
            clientName: clientName,
            clientEmail: clientEmail,
            clientPhone: clientPhone,
            pickupTime: pickupTime.toISOString(),
            distance: distance,
            pickupAddress: startPoint.address || `${startPoint.latitude}, ${startPoint.longitude}`,
            dropAddress: endPoint.address || `${endPoint.latitude}, ${endPoint.longitude}`,
            status: 'pending_assignment',
            requiresAction: true
          },
          priority: 'high',
          category: 'client_trip_request',
          channels: ['fcm', 'database']
        };
        
        await createNotification(req.db, adminNotificationData);
        adminNotificationsSent++;
        console.log(`   ✅ Notified admin: ${admin.email}`);
      }
      
      console.log(`✅ Sent ${adminNotificationsSent} admin notifications`);
      
    } catch (notifError) {
      console.log(`⚠️  Admin notifications failed: ${notifError.message}`);
    }
    
    await session.commitTransaction();
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ CLIENT TRIP REQUEST CREATED SUCCESSFULLY');
    console.log('='.repeat(80));
    console.log(`🎫 Trip Number: ${tripNumber}`);
    console.log(`🆔 Trip ID: ${tripId}`);
    console.log(`👤 Client: ${clientName} (${clientEmail})`);
    console.log(`📏 Distance: ${distance} km`);
    console.log(`⏰ Pickup: ${formatTime(pickupTime)}`);
    console.log(`📱 Admins Notified: ${adminNotificationsSent}`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: '✅ Trip request created successfully! Admins have been notified.',
      data: {
        tripId: tripId,
        tripNumber: tripNumber,
        status: 'pending_assignment',
        client: {
          name: clientName,
          email: clientEmail,
          phone: clientPhone
        },
        trip: {
          pickupTime: pickupTime.toISOString(),
          estimatedEndTime: estimatedEndTime.toISOString(),
          estimatedDuration: estimatedDuration,
          distance: distance,
          pickupLocation: startPoint,
          dropLocation: endPoint
        },
        adminsNotified: adminNotificationsSent,
        nextSteps: [
          'Admin will review your trip request',
          'Admin will assign a vehicle and driver',
          'Driver will accept or decline the assignment',
          'You will be notified once trip is confirmed'
        ]
      }
    });
    
  } catch (error) {
    if (session) await session.abortTransaction();
    console.error('\n' + '❌'.repeat(40));
    console.error('CLIENT TRIP REQUEST CREATION FAILED');
    console.error('❌'.repeat(40));
    console.error('Error:', error);
    console.error('Stack:', error.stack);
    console.error('❌'.repeat(40) + '\n');
    
    res.status(500).json({
      success: false,
      message: '❌ Failed to create trip request',
      error: error.message
    });
  } finally {
    if (session) {
      await session.endSession();
    }
  }
});

// ============================================================================
// @route   GET /api/client-trips/my-trips
// @desc    Get all trips created by logged-in client (filtered by email)
// @access  Private (Client)
// ============================================================================
router.get('/my-trips', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📋 FETCHING CLIENT TRIPS');
    console.log('='.repeat(80));
    
    const clientEmail = req.user.email;
    const { status, limit = 50 } = req.query;
    
    if (!clientEmail) {
      return res.status(401).json({
        success: false,
        message: 'Client email not found in token'
      });
    }
    
    console.log(`   📧 Client Email: ${clientEmail}`);
    
    const filter = {
      clientEmail: clientEmail
    };
    
    if (status) {
      filter.status = status;
      console.log(`   🔍 Filtering by status: ${status}`);
    }
    
    const trips = await req.db.collection('client_created_trips')
      .find(filter)
      .sort({ createdAt: -1 })
      .limit(parseInt(limit))
      .toArray();
    
    console.log(`✅ Found ${trips.length} trip(s) for ${clientEmail}`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      count: trips.length,
      clientEmail: clientEmail,
      data: trips
    });
    
  } catch (error) {
    console.error('❌ Error fetching client trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch trips',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/client-trips/all
// @desc    Get all client-created trips (ADMIN ONLY)
// @access  Private (Admin)
// ============================================================================
router.get('/all', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📋 ADMIN: FETCHING ALL CLIENT TRIPS');
    console.log('='.repeat(80));
    
    // Verify admin role
    if (req.user.role !== 'admin' && req.user.role !== 'super_admin') {
      return res.status(403).json({
        success: false,
        message: 'Access denied. Admin role required.'
      });
    }
    
    const { status, limit = 100 } = req.query;
    
    const filter = {};
    
    if (status) {
      filter.status = status;
      console.log(`   🔍 Filtering by status: ${status}`);
    }
    
    const trips = await req.db.collection('client_created_trips')
      .find(filter)
      .sort({ createdAt: -1 })
      .limit(parseInt(limit))
      .toArray();
    
    console.log(`✅ Found ${trips.length} client trip(s)`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      count: trips.length,
      data: trips
    });
    
  } catch (error) {
    console.error('❌ Error fetching all client trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch trips',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/client-trips/:tripId/assign-vehicle
// @desc    Admin assigns vehicle+driver to client trip
// @access  Private (Admin)
// ============================================================================
router.post('/:tripId/assign-vehicle', verifyToken, async (req, res) => {
  let session = null;
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🚗 ADMIN ASSIGNING VEHICLE TO CLIENT TRIP');
    console.log('='.repeat(80));
    
    // Verify admin role
    if (req.user.role !== 'admin' && req.user.role !== 'super_admin') {
      return res.status(403).json({
        success: false,
        message: 'Access denied. Admin role required.'
      });
    }
    
    if (!req.mongoClient || !req.db) {
      return res.status(500).json({
        success: false,
        message: 'Database connection error'
      });
    }
    
    session = req.mongoClient.startSession();
    await session.startTransaction();
    
    const { tripId } = req.params;
    const { vehicleId } = req.body;
    
    if (!vehicleId) {
      return res.status(400).json({
        success: false,
        message: '❌ Vehicle ID is required',
        error: 'MISSING_VEHICLE_ID'
      });
    }
    
    console.log(`📋 Trip ID: ${tripId}`);
    console.log(`🚗 Vehicle ID: ${vehicleId}`);
    
    // Get trip details
    const trip = await req.db.collection('client_created_trips').findOne({
      _id: new ObjectId(tripId)
    }, { session });
    
    if (!trip) {
      if (session) await session.abortTransaction();
      return res.status(404).json({
        success: false,
        message: '❌ Trip not found',
        error: 'TRIP_NOT_FOUND'
      });
    }
    
    console.log(`✅ Trip found: ${trip.tripNumber}`);
    console.log(`   Client: ${trip.clientName} (${trip.clientEmail})`);
    
    // Get vehicle details
    const vehicle = await req.db.collection('vehicles').findOne(
      { _id: new ObjectId(vehicleId) },
      { session }
    );
    
    if (!vehicle) {
      if (session) await session.abortTransaction();
      return res.status(404).json({
        success: false,
        message: '❌ Vehicle not found',
        error: 'VEHICLE_NOT_FOUND'
      });
    }
    
    console.log(`✅ Vehicle: ${vehicle.registrationNumber || vehicle.name}`);
    
    // Get driver details
    let driver = null;
    let driverIdToSearch = null;
    
    if (vehicle.assignedDriver) {
      if (typeof vehicle.assignedDriver === 'object' && vehicle.assignedDriver.name) {
        driver = {
          _id: vehicle.assignedDriver._id || vehicle.assignedDriver.driverId,
          name: vehicle.assignedDriver.name,
          email: vehicle.assignedDriver.email || '',
          phone: vehicle.assignedDriver.phone || vehicle.assignedDriver.phoneNumber || '',
          firebaseUid: vehicle.assignedDriver.firebaseUid || vehicle.assignedDriver.userId
        };
      } else if (typeof vehicle.assignedDriver === 'string') {
        driverIdToSearch = vehicle.assignedDriver;
      } else if (typeof vehicle.assignedDriver === 'object') {
        driverIdToSearch = vehicle.assignedDriver.driverId || vehicle.assignedDriver._id;
      }
    }
    
    if (!driver && driverIdToSearch) {
      driver = await req.db.collection('drivers').findOne(
        { driverId: driverIdToSearch },
        { session }
      );
      
      if (driver) {
        const firstName = driver.personalInfo?.firstName || driver.firstName || '';
        const lastName = driver.personalInfo?.lastName || driver.lastName || '';
        const fullName = `${firstName} ${lastName}`.trim() || driver.name || 'Unknown Driver';
        
        driver = {
          _id: driver._id,
          name: fullName,
          email: driver.personalInfo?.email || driver.email || '',
          phone: driver.personalInfo?.phone || driver.phone || driver.phoneNumber || '',
          firebaseUid: driver.firebaseUid || driver.userId
        };
      } else if (ObjectId.isValid(driverIdToSearch)) {
        driver = await req.db.collection('drivers').findOne(
          { _id: new ObjectId(driverIdToSearch) },
          { session }
        );
        
        if (driver) {
          const firstName = driver.personalInfo?.firstName || driver.firstName || '';
          const lastName = driver.personalInfo?.lastName || driver.lastName || '';
          const fullName = `${firstName} ${lastName}`.trim() || driver.name || 'Unknown Driver';
          
          driver = {
            _id: driver._id,
            name: fullName,
            email: driver.personalInfo?.email || driver.email || '',
            phone: driver.personalInfo?.phone || driver.phone || driver.phoneNumber || '',
            firebaseUid: driver.firebaseUid || driver.userId
          };
        }
      }
    }
    
    if (!driver) {
      if (session) await session.abortTransaction();
      return res.status(404).json({
        success: false,
        message: '❌ No driver assigned to this vehicle',
        error: 'DRIVER_NOT_FOUND'
      });
    }
    
    if (!driver.email) {
      if (session) await session.abortTransaction();
      return res.status(404).json({
        success: false,
        message: '❌ Driver email not found - required for notifications',
        error: 'DRIVER_EMAIL_MISSING'
      });
    }
    
    console.log(`✅ Driver: ${driver.name}`);
    console.log(`   📧 Email: ${driver.email}`);
    console.log(`   📱 Phone: ${driver.phone || 'N/A'}`);
    
    // Update trip with vehicle and driver assignment
    const updateResult = await req.db.collection('client_created_trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: {
          vehicleId: new ObjectId(vehicleId),
          vehicleNumber: vehicle.registrationNumber || vehicle.name || 'Vehicle',
          driverId: driver._id.toString(),
          driverName: driver.name,
          driverEmail: driver.email,
          driverPhone: driver.phone || '',
          driverFirebaseUid: driver.firebaseUid || '',
          status: 'assigned',
          assignedAt: new Date(),
          assignedBy: req.user.userId || req.user.id,
          'statusHistory.assigned': new Date(),
          updatedAt: new Date()
        }
      },
      { session }
    );
    
    if (updateResult.matchedCount === 0) {
      if (session) await session.abortTransaction();
      return res.status(500).json({
        success: false,
        message: 'Failed to update trip'
      });
    }
    
    console.log(`✅ Trip updated with vehicle and driver assignment`);
    
    // ============================================================================
    // SEND FCM NOTIFICATION TO DRIVER (Accept/Decline)
    // ============================================================================
    
    let driverNotificationSent = false;
    
    try {
      console.log('📤 Sending assignment notification to driver...');
      
      const driverNotificationData = {
        userId: driver._id.toString(),
        userEmail: driver.email,
        userRole: 'driver',
        title: '🚗 New Client Trip Assigned',
        body: `You have been assigned a client trip.\n\n` +
              `🎫 Trip: ${trip.tripNumber}\n` +
              `🚗 Vehicle: ${vehicle.registrationNumber || vehicle.name}\n` +
              `👤 Client: ${trip.clientName}\n` +
              `📱 Client Phone: ${trip.clientPhone}\n` +
              `📏 Distance: ${trip.distance} km\n` +
              `⏰ Pickup Time: ${formatTime(trip.scheduledPickupTime)}\n` +
              `⏱️  Duration: ~${trip.estimatedDuration} minutes\n\n` +
              `Please confirm if you can accept this trip.`,
        type: 'client_trip_assigned',
        data: {
          tripId: tripId,
          tripNumber: trip.tripNumber,
          vehicleId: vehicleId,
          vehicleNumber: vehicle.registrationNumber || vehicle.name,
          clientName: trip.clientName,
          clientPhone: trip.clientPhone,
          clientEmail: trip.clientEmail,
          pickupTime: trip.scheduledPickupTime.toISOString(),
          estimatedDuration: trip.estimatedDuration,
          distance: trip.distance,
          pickupAddress: trip.pickupLocation.address,
          dropAddress: trip.dropLocation.address,
          canAccept: true,
          canDecline: true,
          requiresResponse: true,
          tripType: 'client_request'
        },
        priority: 'high',
        category: 'trip_assignment',
        channels: ['fcm', 'database']
      };
      
      await createNotification(req.db, driverNotificationData);
      driverNotificationSent = true;
      console.log('✅ Driver notification sent');
      
    } catch (notifError) {
      console.log(`⚠️  Driver notification failed: ${notifError.message}`);
    }
    
    await session.commitTransaction();
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ VEHICLE ASSIGNED SUCCESSFULLY');
    console.log('='.repeat(80));
    console.log(`🎫 Trip Number: ${trip.tripNumber}`);
    console.log(`🚗 Vehicle: ${vehicle.registrationNumber || vehicle.name}`);
    console.log(`👨‍✈️ Driver: ${driver.name} (${driver.email})`);
    console.log(`👤 Client: ${trip.clientName} (${trip.clientEmail})`);
    console.log(`📱 Driver Notification: ${driverNotificationSent ? '✅ Sent' : '❌ Failed'}`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: '✅ Vehicle and driver assigned successfully! Driver has been notified.',
      data: {
        tripId: tripId,
        tripNumber: trip.tripNumber,
        status: 'assigned',
        vehicle: {
          id: vehicleId,
          number: vehicle.registrationNumber || vehicle.name
        },
        driver: {
          id: driver._id.toString(),
          name: driver.name,
          email: driver.email,
          phone: driver.phone || '',
          notificationSent: driverNotificationSent
        },
        client: {
          name: trip.clientName,
          email: trip.clientEmail,
          phone: trip.clientPhone
        },
        nextSteps: [
          'Driver will receive notification with Accept/Decline buttons',
          'Wait for driver response',
          'If driver accepts, confirm to notify client',
          'If driver declines, reassign different vehicle'
        ]
      }
    });
    
  } catch (error) {
    if (session) await session.abortTransaction();
    console.error('\n' + '❌'.repeat(40));
    console.error('VEHICLE ASSIGNMENT FAILED');
    console.error('❌'.repeat(40));
    console.error('Error:', error);
    console.error('Stack:', error.stack);
    console.error('❌'.repeat(40) + '\n');
    
    res.status(500).json({
      success: false,
      message: '❌ Failed to assign vehicle',
      error: error.message
    });
  } finally {
    if (session) {
      await session.endSession();
    }
  }
});

// ============================================================================
// @route   POST /api/client-trips/:tripId/driver-response
// @desc    Driver accepts or declines client trip assignment
// @access  Private (Driver)
// ============================================================================
router.post('/:tripId/driver-response', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📱 DRIVER RESPONSE TO CLIENT TRIP');
    console.log('='.repeat(80));
    
    const { tripId } = req.params;
    const { response, notes } = req.body;
    
    if (!response || !['accept', 'decline'].includes(response)) {
      return res.status(400).json({
        success: false,
        message: 'Response must be "accept" or "decline"'
      });
    }
    
    console.log(`📋 Trip ID: ${tripId}`);
    console.log(`📱 Response: ${response}`);
    console.log(`📝 Notes: ${notes || 'None'}`);
    
    const trip = await req.db.collection('client_created_trips').findOne({
      _id: new ObjectId(tripId)
    });
    
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }
    
    console.log(`✅ Trip found: ${trip.tripNumber}`);
    console.log(`   Client: ${trip.clientName}`);
    console.log(`   Driver: ${trip.driverName}`);
    
    // Update trip with driver response
    const updateData = {
      driverResponse: response,
      driverResponseTime: new Date(),
      driverResponseNotes: notes || '',
      updatedAt: new Date()
    };
    
    if (response === 'accept') {
      updateData.status = 'accepted';
      updateData['statusHistory.accepted'] = new Date();
      updateData.acceptedAt = new Date();
    } else if (response === 'decline') {
      updateData.status = 'declined';
      updateData['statusHistory.declined'] = new Date();
      // Reset assignment for reassignment
      updateData.vehicleId = null;
      updateData.vehicleNumber = null;
      updateData.driverId = null;
      updateData.driverName = null;
      updateData.driverEmail = null;
      updateData.driverPhone = null;
      updateData.driverFirebaseUid = null;
      updateData.assignedAt = null;
      updateData.assignedBy = null;
    }
    
    await req.db.collection('client_created_trips').updateOne(
      { _id: new ObjectId(tripId) },
      { $set: updateData }
    );
    
    console.log(`✅ Trip updated with driver response: ${response}`);
    
    // Update the notification document with driver response for persistence
    try {
      const notifUpdateResult = await req.db.collection('notifications').updateMany(
        {
          'data.tripId': tripId,
          type: { $in: ['client_trip_assigned', 'trip_assigned'] }
        },
        {
          $set: {
            'data.driverResponse': response,
            'data.driverResponseTime': new Date(),
            'data.driverResponseNotes': notes || '',
            updatedAt: new Date()
          }
        }
      );
      console.log(`✅ Updated ${notifUpdateResult.modifiedCount} notification(s) with driver response`);
    } catch (notifError) {
      console.log('⚠️  Failed to update notification:', notifError.message);
      // Don't fail the request if notification update fails
    }
    
    // ============================================================================
    // SEND FCM NOTIFICATION TO ADMINS ONLY (NOT CLIENT)
    // ============================================================================
    
    console.log('📤 Notifying admins...');
    
    const adminUsers = await req.db.collection('employee_admins').find({
      role: { $in: ['admin', 'super_admin'] },
      status: 'active'
    }).toArray();
    
    console.log(`   Found ${adminUsers.length} admin(s)`);
    
    let notificationsSent = 0;
    
    for (const admin of adminUsers) {
      if (!admin.email) {
        console.log(`   ⚠️  Skipping admin ${admin._id} - no email`);
        continue;
      }
      
      const adminNotificationTitle = response === 'accept' 
        ? '✅ Driver Accepted Client Trip' 
        : '❌ Driver Declined Client Trip';
      
      const adminNotificationBody = response === 'accept'
        ? `${trip.driverName} has accepted client trip ${trip.tripNumber}.\n\n` +
          `Client: ${trip.clientName}\n` +
          `Phone: ${trip.clientPhone}\n\n` +
          `${notes ? `Notes: ${notes}\n\n` : ''}` +
          `Click "Confirm Accepted" to notify the client.`
        : `${trip.driverName} has declined client trip ${trip.tripNumber}.\n\n` +
          `Client: ${trip.clientName}\n` +
          `Phone: ${trip.clientPhone}\n\n` +
          `${notes ? `Reason: ${notes}\n\n` : 'No reason provided.\n\n'}` +
          `Please assign a different driver.`;
      
      try {
        await createNotification(req.db, {
          userId: admin._id.toString(),
          userEmail: admin.email,
          userRole: admin.role,
          title: adminNotificationTitle,
          body: adminNotificationBody,
          type: response === 'accept' ? 'client_trip_accepted_admin' : 'client_trip_declined_admin',
          data: {
            tripId: tripId,
            tripNumber: trip.tripNumber,
            clientName: trip.clientName,
            clientEmail: trip.clientEmail,
            clientPhone: trip.clientPhone,
            driverName: trip.driverName,
            driverResponse: response,
            driverNotes: notes || '',
            requiresAction: true,
            needsConfirmation: response === 'accept'
          },
          priority: 'high',
          category: 'admin_notification',
          channels: ['fcm', 'database']
        });
        
        notificationsSent++;
        console.log(`   ✅ Notified admin: ${admin.email}`);
        
      } catch (notifError) {
        console.log(`   ⚠️  Failed to notify admin ${admin.email}: ${notifError.message}`);
      }
    }
    
    console.log(`✅ Sent ${notificationsSent}/${adminUsers.length} admin notifications`);
    
    // NOTE: NO NOTIFICATION TO CLIENT - Client only gets notified when admin confirms
    
    console.log('='.repeat(80));
    console.log(response === 'accept' ? '✅ TRIP ACCEPTED BY DRIVER' : '❌ TRIP DECLINED BY DRIVER');
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: response === 'accept' 
        ? '✅ Trip accepted. Admins notified - waiting for confirmation to notify client.' 
        : '❌ Trip declined. Admins notified for reassignment.',
      data: {
        tripId: tripId,
        tripNumber: trip.tripNumber,
        response: response,
        notes: notes,
        status: response === 'accept' ? 'accepted' : 'declined',
        adminsNotified: notificationsSent,
        clientNotified: false, // Client NOT notified yet
        nextStep: response === 'accept' 
          ? 'Admin must confirm to notify client'
          : 'Admin will reassign different vehicle'
      }
    });
    
  } catch (error) {
    console.error('❌ Error processing driver response:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to process driver response',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/client-trips/:tripId/confirm-accepted
// @desc    Admin confirms accepted trip and notifies client
// @access  Private (Admin)
// ============================================================================
router.post('/:tripId/confirm-accepted', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('✅ ADMIN CONFIRMING ACCEPTED CLIENT TRIP');
    console.log('='.repeat(80));
    
    // Verify admin role
    if (req.user.role !== 'admin' && req.user.role !== 'super_admin') {
      return res.status(403).json({
        success: false,
        message: 'Access denied. Admin role required.'
      });
    }
    
    const { tripId } = req.params;
    
    const trip = await req.db.collection('client_created_trips').findOne({
      _id: new ObjectId(tripId)
    });
    
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }
    
    if (trip.status !== 'accepted') {
      return res.status(400).json({
        success: false,
        message: 'Trip must be in accepted status to confirm'
      });
    }
    
    console.log(`✅ Trip found: ${trip.tripNumber}`);
    console.log(`   Client: ${trip.clientName} (${trip.clientEmail})`);
    console.log(`   Driver: ${trip.driverName}`);
    
    // Update trip with admin confirmation
    await req.db.collection('client_created_trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: {
          adminConfirmed: true,
          adminConfirmedAt: new Date(),
          adminConfirmedBy: req.user.userId || req.user.id,
          updatedAt: new Date()
        }
      }
    );
    
    console.log('✅ Trip confirmed by admin');
    
    // ============================================================================
    // SEND FCM NOTIFICATION TO CLIENT - ONLY NOW!
    // ============================================================================
    
    let clientNotificationSent = false;
    
    try {
      console.log('📤 Sending confirmation notification to client...');
      
      const clientNotificationData = {
        userId: trip.clientId || trip.clientEmail,
        userEmail: trip.clientEmail,
        userRole: 'client',
        title: '✅ Trip Confirmed!',
        body: `Great news! Your trip has been confirmed.\n\n` +
              `🎫 Trip: ${trip.tripNumber}\n` +
              `👨‍✈️ Driver: ${trip.driverName}\n` +
              `📱 Driver Phone: ${trip.driverPhone || 'N/A'}\n` +
              `🚗 Vehicle: ${trip.vehicleNumber}\n` +
              `⏰ Pickup Time: ${formatTime(trip.scheduledPickupTime)}\n` +
              `📍 From: ${trip.pickupLocation.address}\n` +
              `📍 To: ${trip.dropLocation.address}\n\n` +
              `Your driver will contact you before arrival.`,
        type: 'client_trip_confirmed',
        data: {
          tripId: tripId,
          tripNumber: trip.tripNumber,
          driverName: trip.driverName,
          driverPhone: trip.driverPhone || '',
          vehicleNumber: trip.vehicleNumber,
          pickupTime: trip.scheduledPickupTime.toISOString(),
          pickupAddress: trip.pickupLocation.address,
          dropAddress: trip.dropLocation.address,
          distance: trip.distance,
          estimatedDuration: trip.estimatedDuration
        },
        priority: 'high',
        category: 'trip_confirmation',
        channels: ['fcm', 'database']
      };
      
      await createNotification(req.db, clientNotificationData);
      clientNotificationSent = true;
      console.log(`✅ Client notified: ${trip.clientEmail}`);
      
    } catch (notifError) {
      console.log(`⚠️  Client notification failed: ${notifError.message}`);
    }
    
    console.log('='.repeat(80));
    console.log('✅ CLIENT TRIP CONFIRMED AND CLIENT NOTIFIED');
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: '✅ Trip confirmed and client has been notified!',
      data: {
        tripId: tripId,
        tripNumber: trip.tripNumber,
        clientName: trip.clientName,
        clientEmail: trip.clientEmail,
        driverName: trip.driverName,
        vehicleNumber: trip.vehicleNumber,
        adminConfirmed: true,
        clientNotified: clientNotificationSent
      }
    });
    
  } catch (error) {
    console.error('❌ Error confirming trip:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to confirm trip',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/client-trips/:tripId/reassign-vehicle
// @desc    Admin reassigns a different vehicle+driver to an existing client trip
// @access  Private (Admin)
// ============================================================================
router.post('/:tripId/reassign-vehicle', verifyToken, async (req, res) => {
  let session = null;
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🔄 REASSIGNING VEHICLE TO CLIENT TRIP');
    console.log('='.repeat(80));
    
    const { tripId } = req.params;
    const { vehicleId } = req.body;
    
    if (!vehicleId) {
      return res.status(400).json({
        success: false,
        message: 'Vehicle ID is required'
      });
    }
    
    console.log(`📋 Trip ID: ${tripId}`);
    console.log(`🚗 New Vehicle ID: ${vehicleId}`);
    
    session = req.mongoClient.startSession();
    await session.startTransaction();
    
    // Find the trip in client_created_trips collection
    const trip = await req.db.collection('client_created_trips').findOne(
      { _id: new ObjectId(tripId) },
      { session }
    );
    
    if (!trip) {
      if (session) await session.abortTransaction();
      return res.status(404).json({ success: false, message: 'Trip not found' });
    }
    
    console.log(`✅ Trip found: ${trip.tripNumber} | Status: ${trip.status}`);
    
    // Find the new vehicle
    const vehicle = await req.db.collection('vehicles').findOne(
      { _id: new ObjectId(vehicleId) },
      { session }
    );
    
    if (!vehicle) {
      if (session) await session.abortTransaction();
      return res.status(404).json({ success: false, message: 'Vehicle not found' });
    }
    
    console.log(`✅ New vehicle: ${vehicle.registrationNumber || vehicle.name}`);
    
    // Find the driver assigned to this vehicle
    let driver = null;
    let driverIdToSearch = null;
    
    if (vehicle.assignedDriver) {
      if (typeof vehicle.assignedDriver === 'object' && vehicle.assignedDriver.name) {
        driver = {
          _id: vehicle.assignedDriver._id || vehicle.assignedDriver.driverId,
          name: vehicle.assignedDriver.name,
          email: vehicle.assignedDriver.email || '',
          phone: vehicle.assignedDriver.phone || vehicle.assignedDriver.phoneNumber || '',
          firebaseUid: vehicle.assignedDriver.firebaseUid || vehicle.assignedDriver.userId
        };
      } else if (typeof vehicle.assignedDriver === 'string') {
        driverIdToSearch = vehicle.assignedDriver;
      } else if (typeof vehicle.assignedDriver === 'object') {
        driverIdToSearch = vehicle.assignedDriver.driverId || vehicle.assignedDriver._id;
      }
    }
    
    if (!driver && driverIdToSearch) {
      driver = await req.db.collection('drivers').findOne(
        { driverId: driverIdToSearch },
        { session }
      );
      if (driver) {
        const firstName = driver.personalInfo?.firstName || driver.firstName || '';
        const lastName = driver.personalInfo?.lastName || driver.lastName || '';
        const fullName = `${firstName} ${lastName}`.trim() || driver.name || 'Unknown Driver';
        driver = {
          _id: driver._id,
          name: fullName,
          email: driver.personalInfo?.email || driver.email || '',
          phone: driver.personalInfo?.phone || driver.phone || driver.phoneNumber || '',
          firebaseUid: driver.firebaseUid || driver.userId
        };
      }
    }
    
    if (!driver) {
      if (session) await session.abortTransaction();
      return res.status(404).json({
        success: false,
        message: 'No driver assigned to this vehicle'
      });
    }
    
    if (!driver.email) {
      if (session) await session.abortTransaction();
      return res.status(404).json({
        success: false,
        message: 'Driver email not found - required for notifications'
      });
    }
    
    console.log(`✅ New driver: ${driver.name} | Email: ${driver.email}`);
    
    // Update the trip with new vehicle and driver in client_created_trips collection
    const currentTime = new Date();
    await req.db.collection('client_created_trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: {
          vehicleId: new ObjectId(vehicleId),
          vehicleNumber: vehicle.registrationNumber || vehicle.name || 'Vehicle',
          driverId: driver._id.toString(),
          driverName: driver.name,
          driverEmail: driver.email,
          driverPhone: driver.phone || '',
          driverFirebaseUid: driver.firebaseUid || '',
          status: 'assigned',
          driverResponse: null,
          driverResponseTime: null,
          driverResponseNotes: null,
          reassignedAt: currentTime,
          reassignedBy: req.user.userId || req.user.id,
          updatedAt: currentTime,
          'statusHistory.reassigned': currentTime
        }
      },
      { session }
    );
    
    console.log(`✅ Trip reassigned successfully`);
    
    // Notify old driver (if exists)
    if (trip.driverEmail) {
      try {
        await createNotification(req.db, {
          userId: trip.driverId,
          userEmail: trip.driverEmail,
          userRole: 'driver',
          title: '🔄 Trip Reassigned',
          body: `Trip ${trip.tripNumber} has been reassigned to another driver.`,
          type: 'trip_reassigned_old_driver',
          data: { tripId: tripId, tripNumber: trip.tripNumber },
          priority: 'normal',
          category: 'trip_update',
          channels: ['fcm', 'database']
        });
        console.log('✅ Old driver notified');
      } catch (notifError) {
        console.log(`⚠️ Old driver notification failed: ${notifError.message}`);
      }
    }
    
    // Notify new driver
    try {
      await createNotification(req.db, {
        userId: driver._id.toString(),
        userEmail: driver.email,
        userRole: 'driver',
        title: '🚗 New Trip Assigned',
        body: `You have been assigned a new trip.\n\n` +
              `🎫 Trip: ${trip.tripNumber}\n` +
              `🚗 Vehicle: ${vehicle.registrationNumber || vehicle.name}\n` +
              `👤 Client: ${trip.clientName}\n` +
              `📱 Client Phone: ${trip.clientPhone}\n` +
              `📏 Distance: ${trip.distance} km\n` +
              `⏰ Pickup Time: ${formatTime(trip.scheduledPickupTime)}\n\n` +
              `Please confirm if you can accept this trip.`,
        type: 'trip_assigned',
        data: {
          tripId: tripId,
          tripNumber: trip.tripNumber,
          vehicleId: vehicleId,
          vehicleNumber: vehicle.registrationNumber || vehicle.name,
          pickupTime: trip.scheduledPickupTime,
          estimatedDuration: trip.estimatedDuration,
          distance: trip.distance,
          clientName: trip.clientName,
          clientPhone: trip.clientPhone,
          pickupAddress: trip.pickupLocation?.address,
          dropAddress: trip.dropLocation?.address,
          canAccept: true,
          canDecline: true,
          requiresResponse: true
        },
        priority: 'high',
        category: 'trip_assignment',
        channels: ['fcm', 'database']
      });
      console.log('✅ New driver notified');
    } catch (notifError) {
      console.log(`⚠️ New driver notification failed: ${notifError.message}`);
    }
    
    await session.commitTransaction();
    
    console.log('='.repeat(80));
    console.log('✅ REASSIGNMENT COMPLETED SUCCESSFULLY');
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: '✅ Vehicle reassigned successfully!',
      data: {
        tripId: tripId,
        tripNumber: trip.tripNumber,
        newVehicle: {
          id: vehicleId,
          number: vehicle.registrationNumber || vehicle.name
        },
        newDriver: {
          id: driver._id.toString(),
          name: driver.name,
          email: driver.email,
          phone: driver.phone || ''
        },
        status: 'assigned',
        reassignedAt: currentTime
      }
    });
    
  } catch (error) {
    if (session) await session.abortTransaction();
    console.error('❌ Error reassigning vehicle:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to reassign vehicle',
      error: error.message
    });
  } finally {
    if (session) {
      await session.endSession();
    }
  }
});

module.exports = router;