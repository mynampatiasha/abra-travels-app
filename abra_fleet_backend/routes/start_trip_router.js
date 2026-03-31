// routes/trip_creation_router.js - FIXED VERSION
// ============================================================================
// FIXES APPLIED:
// ✅ FIX 1: /start-trip-list — removed notes filter so ALL trips show
//           (assigned, accepted, confirmed, declined, started, completed)
// ✅ FIX 2: Smart sort — active/pending trips first, completed last
// ✅ FIX 3: /:tripId/reassign-vehicle — this is the CORRECT endpoint
//           Flutter must call /api/trips/:tripId/reassign-vehicle
// ============================================================================
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const { createNotification } = require('../models/notification_model');
const multer = require('multer');
const { GridFSBucket } = require('mongodb');

// ============================================================================
// MULTER CONFIGURATION - Memory storage for GridFS
// ============================================================================
const storage = multer.memoryStorage();
const upload = multer({
  storage: storage,
  limits: {
    fileSize: 5 * 1024 * 1024, // 5MB max
  },
  fileFilter: (req, file, cb) => {
    console.log('📸 File upload attempt:', {
      fieldname: file.fieldname,
      originalname: file.originalname,
      mimetype: file.mimetype,
      size: file.size
    });
    
    const isImage = file.mimetype && file.mimetype.startsWith('image/');
    const hasImageExtension = /\.(jpg|jpeg|png|gif|webp|bmp)$/i.test(file.originalname);
    
    if (isImage || hasImageExtension) {
      console.log('✅ File accepted:', file.originalname);
      cb(null, true);
    } else {
      console.error('❌ Rejected file:', file.mimetype, file.originalname);
      cb(new Error('Only image files are allowed! Received: ' + file.mimetype), false);
    }
  }
});

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

function generateTripNumber() {
  const timestamp = Date.now().toString().slice(-8);
  const random = Math.floor(Math.random() * 1000).toString().padStart(3, '0');
  return `TRIP-${timestamp}-${random}`;
}

function calculateETA(distance) {
  const averageSpeed = 30;
  const timeInHours = distance / averageSpeed;
  const timeInMinutes = Math.ceil(timeInHours * 60);
  return Math.max(timeInMinutes, 15);
}

