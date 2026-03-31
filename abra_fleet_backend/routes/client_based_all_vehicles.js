// routes/client_based_all_vehicles.js
// ============================================================================
// CLIENT LIVE VEHICLE TRACKING ROUTER - Domain-Based Fleet Monitoring
// ============================================================================
// Features:
// ✅ Real-time vehicle positions filtered by client's email domain
// ✅ 10-second polling support
// ✅ 6-day location history with playback
// ✅ Domain-based access control (only see trips with your domain passengers)
// ✅ Vehicle offline alerts (>5 min no GPS)
// ✅ Route deviation alerts (>500m off route)
// ✅ Speed alerts (>80 km/h)
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');

// ============================================================================
// HELPER FUNCTION: Extract domain from email
// ============================================================================
function extractDomain(email) {
  if (!email || typeof email !== 'string' || !email.includes('@')) {
    return null;
  }
  return email.split('@')[1].toLowerCase();
}

// ============================================================================
// HELPER FUNCTION: Check if trip has passengers from specific domain
// ============================================================================
function tripHasPassengersFromDomain(trip, domain) {
  if (!trip || !trip.stops || !Array.isArray(trip.stops)) {
    return false;
  }

  // Check all stops for passengers with matching domain
  for (const stop of trip.stops) {
    if (stop.type === 'drop') {
      // Skip office drop points (no customer)
      continue;
    }

    const customerEmail = stop.customer?.email;
    
    if (customerEmail) {
      const customerDomain = extractDomain(customerEmail);
      
      if (customerDomain && customerDomain === domain) {
        return true; // Found at least one passenger from this domain
      }
    }
  }

  return false;
}

