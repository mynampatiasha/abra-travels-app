// routes/admin_trip_management_chunk1.js
// ============================================================================
// ADMIN TRIP MANAGEMENT ROUTER — CHUNK 1 OF 2
// ============================================================================
// Contains:
//   - All requires / imports
//   - extractLocationParts() helper
//   - GET  /dashboard
//   - GET  /list
//
// HOW TO COMBINE:
//   Copy chunk1 content (everything except the last line: module.exports = router;)
//   then paste chunk2 content directly after it.
//   The combined file IS your final admin_trip_management.js
//
// ⚠️  ROUTE ORDER IS CRITICAL — static paths (/locations/*, /bulk-report,
//     /dashboard, /list) MUST come BEFORE wildcard /:tripId/* routes.
//     This split is arranged correctly: chunk1 = static, chunk2 = dynamic.
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const notificationService = require('../services/fcm_service');

// ============================================================================
// LOCATION HELPER - Extracts country/state/city from a stop's location
// ============================================================================
// Trip stops store location as: stop.location.address (free text)
// OR structured fields: stop.location.country, stop.location.state, stop.location.city
// This helper normalises both forms.
// ============================================================================

function extractLocationParts(locationObj) {
  if (!locationObj) return { country: null, state: null, city: null };

  // Prefer structured fields if present
  if (locationObj.country || locationObj.state || locationObj.city) {
    return {
      country: locationObj.country || null,
      state: locationObj.state || null,
      city: locationObj.city || null,
    };
  }

  // Fall back to parsing the free-text address
  // Typical Indian address: "123 Street, Koramangala, Bengaluru, Karnataka, India"
  const address = locationObj.address || '';
  const parts = address.split(',').map(p => p.trim()).filter(Boolean);

  if (parts.length >= 3) {
    return {
      city: parts[parts.length - 3] || null,
      state: parts[parts.length - 2] || null,
      country: parts[parts.length - 1] || null,
    };
  }

  return { country: null, state: null, city: null };
}

// ============================================================================
// @route   GET /api/admin/trips/dashboard
// @desc    Get dashboard summary with counts for all trip statuses
// @access  Private (Admin only)
// ============================================================================
router.get('/dashboard', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📊 ADMIN TRIP DASHBOARD - FETCHING SUMMARY');
    console.log('='.repeat(80));
    
    const { fromDate, toDate } = req.query;
    
    console.log(`👤 Admin: ${req.user.email || req.user.id}`);
    
    // ========================================================================
    // STEP 1: Build date filter - ✅ FIXED
    // ========================================================================
    const filter = {};
    
    if (fromDate || toDate) {
      filter.scheduledDate = {};
      
      if (fromDate) {
        filter.scheduledDate.$gte = fromDate;
        console.log(`📅 From Date: ${fromDate}`);
      }
      
      if (toDate) {
        filter.scheduledDate.$lte = toDate;
        console.log(`📅 To Date: ${toDate}`);
      }
    } else {
      console.log(`📅 Mode: ALL TRIPS (no date restriction)`);
    }
    
    console.log('🔍 Date Filter:', JSON.stringify(filter, null, 2));
    
    // Get all trips matching filter
    const allTrips = await req.db.collection('roster-assigned-trips').find(filter).toArray();
    
    console.log(`📦 Found ${allTrips.length} total trip(s)`);
    if (fromDate || toDate) {
      console.log(`   Date range: ${fromDate || 'beginning'} to ${toDate || 'future'}`);
    }
    
    // ========================================================================
    // STEP 2: Count by status - ✅ FIXED: Proper cancelled counting
    // ========================================================================
    const ongoing = allTrips.filter(t => 
      t.status === 'started' || t.status === 'in_progress'
    ).length;
    
    const scheduled = allTrips.filter(t => 
      t.status === 'assigned'
    ).length;
    
    const completed = allTrips.filter(t => 
      t.status === 'completed' || t.status === 'done' || t.status === 'finished'
    ).length;
    
    // ✅ CRITICAL FIX: Count trips with cancelled status OR any cancelled stop
    const cancelled = allTrips.filter(t => {
      const status = (t.status || '').toLowerCase();
      const isTripCancelled = status === 'cancelled' || status === 'canceled';
      
      // ✅ Check if ANY stop is cancelled (not ALL stops)
      const hasStops = t.stops && Array.isArray(t.stops) && t.stops.length > 0;
      const hasCancelledStops = hasStops && t.stops.some(s => {
        const stopStatus = (s.status || '').toLowerCase();
        return stopStatus === 'cancelled' || stopStatus === 'canceled';
      });
      
      const result = isTripCancelled || hasCancelledStops;
      
      if (result) {
        console.log(`   🔴 Cancelled trip: ${t.tripNumber}`);
        console.log(`      - Trip status: ${t.status}`);
        console.log(`      - Has cancelled stops: ${hasCancelledStops}`);
      }
      
      return result;
    }).length;
    
    // ========================================================================
    // STEP 3: Additional metrics
    // ========================================================================
    const totalVehicles = new Set(
      allTrips
        .map(t => t.vehicleId)
        .filter(id => id)
        .map(id => id.toString())
    ).size;
    
    const totalDrivers = new Set(
      allTrips
        .map(t => t.driverId)
        .filter(id => id)
        .map(id => id.toString())
    ).size;
    
    const uniqueCustomerEmails = new Set();
    allTrips.forEach(trip => {
      if (trip.stops && Array.isArray(trip.stops)) {
        trip.stops
          .filter(s => s.type === 'pickup' && s.customer?.email)
          .forEach(s => uniqueCustomerEmails.add(s.customer.email));
      }
    });
    const totalCustomers = uniqueCustomerEmails.size;
    
    console.log(`   📊 Unique customers: ${totalCustomers}`);
    
    // Get delayed trips (started but behind schedule)
    const now = new Date();
    const currentMinutes = now.getHours() * 60 + now.getMinutes();
    
    const delayed = allTrips.filter(trip => {
      if (trip.status !== 'started' && trip.status !== 'in_progress') return false;
      
      const estimatedEnd = trip.endTime || '00:00';
      const [hours, minutes] = estimatedEnd.split(':').map(Number);
      const estimatedMinutes = hours * 60 + minutes;
      
      return currentMinutes > estimatedMinutes;
    }).length;
    
    const summary = {
      ongoing: ongoing,
      scheduled: scheduled,
      completed: completed,
      cancelled: cancelled,
      total: allTrips.length,
      delayed: delayed,
      totalVehicles: totalVehicles,
      totalDrivers: totalDrivers,
      totalCustomers: totalCustomers,
      fromDate: fromDate || null,
      toDate: toDate || null
    };
    
    console.log('\n📊 DASHBOARD SUMMARY:');
    console.log(`   🟢 Ongoing: ${ongoing}`);
    console.log(`   🔵 Scheduled: ${scheduled}`);
    console.log(`   ⚫ Completed: ${completed}`);
    console.log(`   🔴 Cancelled: ${cancelled}`);
    console.log(`   🟡 Delayed: ${delayed}`);
    console.log(`   📊 Total: ${allTrips.length}`);
    console.log(`   🚗 Vehicles: ${totalVehicles}`);
    console.log(`   👨‍✈️ Drivers: ${totalDrivers}`);
    console.log(`   👥 Customers: ${totalCustomers}`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Dashboard summary retrieved',
      data: summary
    });
    
  } catch (error) {
    console.error('❌ Error fetching dashboard summary:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch dashboard summary',
      error: error.message
    });
  }
});


