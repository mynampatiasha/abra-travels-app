// routes/client_live_tracking.js
// ============================================================================
// CLIENT LIVE VEHICLE TRACKING ROUTER
// ============================================================================
// Domain-based: Only shows trips belonging to the logged-in client's
// email domain (e.g. @abrafleet.com).
//
// Sources:
//   1. client_created_trips  — where clientEmail domain matches
//   2. roster-assigned-trips — where stops[].customer.email domain matches
//
// Visible statuses: assigned, accepted, started, in_progress
//
// ROUTES:
//   GET /api/client/live-tracking/vehicles          — main polling endpoint
//   GET /api/client/live-tracking/trip/:tripId      — single trip details
//   GET /api/client/live-tracking/history           — location history/playback
// ============================================================================

const express = require('express');
const router  = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const clientLiveTrackingService = require('../services/client_live_tracking_service');

// ============================================================================
// MIDDLEWARE: Ensure only clients can access these routes
// ============================================================================
function requireClientRole(req, res, next) {
  const role = req.user?.role;
  // Allow client, admin, super_admin (admin may preview client view)
  if (!role) {
    return res.status(401).json({ success: false, message: 'Unauthorized' });
  }
  if (!['client', 'admin', 'super_admin'].includes(role)) {
    return res.status(403).json({
      success: false,
      message: 'Access denied. Client role required.'
    });
  }
  next();
}

// ============================================================================
// @route   GET /api/client/live-tracking/vehicles
// @desc    Get live vehicles for client's domain (polling endpoint)
// @access  Private (Client)
// ============================================================================
router.get('/vehicles', verifyToken, requireClientRole, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📍 CLIENT LIVE TRACKING — FETCH VEHICLES');
    console.log('='.repeat(80));

    const clientEmail = req.user.email;
    const { date, status } = req.query;

    if (!clientEmail) {
      return res.status(401).json({
        success: false,
        message: 'Client email not found in token'
      });
    }

    // Extract domain for logging
    const domain = clientEmail.includes('@')
      ? clientEmail.split('@')[1]
      : 'unknown';

    const queryDate   = date   || new Date().toISOString().split('T')[0];
    const statusFilter = status || 'all';

    console.log(`👤 Client Email : ${clientEmail}`);
    console.log(`🏢 Domain       : ${domain}`);
    console.log(`📅 Date         : ${queryDate}`);
    console.log(`📊 Status filter: ${statusFilter}`);

    // ── Fetch vehicles for this domain ─────────────────────────────────────
    const { vehicles, summary } = await clientLiveTrackingService.fetchClientLiveVehicles(
      req.db,
      clientEmail,
      queryDate,
      statusFilter
    );

    console.log(`✅ Vehicles found: ${vehicles.length}`);
    console.log(`📊 Summary: total=${summary.total}, active=${summary.active}, assigned=${summary.assigned}, idle=${summary.idle}`);

    // ── Check alerts (only for started/in_progress vehicles) ───────────────
    const alerts = await clientLiveTrackingService.checkClientVehicleAlerts(vehicles);

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

    res.json({
      success: true,
      message: `Found ${vehicles.length} vehicle(s) for domain @${domain}`,
      data: {
        vehicles,
        summary,
        alerts,
        domain,
        clientEmail,
      },
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('❌ Error fetching client live vehicles:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch live vehicles',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/client/live-tracking/trip/:tripId
// @desc    Get details for a specific trip (verifies it belongs to client domain)
// @access  Private (Client)
// ============================================================================
router.get('/trip/:tripId', verifyToken, requireClientRole, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🚗 CLIENT LIVE TRACKING — TRIP DETAILS');
    console.log('='.repeat(80));

    const { tripId } = req.params;
    const clientEmail = req.user.email;

    console.log(`🆔 Trip ID    : ${tripId}`);
    console.log(`👤 Client     : ${clientEmail}`);

    if (!ObjectId.isValid(tripId)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid trip ID format'
      });
    }

    const tripDetails = await clientLiveTrackingService.fetchClientVehicleDetails(
      req.db,
      tripId,
      clientEmail
    );

    if (!tripDetails) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found or does not belong to your organisation'
      });
    }

    console.log(`✅ Trip: ${tripDetails.tripNumber} | source: ${tripDetails.source} | status: ${tripDetails.status}`);
    console.log('='.repeat(80) + '\n');

    res.json({
      success: true,
      message: 'Trip details retrieved',
      data: tripDetails
    });

  } catch (error) {
    console.error('❌ Error fetching client trip details:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch trip details',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/client/live-tracking/history
// @desc    Get location history for playback
// @access  Private (Client)
// ============================================================================
router.get('/history', verifyToken, requireClientRole, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('⏰ CLIENT LIVE TRACKING — LOCATION HISTORY');
    console.log('='.repeat(80));

    const { vehicleId, date, time } = req.query;
    const clientEmail = req.user.email;

    console.log(`🚗 Vehicle ID : ${vehicleId}`);
    console.log(`📅 Date       : ${date}`);
    console.log(`🕐 Time       : ${time || 'all'}`);
    console.log(`👤 Client     : ${clientEmail}`);

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

    const history = await clientLiveTrackingService.fetchClientLocationHistory(
      req.db,
      vehicleId,
      date,
      time,
      clientEmail
    );

    if (!history || history.locations.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'No location history found for this date/time'
      });
    }

    console.log(`✅ Found ${history.locations.length} location point(s)`);
    console.log('='.repeat(80) + '\n');

    res.json({
      success: true,
      message: 'Location history retrieved',
      data: {
        vehicleId,
        date,
        time: time || 'all',
        locations: history.locations,
        summary: {
          totalPoints: history.locations.length,
          firstPoint: history.locations[0],
          lastPoint:  history.locations[history.locations.length - 1],
          timeRange: {
            start: history.locations[0]?.timestamp,
            end:   history.locations[history.locations.length - 1]?.timestamp
          }
        }
      }
    });

  } catch (error) {
    console.error('❌ Error fetching client location history:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch location history',
      error: error.message
    });
  }
});

module.exports = router;