// routes/driver_trip_router.js
// ============================================================================
// DRIVER TRIP MANAGEMENT ROUTER - Complete Fleet Management System
// ============================================================================
// Features:
// ✅ JWT Authentication (no Firebase)
// ✅ GridFS for odometer photos
// ✅ OSRM for routing calculations
// ✅ FCM notifications to customers
// ✅ Real-time GPS tracking
// ✅ Trip grouping by vehicle + tripType
// ✅ FIXED: Proper tripGroupId parsing (vehicleId-tripType)
// ✅ FIXED: Customer notifications (uses 'customers' collection)
// ✅ NEW: Arrival notifications to customers
// ✅ NEW: Feedback request system after departure
// ✅ NEW: Store feedback in driver's profile
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const multer = require('multer');
const { GridFSBucket } = require('mongodb');
const notificationService = require('../services/fcm_service');


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
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed'));
    }
  }
});

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

// Parse time to minutes since midnight
function parseTime(timeStr) {
  if (!timeStr || typeof timeStr !== 'string') return 0;
  if (timeStr.includes(':')) {
    const [hours, minutes] = timeStr.split(':').map(Number);
    return hours * 60 + minutes;
  }
  const numValue = parseInt(timeStr);
  return !isNaN(numValue) ? numValue * 60 : 0;
}

// Format time from minutes to HH:mm
function formatTime(minutes) {
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  return `${hours.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}`;
}

// Calculate ETA using OSRM
async function calculateETA(startLat, startLng, endLat, endLng) {
  try {
    const fetch = (await import('node-fetch')).default;
    const url = `https://router.project-osrm.org/route/v1/driving/${startLng},${startLat};${endLng},${endLat}?overview=false`;
    
    const response = await fetch(url);
    const data = await response.json();
    
    if (data.routes && data.routes.length > 0) {
      const durationMinutes = Math.round(data.routes[0].duration / 60);
      return durationMinutes;
    }
    
    // Fallback: straight-line distance * 3 minutes/km
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
    console.error('❌ ETA calculation failed:', error.message);
    return 30; // Default 30 minutes
  }
}

// ✅ HELPER: Validate and parse tripGroupId
function parseTripGroupId(tripGroupId) {
  if (!tripGroupId || !tripGroupId.includes('-')) {
    throw new Error('Invalid tripGroupId format. Expected: vehicleId-tripType');
  }
  
  const parts = tripGroupId.split('-');
  const vehicleId = parts[0];
  const tripType = parts.slice(1).join('-'); // Handle trip types with hyphens
  
  // Validate vehicleId is 24 hex characters
  if (!vehicleId || vehicleId.length !== 24 || !/^[0-9a-fA-F]{24}$/.test(vehicleId)) {
    throw new Error('Invalid vehicle ID format in tripGroupId');
  }
  
  return { vehicleId, tripType };
}


// ============================================================================
// NOTIFICATION HELPER - Centralized notification creation
// ============================================================================
async function createTripNotification(db, customer, notificationData) {
  try {
    if (!customer || !customer._id) {
      console.log('⚠️ Cannot create notification - invalid customer object');
      return null;
    }

    const notification = {
      userId: customer._id,
      userEmail: customer.email || null,
      userRole: 'customer',
      type: notificationData.type,
      title: notificationData.title,
      body: notificationData.body || notificationData.message,
      message: notificationData.message || notificationData.body,
      data: notificationData.data || {},
      priority: notificationData.priority || 'normal',
      category: notificationData.category || 'trip_updates',
      isRead: false,
      createdAt: new Date(),
      updatedAt: new Date(),
      expiresAt: notificationData.expiresAt || new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      deliveryStatus: notificationData.deliveryStatus || {
        fcm: 'no_devices',
        database: 'success'
      },
      fcmResponse: notificationData.fcmResponse || null,
      channels: notificationData.channels || ['database']
    };

    const result = await db.collection('notifications').insertOne(notification);
    console.log(`✅ Notification created: ${notification.type} for ${customer.email}`);
    return result;
  } catch (error) {
    console.error(`❌ Failed to create notification: ${error.message}`);
    return null;
  }
}