// ============================================================================
// @route   GET /api/client/trips/list
// @desc    Get filtered trips for CLIENT (auto-filtered by domain)
// @access  Private (Client only)
// ============================================================================
router.get('/list', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📋 CLIENT TRIP LIST - FETCHING FILTERED TRIPS');
    console.log('='.repeat(80));
    
    // ✅ EXTRACT DOMAIN FROM USER EMAIL
    const userEmail = req.user.email || '';
    const domain = userEmail.includes('@') 
      ? userEmail.split('@')[1].toLowerCase() 
      : '';
    
    if (!domain) {
      return res.status(400).json({
        success: false,
        message: 'Invalid user email - cannot determine domain'
      });
    }
    
    console.log(`🏢 Client Domain: ${domain}`);
    console.log(`👤 User Email: ${userEmail}`);
    
    const { 
      fromDate,
      toDate,
      status, 
      search,
      country,
      state,
      city,
      locationSearch,
      page = 1,
      limit = 20
    } = req.query;
    
    console.log(`📊 Status filter: ${status || 'all'}`);
    console.log(`🔍 Search: ${search || 'none'}`);
    console.log(`🌍 Location: country=${country || 'all'}, state=${state || 'all'}, city=${city || 'all'}`);
    console.log(`📄 Page: ${page}, Limit: ${limit}`);
    
    // ========================================================================
    // STEP 1: Build query filter with DOMAIN auto-filter
    // ========================================================================
    const filter = {
      // ✅ CRITICAL: Auto-filter by client domain
      'stops': {
        $elemMatch: {
          'customer.email': { 
            $regex: `@${domain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 
            $options: 'i' 
          }
        }
      }
    };
    
    // Date range
    if (fromDate || toDate) {
      filter.scheduledDate = {};
      if (fromDate) filter.scheduledDate.$gte = fromDate;
      if (toDate) filter.scheduledDate.$lte = toDate;
    }
    
    // Status filter
    if (status && status !== 'all') {
      if (status === 'ongoing') {
        filter.status = { $in: ['started', 'in_progress'] };
      } else if (status === 'scheduled') {
        filter.status = 'assigned';
      } else if (status === 'cancelled') {
        filter.$or = [
          { status: { $regex: /^cancel(l)?ed$/i } },
          { 'stops': { $elemMatch: { status: { $regex: /^cancel(l)?ed$/i } } } }
        ];
      } else if (status === 'completed') {
        filter.status = { $in: ['completed', 'done', 'finished'] };
      } else {
        filter.status = status;
      }
    }
    
    // Text search
    if (search) {
      const searchFilter = [
        { vehicleNumber: { $regex: search, $options: 'i' } },
        { driverName: { $regex: search, $options: 'i' } },
        { tripNumber: { $regex: search, $options: 'i' } }
      ];
      filter.$or = filter.$or ? [...(filter.$or), ...searchFilter] : searchFilter;
    }
    
    // Location filters
    if (country || state || city) {
      const stopMatchConditions = [];
      if (country) {
        stopMatchConditions.push({
          $or: [
            { 'stops.location.country': { $regex: country, $options: 'i' } },
            { 'stops.location.address': { $regex: country, $options: 'i' } },
          ]
        });
      }
      if (state) {
        stopMatchConditions.push({
          $or: [
            { 'stops.location.state': { $regex: state, $options: 'i' } },
            { 'stops.location.address': { $regex: state, $options: 'i' } },
          ]
        });
      }
      if (city) {
        stopMatchConditions.push({
          $or: [
            { 'stops.location.city': { $regex: city, $options: 'i' } },
            { 'stops.location.address': { $regex: city, $options: 'i' } },
          ]
        });
      }
      if (stopMatchConditions.length > 0) {
        filter.$and = stopMatchConditions;
      }
    }
    
    // Location search
    if (locationSearch) {
      const locationCondition = {
        stops: {
          $elemMatch: {
            $or: [
              { 'location.address': { $regex: locationSearch, $options: 'i' } },
              { 'location.city': { $regex: locationSearch, $options: 'i' } },
              { 'location.state': { $regex: locationSearch, $options: 'i' } },
              { 'location.country': { $regex: locationSearch, $options: 'i' } },
            ]
          }
        }
      };
      if (filter.$and) {
        filter.$and.push(locationCondition);
      } else {
        Object.assign(filter, locationCondition);
      }
    }
    
    console.log('🔍 Query filter:', JSON.stringify(filter, null, 2));
    
    // ========================================================================
    // STEP 2: Get total count
    // ========================================================================
    const totalCount = await req.db.collection('roster-assigned-trips').countDocuments(filter);
    
    // ========================================================================
    // STEP 3: Fetch trips
    // ========================================================================
    const skip = (parseInt(page) - 1) * parseInt(limit);
    const trips = await req.db.collection('roster-assigned-trips')
      .find(filter)
      .sort({ scheduledDate: -1, createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();
    
    console.log(`📦 Found ${trips.length} trip(s) for domain: ${domain}`);
    
    // ========================================================================
    // STEP 4: Enhance trip data (same as admin)
    // ========================================================================
    const enhancedTrips = trips.map(trip => {
      const totalStops = trip.stops?.length || 0;
      const completedStops = trip.stops?.filter(s => s.status === 'completed').length || 0;
      const cancelledStops = trip.stops?.filter(s => s.status === 'cancelled').length || 0;
      const progress = totalStops > 0 ? Math.round((completedStops / totalStops) * 100) : 0;
      const customerCount = trip.stops?.filter(s => s.type === 'pickup').length || 0;
      
      let displayStatus = trip.status;
      if (cancelledStops > 0 && cancelledStops === totalStops) {
        displayStatus = 'cancelled';
      }
      
      return {
        _id: trip._id,
        tripNumber: trip.tripNumber,
        tripGroupId: trip.tripGroupId,
        tripType: trip.tripType,
        vehicleId: trip.vehicleId,
        vehicleNumber: trip.vehicleNumber || 'Unknown',
        vehicleName: trip.vehicleName || '',
        driverId: trip.driverId,
        driverName: trip.driverName || 'Unknown Driver',
        driverPhone: trip.driverPhone || '',
        driverEmail: trip.driverEmail || '',
        scheduledDate: trip.scheduledDate,
        startTime: trip.startTime,
        endTime: trip.endTime,
        actualStartTime: trip.actualStartTime,
        actualEndTime: trip.actualEndTime,
        status: displayStatus,
        progress: progress,
        currentStopIndex: trip.currentStopIndex || 0,
        totalStops: totalStops,
        completedStops: completedStops,
        cancelledStops: cancelledStops,
        customerCount: customerCount,
        totalDistance: trip.totalDistance || 0,
        totalTime: trip.totalTime || 0,
        createdAt: trip.createdAt,
        updatedAt: trip.updatedAt
      };
    });
    
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: `Found ${trips.length} trip(s) for ${domain}`,
      data: {
        trips: enhancedTrips,
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total: totalCount,
          totalPages: Math.ceil(totalCount / parseInt(limit))
        },
        filters: {
          domain: domain, // Return domain for client info
          fromDate: fromDate || null,
          toDate: toDate || null,
          status: status || 'all',
          country: country || null,
          state: state || null,
          city: city || null,
          locationSearch: locationSearch || null,
          search: search || ''
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching client trip list:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch trip list',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/client/trips/dashboard
// @desc    Get dashboard summary for CLIENT (auto-filtered by domain)
// @access  Private (Client only)
// ============================================================================
router.get('/dashboard', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📊 CLIENT TRIP DASHBOARD - FETCHING SUMMARY');
    console.log('='.repeat(80));
    
    // ✅ EXTRACT DOMAIN
    const userEmail = req.user.email || '';
    const domain = userEmail.includes('@') 
      ? userEmail.split('@')[1].toLowerCase() 
      : '';
    
    if (!domain) {
      return res.status(400).json({
        success: false,
        message: 'Invalid user email - cannot determine domain'
      });
    }
    
    console.log(`🏢 Client Domain: ${domain}`);
    
    const { fromDate, toDate } = req.query;
    
    // Build filter with domain
    const filter = {
      'stops': {
        $elemMatch: {
          'customer.email': { 
            $regex: `@${domain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 
            $options: 'i' 
          }
        }
      }
    };
    
    if (fromDate || toDate) {
      filter.scheduledDate = {};
      if (fromDate) filter.scheduledDate.$gte = fromDate;
      if (toDate) filter.scheduledDate.$lte = toDate;
    }
    
    const allTrips = await req.db.collection('roster-assigned-trips').find(filter).toArray();
    
    console.log(`📦 Found ${allTrips.length} total trip(s) for domain: ${domain}`);
    
    // Count by status (same logic as admin)
    const ongoing = allTrips.filter(t => 
      t.status === 'started' || t.status === 'in_progress'
    ).length;
    
    const scheduled = allTrips.filter(t => 
      t.status === 'assigned'
    ).length;
    
    const completed = allTrips.filter(t => 
      t.status === 'completed' || t.status === 'done' || t.status === 'finished'
    ).length;
    
    const cancelled = allTrips.filter(t => {
      const status = (t.status || '').toLowerCase();
      const isTripCancelled = status === 'cancelled' || status === 'canceled';
      const hasStops = t.stops && Array.isArray(t.stops) && t.stops.length > 0;
      const hasCancelledStops = hasStops && t.stops.some(s => {
        const stopStatus = (s.status || '').toLowerCase();
        return stopStatus === 'cancelled' || stopStatus === 'canceled';
      });
      return isTripCancelled || hasCancelledStops;
    }).length;
    
    const totalVehicles = new Set(
      allTrips.map(t => t.vehicleId).filter(id => id).map(id => id.toString())
    ).size;
    
    const totalDrivers = new Set(
      allTrips.map(t => t.driverId).filter(id => id).map(id => id.toString())
    ).size;
    
    const uniqueCustomerEmails = new Set();
    allTrips.forEach(trip => {
      if (trip.stops && Array.isArray(trip.stops)) {
        trip.stops
          .filter(s => s.type === 'pickup' && s.customer?.email)
          .forEach(s => uniqueCustomerEmails.add(s.customer.email));
      }
    });
    const totalCustomers = uniqueCustomerEmails.size;
    
    const summary = {
      ongoing,
      scheduled,
      completed,
      cancelled,
      total: allTrips.length,
      delayed: 0,
      totalVehicles,
      totalDrivers,
      totalCustomers,
      fromDate: fromDate || null,
      toDate: toDate || null,
      domain: domain // Return domain info
    };
    
    console.log('\n📊 DASHBOARD SUMMARY:');
    console.log(`   🟢 Ongoing: ${ongoing}`);
    console.log(`   🔵 Scheduled: ${scheduled}`);
    console.log(`   ⚫ Completed: ${completed}`);
    console.log(`   🔴 Cancelled: ${cancelled}`);
    console.log(`   📊 Total: ${allTrips.length}`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Dashboard summary retrieved',
      data: summary
    });
    
  } catch (error) {
    console.error('❌ Error fetching client dashboard:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch dashboard summary',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/client/trips/:tripId/details
// @desc    Get trip details for CLIENT (domain-filtered)
// @access  Private (Client only)
// ============================================================================
router.get('/client/:tripId/details', verifyToken, async (req, res) => {
  try {
    // Extract client domain
    const userEmail = req.user.email || '';
    const domain = userEmail.includes('@') 
      ? userEmail.split('@')[1].toLowerCase() 
      : '';
    
    if (!domain) {
      return res.status(400).json({
        success: false,
        message: 'Invalid user email'
      });
    }
    
    const { tripId } = req.params;
    
    if (!ObjectId.isValid(tripId)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid trip ID format'
      });
    }
    
    // Fetch trip with domain filter
    const trip = await req.db.collection('roster-assigned-trips').findOne({
      _id: new ObjectId(tripId),
      'stops': {
        $elemMatch: {
          'customer.email': { 
            $regex: `@${domain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 
            $options: 'i' 
          }
        }
      }
    });
    
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found or access denied'
      });
    }
    
    // [... rest of the existing trip details code ...]
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
// @route   GET /api/client/trips/bulk-report
// @desc    Generate bulk report for CLIENT (auto-filtered by domain)
// @access  Private (Client only)
// ============================================================================
router.get('/bulk-report', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(70));
    console.log('📊 GENERATING CLIENT BULK TRIP REPORT');
    console.log('='.repeat(70));

    // ✅ EXTRACT DOMAIN
    const userEmail = req.user.email || '';
    const domain = userEmail.includes('@') 
      ? userEmail.split('@')[1].toLowerCase() 
      : '';
    
    if (!domain) {
      return res.status(400).json({
        success: false,
        message: 'Invalid user email'
      });
    }

    const { fromDate, toDate, status, country, state, city, locationSearch, search } = req.query;

    // Build filter (same as /list but for all trips)
    const filter = {
      'stops': {
        $elemMatch: {
          'customer.email': { 
            $regex: `@${domain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 
            $options: 'i' 
          }
        }
      }
    };
    
    if (fromDate || toDate) {
      filter.scheduledDate = {};
      if (fromDate) filter.scheduledDate.$gte = fromDate;
      if (toDate) filter.scheduledDate.$lte = toDate;
    }
    
    if (status && status !== 'all') {
      if (status === 'ongoing') filter.status = { $in: ['started', 'in_progress'] };
      else if (status === 'scheduled') filter.status = 'assigned';
      else if (status === 'cancelled') {
        filter.$or = [
          { status: { $regex: /^cancel(l)?ed$/i } },
          { stops: { $elemMatch: { status: { $regex: /^cancel(l)?ed$/i } } } }
        ];
      }
      else if (status === 'completed') filter.status = { $in: ['completed', 'done', 'finished'] };
      else filter.status = status;
    }
    
    // Add search, location filters (same as /list)...
    // (Copy the rest from admin bulk-report)

    const trips = await req.db.collection('roster-assigned-trips')
      .find(filter)
      .sort({ scheduledDate: -1, createdAt: -1 })
      .toArray();

    console.log(`📦 Found ${trips.length} trip(s) for report (domain: ${domain})`);

    // Enrich trips (same as admin)
    const enrichedTrips = await Promise.all(trips.map(async (trip) => {
      // ... (same enrichment logic as admin bulk-report)
      return {
        _id: trip._id,
        tripNumber: trip.tripNumber || 'N/A',
        // ... rest of fields
      };
    }));

    const summary = {
      total: enrichedTrips.length,
      // ... (calculate summary)
    };

    res.json({
      success: true,
      message: 'Bulk report data ready',
      data: {
        summary,
        trips: enrichedTrips,
        generatedAt: new Date().toISOString(),
        generatedBy: req.user.email || req.user.id,
        domain: domain,
        filterApplied: { fromDate, toDate, status, country, state, city, locationSearch, search },
      }
    });

  } catch (error) {
    console.error('❌ Error generating client bulk report:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});


// ============================================================================
// @route   GET /api/admin/trips/list
// @desc    Get filtered list of trips with pagination and location filters
// @access  Private (Admin only)
// ============================================================================
router.get('/list', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📋 ADMIN TRIP LIST - FETCHING FILTERED TRIPS');
    console.log('='.repeat(80));
    
    const { 
      fromDate,
      toDate,
      status, 
      company, 
      route, 
      search,
      country,
      state,
      city,
      locationSearch,
      domain,  // ✅ NEW: Domain filter parameter
      page = 1,
      limit = 20
    } = req.query;
    
    console.log(`📊 Status filter: ${status || 'all'}`);
    console.log(`🏢 Company filter: ${company || 'all'}`);
    console.log(`🛣️  Route filter: ${route || 'all'}`);
    console.log(`🔍 Search: ${search || 'none'}`);
    console.log(`🌍 Location filters: country=${country || 'all'}, state=${state || 'all'}, city=${city || 'all'}`);
    console.log(`📍 Location search: ${locationSearch || 'none'}`);
    console.log(`🏢 Domain filter: ${domain || 'none'}`);  // ✅ NEW
    console.log(`📄 Page: ${page}, Limit: ${limit}`);
    
    // ========================================================================
    // STEP 1: Build query filter - FIXED for cancelled + location + domain
    // ========================================================================
    const filter = {};
    
    // Date range filter
    if (fromDate || toDate) {
      filter.scheduledDate = {};
      
      if (fromDate) {
        filter.scheduledDate.$gte = fromDate;
        console.log(`📅 From: ${fromDate}`);
      }
      
      if (toDate) {
        filter.scheduledDate.$lte = toDate;
        console.log(`📅 To: ${toDate}`);
      }
    } else {
      console.log(`📅 Mode: ALL TRIPS (no date restriction)`);
    }
    
    // ✅ FIXED: Status filter - handle cancelled properly
    if (status && status !== 'all') {
      if (status === 'ongoing') {
        filter.status = { $in: ['started', 'in_progress'] };
      } else if (status === 'scheduled') {
        filter.status = 'assigned';
      } else if (status === 'cancelled') {
        // ✅ CRITICAL FIX: Match trips with cancelled status OR any cancelled stop
        filter.$or = [
          { status: { $regex: /^cancel(l)?ed$/i } },
          { 'stops': { $elemMatch: { status: { $regex: /^cancel(l)?ed$/i } } } }
        ];
        console.log('   🔍 Cancelled filter: Using OR + elemMatch for any cancelled stop');
      } else if (status === 'completed') {
        filter.status = { $in: ['completed', 'done', 'finished'] };
      } else {
        filter.status = status;
      }
    }
    
    // Company filter (legacy)
    if (company && company !== 'all') {
      filter['stops.customer.email'] = { $regex: `@${company}\\.`, $options: 'i' };
    }
    
    // Text search filter (vehicle number, driver name, trip number)
    if (search) {
      const searchFilter = [
        { vehicleNumber: { $regex: search, $options: 'i' } },
        { driverName: { $regex: search, $options: 'i' } },
        { tripNumber: { $regex: search, $options: 'i' } }
      ];
      filter.$or = filter.$or ? [...(filter.$or), ...searchFilter] : searchFilter;
    }
    
    // ✅ Location filter - structured (country / state / city)
    if (country || state || city) {
      const stopMatchConditions = [];

      if (country) {
        stopMatchConditions.push({
          $or: [
            { 'stops.location.country': { $regex: country, $options: 'i' } },
            { 'stops.location.address': { $regex: country, $options: 'i' } },
          ]
        });
      }
      if (state) {
        stopMatchConditions.push({
          $or: [
            { 'stops.location.state': { $regex: state, $options: 'i' } },
            { 'stops.location.address': { $regex: state, $options: 'i' } },
          ]
        });
      }
      if (city) {
        stopMatchConditions.push({
          $or: [
            { 'stops.location.city': { $regex: city, $options: 'i' } },
            { 'stops.location.address': { $regex: city, $options: 'i' } },
          ]
        });
      }

      if (stopMatchConditions.length > 0) {
        filter.$and = stopMatchConditions;
      }
    }

    // ✅ FINAL FIX: Location search - merge with existing filters properly
    if (locationSearch) {
      console.log(`🔍 Location search: ${locationSearch}`);
      
      // Create location search condition
      const locationCondition = {
        stops: {
          $elemMatch: {
            $or: [
              { 'location.address': { $regex: locationSearch, $options: 'i' } },
              { 'location.city': { $regex: locationSearch, $options: 'i' } },
              { 'location.state': { $regex: locationSearch, $options: 'i' } },
              { 'location.country': { $regex: locationSearch, $options: 'i' } },
            ]
          }
        }
      };
      
      // Merge with existing filters
      if (filter.$and) {
        filter.$and.push(locationCondition);
      } else {
        Object.assign(filter, locationCondition);
      }
    }

    // ✅ NEW: Domain/Company filter
    if (domain) {
      const cleanDomain = domain.toLowerCase().replace('@', '');
      console.log(`🏢 Domain filter: @${cleanDomain}`);
      
      // Add to existing $and conditions or create new one
      const domainCondition = {
        'stops': {
          $elemMatch: {
            'customer.email': { 
              $regex: `@${cleanDomain.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 
              $options: 'i' 
            }
          }
        }
      };
      
      if (filter.$and) {
        filter.$and.push(domainCondition);
      } else {
        filter.$and = [domainCondition];
      }
    }
    
    console.log('🔍 Query filter:', JSON.stringify(filter, null, 2));
    
    // ========================================================================
    // STEP 2: Get total count
    // ========================================================================
    const totalCount = await req.db.collection('roster-assigned-trips').countDocuments(filter);
    
    // ========================================================================
    // STEP 3: Fetch trips with pagination
    // ========================================================================
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const trips = await req.db.collection('roster-assigned-trips')
      .find(filter)
      .sort({ scheduledDate: -1, createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();
    
    console.log(`📦 Found ${trips.length} trip(s) (Total: ${totalCount})`);
    
    // ========================================================================
    // STEP 4: Enhance trip data
    // ========================================================================
    const enhancedTrips = trips.map(trip => {
      const totalStops = trip.stops?.length || 0;
      const currentStopIndex = trip.currentStopIndex || 0;
      const completedStops = trip.stops?.filter(s => s.status === 'completed').length || 0;
      const cancelledStops = trip.stops?.filter(s => s.status === 'cancelled').length || 0;
      const progress = totalStops > 0 ? Math.round((completedStops / totalStops) * 100) : 0;
      
      const customerCount = trip.stops?.filter(s => s.type === 'pickup').length || 0;
      
      let currentStop = null;
      if (trip.stops && currentStopIndex < trip.stops.length) {
        currentStop = trip.stops[currentStopIndex];
      }
      
      const now = new Date();
      const currentMinutes = now.getHours() * 60 + now.getMinutes();
      const estimatedEnd = trip.endTime || '00:00';
      const [hours, minutes] = estimatedEnd.split(':').map(Number);
      const estimatedMinutes = hours * 60 + minutes;
      const isDelayed = (trip.status === 'started' || trip.status === 'in_progress') && 
                       currentMinutes > estimatedMinutes;
      
      // ✅ FIXED: Determine actual status considering cancelled stops
      let displayStatus = trip.status;
      if (cancelledStops > 0 && cancelledStops === totalStops) {
        displayStatus = 'cancelled';
      }
      
      return {
        _id: trip._id,
        tripNumber: trip.tripNumber,
        tripGroupId: trip.tripGroupId,
        tripType: trip.tripType,
        
        vehicleId: trip.vehicleId,
        vehicleNumber: trip.vehicleNumber || 'Unknown',
        vehicleName: trip.vehicleName || '',
        driverId: trip.driverId,
        driverName: trip.driverName || 'Unknown Driver',
        driverPhone: trip.driverPhone || '',
        driverEmail: trip.driverEmail || '',
        
        scheduledDate: trip.scheduledDate,
        startTime: trip.startTime,
        endTime: trip.endTime,
        actualStartTime: trip.actualStartTime,
        actualEndTime: trip.actualEndTime,
        
        status: displayStatus,
        progress: progress,
        currentStopIndex: currentStopIndex,
        totalStops: totalStops,
        completedStops: completedStops,
        cancelledStops: cancelledStops,
        customerCount: customerCount,
        isDelayed: isDelayed,
        
        totalDistance: trip.totalDistance || 0,
        totalTime: trip.totalTime || 0,
        
        currentStop: currentStop ? {
          sequence: currentStop.sequence,
          type: currentStop.type,
          customerName: currentStop.customer?.name || 'Drop',
          address: currentStop.location?.address || '',
          estimatedTime: currentStop.estimatedTime
        } : null,
        
        createdAt: trip.createdAt,
        updatedAt: trip.updatedAt
      };
    });
    
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: `Found ${trips.length} trip(s)`,
      data: {
        trips: enhancedTrips,
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total: totalCount,
          totalPages: Math.ceil(totalCount / parseInt(limit))
        },
        filters: {
          fromDate: fromDate || null,
          toDate: toDate || null,
          status: status || 'all',
          company: company || 'all',
          route: route || 'all',
          country: country || null,
          state: state || null,
          city: city || null,
          locationSearch: locationSearch || null,
          domain: domain || null,  // ✅ NEW
          search: search || ''
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching trip list:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch trip list',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/trips/locations/countries
// @desc    Get distinct countries from all trip pickup/dropoff locations
// @access  Private (Admin)
// ============================================================================
router.get('/locations/countries', verifyToken, async (req, res) => {
  try {
    console.log('🌍 Fetching distinct countries from trips');

    const trips = await req.db.collection('roster-assigned-trips')
      .find({}, { projection: { stops: 1 } })
      .toArray();

    const countrySet = new Set();

    trips.forEach(trip => {
      if (!trip.stops || !Array.isArray(trip.stops)) return;
      trip.stops.forEach(stop => {
        if (!stop.location) return;
        
        // ✅ Method 1: Check structured country field first
        if (stop.location.country && stop.location.country.trim()) {
          countrySet.add(stop.location.country.trim());
        }
        
        // ✅ Method 2: Parse from address ONLY if structured field is missing
        else if (stop.location.address) {
          // Address format: "Street, Area, City, State, Country"
          // Example: "123 Main St, Koramangala, Bangalore, Karnataka, India"
          const parts = stop.location.address.split(',').map(p => p.trim()).filter(Boolean);
          
          // ✅ CRITICAL: Only take the LAST part as country (if 3+ parts)
          // This prevents "Bangalore" from being treated as country
          if (parts.length >= 3) {
            const lastPart = parts[parts.length - 1];
            
            // ✅ Additional validation: Common country names
            const validCountries = ['India', 'USA', 'United States', 'UK', 'United Kingdom', 'Canada', 'Australia'];
            const isLikelyCountry = validCountries.some(c => lastPart.toLowerCase().includes(c.toLowerCase())) || parts.length >= 5;
            
            if (isLikelyCountry && lastPart.trim()) {
              countrySet.add(lastPart.trim());
            }
          }
        }
      });
    });

    const countries = Array.from(countrySet).sort();
    console.log(`   Found ${countries.length} distinct countries: ${JSON.stringify(countries)}`);

    res.json({ success: true, data: countries });
  } catch (error) {
    console.error('❌ Error fetching countries:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

// ============================================================================
// @route   GET /api/admin/trips/locations/states?country=India
// @desc    Get distinct states for a given country
// @access  Private (Admin)
// ============================================================================
router.get('/locations/states', verifyToken, async (req, res) => {
  try {
    const { country } = req.query;
    if (!country) return res.status(400).json({ success: false, message: 'country is required' });

    console.log(`📍 Fetching states for country: ${country}`);

    const trips = await req.db.collection('roster-assigned-trips')
      .find({}, { projection: { stops: 1 } })
      .toArray();

    const stateSet = new Set();

    trips.forEach(trip => {
      if (!trip.stops || !Array.isArray(trip.stops)) return;
      trip.stops.forEach(stop => {
        const parts = extractLocationParts(stop.location);
        if (
          parts.country &&
          parts.country.toLowerCase() === country.toLowerCase() &&
          parts.state
        ) {
          stateSet.add(parts.state.trim());
        }
      });
    });

    const states = Array.from(stateSet).sort();
    console.log(`   Found ${states.length} state(s)`);

    res.json({ success: true, data: states });
  } catch (error) {
    console.error('❌ Error fetching states:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

// ============================================================================
// @route   GET /api/admin/trips/locations/cities?country=India&state=Karnataka
// @desc    Get distinct cities for a given country + state
// @access  Private (Admin)
// ============================================================================
router.get('/locations/cities', verifyToken, async (req, res) => {
  try {
    const { country, state } = req.query;
    if (!country || !state) {
      return res.status(400).json({ success: false, message: 'country and state are required' });
    }

    console.log(`🏙️  Fetching cities for ${state}, ${country}`);

    const trips = await req.db.collection('roster-assigned-trips')
      .find({}, { projection: { stops: 1 } })
      .toArray();

    const citySet = new Set();

    trips.forEach(trip => {
      if (!trip.stops || !Array.isArray(trip.stops)) return;
      trip.stops.forEach(stop => {
        const parts = extractLocationParts(stop.location);
        if (
          parts.country &&
          parts.country.toLowerCase() === country.toLowerCase() &&
          parts.state &&
          parts.state.toLowerCase() === state.toLowerCase() &&
          parts.city
        ) {
          citySet.add(parts.city.trim());
        }
      });
    });

    const cities = Array.from(citySet).sort();
    console.log(`   Found ${cities.length} city/cities`);

    res.json({ success: true, data: cities });
  } catch (error) {
    console.error('❌ Error fetching cities:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

// ============================================================================
// @route   GET /api/admin/trips/bulk-report
// @desc    Get all filtered trips with full details for PDF generation
// @access  Private (Admin)
// ============================================================================
router.get('/bulk-report', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(70));
    console.log('📊 GENERATING BULK TRIP REPORT');
    console.log('='.repeat(70));

    const { fromDate, toDate, status, country, state, city, locationSearch, search } = req.query;

    // ── Build same filter as /list ─────────────────────────────────────────
    const filter = {};
    if (fromDate || toDate) {
      filter.scheduledDate = {};
      if (fromDate) filter.scheduledDate.$gte = fromDate;
      if (toDate) filter.scheduledDate.$lte = toDate;
    }
    if (status && status !== 'all') {
      if (status === 'ongoing') filter.status = { $in: ['started', 'in_progress'] };
      else if (status === 'scheduled') filter.status = 'assigned';
      else if (status === 'cancelled') {
        filter.$or = [
          { status: { $regex: /^cancel(l)?ed$/i } },
          { stops: { $elemMatch: { status: { $regex: /^cancel(l)?ed$/i } } } }
        ];
      }
      else if (status === 'completed') filter.status = { $in: ['completed', 'done', 'finished'] };
      else filter.status = status;
    }
    if (search) {
      const sf = [
        { vehicleNumber: { $regex: search, $options: 'i' } },
        { driverName: { $regex: search, $options: 'i' } },
        { tripNumber: { $regex: search, $options: 'i' } },
      ];
      filter.$or = filter.$or ? [...(filter.$or), ...sf] : sf;
    }
    if (country || state || city) {
      const loc = [];
      if (country) loc.push({ $or: [{ 'stops.location.country': { $regex: country, $options: 'i' } }, { 'stops.location.address': { $regex: country, $options: 'i' } }] });
      if (state)   loc.push({ $or: [{ 'stops.location.state': { $regex: state, $options: 'i' } },   { 'stops.location.address': { $regex: state, $options: 'i' } }] });
      if (city)    loc.push({ $or: [{ 'stops.location.city': { $regex: city, $options: 'i' } },     { 'stops.location.address': { $regex: city, $options: 'i' } }] });
      if (loc.length) filter.$and = loc;
    }
    if (locationSearch) {
      const lf = { $or: [
        { 'stops.location.address': { $regex: locationSearch, $options: 'i' } },
        { 'stops.location.city': { $regex: locationSearch, $options: 'i' } },
        { 'stops.location.state': { $regex: locationSearch, $options: 'i' } },
      ]};
      filter.$and = filter.$and ? [...filter.$and, lf] : [lf];
    }

    // ── Fetch all matching trips (no pagination for report) ────────────────
    const trips = await req.db.collection('roster-assigned-trips')
      .find(filter)
      .sort({ scheduledDate: -1, createdAt: -1 })
      .toArray();

    console.log(`📦 Found ${trips.length} trip(s) for report`);

    // ── Enrich each trip with vehicle + driver details ─────────────────────
    const enrichedTrips = await Promise.all(trips.map(async (trip) => {
      // ── Vehicle: fetch from DB, fall back to trip fields ──────────────────
      let vehicleDoc = null;
      if (trip.vehicleId) {
        try {
          vehicleDoc = await req.db.collection('vehicles').findOne({
            _id: new ObjectId(trip.vehicleId)
          });
        } catch (_) {}
      }

      const vehicle = {
        _id: vehicleDoc?._id || trip.vehicleId,
        // ✅ ALWAYS use trip fields first (they are denormalised copies stored at trip creation)
        vehicleNumber: trip.vehicleNumber || vehicleDoc?.vehicleNumber || vehicleDoc?.registrationNumber || 'N/A',
        vehicleName: trip.vehicleName || vehicleDoc?.name || vehicleDoc?.vehicleName || 'N/A',
        registrationNumber: vehicleDoc?.registrationNumber || trip.vehicleNumber || 'N/A',
        manufacturer: vehicleDoc?.manufacturer || 'N/A',
        model: vehicleDoc?.model || 'N/A',
        capacity: vehicleDoc?.capacity?.toString() || 'N/A',
        fuelType: vehicleDoc?.fuelType || 'N/A',
      };

      // ── Driver: fetch from DB, fall back to trip fields ───────────────────
      let driverDoc = null;
      if (trip.driverId) {
        try {
          driverDoc = await req.db.collection('drivers').findOne({
            _id: new ObjectId(trip.driverId)
          });
        } catch (_) {}
      }

      const driver = {
        _id: driverDoc?._id || trip.driverId,
        // ✅ ALWAYS use trip fields first
        name: trip.driverName || driverDoc?.personalInfo?.name || driverDoc?.name || 'Unknown Driver',
        phone: trip.driverPhone || driverDoc?.personalInfo?.phone || driverDoc?.phone || 'N/A',
        email: trip.driverEmail || driverDoc?.personalInfo?.email || driverDoc?.email || 'N/A',
        licenseNumber: driverDoc?.licenseDetails?.licenseNumber || driverDoc?.licenseNumber || 'N/A',
        experience: driverDoc?.experience?.toString() || 'N/A',
      };

      // ── Feedback ──────────────────────────────────────────────────────────
      let feedback = [];
      if (trip.status === 'completed') {
        try {
          const fbDocs = await req.db.collection('driver_feedback').find({ tripId: trip._id }).toArray();
          feedback = fbDocs.map(fb => ({
            customerName: fb.customerName || 'Anonymous',
            customerEmail: fb.customerEmail || '',
            rating: fb.rating || 0,
            feedback: fb.feedback || '',
            rideAgain: fb.rideAgain || 'not_specified',
            submittedAt: fb.submittedAt,
          }));
        } catch (_) {}
      }

      // ── Metrics ───────────────────────────────────────────────────────────
      const totalStops = trip.stops?.length || 0;
      const completedStops = trip.stops?.filter(s => s.status === 'completed').length || 0;
      const onTimeStops = (trip.stops || []).filter(s => {
        if (!s.arrivedAt || !s.estimatedTime) return false;
        const [eh, em] = s.estimatedTime.split(':').map(Number);
        const arrived = new Date(s.arrivedAt);
        return Math.abs((arrived.getHours() * 60 + arrived.getMinutes()) - (eh * 60 + em)) <= 5;
      }).length;
      const delayedStops = (trip.stops || []).filter(s => {
        if (!s.arrivedAt || !s.estimatedTime) return false;
        const [eh, em] = s.estimatedTime.split(':').map(Number);
        const arrived = new Date(s.arrivedAt);
        return (arrived.getHours() * 60 + arrived.getMinutes()) - (eh * 60 + em) > 5;
      }).length;

      return {
        _id: trip._id,
        tripNumber: trip.tripNumber || 'N/A',
        tripGroupId: trip.tripGroupId,
        tripType: trip.tripType,
        // ✅ Direct trip-level fields (guaranteed to exist)
        vehicleNumber: trip.vehicleNumber || 'N/A',
        vehicleName: trip.vehicleName || 'N/A',
        driverName: trip.driverName || 'Unknown Driver',
        driverPhone: trip.driverPhone || 'N/A',
        driverEmail: trip.driverEmail || 'N/A',
        // Enriched sub-objects
        vehicle,
        driver,
        scheduledDate: trip.scheduledDate,
        startTime: trip.startTime,
        endTime: trip.endTime,
        actualStartTime: trip.actualStartTime,
        actualEndTime: trip.actualEndTime,
        status: trip.status,
        progress: totalStops > 0 ? Math.round((completedStops / totalStops) * 100) : 0,
        totalStops,
        completedStops,
        cancelledStops: trip.stops?.filter(s => s.status === 'cancelled').length || 0,
        customerCount: trip.stops?.filter(s => s.type === 'pickup').length || 0,
        totalDistance: trip.totalDistance || 0,
        totalTime: trip.totalTime || 0,
        actualDistance: trip.actualDistance || 0,
        startOdometer: trip.startOdometer?.reading || null,
        endOdometer: trip.endOdometer?.reading || null,
        metrics: { onTimeStops, delayedStops, averageDelay: 0 },
        // Stops with safe fallbacks
        stops: (trip.stops || []).map(s => ({
          stopId: s.stopId,
          sequence: s.sequence,
          type: s.type,
          customerName: s.customer?.name || 'Drop',
          customer: {
            name: s.customer?.name || 'N/A',
            email: s.customer?.email || '',
            phone: s.customer?.phone || '',
          },
          location: {
            address: s.location?.address || 'N/A',
            city: s.location?.city || '',
            state: s.location?.state || '',
            country: s.location?.country || '',
          },
          address: s.location?.address || 'N/A',
          estimatedTime: s.estimatedTime,
          arrivedAt: s.arrivedAt,
          departedAt: s.departedAt,
          status: s.status,
          distanceFromPrevious: s.distanceFromPrevious || 0,
          distanceToOffice: s.distanceToOffice || 0,
        })),
        customerFeedback: feedback,
        createdAt: trip.createdAt,
        updatedAt: trip.updatedAt
      };
    }));

    // ── Overall summary ────────────────────────────────────────────────────
    const allOngoing = enrichedTrips.filter(t => t.status === 'started' || t.status === 'in_progress').length;
    const allScheduled = enrichedTrips.filter(t => t.status === 'assigned').length;
    const allCompleted = enrichedTrips.filter(t => ['completed', 'done', 'finished'].includes(t.status)).length;
    const allCancelled = enrichedTrips.filter(t => t.status === 'cancelled').length;
    const totalDistance = enrichedTrips.reduce((sum, t) => sum + (t.totalDistance || 0), 0);
    const totalVehicles = new Set(enrichedTrips.map(t => t.vehicleNumber).filter(Boolean)).size;
    const totalDrivers = new Set(enrichedTrips.map(t => t.driverName).filter(Boolean)).size;
    const totalCustomers = enrichedTrips.reduce((sum, t) => sum + (t.customerCount || 0), 0);

    const summary = {
      total: enrichedTrips.length,
      ongoing: allOngoing,
      scheduled: allScheduled,
      completed: allCompleted,
      cancelled: allCancelled,
      totalVehicles,
      totalDrivers,
      totalCustomers,
      totalDistance,
      delayed: 0,
    };

    console.log(`✅ Report ready: ${enrichedTrips.length} trips`);
    console.log('='.repeat(70) + '\n');

    res.json({
      success: true,
      message: 'Bulk report data ready',
      data: {
        summary,
        trips: enrichedTrips,
        generatedAt: new Date().toISOString(),
        generatedBy: req.user.email || req.user.id || 'admin',
        filterApplied: { fromDate, toDate, status, country, state, city, locationSearch, search },
      }
    });

  } catch (error) {
    console.error('❌ Error generating bulk report:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

// ============================================================================
// ↓↓↓ PASTE CHUNK 2 CONTENT DIRECTLY BELOW THIS LINE ↓↓↓
// (remove chunk2's "const express..." header lines — keep only the routes
//  and the final module.exports = router; line)
// ============================================================================
// routes/admin_trip_management_chunk2.js
// ============================================================================
// ADMIN TRIP MANAGEMENT ROUTER — CHUNK 2 OF 2
// ============================================================================
// Contains:
//   - GET  /:tripId/details
//   - POST /:tripId/send-alert
//   - GET  /:tripId/report
//   - POST /backfill-denorm
//   - module.exports = router
//
// HOW TO COMBINE WITH CHUNK 1:
//   Open chunk1.js → delete its last comment block (the "PASTE CHUNK 2..." line)
//   Then append everything below (starting from the first router.get line)
//   down to and including module.exports = router;
//   The result is your complete admin_trip_management.js
// ============================================================================

// ============================================================================
// @route   GET /api/admin/trips/:tripId/details
// @desc    Get complete trip details - ✅ FIXED: Always return vehicle/driver data
// @access  Private (Admin only)
// ============================================================================
router.get('/:tripId/details', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🔍 FETCHING TRIP DETAILS');
    console.log('='.repeat(80));
    
    const { tripId } = req.params;
    
    console.log(`📋 Trip ID: ${tripId}`);
    
    if (!ObjectId.isValid(tripId)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid trip ID format'
      });
    }
    
    // ========================================================================
    // STEP 1: Fetch trip document
    // ========================================================================
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
    
    console.log(`✅ Trip found: ${trip.tripNumber}`);
    console.log(`   Vehicle: ${trip.vehicleNumber}`);
    console.log(`   Driver: ${trip.driverName}`);
    console.log(`   Status: ${trip.status}`);
    console.log(`   Stops: ${trip.stops?.length || 0}`);
    
    // ========================================================================
    // STEP 2: ✅ FIXED - Get vehicle details with FALLBACK to trip data
    // ========================================================================
    let vehicle = null;
    if (trip.vehicleId && ObjectId.isValid(trip.vehicleId.toString())) {
      try {
        vehicle = await req.db.collection('vehicles').findOne({
          _id: new ObjectId(trip.vehicleId)
        });
        console.log(`   Vehicle lookup: ${vehicle ? 'Found in DB' : 'Not found in DB, using trip data'}`);
      } catch (err) {
        console.log(`   ⚠️  Could not fetch vehicle: ${err.message}`);
      }
    }
    
    // ========================================================================
    // STEP 3: ✅ FIXED - Get driver details with FALLBACK to trip data
    // ========================================================================
    let driver = null;
    if (trip.driverId && ObjectId.isValid(trip.driverId.toString())) {
      try {
        driver = await req.db.collection('drivers').findOne({
          _id: new ObjectId(trip.driverId)
        });
        console.log(`   Driver lookup: ${driver ? 'Found in DB' : 'Not found in DB, using trip data'}`);
      } catch (err) {
        console.log(`   ⚠️  Could not fetch driver: ${err.message}`);
      }
    }
    
    // ========================================================================
    // STEP 4: Enhance stops with customer details
    // ========================================================================
    const enhancedStops = [];
    
    if (trip.stops && Array.isArray(trip.stops)) {
      for (const stop of trip.stops) {
        let customerDetails = null;
        
        if (stop.customer?.email) {
          customerDetails = await req.db.collection('customers').findOne({
            email: stop.customer.email
          });
        }
        
        let timingStatus = null;
        if (stop.status === 'completed' && stop.estimatedTime && stop.arrivedAt) {
          const estimated = stop.estimatedTime.split(':').map(Number);
          const estimatedMinutes = estimated[0] * 60 + estimated[1];
          
          const arrived = new Date(stop.arrivedAt);
          const arrivedMinutes = arrived.getHours() * 60 + arrived.getMinutes();
          
          const diff = arrivedMinutes - estimatedMinutes;
          
          if (diff > 5) {
            timingStatus = { type: 'delayed', minutes: diff };
          } else if (diff < -5) {
            timingStatus = { type: 'early', minutes: Math.abs(diff) };
          } else {
            timingStatus = { type: 'on_time', minutes: 0 };
          }
        }
        
        enhancedStops.push({
          stopId: stop.stopId,
          rosterId: stop.rosterId,
          sequence: stop.sequence,
          type: stop.type,
          
          customer: {
            name: stop.customer?.name || customerDetails?.name || 'Unknown',
            email: stop.customer?.email || customerDetails?.email || '',
            phone: stop.customer?.phone || customerDetails?.phone || '',
            employeeId: customerDetails?.employeeId || '',
            company: customerDetails?.company || '',
            department: customerDetails?.department || ''
          },
          
          location: stop.location,
          
          estimatedTime: stop.estimatedTime,
          readyByTime: stop.readyByTime,
          arrivedAt: stop.arrivedAt,
          departedAt: stop.departedAt,
          timingStatus: timingStatus,
          
          distanceToOffice: stop.distanceToOffice,
          distanceFromPrevious: stop.distanceFromPrevious,
          
          status: stop.status,
          passengerStatus: stop.passengerStatus,
          
          arrivalLocation: stop.arrivalLocation,
          departureLocation: stop.departureLocation
        });
      }
    }
    
    // ========================================================================
    // STEP 5: Calculate overall metrics
    // ========================================================================
    const totalStops = enhancedStops.length;
    const completedStops = enhancedStops.filter(s => s.status === 'completed').length;
    const progress = totalStops > 0 ? Math.round((completedStops / totalStops) * 100) : 0;
    
    const pickupStops = enhancedStops.filter(s => s.type === 'pickup');
    const dropStops = enhancedStops.filter(s => s.type === 'drop');
    
    const onTimeStops = enhancedStops.filter(s => s.timingStatus?.type === 'on_time').length;
    const delayedStops = enhancedStops.filter(s => s.timingStatus?.type === 'delayed').length;
    
    // ========================================================================
    // STEP 6: Get customer feedback - ✅ ENSURE ARRAY
    // ========================================================================
    let customerFeedback = [];
    if (trip.status === 'completed') {
      try {
        const feedbackDocs = await req.db.collection('driver_feedback').find({
          tripId: trip._id
        }).toArray();
        
        // ✅ FIX: Ensure it's always an array
        customerFeedback = Array.isArray(feedbackDocs) ? feedbackDocs.map(fb => ({
          feedbackId: fb._id,
          customerName: fb.customerName,
          customerEmail: fb.customerEmail,
          rating: fb.rating,
          feedback: fb.feedback,
          rideAgain: fb.rideAgain,
          submittedAt: fb.submittedAt
        })) : [];
        
        console.log(`   Customer Feedback: ${customerFeedback.length} item(s)`);
      } catch (err) {
        console.log(`   ⚠️  Could not fetch feedback: ${err.message}`);
        customerFeedback = [];
      }
    }
    
    // ========================================================================
    // STEP 7: ✅ FIXED - Build complete response with GUARANTEED vehicle/driver data
    // ========================================================================
    const tripDetails = {
      _id: trip._id,
      tripNumber: trip.tripNumber,
      tripGroupId: trip.tripGroupId,
      tripType: trip.tripType,
      
      // ✅ CRITICAL FIX: ALWAYS include trip data, use DB data as enhancement only
      vehicle: {
        _id: vehicle?._id || trip.vehicleId,
        vehicleNumber: trip.vehicleNumber || 'Unknown',  // ✅ ALWAYS from trip
        vehicleName: trip.vehicleName || '',             // ✅ ALWAYS from trip
        registrationNumber: vehicle?.registrationNumber || trip.vehicleNumber || 'N/A',
        capacity: vehicle?.capacity || 'N/A',
        fuelType: vehicle?.fuelType || 'N/A',
        manufacturer: vehicle?.manufacturer || 'N/A',
        model: vehicle?.model || 'N/A'
      },
      
      // ✅ CRITICAL FIX: ALWAYS include trip data, use DB data as enhancement only
      driver: {
        _id: driver?._id || trip.driverId,
        driverId: driver?.driverId || trip.driverId?.toString() || 'N/A',
        name: trip.driverName || 'Unknown Driver',      // ✅ ALWAYS from trip
        phone: trip.driverPhone || '',                  // ✅ ALWAYS from trip
        email: trip.driverEmail || '',                  // ✅ ALWAYS from trip
        licenseNumber: driver?.licenseDetails?.licenseNumber || 'N/A',
        experience: driver?.experience || 'N/A'
      },
      
      scheduledDate: trip.scheduledDate,
      startTime: trip.startTime,
      endTime: trip.endTime,
      actualStartTime: trip.actualStartTime,
      actualEndTime: trip.actualEndTime,
      
      status: trip.status,
      currentStopIndex: trip.currentStopIndex || 0,
      progress: progress,
      
      totalStops: totalStops,
      completedStops: completedStops,
      pickupStops: pickupStops.length,
      dropStops: dropStops.length,
      totalDistance: trip.totalDistance,
      totalTime: trip.totalTime,
      estimatedDuration: trip.estimatedDuration,
      
      metrics: {
        onTimeStops: onTimeStops,
        delayedStops: delayedStops,
        averageDelay: delayedStops > 0 ? 
          Math.round(enhancedStops
            .filter(s => s.timingStatus?.type === 'delayed')
            .reduce((sum, s) => sum + s.timingStatus.minutes, 0) / delayedStops) 
          : 0
      },
      
      startOdometer: trip.startOdometer,
      endOdometer: trip.endOdometer,
      actualDistance: trip.actualDistance,
      
      // ✅ CRITICAL FIX: Ensure stops is always an array
      stops: Array.isArray(enhancedStops) ? enhancedStops : [],
      
      // ✅ CRITICAL FIX: Ensure customerFeedback is always an array
      customerFeedback: Array.isArray(customerFeedback) ? customerFeedback : [],
      
      currentLocation: trip.currentLocation,
      // ✅ CRITICAL FIX: Ensure locationHistory is always an array
      locationHistory: Array.isArray(trip.locationHistory) ? trip.locationHistory : [],
      
      assignedAt: trip.assignedAt,
      createdAt: trip.createdAt,
      updatedAt: trip.updatedAt
    };
    
    console.log('\n✅ TRIP DETAILS COMPILED:');
    console.log(`   Vehicle: ${tripDetails.vehicle.vehicleNumber} (${tripDetails.vehicle.vehicleName})`);
    console.log(`   Driver: ${tripDetails.driver.name} (${tripDetails.driver.phone})`);
    console.log(`   Total stops: ${totalStops}`);
    console.log(`   Completed: ${completedStops} (${progress}%)`);
    console.log(`   Feedback items: ${customerFeedback.length}`);
    console.log('='.repeat(80) + '\n');
    
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
// @route   POST /api/admin/trips/:tripId/send-alert
// @desc    Send urgent alert to driver (FCM + Email + Database)
// @access  Private (Admin only)
// ============================================================================
router.post('/:tripId/send-alert', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '🚨'.repeat(40));
    console.log('SENDING ALERT TO DRIVER');
    console.log('🚨'.repeat(40));
    
    const { tripId } = req.params;
    const { message, priority = 'high' } = req.body;
    
    console.log(`📋 Trip ID: ${tripId}`);
    console.log(`📝 Message: ${message}`);
    console.log(`⚠️  Priority: ${priority}`);
    console.log(`👤 Sent by: ${req.user.email || req.user.id}`);
    
    if (!message || message.trim().length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Alert message is required'
      });
    }
    
    if (!ObjectId.isValid(tripId)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid trip ID format'
      });
    }
    
    const trip = await req.db.collection('roster-assigned-trips').findOne({
      _id: new ObjectId(tripId)
    });
    
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }
    
    console.log(`✅ Trip: ${trip.tripNumber}`);
    console.log(`🚗 Vehicle: ${trip.vehicleNumber}`);
    
    const driver = await req.db.collection('drivers').findOne({
      _id: trip.driverId
    });
    
    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    const driverName = driver.personalInfo?.name || driver.name || 'Driver';
    const driverEmail = driver.personalInfo?.email || driver.email;
    
    console.log(`✅ Driver: ${driverName}`);
    console.log(`📧 Email: ${driverEmail}`);
    
    console.log('\n📱 SENDING FCM NOTIFICATIONS...');
    
    const devices = await req.db.collection('user_devices').find({
      $or: [
        { userId: driver._id.toString() },
        { userEmail: driverEmail }
      ],
      isActive: true
    }).toArray();
    
    console.log(`   Found ${devices.length} active device(s)`);
    
    let fcmSuccessCount = 0;
    const fcmErrors = [];
    
    for (const device of devices) {
      try {
        await notificationService.send({
          deviceToken: device.deviceToken,
          deviceType: device.deviceType || 'android',
          title: `🚨 URGENT ALERT - ${priority.toUpperCase()}`,
          body: message,
          data: {
            type: 'admin_alert',
            tripId: tripId,
            tripNumber: trip.tripNumber,
            vehicleNumber: trip.vehicleNumber,
            priority: priority,
            alertTime: new Date().toISOString()
          },
          priority: 'urgent'
        });
        
        fcmSuccessCount++;
        console.log(`   ✅ FCM sent to ${device.deviceType}`);
      } catch (fcmError) {
        console.log(`   ❌ FCM failed for ${device.deviceType}: ${fcmError.message}`);
        fcmErrors.push({
          deviceType: device.deviceType,
          error: fcmError.message
        });
      }
    }
    
    console.log(`   📊 FCM: ${fcmSuccessCount}/${devices.length} sent`);
    
    console.log('\n💾 SAVING ALERT TO DATABASE...');
    
    const alertDoc = {
      tripId: trip._id,
      tripNumber: trip.tripNumber,
      driverId: driver._id,
      driverName: driverName,
      driverEmail: driverEmail,
      vehicleId: trip.vehicleId,
      vehicleNumber: trip.vehicleNumber,
      
      message: message,
      priority: priority,
      
      sentBy: req.user.email || req.user.id || 'admin',
      sentByName: req.user.name || 'Admin',
      
      sentAt: new Date(),
      
      deliveryStatus: {
        fcm: {
          sent: fcmSuccessCount,
          failed: devices.length - fcmSuccessCount,
          errors: fcmErrors
        },
        email: 'not_implemented',
        database: 'saved'
      },
      
      status: 'sent',
      readAt: null,
      acknowledgedAt: null
    };
    
    const insertResult = await req.db.collection('driver_alerts').insertOne(alertDoc);
    
    console.log(`   ✅ Alert saved: ${insertResult.insertedId}`);
    
    await req.db.collection('notifications').insertOne({
      userId: driver._id,
      userEmail: driverEmail,
      userRole: 'driver',
      type: 'admin_alert',
      title: `🚨 URGENT ALERT - ${priority.toUpperCase()}`,
      body: message,
      message: message,
      data: {
        tripId: tripId,
        tripNumber: trip.tripNumber,
        vehicleNumber: trip.vehicleNumber,
        priority: priority,
        alertId: insertResult.insertedId.toString()
      },
      priority: priority,
      category: 'alerts',
      isRead: false,
      createdAt: new Date(),
      updatedAt: new Date(),
      expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      deliveryStatus: {
        fcm: fcmSuccessCount > 0 ? 'success' : 'no_devices',
        database: 'success'
      },
      channels: ['fcm', 'database']
    });
    
    console.log('   ✅ In-app notification created');
    
    console.log('\n' + '✅'.repeat(40));
    console.log('ALERT SENT SUCCESSFULLY');
    console.log('✅'.repeat(40) + '\n');
    
    res.json({
      success: true,
      message: 'Alert sent successfully',
      data: {
        alertId: insertResult.insertedId,
        tripNumber: trip.tripNumber,
        driverName: driverName,
        deliveryStatus: {
          fcm: `${fcmSuccessCount}/${devices.length} devices`,
          email: 'not sent',
          database: 'saved'
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Error sending alert:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to send alert',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/admin/trips/:tripId/report
// @desc    Generate trip report data (ready for PDF generation in frontend)
// @access  Private (Admin only)
// ============================================================================
router.get('/:tripId/report', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '📊'.repeat(40));
    console.log('GENERATING TRIP REPORT DATA');
    console.log('📊'.repeat(40));
    
    const { tripId } = req.params;
    
    const trip = await req.db.collection('roster-assigned-trips').findOne({
      _id: new ObjectId(tripId)
    });
    
    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }
    
    console.log(`📋 Generating report for: ${trip.tripNumber}`);
    
    // Get vehicle and driver details
    let vehicle = null;
    if (trip.vehicleId && ObjectId.isValid(trip.vehicleId.toString())) {
      vehicle = await req.db.collection('vehicles').findOne({
        _id: new ObjectId(trip.vehicleId)
      });
    }
    
    let driver = null;
    if (trip.driverId && ObjectId.isValid(trip.driverId.toString())) {
      driver = await req.db.collection('drivers').findOne({
        _id: new ObjectId(trip.driverId)
      });
    }
    
    // Get customer feedback
    const feedbackDocs = await req.db.collection('driver_feedback').find({
      tripId: trip._id
    }).toArray();
    
    // Build comprehensive report data
    const report = {
      reportGeneratedAt: new Date().toISOString(),
      reportGeneratedBy: req.user.email || req.user.id,
      
      tripInfo: {
        tripNumber: trip.tripNumber,
        tripType: trip.tripType,
        scheduledDate: trip.scheduledDate,
        status: trip.status,
        startTime: trip.startTime,
        endTime: trip.endTime,
        actualStartTime: trip.actualStartTime,
        actualEndTime: trip.actualEndTime
      },
      
      vehicleInfo: {
        vehicleNumber: trip.vehicleNumber || 'Unknown',
        vehicleName: trip.vehicleName || '',
        registrationNumber: vehicle?.registrationNumber || trip.vehicleNumber || 'N/A',
        manufacturer: vehicle?.manufacturer || 'N/A',
        model: vehicle?.model || 'N/A',
        capacity: vehicle?.capacity || 'N/A'
      },
      
      driverInfo: {
        name: trip.driverName || 'Unknown',
        phone: trip.driverPhone || '',
        email: trip.driverEmail || '',
        licenseNumber: driver?.licenseDetails?.licenseNumber || 'N/A'
      },
      
      routeSummary: {
        totalStops: trip.stops?.length || 0,
        completedStops: trip.stops?.filter(s => s.status === 'completed').length || 0,
        cancelledStops: trip.stops?.filter(s => s.status === 'cancelled').length || 0,
        totalDistance: trip.totalDistance || 0,
        totalTime: trip.totalTime || 0,
        startOdometer: trip.startOdometer?.reading || 'N/A',
        endOdometer: trip.endOdometer?.reading || 'N/A',
        actualDistance: trip.actualDistance || 0
      },
      
      stops: trip.stops?.map(stop => {
        // ✅ Extract customer info properly
        const customerName = stop.type === 'pickup' 
          ? (stop.customer?.name || 'Unknown Customer')
          : 'Office Drop';
          
        const customerPhone = stop.type === 'pickup'
          ? (stop.customer?.phone || '')
          : '';
        
        return {
          sequence: stop.sequence,
          type: stop.type,
          
          // Customer details
          customerName: customerName,
          customerPhone: customerPhone,
          customerEmail: stop.customer?.email || '',
          
          // Customer object (for nested access)
          customer: {
            name: customerName,
            phone: customerPhone,
            email: stop.customer?.email || '',
          },
          
          // Location
          address: stop.location?.address || '',
          location: {
            address: stop.location?.address || '',
            city: stop.location?.city || '',
            state: stop.location?.state || '',
            country: stop.location?.country || '',
          },
          
          // Timing - ✅ CRITICAL: Include ALL timing fields
          estimatedTime: stop.estimatedTime || '',
          pickupTime: stop.pickupTime || '',
          readyByTime: stop.readyByTime || '',
          arrivedAt: stop.arrivedAt || null,        // ✅ ACTUAL ARRIVAL TIME
          departedAt: stop.departedAt || null,      // ✅ ACTUAL DEPARTURE TIME
          
          // Status
          status: stop.status || 'pending',
          passengerStatus: stop.passengerStatus || null,
          
          // Distance
          distanceFromPrevious: stop.distanceFromPrevious || 0,
          distanceToOffice: stop.distanceToOffice || 0,
        };
      }) || [],
      
      customerFeedback: feedbackDocs.map(fb => ({
        customerName: fb.customerName,
        customerEmail: fb.customerEmail,
        rating: fb.rating,
        feedback: fb.feedback,
        rideAgain: fb.rideAgain,
        submittedAt: fb.submittedAt
      })),
      
      performance: {
        onTimeStops: trip.stops?.filter(s => {
          if (!s.arrivedAt || !s.estimatedTime) return false;
          const estimated = s.estimatedTime.split(':').map(Number);
          const estimatedMinutes = estimated[0] * 60 + estimated[1];
          const arrived = new Date(s.arrivedAt);
          const arrivedMinutes = arrived.getHours() * 60 + arrived.getMinutes();
          return Math.abs(arrivedMinutes - estimatedMinutes) <= 5;
        }).length || 0,
        
        averageRating: feedbackDocs.length > 0 ?
          (feedbackDocs.reduce((sum, fb) => sum + fb.rating, 0) / feedbackDocs.length).toFixed(2)
          : 'N/A',
        
        totalFeedback: feedbackDocs.length
      }
    };
    
    console.log('✅ Report data generated successfully');
    console.log('📊'.repeat(40) + '\n');
    
    res.json({
      success: true,
      message: 'Trip report data generated',
      data: report
    });
    
  } catch (error) {
    console.error('❌ Error generating report:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to generate report',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/admin/trips/backfill-denorm
// @desc    One-time migration to backfill missing vehicle/driver fields
// @access  Private (Admin only) - Run once after deployment
// ============================================================================
router.post('/backfill-denorm', verifyToken, async (req, res) => {
  try {
    console.log('🔧 Starting backfill of denormalised vehicle/driver fields...');

    const trips = await req.db.collection('roster-assigned-trips')
      .find({ $or: [{ vehicleNumber: { $exists: false } }, { driverName: { $exists: false } }] })
      .toArray();

    console.log(`Found ${trips.length} trip(s) needing backfill`);

    let updated = 0;
    let skipped = 0;

    for (const trip of trips) {
      const updates = {};

      // Fetch vehicle
      if (!trip.vehicleNumber && trip.vehicleId) {
        try {
          const v = await req.db.collection('vehicles').findOne({ _id: new ObjectId(trip.vehicleId) });
          if (v) {
            updates.vehicleNumber = v.registrationNumber || v.vehicleNumber || 'N/A';
            updates.vehicleName = v.name || v.vehicleName || '';
          }
        } catch (_) {}
      }

      // Fetch driver
      if (!trip.driverName && trip.driverId) {
        try {
          const d = await req.db.collection('drivers').findOne({ _id: new ObjectId(trip.driverId) });
          if (d) {
            updates.driverName = d.personalInfo?.name || d.name || 'Unknown Driver';
            updates.driverPhone = d.personalInfo?.phone || d.phone || '';
            updates.driverEmail = d.personalInfo?.email || d.email || '';
          }
        } catch (_) {}
      }

      if (Object.keys(updates).length > 0) {
        await req.db.collection('roster-assigned-trips').updateOne(
          { _id: trip._id },
          { $set: { ...updates, updatedAt: new Date() } }
        );
        updated++;
      } else {
        skipped++;
      }
    }

    console.log(`✅ Backfill done. Updated: ${updated}, Skipped: ${skipped}`);
    res.json({ success: true, message: `Backfill complete. Updated: ${updated}, Skipped: ${skipped}` });

  } catch (error) {
    console.error('❌ Backfill error:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

module.exports = router;

// ============================================================================
// INTEGRATION INSTRUCTIONS
// ============================================================================
//
// In your main app.js / server.js:
//
//   const adminTripsRouter = require('./routes/admin_trip_management');
//   app.use('/api/admin/trips', adminTripsRouter);
//
// After deploying, run the backfill once to fix existing documents:
//   POST /api/admin/trips/backfill-denorm
//
// This fixes all existing documents where vehicleNumber / driverName are missing.
// ============================================================================