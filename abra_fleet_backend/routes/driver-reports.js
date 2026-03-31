// ============================================================================
// FILE: routes/driver_reports_routes.js
// ✅ UPDATED: Includes roster-assigned trips, individual admin trips,
//             AND client_created_trips (clientName → customerName normalised)
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const PDFDocument = require('pdfkit');
const fs = require('fs');
const path = require('path');

// ============================================================================
// LOGO PATH RESOLVER
// ============================================================================

let CACHED_LOGO_PATH = null;

function findLogoPath() {
  const possiblePaths = [
    path.join(__dirname, '..', 'assets', 'abra.jpeg'),
    path.join(__dirname, '..', 'assets', 'abra.jpg'),
    path.join(__dirname, '..', 'assets', 'abra.png'),
    path.join(__dirname, '..', '..', 'assets', 'abra.jpeg'),
    path.join(__dirname, '..', '..', 'assets', 'abra.jpg'),
    path.join(__dirname, '..', '..', 'assets', 'abra.png'),
    path.join(process.cwd(), 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'assets', 'abra.jpg'),
    path.join(process.cwd(), 'assets', 'abra.png'),
    path.join(process.cwd(), 'abra_fleet_backend', 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'abra_fleet_backend', 'assets', 'abra.jpg'),
    path.join(process.cwd(), 'abra_fleet_backend', 'assets', 'abra.png'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.jpeg'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.jpg'),
    path.join(process.cwd(), 'backend', 'assets', 'abra.png'),
  ];

  for (const testPath of possiblePaths) {
    try {
      if (fs.existsSync(testPath)) {
        const stats = fs.statSync(testPath);
        if (stats.isFile() && stats.size > 0) {
          console.log('✅ LOGO FOUND:', testPath);
          return testPath;
        }
      }
    } catch (err) {
      // Continue searching
    }
  }

  console.error('❌ LOGO NOT FOUND!');
  return null;
}

function getLogoPath() {
  if (!CACHED_LOGO_PATH) {
    CACHED_LOGO_PATH = findLogoPath();
  }
  return CACHED_LOGO_PATH;
}

/**
 * HELPER: Build robust query based on Email or Driver ID
 */
async function buildDriverQuery(db, email, driverId) {
  const driver = await db.collection('drivers').findOne({
    $or: [
      { email: email },
      { 'personalInfo.email': email },
      { driverId: driverId }
    ]
  });

  if (!driver) {
    throw new Error('Driver not found');
  }

  return {
    driverId: driver._id,
    driverMongoId: driver._id,
    driverInfo: driver
  };
}

/**
 * HELPER: Build driverId filter for trips/client_created_trips collections
 * (these use string driverId, not ObjectId)
 */
function buildStringDriverFilter(driverMongoId) {
  return {
    $or: [
      { driverId: driverMongoId.toString() },
      { driverId: driverMongoId },
    ]
  };
}

/**
 * ✅ UPDATED HELPER: Get ALL trips for driver from all 3 collections
 * - roster-assigned-trips (original)
 * - trips (admin manual trips)
 * - client_created_trips (client-requested, assigned by admin)
 */
async function getAllDriverTrips(db, driverMongoId) {
  console.log('📊 Fetching trips from ALL collections...');

  // ── 1. Get roster-assigned trips (original) ──────────────────────────────
  const rosterTrips = await db.collection('roster-assigned-trips')
    .find({ driverId: driverMongoId })
    .toArray();

  console.log(`   ✅ Roster trips: ${rosterTrips.length}`);

  // ── 2. Get individual/manual trips (admin-created, trips collection) ─────
  let manualTrips = [];
  try {
    manualTrips = await db.collection('trips')
      .find(buildStringDriverFilter(driverMongoId))
      .toArray();
    console.log(`   ✅ Manual trips (trips collection): ${manualTrips.length}`);
  } catch (e) {
    console.error('   ⚠️  trips collection query failed:', e.message);
  }

  // ── 3. ✅ NEW: Get client_created_trips ───────────────────────────────────
  let clientTrips = [];
  try {
    clientTrips = await db.collection('client_created_trips')
      .find(buildStringDriverFilter(driverMongoId))
      .toArray();
    console.log(`   ✅ Client trips: ${clientTrips.length}`);

    // Normalise clientName → customerName for uniform processing
    clientTrips = clientTrips.map(trip => ({
      ...trip,
      customerName: trip.clientName || trip.customerName || 'Unknown Client',
      customerPhone: trip.clientPhone || trip.customerPhone || '',
      customerEmail: trip.clientEmail || trip.customerEmail || '',
      // Normalise odometer fields
      startOdometerReading: trip.startOdometer?.reading || trip.startOdometerReading || null,
      endOdometerReading: trip.endOdometer?.reading || trip.endOdometerReading || null,
      startTime: trip.actualStartTime || trip.startTime || null,
      endTime: trip.actualEndTime || trip.endTime || null,
      _source: 'client_created_trips',
    }));
  } catch (e) {
    console.error('   ⚠️  client_created_trips query failed:', e.message);
  }

  // Combine all three arrays
  const allTrips = [...rosterTrips, ...manualTrips, ...clientTrips];

  console.log(`   📊 Total trips across all collections: ${allTrips.length}`);

  return allTrips;
}

