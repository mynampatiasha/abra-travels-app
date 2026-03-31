// routes/admin_live_location_whole_vehicles.js
// ============================================================================
// ADMIN LIVE VEHICLE TRACKING ROUTER - Complete Fleet Monitoring System
// ============================================================================
// Features:
// ✅ Real-time vehicle positions (10-second polling)
// ✅ 6-day location history with playback
// ✅ Company filtering (optional manual selection)
// ✅ Vehicle offline alerts (>5 min no GPS)
// ✅ Route deviation alerts (>500m off route)
// ✅ Speed alerts (>80 km/h)
// ✅ FCM notifications to all admins
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const liveTrackingService = require('../services/admin_live_tracking_service');

// ============================================================================
// @route   GET /api/admin/live-tracking/vehicles
// @desc    Get all live vehicles with current positions (POLLING ENDPOINT)
// @access  Private (Any authenticated user)
// ============================================================================
router.get('/vehicles', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📍 ADMIN LIVE TRACKING - FETCH VEHICLES');
    console.log('='.repeat(80));
    
    const { date, status, company } = req.query;
    const userEmail = req.user.email;
    
    console.log(`👤 Accessed by: ${userEmail}`);
    console.log(`📅 Date: ${date || 'today'}`);
    console.log(`📊 Status filter: ${status || 'all'}`);
    console.log(`🏢 Company filter: ${company || 'all'}`);
    
    // ========================================================================
    // STEP 1: Determine date to query
    // ========================================================================
    const queryDate = date || new Date().toISOString().split('T')[0];
    console.log(`🔍 Querying date: ${queryDate}`);
    
    // ========================================================================
    // STEP 2: Build status filter
    // ========================================================================
    let statusFilter = { $in: ['started', 'in_progress'] };
    
    if (status) {
      switch (status.toLowerCase()) {
        case 'active':
          statusFilter = { $in: ['started', 'in_progress'] };
          break;
        case 'idle':
          // Vehicles that are started but haven't moved in 10+ minutes
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
    // STEP 3: Fetch live vehicles from service
    // ========================================================================
    const vehicles = await liveTrackingService.fetchLiveVehicles(
      req.db,
      queryDate,
      statusFilter,
      company
    );
    
    console.log(`✅ Found ${vehicles.length} vehicle(s)`);
    
    // ========================================================================
    // STEP 4: Check for alerts (offline, route deviation, speed)
    // ========================================================================
    console.log('\n🔍 Checking for vehicle alerts...');
    
    const alerts = await liveTrackingService.checkVehicleAlerts(
      req.db,
      vehicles
    );
    
    if (alerts.offline.length > 0) {
      console.log(`⚠️  ${alerts.offline.length} vehicle(s) offline`);
    }
    if (alerts.routeDeviation.length > 0) {
      console.log(`⚠️  ${alerts.routeDeviation.length} vehicle(s) off route`);
    }
    if (alerts.speeding.length > 0) {
      console.log(`⚠️  ${alerts.speeding.length} vehicle(s) speeding`);
    }
    
    console.log('='.repeat(80) + '\n');
    
    // ========================================================================
    // STEP 5: Return response
    // ========================================================================
    res.json({
      success: true,
      message: `Found ${vehicles.length} vehicle(s)`,
      data: {
        vehicles: vehicles,
        alerts: alerts,
        filters: {
          date: queryDate,
          status: status || 'active',
          company: company || 'all'
        },
        summary: {
          total: vehicles.length,
          active: vehicles.filter(v => ['started', 'in_progress'].includes(v.status)).length,
          idle: vehicles.filter(v => v.status === 'started' && v.isIdle).length,
          completed: vehicles.filter(v => v.status === 'completed').length,
          offline: alerts.offline.length,
          offRoute: alerts.routeDeviation.length,
          speeding: alerts.speeding.length
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching live vehicles:', error);
    console.error('Stack:', error.stack);
    
    res.status(500).json({
      success: false,
      message: 'Failed to fetch live vehicles',
      error: error.message
    });
  }
});

// // ============================================================================
// // @route   GET /api/admin/live-tracking/vehicle/:vehicleId
// // @desc    Get detailed information for a specific vehicle
// // @access  Private (Any authenticated user)
// // ============================================================================
// router.get('/vehicle/:vehicleId', verifyToken, async (req, res) => {
//   try {
//     console.log('\n' + '='.repeat(80));
//     console.log('🚗 ADMIN LIVE TRACKING - VEHICLE DETAILS');
//     console.log('='.repeat(80));
    
//     const { vehicleId } = req.params;
//     const { date } = req.query;
    
//     console.log(`🚗 Vehicle ID: ${vehicleId}`);
//     console.log(`📅 Date: ${date || 'today'}`);
    
//     // Validate vehicleId
//     if (!ObjectId.isValid(vehicleId)) {
//       return res.status(400).json({
//         success: false,
//         message: 'Invalid vehicle ID format'
//       });
//     }
    
//     const queryDate = date || new Date().toISOString().split('T')[0];
    
//     // ========================================================================
//     // STEP 1: Fetch vehicle details
//     // ========================================================================
//     const vehicleDetails = await liveTrackingService.fetchVehicleDetails(
//       req.db,
//       vehicleId,
//       queryDate
//     );
    
//     if (!vehicleDetails) {
//       return res.status(404).json({
//         success: false,
//         message: 'Vehicle not found or no active trip for this date'
//       });
//     }
    
//     console.log(`✅ Vehicle: ${vehicleDetails.vehicleNumber}`);
//     console.log(`   Trip: ${vehicleDetails.tripGroupId}`);
//     console.log(`   Status: ${vehicleDetails.status}`);
//     console.log(`   Stops: ${vehicleDetails.stops.length}`);
//     console.log(`   Current location: ${vehicleDetails.currentLocation ? 'Yes' : 'No'}`);
    
//     console.log('='.repeat(80) + '\n');
    
//     res.json({
//       success: true,
//       message: 'Vehicle details retrieved',
//       data: vehicleDetails
//     });
    
//   } catch (error) {
//     console.error('❌ Error fetching vehicle details:', error);
    
//     res.status(500).json({
//       success: false,
//       message: 'Failed to fetch vehicle details',
//       error: error.message
//     });
//   }
// });

// ============================================================================
// FIX 2: In routes/admin_live_location_whole_vehicles.js
// ADD this new route BEFORE the existing /vehicle/:vehicleId route.
// This fetches by tripId directly — returns the EXACT trip the map card shows.
// ============================================================================

// @route   GET /api/admin/live-tracking/trip/:tripId
// @desc    Get details for a specific trip by its _id (searches all 3 collections)
// @access  Private
router.get('/trip/:tripId', verifyToken, async (req, res) => {
  try {
    const { tripId } = req.params;

    if (!ObjectId.isValid(tripId)) {
      return res.status(400).json({ success: false, message: 'Invalid trip ID' });
    }

    const tripDetails = await liveTrackingService.fetchTripById(req.db, tripId);

    if (!tripDetails) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found in any collection'
      });
    }

    console.log(`✅ Trip details: ${tripDetails.tripNumber} | source: ${tripDetails.source} | status: ${tripDetails.status}`);

    res.json({
      success: true,
      message: 'Trip details retrieved',
      data: tripDetails
    });

  } catch (error) {
    console.error('❌ Error fetching trip details:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch trip details',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/live-tracking/history
// @desc    Get historical location data for playback ("Show me 10 AM" feature)
// @access  Private (Any authenticated user)
// ============================================================================
router.get('/history', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('⏰ ADMIN LIVE TRACKING - HISTORICAL PLAYBACK');
    console.log('='.repeat(80));
    
    const { vehicleId, date, time } = req.query;
    
    console.log(`🚗 Vehicle ID: ${vehicleId}`);
    console.log(`📅 Date: ${date}`);
    console.log(`🕐 Time: ${time || 'all'}`);
    
    // ========================================================================
    // STEP 1: Validate required parameters
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
    
    // ========================================================================
    // STEP 2: Fetch from 6-day location archive
    // ========================================================================
    const history = await liveTrackingService.fetchLocationHistory(
      req.db,
      vehicleId,
      date,
      time
    );
    
    if (!history || history.locations.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'No location history found for this date/time'
      });
    }
    
    console.log(`✅ Found ${history.locations.length} location point(s)`);
    
    if (time) {
      console.log(`   Filtered to time: ${time}`);
    }
    
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Location history retrieved',
      data: {
        vehicleId: vehicleId,
        date: date,
        time: time || 'all',
        locations: history.locations,
        summary: {
          totalPoints: history.locations.length,
          firstPoint: history.locations[0],
          lastPoint: history.locations[history.locations.length - 1],
          timeRange: {
            start: history.locations[0]?.timestamp,
            end: history.locations[history.locations.length - 1]?.timestamp
          }
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

// ============================================================================
// @route   GET /api/admin/live-tracking/stats
// @desc    Get overall fleet statistics
// @access  Private (Any authenticated user)
// ============================================================================
router.get('/stats', verifyToken, async (req, res) => {
  try {
    const { date } = req.query;
    const queryDate = date || new Date().toISOString().split('T')[0];
    
    const stats = await liveTrackingService.getFleetStatistics(
      req.db,
      queryDate
    );
    
    res.json({
      success: true,
      message: 'Fleet statistics retrieved',
      data: stats
    });
    
  } catch (error) {
    console.error('❌ Error fetching fleet stats:', error);
    
    res.status(500).json({
      success: false,
      message: 'Failed to fetch fleet statistics',
      error: error.message
    });
  }
});

module.exports = router;