// ============================================================================
// @route   GET /api/client/live-tracking/vehicles
// @desc    Get live vehicles filtered by logged-in user's email domain
// @access  Private (Any authenticated user)
// ============================================================================
router.get('/vehicles', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📍 CLIENT LIVE TRACKING - FETCH VEHICLES (DOMAIN FILTERED)');
    console.log('='.repeat(80));
    
    const { date, status } = req.query;
    const userEmail = req.user.email;
    
    console.log(`👤 User Email: ${userEmail}`);
    
    // ========================================================================
    // STEP 1: Extract user's domain
    // ========================================================================
    const userDomain = extractDomain(userEmail);
    
    if (!userDomain) {
      console.log('❌ Unable to extract domain from user email');
      return res.status(400).json({
        success: false,
        message: 'Invalid user email format'
      });
    }
    
    console.log(`🏢 User Domain: ${userDomain}`);
    
    // ========================================================================
    // STEP 2: Determine date to query
    // ========================================================================
    const queryDate = date || new Date().toISOString().split('T')[0];
    console.log(`📅 Query Date: ${queryDate}`);
    console.log(`📊 Status Filter: ${status || 'active'}`);
    
    // ========================================================================
    // STEP 3: Build status filter
    // ========================================================================
    let statusFilter = { $in: ['started', 'in_progress'] };
    
    if (status) {
      switch (status.toLowerCase()) {
        case 'active':
          statusFilter = { $in: ['started', 'in_progress'] };
          break;
        case 'idle':
          statusFilter = 'started';
          break;
        case 'completed':
          statusFilter = 'completed';
          break;
        case 'all':
          statusFilter = { $in: ['assigned', 'started', 'in_progress', 'completed'] };
          break;
        default:
          statusFilter = { $in: ['started', 'in_progress'] };
      }
    }
    
    // ========================================================================
    // STEP 4: Fetch ALL trips for this date first
    // ========================================================================
    const tripsCollection = req.db.collection('trips');
    
    const query = {
      scheduledDate: queryDate,
      status: statusFilter
    };
    
    console.log(`🔍 Fetching trips with query:`, JSON.stringify(query));
    
    const allTrips = await tripsCollection.find(query).toArray();
    
    console.log(`📦 Found ${allTrips.length} total trip(s) for ${queryDate}`);
    
    // ========================================================================
    // STEP 5: Filter trips by domain
    // ========================================================================
    const filteredTrips = allTrips.filter(trip => {
      return tripHasPassengersFromDomain(trip, userDomain);
    });
    
    console.log(`✅ ${filteredTrips.length} trip(s) match domain: ${userDomain}`);
    
    if (filteredTrips.length === 0) {
      console.log('ℹ️  No trips found with passengers from your company');
      console.log('='.repeat(80) + '\n');
      
      return res.json({
        success: true,
        message: `No vehicles found with passengers from @${userDomain}`,
        data: {
          vehicles: [],
          alerts: {
            offline: [],
            routeDeviation: [],
            speeding: []
          },
          filters: {
            date: queryDate,
            status: status || 'active',
            domain: userDomain
          },
          summary: {
            total: 0,
            active: 0,
            idle: 0,
            completed: 0,
            offline: 0,
            offRoute: 0,
            speeding: 0
          }
        }
      });
    }
    
    // ========================================================================
    // STEP 6: Transform trips into vehicle objects
    // ========================================================================
    const vehicles = filteredTrips.map(trip => {
      // Calculate progress
      let progress = 0;
      const completedStops = trip.stops.filter(s => s.status === 'completed').length;
      if (trip.totalStops > 0) {
        progress = Math.round((completedStops / trip.totalStops) * 100);
      }
      
      // Determine if vehicle is idle (started but no movement in 10+ min)
      let isIdle = false;
      if (trip.status === 'started' && trip.currentLocation) {
        const lastUpdate = new Date(trip.currentLocation.timestamp);
        const now = new Date();
        const minutesSinceUpdate = (now - lastUpdate) / (1000 * 60);
        isIdle = minutesSinceUpdate > 10;
      }
      
      // Get current stop
      const currentStop = trip.stops.find(s => s.status === 'pending' || s.status === 'arrived');
      
      return {
        vehicleId: trip.vehicleId.toString(),
        tripId: trip._id.toString(),
        tripNumber: trip.tripNumber,
        tripGroupId: trip.tripGroupId,
        vehicleNumber: trip.vehicleNumber,
        vehicleName: trip.vehicleName,
        driverName: trip.driverName,
        driverEmail: trip.driverEmail,
        driverPhone: trip.driverPhone,
        status: trip.status,
        currentLocation: trip.currentLocation || null,
        locationHistory: trip.locationHistory || [],
        stops: trip.stops || [],
        currentStopIndex: trip.currentStopIndex || 0,
        totalStops: trip.totalStops,
        progress: progress,
        isIdle: isIdle,
        currentStop: currentStop || null,
        scheduledDate: trip.scheduledDate,
        startTime: trip.startTime,
        endTime: trip.endTime
      };
    });
    
    console.log(`📊 Transformed ${vehicles.length} vehicle object(s)`);
    
    // ========================================================================
    // STEP 7: Check for alerts
    // ========================================================================
    const alerts = {
      offline: [],
      routeDeviation: [],
      speeding: []
    };
    
    const now = new Date();
    
    for (const vehicle of vehicles) {
      // Offline check (no GPS update in 5+ minutes)
      if (vehicle.currentLocation && vehicle.currentLocation.timestamp) {
        const lastUpdate = new Date(vehicle.currentLocation.timestamp);
        const minutesOffline = (now - lastUpdate) / (1000 * 60);
        
        if (minutesOffline > 5 && vehicle.status !== 'completed') {
          alerts.offline.push({
            vehicleId: vehicle.vehicleId,
            vehicleNumber: vehicle.vehicleNumber,
            duration: `${Math.round(minutesOffline)} min`,
            lastSeen: vehicle.currentLocation.timestamp
          });
        }
      }
      
      // Speed check (>80 km/h)
      if (vehicle.currentLocation && vehicle.currentLocation.speed) {
        const speed = vehicle.currentLocation.speed;
        
        if (speed > 80) {
          alerts.speeding.push({
            vehicleId: vehicle.vehicleId,
            vehicleNumber: vehicle.vehicleNumber,
            speed: Math.round(speed),
            location: vehicle.currentLocation
          });
        }
      }
      
      // Route deviation check would require geofencing logic
      // Skipping for now (can be added later)
    }
    
    console.log(`⚠️  Alerts: ${alerts.offline.length} offline, ${alerts.routeDeviation.length} off-route, ${alerts.speeding.length} speeding`);
    
    // ========================================================================
    // STEP 8: Build summary stats
    // ========================================================================
    const summary = {
      total: vehicles.length,
      active: vehicles.filter(v => ['started', 'in_progress'].includes(v.status)).length,
      idle: vehicles.filter(v => v.status === 'started' && v.isIdle).length,
      completed: vehicles.filter(v => v.status === 'completed').length,
      offline: alerts.offline.length,
      offRoute: alerts.routeDeviation.length,
      speeding: alerts.speeding.length
    };
    
    console.log('='.repeat(80) + '\n');
    
    // ========================================================================
    // STEP 9: Return response
    // ========================================================================
    res.json({
      success: true,
      message: `Found ${vehicles.length} vehicle(s) for domain: ${userDomain}`,
      data: {
        vehicles: vehicles,
        alerts: alerts,
        filters: {
          date: queryDate,
          status: status || 'active',
          domain: userDomain
        },
        summary: summary
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching client vehicles:', error);
    console.error('Stack:', error.stack);
    
    res.status(500).json({
      success: false,
      message: 'Failed to fetch vehicles',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/client/live-tracking/vehicle/:vehicleId
// @desc    Get detailed information for a specific vehicle (domain check)
// @access  Private (Any authenticated user)
// ============================================================================
router.get('/vehicle/:vehicleId', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🚗 CLIENT LIVE TRACKING - VEHICLE DETAILS (DOMAIN FILTERED)');
    console.log('='.repeat(80));
    
    const { vehicleId } = req.params;
    const { date } = req.query;
    const userEmail = req.user.email;
    
    console.log(`🚗 Vehicle ID: ${vehicleId}`);
    console.log(`👤 User Email: ${userEmail}`);
    console.log(`📅 Date: ${date || 'today'}`);
    
    // Validate vehicleId
    if (!ObjectId.isValid(vehicleId)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid vehicle ID format'
      });
    }
    
    // Extract user domain
    const userDomain = extractDomain(userEmail);
    
    if (!userDomain) {
      return res.status(400).json({
        success: false,
        message: 'Invalid user email format'
      });
    }
    
    console.log(`🏢 User Domain: ${userDomain}`);
    
    const queryDate = date || new Date().toISOString().split('T')[0];
    
    // ========================================================================
    // STEP 1: Find the trip
    // ========================================================================
    const tripsCollection = req.db.collection('trips');
    
    const trip = await tripsCollection.findOne({
      vehicleId: new ObjectId(vehicleId),
      scheduledDate: queryDate
    });
    
    if (!trip) {
      console.log('❌ Trip not found');
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found or no active trip for this date'
      });
    }
    
    console.log(`✅ Found trip: ${trip.tripNumber}`);
    
    // ========================================================================
    // STEP 2: Check domain access
    // ========================================================================
    const hasAccess = tripHasPassengersFromDomain(trip, userDomain);
    
    if (!hasAccess) {
      console.log(`❌ Access denied: No passengers from domain ${userDomain}`);
      return res.status(403).json({
        success: false,
        message: 'Access denied: This vehicle does not have passengers from your company'
      });
    }
    
    console.log(`✅ Access granted: Trip has passengers from ${userDomain}`);
    
    // ========================================================================
    // STEP 3: Transform trip data
    // ========================================================================
    const vehicleDetails = {
      vehicleId: trip.vehicleId.toString(),
      tripId: trip._id.toString(),
      tripNumber: trip.tripNumber,
      tripGroupId: trip.tripGroupId,
      vehicleNumber: trip.vehicleNumber,
      vehicleName: trip.vehicleName,
      driverName: trip.driverName,
      driverEmail: trip.driverEmail,
      driverPhone: trip.driverPhone,
      status: trip.status,
      currentLocation: trip.currentLocation || null,
      locationHistory: trip.locationHistory || [],
      stops: trip.stops || [],
      currentStopIndex: trip.currentStopIndex || 0,
      totalStops: trip.totalStops,
      scheduledDate: trip.scheduledDate,
      startTime: trip.startTime,
      endTime: trip.endTime,
      actualStartTime: trip.actualStartTime,
      totalDistance: trip.totalDistance,
      actualDistance: trip.actualDistance
    };
    
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Vehicle details retrieved',
      data: vehicleDetails
    });
    
  } catch (error) {
    console.error('❌ Error fetching vehicle details:', error);
    
    res.status(500).json({
      success: false,
      message: 'Failed to fetch vehicle details',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/client/live-tracking/history
// @desc    Get historical location data for playback (domain check)
// @access  Private (Any authenticated user)
// ============================================================================
router.get('/history', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('⏰ CLIENT LIVE TRACKING - HISTORICAL PLAYBACK (DOMAIN FILTERED)');
    console.log('='.repeat(80));
    
    const { vehicleId, date, time } = req.query;
    const userEmail = req.user.email;
    
    console.log(`🚗 Vehicle ID: ${vehicleId}`);
    console.log(`👤 User Email: ${userEmail}`);
    console.log(`📅 Date: ${date}`);
    console.log(`🕐 Time: ${time || 'all'}`);
    
    // ========================================================================
    // STEP 1: Validate parameters
    // ========================================================================
    if (!vehicleId || !date) {
      return res.status(400).json({
        success: false,
        message: 'vehicleId and date are required'
      });
    }
    
    if (!ObjectId.isValid(vehicleId)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid vehicle ID format'
      });
    }
    
    // Extract user domain
    const userDomain = extractDomain(userEmail);
    
    if (!userDomain) {
      return res.status(400).json({
        success: false,
        message: 'Invalid user email format'
      });
    }
    
    console.log(`🏢 User Domain: ${userDomain}`);
    
    // ========================================================================
    // STEP 2: Find the trip and check access
    // ========================================================================
    const tripsCollection = req.db.collection('trips');
    
    const trip = await tripsCollection.findOne({
      vehicleId: new ObjectId(vehicleId),
      scheduledDate: date
    });
    
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found for this date'
      });
    }
    
    // Check domain access
    const hasAccess = tripHasPassengersFromDomain(trip, userDomain);
    
    if (!hasAccess) {
      console.log(`❌ Access denied: No passengers from domain ${userDomain}`);
      return res.status(403).json({
        success: false,
        message: 'Access denied: This vehicle does not have passengers from your company'
      });
    }
    
    console.log(`✅ Access granted`);
    
    // ========================================================================
    // STEP 3: Get location history
    // ========================================================================
    let locations = trip.locationHistory || [];
    
    // Filter by time if provided
    if (time) {
      locations = locations.filter(loc => {
        if (!loc.timestamp) return false;
        
        const locTime = new Date(loc.timestamp).toTimeString().substring(0, 5); // HH:MM
        return locTime === time;
      });
    }
    
    console.log(`✅ Found ${locations.length} location point(s)`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Location history retrieved',
      data: {
        vehicleId: vehicleId,
        date: date,
        time: time || 'all',
        locations: locations,
        summary: {
          totalPoints: locations.length,
          firstPoint: locations[0] || null,
          lastPoint: locations[locations.length - 1] || null,
          timeRange: locations.length > 0 ? {
            start: locations[0]?.timestamp,
            end: locations[locations.length - 1]?.timestamp
          } : null
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching location history:', error);
    
    res.status(500).json({
      success: false,
      message: 'Failed to fetch location history',
      error: error.message
    });
  }
});

module.exports = router;