// ============================================================================
// @route   GET /api/driver/trips/today
// @desc    Get today's trips for logged-in driver (GROUPED)
// @access  Private (Driver only)
// ============================================================================
// ============================================================================
// @route   GET /api/driver/trips/today
// @desc    Get today's trips for logged-in driver (GROUPED)
// @access  Private (Driver only)
// ============================================================================
router.get('/trips/today', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📋 FETCHING TODAY\'S TRIPS FOR DRIVER');
    console.log('='.repeat(80));

    const driverId = req.user.driverId || req.user.id || req.user.uid;

    if (!driverId) {
      return res.status(401).json({
        success: false,
        message: 'Driver ID not found in token'
      });
    }

    console.log(`👨‍✈️ Driver ID: ${driverId}`);

    const today = new Date().toISOString().split('T')[0];
    console.log(`📅 Date: ${today}`);

    // ========================================================================
    // STEP 1: Get driver's MongoDB _id from drivers collection
    // ========================================================================
    console.log('🔍 Looking up driver in database...');

    const driver = await req.db.collection('drivers').findOne({
      driverId: driverId
    });

    if (!driver) {
      console.log(`❌ Driver not found with driverId: ${driverId}`);
      return res.status(404).json({
        success: false,
        message: 'Driver not found',
        driverId: driverId
      });
    }

    console.log(`✅ Driver: ${driver.personalInfo?.name || driver.name || 'Unknown'}`);
    console.log(`   MongoDB _id: ${driver._id}`);

    // ========================================================================
    // STEP 2: Fetch all trips for this driver today
    // ========================================================================
    const trips = await req.db.collection('roster-assigned-trips').find({
      driverId: driver._id,
      scheduledDate: today,
      status: { $ne: 'completed' }
    }).toArray();

    console.log(`📦 Found ${trips.length} trip assignment(s)`);

    if (trips.length === 0) {
      return res.json({
        success: true,
        message: 'No trips assigned for today',
        data: [],
        count: 0
      });
    }

    // ========================================================================
    // STEP 3: Group trips by vehicle + tripType
    // ========================================================================
    console.log('\n🔄 Grouping trips by vehicle and trip type...');

    const grouped = {};

    for (const trip of trips) {
      const vehicleId = trip.vehicleId.toString();
      const tripType = trip.tripType || 'both';
      const key = `${vehicleId}-${tripType}`;

      if (!grouped[key]) {
        grouped[key] = {
          vehicleId: trip.vehicleId,
          tripType: tripType,
          scheduledDate: trip.scheduledDate,
          status: trip.status,
          stops: [],
          currentStopIndex: trip.currentStopIndex || 0
        };
      }

      grouped[key].stops.push({
        stopId: trip._id.toString(),
        rosterId: trip.rosterId.toString(),
        sequence: trip.pickupSequence || trip.sequence || 1,
        type: 'pickup',
        customer: {
          name: trip.customerName,
          email: trip.customerEmail,
          phone: trip.customerPhone || ''
        },
        location: {
          address: trip.pickupLocation?.address || 'Pickup location',
          coordinates: trip.pickupLocation?.coordinates || null
        },
        estimatedTime: trip.estimatedPickupTime || trip.startTime,
        readyByTime: trip.readyByTime,
        distanceFromPrevious: trip.distanceFromPrevious || 0,
        distanceToOffice: trip.distanceToOffice || 0,
        status: trip.status === 'started' || trip.status === 'in_progress' ? 'in_progress' : 'pending',
        passengerStatus: trip.passengerStatus || null
      });
    }

    // ========================================================================
    // STEP 4: Process each trip group
    // ========================================================================
    const processedTrips = [];

    for (const [key, group] of Object.entries(grouped)) {
      console.log(`\n📍 Processing trip group: ${key}`);

      group.stops.sort((a, b) => a.sequence - b.sequence);

      const vehicle = await req.db.collection('vehicles').findOne({
        _id: group.vehicleId
      });

      if (!vehicle) {
        console.log(`⚠️ Vehicle not found: ${group.vehicleId}`);
        continue;
      }

      // ✅ FIX: Populate customer phone from customers collection
      console.log('📞 Looking up customer phone numbers...');
      for (const stop of group.stops) {
        if (stop.type === 'pickup' && stop.customer?.email) {
          // Check if phone is missing or empty
          if (!stop.customer.phone || stop.customer.phone.trim() === '') {
            const customerDoc = await req.db.collection('customers').findOne(
              { email: stop.customer.email },
              { projection: { phone: 1 } }
            );
            if (customerDoc?.phone) {
              stop.customer.phone = customerDoc.phone;
              console.log(`   ✅ Phone found for ${stop.customer.name}: ${customerDoc.phone}`);
            } else {
              console.log(`   ⚠️ No phone in customers collection for ${stop.customer.email}`);
            }
          } else {
            console.log(`   ℹ️ Phone already present for ${stop.customer.name}: ${stop.customer.phone}`);
          }
        }
      }

      // Add office drop as final stop
      if (group.stops.length > 0) {
        const firstStop = group.stops[0];
        const officeAddress = trips.find(t =>
          t.vehicleId.toString() === group.vehicleId.toString()
        )?.dropLocation?.address || 'Office';

        const officeCoords = trips.find(t =>
          t.vehicleId.toString() === group.vehicleId.toString()
        )?.dropLocation?.coordinates || null;

        group.stops.push({
          stopId: `office-drop-${group.vehicleId}`,
          sequence: group.stops.length + 1,
          type: 'drop',
          location: {
            address: officeAddress,
            coordinates: officeCoords
          },
          estimatedTime: firstStop.estimatedTime,
          passengers: group.stops.map(s => s.customer.name),
          status: 'pending'
        });
      }

      const totalDistance = group.stops.reduce((sum, stop) =>
        sum + (stop.distanceFromPrevious || 0), 0
      );

      const estimatedDuration = group.stops.reduce((sum, stop) =>
        sum + (stop.estimatedTravelTime || 0), 0
      );

      processedTrips.push({
        tripGroupId: key,
        vehicleId: group.vehicleId.toString(),
        vehicleNumber: vehicle.registrationNumber || vehicle.vehicleNumber || 'Unknown',
        vehicleName: vehicle.name || vehicle.vehicleNumber || 'Unknown',
        tripType: group.tripType,
        scheduledDate: group.scheduledDate,
        status: group.status,
        totalStops: group.stops.length,
        totalDistance: totalDistance,
        estimatedDuration: estimatedDuration,
        stops: group.stops,
        currentStopIndex: group.currentStopIndex || 0,
        driver: {
          id: driver._id.toString(),
          driverId: driver.driverId,
          name: driver.personalInfo?.name || driver.name || 'Unknown',
          phone: driver.personalInfo?.phone || driver.phone || '',
          email: driver.personalInfo?.email || driver.email || ''
        }
      });

      console.log(`✅ Trip group processed: ${group.stops.length} stops, ${totalDistance.toFixed(1)} km`);
      console.log(`   Current stop index: ${group.currentStopIndex || 0}`);
    }

    console.log('\n' + '='.repeat(80));
    console.log(`✅ RETURNING ${processedTrips.length} TRIP GROUP(S)`);
    console.log('='.repeat(80) + '\n');

    res.json({
      success: true,
      message: `Found ${processedTrips.length} trip(s) for today`,
      data: processedTrips,
      count: processedTrips.length
    });

  } catch (error) {
    console.error('❌ Error fetching driver trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch trips',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/driver/trips/today/all
// @desc    Get ALL trips for today (including assigned/not started)
// @access  Private (Driver only)
// ============================================================================
router.get('/trips/today/all', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📋 FETCHING ALL TRIPS FOR TODAY');
    console.log('='.repeat(80));

    const driverId = req.user.driverId || req.user.id || req.user.uid;
    const today = new Date().toISOString().split('T')[0];

    const driver = await req.db.collection('drivers').findOne({ driverId });
    if (!driver) {
      return res.status(404).json({ success: false, message: 'Driver not found' });
    }

    // ========================================================================
    // STEP 1: Check if trips are pre-grouped
    // ========================================================================
    const preGroupedTrips = await req.db.collection('roster-assigned-trips').find({
      driverId: driver._id,
      scheduledDate: today,
      tripGroupId: { $exists: true },
      'stops.0': { $exists: true }
    }).toArray();

    console.log(`📦 Found ${preGroupedTrips.length} pre-grouped trip(s)`);

    if (preGroupedTrips.length > 0) {
      console.log('✅ Using pre-grouped trip documents');

      const processedTrips = [];

      for (const trip of preGroupedTrips) {
        const vehicle = await req.db.collection('vehicles').findOne({ _id: trip.vehicleId });

        // ✅ FIX: Populate customer phone from customers collection
        const enrichedStops = [...(trip.stops || [])];
        console.log('📞 Looking up customer phone numbers...');
        for (const stop of enrichedStops) {
          if (stop.type === 'pickup' && stop.customer?.email) {
            // Check if phone is missing or empty
            if (!stop.customer.phone || stop.customer.phone.trim() === '') {
              const customerDoc = await req.db.collection('customers').findOne(
                { email: stop.customer.email },
                { projection: { phone: 1 } }
              );
              if (customerDoc?.phone) {
                stop.customer.phone = customerDoc.phone;
                console.log(`   ✅ Phone found for ${stop.customer.name}: ${customerDoc.phone}`);
              } else {
                console.log(`   ⚠️ No phone in customers collection for ${stop.customer.email}`);
              }
            } else {
              console.log(`   ℹ️ Phone already present for ${stop.customer.name}: ${stop.customer.phone}`);
            }
          }
        }

        processedTrips.push({
          tripGroupId: trip.tripGroupId,
          vehicleId: trip.vehicleId.toString(),
          vehicleNumber: vehicle?.registrationNumber || vehicle?.vehicleNumber || 'Unknown',
          vehicleName: vehicle?.name || 'Unknown',
          tripType: trip.tripType,
          scheduledDate: trip.scheduledDate,
          status: trip.status || 'assigned',
          totalStops: enrichedStops.length,
          totalDistance: trip.totalDistance || 0,
          estimatedDuration: trip.estimatedDuration || 0,
          stops: enrichedStops,
          currentStopIndex: trip.currentStopIndex || 0,
          driver: {
            id: driver._id.toString(),
            driverId: driver.driverId,
            name: driver.personalInfo?.name || driver.name || 'Unknown',
            phone: driver.personalInfo?.phone || '',
            email: driver.personalInfo?.email || ''
          }
        });
      }

      return res.json({
        success: true,
        message: `Found ${processedTrips.length} trip(s)`,
        data: processedTrips,
        count: processedTrips.length
      });
    }

    // ========================================================================
    // STEP 2: If no pre-grouped trips, try individual records
    // ========================================================================
    console.log('⚠️ No pre-grouped trips found, checking for individual records...');

    const individualTrips = await req.db.collection('roster-assigned-trips').find({
      driverId: driver._id,
      scheduledDate: today
    }).toArray();

    console.log(`📦 Found ${individualTrips.length} individual trip(s)`);

    if (individualTrips.length === 0) {
      return res.json({
        success: true,
        message: 'No trips assigned for today',
        data: [],
        count: 0
      });
    }

    console.log('🔄 Grouping individual trips...');

    const grouped = {};

    for (const trip of individualTrips) {
      const vehicleId = trip.vehicleId?.toString() || 'unknown';
      const tripType = trip.tripType || 'both';
      const key = `${vehicleId}-${tripType}`;

      if (!grouped[key]) {
        grouped[key] = {
          vehicleId: trip.vehicleId,
          tripType: tripType,
          scheduledDate: trip.scheduledDate,
          status: trip.status || 'assigned',
          stops: []
        };
      }

      grouped[key].stops.push({
        stopId: trip._id.toString(),
        rosterId: trip.rosterId?.toString() || '',
        sequence: trip.pickupSequence || trip.sequence || 1,
        type: 'pickup',
        customer: {
          name: trip.customerName || 'Unknown',
          email: trip.customerEmail || '',
          phone: trip.customerPhone || ''
        },
        location: {
          address: trip.pickupLocation?.address || 'Pickup location',
          coordinates: trip.pickupLocation?.coordinates || null
        },
        estimatedTime: trip.estimatedPickupTime || trip.startTime || '00:00',
        readyByTime: trip.readyByTime || '00:00',
        distanceFromPrevious: trip.distanceFromPrevious || 0,
        distanceToOffice: trip.distanceToOffice || 0,
        status: trip.status || 'assigned',
        passengerStatus: trip.passengerStatus || null
      });
    }

    const processedTrips = [];

    for (const [key, group] of Object.entries(grouped)) {
      group.stops.sort((a, b) => a.sequence - b.sequence);

      const vehicle = await req.db.collection('vehicles').findOne({ _id: group.vehicleId });

      // ✅ FIX: Populate customer phone from customers collection
      console.log('📞 Looking up customer phone numbers...');
      for (const stop of group.stops) {
        if (stop.type === 'pickup' && stop.customer?.email) {
          // Check if phone is missing or empty
          if (!stop.customer.phone || stop.customer.phone.trim() === '') {
            const customerDoc = await req.db.collection('customers').findOne(
              { email: stop.customer.email },
              { projection: { phone: 1 } }
            );
            if (customerDoc?.phone) {
              stop.customer.phone = customerDoc.phone;
              console.log(`   ✅ Phone found for ${stop.customer.name}: ${customerDoc.phone}`);
            } else {
              console.log(`   ⚠️ No phone in customers collection for ${stop.customer.email}`);
            }
          } else {
            console.log(`   ℹ️ Phone already present for ${stop.customer.name}: ${stop.customer.phone}`);
          }
        }
      }

      // Add office drop
      if (group.stops.length > 0) {
        const officeAddress = individualTrips.find(t =>
          t.vehicleId?.toString() === group.vehicleId?.toString()
        )?.dropLocation?.address || 'Office';

        group.stops.push({
          stopId: `office-drop-${group.vehicleId}`,
          sequence: group.stops.length + 1,
          type: 'drop',
          location: { address: officeAddress, coordinates: null },
          estimatedTime: group.stops[0].estimatedTime,
          passengers: group.stops.map(s => s.customer.name),
          status: 'pending'
        });
      }

      const totalDistance = group.stops.reduce((sum, stop) => sum + (stop.distanceFromPrevious || 0), 0);

      processedTrips.push({
        tripGroupId: key,
        vehicleId: group.vehicleId.toString(),
        vehicleNumber: vehicle?.registrationNumber || 'Unknown',
        vehicleName: vehicle?.name || 'Unknown',
        tripType: group.tripType,
        scheduledDate: group.scheduledDate,
        status: group.status,
        totalStops: group.stops.length,
        totalDistance: totalDistance,
        estimatedDuration: 0,
        stops: group.stops,
        currentStopIndex: 0,
        driver: {
          id: driver._id.toString(),
          driverId: driver.driverId,
          name: driver.personalInfo?.name || 'Unknown',
          phone: driver.personalInfo?.phone || '',
          email: driver.personalInfo?.email || ''
        }
      });
    }

    console.log(`✅ RETURNING ${processedTrips.length} TRIP GROUP(S)\n`);

    res.json({
      success: true,
      message: `Found ${processedTrips.length} trip(s)`,
      data: processedTrips,
      count: processedTrips.length
    });

  } catch (error) {
    console.error('❌ Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch trips',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/driver/trips/today/all
// @desc    Get ALL trips for today (including assigned/not started)
// @access  Private (Driver only)
// ============================================================================
router.get('/trips/today/all', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📋 FETCHING ALL TRIPS FOR TODAY');
    console.log('='.repeat(80));
    
    const driverId = req.user.driverId || req.user.id || req.user.uid;
    const today = new Date().toISOString().split('T')[0];
    
    // Get driver
    const driver = await req.db.collection('drivers').findOne({ driverId });
    if (!driver) {
      return res.status(404).json({ success: false, message: 'Driver not found' });
    }
    
    // ========================================================================
    // STEP 1: Check if trips are pre-grouped
    // ========================================================================
    const preGroupedTrips = await req.db.collection('roster-assigned-trips').find({
      driverId: driver._id,
      scheduledDate: today,
      tripGroupId: { $exists: true },
      'stops.0': { $exists: true } // Has stops array
    }).toArray();
    
    console.log(`📦 Found ${preGroupedTrips.length} pre-grouped trip(s)`);
    
    if (preGroupedTrips.length > 0) {
      // ✅ USE PRE-GROUPED DATA
      console.log('✅ Using pre-grouped trip documents');
      
      const processedTrips = [];
      
      for (const trip of preGroupedTrips) {
        const vehicle = await req.db.collection('vehicles').findOne({ _id: trip.vehicleId });
        
        processedTrips.push({
          tripGroupId: trip.tripGroupId,
          vehicleId: trip.vehicleId.toString(),
          vehicleNumber: vehicle?.registrationNumber || vehicle?.vehicleNumber || 'Unknown',
          vehicleName: vehicle?.name || 'Unknown',
          tripType: trip.tripType,
          scheduledDate: trip.scheduledDate,
          status: trip.status || 'assigned',
          totalStops: trip.stops?.length || 0,
          totalDistance: trip.totalDistance || 0,
          estimatedDuration: trip.estimatedDuration || 0,
          stops: trip.stops || [],
          driver: {
            id: driver._id.toString(),
            driverId: driver.driverId,
            name: driver.personalInfo?.name || driver.name || 'Unknown',
            phone: driver.personalInfo?.phone || '',
            email: driver.personalInfo?.email || ''
          }
        });
      }
      
      return res.json({
        success: true,
        message: `Found ${processedTrips.length} trip(s)`,
        data: processedTrips,
        count: processedTrips.length
      });
    }
    
    // ========================================================================
    // STEP 2: If no pre-grouped trips, try individual records
    // ========================================================================
    console.log('⚠️ No pre-grouped trips found, checking for individual records...');
    
    const individualTrips = await req.db.collection('roster-assigned-trips').find({
      driverId: driver._id,
      scheduledDate: today
    }).toArray();
    
    console.log(`📦 Found ${individualTrips.length} individual trip(s)`);
    
    if (individualTrips.length === 0) {
      return res.json({
        success: true,
        message: 'No trips assigned for today',
        data: [],
        count: 0
      });
    }
    
    // ✅ GROUP INDIVIDUAL TRIPS
    console.log('🔄 Grouping individual trips...');
    
    const grouped = {};
    
    for (const trip of individualTrips) {
      const vehicleId = trip.vehicleId?.toString() || 'unknown';
      const tripType = trip.tripType || 'both';
      const key = `${vehicleId}-${tripType}`;
      
      if (!grouped[key]) {
        grouped[key] = {
          vehicleId: trip.vehicleId,
          tripType: tripType,
          scheduledDate: trip.scheduledDate,
          status: trip.status || 'assigned',
          stops: []
        };
      }
      
      grouped[key].stops.push({
        stopId: trip._id.toString(),
        rosterId: trip.rosterId?.toString() || '',
        sequence: trip.pickupSequence || trip.sequence || 1,
        type: 'pickup',
        customer: {
          name: trip.customerName || 'Unknown',
          email: trip.customerEmail || '',
          phone: trip.customerPhone || ''
        },
        location: {
          address: trip.pickupLocation?.address || 'Pickup location',
          coordinates: trip.pickupLocation?.coordinates || null
        },
        estimatedTime: trip.estimatedPickupTime || trip.startTime || '00:00',
        readyByTime: trip.readyByTime || '00:00',
        distanceFromPrevious: trip.distanceFromPrevious || 0,
        distanceToOffice: trip.distanceToOffice || 0,
        status: trip.status || 'assigned',
        passengerStatus: trip.passengerStatus || null
      });
    }
    
    // Process grouped trips
    const processedTrips = [];
    
    for (const [key, group] of Object.entries(grouped)) {
      group.stops.sort((a, b) => a.sequence - b.sequence);
      
      const vehicle = await req.db.collection('vehicles').findOne({ _id: group.vehicleId });
      
      // Add office drop
      if (group.stops.length > 0) {
        const officeAddress = individualTrips.find(t => 
          t.vehicleId?.toString() === group.vehicleId?.toString()
        )?.dropLocation?.address || 'Office';
        
        group.stops.push({
          stopId: `office-drop-${group.vehicleId}`,
          sequence: group.stops.length + 1,
          type: 'drop',
          location: { address: officeAddress, coordinates: null },
          estimatedTime: group.stops[0].estimatedTime,
          passengers: group.stops.map(s => s.customer.name),
          status: 'pending'
        });
      }
      
      const totalDistance = group.stops.reduce((sum, stop) => sum + (stop.distanceFromPrevious || 0), 0);
      
      processedTrips.push({
        tripGroupId: key,
        vehicleId: group.vehicleId.toString(),
        vehicleNumber: vehicle?.registrationNumber || 'Unknown',
        vehicleName: vehicle?.name || 'Unknown',
        tripType: group.tripType,
        scheduledDate: group.scheduledDate,
        status: group.status,
        totalStops: group.stops.length,
        totalDistance: totalDistance,
        estimatedDuration: 0,
        stops: group.stops,
        driver: {
          id: driver._id.toString(),
          driverId: driver.driverId,
          name: driver.personalInfo?.name || 'Unknown',
          phone: driver.personalInfo?.phone || '',
          email: driver.personalInfo?.email || ''
        }
      });
    }
    
    console.log(`✅ RETURNING ${processedTrips.length} TRIP GROUP(S)\n`);
    
    res.json({
      success: true,
      message: `Found ${processedTrips.length} trip(s)`,
      data: processedTrips,
      count: processedTrips.length
    });
    
  } catch (error) {
    console.error('❌ Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch trips',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/driver/trips/:tripGroupId/start
// @desc    Start a trip with odometer photo
// @access  Private (Driver only)
// ============================================================================
// ============================================================================
// @route   POST /api/driver/trips/:tripGroupId/start
// @desc    Start a trip with odometer photo
// @access  Private (Driver only)
// ============================================================================
router.post('/trips/:tripGroupId/start', verifyToken, upload.single('photo'), async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🚀 STARTING TRIP');
    console.log('='.repeat(80));
    
    const { tripGroupId } = req.params;
    const { reading } = req.body;
    const photo = req.file;
    
    console.log(`📋 Trip Group ID: ${tripGroupId}`);
    console.log(`📏 Odometer Reading: ${reading}`);
    console.log(`📸 Photo: ${photo ? 'Uploaded' : 'Missing'}`);
    
    // Validate inputs
    if (!reading || !photo) {
      return res.status(400).json({
        success: false,
        message: 'Odometer reading and photo are required'
      });
    }
    
    const driverId = req.user.driverId || req.user.id || req.user.uid;
    const today = new Date().toISOString().split('T')[0];
    
    // ========================================================================
    // STEP 0: Get driver's MongoDB _id
    // ========================================================================
    console.log(`🔍 Looking up driver: ${driverId}`);
    
    const driver = await req.db.collection('drivers').findOne({
      driverId: driverId
    });
    
    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found',
        driverId: driverId
      });
    }
    
    const driverMongoId = driver._id;
    console.log(`✅ Driver found: ${driver.personalInfo?.name || driver.name || 'Unknown'}`);
    console.log(`   MongoDB _id: ${driverMongoId}`);
    
    // ========================================================================
    // STEP 1: Upload photo to GridFS
    // ========================================================================
    console.log('📤 Uploading odometer photo to GridFS...');
    
    const bucket = new GridFSBucket(req.db, {
      bucketName: 'odometer_photos'
    });
    
    const uploadStream = bucket.openUploadStream(`start-${tripGroupId}-${Date.now()}.jpg`, {
      metadata: {
        tripGroupId: tripGroupId,
        type: 'start_odometer',
        reading: parseInt(reading),
        uploadedBy: driverId,
        uploadedAt: new Date()
      }
    });
    
    uploadStream.end(photo.buffer);
    
    const photoId = await new Promise((resolve, reject) => {
      uploadStream.on('finish', () => resolve(uploadStream.id));
      uploadStream.on('error', reject);
    });
    
    console.log(`✅ Photo uploaded to GridFS: ${photoId}`);
    
    // ========================================================================
    // STEP 2: Update trip(s) in database - Try both methods
    // ========================================================================
    console.log('📝 Updating trips in database...');
    console.log(`   Looking for tripGroupId: ${tripGroupId}`);
    console.log(`   Driver: ${driverMongoId}`);
    
    // ✅ METHOD 1: Try pre-grouped trip (single document with all stops)
    let updateResult = await req.db.collection('roster-assigned-trips').updateMany(
      {
        tripGroupId: tripGroupId,
        driverId: driverMongoId
      },
      {
        $set: {
          status: 'started',
          actualStartTime: new Date(),
          startOdometer: {
            reading: parseInt(reading),
            photoId: photoId,
            timestamp: new Date()
          },
          updatedAt: new Date()
        }
      }
    );
    
    console.log(`📊 Pre-grouped query matched: ${updateResult.matchedCount} document(s)`);
    console.log(`📊 Pre-grouped query modified: ${updateResult.modifiedCount} document(s)`);
    
    // ✅ METHOD 2: If no match, try individual trip records (fallback)
    if (updateResult.matchedCount === 0) {
      console.log('⚠️ No pre-grouped trip found, trying individual records...');
      
      // Parse tripGroupId to extract vehicle and type
      let vehicleId, tripType;
      try {
        const parsed = parseTripGroupId(tripGroupId);
        vehicleId = parsed.vehicleId;
        tripType = parsed.tripType;
        console.log(`   Parsed - Vehicle: ${vehicleId}, Type: ${tripType}`);
      } catch (parseError) {
        console.log(`❌ Failed to parse tripGroupId: ${parseError.message}`);
        return res.status(400).json({
          success: false,
          message: 'Invalid trip group ID format'
        });
      }
      
      updateResult = await req.db.collection('roster-assigned-trips').updateMany(
        {
          vehicleId: new ObjectId(vehicleId),
          tripType: tripType,
          scheduledDate: today,
          driverId: driverMongoId
        },
        {
          $set: {
            status: 'started',
            actualStartTime: new Date(),
            startOdometer: {
              reading: parseInt(reading),
              photoId: photoId,
              timestamp: new Date()
            },
            updatedAt: new Date()
          }
        }
      );
      
      console.log(`📊 Individual query matched: ${updateResult.matchedCount} document(s)`);
      console.log(`📊 Individual query modified: ${updateResult.modifiedCount} document(s)`);
    }
    
    console.log(`✅ Updated ${updateResult.modifiedCount} trip(s) to 'started'`);
    
    if (updateResult.modifiedCount === 0) {
      console.log('❌ No trips were updated!');
      console.log('   Possible reasons:');
      console.log('   1. Trip already started');
      console.log('   2. Trip assigned to different driver');
      console.log('   3. Trip for different date');
      console.log('   4. Trip not found in database');
      
      return res.status(404).json({
        success: false,
        message: 'No trips found to start. Please refresh and try again.'
      });
    }
    
    // ========================================================================
    // STEP 3: Get trip details for notifications
    // ========================================================================
    console.log('\n📲 SENDING NOTIFICATIONS TO CUSTOMERS');
    console.log('='.repeat(60));
    
    // Get trip document(s)
    let trips = await req.db.collection('roster-assigned-trips').find({
      tripGroupId: tripGroupId,
      driverId: driverMongoId
    }).toArray();
    
    // If no pre-grouped trip, get individual trips
    if (trips.length === 0) {
      const parsed = parseTripGroupId(tripGroupId);
      trips = await req.db.collection('roster-assigned-trips').find({
        vehicleId: new ObjectId(parsed.vehicleId),
        tripType: parsed.tripType,
        scheduledDate: today,
        driverId: driverMongoId
      }).toArray();
    }
    
    console.log(`📦 Found ${trips.length} trip document(s) for notifications`);
    
    // Get vehicle details
    const vehicleId = trips[0]?.vehicleId;
    const vehicle = await req.db.collection('vehicles').findOne({
      _id: vehicleId
    });
    
    const driverName = driver.personalInfo?.name || driver.name || 'Your driver';
    const driverPhone = driver.personalInfo?.phone || driver.phone || '';
    const vehicleNumber = vehicle?.registrationNumber || vehicle?.vehicleNumber || 'N/A';
    
    // Track notification success
    let totalDevicesNotified = 0;
    let totalCustomersProcessed = 0;
    
    // ========================================================================
    // STEP 4: Send notifications to each customer
    // ========================================================================
    for (const trip of trips) {
      try {
        // Handle both pre-grouped (with stops array) and individual trips
        let customers = [];
        
        if (trip.stops && Array.isArray(trip.stops)) {
          // Pre-grouped trip - extract customers from stops
          customers = trip.stops
            .filter(stop => stop.type === 'pickup' && stop.customer)
            .map(stop => ({
              email: stop.customer.email,
              name: stop.customer.name
            }));
        } else if (trip.customerEmail) {
          // Individual trip - single customer
          customers = [{
            email: trip.customerEmail,
            name: trip.customerName
          }];
        }
        
        for (const customerInfo of customers) {
          console.log(`\n📧 Processing customer: ${customerInfo.name || customerInfo.email}`);
          
          // Find customer in customers collection
          const customer = await req.db.collection('customers').findOne({
            email: customerInfo.email
          });
          
          if (!customer) {
            console.log(`   ⚠️ Customer not found: ${customerInfo.email}`);
            continue;
          }
          
          console.log(`   ✅ Customer found: ${customer.name || customer.email}`);
          
          // Calculate ETA
          let eta = 30; // Default 30 minutes
          const tripNumber = trip.tripNumber || tripGroupId.substring(0, 8);
          
          // Get customer devices
          const devices = await req.db.collection('user_devices').find({
            $or: [
              { userEmail: customerInfo.email },
              { userId: customer._id.toString() }
            ],
            isActive: true
          }).toArray();
          
          console.log(`   📱 Found ${devices.length} device(s)`);
          
          let fcmSuccessCount = 0;
          const fcmErrors = [];
          
          // Send FCM to all devices
          for (const device of devices) {
            try {
              await notificationService.send({
                deviceToken: device.deviceToken,
                deviceType: device.deviceType || 'android',
                title: '🚗 Your Driver Has Started!',
                body: `${driverName} is on the way. ETA: ${eta} min. Vehicle: ${vehicleNumber}`,
                data: {
                  type: 'trip_started',
                  tripId: trip._id.toString(),
                  tripNumber: tripNumber,
                  tripGroupId: tripGroupId,
                  driverName: driverName,
                  driverPhone: driverPhone,
                  vehicleNumber: vehicleNumber,
                  eta: eta.toString(),
                },
                priority: 'high'
              });
              
              fcmSuccessCount++;
              totalDevicesNotified++;
              console.log(`   ✅ FCM sent to ${device.deviceType}`);
            } catch (fcmError) {
              console.log(`   ❌ FCM failed: ${fcmError.message}`);
              fcmErrors.push({
                deviceType: device.deviceType,
                error: fcmError.message
              });
            }
          }
          
          // Save to database
          await createTripNotification(req.db, customer, {
            type: 'trip_started',
            title: '🚗 Your Driver Has Started!',
            body: `${driverName} is on the way. ETA: ${eta} min`,
            message: `Your driver ${driverName} has started the trip.\n\nTrip: ${tripNumber}\nVehicle: ${vehicleNumber}\nETA: ${eta} minutes\n\nPlease be ready at your pickup location.`,
            data: {
              tripId: trip._id.toString(),
              tripNumber: tripNumber,
              tripGroupId: tripGroupId,
              driverName: driverName,
              driverPhone: driverPhone,
              vehicleNumber: vehicleNumber,
              eta: eta,
            },
            priority: 'high',
            category: 'trip_updates',
            expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
            deliveryStatus: {
              fcm: fcmSuccessCount > 0 ? 'success' : 'no_devices',
              database: 'success'
            },
            fcmResponse: {
              success: fcmSuccessCount,
              failed: devices.length - fcmSuccessCount,
              errors: fcmErrors
            },
            channels: fcmSuccessCount > 0 ? ['fcm', 'database'] : ['database']
          });
          
          console.log(`   ✅ Database notification saved`);
          totalCustomersProcessed++;
        }
      } catch (customerError) {
        console.log(`   ❌ Error processing customer: ${customerError.message}`);
      }
    }
    
    console.log('='.repeat(60));
    console.log(`✅ Notification Summary:`);
    console.log(`   Customers processed: ${totalCustomersProcessed}`);
    console.log(`   Total devices notified: ${totalDevicesNotified}`);
    console.log('='.repeat(60) + '\n');
    
    console.log('='.repeat(80));
    console.log('✅ TRIP STARTED SUCCESSFULLY');
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Trip started successfully',
      data: {
        tripGroupId: tripGroupId,
        startOdometer: {
          reading: parseInt(reading),
          photoId: photoId.toString()
        },
        status: 'started',
        notificationsSent: {
          customers: totalCustomersProcessed,
          devices: totalDevicesNotified
        },
        tripsUpdated: updateResult.modifiedCount
      }
    });
    
  } catch (error) {
    console.error('❌ Error starting trip:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to start trip',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/driver/trips/:tripGroupId/stop/:stopId/arrive
// @desc    Mark arrival at specific stop in pre-grouped trip
// @access  Private (Driver only)
// ============================================================================
router.post('/trips/:tripGroupId/stop/:stopId/arrive', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log(`📍 DRIVER ARRIVED AT STOP`);
    console.log('='.repeat(80));
    
    const { tripGroupId, stopId } = req.params;
    const { latitude, longitude } = req.body;
    
    console.log(`🆔 Trip Group ID: ${tripGroupId}`);
    console.log(`📍 Stop ID: ${stopId}`);
    
    // ========================================================================
    // STEP 1: Find the pre-grouped trip document
    // ========================================================================
    const trip = await req.db.collection('roster-assigned-trips').findOne({
      tripGroupId: tripGroupId
    });
    
    if (!trip) {
      console.log('❌ Trip group not found');
      return res.status(404).json({
        success: false,
        message: 'Trip not found. Please refresh and try again.'
      });
    }
    
    console.log(`✅ Trip found: ${trip.tripNumber}`);
    console.log(`   Total stops: ${trip.stops?.length || 0}`);
    console.log(`   Current status: ${trip.status}`);
    
    // ========================================================================
    // STEP 2: Find the specific stop in the stops array
    // ========================================================================
    const stopIndex = trip.stops.findIndex(s => s.stopId === stopId);
    
    if (stopIndex === -1) {
      console.log(`❌ Stop not found: ${stopId}`);
      return res.status(404).json({
        success: false,
        message: 'Stop not found in trip'
      });
    }
    
    const stop = trip.stops[stopIndex];
    console.log(`✅ Stop found: ${stop.customer?.name || 'Drop'}`);
    console.log(`   Type: ${stop.type}`);
    console.log(`   Sequence: ${stop.sequence}`);
    
    // ========================================================================
    // STEP 3: Update the stop status AND overall trip status
    // ========================================================================
    console.log('📝 Updating stop status...');
    
    const updateResult = await req.db.collection('roster-assigned-trips').updateOne(
      { tripGroupId: tripGroupId },
      {
        $set: {
          [`stops.${stopIndex}.status`]: 'arrived',
          [`stops.${stopIndex}.arrivedAt`]: new Date(),
          [`stops.${stopIndex}.arrivalLocation`]: latitude && longitude ? {
            latitude: parseFloat(latitude),
            longitude: parseFloat(longitude),
            timestamp: new Date()
          } : null,
          status: 'in_progress',  // ✅ CRITICAL: Update overall trip status
          updatedAt: new Date()
        }
      }
    );
    
    if (updateResult.matchedCount === 0) {
      console.log('❌ Failed to update trip');
      return res.status(500).json({
        success: false,
        message: 'Failed to update trip status'
      });
    }
    
    console.log(`✅ Stop status updated to 'arrived'`);
    console.log(`✅ Trip status updated to 'in_progress'`);
    
    // ========================================================================
    // STEP 4: Send Arrival Notification to Customer (only for pickup stops)
    // ========================================================================
    if (stop.type === 'pickup' && stop.customer) {
      console.log(`\n📍 SENDING ARRIVAL NOTIFICATION TO CUSTOMER`);
      console.log('='.repeat(60));
      
      try {
        // Find customer
        const customer = await req.db.collection('customers').findOne({
          email: stop.customer.email
        });
        
        if (!customer) {
          console.log(`⚠️  Customer not found: ${stop.customer.email}`);
        } else {
          console.log(`✅ Customer found: ${customer.name || customer.email}`);
          
          // Get driver info
          const driver = await req.db.collection('drivers').findOne({
            _id: trip.driverId
          });
          
          const driverName = driver?.personalInfo?.name || driver?.name || 'Your driver';
          const driverPhone = driver?.personalInfo?.phone || driver?.phone || '';
          
          // Get all customer devices
          const devices = await req.db.collection('user_devices').find({
            $or: [
              { userEmail: stop.customer.email },
              { userId: customer._id.toString() }
            ],
            isActive: true
          }).toArray();
          
          console.log(`📱 Found ${devices.length} device(s) for customer`);
          
          let fcmSuccessCount = 0;
          const fcmErrors = [];
          
          // Send FCM to all devices
          for (const device of devices) {
            try {
              await notificationService.send({
                deviceToken: device.deviceToken,
                deviceType: device.deviceType || 'android',
                title: '📍 Driver Has Arrived!',
                body: `${driverName} is waiting at your pickup location. Vehicle: ${trip.vehicleNumber}`,
                data: {
                  type: 'driver_arrived',
                  tripGroupId: tripGroupId,
                  stopId: stopId,
                  driverName: driverName,
                  driverPhone: driverPhone,
                  vehicleNumber: trip.vehicleNumber,
                  pickupAddress: stop.location?.address || 'Your location',
                },
                priority: 'urgent'
              });
              
              fcmSuccessCount++;
              console.log(`✅ FCM sent to ${device.deviceType}`);
            } catch (fcmError) {
              console.log(`⚠️  FCM failed for ${device.deviceType}: ${fcmError.message}`);
              fcmErrors.push({ deviceType: device.deviceType, error: fcmError.message });
            }
          }

          // Create notification helper
          const createTripNotification = async (db, customer, notificationData) => {
            const notification = {
              userId: customer._id,
              userEmail: customer.email || null,
              userRole: 'customer',
              type: notificationData.type,
              title: notificationData.title,
              body: notificationData.body || notificationData.message,
              message: notificationData.message || notificationData.body,
              data: notificationData.data || {},
              priority: notificationData.priority || 'normal',
              category: notificationData.category || 'trip_updates',
              isRead: false,
              createdAt: new Date(),
              updatedAt: new Date(),
              expiresAt: notificationData.expiresAt || new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
              deliveryStatus: notificationData.deliveryStatus || {
                fcm: 'no_devices',
                database: 'success'
              },
              fcmResponse: notificationData.fcmResponse || null,
              channels: notificationData.channels || ['database']
            };
            
            const result = await db.collection('notifications').insertOne(notification);
            console.log(`✅ Database notification created`);
            return result;
          };

          await createTripNotification(req.db, customer, {
            type: 'driver_arrived',
            title: '📍 Driver Has Arrived!',
            body: `${driverName} is waiting at your location`,
            message: `Your driver ${driverName} has arrived at your pickup location.\n\nVehicle: ${trip.vehicleNumber}\nPhone: ${driverPhone}\n\nPlease proceed to the vehicle.`,
            data: {
              tripGroupId: tripGroupId,
              stopId: stopId,
              driverName: driverName,
              driverPhone: driverPhone,
              vehicleNumber: trip.vehicleNumber,
              pickupAddress: stop.location?.address || 'Your location',
            },
            priority: 'urgent',
            category: 'trip_updates',
            expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
            deliveryStatus: {
              fcm: fcmSuccessCount > 0 ? 'success' : 'no_devices',
              database: 'success'
            },
            fcmResponse: {
              success: fcmSuccessCount,
              failed: devices.length - fcmSuccessCount,
              errors: fcmErrors
            },
            channels: fcmSuccessCount > 0 ? ['fcm', 'database'] : ['database']
          });
          console.log(`✅ Database notification saved`);
          console.log(`📊 Notification sent to ${fcmSuccessCount}/${devices.length} device(s)`);
        }
      } catch (notificationError) {
        console.log(`⚠️  Notification error: ${notificationError.message}`);
      }
      
      console.log('='.repeat(60));
    }
    
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Marked as arrived and customer notified',
      data: {
        tripGroupId: tripGroupId,
        stopId: stopId,
        stopStatus: 'arrived',
        arrivedAt: new Date(),
        customerNotified: stop.type === 'pickup',
        tripStatus: 'in_progress'  // ✅ Return updated trip status
      }
    });
    
  } catch (error) {
    console.error('❌ Error marking arrival:', error);
    console.error('Stack trace:', error.stack);
    res.status(500).json({
      success: false,
      message: 'Failed to mark arrival',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/driver/trips/:tripGroupId/stop/:stopId/depart
// @desc    Mark departure from specific stop in pre-grouped trip
// @access  Private (Driver only)
// ============================================================================
// ============================================================================
// @route   POST /api/driver/trips/:tripGroupId/stop/:stopId/depart
// @desc    Mark departure from specific stop in pre-grouped trip
// @access  Private (Driver only)
// ============================================================================
// ============================================================================
// @route   POST /api/driver/trips/:tripGroupId/stop/:stopId/depart
// @desc    Mark departure from specific stop in pre-grouped trip
// @access  Private (Driver only)
// ============================================================================
router.post('/trips/:tripGroupId/stop/:stopId/depart', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🚗 DEPARTING FROM STOP');
    console.log('='.repeat(80));
    
    const { tripGroupId, stopId } = req.params;
    const { latitude, longitude } = req.body;
    
    console.log(`🆔 Trip Group ID: ${tripGroupId}`);
    console.log(`📍 Stop ID: ${stopId}`);
    
    // Find trip
    const trip = await req.db.collection('roster-assigned-trips').findOne({
      tripGroupId: tripGroupId
    });
    
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }
    
    // Find stop
    const stopIndex = trip.stops.findIndex(s => s.stopId === stopId);
    
    if (stopIndex === -1) {
      return res.status(404).json({
        success: false,
        message: 'Stop not found'
      });
    }
    
    const stop = trip.stops[stopIndex];
    console.log(`✅ Stop found: ${stop.customer?.name || 'Drop'}`);
    console.log(`   Stop index in array: ${stopIndex}`);
    console.log(`   Stop ID in array: ${stop.stopId}`);
    
    // ✅ CRITICAL FIX: Update stop status AND currentStopIndex
    const updateResult = await req.db.collection('roster-assigned-trips').updateOne(
      { tripGroupId: tripGroupId },
      {
        $set: {
          [`stops.${stopIndex}.status`]: 'completed',
          [`stops.${stopIndex}.departedAt`]: new Date(),
          [`stops.${stopIndex}.departureLocation`]: latitude && longitude ? {
            latitude: parseFloat(latitude),
            longitude: parseFloat(longitude),
            timestamp: new Date()
          } : null,
          currentStopIndex: stopIndex + 1,  // ✅ CRITICAL: Store in MongoDB!
          status: 'in_progress',  // ✅ Update overall trip status
          updatedAt: new Date()
        }
      }
    );
    
    if (updateResult.matchedCount === 0) {
      return res.status(500).json({
        success: false,
        message: 'Failed to update trip'
      });
    }
    
    console.log(`✅ Stop marked as completed`);
    console.log(`✅ Updated currentStopIndex to: ${stopIndex + 1}`);
    console.log(`✅ Updated trip status to: in_progress`);
    
    // ========================================================================
    // ⭐ REQUEST FEEDBACK FOR PICKUP STOPS
    // ========================================================================
    if (stop.type === 'pickup' && stop.customer) {
      console.log('\n⭐ REQUESTING CUSTOMER FEEDBACK');
      console.log('='.repeat(60));
      
      try {
        const customer = await req.db.collection('customers').findOne({
          email: stop.customer.email
        });
        
        if (customer) {
          console.log(`✅ Customer found: ${customer.name || customer.email}`);
          
          const driver = await req.db.collection('drivers').findOne({
            _id: trip.driverId
          });
          
          const driverName = driver?.personalInfo?.name || driver?.name || 'Your driver';
          
          // Get devices
          const devices = await req.db.collection('user_devices').find({
            $or: [
              { userEmail: stop.customer.email },
              { userId: customer._id.toString() }
            ],
            isActive: true
          }).toArray();
          
          console.log(`📱 Found ${devices.length} device(s)`);
          
          let fcmSuccessCount = 0;
          
          // Send FCM
          for (const device of devices) {
            try {
              await notificationService.send({
                deviceToken: device.deviceToken,
                deviceType: device.deviceType || 'android',
                title: '⭐ How was your ride?',
                body: `Please rate your experience with ${driverName}`,
                data: {
                  type: 'feedback_request',
                  tripId: trip._id.toString(),  // ✅ FIXED: Use main trip document _id
                  stopId: stop.stopId,           // Keep for reference
                  tripNumber: trip.tripNumber || tripGroupId.substring(0, 8),
                  driverName: driverName,
                  driverId: trip.driverId.toString(),
                  action: 'open_feedback',
                },
                priority: 'high'
              });
              
              fcmSuccessCount++;
              console.log(`✅ FCM sent to ${device.deviceType}`);
            } catch (fcmError) {
              console.log(`⚠️ FCM failed: ${fcmError.message}`);
            }
          }
          
          // Save feedback request
          const feedbackRequestResult = await req.db.collection('feedback_requests').insertOne({
            tripId: trip._id,              // ✅ FIXED: Use main trip document _id
            tripGroupId: tripGroupId,
            stopId: stop.stopId,
            customerId: customer._id,
            customerEmail: customer.email,
            driverId: trip.driverId,
            driverName: driverName,
            requestedAt: new Date(),
            status: 'pending',
            feedbackGiven: false,
            expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
          });
          
          console.log(`✅ Feedback request saved: ${feedbackRequestResult.insertedId}`);
          
          // Create notification helper
          const createTripNotification = async (db, customer, notificationData) => {
            const notification = {
              userId: customer._id,
              userEmail: customer.email || null,
              userRole: 'customer',
              type: notificationData.type,
              title: notificationData.title,
              body: notificationData.body || notificationData.message,
              message: notificationData.message || notificationData.body,
              data: notificationData.data || {},
              priority: notificationData.priority || 'normal',
              category: notificationData.category || 'trip_updates',
              isRead: false,
              createdAt: new Date(),
              updatedAt: new Date(),
              expiresAt: notificationData.expiresAt || new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
              deliveryStatus: notificationData.deliveryStatus || {
                fcm: 'no_devices',
                database: 'success'
              },
              fcmResponse: notificationData.fcmResponse || null,
              channels: notificationData.channels || ['database']
            };
            
            const result = await db.collection('notifications').insertOne(notification);
            console.log(`✅ Database notification created: ${result.insertedId}`);
            return result;
          };
          
          // Save to database
          await createTripNotification(req.db, customer, {
            type: 'feedback_request',
            title: '⭐ How was your ride?',
            body: `Please rate your experience with ${driverName}`,
            message: `Hi ${customer.name},\n\nYour pickup has been completed. We'd love to hear about your experience!\n\nPlease take a moment to rate your ride with ${driverName}.`,
            data: {
              tripId: trip._id.toString(),  // ✅ FIXED: Use main trip document _id
              stopId: stop.stopId,           // Keep for reference
              tripNumber: trip.tripNumber || tripGroupId.substring(0, 8),
              driverName: driverName,
              driverId: trip.driverId.toString(),
              feedbackRequestId: feedbackRequestResult.insertedId.toString(),
              action: 'open_feedback',
            },
            priority: 'high',
            category: 'feedback',
            expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
            deliveryStatus: {
              fcm: fcmSuccessCount > 0 ? 'success' : 'no_devices',
              database: 'success'
            },
            channels: ['fcm', 'database']
          });
          
          console.log(`✅ Feedback request sent to ${fcmSuccessCount} device(s)`);
          console.log('='.repeat(60));
        } else {
          console.log(`⚠️ Customer not found: ${stop.customer.email}`);
        }
      } catch (feedbackError) {
        console.log(`⚠️ Feedback error: ${feedbackError.message}`);
      }
    }
    
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Marked as departed and feedback requested',
      data: {
        tripGroupId: tripGroupId,
        stopId: stopId,
        stopStatus: 'completed',
        departedAt: new Date(),
        nextStopIndex: stopIndex + 1,
        currentStopIndex: stopIndex + 1  // ✅ Return updated value
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

// ============================================================================
// @route   POST /api/driver/trips/:tripGroupId/location
// @desc    Update driver GPS location
// @access  Private (Driver only)
// ============================================================================
router.post('/trips/:tripGroupId/location', verifyToken, async (req, res) => {
  try {
    const { tripGroupId } = req.params;
    const { latitude, longitude, speed, heading } = req.body;
    
    if (!latitude || !longitude) {
      return res.status(400).json({
        success: false,
        message: 'Latitude and longitude are required'
      });
    }
    
    // ✅ FIXED: Parse tripGroupId safely
    let vehicleId, tripType;
    try {
      const parsed = parseTripGroupId(tripGroupId);
      vehicleId = parsed.vehicleId;
      tripType = parsed.tripType;
    } catch (parseError) {
      return res.status(400).json({
        success: false,
        message: parseError.message
      });
    }
    
    const driverId = req.user.driverId || req.user.id || req.user.uid;
    const today = new Date().toISOString().split('T')[0];
    
    // ✅ Get driver's MongoDB _id
    const driver = await req.db.collection('drivers').findOne({
      driverId: driverId
    });
    
    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    const driverMongoId = driver._id;
    
    const locationUpdate = {
      latitude: parseFloat(latitude),
      longitude: parseFloat(longitude),
      speed: speed ? parseFloat(speed) : null,
      heading: heading ? parseFloat(heading) : null,
      timestamp: new Date()
    };
    
    await req.db.collection('roster-assigned-trips').updateMany(
      {
        vehicleId: new ObjectId(vehicleId),
        tripType: tripType,
        scheduledDate: today,
        driverId: driverMongoId,
        status: { $in: ['started', 'in_progress'] }
      },
      {
        $set: {
          currentLocation: locationUpdate,
          updatedAt: new Date()
        },
        $push: {
          locationHistory: {
            $each: [locationUpdate],
            $slice: -100
          }
        }
      }
    );
    
    // Calculate ETA to next pending stop
    const nextStop = await req.db.collection('roster-assigned-trips').findOne({
      vehicleId: new ObjectId(vehicleId),
      tripType: tripType,
      scheduledDate: today,
      driverId: driverMongoId,
      status: { $in: ['started', 'in_progress'] }
    }, {
      sort: { pickupSequence: 1 }
    });
    
    let eta = null;
    if (nextStop && nextStop.pickupLocation?.coordinates) {
      const coords = nextStop.pickupLocation.coordinates;
      const destLat = coords.latitude || coords[1];
      const destLng = coords.longitude || coords[0];
      
      eta = await calculateETA(latitude, longitude, destLat, destLng);
    }
    
    res.json({
      success: true,
      message: 'Location updated',
      data: {
        currentLocation: locationUpdate,
        eta: eta
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

// ============================================================================
// @route   POST /api/driver/trips/:tripId/stop/arrive
// @desc    Mark arrival at stop + SEND NOTIFICATION TO CUSTOMER
// @access  Private (Driver only)
// ============================================================================
router.post('/trips/:tripId/stop/arrive', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log(`📍 DRIVER ARRIVED AT STOP: ${req.params.tripId}`);
    console.log('='.repeat(80));
    
    const { tripId } = req.params;
    const { latitude, longitude } = req.body;
    
    // ========================================================================
    // STEP 1: Update trip status to 'in_progress'
    // ========================================================================
    const updateResult = await req.db.collection('roster-assigned-trips').findOneAndUpdate(
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
          updatedAt: new Date()
        }
      },
      { returnDocument: 'after' }
    );
    
    if (!updateResult.value) {
      console.log('❌ Trip not found');
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }
    
    const trip = updateResult.value;
    console.log(`✅ Trip status updated: ${trip.customerName}`);
    
    // ========================================================================
    // STEP 2: Send Enhanced Arrival Notification to Customer
    // ========================================================================
    console.log(`\n📍 Sending arrival notification to customer...`);
    
    // ✅ Find customer in CUSTOMERS collection
    const customer = await req.db.collection('customers').findOne({
      email: trip.customerEmail
    });
    
    if (customer) {
      console.log(`✅ Customer found: ${customer.name || customer.email}`);
      
      // Get driver info
      const driver = await req.db.collection('drivers').findOne({
        _id: trip.driverId
      });
      
      const driverName = driver?.personalInfo?.name || driver?.name || 'Your driver';
      const driverPhone = driver?.personalInfo?.phone || driver?.phone || '';
      
      // Get all customer devices
      const devices = await req.db.collection('user_devices').find({
        $or: [
          { userEmail: trip.customerEmail },
          { userId: customer._id.toString() }
        ],
        isActive: true
      }).toArray();
      
      console.log(`📱 Found ${devices.length} device(s) for customer`);
      
      let fcmSuccessCount = 0;
      
      // ✅ Send FCM push notification to ALL devices
      for (const device of devices) {
        try {
          await notificationService.send({
            deviceToken: device.deviceToken,
            deviceType: device.deviceType || 'android',
            title: '📍 Driver Has Arrived!',
            body: `${driverName} is waiting at your pickup location`,
            data: {
              type: 'driver_arrived',
              tripId: tripId,
              driverName: driverName,
              driverPhone: driverPhone,
            },
            priority: 'urgent'
          });
          
          fcmSuccessCount++;
          console.log(`✅ FCM arrival notification sent to ${device.deviceType}`);
        } catch (fcmError) {
          console.log(`⚠️ FCM failed for ${device.deviceType}: ${fcmError.message}`);
        }
      }

      // ✅ Save to database (for in-app notifications)
      try {
        await createTripNotification(req.db, customer, {
  type: 'driver_arrived',
  title: '📍 Driver Has Arrived!',
  body: `${driverName} is waiting at your location`,
  message: `Your driver ${driverName} has arrived at your pickup location. Please proceed to the vehicle.`,
  data: {
    tripId: tripId,
    driverName: driverName,
    driverPhone: driverPhone,
  },
  priority: 'urgent',
  category: 'trip_updates',
  expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
  deliveryStatus: {
    fcm: fcmSuccessCount > 0 ? 'success' : 'no_devices',
    database: 'success'
  },
  channels: ['fcm', 'database']
});
        
        console.log(`✅ Database notification saved`);
      } catch (dbError) {
        console.log(`⚠️ Database save failed: ${dbError.message}`);
      }
      
      console.log(`📊 Arrival notification sent to ${fcmSuccessCount} device(s)`);
    } else {
      console.log(`⚠️ Customer not found: ${trip.customerEmail}`);
    }
    
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Marked as arrived',
      data: {
        tripId: tripId,
        status: 'in_progress',
        arrivedAt: trip.arrivedAt
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

// ============================================================================
// @route   POST /api/driver/trips/:tripId/attendance
// @desc    Update passenger attendance (boarded/not boarded)
// @access  Private (Driver only)
// ============================================================================
router.post('/trips/:tripId/attendance', verifyToken, async (req, res) => {
  try {
    console.log(`\n👥 UPDATING PASSENGER ATTENDANCE: ${req.params.tripId}`);
    
    const { tripId } = req.params;
    const { status } = req.body;
    
    if (!['boarded', 'not_boarded'].includes(status)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid status. Must be "boarded" or "not_boarded"'
      });
    }
    
    const updateResult = await req.db.collection('roster-assigned-trips').findOneAndUpdate(
      { _id: new ObjectId(tripId) },
      {
        $set: {
          passengerStatus: status,
          passengerStatusUpdatedAt: new Date(),
          updatedAt: new Date()
        }
      },
      { returnDocument: 'after' }
    );
    
    if (!updateResult.value) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }
    
    console.log(`✅ Passenger marked as: ${status}`);
    
    res.json({
      success: true,
      message: `Passenger marked as ${status}`,
      data: {
        tripId: tripId,
        passengerStatus: status
      }
    });
    
  } catch (error) {
    console.error('❌ Error updating attendance:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update attendance',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/driver/trips/:tripId/stop/depart
// @desc    Mark departure from stop + REQUEST FEEDBACK FROM CUSTOMER
// @access  Private (Driver only)
// ============================================================================
router.post('/trips/:tripId/stop/depart', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🚗 DEPARTING FROM STOP');
    console.log('='.repeat(80));
    
    const { tripId } = req.params;
    const { latitude, longitude } = req.body;
    
    console.log(`📋 Trip ID: ${tripId}`);
    console.log(`📍 Location: ${latitude || 'N/A'}, ${longitude || 'N/A'}`);
    
    // Validate tripId format
    if (!ObjectId.isValid(tripId)) {
      console.log('❌ Invalid trip ID format');
      return res.status(400).json({
        success: false,
        message: 'Invalid trip ID format'
      });
    }
    
    // ========================================================================
    // STEP 1: Get trip details first
    // ========================================================================
    const existingTrip = await req.db.collection('roster-assigned-trips').findOne({
      _id: new ObjectId(tripId)
    });
    
    if (!existingTrip) {
      console.log('❌ Trip not found in roster-assigned-trips');
      return res.status(404).json({
        success: false,
        message: 'Trip not found. It may have been completed or deleted.',
      });
    }
    
    console.log(`✅ Trip found: ${existingTrip.customerName || 'Unknown'}`);
    console.log(`   Status: ${existingTrip.status}`);
    
    // Check if trip is in correct status
    if (existingTrip.status === 'completed') {
      console.log('⚠️  Trip already completed');
      return res.status(400).json({
        success: false,
        message: 'This trip has already been completed'
      });
    }
    
    if (existingTrip.status === 'pending' || existingTrip.status === 'assigned') {
      console.log('⚠️  Trip not started yet');
      return res.status(400).json({
        success: false,
        message: 'Please start the trip first before marking departure'
      });
    }
    
    // ========================================================================
    // STEP 2: Update the trip to mark departure
    // ========================================================================
    console.log('📝 Updating trip in database...');
    const updateResult = await req.db.collection('roster-assigned-trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: {
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
    
    if (!updateResult.acknowledged || updateResult.matchedCount === 0) {
      console.log('❌ Failed to update trip');
      return res.status(500).json({
        success: false,
        message: 'Failed to update trip. Please try again.',
      });
    }
    
    console.log('✅ Departure marked successfully');
    
    // ========================================================================
    // STEP 3: REQUEST FEEDBACK FROM CUSTOMER
    // ========================================================================
    console.log('\n⭐ REQUESTING CUSTOMER FEEDBACK AFTER DEPARTURE');
    console.log('='.repeat(60));
    
    try {
      // Get customer from customers collection
      const customer = await req.db.collection('customers').findOne({
        email: existingTrip.customerEmail
      });
      
      if (!customer) {
        console.log(`⚠️ Customer not found: ${existingTrip.customerEmail}`);
      } else {
        console.log(`✅ Customer found: ${customer.name || customer.email}`);
        
        // Get driver details
        const driver = await req.db.collection('drivers').findOne({
          _id: existingTrip.driverId
        });
        
        const driverName = driver?.personalInfo?.name || driver?.name || 'Your driver';
        const driverEmail = driver?.personalInfo?.email || driver?.email || '';
        
        // Get all customer devices
        const devices = await req.db.collection('user_devices').find({
          $or: [
            { userEmail: existingTrip.customerEmail },
            { userId: customer._id.toString() }
          ],
          isActive: true
        }).toArray();
        
        console.log(`📱 Found ${devices.length} device(s) for customer`);
        
        let fcmSuccessCount = 0;
        
        // Send FCM to all devices
        for (const device of devices) {
          try {
            await notificationService.send({
              deviceToken: device.deviceToken,
              deviceType: device.deviceType || 'android',
              title: '⭐ How was your ride?',
              body: `Please rate your experience with ${driverName}`,
              data: {
                type: 'feedback_request',
                tripId: tripId,
                driverName: driverName,
                driverEmail: driverEmail,
                driverId: existingTrip.driverId.toString(),
                action: 'open_feedback',
              },
              priority: 'high'
            });
            
            fcmSuccessCount++;
            console.log(`✅ Feedback request FCM sent to ${device.deviceType}`);
          } catch (fcmError) {
            console.log(`⚠️ FCM failed for ${device.deviceType}: ${fcmError.message}`);
          }
        }
        
        // Save feedback request to database
        const feedbackRequestDoc = {
          tripId: new ObjectId(tripId),
          customerId: customer._id,
          customerEmail: customer.email,
          driverId: existingTrip.driverId,
          driverName: driverName,
          driverEmail: driverEmail,
          requestedAt: new Date(),
          status: 'pending', // pending, completed
          feedbackGiven: false,
          expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000), // 24 hours
        };
        
        const feedbackRequestResult = await req.db.collection('feedback_requests').insertOne(feedbackRequestDoc);
        
        console.log(`✅ Feedback request saved: ${feedbackRequestResult.insertedId}`);
        
        await createTripNotification(req.db, customer, {
  type: 'feedback_request',
  title: '⭐ How was your ride?',
  body: `Please rate your experience with ${driverName}`,
  message: `Hi ${customer.name},\n\nYour pickup has been completed. We'd love to hear about your experience!\n\nPlease take a moment to rate your ride with ${driverName}.`,
  data: {
    tripId: tripId,
    driverName: driverName,
    driverEmail: driverEmail,
    driverId: existingTrip.driverId.toString(),
    feedbackRequestId: feedbackRequestResult.insertedId.toString(),
    action: 'open_feedback',
  },
  priority: 'high',
  category: 'feedback',
  expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
  deliveryStatus: {
    fcm: fcmSuccessCount > 0 ? 'success' : 'no_devices',
    database: 'success'
  },
  channels: ['fcm', 'database']
});
        
        console.log(`✅ Feedback notification saved to database`);
        console.log(`📊 Feedback request sent to ${fcmSuccessCount} device(s)`);
      }
    } catch (feedbackError) {
      console.log(`⚠️ Failed to send feedback request: ${feedbackError.message}`);
      // Don't fail the departure if feedback fails
    }
    
    console.log('='.repeat(60));
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Marked as departed and feedback requested',
      data: {
        tripId: tripId,
        departedAt: new Date(),
        modifiedCount: updateResult.modifiedCount
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

// ============================================================================
// @route   POST /api/customer/feedback/submit
// @desc    Submit customer feedback and store in driver's profile
// @access  Private (Customer only)
// ============================================================================
// ============================================================================
// @route   POST /api/driver/customer/feedback/submit
// @desc    Submit customer feedback and store in driver's profile
// @access  Private (Customer only)
// ============================================================================
// ============================================================================
// @route   POST /api/driver/customer/feedback/submit
// @desc    Submit customer feedback and store in driver's profile
// @access  Private (Customer only)
// ============================================================================
// ============================================================================
// @route   POST /api/driver/customer/feedback/submit
// @desc    Submit customer feedback for driver (CLEAN - uses driver_feedback collection)
// @access  Private (Customer only)
// ============================================================================
router.post('/customer/feedback/submit', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '⭐'.repeat(40));
    console.log('CUSTOMER SUBMITTING DRIVER FEEDBACK');
    console.log('⭐'.repeat(40));
    
    const { tripId, driverId, rating, feedback, rideAgain } = req.body;
    
    console.log(`📋 Received tripId: ${tripId}`);
    console.log(`🚗 Driver ID: ${driverId}`);
    console.log(`⭐ Rating: ${rating}/5`);
    console.log(`📝 Feedback: ${feedback || 'None'}`);
    console.log(`🔄 Ride Again: ${rideAgain || 'not_specified'}`);
    
    // ========================================================================
    // VALIDATION
    // ========================================================================
    if (!tripId || !driverId || !rating) {
      return res.status(400).json({
        success: false,
        message: 'Trip ID, Driver ID, and rating are required'
      });
    }
    
    if (rating < 1 || rating > 5) {
      return res.status(400).json({
        success: false,
        message: 'Rating must be between 1 and 5'
      });
    }
    
    if (!ObjectId.isValid(tripId)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid trip ID format'
      });
    }
    
    if (!ObjectId.isValid(driverId)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid driver ID format'
      });
    }
    
    const customerId = req.user.userId || req.user.id || req.user.uid || req.user.customerId;
    console.log(`👤 Customer ID from JWT: ${customerId}`);
    
    // ========================================================================
    // STEP 1: Find the trip
    // ========================================================================
    console.log('\n🔍 Looking for trip...');
    
    const trip = await req.db.collection('roster-assigned-trips').findOne({
      _id: new ObjectId(tripId)
    });
    
    if (!trip) {
      console.log('❌ Trip not found');
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }
    
    console.log(`✅ Trip found: ${trip.tripNumber || tripId}`);
    
    // ========================================================================
    // STEP 2: ✅ GET REAL CUSTOMER DATA FROM DATABASE
    // ========================================================================
    console.log('\n👤 Getting customer details...');
    
    let customer = null;
    
    // Try to find customer by ID first (from JWT)
    if (customerId && ObjectId.isValid(customerId)) {
      customer = await req.db.collection('customers').findOne({
        _id: new ObjectId(customerId)
      });
    }
    
    // If not found, try by email from trip
    if (!customer && trip.customerEmail) {
      customer = await req.db.collection('customers').findOne({
        email: trip.customerEmail
      });
    }
    
    // If still not found, try from stops array (pre-grouped trips)
    if (!customer && trip.stops && Array.isArray(trip.stops)) {
      const firstStop = trip.stops.find(s => s.type === 'pickup' && s.customer?.email);
      if (firstStop?.customer?.email) {
        customer = await req.db.collection('customers').findOne({
          email: firstStop.customer.email
        });
      }
    }
    
    if (!customer) {
      console.log('❌ Customer not found in database');
      return res.status(404).json({
        success: false,
        message: 'Customer not found. Please contact support.'
      });
    }
    
    console.log(`✅ Customer found: ${customer.name || customer.email}`);
    console.log(`   Email: ${customer.email}`);
    console.log(`   Phone: ${customer.phone || 'N/A'}`);
    
    // ========================================================================
    // STEP 3: Get driver details
    // ========================================================================
    const driver = await req.db.collection('drivers').findOne({
      _id: new ObjectId(driverId)
    });
    
    if (!driver) {
      console.log('❌ Driver not found');
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    console.log(`✅ Driver found: ${driver.personalInfo?.name || driver.name || 'Unknown'}`);
    
    // ========================================================================
    // STEP 4: ✅ SAVE TO NEW driver_feedback COLLECTION
    // ========================================================================
    console.log('\n💾 SAVING TO driver_feedback COLLECTION');
    console.log('═'.repeat(60));
    
    const feedbackDoc = {
      // Trip info
      tripId: new ObjectId(tripId),
      tripNumber: trip.tripNumber || null,
      tripGroupId: trip.tripGroupId || null,
      vehicleId: trip.vehicleId,
      vehicleNumber: trip.vehicleNumber || null,
      
      // ✅ REAL CUSTOMER DATA (as strings, not objects)
      customerId: customer._id,
      customerName: customer.name || 'Unknown',  // ✅ String, not object
      customerEmail: customer.email,
      customerPhone: customer.phone || null,
      
      // Driver info
      driverId: new ObjectId(driverId),
      driverName: driver.personalInfo?.name || driver.name || 'Unknown',
      driverEmail: driver.personalInfo?.email || driver.email || '',
      driverPhone: driver.personalInfo?.phone || driver.phone || '',
      
      // Feedback data
      rating: parseInt(rating),
      feedback: feedback || '',
      rideAgain: rideAgain || 'not_specified',
      
      // Timestamps
      submittedAt: new Date(),
      createdAt: new Date(),
      updatedAt: new Date(),
      
      // Metadata
      feedbackType: 'driver_trip_feedback',  // ✅ Distinguish from complaints
      status: 'submitted'
    };
    
    const insertResult = await req.db.collection('driver_feedback').insertOne(feedbackDoc);
    console.log(`✅ Saved to driver_feedback collection`);
    console.log(`   Feedback ID: ${insertResult.insertedId}`);
    
    // ========================================================================
    // STEP 5: Update feedback request status
    // ========================================================================
    await req.db.collection('feedback_requests').updateOne(
      { tripId: new ObjectId(tripId) },
      {
        $set: {
          status: 'completed',
          feedbackGiven: true,
          feedbackId: insertResult.insertedId,
          completedAt: new Date()
        }
      }
    );
    console.log(`✅ Updated feedback_requests status`);
    
    // ========================================================================
    // STEP 6: Update trip document
    // ========================================================================
    await req.db.collection('roster-assigned-trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: {
          customerFeedback: {
            feedbackId: insertResult.insertedId,
            rating: parseInt(rating),
            feedback: feedback || '',
            rideAgain: rideAgain || 'not_specified',
            submittedAt: new Date()
          },
          feedbackSubmitted: true,
          feedbackSubmittedAt: new Date()
        }
      }
    );
    console.log(`✅ Updated trip document`);
    
    // ========================================================================
    // STEP 7: ⭐ ADD TO DRIVER'S PROFILE
    // ========================================================================
    console.log('\n📊 UPDATING DRIVER PROFILE');
    console.log('═'.repeat(60));
    
    const driverFeedbackEntry = {
      feedbackId: insertResult.insertedId,
      tripId: new ObjectId(tripId),
      tripNumber: trip.tripNumber || null,
      customerId: customer._id,
      customerName: customer.name || 'Unknown',  // ✅ String
      customerEmail: customer.email,
      rating: parseInt(rating),
      feedback: feedback || '',
      rideAgain: rideAgain || 'not_specified',
      submittedAt: new Date(),
    };
    
    // Initialize feedbackStats if needed
    await req.db.collection('drivers').updateOne(
      { 
        _id: new ObjectId(driverId),
        feedbackStats: { $exists: false }
      },
      {
        $set: {
          feedbackStats: {
            totalFeedback: 0,
            rating5Stars: 0,
            rating4Stars: 0,
            rating3Stars: 0,
            rating2Stars: 0,
            rating1Stars: 0,
            totalRatingPoints: 0,
            averageRating: 0
          }
        }
      }
    );
    
    // Add feedback to driver
    const driverUpdateResult = await req.db.collection('drivers').updateOne(
      { _id: new ObjectId(driverId) },
      {
        $push: {
          customerFeedback: driverFeedbackEntry
        },
        $inc: {
          'feedbackStats.totalFeedback': 1,
          [`feedbackStats.rating${rating}Stars`]: 1,
          'feedbackStats.totalRatingPoints': parseInt(rating)
        },
        $set: {
          updatedAt: new Date()
        }
      }
    );
    
    if (driverUpdateResult.modifiedCount > 0) {
      console.log(`✅ Feedback added to driver profile`);
      
      // Calculate average
      const updatedDriver = await req.db.collection('drivers').findOne({
        _id: new ObjectId(driverId)
      });
      
      if (updatedDriver?.feedbackStats) {
        const totalFeedback = updatedDriver.feedbackStats.totalFeedback || 0;
        const totalPoints = updatedDriver.feedbackStats.totalRatingPoints || 0;
        const averageRating = totalFeedback > 0 ? (totalPoints / totalFeedback).toFixed(2) : 0;
        
        await req.db.collection('drivers').updateOne(
          { _id: new ObjectId(driverId) },
          {
            $set: {
              'feedbackStats.averageRating': parseFloat(averageRating)
            }
          }
        );
        
        console.log(`\n📊 DRIVER STATS:`);
        console.log(`   Total Feedback: ${totalFeedback}`);
        console.log(`   Average Rating: ${averageRating}/5.0`);
        console.log(`   5⭐: ${updatedDriver.feedbackStats.rating5Stars || 0}`);
        console.log(`   4⭐: ${updatedDriver.feedbackStats.rating4Stars || 0}`);
        console.log(`   3⭐: ${updatedDriver.feedbackStats.rating3Stars || 0}`);
        console.log(`   2⭐: ${updatedDriver.feedbackStats.rating2Stars || 0}`);
        console.log(`   1⭐: ${updatedDriver.feedbackStats.rating1Stars || 0}`);
      }
    }
    
    console.log('\n✅ FEEDBACK SUBMITTED SUCCESSFULLY');
    console.log('═'.repeat(60));
    console.log('⭐'.repeat(40) + '\n');
    
    res.status(201).json({
      success: true,
      message: 'Thank you for your feedback!',
      data: {
        feedbackId: insertResult.insertedId.toString(),
        rating: rating,
        customerName: customer.name,  // ✅ Return real name
        driverName: driver.personalInfo?.name || driver.name,
        driverUpdated: driverUpdateResult.modifiedCount > 0
      }
    });
    
  } catch (error) {
    console.error('❌ Error submitting feedback:', error);
    console.error('Stack trace:', error.stack);
    res.status(500).json({
      success: false,
      message: 'Failed to submit feedback',
      error: error.message
    });
  }
});


// ============================================================================
// @route   POST /api/driver/trips/:tripGroupId/end
// @desc    End trip with final odometer photo
// @access  Private (Driver only)
// ============================================================================
// ============================================================================
// @route   POST /api/driver/trips/:tripGroupId/end
// @desc    End trip with final odometer photo
// @access  Private (Driver only)
// ============================================================================
router.post('/trips/:tripGroupId/end', verifyToken, upload.single('photo'), async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🏁 ENDING TRIP');
    console.log('='.repeat(80));
    
    const { tripGroupId } = req.params;
    const { reading } = req.body;
    const photo = req.file;
    
    console.log(`📋 Trip Group ID: ${tripGroupId}`);
    console.log(`📏 End Odometer Reading: ${reading}`);
    console.log(`📸 Photo: ${photo ? 'Uploaded' : 'Missing'}`);
    
    if (!reading || !photo) {
      return res.status(400).json({
        success: false,
        message: 'End odometer reading and photo are required'
      });
    }
    
    // ✅ FIXED: Parse tripGroupId safely
    let vehicleId, tripType;
    try {
      const parsed = parseTripGroupId(tripGroupId);
      vehicleId = parsed.vehicleId;
      tripType = parsed.tripType;
      console.log(`✅ Parsed - Vehicle: ${vehicleId}, Type: ${tripType}`);
    } catch (parseError) {
      return res.status(400).json({
        success: false,
        message: parseError.message
      });
    }
    
    const driverId = req.user.driverId || req.user.id || req.user.uid;
    const today = new Date().toISOString().split('T')[0];
    
    // ✅ Get driver's MongoDB _id
    const driver = await req.db.collection('drivers').findOne({
      driverId: driverId
    });
    
    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    const driverMongoId = driver._id;
    console.log(`✅ Driver: ${driver.personalInfo?.name || driver.name || 'Unknown'}`);
    
    // ========================================================================
    // STEP 1: Upload photo to GridFS
    // ========================================================================
    console.log('📤 Uploading end odometer photo to GridFS...');
    
    const bucket = new GridFSBucket(req.db, {
      bucketName: 'odometer_photos'
    });
    
    const uploadStream = bucket.openUploadStream(`end-${tripGroupId}-${Date.now()}.jpg`, {
      metadata: {
        tripGroupId: tripGroupId,
        vehicleId: vehicleId,
        tripType: tripType,
        type: 'end_odometer',
        reading: parseInt(reading),
        uploadedBy: driverId,
        uploadedAt: new Date()
      }
    });
    
    uploadStream.end(photo.buffer);
    
    const photoId = await new Promise((resolve, reject) => {
      uploadStream.on('finish', () => resolve(uploadStream.id));
      uploadStream.on('error', reject);
    });
    
    console.log(`✅ Photo uploaded to GridFS: ${photoId}`);
    
    // ========================================================================
    // STEP 2: Get trip data for calculations
    // ========================================================================
    const trips = await req.db.collection('roster-assigned-trips').find({
      vehicleId: new ObjectId(vehicleId),
      tripType: tripType,
      scheduledDate: today,
      driverId: driverMongoId
    }).toArray();
    
    if (trips.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }
    
    const startOdometer = trips[0].startOdometer?.reading || 0;
    const actualDistance = parseInt(reading) - startOdometer;
    
    console.log(`📏 Start odometer: ${startOdometer} km`);
    console.log(`📏 End odometer: ${reading} km`);
    console.log(`📏 Distance traveled: ${actualDistance} km`);
    
    // ========================================================================
    // STEP 3: Update all trips in group to completed
    // ========================================================================
    const updateResult = await req.db.collection('roster-assigned-trips').updateMany(
      {
        vehicleId: new ObjectId(vehicleId),
        tripType: tripType,
        scheduledDate: today,
        driverId: driverMongoId
      },
      {
        $set: {
          status: 'completed',
          actualEndTime: new Date(),
          endOdometer: {
            reading: parseInt(reading),
            photoId: photoId,
            timestamp: new Date()
          },
          actualDistance: actualDistance,
          updatedAt: new Date()
        }
      }
    );
    
    console.log(`✅ Updated ${updateResult.modifiedCount} trip(s) to 'completed'`);

    // ========================================================================
    // STEP 3B: Auto-calculate billing for each completed trip
    // ========================================================================
    console.log('\n💰 AUTO-CALCULATING BILLING...');
    try {
      const { calculateTripAmount, TripBilling } = require('./rate_card_billing');
      const { getActiveRateCard } = require('./rate_cards');

      // Get completed trip documents (now have actualDistance set)
      const completedTrips = await req.db.collection('roster-assigned-trips').find({
        vehicleId: new ObjectId(vehicleId),
        tripType:  tripType,
        scheduledDate: today,
        driverId:  driverMongoId
      }).toArray();

      if (completedTrips.length === 0) {
        console.log('   ⚠️ No completed trips found for billing');
      } else {
        // ── Extract client domain from the trip's own passenger stop emails ──
        // All stops in this trip belong to same company (grouped by domain).
        // e.g. stops[0].customer.email = "pooja.joshi@tcs.com" → "tcs.com"
        const firstTrip = completedTrips[0];
        const firstPickupStop = (firstTrip.stops || []).find(
          s => s.type === 'pickup' && s.customer?.email
        );
        const clientDomain = firstPickupStop?.customer?.email?.split('@')[1]?.toLowerCase() || '';

        console.log(`   📧 Client domain from trip stops: "${clientDomain}"`);

        if (!clientDomain) {
          console.log('   ⚠️ Could not find client domain from trip stops — billing skipped');
        } else {
          const rateCard = await getActiveRateCard(clientDomain).catch(() => null);

          if (!rateCard) {
            console.log(`   ⚠️ No active rate card for domain "${clientDomain}" — billing skipped`);
          } else {
            console.log(`   ✅ Rate card found: ${rateCard.rateCardId} (${rateCard.organizationName})`);
            let billedCount = 0;

            for (const trip of completedTrips) {
              try {
                const tripDate = trip.actualEndTime || trip.actualStartTime || new Date();
                const period   = `${tripDate.getFullYear()}-${String(tripDate.getMonth() + 1).padStart(2, '0')}`;

                const tripForCalc = {
                  vehicleType:    trip.vehicleType   || 'SEDAN',
                  actualKm:       actualDistance,     // ✅ endOdometer - startOdometer
                  distance:       actualDistance,
                  tripDate:       tripDate,
                  waitingMinutes: trip.waitingMinutes || 0,
                  tollAmount:     trip.tollAmount     || 0,
                  escortRequired: trip.escortRequired || false,
                  isWomenOnly:    trip.isWomenOnly    || false,
                };

                const calc = calculateTripAmount(tripForCalc, rateCard);

                if (calc.error) {
                  console.log(`   ⚠️ Calc error for ${trip.tripNumber}: ${calc.error}`);
                  continue;
                }

                await TripBilling.findOneAndUpdate(
                  {
                    tripId:         trip._id.toString(),
                    tripCollection: 'roster-assigned-trips',
                  },
                  {
                    tripId:            trip._id.toString(),
                    tripCollection:    'roster-assigned-trips',
                    domain:            clientDomain,
                    rateCardId:        rateCard.rateCardId,
                    rateCardMongoId:   rateCard._id,
                    tripDate:          tripDate,
                    vehicleType:       calc.vehicleType,
                    vehicleNumber:     trip.vehicleNumber   || '',
                    driverName:        driver.personalInfo?.name || driver.name || '',
                    actualKm:          calc.actualKm,
                    billedKm:          calc.billedKm,
                    waitingMinutes:    trip.waitingMinutes  || 0,
                    isNightTrip:       calc.isNightTrip,
                    isWeekend:         calc.isWeekend,
                    isFestival:        calc.isFestival,
                    isEscortTrip:      calc.isEscortTrip,
                    tollAmount:        trip.tollAmount      || 0,
                    billingModel:      calc.billingModel,
                    baseAmount:        calc.baseAmount,
                    nightSurcharge:    calc.nightSurcharge,
                    weekendSurcharge:  calc.weekendSurcharge,
                    festivalSurcharge: calc.festivalSurcharge,
                    waitingSurcharge:  calc.waitingSurcharge,
                    tollSurcharge:     calc.tollSurcharge,
                    escortSurcharge:   calc.escortSurcharge,
                    totalSurcharges:   calc.totalSurcharges,
                    subtotalBeforeTax: calc.subtotalBeforeTax,
                    status:            'CALCULATED',
                    billingPeriod:     period,
                    calculatedAt:      new Date(),
                  },
                  { upsert: true, new: true }
                );

                billedCount++;
                console.log(`   ✅ Billed ${trip.tripNumber}: ₹${calc.subtotalBeforeTax} | ${calc.billedKm} km | ${clientDomain}`);

              } catch (tripErr) {
                console.log(`   ⚠️ Billing failed for ${trip._id}: ${tripErr.message}`);
              }
            }

            console.log(`💰 Billing complete: ${billedCount}/${completedTrips.length} trips calculated`);
          }
        }
      }
    } catch (billingErr) {
      // Never fail trip completion because billing errored
      console.error(`   ⚠️ Billing hook error (trip still completed): ${billingErr.message}`);
    }
    
    // ========================================================================
    // STEP 4: Send completion notifications
    // ========================================================================
    console.log(`\n📲 Sending completion notifications...`);
    
    for (const trip of trips) {
      // ✅ FIXED: Find customer in CUSTOMERS collection
      const customer = await req.db.collection('customers').findOne({
        email: trip.customerEmail
      });
      
      if (customer) {
        // Get all customer devices
        const devices = await req.db.collection('user_devices').find({
          $or: [
            { userEmail: trip.customerEmail },
            { userId: customer._id.toString() }
          ],
          isActive: true
        }).toArray();
        
        for (const device of devices) {
          try {
            await notificationService.send({
              deviceToken: device.deviceToken,
              deviceType: device.deviceType || 'android',
              title: '✅ Trip completed!',
              body: `Thank you for riding with us. Distance: ${actualDistance} km`,
              data: {
                type: 'trip_completed',
                tripId: trip._id.toString(),
                actualDistance: actualDistance
              }
            });
            
            console.log(`   ✅ Completion notification sent to ${trip.customerName}`);
          } catch (notifError) {
            console.log(`   ⚠️ Failed to notify ${trip.customerName}`);
          }
        }
      }
    }
    
    console.log('='.repeat(80));
    console.log('✅ TRIP COMPLETED SUCCESSFULLY');
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Trip completed successfully',
      data: {
        tripGroupId: tripGroupId,
        vehicleId: vehicleId,
        tripType: tripType,
        endOdometer: {
          reading: parseInt(reading),
          photoId: photoId.toString()
        },
        startOdometer: startOdometer,
        actualDistance: actualDistance,
        status: 'completed',
        completedTrips: updateResult.modifiedCount
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

// ============================================================================
// @route   POST /api/driver/trips/:tripGroupId/gps-disabled
// @desc    Report GPS disabled during active trip
// @access  Private (Driver only)
// ============================================================================
router.post('/trips/:tripGroupId/gps-disabled', verifyToken, async (req, res) => {
  try {
    const { tripGroupId } = req.params;
    const { timestamp } = req.body;
    
    console.log('\n' + '⚠️'.repeat(40));
    console.log('GPS DISABLED ALERT');
    console.log('⚠️'.repeat(40));
    console.log(`Trip Group: ${tripGroupId}`);
    console.log(`Timestamp: ${timestamp}`);
    
    // Parse tripGroupId
    const { vehicleId, tripType } = parseTripGroupId(tripGroupId);
    
    // Get driver info
    const driverId = req.user.driverId || req.user.id || req.user.uid;
    const driver = await req.db.collection('drivers').findOne({ driverId });
    
    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    // Get vehicle info
    const vehicle = await req.db.collection('vehicles').findOne({
      _id: new ObjectId(vehicleId)
    });
    
    const vehicleNumber = vehicle?.registrationNumber || vehicle?.vehicleNumber || 'Unknown';
    const driverName = driver.personalInfo?.name || driver.name || 'Unknown Driver';
    
    console.log(`Driver: ${driverName}`);
    console.log(`Vehicle: ${vehicleNumber}`);
    
    // Update trip document with GPS status
    await req.db.collection('roster-assigned-trips').updateMany(
      {
        tripGroupId: tripGroupId,
        status: { $in: ['started', 'in_progress'] }
      },
      {
        $set: {
          gpsStatus: 'disabled',
          gpsDisabledAt: new Date(timestamp),
          lastGPSAlert: new Date()
        }
      }
    );
    
    // Get all admins to notify
    const admins = await req.db.collection('admin_users').find({
      role: { $in: ['admin', 'super_admin'] },
      isActive: true
    }).toArray();
    
    console.log(`📧 Notifying ${admins.length} admin(s)...`);
    
    // Create notification for each admin
    for (const admin of admins) {
      await createTripNotification(req.db, admin, {
        type: 'gps_disabled_alert',
        title: '⚠️ GPS Disabled Alert',
        message: `Driver ${driverName} (${vehicleNumber}) has disabled GPS during an active trip.`,
        body: `GPS tracking has been disabled for vehicle ${vehicleNumber}. Driver: ${driverName}. Immediate action required.`,
        priority: 'high',
        category: 'system_alerts',
        data: {
          tripGroupId: tripGroupId,
          vehicleId: vehicleId,
          vehicleNumber: vehicleNumber,
          driverId: driver._id.toString(),
          driverName: driverName,
          tripType: tripType,
          timestamp: timestamp,
          alertType: 'gps_disabled'
        },
        channels: ['database', 'fcm']
      });
    }
    
    console.log('✅ GPS disabled alert sent to all admins');
    console.log('⚠️'.repeat(40) + '\n');
    
    res.json({
      success: true,
      message: 'GPS disabled alert sent to admins',
      data: {
        tripGroupId: tripGroupId,
        vehicleNumber: vehicleNumber,
        driverName: driverName,
        timestamp: timestamp,
        adminsNotified: admins.length
      }
    });
    
  } catch (error) {
    console.error('❌ Error reporting GPS disabled:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to report GPS status',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/driver/odometer-photo/:photoId
// @desc    Get odometer photo from GridFS
// @access  Private (Driver only)
// ============================================================================
router.get('/odometer-photo/:photoId', verifyToken, async (req, res) => {
  try {
    const { photoId } = req.params;
    
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

module.exports = router;