// routes/trip_creation_router.js - Trip Creation and Management
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const { createNotification } = require('../models/notification_model');

// Helper function to generate trip number
function generateTripNumber() {
  const timestamp = Date.now().toString().slice(-8);
  const random = Math.floor(Math.random() * 1000).toString().padStart(3, '0');
  return `TRIP-${timestamp}-${random}`;
}

// Helper function to calculate ETA
function calculateETA(distance) {
  // Assume average speed of 30 km/h in city traffic
  const averageSpeed = 30;
  const timeInHours = distance / averageSpeed;
  const timeInMinutes = Math.ceil(timeInHours * 60);
  return Math.max(timeInMinutes, 15); // Minimum 15 minutes
}

// Helper function to format time for display
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

// ==================== NEW ROUTE ====================
// @route   GET /api/trips/start-trip-list
// @desc    Get list of admin-assigned trips (filtered by notes field)
// @access  Private (Admin/Driver)
router.get('/start-trip-list', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📋 FETCHING ADMIN-ASSIGNED TRIPS');
    console.log('='.repeat(80));
    
    const { driverId, status, vehicleId, limit = 50 } = req.query;
    
    // Base filter for admin panel trips
    const filter = {
      notes: "Trip created from admin panel"
    };
    
    // Optional: Filter by driver
    if (driverId) {
      filter.driverId = driverId;
      console.log(`   🔍 Filtering by driver: ${driverId}`);
    }
    
    // Optional: Filter by vehicle
    if (vehicleId) {
      filter.vehicleId = new ObjectId(vehicleId);
      console.log(`   🔍 Filtering by vehicle: ${vehicleId}`);
    }
    
    // Optional: Filter by status (default to assigned)
    if (status) {
      filter.status = status;
      console.log(`   🔍 Filtering by status: ${status}`);
    } else {
      filter.status = "assigned"; // Default to assigned trips only
      console.log(`   🔍 Default filter: status = assigned`);
    }
    
    console.log('   🔍 Filter:', JSON.stringify(filter, null, 2));
    
    const trips = await req.db.collection('trips')
      .find(filter)
      .sort({ scheduledPickupTime: 1 }) // Sort by pickup time (earliest first)
      .limit(parseInt(limit))
      .toArray();
    
    console.log(`✅ Found ${trips.length} admin-assigned trips`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      count: trips.length,
      tripType: 'admin_start_trip',
      filter: {
        notes: "Trip created from admin panel",
        status: status || "assigned",
        driverId: driverId || null,
        vehicleId: vehicleId || null
      },
      data: trips
    });
    
  } catch (error) {
    console.error('❌ Error fetching start trip list:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch start trip list',
      error: error.message
    });
  }
});

