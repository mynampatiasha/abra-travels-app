// routes/individual_trips_router.js
// ============================================================================
// INDIVIDUAL TRIPS ROUTER - Admin-Created Trips + Client-Created Trips
// ============================================================================
// Queries ALL collections:
//   1. roster_assigned_trips  — original (individual/manual tripType)
//   2. trips                  — admin manual trips (from trips collection)
//   3. client_created_trips   — trips created by clients, assigned by admin
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const multer = require('multer');
const { GridFSBucket } = require('mongodb');

// ============================================================================
// MULTER CONFIGURATION
// ============================================================================
const storage = multer.memoryStorage();
const upload = multer({
  storage: storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed'));
    }
  }
});

// ============================================================================
// HELPER: Build driverId filter (handles both string and ObjectId in DB)
// ============================================================================
function buildDriverFilter(driverId) {
  const filter = { $or: [{ driverId: driverId }] };
  try { filter.$or.push({ driverId: new ObjectId(driverId) }); } catch (_) {}
  return filter;
}

// ============================================================================
// HELPER: Robust driver-ownership filter for action endpoints (respond/start/
// arrive/depart/end) and the driver's trip lists.
//
// The JWT `userId` is the driver's `drivers._id`, but different creation flows
// store the assigned driver under different ids / field names:
//   • admin "Start New Trip"      → trips.driverId = driver._id (may be users._id
//                                    or a driver code), trips.driverFirebaseUid
//   • route optimiser             → roster-assigned-trips.driverId = ObjectId
//   • roster assignment           → roster_assigned_trips.driverId = string
// Matching only on `req.user.userId` produces false 404s ("Trip not found or not
// assigned to you") and empty lists. This resolves every id that can represent
// the caller and matches the trip against all of them, across every field name
// in use.
// ============================================================================
async function buildDriverTripFilter(db, reqUser) {
  const ids = new Set();
  const add = (v) => {
    if (v === undefined || v === null) return;
    const s = String(v).trim();
    if (s && s !== 'null' && s !== 'undefined') ids.add(s);
  };

  add(reqUser.userId);
  add(reqUser.driverId);

  try {
    let driverDoc = null;
    if (ObjectId.isValid(reqUser.userId)) {
      driverDoc = await db.collection('drivers').findOne({ _id: new ObjectId(reqUser.userId) });
    }
    if (!driverDoc && reqUser.email) {
      driverDoc = await db.collection('drivers').findOne({ email: String(reqUser.email).toLowerCase() });
    }
    if (driverDoc) {
      add(driverDoc._id);
      add(driverDoc.userId);
      add(driverDoc.firebaseUid);
      add(driverDoc.driverId);
      add(driverDoc.driverCode);
    }
  } catch (e) {
    console.warn('⚠️  buildDriverTripFilter: driver lookup failed:', e.message);
  }

  const idList = [...ids];
  const idFields = [
    'driverId', 'assignedDriverId', 'driverFirebaseUid',
    'driver._id', 'assignedDriver._id', 'assignedDriver.driverId',
  ];
  const or = [];
  for (const f of idFields) {
    for (const v of idList) {
      or.push({ [f]: v });
      if (ObjectId.isValid(v)) {
        try { or.push({ [f]: new ObjectId(v) }); } catch (_) {}
      }
    }
  }
  if (reqUser.email) {
    const em = String(reqUser.email).toLowerCase();
    or.push({ driverEmail: em }, { driverEmail: reqUser.email },
            { 'driver.email': em }, { 'assignedDriver.email': em });
  }

  // If we somehow resolved nothing, never match (safer than matching everything).
  return or.length ? { $or: or } : { _id: null };
}

// Every collection an individual/assigned trip can live in. NOTE the hyphenated
// `roster-assigned-trips` (route optimiser) vs underscored `roster_assigned_trips`
// (roster assignment) — both are real, separate collections.
const DRIVER_TRIP_COLLECTIONS = [
  'roster_assigned_trips',
  'roster-assigned-trips',
  'trips',
  'client_created_trips',
];

// ============================================================================
// HELPER: Normalise a client_created_trips document to match roster/trips shape
// Maps clientName/clientPhone → customerName/customerPhone for Flutter UI
// ============================================================================
function normaliseClientTrip(trip) {
  return {
    ...trip,
    customerName: trip.clientName || trip.customerName || 'Unknown Client',
    customerPhone: trip.clientPhone || trip.customerPhone || '',
    customerEmail: trip.clientEmail || trip.customerEmail || '',
    startOdometerReading: trip.startOdometer?.reading || trip.startOdometerReading || null,
    endOdometerReading: trip.endOdometer?.reading || trip.endOdometerReading || null,
    startOdometerPhotoId: trip.startOdometer?.photoId || trip.startOdometerPhotoId || null,
    endOdometerPhotoId: trip.endOdometer?.photoId || trip.endOdometerPhotoId || null,
    startTime: trip.actualStartTime || trip.startTime || null,
    endTime: trip.actualEndTime || trip.endTime || null,
    completedAt: trip.statusHistory?.completed || trip.completedAt || null,
    scheduledTime: trip.scheduledPickupTime || trip.scheduledTime || null,
    _source: 'client_created_trips',
  };
}