async function calculateETAWithOSRM(startLat, startLng, endLat, endLng) {
  try {
    const fetch = (await import('node-fetch')).default;
    const url = `https://router.project-osrm.org/route/v1/driving/${startLng},${startLat};${endLng},${endLat}?overview=false`;
    
    const response = await fetch(url);
    const data = await response.json();
    
    if (data.routes && data.routes.length > 0) {
      const durationMinutes = Math.round(data.routes[0].duration / 60);
      return durationMinutes;
    }
    
    const R = 6371;
    const dLat = (endLat - startLat) * Math.PI / 180;
    const dLon = (endLng - startLng) * Math.PI / 180;
    const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
              Math.cos(startLat * Math.PI / 180) * Math.cos(endLat * Math.PI / 180) *
              Math.sin(dLon/2) * Math.sin(dLon/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    const distance = R * c;
    return Math.round(distance * 3);
  } catch (error) {
    console.error('❌ OSRM ETA calculation failed:', error.message);
    return 30;
  }
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
// @route   GET /api/trips/start-trip-list
// @desc    Get ALL trips for admin (no notes filter — shows every status)
// @access  Private (Admin/Driver)
// ============================================================================
router.get('/start-trip-list', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📋 FETCHING ALL TRIPS FOR ADMIN');
    console.log('='.repeat(80));

    const { driverId, status, vehicleId, limit = 200 } = req.query;

    // ✅ FIX: No notes filter — show ALL trips regardless of how they were created
    const filter = {};

    if (driverId) {
      filter.driverId = driverId;
      console.log(`   🔍 Filtering by driver: ${driverId}`);
    }

    if (vehicleId) {
      try {
        filter.vehicleId = new ObjectId(vehicleId);
      } catch (e) {
        filter.vehicleId = vehicleId; // fallback if not a valid ObjectId
      }
      console.log(`   🔍 Filtering by vehicle: ${vehicleId}`);
    }

    if (status && status !== 'All') {
      filter.status = status;
      console.log(`   🔍 Filtering by status: ${status}`);
    }

    console.log('   🔍 Filter:', JSON.stringify(filter, null, 2));

    // ✅ FIX: Smart sort using $addFields + $sort aggregation
    // Active trips (assigned, declined, accepted, confirmed, started) appear first
    // Completed trips appear at the bottom, sorted by completion time desc
    const trips = await req.db.collection('trips').aggregate([
      { $match: filter },
      {
        $addFields: {
          _sortPriority: {
            $switch: {
              branches: [
                { case: { $eq: ['$status', 'assigned'] },  then: 1 },
                { case: { $eq: ['$status', 'declined'] },  then: 2 },
                { case: { $eq: ['$status', 'accepted'] },  then: 3 },
                { case: { $eq: ['$status', 'confirmed'] }, then: 4 },
                { case: { $eq: ['$status', 'started'] },   then: 5 },
                { case: { $eq: ['$status', 'in_progress'] }, then: 5 },
                { case: { $eq: ['$status', 'completed'] }, then: 9 },
              ],
              default: 8
            }
          }
        }
      },
      { $sort: { _sortPriority: 1, createdAt: -1 } },
      { $limit: parseInt(limit) },
      { $unset: '_sortPriority' }
    ]).toArray();

    console.log(`✅ Found ${trips.length} trips`);

    // Log status breakdown for debugging
    const statusBreakdown = trips.reduce((acc, t) => {
      acc[t.status] = (acc[t.status] || 0) + 1;
      return acc;
    }, {});
    console.log('   📊 Status breakdown:', statusBreakdown);
    console.log('='.repeat(80) + '\n');

    res.json({
      success: true,
      count: trips.length,
      tripType: 'admin_all_trips',
      filter: filter,
      statusBreakdown: statusBreakdown,
      data: trips
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

router.get('/debug-auth', verifyToken, async (req, res) => {
  try {
    console.log('\n🔍 JWT TOKEN DEBUG:');
    console.log('Full req.user:', JSON.stringify(req.user, null, 2));
    
    const possibleIds = {
      driverId: req.user.driverId,
      userId: req.user.userId,
      uid: req.user.uid,
      id: req.user.id,
      _id: req.user._id,
    };
    
    console.log('Possible ID fields:', possibleIds);
    
    res.json({
      success: true,
      user: req.user,
      possibleIds
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ============================================================================
// @route   GET /api/trips/pending
// @desc    Get pending individual trips for driver (can accept/decline)
// @access  Private (Driver)
// ============================================================================
router.get('/pending', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📋 FETCHING PENDING TRIPS');
    console.log('='.repeat(80));
    
    const driverId = req.user.driverId || req.user.id || req.user.uid || req.user.userId;
    const driverEmail = req.user.email;
    
    console.log('🔍 Searching with:');
    console.log('   driverId:', driverId);
    console.log('   email:', driverEmail);
    
    const trips = await req.db.collection('trips').find({
      $or: [
        { driverId: driverId },
        { driverId: driverId?.toString() },
        { driverEmail: driverEmail }
      ],
      status: 'assigned'
    }).sort({ createdAt: -1 }).toArray();
    
    console.log(`✅ Found ${trips.length} pending trip(s)`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: `Found ${trips.length} pending trip(s)`,
      count: trips.length,
      data: trips
    });
    
  } catch (error) {
    console.error('❌ Error:', error);
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

router.get('/accepted', verifyToken, async (req, res) => {
  try {
    const driverId = req.user.driverId || req.user.id || req.user.uid || req.user.userId;
    const driverEmail = req.user.email;
    
    console.log('🔍 Searching accepted trips with email:', driverEmail);
    
    const trips = await req.db.collection('trips').find({
      $or: [
        { driverId: driverId },
        { driverId: driverId?.toString() },
        { driverEmail: driverEmail }
      ],
      status: { $in: ['accepted', 'confirmed', 'started', 'in_progress'] }
    }).sort({ scheduledPickupTime: 1 }).toArray();
    
    console.log(`✅ Found ${trips.length} accepted trip(s)`);
    
    res.json({
      success: true,
      count: trips.length,
      data: trips
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// @route   GET /api/trips/completed
// @desc    Get completed individual trips for driver (history)
// @access  Private (Driver)
// ============================================================================
router.get('/completed', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📋 FETCHING COMPLETED TRIPS FOR DRIVER');
    console.log('='.repeat(80));
    
    const driverId = req.user.driverId || req.user.id || req.user.uid;
    const { limit = 20 } = req.query;
    
    if (!driverId) {
      return res.status(401).json({
        success: false,
        message: 'Driver ID not found in token'
      });
    }
    
    console.log(`👨‍✈️ Driver ID: ${driverId}`);
    
    const trips = await req.db.collection('trips').find({
      $or: [
        { driverId: driverId },
        { driverId: driverId?.toString() }
      ],
      status: 'completed'
    })
    .sort({ actualEndTime: -1 })
    .limit(parseInt(limit))
    .toArray();
    
    console.log(`✅ Found ${trips.length} completed trip(s)`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: `Found ${trips.length} completed trip(s)`,
      count: trips.length,
      data: trips
    });
    
  } catch (error) {
    console.error('❌ Error fetching completed trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch completed trips',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/trips/create
// @desc    Create a new trip with driver notification and CUSTOMER DETAILS
// @access  Private (Admin)
// ============================================================================
router.post('/create', verifyToken, async (req, res) => {
  let session = null;
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🚀 CREATING NEW TRIP WITH CUSTOMER DETAILS');
    console.log('='.repeat(80));
    
    if (!req.mongoClient) {
      console.error('❌ MongoDB client not available in request');
      return res.status(500).json({
        success: false,
        message: 'Database connection error',
        error: 'MongoDB client not initialized'
      });
    }
    
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
      scheduledDropTime,
      customerName,
      customerEmail,
      customerPhone,
      customerId,
      tripType = 'manual',
      notes
    } = req.body;
    
    if (!vehicleId || !startPoint || !endPoint || !distance) {
      return res.status(400).json({
        success: false,
        message: '❌ Missing required trip information',
        error: 'INVALID_REQUEST'
      });
    }
    
    if (!customerName || !customerPhone) {
      return res.status(400).json({
        success: false,
        message: '❌ Customer name and phone are required',
        error: 'MISSING_CUSTOMER_DETAILS'
      });
    }
    
    console.log('📋 Trip Details:');
    console.log(`   🚗 Vehicle ID: ${vehicleId}`);
    console.log(`   📍 Start: ${startPoint.latitude}, ${startPoint.longitude}`);
    console.log(`   📍 End: ${endPoint.latitude}, ${endPoint.longitude}`);
    console.log(`   📏 Distance: ${distance} km`);
    console.log(`   👤 Customer Name: ${customerName}`);
    console.log(`   📧 Customer Email: ${customerEmail || 'N/A'}`);
    console.log(`   📱 Customer Phone: ${customerPhone}`);
    
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
    
    if (!driver.email) {
      if (session) await session.abortTransaction();
      return res.status(404).json({
        success: false,
        message: '❌ Driver email not found - required for notifications',
        error: 'DRIVER_EMAIL_MISSING'
      });
    }
    
    console.log(`✅ Driver: ${driver.name}`);
    console.log(`   📧 Email: ${driver.email || 'N/A'}`);
    console.log(`   📱 Phone: ${driver.phone || 'N/A'}`);
    
    const tripNumber = generateTripNumber();
    const estimatedDuration = calculateETA(distance);
    const currentTime = new Date();
    const pickupTime = scheduledPickupTime ? new Date(scheduledPickupTime) : new Date(currentTime.getTime() + 30 * 60000);
    const estimatedEndTime = new Date(pickupTime.getTime() + estimatedDuration * 60000);
    
    console.log(`🎫 Trip Number: ${tripNumber}`);
    console.log(`⏰ Pickup Time: ${formatTime(pickupTime)}`);
    console.log(`🏁 Estimated End: ${formatTime(estimatedEndTime)}`);
    console.log(`⏱️  Duration: ${estimatedDuration} minutes`);
    
    const tripData = {
      tripNumber,
      vehicleId: new ObjectId(vehicleId),
      vehicleNumber: vehicle.registrationNumber || vehicle.name || 'Vehicle',
      driverId: driver._id.toString(),
      driverName: driver.name,
      driverEmail: driver.email,
      driverPhone: driver.phone || '',
      driverFirebaseUid: driver.firebaseUid || '',
      customer: {
        customerId: customerId || null,
        name: customerName,
        email: customerEmail || '',
        phone: customerPhone
      },
      customerName: customerName,
      customerEmail: customerEmail || '',
      customerPhone: customerPhone,
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
      pickupTime: pickupTime,
      scheduledDropTime: scheduledDropTime ? new Date(scheduledDropTime) : null,
      dropTime: scheduledDropTime ? new Date(scheduledDropTime) : estimatedEndTime,
      estimatedEndTime: estimatedEndTime,
      estimatedDuration: estimatedDuration,
      actualStartTime: null,
      actualEndTime: null,
      actualDuration: null,
      distance: parseFloat(distance),
      actualDistance: null,
      tripType: tripType,
      status: 'assigned',
      currentLocation: null,
      locationHistory: [],
      etaAlerts: {
        sent15min: false,
        sent5min: false,
        sentArrival: false
      },
      delayAlertSent: false,
      notes: notes || 'Trip created from admin panel',
      createdAt: currentTime,
      updatedAt: currentTime,
      createdBy: req.user.userId,
      assignedAt: currentTime,
      statusHistory: {
        assigned: currentTime
      },
      driverResponse: null,
      driverResponseTime: null,
      driverResponseNotes: null,
      startOdometer: null,
      endOdometer: null
    };
    
    const tripResult = await req.db.collection('trips').insertOne(tripData, { session });
    const tripId = tripResult.insertedId.toString();
    
    console.log(`✅ Trip created in database: ${tripId}`);
    
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
    
    let driverNotificationSent = false;
    try {
      const driverNotificationData = {
        userId: driver._id.toString(),
        userEmail: driver.email,
        userRole: 'driver',
        title: '🚗 New Trip Assigned',
        body: `You have been assigned a new trip.\n\n` +
              `🎫 Trip: ${tripNumber}\n` +
              `🚗 Vehicle: ${vehicle.registrationNumber || vehicle.name}\n` +
              `👤 Customer: ${customerName}\n` +
              `📱 Customer Phone: ${customerPhone}\n` +
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
          customerName: customerName,
          customerPhone: customerPhone,
          customerEmail: customerEmail || '',
          pickupAddress: startPoint.address || `${startPoint.latitude}, ${startPoint.longitude}`,
          dropAddress: endPoint.address || `${endPoint.latitude}, ${endPoint.longitude}`,
          canAccept: true,
          canDecline: true,
          requiresResponse: true
        },
        priority: 'high',
        category: 'trip_assignment',
        channels: ['fcm', 'database']
      };
      await createNotification(req.db, driverNotificationData);
      driverNotificationSent = true;
      console.log('✅ Driver notification created and sent');
    } catch (notifError) {
      console.log(`⚠️  Driver notification failed: ${notifError.message}`);
    }
    
    let customerNotificationSent = false;
    if (customerEmail || customerPhone) {
      try {
        await createNotification(req.db, {
          userId: customerId || customerEmail || customerPhone,
          userEmail: customerEmail || '',
          userRole: 'customer',
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
          channels: ['database']
        });
        customerNotificationSent = true;
        console.log('✅ Customer notification sent successfully');
      } catch (notifError) {
        console.log(`⚠️  Customer notification failed: ${notifError.message}`);
      }
    }
    
    await session.commitTransaction();
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ TRIP CREATION COMPLETED SUCCESSFULLY');
    console.log('='.repeat(80));
    console.log(`🎫 Trip Number: ${tripNumber}`);
    console.log(`🆔 Trip ID: ${tripId}`);
    console.log(`👨‍✈️ Driver: ${driver.name} (${driver.email})`);
    console.log(`👤 Customer: ${customerName} (${customerPhone})`);
    console.log(`🚗 Vehicle: ${vehicle.registrationNumber || vehicle.name}`);
    console.log(`📱 Driver Notification: ${driverNotificationSent ? '✅ Sent' : '❌ Failed'}`);
    console.log(`📱 Customer Notification: ${customerNotificationSent ? '✅ Sent' : '❌ Failed'}`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: '✅ Trip created successfully! Driver and customer notified.',
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
          email: driver.email,
          phone: driver.phone || '',
          notificationSent: driverNotificationSent
        },
        customer: {
          name: customerName,
          email: customerEmail || '',
          phone: customerPhone,
          notificationSent: customerNotificationSent
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
          driver: driverNotificationSent,
          customer: customerNotificationSent,
          admin: true
        }
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

// ============================================================================
// PART 2 OF 2 - APPENDED BELOW
// ============================================================================

// ============================================================================
// @route   POST /api/trips/:tripId/driver-response
// @desc    Handle driver accept/decline response and notify admin
// @access  Private (Driver)
// ============================================================================
router.post('/:tripId/driver-response', verifyToken, async (req, res) => {
  try {
    const { tripId } = req.params;
    const { response, notes } = req.body;
    
    console.log(`📱 Driver response for trip ${tripId}: ${response}`);
    console.log(`📝 Notes: ${notes || 'None'}`);
    
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
      driverResponseNotes: notes || '',
      updatedAt: new Date()
    };
    
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
    
    // Update the notification document with driver response for persistence
    try {
      const notifUpdateResult = await req.db.collection('notifications').updateMany(
        {
          'data.tripId': tripId,
          type: { $in: ['trip_assigned', 'route_assigned', 'route_assigned_driver', 'driver_route_assignment'] }
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
    
    console.log('📤 Notifying admins from employee_admins collection...');
    
    const adminUsers = await req.db.collection('employee_admins').find({
      role: { $in: ['admin', 'super_admin'] },
      status: 'active'
    }).toArray();
    
    console.log(`Found ${adminUsers.length} admin user(s) in employee_admins collection`);
    
    let notificationsSent = 0;
    
    for (const admin of adminUsers) {
      if (!admin.email) continue;
      
      const adminNotificationTitle = response === 'accept' 
        ? '✅ Driver Accepted Trip' 
        : '❌ Driver Declined Trip';
      
      const adminNotificationBody = response === 'accept'
        ? `${trip.driverName} has accepted trip ${trip.tripNumber}.\n\n${notes ? `Notes: ${notes}\n\n` : ''}Trip is ready to start.`
        : `${trip.driverName} has declined trip ${trip.tripNumber}.\n\n${notes ? `Reason: ${notes}\n\n` : 'No reason provided.\n\n'}Please assign a different driver.`;
      
      try {
        await createNotification(req.db, {
          userId: admin._id.toString(),
          userEmail: admin.email,
          userRole: admin.role,
          title: adminNotificationTitle,
          body: adminNotificationBody,
          type: response === 'accept' ? 'trip_accepted_admin' : 'trip_declined_admin',
          data: {
            tripId: tripId,
            tripNumber: trip.tripNumber,
            driverName: trip.driverName,
            driverResponse: response,
            driverNotes: notes || '',
            requiresAction: response === 'decline'
          },
          priority: response === 'decline' ? 'high' : 'normal',
          category: 'admin_notification',
          channels: ['fcm', 'database']
        });
        notificationsSent++;
        console.log(`✅ Notified admin: ${admin.email}`);
      } catch (notifError) {
        console.log(`⚠️  Failed to notify admin ${admin.email}: ${notifError.message}`);
      }
    }
    
    console.log(`✅ Sent ${notificationsSent}/${adminUsers.length} admin notifications`);
    
    if (response === 'accept' && (trip.customer?.customerId || trip.customer?.email)) {
      try {
        await createNotification(req.db, {
          userId: trip.customer.customerId || trip.customer.email,
          userEmail: trip.customer.email,
          userRole: 'customer',
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
          category: 'trip_update',
          channels: ['database']
        });
        console.log('✅ Customer notified');
      } catch (err) {
        console.log('⚠️ Customer notification failed:', err.message);
      }
    }
    
    res.json({
      success: true,
      message: response === 'accept' 
        ? '✅ Trip accepted successfully. Admins have been notified.' 
        : '❌ Trip declined. Admins have been notified.',
      data: {
        tripId: tripId,
        tripNumber: trip.tripNumber,
        response: response,
        notes: notes,
        status: response === 'accept' ? 'accepted' : 'declined',
        adminsNotified: notificationsSent
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
// @route   POST /api/trips/:tripId/confirm-accepted
// @desc    Admin confirms an accepted trip
// @access  Private (Admin)
// ============================================================================
router.post('/:tripId/confirm-accepted', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('✅ ADMIN CONFIRMING ACCEPTED TRIP');
    console.log('='.repeat(80));
    
    const { tripId } = req.params;
    
    const trip = await req.db.collection('trips').findOne({
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
        message: `Cannot confirm trip with status: ${trip.status}. Trip must be accepted first.`
      });
    }
    
    console.log(`✅ Trip found: ${trip.tripNumber}`);
    
    await req.db.collection('trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: {
          status: 'confirmed',
          confirmedAt: new Date(),
          confirmedBy: req.user.userId || req.user.id,
          'statusHistory.confirmed': new Date(),
          updatedAt: new Date()
        }
      }
    );
    
    console.log(`✅ Trip confirmed successfully`);
    
    try {
      await createNotification(req.db, {
        userId: trip.driverId,
        userEmail: trip.driverEmail,
        userRole: 'driver',
        title: '✅ Trip Confirmed by Admin',
        body: `Your trip ${trip.tripNumber} has been confirmed by admin.\n\nYou can now start the trip when ready.`,
        type: 'trip_confirmed_driver',
        data: { tripId: tripId, tripNumber: trip.tripNumber, canStart: true },
        priority: 'high',
        category: 'trip_update',
        channels: ['fcm', 'database']
      });
      console.log('✅ Driver notified');
    } catch (notifError) {
      console.log(`⚠️ Driver notification failed: ${notifError.message}`);
    }
    
    if (trip.customer && (trip.customer.customerId || trip.customer.email)) {
      try {
        await createNotification(req.db, {
          userId: trip.customer.customerId || trip.customer.email,
          userEmail: trip.customer.email,
          userRole: 'customer',
          title: '✅ Trip Confirmed',
          body: `Great news! Your trip ${trip.tripNumber} has been confirmed.\n\n` +
                `Driver: ${trip.driverName}\nVehicle: ${trip.vehicleNumber}\nPickup Time: ${formatTime(trip.scheduledPickupTime)}`,
          type: 'trip_confirmed_customer',
          data: {
            tripId: tripId,
            tripNumber: trip.tripNumber,
            driverName: trip.driverName,
            vehicleNumber: trip.vehicleNumber
          },
          priority: 'high',
          category: 'trip_update',
          channels: ['database']
        });
        console.log('✅ Customer notified');
      } catch (notifError) {
        console.log(`⚠️ Customer notification failed: ${notifError.message}`);
      }
    }
    
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: '✅ Trip confirmed successfully',
      data: {
        tripId: tripId,
        tripNumber: trip.tripNumber,
        status: 'confirmed',
        confirmedAt: new Date().toISOString()
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
// @route   POST /api/trips/:tripId/reassign-vehicle
// @desc    Admin reassigns a different vehicle+driver to an existing trip
// @access  Private (Admin)
// ✅ Flutter must call: POST /api/trips/:tripId/reassign-vehicle
// ============================================================================
router.post('/:tripId/reassign-vehicle', verifyToken, async (req, res) => {
  let session = null;
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🔄 REASSIGNING VEHICLE TO TRIP');
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
    
    const trip = await req.db.collection('trips').findOne(
      { _id: new ObjectId(tripId) },
      { session }
    );
    
    if (!trip) {
      if (session) await session.abortTransaction();
      return res.status(404).json({ success: false, message: 'Trip not found' });
    }
    
    console.log(`✅ Trip found: ${trip.tripNumber} | Status: ${trip.status}`);
    
    const vehicle = await req.db.collection('vehicles').findOne(
      { _id: new ObjectId(vehicleId) },
      { session }
    );
    
    if (!vehicle) {
      if (session) await session.abortTransaction();
      return res.status(404).json({ success: false, message: 'Vehicle not found' });
    }
    
    console.log(`✅ New vehicle: ${vehicle.registrationNumber || vehicle.name}`);
    
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
    
    const currentTime = new Date();
    await req.db.collection('trips').updateOne(
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
    
    try {
      await createNotification(req.db, {
        userId: driver._id.toString(),
        userEmail: driver.email,
        userRole: 'driver',
        title: '🚗 New Trip Assigned',
        body: `You have been assigned a new trip.\n\n` +
              `🎫 Trip: ${trip.tripNumber}\n` +
              `🚗 Vehicle: ${vehicle.registrationNumber || vehicle.name}\n` +
              `👤 Customer: ${trip.customerName}\n` +
              `📱 Customer Phone: ${trip.customerPhone}\n` +
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
          customerName: trip.customerName,
          customerPhone: trip.customerPhone,
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
      message: '✅ Vehicle reassigned successfully! New driver notified.',
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
        reassignedAt: currentTime.toISOString()
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

// ============================================================================
// @route   DELETE /api/trips/:tripId
// @desc    Admin deletes a trip
// @access  Private (Admin)
// ============================================================================
router.delete('/:tripId', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🗑️  DELETING TRIP');
    console.log('='.repeat(80));
    
    const { tripId } = req.params;
    
    const trip = await req.db.collection('trips').findOne({
      _id: new ObjectId(tripId)
    });
    
    if (!trip) {
      return res.status(404).json({ success: false, message: 'Trip not found' });
    }
    
    console.log(`✅ Trip found: ${trip.tripNumber} | Status: ${trip.status}`);
    
    if (trip.status === 'started' || trip.status === 'in_progress') {
      return res.status(400).json({
        success: false,
        message: 'Cannot delete a trip that is already started or in progress'
      });
    }
    
    const deleteResult = await req.db.collection('trips').deleteOne({
      _id: new ObjectId(tripId)
    });
    
    if (deleteResult.deletedCount === 0) {
      return res.status(500).json({ success: false, message: 'Failed to delete trip' });
    }
    
    console.log(`✅ Trip deleted successfully`);
    
    if (trip.driverEmail && ['assigned', 'accepted', 'declined'].includes(trip.status)) {
      try {
        await createNotification(req.db, {
          userId: trip.driverId,
          userEmail: trip.driverEmail,
          userRole: 'driver',
          title: '🗑️ Trip Cancelled',
          body: `Trip ${trip.tripNumber} has been cancelled by admin.`,
          type: 'trip_cancelled_driver',
          data: { tripNumber: trip.tripNumber },
          priority: 'normal',
          category: 'trip_update',
          channels: ['fcm', 'database']
        });
        console.log('✅ Driver notified');
      } catch (notifError) {
        console.log(`⚠️ Driver notification failed: ${notifError.message}`);
      }
    }
    
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: '✅ Trip deleted successfully',
      data: { tripId: tripId, tripNumber: trip.tripNumber }
    });
    
  } catch (error) {
    console.error('❌ Error deleting trip:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete trip',
      error: error.message
    });
  }
});

// ============================================================================
// EXISTING ENDPOINTS CONTINUE BELOW...
// ============================================================================

router.post('/:tripId/start', verifyToken, upload.single('photo'), async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🚀 STARTING INDIVIDUAL TRIP');
    console.log('='.repeat(80));
    
    const { tripId } = req.params;
    const { reading } = req.body;
    const photo = req.file;
    
    console.log(`📋 Trip ID: ${tripId}`);
    console.log(`📏 Odometer Reading: ${reading}`);
    console.log(`📸 Photo: ${photo ? 'Uploaded' : 'Missing'}`);
    
    if (!reading || !photo) {
      return res.status(400).json({
        success: false,
        message: 'Odometer reading and photo are required'
      });
    }
    
    const trip = await req.db.collection('trips').findOne({
      _id: new ObjectId(tripId)
    });
    
    if (!trip) {
      return res.status(404).json({ success: false, message: 'Trip not found' });
    }
    
    if (trip.status !== 'accepted' && trip.status !== 'confirmed') {
      return res.status(400).json({
        success: false,
        message: 'Trip must be accepted or confirmed before starting'
      });
    }
    
    const bucket = new GridFSBucket(req.db, { bucketName: 'odometer_photos' });
    const uploadStream = bucket.openUploadStream(`start-${tripId}-${Date.now()}.jpg`, {
      metadata: {
        tripId: tripId,
        type: 'start_odometer',
        reading: parseInt(reading),
        uploadedBy: req.user.driverId || req.user.id || req.user.uid,
        uploadedAt: new Date()
      }
    });
    
    uploadStream.end(photo.buffer);
    const photoId = await new Promise((resolve, reject) => {
      uploadStream.on('finish', () => resolve(uploadStream.id));
      uploadStream.on('error', reject);
    });
    
    console.log(`✅ Photo uploaded to GridFS: ${photoId}`);
    
    await req.db.collection('trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: {
          status: 'started',
          actualStartTime: new Date(),
          startOdometer: {
            reading: parseInt(reading),
            photoId: photoId,
            timestamp: new Date()
          },
          'statusHistory.started': new Date(),
          updatedAt: new Date()
        }
      }
    );
    
    console.log(`✅ Trip updated to 'started' status`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Trip started successfully',
      data: {
        tripId: tripId,
        tripNumber: trip.tripNumber,
        status: 'started',
        startOdometer: { reading: parseInt(reading), photoId: photoId.toString() },
        startTime: new Date().toISOString()
      }
    });
    
  } catch (error) {
    console.error('❌ Error starting trip:', error);
    res.status(500).json({ success: false, message: 'Failed to start trip', error: error.message });
  }
});

router.post('/:tripId/location', verifyToken, async (req, res) => {
  try {
    const { tripId } = req.params;
    const { latitude, longitude, speed, heading } = req.body;
    
    if (!latitude || !longitude) {
      return res.status(400).json({ success: false, message: 'Latitude and longitude are required' });
    }
    
    const locationUpdate = {
      latitude: parseFloat(latitude),
      longitude: parseFloat(longitude),
      speed: speed ? parseFloat(speed) : null,
      heading: heading ? parseFloat(heading) : null,
      timestamp: new Date()
    };
    
    await req.db.collection('trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: { currentLocation: locationUpdate, updatedAt: new Date() },
        $push: { locationHistory: { $each: [locationUpdate], $slice: -100 } }
      }
    );
    
    res.json({
      success: true,
      message: 'Location updated',
      data: {
        currentLocation: locationUpdate
      }
    });
    
  } catch (error) {
    console.error('❌ Error updating location:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update location',
      error: error.message
    });
  }
});

router.post('/:tripId/arrive', verifyToken, async (req, res) => {
  try {
    const { tripId } = req.params;
    const { latitude, longitude } = req.body;
    
    await req.db.collection('trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: {
          status: 'in_progress',
          arrivedAt: new Date(),
          arrivalLocation: latitude && longitude ? {
            latitude: parseFloat(latitude),
            longitude: parseFloat(longitude),
            timestamp: new Date()
          } : null,
          'statusHistory.arrived': new Date(),
          updatedAt: new Date()
        }
      }
    );
    
    res.json({
      success: true,
      message: 'Marked as arrived',
      data: {
        tripId: tripId,
        status: 'in_progress',
        arrivedAt: new Date().toISOString()
      }
    });
    
  } catch (error) {
    console.error('❌ Error marking arrival:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to mark arrival',
      error: error.message
    });
  }
});

router.post('/:tripId/depart', verifyToken, async (req, res) => {
  try {
    const { tripId } = req.params;
    const { latitude, longitude } = req.body;
    
    await req.db.collection('trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: {
          departedAt: new Date(),
          departureLocation: latitude && longitude ? {
            latitude: parseFloat(latitude),
            longitude: parseFloat(longitude),
            timestamp: new Date()
          } : null,
          'statusHistory.departed': new Date(),
          updatedAt: new Date()
        }
      }
    );
    
    res.json({
      success: true,
      message: 'Marked as departed',
      data: {
        tripId: tripId,
        departedAt: new Date().toISOString()
      }
    });
    
  } catch (error) {
    console.error('❌ Error marking departure:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to mark departure',
      error: error.message
    });
  }
});

router.post('/:tripId/end', verifyToken, upload.single('photo'), async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🏁 ENDING INDIVIDUAL TRIP');
    console.log('='.repeat(80));
    
    const { tripId } = req.params;
    const { reading } = req.body;
    const photo = req.file;
    
    if (!reading || !photo) {
      return res.status(400).json({ success: false, message: 'End odometer reading and photo are required' });
    }
    
    const trip = await req.db.collection('trips').findOne({ _id: new ObjectId(tripId) });
    if (!trip) {
      return res.status(404).json({ success: false, message: 'Trip not found' });
    }
    
    const bucket = new GridFSBucket(req.db, { bucketName: 'odometer_photos' });
    const uploadStream = bucket.openUploadStream(`end-${tripId}-${Date.now()}.jpg`, {
      metadata: {
        tripId: tripId,
        type: 'end_odometer',
        reading: parseInt(reading),
        uploadedBy: req.user.driverId || req.user.id || req.user.uid,
        uploadedAt: new Date()
      }
    });
    
    uploadStream.end(photo.buffer);
    const photoId = await new Promise((resolve, reject) => {
      uploadStream.on('finish', () => resolve(uploadStream.id));
      uploadStream.on('error', reject);
    });
    
    const startOdometer = trip.startOdometer?.reading || 0;
    const actualDistance = parseInt(reading) - startOdometer;
    const startTime = trip.actualStartTime ? new Date(trip.actualStartTime) : new Date();
    const endTime = new Date();
    const actualDuration = Math.round((endTime - startTime) / 60000);
    
    await req.db.collection('trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: {
          status: 'completed',
          actualEndTime: endTime,
          actualDuration: actualDuration,
          actualDistance: actualDistance,
          endOdometer: { reading: parseInt(reading), photoId: photoId, timestamp: endTime },
          'statusHistory.completed': endTime,
          updatedAt: endTime
        }
      }
    );
    
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Trip completed successfully',
      data: {
        tripId: tripId,
        tripNumber: trip.tripNumber,
        status: 'completed',
        endOdometer: { reading: parseInt(reading), photoId: photoId.toString() },
        startOdometer: startOdometer,
        actualDistance: actualDistance,
        actualDuration: actualDuration,
        completedAt: endTime.toISOString()
      }
    });
    
  } catch (error) {
    console.error('❌ Error ending trip:', error);
    res.status(500).json({ success: false, message: 'Failed to end trip', error: error.message });
  }
});

// ============================================================================
// Group trip endpoints (tripGroupId)
// ============================================================================

router.post('/:tripGroupId/stop/:stopId/arrive', verifyToken, async (req, res) => {
  try {
    const { tripGroupId, stopId } = req.params;
    const { latitude, longitude } = req.body;
    
    const trip = await req.db.collection('trips').findOne({
      tripNumber: tripGroupId
    });
    
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }
    
    await req.db.collection('trips').updateOne(
      { tripNumber: tripGroupId },
      {
        $set: {
          status: 'in_progress',
          arrivedAt: new Date(),
          arrivalLocation: latitude && longitude ? {
            latitude: parseFloat(latitude),
            longitude: parseFloat(longitude),
            timestamp: new Date()
          } : null,
          updatedAt: new Date()
        }
      }
    );
    
    res.json({
      success: true,
      message: 'Marked as arrived',
      data: {
        tripId: trip._id.toString(),
        tripNumber: trip.tripNumber,
        status: 'in_progress',
        arrivedAt: new Date()
      }
    });
    
  } catch (error) {
    console.error('❌ Error marking arrival:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to mark arrival',
      error: error.message
    });
  }
});

router.post('/:tripGroupId/stop/:stopId/depart', verifyToken, async (req, res) => {
  try {
    const { tripGroupId, stopId } = req.params;
    const { latitude, longitude } = req.body;
    
    const trip = await req.db.collection('trips').findOne({
      tripNumber: tripGroupId
    });
    
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }
    
    await req.db.collection('trips').updateOne(
      { tripNumber: tripGroupId },
      {
        $set: {
          status: 'in_progress',
          departedAt: new Date(),
          departureLocation: latitude && longitude ? {
            latitude: parseFloat(latitude),
            longitude: parseFloat(longitude),
            timestamp: new Date()
          } : null,
          updatedAt: new Date()
        }
      }
    );
    
    res.json({
      success: true,
      message: 'Marked as departed',
      data: {
        tripId: trip._id.toString(),
        tripNumber: trip.tripNumber,
        status: 'in_progress',
        departedAt: new Date()
      }
    });
    
  } catch (error) {
    console.error('❌ Error marking departure:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to mark departure',
      error: error.message
    });
  }
});

router.post('/:tripGroupId/end', verifyToken, upload.single('photo'), async (req, res) => {
  try {
    const { tripGroupId } = req.params;
    const { reading } = req.body;
    const photo = req.file;
    
    if (!reading || !photo) {
      return res.status(400).json({
        success: false,
        message: 'End odometer reading and photo are required'
      });
    }
    
    const trip = await req.db.collection('trips').findOne({
      tripNumber: tripGroupId
    });
    
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }
    
    const bucket = new GridFSBucket(req.db, {
      bucketName: 'odometer_photos'
    });
    
    const uploadStream = bucket.openUploadStream(`end-${tripGroupId}-${Date.now()}.jpg`, {
      metadata: {
        tripNumber: tripGroupId,
        type: 'end_odometer',
        reading: parseInt(reading),
        uploadedBy: req.user.driverId || req.user.id,
        uploadedAt: new Date()
      }
    });
    
    uploadStream.end(photo.buffer);
    
    const photoId = await new Promise((resolve, reject) => {
      uploadStream.on('finish', () => resolve(uploadStream.id));
      uploadStream.on('error', reject);
    });
    
    const startReading = trip.startOdometer?.reading || 0;
    const endReading = parseInt(reading);
    const actualDistance = endReading - startReading;
    
    await req.db.collection('trips').updateOne(
      { tripNumber: tripGroupId },
      {
        $set: {
          status: 'completed',
          endOdometer: {
            reading: endReading,
            photoId: photoId,
            timestamp: new Date()
          },
          actualDistance: actualDistance,
          actualEndTime: new Date(),
          actualDuration: trip.actualStartTime ? 
            Math.round((new Date() - new Date(trip.actualStartTime)) / 60000) : null,
          updatedAt: new Date()
        }
      }
    );
    
    res.json({
      success: true,
      message: 'Trip completed successfully!',
      data: {
        tripId: trip._id.toString(),
        tripNumber: trip.tripNumber,
        status: 'completed',
        endOdometer: {
          reading: endReading,
          photoId: photoId.toString()
        },
        actualDistance: actualDistance,
        completedAt: new Date()
      }
    });
    
  } catch (error) {
    console.error('❌ Error ending trip:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to end trip',
      error: error.message
    });
  }
});

router.post('/:tripGroupId/location', verifyToken, async (req, res) => {
  try {
    const { tripGroupId } = req.params;
    const { latitude, longitude, speed, heading } = req.body;
    
    if (!latitude || !longitude) {
      return res.status(400).json({
        success: false,
        message: 'Latitude and longitude are required'
      });
    }
    
    const location = {
      latitude: parseFloat(latitude),
      longitude: parseFloat(longitude),
      speed: speed ? parseFloat(speed) : null,
      heading: heading ? parseFloat(heading) : null,
      timestamp: new Date()
    };
    
    await req.db.collection('trips').updateOne(
      { tripNumber: tripGroupId },
      {
        $set: {
          currentLocation: location,
          updatedAt: new Date()
        },
        $push: {
          locationHistory: {
            $each: [location],
            $slice: -100
          }
        }
      }
    );
    
    res.json({
      success: true,
      message: 'Location updated',
      data: {
        location: location
      }
    });
    
  } catch (error) {
    console.error('❌ Error updating location:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update location',
      error: error.message
    });
  }
});

module.exports = router;

// ============================================================================
// END OF FILE - ALL DONE! 🎉
// ============================================================================