// ============================================================================
// GET /api/driver/reports/performance-summary
// ✅ UPDATED: Includes roster trips, manual trips AND client_created_trips
// ============================================================================
router.get('/performance-summary', async (req, res) => {
  try {
    const jwtUser = req.user;
    const db = req.db;

    if (!jwtUser || !jwtUser.email) {
      return res.status(401).json({
        status: 'error',
        message: 'Unauthorized: No email found in token'
      });
    }

    const driverEmail = jwtUser.email;
    const driverIdFromToken = jwtUser.driverId || jwtUser.id || jwtUser.uid;

    console.log(`📊 [PERFORMANCE] Fetching stats for: ${driverEmail}`);

    const driverQuery = await buildDriverQuery(db, driverEmail, driverIdFromToken);
    const driverMongoId = driverQuery.driverMongoId;
    const driver = driverQuery.driverInfo;

    console.log(`✅ Driver found: ${driver.personalInfo?.name || driver.name}`);
    console.log(`   MongoDB _id: ${driverMongoId}`);

    // ✅ Get ALL trips (roster + manual + client)
    const allTrips = await getAllDriverTrips(db, driverMongoId);

    console.log(`   Found ${allTrips.length} trips total.`);

    if (allTrips.length === 0) {
      return res.json({
        status: 'success',
        data: {
          scheduledTrips: 0,
          completedTrips: 0,
          totalDistance: 0,
          avgRating: 0
        }
      });
    }

    // ✅ SCHEDULED TRIPS (assigned, started, in_progress, accepted)
    const scheduledTrips = allTrips.filter(t =>
      ['assigned', 'started', 'in_progress', 'accepted'].includes(t.status)
    ).length;

    // ✅ COMPLETED TRIPS (status = 'completed' ONLY)
    const completedTrips = allTrips.filter(t => t.status === 'completed');
    const completedTripsCount = completedTrips.length;

    // ✅ TOTAL DISTANCE (use totalDistance OR actualDistance)
    const totalDistance = completedTrips.reduce((sum, t) => {
      const distance = Number(t.totalDistance) || Number(t.actualDistance) || Number(t.distance) || 0;
      return sum + distance;
    }, 0);

    // ✅ AVERAGE RATING (from driver_feedback collection)
    const feedbackStats = await db.collection('driver_feedback').aggregate([
      {
        $match: {
          driverId: driverMongoId,
          feedbackType: 'driver_trip_feedback'
        }
      },
      {
        $group: {
          _id: null,
          avgRating: { $avg: '$rating' },
          totalFeedback: { $sum: 1 }
        }
      }
    ]).toArray();

    const avgRating = feedbackStats.length > 0
      ? parseFloat(feedbackStats[0].avgRating.toFixed(1))
      : 0;

    console.log(`\n📊 PERFORMANCE METRICS:`);
    console.log(`   Scheduled Trips: ${scheduledTrips}`);
    console.log(`   Completed Trips: ${completedTripsCount}`);
    console.log(`   Total Distance: ${totalDistance.toFixed(1)} km`);
    console.log(`   Average Rating: ${avgRating}/5.0`);

    res.json({
      status: 'success',
      data: {
        scheduledTrips: scheduledTrips,
        completedTrips: completedTripsCount,
        totalDistance: parseFloat(totalDistance.toFixed(1)),
        avgRating: avgRating
      }
    });

  } catch (error) {
    console.error('❌ Error fetching performance summary:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// ============================================================================
// GET /api/driver/reports/daily-analytics
// ✅ UPDATED: Includes roster trips, manual trips AND client_created_trips
// ============================================================================
router.get('/daily-analytics', async (req, res) => {
  try {
    const jwtUser = req.user;
    const db = req.db;
    const targetDate = req.query.date ? new Date(req.query.date) : new Date();

    if (!jwtUser || !jwtUser.email) {
      return res.status(401).json({
        status: 'error',
        message: 'Unauthorized'
      });
    }

    const driverEmail = jwtUser.email;
    const driverIdFromToken = jwtUser.driverId || jwtUser.id || jwtUser.uid;

    console.log(`📊 [DAILY] Fetching for: ${driverEmail} on ${targetDate.toISOString().split('T')[0]}`);

    const driverQuery = await buildDriverQuery(db, driverEmail, driverIdFromToken);
    const driverMongoId = driverQuery.driverMongoId;

    // Date string for today (YYYY-MM-DD)
    const today = targetDate.toISOString().split('T')[0];

    // ── 1. ORIGINAL: roster trips today ─────────────────────────────────────
    const rosterTripsToday = await db.collection('roster-assigned-trips').find({
      driverId: driverMongoId,
      scheduledDate: today
    }).toArray();

    // ── 2. ORIGINAL: individual/manual trips today ───────────────────────────
    const manualTripsToday = await db.collection('trips').find({
      ...buildStringDriverFilter(driverMongoId),
      $or: [
        {
          scheduledPickupTime: {
            $gte: new Date(today + 'T00:00:00.000Z'),
            $lt: new Date(today + 'T23:59:59.999Z')
          }
        },
        {
          actualStartTime: {
            $gte: new Date(today + 'T00:00:00.000Z'),
            $lt: new Date(today + 'T23:59:59.999Z')
          }
        }
      ]
    }).toArray();

    // ── 3. ✅ NEW: client_created_trips today ────────────────────────────────
    let clientTripsToday = [];
    try {
      clientTripsToday = await db.collection('client_created_trips').find({
        ...buildStringDriverFilter(driverMongoId),
        $or: [
          {
            scheduledPickupTime: {
              $gte: new Date(today + 'T00:00:00.000Z'),
              $lt: new Date(today + 'T23:59:59.999Z')
            }
          },
          {
            actualStartTime: {
              $gte: new Date(today + 'T00:00:00.000Z'),
              $lt: new Date(today + 'T23:59:59.999Z')
            }
          }
        ]
      }).toArray();
      console.log(`   ✅ Client trips today: ${clientTripsToday.length}`);
    } catch (e) {
      console.error('   ⚠️  client_created_trips daily query failed:', e.message);
    }

    const todayTrips = [...rosterTripsToday, ...manualTripsToday, ...clientTripsToday];

    console.log(`   Found ${todayTrips.length} trips for today (${rosterTripsToday.length} roster + ${manualTripsToday.length} manual + ${clientTripsToday.length} client)`);

    // ✅ Calculate working hours (from actualStartTime to actualEndTime)
    let totalWorkingMinutes = 0;
    todayTrips.forEach(trip => {
      if (trip.actualStartTime && trip.actualEndTime) {
        const start = new Date(trip.actualStartTime);
        const end = new Date(trip.actualEndTime);
        const minutes = (end - start) / (1000 * 60);
        totalWorkingMinutes += minutes;
      }
    });

    const hours = Math.floor(totalWorkingMinutes / 60);
    const minutes = Math.floor(totalWorkingMinutes % 60);
    const workingHours = `${hours}h ${minutes}min`;

    // ✅ Calculate distance (use totalDistance OR actualDistance OR distance)
    const totalDistance = todayTrips.reduce((sum, t) => {
      const distance = Number(t.totalDistance) || Number(t.actualDistance) || Number(t.distance) || 0;
      return sum + distance;
    }, 0);

    console.log(`\n📊 DAILY ANALYTICS:`);
    console.log(`   Working Hours: ${workingHours}`);
    console.log(`   Trips Today: ${todayTrips.length}`);
    console.log(`   Distance Today: ${totalDistance.toFixed(1)} km`);

    res.json({
      status: 'success',
      data: {
        workingHours: workingHours,
        tripsToday: todayTrips.length,
        distanceToday: totalDistance.toFixed(1)
      }
    });

  } catch (error) {
    console.error('❌ Error fetching daily analytics:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// ============================================================================
// GET /api/driver/reports/trips
// ✅ UPDATED: Shows trips from all 3 collections with proper formatting
// ============================================================================
router.get('/trips', async (req, res) => {
  try {
    const jwtUser = req.user;
    const db = req.db;
    const { startDate, endDate } = req.query;

    if (!jwtUser || !jwtUser.email) {
      return res.status(401).json({
        status: 'error',
        message: 'Unauthorized'
      });
    }

    const driverEmail = jwtUser.email;
    const driverIdFromToken = jwtUser.driverId || jwtUser.id || jwtUser.uid;

    const driverQuery = await buildDriverQuery(db, driverEmail, driverIdFromToken);
    const driverMongoId = driverQuery.driverMongoId;

    // Build date filter
    let dateFilter = {};
    if (startDate || endDate) {
      const start = startDate ? new Date(startDate).toISOString().split('T')[0] : null;
      const end = endDate ? new Date(endDate).toISOString().split('T')[0] : null;

      if (start && end) {
        dateFilter = { $gte: start, $lte: end };
      } else if (start) {
        dateFilter = { $gte: start };
      } else if (end) {
        dateFilter = { $lte: end };
      }
    }

    // ── 1. ORIGINAL: roster-assigned-trips ──────────────────────────────────
    const rosterQuery = { driverId: driverMongoId };
    if (Object.keys(dateFilter).length > 0) {
      rosterQuery.scheduledDate = dateFilter;
    }

    const rosterTrips = await db.collection('roster-assigned-trips')
      .find(rosterQuery)
      .toArray();

    // ── 2. ORIGINAL: trips collection (admin manual trips) ──────────────────
    const manualQuery = buildStringDriverFilter(driverMongoId);

    if (startDate || endDate) {
      const startDateTime = startDate ? new Date(startDate + 'T00:00:00.000Z') : null;
      const endDateTime = endDate ? new Date(endDate + 'T23:59:59.999Z') : null;

      if (startDateTime && endDateTime) {
        manualQuery.$or = [
          { scheduledPickupTime: { $gte: startDateTime, $lte: endDateTime } },
          { actualStartTime: { $gte: startDateTime, $lte: endDateTime } }
        ];
      } else if (startDateTime) {
        manualQuery.$or = [
          { scheduledPickupTime: { $gte: startDateTime } },
          { actualStartTime: { $gte: startDateTime } }
        ];
      } else if (endDateTime) {
        manualQuery.$or = [
          { scheduledPickupTime: { $lte: endDateTime } },
          { actualStartTime: { $lte: endDateTime } }
        ];
      }
    }

    const manualTrips = await db.collection('trips')
      .find(manualQuery)
      .toArray();

    // ── 3. ✅ NEW: client_created_trips ───────────────────────────────────────
    let clientTrips = [];
    try {
      const clientQuery = buildStringDriverFilter(driverMongoId);

      if (startDate || endDate) {
        const startDateTime = startDate ? new Date(startDate + 'T00:00:00.000Z') : null;
        const endDateTime = endDate ? new Date(endDate + 'T23:59:59.999Z') : null;

        if (startDateTime && endDateTime) {
          clientQuery.$or = [
            { scheduledPickupTime: { $gte: startDateTime, $lte: endDateTime } },
            { actualStartTime: { $gte: startDateTime, $lte: endDateTime } }
          ];
        } else if (startDateTime) {
          clientQuery.$or = [
            { scheduledPickupTime: { $gte: startDateTime } },
            { actualStartTime: { $gte: startDateTime } }
          ];
        } else if (endDateTime) {
          clientQuery.$or = [
            { scheduledPickupTime: { $lte: endDateTime } },
            { actualStartTime: { $lte: endDateTime } }
          ];
        }
      }

      clientTrips = await db.collection('client_created_trips')
        .find(clientQuery)
        .toArray();

      console.log(`   ✅ Client trips: ${clientTrips.length}`);
    } catch (e) {
      console.error('   ⚠️  client_created_trips query failed:', e.message);
    }

    // ✅ Combine all trips
    const allTrips = [...rosterTrips, ...manualTrips, ...clientTrips];

    console.log(`✅ Found ${allTrips.length} trips (${rosterTrips.length} roster + ${manualTrips.length} manual + ${clientTrips.length} client)`);

    // ✅ Get ratings from driver_feedback + format trip data properly
    const tripsWithRatings = await Promise.all(
      allTrips.map(async (trip) => {
        // Get feedback for this trip
        const feedback = await db.collection('driver_feedback').findOne({
          tripId: trip._id,
          feedbackType: 'driver_trip_feedback'
        });

        // ✅ Extract customer names (handle all 3 trip types)
        let customerNames = 'N/A';

        // For roster trips with stops array
        if (trip.stops && Array.isArray(trip.stops)) {
          customerNames = trip.stops
            .filter(stop => stop.type === 'pickup' && stop.customer && stop.customer.name)
            .map(stop => stop.customer.name)
            .join(', ');
        }
        // For client_created_trips — clientName maps to customerName
        else if (trip.clientName) {
          customerNames = trip.clientName;
        }
        // For individual/manual trips with customer object
        else if (trip.customer && trip.customer.name) {
          customerNames = trip.customer.name;
        }
        // For individual/manual trips with customerName field
        else if (trip.customerName) {
          customerNames = trip.customerName;
        }

        if (!customerNames || customerNames.trim() === '') {
          customerNames = 'N/A';
        }

        // ✅ Get proper distance
        const distance = Number(trip.totalDistance) || Number(trip.actualDistance) || Number(trip.distance) || 0;

        // ✅ Get trip number
        const tripNumber = trip.tripNumber || trip.tripGroupId || `TRIP-${trip._id.toString().slice(-8)}`;

        // ✅ Get pickup location (handles roster stops array and direct pickupLocation)
        let pickupLocation = 'N/A';
        if (trip.stops && trip.stops.length > 0 && trip.stops[0].location) {
          pickupLocation = trip.stops[0].location.address || 'N/A';
        } else if (trip.pickupLocation) {
          pickupLocation = trip.pickupLocation.address || `${trip.pickupLocation.latitude}, ${trip.pickupLocation.longitude}`;
        }

        // ✅ Get drop location
        let dropLocation = 'Office';
        if (trip.stops && trip.stops.length > 0) {
          const lastStop = trip.stops[trip.stops.length - 1];
          dropLocation = lastStop.location?.address || 'Office';
        } else if (trip.dropLocation) {
          dropLocation = trip.dropLocation.address || `${trip.dropLocation.latitude}, ${trip.dropLocation.longitude}`;
        }

        return {
          id: trip._id.toString(),
          tripNumber: tripNumber,
          startTime: trip.actualStartTime || trip.scheduledPickupTime || trip.scheduledDate,
          endTime: trip.actualEndTime || null,
          status: trip.status || 'unknown',
          distance: distance,
          rating: feedback ? feedback.rating : null,
          customerName: customerNames,
          pickupLocation: pickupLocation,
          dropLocation: dropLocation,
          // Metadata tag visible in reports UI
          tripType: trip.stops ? 'roster' : (trip.clientName ? 'client' : 'individual'),
          source: trip._source || (trip.stops ? 'roster' : (trip.clientName ? 'client_created_trips' : 'trips')),
        };
      })
    );

    // Sort by start time (most recent first)
    tripsWithRatings.sort((a, b) => {
      const dateA = a.startTime ? new Date(a.startTime) : new Date(0);
      const dateB = b.startTime ? new Date(b.startTime) : new Date(0);
      return dateB - dateA;
    });

    // Summary Calculation
    const completedTrips = tripsWithRatings.filter(t => t.status === 'completed');
    const totalDistance = completedTrips.reduce((sum, t) => sum + t.distance, 0);
    const totalDuration = completedTrips.reduce((sum, t) => {
      if (t.startTime && t.endTime) {
        return sum + (new Date(t.endTime) - new Date(t.startTime));
      }
      return sum;
    }, 0);

    res.json({
      status: 'success',
      data: {
        trips: tripsWithRatings,
        summary: {
          totalTrips: allTrips.length,
          completedTrips: completedTrips.length,
          totalDistance: totalDistance.toFixed(1),
          totalDurationHours: (totalDuration / (1000 * 60 * 60)).toFixed(1)
        }
      }
    });

  } catch (error) {
    console.error('❌ Error fetching trips:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// ============================================================================
// POST /api/driver/reports/generate
// ✅ UPDATED: Includes trips from all 3 collections
// ============================================================================
router.post('/generate', async (req, res) => {
  try {
    const jwtUser = req.user;
    const db = req.db;
    const { type, startDate: customStartDate, endDate: customEndDate } = req.body;

    if (!jwtUser || !jwtUser.email) {
      return res.status(401).json({
        status: 'error',
        message: 'Unauthorized'
      });
    }

    const driverEmail = jwtUser.email;
    const driverIdFromToken = jwtUser.driverId || jwtUser.id || jwtUser.uid;

    if (!['daily', 'weekly', 'monthly', 'custom'].includes(type)) {
      return res.status(400).json({
        status: 'error',
        message: 'Invalid report type'
      });
    }

    const driverQuery = await buildDriverQuery(db, driverEmail, driverIdFromToken);
    const driverMongoId = driverQuery.driverMongoId;
    const driver = driverQuery.driverInfo;

    // Determine Dates
    let startDate, endDate;
    const now = new Date();

    switch (type) {
      case 'daily':
        startDate = new Date().toISOString().split('T')[0];
        endDate = startDate;
        break;
      case 'weekly':
        const weekStart = new Date();
        const day = weekStart.getDay();
        const diff = weekStart.getDate() - day + (day === 0 ? -6 : 1);
        weekStart.setDate(diff);
        startDate = weekStart.toISOString().split('T')[0];

        const weekEnd = new Date(weekStart);
        weekEnd.setDate(weekStart.getDate() + 6);
        endDate = weekEnd.toISOString().split('T')[0];
        break;
      case 'monthly':
        startDate = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().split('T')[0];
        endDate = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().split('T')[0];
        break;
      case 'custom':
        if (!customStartDate) {
          return res.status(400).json({
            status: 'error',
            message: 'Start date required'
          });
        }
        startDate = new Date(customStartDate).toISOString().split('T')[0];
        endDate = customEndDate
          ? new Date(customEndDate).toISOString().split('T')[0]
          : startDate;
        break;
    }

    console.log(`📊 Generating ${type} report from ${startDate} to ${endDate}`);

    const startDateTime = new Date(startDate + 'T00:00:00.000Z');
    const endDateTime = new Date(endDate + 'T23:59:59.999Z');

    // ── 1. ORIGINAL: Build Query for roster trips ────────────────────────────
    const rosterQuery = {
      driverId: driverMongoId,
      scheduledDate: { $gte: startDate, $lte: endDate }
    };

    const rosterTrips = await db.collection('roster-assigned-trips')
      .find(rosterQuery)
      .toArray();

    // ── 2. ORIGINAL: Build Query for individual trips (trips collection) ─────
    const manualQuery = {
      ...buildStringDriverFilter(driverMongoId),
      $or: [
        { scheduledPickupTime: { $gte: startDateTime, $lte: endDateTime } },
        { actualStartTime: { $gte: startDateTime, $lte: endDateTime } }
      ]
    };

    const manualTrips = await db.collection('trips')
      .find(manualQuery)
      .toArray();

    // ── 3. ✅ NEW: client_created_trips ───────────────────────────────────────
    let clientTrips = [];
    try {
      const clientQuery = {
        ...buildStringDriverFilter(driverMongoId),
        $or: [
          { scheduledPickupTime: { $gte: startDateTime, $lte: endDateTime } },
          { actualStartTime: { $gte: startDateTime, $lte: endDateTime } }
        ]
      };

      clientTrips = await db.collection('client_created_trips')
        .find(clientQuery)
        .toArray();

      // Normalise clientName → customerName
      clientTrips = clientTrips.map(t => ({
        ...t,
        customerName: t.clientName || t.customerName || 'Unknown Client',
        customerPhone: t.clientPhone || t.customerPhone || '',
        _source: 'client_created_trips',
      }));

      console.log(`   ✅ Client trips: ${clientTrips.length}`);
    } catch (e) {
      console.error('   ⚠️  client_created_trips query failed:', e.message);
    }

    // ✅ Combine all trips
    const trips = [...rosterTrips, ...manualTrips, ...clientTrips];

    console.log(`   Found ${trips.length} trips (${rosterTrips.length} roster + ${manualTrips.length} manual + ${clientTrips.length} client)`);

    const completedTrips = trips.filter(t => t.status === 'completed');

    // ✅ Calculations
    const totalDistance = completedTrips.reduce((sum, t) => {
      const distance = Number(t.totalDistance) || Number(t.actualDistance) || Number(t.distance) || 0;
      return sum + distance;
    }, 0);

    // ✅ Get average rating from driver_feedback
    const feedbackStats = await db.collection('driver_feedback').aggregate([
      {
        $match: {
          driverId: driverMongoId,
          feedbackType: 'driver_trip_feedback',
          submittedAt: {
            $gte: new Date(startDate),
            $lte: new Date(endDate + 'T23:59:59.999Z')
          }
        }
      },
      {
        $group: {
          _id: null,
          avgRating: { $avg: '$rating' },
          totalFeedback: { $sum: 1 }
        }
      }
    ]).toArray();

    const avgRating = feedbackStats.length > 0
      ? parseFloat(feedbackStats[0].avgRating.toFixed(2))
      : 0;

    // ✅ Calculate working hours
    let totalWorkingMinutes = 0;
    completedTrips.forEach(trip => {
      if (trip.actualStartTime && trip.actualEndTime) {
        const minutes = (new Date(trip.actualEndTime) - new Date(trip.actualStartTime)) / (1000 * 60);
        totalWorkingMinutes += minutes;
      }
    });

    // ✅ Create Report Object with TRIP DETAILS (all 3 sources)
    const report = {
      driverEmail: driverEmail,
      driverId: driver.driverId,
      driverName: driver.personalInfo?.name || driver.name || 'Unknown',
      reportType: type,
      generatedAt: new Date(),
      period: { startDate, endDate },
      summary: {
        totalTrips: trips.length,
        completedTrips: completedTrips.length,
        scheduledTrips: trips.filter(t => ['assigned', 'started', 'in_progress', 'accepted'].includes(t.status)).length,
        cancelledTrips: trips.filter(t => t.status === 'cancelled').length,
        totalDistance: parseFloat(totalDistance.toFixed(2)),
        avgRating: avgRating,
        workingHours: parseFloat((totalWorkingMinutes / 60).toFixed(2))
      },
      trips: trips.map(t => {
        // ✅ Extract customer names (handle all 3 trip types)
        let customerNames = 'N/A';

        if (t.stops && Array.isArray(t.stops)) {
          // Roster trip with stops
          customerNames = t.stops
            .filter(stop => stop.type === 'pickup' && stop.customer && stop.customer.name)
            .map(stop => stop.customer.name)
            .join(', ');
        } else if (t.clientName) {
          // Client trip
          customerNames = t.clientName;
        } else if (t.customer && t.customer.name) {
          // Manual trip with customer object
          customerNames = t.customer.name;
        } else if (t.customerName) {
          // Already normalised
          customerNames = t.customerName;
        }

        if (!customerNames || customerNames.trim() === '') {
          customerNames = 'N/A';
        }

        const distance = Number(t.totalDistance) || Number(t.actualDistance) || Number(t.distance) || 0;
        const tripNumber = t.tripNumber || t.tripGroupId || `TRIP-${t._id.toString().slice(-8)}`;

        return {
          tripNumber: tripNumber,
          date: t.scheduledDate || (t.actualStartTime ? new Date(t.actualStartTime).toISOString().split('T')[0] : 'N/A'),
          startTime: t.actualStartTime ? new Date(t.actualStartTime).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }) : 'N/A',
          endTime: t.actualEndTime ? new Date(t.actualEndTime).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }) : 'N/A',
          status: t.status,
          distance: distance.toFixed(2),
          customerNames: customerNames,
          tripType: t.stops ? 'roster' : (t.clientName ? 'client' : 'individual'),
        };
      })
    };

    // Save
    const result = await db.collection('driver_reports').insertOne(report);

    console.log(`✅ Report generated: ${result.insertedId}`);

    res.json({
      status: 'success',
      message: 'Report generated successfully',
      data: {
        reportId: result.insertedId,
        report
      }
    });

  } catch (error) {
    console.error('❌ Error generating report:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// ============================================================================
// GET /api/driver/reports/history
// (original code preserved unchanged)
// ============================================================================
router.get('/history', async (req, res) => {
  try {
    const jwtUser = req.user;
    const db = req.db;
    const { type, limit = 10 } = req.query;

    if (!jwtUser || !jwtUser.email) {
      return res.status(401).json({
        status: 'error',
        message: 'Unauthorized'
      });
    }

    const query = { driverEmail: jwtUser.email };
    if (type) query.reportType = type;

    const reports = await db.collection('driver_reports')
      .find(query)
      .sort({ generatedAt: -1 })
      .limit(parseInt(limit))
      .toArray();

    res.json({
      status: 'success',
      data: reports.map(r => ({
        id: r._id,
        type: r.reportType,
        generatedAt: r.generatedAt,
        period: r.period,
        summary: r.summary
      }))
    });

  } catch (error) {
    console.error('❌ Error fetching history:', error);
    res.status(500).json({
      status: 'error',
      message: error.message
    });
  }
});

// ============================================================================
// GET /api/driver/reports/download/:reportId
// ✅ PDF generation — works with combined data from all 3 sources
//    tripType label now shows 'roster', 'client', or 'individual'
// ============================================================================
router.get('/download/:reportId', async (req, res) => {
  try {
    const { reportId } = req.params;
    const db = req.db;

    if (!ObjectId.isValid(reportId)) {
      return res.status(400).json({
        status: 'error',
        message: 'Invalid Report ID'
      });
    }

    const report = await db.collection('driver_reports').findOne({
      _id: new ObjectId(reportId)
    });

    if (!report) {
      return res.status(404).json({
        status: 'error',
        message: 'Report not found'
      });
    }

    // PDF Generation
    const doc = new PDFDocument({ margin: 50 });

    const filename = `Report-${report.reportType}-${new Date(report.generatedAt).toISOString().split('T')[0]}.pdf`;
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${filename}"`);

    doc.pipe(res);

    // ============================================================================
    // LOGO SECTION (TOP LEFT) — original logic preserved
    // ============================================================================
    const logoPath = getLogoPath();
    let logoLoaded = false;

    if (logoPath) {
      try {
        doc.image(logoPath, 40, 35, {
          width: 120,
          height: 60,
          fit: [120, 60]
        });
        logoLoaded = true;
        console.log('✅ Logo added to driver report PDF');
      } catch (logoError) {
        console.error('❌ Error loading logo in PDF:', logoError.message);
      }
    }

    // Text fallback if logo not loaded
    if (!logoLoaded) {
      doc.fontSize(18)
        .fillColor('#0066CC')
        .text('ABRA Travels', 40, 35);
      doc.fontSize(8)
        .fillColor('#666666')
        .text('YOUR JOURNEY, OUR COMMITMENT', 40, 58);
    }

    // Move to header position (after logo)
    doc.moveDown(3);

    // Header
    doc.fontSize(20).fillColor('#000000').text(`Driver Report: ${report.reportType.toUpperCase()}`, { align: 'center' });
    doc.moveDown();
    doc.fontSize(12)
      .text(`Generated on: ${new Date(report.generatedAt).toUTCString()}`)
      .text(`Driver: ${report.driverName} (${report.driverEmail})`)
      .text(`Period: ${report.period.startDate} to ${report.period.endDate}`);
    doc.moveDown(2);

    // Summary
    doc.fontSize(16).text('Summary', { underline: true });
    doc.moveDown();
    doc.fontSize(12)
      .text(`Total Trips: ${report.summary.totalTrips}`)
      .text(`Completed Trips: ${report.summary.completedTrips}`)
      .text(`Scheduled Trips: ${report.summary.scheduledTrips}`)
      .text(`Total Distance: ${report.summary.totalDistance} KM`)
      .text(`Average Rating: ${report.summary.avgRating}/5.0`)
      .text(`Working Hours: ${report.summary.workingHours}`);

    doc.moveDown(2);

    // ✅ Trip Details Table
    doc.fontSize(16).text('Trip Details', { underline: true });
    doc.moveDown();

    if (report.trips && report.trips.length > 0) {
      doc.fontSize(9);

      // Table Header with better spacing
      const tableTop = doc.y;
      const col1 = 50;   // Trip #
      const col2 = 140;  // Date
      const col3 = 225;  // Time
      const col4 = 310;  // Customers
      const col5 = 470;  // Distance
      const col6 = 510;  // Type (NEW)

      // Header row
      doc.font('Helvetica-Bold');
      doc.text('Trip #', col1, tableTop, { width: 85, align: 'left' });
      doc.text('Date', col2, tableTop, { width: 75, align: 'left' });
      doc.text('Time', col3, tableTop, { width: 75, align: 'left' });
      doc.text('Customer', col4, tableTop, { width: 150, align: 'left' });
      doc.text('Dist (km)', col5, tableTop, { width: 45, align: 'right' });
      doc.text('Type', col6, tableTop, { width: 40, align: 'left' });

      // Draw line under header
      doc.moveTo(col1, tableTop + 15)
        .lineTo(545, tableTop + 15)
        .stroke();

      doc.moveDown(1.5);

      // Table Rows
      doc.font('Helvetica');
      report.trips.forEach((trip, index) => {
        const y = doc.y;

        // Ensure we don't overflow the page
        if (y > 700) {
          doc.addPage();
          doc.y = 50;
        }

        const currentY = doc.y;

        doc.text(trip.tripNumber || 'N/A', col1, currentY, { width: 85, align: 'left' });
        doc.text(trip.date || 'N/A', col2, currentY, { width: 75, align: 'left' });

        const timeStr = trip.startTime && trip.endTime
          ? `${trip.startTime}-${trip.endTime}`
          : 'N/A';
        doc.text(timeStr, col3, currentY, { width: 75, align: 'left' });

        const customerStr = trip.customerNames
          ? (trip.customerNames.length > 30 ? trip.customerNames.substring(0, 30) + '...' : trip.customerNames)
          : 'N/A';
        doc.text(customerStr, col4, currentY, { width: 150, align: 'left' });

        doc.text(trip.distance ? trip.distance.toString() : '0', col5, currentY, { width: 45, align: 'right' });

        // ✅ Show trip type (roster / client / individual)
        const typeLabel = trip.tripType === 'client' ? 'Client' : (trip.tripType === 'roster' ? 'Roster' : 'Admin');
        doc.text(typeLabel, col6, currentY, { width: 40, align: 'left' });

        doc.moveDown(1);

        // Draw light separator line between rows
        if (index < report.trips.length - 1) {
          const lineY = doc.y - 5;
          doc.moveTo(col1, lineY)
            .lineTo(545, lineY)
            .strokeOpacity(0.2)
            .stroke()
            .strokeOpacity(1);
        }
      });
    } else {
      doc.fontSize(10).text('No trips found for this period.', { align: 'center' });
    }

    doc.end();

  } catch (error) {
    console.error('Error downloading report:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to download report',
      error: error.message
    });
  }
});

module.exports = router;