// ============================================================================
// HELPER: Normalise a trips collection document (admin manual trip)
// ============================================================================
function normaliseManualTrip(trip) {
  return {
    ...trip,
    customerName: trip.customerName || trip.customer?.name || 'Unknown Customer',
    customerPhone: trip.customerPhone || trip.customer?.phone || '',
    customerEmail: trip.customerEmail || trip.customer?.email || '',
    startOdometerReading: trip.startOdometer?.reading || trip.startOdometerReading || null,
    endOdometerReading: trip.endOdometer?.reading || trip.endOdometerReading || null,
    startOdometerPhotoId: trip.startOdometer?.photoId || trip.startOdometerPhotoId || null,
    endOdometerPhotoId: trip.endOdometer?.photoId || trip.endOdometerPhotoId || null,
    startTime: trip.actualStartTime || trip.startTime || null,
    endTime: trip.actualEndTime || trip.endTime || null,
    completedAt: trip.statusHistory?.completed || trip.completedAt || null,
    scheduledTime: trip.scheduledPickupTime || trip.scheduledTime || null,
    _source: 'trips',
  };
}

// ============================================================================
// @route   GET /api/driver-trips/individual/pending
// @desc    Get pending individual trips for driver (need accept/decline)
//          ✅ UPDATED: Now includes trips + client_created_trips
// @access  Private (Driver)
// ============================================================================
router.get('/individual/pending', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '📋'.repeat(40));
    console.log('FETCHING PENDING INDIVIDUAL TRIPS');
    console.log('📋'.repeat(40));

    if (!req.db) {
      console.error('❌ Database not available on request object');
      console.error('   req.db:', req.db);
      console.error('   mongoose.connection.readyState:', require('mongoose').connection.readyState);
      return res.status(503).json({
        success: false,
        error: 'Database unavailable',
        message: 'Server is initializing. Please retry in a moment.'
      });
    }

    const db = req.db;
    const driverId = req.user.userId;
    const driverFilter = await buildDriverTripFilter(db, req.user);

    console.log('🔍 Driver ID:', driverId);
    console.log('   Type:', typeof driverId);

    // ── 1. ORIGINAL: roster_assigned_trips ──────────────────────────────────
    const rosterTrips = await db.collection('roster_assigned_trips').find({
      ...driverFilter,
      status: { $in: ['assigned', 'pending'] },
      tripType: { $in: ['individual', 'manual'] }
    }).sort({ createdAt: -1 }).toArray();

    console.log(`✅ Roster trips (pending): ${rosterTrips.length}`);

    // ── 2. NEW: trips collection (admin manual trips) ────────────────────────
    let manualTrips = [];
    try {
      manualTrips = await db.collection('trips').find({
        ...driverFilter,
        status: { $in: ['assigned', 'accepted'] },
      }).sort({ createdAt: -1 }).toArray();
      console.log(`✅ Manual trips (pending): ${manualTrips.length}`);
    } catch (e) {
      console.error('⚠️  trips collection query failed:', e.message);
    }

    // ── 3. NEW: client_created_trips ─────────────────────────────────────────
    let clientTrips = [];
    try {
      clientTrips = await db.collection('client_created_trips').find({
        ...driverFilter,
        status: { $in: ['assigned', 'accepted'] },
      }).sort({ createdAt: -1 }).toArray();
      console.log(`✅ Client trips (pending): ${clientTrips.length}`);
    } catch (e) {
      console.error('⚠️  client_created_trips query failed:', e.message);
    }

    const normalisedManual = manualTrips.map(normaliseManualTrip);
    const normalisedClient = clientTrips.map(normaliseClientTrip);
    const allTrips = [...rosterTrips, ...normalisedManual, ...normalisedClient];

    // ✅ Add vehicle lookup for each trip (original logic preserved)
    for (const trip of allTrips) {
      if (trip.vehicleId) {
        try {
          const vehicle = await db.collection('vehicles').findOne({
            _id: new ObjectId(trip.vehicleId)
          });
          if (vehicle) {
            trip.vehicleNumber = vehicle.registrationNumber || vehicle.vehicleNumber || trip.vehicleNumber || 'Unknown';
            trip.vehicleType = vehicle.vehicleType || '';
            trip.vehicleCapacity = vehicle.capacity || 0;
            console.log(`   🚗 Vehicle lookup: ${trip.vehicleNumber}`);
          }
        } catch (e) {
          console.error(`   ⚠️  Vehicle lookup failed for trip ${trip._id}:`, e.message);
        }
      }
    }

    allTrips.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    const formattedTrips = allTrips.map(trip => ({
      _id: trip._id.toString(),
      tripNumber: trip.tripNumber || `TRIP-${trip._id.toString().slice(-8)}`,
      status: trip.status,
      distance: trip.distance || 0,
      vehicleNumber: trip.vehicleNumber || 'Not Assigned',
      vehicleType: trip.vehicleType || '',
      vehicleCapacity: trip.vehicleCapacity || 0,
      pickupLocation: {
        address: trip.pickupLocation?.address || 'Unknown',
        latitude: trip.pickupLocation?.latitude || 0,
        longitude: trip.pickupLocation?.longitude || 0
      },
      dropLocation: {
        address: trip.dropLocation?.address || 'Unknown',
        latitude: trip.dropLocation?.latitude || 0,
        longitude: trip.dropLocation?.longitude || 0
      },
      customer: {
        name: trip.customerName || 'Unknown Customer',
        phone: trip.customerPhone || ''
      },
      createdAt: trip.createdAt,
      scheduledTime: trip.scheduledTime || trip.scheduledPickupTime,
      customerName: trip.customerName || 'Unknown Customer',
      customerPhone: trip.customerPhone || '',
      tripType: trip.tripType || 'manual',
      source: trip._source || 'roster_assigned_trips',
    }));

    console.log(`📊 Total pending trips: ${formattedTrips.length} (roster: ${rosterTrips.length} + manual: ${normalisedManual.length} + client: ${normalisedClient.length})`);

    res.json({
      success: true,
      trips: formattedTrips,
      data: formattedTrips,
    });

  } catch (error) {
    console.error('❌ Error fetching pending trips:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// @route   GET /api/driver-trips/individual/accepted
// @desc    Get accepted/in-progress individual trips for driver
//          ✅ UPDATED: Now includes trips + client_created_trips
// @access  Private (Driver)
// ============================================================================
router.get('/individual/accepted', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '✅'.repeat(40));
    console.log('FETCHING ACCEPTED INDIVIDUAL TRIPS');
    console.log('✅'.repeat(40));

    if (!req.db) {
      console.error('❌ Database not available');
      return res.status(503).json({ success: false, error: 'Database unavailable' });
    }

    const db = req.db;
    const driverId = req.user.userId;
    const driverFilter = await buildDriverTripFilter(db, req.user);

    console.log('🔍 Driver ID:', driverId);
    console.log('   Type:', typeof driverId);

    // ── 1. ORIGINAL: roster_assigned_trips ──────────────────────────────────
    const rosterTrips = await db.collection('roster_assigned_trips').find({
      ...driverFilter,
      status: { $in: ['accepted', 'started', 'in_progress'] },
      tripType: { $in: ['individual', 'manual'] }
    }).sort({ createdAt: -1 }).toArray();

    console.log(`✅ Roster trips (accepted): ${rosterTrips.length}`);

    // ── 2. NEW: trips collection ─────────────────────────────────────────────
    let manualTrips = [];
    try {
      manualTrips = await db.collection('trips').find({
        ...driverFilter,
        status: { $in: ['accepted', 'started', 'in_progress'] },
      }).sort({ createdAt: -1 }).toArray();
      console.log(`✅ Manual trips (accepted): ${manualTrips.length}`);
    } catch (e) {
      console.error('⚠️  trips collection query failed:', e.message);
    }

    // ── 3. NEW: client_created_trips ─────────────────────────────────────────
    let clientTrips = [];
    try {
      clientTrips = await db.collection('client_created_trips').find({
        ...driverFilter,
        status: { $in: ['accepted', 'started', 'in_progress'] },
      }).sort({ createdAt: -1 }).toArray();
      console.log(`✅ Client trips (accepted): ${clientTrips.length}`);
    } catch (e) {
      console.error('⚠️  client_created_trips query failed:', e.message);
    }

    const normalisedManual = manualTrips.map(normaliseManualTrip);
    const normalisedClient = clientTrips.map(normaliseClientTrip);
    const allTrips = [...rosterTrips, ...normalisedManual, ...normalisedClient];

    // ✅ Add vehicle lookup (original logic preserved)
    for (const trip of allTrips) {
      if (trip.vehicleId) {
        try {
          const vehicle = await db.collection('vehicles').findOne({ _id: new ObjectId(trip.vehicleId) });
          if (vehicle) {
            trip.vehicleNumber = vehicle.registrationNumber || vehicle.vehicleNumber || trip.vehicleNumber || 'Unknown';
            trip.vehicleType = vehicle.vehicleType || '';
            trip.vehicleCapacity = vehicle.capacity || 0;
            console.log(`   🚗 Vehicle lookup: ${trip.vehicleNumber}`);
          }
        } catch (e) {
          console.error(`   ⚠️  Vehicle lookup failed for trip ${trip._id}:`, e.message);
        }
      }
    }

    allTrips.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    const formattedTrips = allTrips.map(trip => ({
      _id: trip._id.toString(),
      tripNumber: trip.tripNumber || `TRIP-${trip._id.toString().slice(-8)}`,
      status: trip.status,
      distance: trip.distance || 0,
      vehicleNumber: trip.vehicleNumber || 'Not Assigned',
      vehicleType: trip.vehicleType || '',
      vehicleCapacity: trip.vehicleCapacity || 0,
      pickupLocation: {
        address: trip.pickupLocation?.address || 'Unknown',
        latitude: trip.pickupLocation?.latitude || 0,
        longitude: trip.pickupLocation?.longitude || 0
      },
      dropLocation: {
        address: trip.dropLocation?.address || 'Unknown',
        latitude: trip.dropLocation?.latitude || 0,
        longitude: trip.dropLocation?.longitude || 0
      },
      customer: {
        name: trip.customerName || 'Unknown Customer',
        phone: trip.customerPhone || ''
      },
      startOdometerReading: trip.startOdometerReading || null,
      startTime: trip.startTime || trip.actualStartTime || null,
      createdAt: trip.createdAt,
      customerName: trip.customerName || 'Unknown Customer',
      customerPhone: trip.customerPhone || '',
      tripType: trip.tripType || 'manual',
      source: trip._source || 'roster_assigned_trips',
    }));

    console.log(`📊 Total accepted trips: ${formattedTrips.length}`);

    res.json({ success: true, trips: formattedTrips, data: formattedTrips });

  } catch (error) {
    console.error('❌ Error fetching accepted trips:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// @route   GET /api/driver-trips/individual/completed
// @desc    Get completed individual trips for driver
//          ✅ UPDATED: Now includes trips + client_created_trips
// @access  Private (Driver)
// ============================================================================
router.get('/individual/completed', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '🏁'.repeat(40));
    console.log('FETCHING COMPLETED INDIVIDUAL TRIPS');
    console.log('🏁'.repeat(40));

    if (!req.db) {
      console.error('❌ Database not available');
      return res.status(503).json({ success: false, error: 'Database unavailable' });
    }

    const db = req.db;
    const driverId = req.user.userId;
    const driverFilter = await buildDriverTripFilter(db, req.user);

    console.log('🔍 Driver ID:', driverId);
    console.log('   Type:', typeof driverId);

    // ── 1. ORIGINAL: roster_assigned_trips ──────────────────────────────────
    const rosterTrips = await db.collection('roster_assigned_trips').find({
      ...driverFilter,
      status: 'completed',
      tripType: { $in: ['individual', 'manual'] }
    }).sort({ completedAt: -1 }).limit(50).toArray();

    console.log(`✅ Roster trips (completed): ${rosterTrips.length}`);

    // ── 2. NEW: trips collection ─────────────────────────────────────────────
    let manualTrips = [];
    try {
      manualTrips = await db.collection('trips').find({
        ...driverFilter,
        status: 'completed',
      }).sort({ updatedAt: -1 }).limit(50).toArray();
      console.log(`✅ Manual trips (completed): ${manualTrips.length}`);
    } catch (e) {
      console.error('⚠️  trips collection query failed:', e.message);
    }

    // ── 3. NEW: client_created_trips ─────────────────────────────────────────
    let clientTrips = [];
    try {
      clientTrips = await db.collection('client_created_trips').find({
        ...driverFilter,
        status: 'completed',
      }).sort({ updatedAt: -1 }).limit(50).toArray();
      console.log(`✅ Client trips (completed): ${clientTrips.length}`);
    } catch (e) {
      console.error('⚠️  client_created_trips query failed:', e.message);
    }

    const normalisedManual = manualTrips.map(normaliseManualTrip);
    const normalisedClient = clientTrips.map(normaliseClientTrip);
    const allTrips = [...rosterTrips, ...normalisedManual, ...normalisedClient];

    // ✅ Add vehicle lookup (original logic preserved)
    for (const trip of allTrips) {
      if (trip.vehicleId) {
        try {
          const vehicle = await db.collection('vehicles').findOne({ _id: new ObjectId(trip.vehicleId) });
          if (vehicle) {
            trip.vehicleNumber = vehicle.registrationNumber || vehicle.vehicleNumber || trip.vehicleNumber || 'Unknown';
            trip.vehicleType = vehicle.vehicleType || '';
            trip.vehicleCapacity = vehicle.capacity || 0;
            console.log(`   🚗 Vehicle lookup: ${trip.vehicleNumber}`);
          }
        } catch (e) {
          console.error(`   ⚠️  Vehicle lookup failed for trip ${trip._id}:`, e.message);
        }
      }
    }

    allTrips.sort((a, b) => {
      const dateA = a.completedAt || a.updatedAt || a.createdAt;
      const dateB = b.completedAt || b.updatedAt || b.createdAt;
      return new Date(dateB) - new Date(dateA);
    });

    const formattedTrips = allTrips.map(trip => ({
      _id: trip._id.toString(),
      tripNumber: trip.tripNumber || `TRIP-${trip._id.toString().slice(-8)}`,
      status: trip.status,
      distance: trip.distance || 0,
      actualDistance: trip.actualDistance || trip.distance || 0,
      vehicleNumber: trip.vehicleNumber || 'Not Assigned',
      vehicleType: trip.vehicleType || '',
      vehicleCapacity: trip.vehicleCapacity || 0,
      pickupLocation: {
        address: trip.pickupLocation?.address || 'Unknown',
        latitude: trip.pickupLocation?.latitude || 0,
        longitude: trip.pickupLocation?.longitude || 0
      },
      dropLocation: {
        address: trip.dropLocation?.address || 'Unknown',
        latitude: trip.dropLocation?.latitude || 0,
        longitude: trip.dropLocation?.longitude || 0
      },
      customer: {
        name: trip.customerName || 'Unknown Customer',
        phone: trip.customerPhone || ''
      },
      startOdometerReading: trip.startOdometerReading || null,
      endOdometerReading: trip.endOdometerReading || null,
      startTime: trip.startTime || trip.actualStartTime || null,
      endTime: trip.endTime || trip.actualEndTime || null,
      completedAt: trip.completedAt || trip.updatedAt || null,
      createdAt: trip.createdAt,
      customerName: trip.customerName || 'Unknown Customer',
      customerPhone: trip.customerPhone || '',
      tripType: trip.tripType || 'manual',
      source: trip._source || 'roster_assigned_trips',
    }));

    console.log(`📊 Total completed trips: ${formattedTrips.length}`);

    res.json({ success: true, trips: formattedTrips, data: formattedTrips });

  } catch (error) {
    console.error('❌ Error fetching completed trips:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});


router.post('/individual/:tripId/arrive', verifyToken, async (req, res) => {
  try {
    if (!req.db) return res.status(503).json({ success: false, error: 'Database unavailable' });

    const db = req.db;
    const { tripId } = req.params;
    const { latitude, longitude } = req.body;
    const driverId = req.user.userId;

    let oid;
    try { oid = new ObjectId(tripId); } catch { return res.status(400).json({ success: false, error: 'Invalid trip ID' }); }

    const locationUpdate = latitude && longitude
      ? { currentLocation: { latitude, longitude, timestamp: new Date() } }
      : {};

    // Try every collection — first match wins
    const driverFilter = await buildDriverTripFilter(db, req.user);
    let updated = false;
    for (const col of DRIVER_TRIP_COLLECTIONS) {
      const result = await db.collection(col).updateOne(
        { _id: oid, ...driverFilter },
        { $set: { ...locationUpdate, arrivedAt: new Date(), updatedAt: new Date() } }
      );
      if (result.matchedCount > 0) {
        updated = true;
        console.log(`✅ Arrived marked in ${col}`);
        break;
      }
    }

    if (!updated) return res.status(404).json({ success: false, error: 'Trip not found' });

    res.json({ success: true, message: 'Marked as arrived' });
  } catch (err) {
    console.error('❌ /arrive:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ============================================================================
// @route   POST /api/driver-trips/individual/:tripId/depart
// @desc    Mark driver departed from current stop
// @access  Private (Driver)
// ============================================================================
router.post('/individual/:tripId/depart', verifyToken, async (req, res) => {
  try {
    if (!req.db) return res.status(503).json({ success: false, error: 'Database unavailable' });

    const db = req.db;
    const { tripId } = req.params;
    const { latitude, longitude } = req.body;
    const driverId = req.user.userId;

    let oid;
    try { oid = new ObjectId(tripId); } catch { return res.status(400).json({ success: false, error: 'Invalid trip ID' }); }

    const locationUpdate = latitude && longitude
      ? { currentLocation: { latitude, longitude, timestamp: new Date() } }
      : {};

    const driverFilter = await buildDriverTripFilter(db, req.user);
    let updated = false;
    for (const col of DRIVER_TRIP_COLLECTIONS) {
      const result = await db.collection(col).updateOne(
        { _id: oid, ...driverFilter },
        { $set: { ...locationUpdate, departedAt: new Date(), updatedAt: new Date() } }
      );
      if (result.matchedCount > 0) {
        updated = true;
        console.log(`✅ Departed marked in ${col}`);
        break;
      }
    }

    if (!updated) return res.status(404).json({ success: false, error: 'Trip not found' });

    res.json({ success: true, message: 'Marked as departed' });
  } catch (err) {
    console.error('❌ /depart:', err);
    res.status(500).json({ success: false, error: err.message });
  }
});

// ============================================================================
// @route   POST /api/driver-trips/individual/:tripId/location
// @desc    Update GPS location for live tracking (called every 60 seconds)
// @access  Private (Driver)
// ============================================================================
router.post('/individual/:tripId/location', verifyToken, async (req, res) => {
  try {
    if (!req.db) return res.json({ success: false });

    const db = req.db;
    const { tripId } = req.params;
    const { latitude, longitude, speed, heading } = req.body;
    const driverId = req.user.userId;

    let oid;
    try { oid = new ObjectId(tripId); } catch { return res.json({ success: false }); }

    const locationEntry = {
      latitude,
      longitude,
      speed: speed || null,
      heading: heading || null,
      timestamp: new Date(),
    };

    // Try every collection — first match wins
    const driverFilter = await buildDriverTripFilter(db, req.user);
    for (const col of DRIVER_TRIP_COLLECTIONS) {
      const result = await db.collection(col).updateOne(
        { _id: oid, ...driverFilter },
        {
          $set: { currentLocation: locationEntry, updatedAt: new Date() },
          $push: { locationHistory: { $each: [locationEntry], $slice: -200 } },
        }
      );
      if (result.matchedCount > 0) break;
    }

    res.json({ success: true });
  } catch (err) {
    // Silent fail — location updates must never 500
    res.json({ success: false });
  }
});


// ============================================================================
// @route   POST /api/driver-trips/individual/:tripId/respond
// @desc    Accept or decline an individual trip
//          ✅ UPDATED: Checks trips + client_created_trips if not in roster
//          ✅ ALLOWS drivers to change their response (decline → accept or vice versa)
// @access  Private (Driver)
// ============================================================================
router.post('/individual/:tripId/respond', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '🎯'.repeat(40));
    console.log('DRIVER RESPONDING TO INDIVIDUAL TRIP');
    console.log('🎯'.repeat(40));

    if (!req.db) {
      console.error('❌ Database not available');
      return res.status(503).json({ success: false, error: 'Database unavailable' });
    }

    const db = req.db;
    const { tripId } = req.params;
    const { response, notes } = req.body;
    const driverId = req.user.userId;

    console.log('Trip ID:', tripId);
    console.log('Response:', response);
    console.log('Driver ID:', driverId);
    console.log('   Type:', typeof driverId);

    if (!['accept', 'decline'].includes(response)) {
      return res.status(400).json({ success: false, error: 'Invalid response. Must be "accept" or "decline"' });
    }

    let oid;
    try { oid = new ObjectId(tripId); } catch { return res.status(400).json({ success: false, error: 'Invalid trip ID' }); }

    // ── Locate the trip across every collection, matching the driver by ANY of
    //    their known identifiers (fixes false 404s from id/collection mismatch).
    const driverFilter = await buildDriverTripFilter(db, req.user);
    let trip = null;
    let collectionName = null;
    for (const cn of DRIVER_TRIP_COLLECTIONS) {
      try {
        const found = await db.collection(cn).findOne({ _id: oid, ...driverFilter });
        if (found) { trip = found; collectionName = cn; break; }
      } catch (e) { console.error(`⚠️  ${cn} lookup failed:`, e.message); }
    }

    if (!trip) {
      console.error('❌ Trip not found in any collection for driver:', driverId);
      return res.status(404).json({
        success: false,
        error: 'Trip not found or not assigned to you'
      });
    }

    console.log(`✅ Trip found in: ${collectionName}`);
    console.log(`   Current status: ${trip.status}`);

    // ✅ BUSINESS RULE: Allow response changes UNLESS trip has already started or completed
    const immutableStatuses = ['started', 'in_progress', 'completed', 'cancelled'];
    if (immutableStatuses.includes(trip.status)) {
      console.error(`❌ Cannot respond - trip status is: ${trip.status}`);
      return res.status(400).json({ 
        success: false, 
        error: `Cannot respond to trip that is already ${trip.status}`,
        currentStatus: trip.status
      });
    }

    // ✅ Allow changing response (decline → accept or accept → decline)
    const previousStatus = trip.status;
    const newStatus = response === 'accept' ? 'accepted' : 'declined';

    console.log(`🔄 Changing status from "${previousStatus}" to "${newStatus}"`);

    await db.collection(collectionName).updateOne(
      { _id: oid },
      {
        $set: {
          status: newStatus,
          responseTime: new Date(),
          responseNotes: notes || '',
          driverResponse: response,
          driverResponseTime: new Date(),
          driverResponseNotes: notes || '',
          updatedAt: new Date(),
          [`statusHistory.${newStatus}`]: new Date(),
          ...(response === 'accept' ? { acceptedAt: new Date() } : {}),
          // Track if this was a status change
          ...(previousStatus !== 'assigned' && previousStatus !== 'pending' ? { 
            previousResponse: previousStatus,
            responseChanged: true,
            responseChangedAt: new Date()
          } : {}),
        }
      }
    );

    console.log(`✅ Trip ${response}d successfully in ${collectionName}`);
    
    // Update the notification document with driver response for persistence
    try {
      const notifUpdateResult = await db.collection('notifications').updateMany(
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

    // Send notification to admin (original logic preserved)
    const adminUsers = await db.collection('admin_users').find({
      role: { $in: ['admin', 'super_admin'] }
    }).toArray();

    const wasChanged = previousStatus === 'accepted' || previousStatus === 'declined';
    const notificationMessage = wasChanged 
      ? `Driver changed response from ${previousStatus} to ${newStatus} for trip ${trip.tripNumber || tripId}${notes ? `: ${notes}` : ''}`
      : `Driver has ${response}ed trip ${trip.tripNumber || tripId}${notes ? `: ${notes}` : ''}`;

    for (const admin of adminUsers) {
      await db.collection('notifications').insertOne({
        userId: admin._id,
        userRole: 'admin',
        title: wasChanged ? `Trip Response Changed` : `Trip ${response === 'accept' ? 'Accepted' : 'Declined'}`,
        message: notificationMessage,
        type: 'trip_response',
        tripId: oid,
        read: false,
        createdAt: new Date()
      });
    }

    res.json({ 
      success: true, 
      message: `Trip ${response}ed successfully`, 
      status: newStatus, 
      source: collectionName,
      wasChanged: wasChanged,
      previousStatus: previousStatus
    });

  } catch (error) {
    console.error('❌ Error responding to trip:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// @route   POST /api/driver-trips/individual/:tripId/start
// @desc    Start an individual trip
//          ✅ UPDATED: Checks trips + client_created_trips if not in roster
// @access  Private (Driver)
// ============================================================================
router.post('/individual/:tripId/start', verifyToken, upload.single('photo'), async (req, res) => {
  try {
    console.log('\n' + '🚀'.repeat(40));
    console.log('STARTING INDIVIDUAL TRIP');
    console.log('🚀'.repeat(40));

    if (!req.db) {
      console.error('❌ Database not available');
      return res.status(503).json({ success: false, error: 'Database unavailable' });
    }

    const db = req.db;
    const { tripId } = req.params;
    // ✅ Accept both 'odometerReading' (original) and 'reading' (new)
    const odometerReading = req.body.odometerReading || req.body.reading;
    const driverId = req.user.userId;

    console.log('Trip ID:', tripId);
    console.log('Odometer Reading:', odometerReading);
    console.log('Driver ID:', driverId);
    console.log('   Type:', typeof driverId);

    if (!odometerReading || !req.file) {
      return res.status(400).json({ success: false, error: 'Odometer reading and photo are required' });
    }

    // Upload photo to GridFS (original logic preserved)
    const bucket = new GridFSBucket(db, { bucketName: 'trip_photos' });
    const uploadStream = bucket.openUploadStream(`trip_start_${tripId}_${Date.now()}.jpg`, {
      contentType: req.file.mimetype
    });
    uploadStream.end(req.file.buffer);
    await new Promise((resolve, reject) => {
      uploadStream.on('finish', resolve);
      uploadStream.on('error', reject);
    });
    const photoId = uploadStream.id;

    let oid;
    try { oid = new ObjectId(tripId); } catch { return res.status(400).json({ success: false, error: 'Invalid trip ID' }); }

    // Find which collection this trip belongs to (match driver by any known id)
    const driverFilter = await buildDriverTripFilter(db, req.user);
    let trip = null;
    let collectionName = null;
    for (const cn of DRIVER_TRIP_COLLECTIONS) {
      try {
        const found = await db.collection(cn).findOne({ _id: oid, ...driverFilter });
        if (found) { trip = found; collectionName = cn; break; }
      } catch (e) { console.error(`⚠️  ${cn} lookup failed:`, e.message); }
    }

    if (!trip) {
      return res.status(404).json({ success: false, error: 'Trip not found' });
    }

    console.log(`✅ Trip found in: ${collectionName}`);

    await db.collection(collectionName).updateOne(
      { _id: oid },
      {
        $set: {
          status: 'started',
          startTime: new Date(),
          actualStartTime: new Date(),
          startOdometerReading: parseInt(odometerReading),
          startOdometerPhotoId: photoId,
          startOdometer: {
            reading: parseInt(odometerReading),
            photoId: photoId,
            timestamp: new Date(),
          },
          'statusHistory.started': new Date(),
          updatedAt: new Date()
        }
      }
    );

    console.log('✅ Trip started successfully');

    res.json({ success: true, message: 'Trip started successfully', source: collectionName });

  } catch (error) {
    console.error('❌ Error starting trip:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================================
// @route   POST /api/driver-trips/individual/:tripId/end
// @desc    End an individual trip
//          ✅ UPDATED: Checks trips + client_created_trips if not in roster
// @access  Private (Driver)
// ============================================================================
router.post('/individual/:tripId/end', verifyToken, upload.single('photo'), async (req, res) => {
  try {
    console.log('\n' + '🏁'.repeat(40));
    console.log('ENDING INDIVIDUAL TRIP');
    console.log('🏁'.repeat(40));

    if (!req.db) {
      console.error('❌ Database not available');
      return res.status(503).json({ success: false, error: 'Database unavailable' });
    }

    const db = req.db;
    const { tripId } = req.params;
    // ✅ Accept both 'odometerReading' (original) and 'reading' (new)
    const odometerReading = req.body.odometerReading || req.body.reading;
    const driverId = req.user.userId;

    console.log('Trip ID:', tripId);
    console.log('Odometer Reading:', odometerReading);
    console.log('Driver ID:', driverId);
    console.log('   Type:', typeof driverId);

    if (!odometerReading || !req.file) {
      return res.status(400).json({ success: false, error: 'Odometer reading and photo are required' });
    }

    let oid;
    try { oid = new ObjectId(tripId); } catch { return res.status(400).json({ success: false, error: 'Invalid trip ID' }); }

    // Find which collection this trip belongs to (match driver by any known id)
    const driverFilter = await buildDriverTripFilter(db, req.user);
    let trip = null;
    let collectionName = null;
    for (const cn of DRIVER_TRIP_COLLECTIONS) {
      try {
        const found = await db.collection(cn).findOne({ _id: oid, ...driverFilter });
        if (found) { trip = found; collectionName = cn; break; }
      } catch (e) { console.error(`⚠️  ${cn} lookup failed:`, e.message); }
    }

    if (!trip) {
      return res.status(404).json({ success: false, error: 'Trip not found' });
    }

    console.log(`✅ Trip found in: ${collectionName}`);

    // Upload photo to GridFS (original logic preserved)
    const bucket = new GridFSBucket(db, { bucketName: 'trip_photos' });
    const uploadStream = bucket.openUploadStream(`trip_end_${tripId}_${Date.now()}.jpg`, {
      contentType: req.file.mimetype
    });
    uploadStream.end(req.file.buffer);
    await new Promise((resolve, reject) => {
      uploadStream.on('finish', resolve);
      uploadStream.on('error', reject);
    });
    const photoId = uploadStream.id;

    const endReading = parseInt(odometerReading);
    const startReading = trip.startOdometerReading || trip.startOdometer?.reading || 0;
    const actualDistance = endReading - startReading;

    await db.collection(collectionName).updateOne(
      { _id: oid },
      {
        $set: {
          status: 'completed',
          endTime: new Date(),
          actualEndTime: new Date(),
          completedAt: new Date(),
          endOdometerReading: endReading,
          endOdometerPhotoId: photoId,
          endOdometer: {
            reading: endReading,
            photoId: photoId,
            timestamp: new Date(),
          },
          actualDistance: actualDistance,
          'statusHistory.completed': new Date(),
          updatedAt: new Date()
        }
      }
    );

    console.log('✅ Trip completed successfully');
    console.log(`   Actual distance: ${actualDistance} km`);

    // Notify admin (original logic preserved)
    const adminUsers = await db.collection('admin_users').find({
      role: { $in: ['admin', 'super_admin'] }
    }).toArray();

    for (const admin of adminUsers) {
      await db.collection('notifications').insertOne({
        userId: admin._id,
        userRole: 'admin',
        title: 'Trip Completed',
        message: `Trip ${trip.tripNumber || tripId} completed. Distance: ${actualDistance} km`,
        type: 'trip_completed',
        tripId: oid,
        read: false,
        createdAt: new Date()
      });
    }

    res.json({
      success: true,
      message: 'Trip completed successfully',
      actualDistance: actualDistance,
      data: { actualDistance: actualDistance },
      source: collectionName,
    });

  } catch (error) {
    console.error('❌ Error ending trip:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

module.exports = router;