// @route   POST /api/trips/create
// @desc    Create a new trip with driver and admin notifications
// @access  Private (Admin)
router.post('/create', verifyToken, async (req, res) => {
  let session = null;
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🚀 CREATING NEW TRIP');
    console.log('='.repeat(80));
    
    // Check if MongoDB client is available
    if (!req.mongoClient) {
      console.error('❌ MongoDB client not available in request');
      return res.status(500).json({
        success: false,
        message: 'Database connection error',
        error: 'MongoDB client not initialized'
      });
    }
    
    // Check if database is available
    if (!req.db) {
      console.error('❌ Database not available in request');
      return res.status(500).json({
        success: false,
        message: 'Database connection error',
        error: 'Database not initialized'
      });
    }
    
    session = req.mongoClient.startSession();
    await session.startTransaction();
    
    const {
      vehicleId,
      startPoint,
      endPoint,
      distance,
      scheduledPickupTime,
      customerId,
      customerName,
      customerEmail,
      customerPhone,
      tripType = 'manual',
      notes
    } = req.body;
    
    // Validate required fields
    if (!vehicleId || !startPoint || !endPoint || !distance) {
      return res.status(400).json({
        success: false,
        message: '❌ Missing required trip information',
        error: 'INVALID_REQUEST'
      });
    }
    
    console.log('📋 Trip Details:');
    console.log(`   🚗 Vehicle ID: ${vehicleId}`);
    console.log(`   📍 Start: ${startPoint.latitude}, ${startPoint.longitude}`);
    console.log(`   📍 End: ${endPoint.latitude}, ${endPoint.longitude}`);
    console.log(`   📏 Distance: ${distance} km`);
    console.log(`   👤 Customer: ${customerName || 'N/A'}`);
    
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
    
    console.log(`✅ Vehicle: ${vehicle.registrationNumber || vehicle.name || 'Vehicle'}`);
    
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
    
    // Search for driver if we only have ID
    if (!driver && driverIdToSearch) {
      // Try drivers collection first
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
        // Try by ObjectId
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
      
      // Try users collection as fallback
      if (!driver) {
        driver = await req.db.collection('users').findOne(
          { 
            role: 'driver',
            $or: [
              { _id: ObjectId.isValid(driverIdToSearch) ? new ObjectId(driverIdToSearch) : null },
              { driverId: driverIdToSearch },
              { driverCode: driverIdToSearch }
            ]
          },
          { session }
        );
        
        if (driver) {
          driver = {
            _id: driver._id,
            name: driver.name || driver.displayName || 'Unknown Driver',
            email: driver.email || '',
            phone: driver.phone || driver.phoneNumber || '',
            firebaseUid: driver.uid || driver.firebaseUid
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
    
    console.log(`✅ Driver: ${driver.name}`);
    console.log(`   📧 Email: ${driver.email || 'N/A'}`);
    console.log(`   📱 Phone: ${driver.phone || 'N/A'}`);
    
    // Generate trip details
    const tripNumber = generateTripNumber();
    const estimatedDuration = calculateETA(distance);
    const currentTime = new Date();
    const pickupTime = scheduledPickupTime ? new Date(scheduledPickupTime) : new Date(currentTime.getTime() + 30 * 60000); // Default 30 min from now
    const estimatedEndTime = new Date(pickupTime.getTime() + estimatedDuration * 60000);
    
    console.log(`🎫 Trip Number: ${tripNumber}`);
    console.log(`⏰ Pickup Time: ${formatTime(pickupTime)}`);
    console.log(`🏁 Estimated End: ${formatTime(estimatedEndTime)}`);
    console.log(`⏱️  Duration: ${estimatedDuration} minutes`);
    
    // Create trip document
    const tripData = {
      tripNumber,
      vehicleId: new ObjectId(vehicleId),
      vehicleNumber: vehicle.registrationNumber || vehicle.name || 'Vehicle',
      driverId: driver._id.toString(),
      driverName: driver.name,
      driverPhone: driver.phone || '',
      driverFirebaseUid: driver.firebaseUid || '',
      
      // Customer information
      customer: {
        customerId: customerId || null,
        name: customerName || 'Walk-in Customer',
        email: customerEmail || '',
        phone: customerPhone || ''
      },
      
      // Location details
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
      
      // Trip timing
      scheduledPickupTime: pickupTime,
      estimatedEndTime: estimatedEndTime,
      estimatedDuration: estimatedDuration,
      actualStartTime: null,
      actualEndTime: null,
      actualDuration: null,
      
      // Trip details
      distance: parseFloat(distance),
      actualDistance: null,
      tripType: tripType,
      status: 'assigned',
      
      // Tracking
      currentLocation: null,
      locationHistory: [],
      
      // Notifications tracking
      etaAlerts: {
        sent15min: false,
        sent5min: false,
        sentArrival: false
      },
      delayAlertSent: false,
      
      // Metadata
      notes: notes || 'Trip created from admin panel', // DEFAULT VALUE FOR DIFFERENTIATION
      createdAt: currentTime,
      updatedAt: currentTime,
      createdBy: req.user.userId,
      assignedAt: currentTime,
      
      // Status history
      statusHistory: {
        assigned: currentTime
      }
    };
    
    // Insert trip into database
    const tripResult = await req.db.collection('trips').insertOne(tripData, { session });
    const tripId = tripResult.insertedId.toString();
    
    console.log(`✅ Trip created in database: ${tripId}`);
    
    // Update vehicle with current trip
    await req.db.collection('vehicles').updateOne(
      { _id: new ObjectId(vehicleId) },
      {
        $set: {
          currentTripId: tripId,
          currentTripNumber: tripNumber,
          lastTripAssignment: currentTime,
          updatedAt: currentTime
        }
      },
      { session }
    );
    
    console.log('✅ Vehicle updated with current trip');
    
    // Send notification to driver
    try {
      console.log('📤 Sending notification to driver...');
      
      const driverNotificationData = {
        userId: driver.firebaseUid || driver.email || driver._id.toString(),
        title: '🚗 New Trip Assigned',
        body: `You have been assigned a new trip.\n\n` +
              `🎫 Trip: ${tripNumber}\n` +
              `🚗 Vehicle: ${vehicle.registrationNumber || vehicle.name}\n` +
              `👤 Customer: ${customerName || 'Walk-in Customer'}\n` +
              `📏 Distance: ${distance} km\n` +
              `⏰ Pickup Time: ${formatTime(pickupTime)}\n` +
              `⏱️  Duration: ~${estimatedDuration} minutes\n\n` +
              `Please confirm if you can accept this trip.`,
        type: 'trip_assigned',
        data: {
          tripId: tripId,
          tripNumber: tripNumber,
          vehicleId: vehicleId,
          vehicleNumber: vehicle.registrationNumber || vehicle.name,
          pickupTime: pickupTime.toISOString(),
          estimatedDuration: estimatedDuration,
          distance: distance,
          customerName: customerName || 'Walk-in Customer',
          pickupAddress: startPoint.address || `${startPoint.latitude}, ${startPoint.longitude}`,
          dropAddress: endPoint.address || `${endPoint.latitude}, ${endPoint.longitude}`,
          canAccept: true,
          canDecline: true,
          requiresResponse: true
        },
        priority: 'high',
        category: 'trip_assignment',
        channels: ['fcm', 'firebase_rtdb', 'database']
      };
      
      await createNotification(req.db, driverNotificationData);
      console.log('✅ Driver notification sent successfully');
      
    } catch (notifError) {
      console.log(`⚠️  Driver notification failed: ${notifError.message}`);
    }
    
    // Send notification to customer (if customer info provided)
    if (customerId || customerEmail) {
      try {
        console.log('📤 Sending notification to customer...');
        
        const customerNotificationData = {
          userId: customerId || customerEmail,
          title: '🚗 Trip Confirmed',
          body: `Your trip has been confirmed and assigned to a driver.\n\n` +
                `🎫 Trip: ${tripNumber}\n` +
                `👨‍✈️ Driver: ${driver.name}\n` +
                `🚗 Vehicle: ${vehicle.registrationNumber || vehicle.name}\n` +
                `📱 Driver Phone: ${driver.phone || 'N/A'}\n` +
                `⏰ Pickup Time: ${formatTime(pickupTime)}\n` +
                `📏 Distance: ${distance} km\n\n` +
                `Your driver will contact you before arrival.`,
          type: 'trip_confirmed',
          data: {
            tripId: tripId,
            tripNumber: tripNumber,
            driverName: driver.name,
            driverPhone: driver.phone || '',
            vehicleNumber: vehicle.registrationNumber || vehicle.name,
            pickupTime: pickupTime.toISOString(),
            estimatedDuration: estimatedDuration,
            distance: distance,
            trackingEnabled: true
          },
          priority: 'high',
          category: 'trip_confirmation',
          channels: ['fcm', 'firebase_rtdb', 'database']
        };
        
        await createNotification(req.db, customerNotificationData);
        console.log('✅ Customer notification sent successfully');
        
      } catch (notifError) {
        console.log(`⚠️  Customer notification failed: ${notifError.message}`);
      }
    }
    
    // Send notification to admin about trip creation
    try {
      console.log('📤 Sending notification to admin...');
      
      // Get admin users
      const adminUsers = await req.db.collection('users').find({
        role: { $in: ['admin', 'super_admin'] },
        status: 'active'
      }, { session }).toArray();
      
      for (const admin of adminUsers) {
        const adminNotificationData = {
          userId: admin.uid || admin._id.toString(),
          title: '📋 New Trip Created',
          body: `A new trip has been created and assigned.\n\n` +
                `🎫 Trip: ${tripNumber}\n` +
                `👨‍✈️ Driver: ${driver.name}\n` +
                `🚗 Vehicle: ${vehicle.registrationNumber || vehicle.name}\n` +
                `👤 Customer: ${customerName || 'Walk-in Customer'}\n` +
                `📏 Distance: ${distance} km\n` +
                `⏰ Pickup: ${formatTime(pickupTime)}\n\n` +
                `Waiting for driver confirmation.`,
          type: 'trip_created_admin',
          data: {
            tripId: tripId,
            tripNumber: tripNumber,
            driverName: driver.name,
            vehicleNumber: vehicle.registrationNumber || vehicle.name,
            customerName: customerName || 'Walk-in Customer',
            distance: distance,
            pickupTime: pickupTime.toISOString(),
            status: 'assigned',
            requiresMonitoring: true
          },
          priority: 'normal',
          category: 'admin_notification',
          channels: ['fcm', 'firebase_rtdb', 'database']
        };
        
        await createNotification(req.db, adminNotificationData);
      }
      
      console.log(`✅ Admin notifications sent to ${adminUsers.length} admin(s)`);
      
    } catch (notifError) {
      console.log(`⚠️  Admin notification failed: ${notifError.message}`);
    }
    
    await session.commitTransaction();
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ TRIP CREATION COMPLETED SUCCESSFULLY');
    console.log('='.repeat(80));
    console.log(`🎫 Trip Number: ${tripNumber}`);
    console.log(`🆔 Trip ID: ${tripId}`);
    console.log(`👨‍✈️ Driver: ${driver.name}`);
    console.log(`🚗 Vehicle: ${vehicle.registrationNumber || vehicle.name}`);
    console.log(`📏 Distance: ${distance} km`);
    console.log(`⏰ Pickup: ${formatTime(pickupTime)}`);
    console.log(`📱 Notifications: Driver ✅, Customer ${customerId || customerEmail ? '✅' : '➖'}, Admin ✅`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: '✅ Trip created successfully! Driver and admin have been notified.',
      data: {
        tripId: tripId,
        tripNumber: tripNumber,
        status: 'assigned',
        vehicle: {
          id: vehicleId,
          number: vehicle.registrationNumber || vehicle.name,
          type: vehicle.type || 'Vehicle'
        },
        driver: {
          id: driver._id.toString(),
          name: driver.name,
          phone: driver.phone || '',
          notificationSent: true
        },
        customer: {
          name: customerName || 'Walk-in Customer',
          email: customerEmail || '',
          phone: customerPhone || '',
          notificationSent: !!(customerId || customerEmail)
        },
        trip: {
          pickupTime: pickupTime.toISOString(),
          estimatedEndTime: estimatedEndTime.toISOString(),
          estimatedDuration: estimatedDuration,
          distance: distance,
          pickupLocation: startPoint,
          dropLocation: endPoint
        },
        notifications: {
          driver: true,
          customer: !!(customerId || customerEmail),
          admin: true
        },
        nextSteps: [
          'Driver will receive notification to accept/decline',
          'Customer will be notified when driver accepts',
          'Admin can monitor trip progress in real-time',
          'Driver can start trip when ready'
        ]
      }
    });
    
  } catch (error) {
    if (session) await session.abortTransaction();
    console.error('\n' + '❌'.repeat(40));
    console.error('TRIP CREATION FAILED');
    console.error('❌'.repeat(40));
    console.error('Error:', error);
    console.error('Stack:', error.stack);
    console.error('❌'.repeat(40) + '\n');
    
    res.status(500).json({
      success: false,
      message: '❌ Trip creation failed',
      error: error.message
    });
  } finally {
    if (session) {
      await session.endSession();
    }
  }
});

// @route   POST /api/trips/:tripId/driver-response
// @desc    Handle driver accept/decline response
// @access  Private (Driver)
router.post('/:tripId/driver-response', verifyToken, async (req, res) => {
  try {
    const { tripId } = req.params;
    const { response, reason } = req.body; // response: 'accept' or 'decline'
    
    console.log(`📱 Driver response for trip ${tripId}: ${response}`);
    
    const trip = await req.db.collection('trips').findOne({
      _id: new ObjectId(tripId)
    });
    
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }
    
    const updateData = {
      driverResponse: response,
      driverResponseTime: new Date(),
      updatedAt: new Date()
    };
    
    if (reason) {
      updateData.driverResponseReason = reason;
    }
    
    if (response === 'accept') {
      updateData.status = 'accepted';
      updateData['statusHistory.accepted'] = new Date();
    } else if (response === 'decline') {
      updateData.status = 'declined';
      updateData['statusHistory.declined'] = new Date();
    }
    
    await req.db.collection('trips').updateOne(
      { _id: new ObjectId(tripId) },
      { $set: updateData }
    );
    
    // Send notification to admin about driver response
    const adminUsers = await req.db.collection('users').find({
      role: { $in: ['admin', 'super_admin'] },
      status: 'active'
    }).toArray();
    
    for (const admin of adminUsers) {
      const notificationTitle = response === 'accept' 
        ? '✅ Driver Accepted Trip' 
        : '❌ Driver Declined Trip';
      
      const notificationBody = response === 'accept'
        ? `${trip.driverName} has accepted trip ${trip.tripNumber}.\n\nTrip is ready to start.`
        : `${trip.driverName} has declined trip ${trip.tripNumber}.\n\n${reason ? `Reason: ${reason}\n\n` : ''}Please assign a different driver.`;
      
      await createNotification(req.db, {
        userId: admin.uid || admin._id.toString(),
        title: notificationTitle,
        body: notificationBody,
        type: response === 'accept' ? 'trip_accepted_admin' : 'trip_declined_admin',
        data: {
          tripId: tripId,
          tripNumber: trip.tripNumber,
          driverName: trip.driverName,
          driverResponse: response,
          reason: reason || null,
          requiresAction: response === 'decline'
        },
        priority: response === 'decline' ? 'high' : 'normal',
        category: 'admin_notification'
      });
    }
    
    // If accepted, notify customer
    if (response === 'accept' && (trip.customer?.customerId || trip.customer?.email)) {
      await createNotification(req.db, {
        userId: trip.customer.customerId || trip.customer.email,
        title: '✅ Driver Confirmed',
        body: `Great news! ${trip.driverName} has confirmed your trip.\n\n` +
              `🎫 Trip: ${trip.tripNumber}\n` +
              `⏰ Pickup: ${formatTime(trip.scheduledPickupTime)}\n` +
              `📱 Driver Phone: ${trip.driverPhone || 'N/A'}\n\n` +
              `Your driver will start the trip soon and contact you before arrival.`,
        type: 'trip_driver_confirmed',
        data: {
          tripId: tripId,
          tripNumber: trip.tripNumber,
          driverName: trip.driverName,
          driverPhone: trip.driverPhone || '',
          pickupTime: trip.scheduledPickupTime
        },
        priority: 'high',
        category: 'trip_update'
      });
    }
    
    console.log(`✅ Driver response processed: ${response}`);
    
    res.json({
      success: true,
      message: response === 'accept' 
        ? '✅ Trip accepted successfully' 
        : '❌ Trip declined successfully',
      data: {
        tripId: tripId,
        response: response,
        status: response === 'accept' ? 'accepted' : 'declined',
        notificationsSent: true
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

module.exports = router;