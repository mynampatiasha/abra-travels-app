const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');

// Initialize models
let Trip, Roster;
router.use((req, res, next) => {
  try {
    if (!req.db) {
      return res.status(500).json({ msg: 'Database connection not available' });
    }
    
    if (!Trip) {
      const TripModel = require('../models/trip_model');
      Trip = new TripModel(req.db);
    }
    
    if (!Roster) {
      const RosterModel = require('../models/roster_model');
      Roster = new RosterModel(req.db);
    }
    next();
  } catch (error) {
    console.error('CRITICAL: Failed to initialize models in middleware:', error);
    res.status(500).json({ success: false, message: 'Server configuration error.' });
  }
});

// @route   GET /api/customer/stats/dashboard
// @desc    Get all customer statistics in one call
// @access  Private (Customer)
router.get('/dashboard', async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;
    
    console.log(`📊 STATS DASHBOARD: Fetching stats for user ${userId} (${userEmail})`);
    
    // ✅ FIX: Use ROSTERS as primary data source (same as My Trips)
    // Query rosters using email (like My Trips does)
    const userRosters = await req.db.collection('rosters').find({
      $or: [
        { customerEmail: userEmail },
        { 'employeeDetails.email': userEmail },
        { 'employeeData.email': userEmail }
      ]
    }).toArray();
    
    console.log(`📋 Found ${userRosters.length} rosters for ${userEmail}`);
    
    // ✅ OPTIONAL: Also query trips for additional data (but prioritize rosters)
    const userTrips = await req.db.collection('trips').find({
      $or: [
        { customerEmail: userEmail },
        { 'employeeDetails.email': userEmail },
        { 'employeeData.email': userEmail }
      ]
    }).toArray();
    
    console.log(`📈 Found ${userTrips.length} trips for ${userEmail}`);

    // ✅ FIX: Pass rosters as primary data source
    const tripStats = calculateTripStats(userTrips, userRosters);
    
    // ✅ FIX: Calculate distance from ROSTERS (not trips)
    const distanceStats = calculateDistanceStatsFromRosters(userRosters);
    
    // ✅ FIX: Get recent trip details from ROSTERS (not trips)
    const recentTrip = getRecentTripDetailsFromRosters(userRosters);
    
    // Calculate delivery performance from rosters
    const deliveryStats = calculateDeliveryStatsFromRosters(userRosters);
    
    // Calculate service frequency
    const frequencyStats = calculateServiceFrequency(userTrips, userRosters);
    
    // Get top routes from rosters
    const topRoutes = calculateTopRoutesFromRosters(userRosters);

    const dashboardData = {
      totalTrips: tripStats,
      onTimeDelivery: deliveryStats,
      totalDistance: distanceStats.total,
      recentTrip: recentTrip,
      monthlyDistance: distanceStats.monthly,
      weeklyBookings: frequencyStats,
      topRoutes: topRoutes,
      lastUpdated: new Date()
    };

    res.json({
      success: true,
      data: dashboardData
    });

  } catch (error) {
    console.error('Error fetching customer dashboard stats:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch dashboard statistics'
    });
  }
});

// @route   GET /api/customer/stats/daily-trips
// @desc    Get daily trips with actual data only (no empty days)
// @access  Private (Customer)
router.get('/daily-trips', async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;
    const rosterId = req.query.rosterId;
    
    if (!rosterId) {
      return res.status(400).json({
        success: false,
        message: 'Roster ID is required'
      });
    }
    
    console.log(`📊 DAILY TRIPS: Fetching for roster ${rosterId}, user ${userEmail}`);
    
    // ✅ FIX: Query using email (like My Trips does)
    // Get actual trips for this roster
    const trips = await req.db.collection('trips').find({
      $and: [
        {
          $or: [
            { customerEmail: userEmail },
            { customerId: userId },
            { customerId: new ObjectId(userId) }
          ]
        },
        { rosterId: rosterId }
      ]
    }).sort({ scheduledDate: 1 }).toArray();
    
    console.log(`📈 Found ${trips.length} daily trips for roster ${rosterId}`);
    
    // Format daily trips with distance and details
    const dailyTrips = trips.map(trip => ({
      date: trip.scheduledDate,
      dateString: new Date(trip.scheduledDate).toLocaleDateString('en-GB'),
      status: trip.status,
      distance: trip.actualDistance || trip.distance || 0,
      driverName: trip.driverName,
      driverPhone: trip.driverPhone,
      vehicleNumber: trip.vehicleNumber,
      tripId: trip.tripId,
      pickupTime: trip.pickupTime,
      dropoffTime: trip.dropoffTime
    }));
    
    res.json({
      success: true,
      data: dailyTrips
    });

  } catch (error) {
    console.error('Error fetching daily trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch daily trips'
    });
  }
});

// @route   GET /api/customer/stats/trips
// @desc    Get trip breakdown statistics
// @access  Private (Customer)
router.get('/trips', async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;
    
    console.log(`📊 STATS TRIPS: Fetching trips for user ${userId} (${userEmail})`);
    
    // ✅ FIX: Query using email (like My Trips does)
    const trips = await req.db.collection('trips').find({
      $or: [
        { customerEmail: userEmail },
        { customerId: userId },
        { customerId: new ObjectId(userId) }
      ]
    }).toArray();
    
    const rosters = await req.db.collection('rosters').find({
      $or: [
        { customerEmail: userEmail },
        { 'employeeDetails.email': userEmail },
        { 'employeeData.email': userEmail },
        { userId: userId },
        { userId: new ObjectId(userId) }
      ]
    }).toArray();
    
    console.log(`📈 Found ${trips.length} trips and ${rosters.length} rosters for ${userEmail}`);

    const stats = calculateTripStats(trips, rosters);
    
    res.json({
      success: true,
      data: stats
    });

  } catch (error) {
    console.error('Error fetching trip stats:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch trip statistics'
    });
  }
});

// All other routes are preserved and unchanged
// @route   GET /api/customer/stats/monthly-distance
// @desc    Get monthly distance data for billing with month filter
// @access  Private (Customer)
router.get('/monthly-distance', async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;
    const selectedMonth = req.query.month; // Format: "2024-01" for January 2024
    const selectedYear = req.query.year || new Date().getFullYear();
    
    console.log(`📊 MONTHLY DISTANCE: Fetching for user ${userEmail}`);
    
    // ✅ FIX: Query using email (like My Trips does)
    // Get all trips for the user
    const allTrips = await req.db.collection('trips').find({
      $or: [
        { customerEmail: userEmail },
        { customerId: userId },
        { customerId: new ObjectId(userId) }
      ]
    }).toArray();
    
    console.log(`📈 Found ${allTrips.length} trips for monthly distance calculation`);
    
    // Calculate total distance (all time)
    let totalDistance = 0;
    allTrips.forEach(trip => {
      if (trip.actualDistance) {
        totalDistance += trip.actualDistance;
      } else if (trip.distance) {
        totalDistance += trip.distance;
      }
    });
    
    // Calculate today's distance
    const today = new Date();
    const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
    
    const todayTrips = allTrips.filter(trip => {
      const tripDate = new Date(trip.scheduledDate || trip.createdAt);
      return tripDate >= todayStart && tripDate < todayEnd;
    });
    
    let todayDistance = 0;
    todayTrips.forEach(trip => {
      if (trip.actualDistance) {
        todayDistance += trip.actualDistance;
      } else if (trip.distance) {
        todayDistance += trip.distance;
      }
    });
    
    // If specific month requested, get that month's data
    let monthlyData = null;
    if (selectedMonth) {
      const [year, month] = selectedMonth.split('-');
      const monthStart = new Date(parseInt(year), parseInt(month) - 1, 1);
      const monthEnd = new Date(parseInt(year), parseInt(month), 0, 23, 59, 59);
      
      const monthTrips = allTrips.filter(trip => {
        const tripDate = new Date(trip.scheduledDate || trip.createdAt);
        return tripDate >= monthStart && tripDate <= monthEnd;
      });
      
      let monthDistance = 0;
      const dailyBreakdown = {};
      
      monthTrips.forEach(trip => {
        const distance = trip.actualDistance || trip.distance || 0;
        monthDistance += distance;
        
        // Group by day for daily breakdown
        const tripDate = new Date(trip.scheduledDate || trip.createdAt);
        const dayKey = tripDate.getDate();
        
        if (!dailyBreakdown[dayKey]) {
          dailyBreakdown[dayKey] = {
            day: dayKey,
            date: tripDate.toLocaleDateString('en-GB'),
            distance: 0,
            trips: 0
          };
        }
        
        dailyBreakdown[dayKey].distance += distance;
        dailyBreakdown[dayKey].trips += 1;
      });
      
      monthlyData = {
        month: selectedMonth,
        monthName: new Date(parseInt(year), parseInt(month) - 1).toLocaleDateString('en', { month: 'long', year: 'numeric' }),
        totalDistance: Math.round(monthDistance * 10) / 10,
        totalTrips: monthTrips.length,
        dailyBreakdown: Object.values(dailyBreakdown).sort((a, b) => a.day - b.day)
      };
    }
    
    // Generate available months (months that have trip data)
    const availableMonths = [];
    const monthsWithData = new Set();
    
    allTrips.forEach(trip => {
      const tripDate = new Date(trip.scheduledDate || trip.createdAt);
      if (!isNaN(tripDate.getTime())) {
        const monthKey = `${tripDate.getFullYear()}-${String(tripDate.getMonth() + 1).padStart(2, '0')}`;
        monthsWithData.add(monthKey);
      }
    });
    
    // Convert to sorted array with month names
    Array.from(monthsWithData).sort().forEach(monthKey => {
      const [year, month] = monthKey.split('-');
      const monthName = new Date(parseInt(year), parseInt(month) - 1).toLocaleDateString('en', { month: 'long', year: 'numeric' });
      availableMonths.push({
        key: monthKey,
        name: monthName,
        shortName: new Date(parseInt(year), parseInt(month) - 1).toLocaleDateString('en', { month: 'short' })
      });
    });
    
    res.json({
      success: true,
      data: {
        totalDistance: Math.round(totalDistance * 10) / 10,
        todayDistance: Math.round(todayDistance * 10) / 10,
        todayTrips: todayTrips.length,
        availableMonths: availableMonths,
        selectedMonthData: monthlyData
      }
    });

  } catch (error) {
    console.error('Error fetching monthly distance:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch monthly distance data'
    });
  }
});

// @route   GET /api/customer/stats/distance
// @desc    Get distance statistics (legacy endpoint)
// @access  Private (Customer)
router.get('/distance', async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;
    const months = parseInt(req.query.months) || 6;
    
    // ✅ FIX: Query using email (like My Trips does)
    const trips = await req.db.collection('trips').find({
      $and: [
        {
          $or: [
            { customerEmail: userEmail },
            { customerId: userId },
            { customerId: new ObjectId(userId) }
          ]
        },
        { createdAt: { $gte: new Date(Date.now() - (months * 30 * 24 * 60 * 60 * 1000)) } }
      ]
    }).toArray();
    const distanceStats = calculateDistanceStats(trips);
    res.json({ success: true, data: distanceStats.monthly });
  } catch (error) {
    console.error('Error fetching distance stats:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch distance statistics' });
  }
});

router.get('/frequency', async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;
    const weeks = parseInt(req.query.weeks) || 12;
    const dateLimit = { $gte: new Date(Date.now() - (weeks * 7 * 24 * 60 * 60 * 1000)) };
    
    // ✅ FIX: Query using email (like My Trips does)
    const trips = await req.db.collection('trips').find({ 
      $and: [
        {
          $or: [
            { customerEmail: userEmail },
            { customerId: userId },
            { customerId: new ObjectId(userId) }
          ]
        },
        { createdAt: dateLimit }
      ]
    }).toArray();
    
    const rosters = await req.db.collection('rosters').find({ 
      $and: [
        {
          $or: [
            { customerEmail: userEmail },
            { 'employeeDetails.email': userEmail },
            { 'employeeData.email': userEmail },
            { userId: userId },
            { userId: new ObjectId(userId) }
          ]
        },
        { createdAt: dateLimit }
      ]
    }).toArray();
    const frequency = calculateServiceFrequency(trips, rosters, weeks);
    res.json({ success: true, data: frequency });
  } catch (error) {
    console.error('Error fetching frequency stats:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch frequency statistics' });
  }
});

router.get('/routes', async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;
    const limit = parseInt(req.query.limit) || 3;
    
    // ✅ FIX: Query using email (like My Trips does)
    const trips = await req.db.collection('trips').find({ 
      $or: [
        { customerEmail: userEmail },
        { customerId: userId },
        { customerId: new ObjectId(userId) }
      ]
    }).toArray();
    const topRoutes = calculateTopRoutes(trips, limit);
    res.json({ success: true, data: topRoutes });
  } catch (error) {
    console.error('Error fetching route stats:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch route statistics' });
  }
});

router.get('/delivery-performance', async (req, res) => {
  try {
    const userId = req.user.userId;
    const userEmail = req.user.email;
    
    // ✅ FIX: Query using email (like My Trips does)
    const trips = await req.db.collection('trips').find({
      $and: [
        {
          $or: [
            { customerEmail: userEmail },
            { customerId: userId },
            { customerId: new ObjectId(userId) }
          ]
        },
        { status: { $in: ['completed', 'delivered'] } }
      ]
    }).toArray();
    const deliveryStats = calculateDeliveryStats(trips);
    res.json({ success: true, data: deliveryStats });
  } catch (error) {
    console.error('Error fetching delivery stats:', error);
    res.status(500).json({ success: false, message: 'Failed to fetch delivery statistics' });
  }
});


// ===================================================================
// HELPER FUNCTIONS (UPDATED FOR STABILITY & LOGIC)
// ===================================================================

/**
 * **LOGIC FIX**
 * This function is now updated to correctly calculate the total, fixing the counting bug.
 */
function calculateTripStats(trips = [], rosters = []) {
  const checkStatus = (item, statuses) => {
    if (!item.status || typeof item.status !== 'string') return false;
    return statuses.includes(item.status.trim().toLowerCase());
  };

  // Count only actual trips (not rosters) with proper status separation
  const completedTrips = trips.filter(t => checkStatus(t, ['completed', 'delivered'])).length;
  const ongoingTrips = trips.filter(t => checkStatus(t, ['in_progress', 'picked_up', 'ongoing'])).length;
  const scheduledTrips = trips.filter(t => checkStatus(t, ['scheduled', 'assigned'])).length;
  const cancelledTrips = trips.filter(t => checkStatus(t, ['cancelled'])).length;
  
  // For rosters, we only count them as "ongoing" if they are pending assignment
  const pendingRosters = rosters.filter(r => checkStatus(r, ['pending_assignment', 'pending'])).length;
  const cancelledRosters = rosters.filter(r => checkStatus(r, ['cancelled'])).length;

  // Final counts - separate trips from rosters for clarity
  const completed = completedTrips;
  const ongoing = ongoingTrips + scheduledTrips + pendingRosters; // Include scheduled in ongoing for UI display
  const cancelled = cancelledTrips + cancelledRosters;
  const total = completed + ongoing + cancelled;

  const result = { 
    completed, 
    ongoing, 
    cancelled, 
    total,
    // Additional breakdown for debugging
    breakdown: {
      completedTrips,
      ongoingTrips,
      scheduledTrips,
      cancelledTrips,
      pendingRosters,
      cancelledRosters
    }
  };
  
  console.log('Trip stats calculation:', result);

  return result;
}

// All other helper functions are preserved and unchanged
function calculateDistanceStats(trips = []) {
  let total = 0;
  const monthlyData = {};
  trips.forEach(trip => {
    if (trip.distance && (trip.createdAt || trip.startTime)) {
      total += parseFloat(trip.distance) || 0;
      const date = new Date(trip.createdAt || trip.startTime);
      if (isNaN(date.getTime())) return;
      const monthKey = date.toISOString().substr(0, 7);
      if (!monthlyData[monthKey]) monthlyData[monthKey] = 0;
      monthlyData[monthKey] += parseFloat(trip.distance) || 0;
    }
  });
  const monthly = Object.entries(monthlyData)
    .sort(([a], [b]) => a.localeCompare(b))
    .slice(-6)
    .map(([monthKey, distance]) => ({
      month: new Date(monthKey + '-02').toLocaleDateString('en', { month: 'short' }),
      distance: Math.round(distance * 100) / 100
    }));
  return { total: Math.round(total * 100) / 100, monthly };
}

function calculateDeliveryStats(trips = []) {
  const checkStatus = (item, statuses) => {
    if (!item.status || typeof item.status !== 'string') return false;
    return statuses.includes(item.status.trim().toLowerCase());
  };
  const completedTrips = trips.filter(trip => checkStatus(trip, ['completed', 'delivered']));
  if (completedTrips.length === 0) return { onTime: 0, delayed: 0 };
  let onTime = 0;
  let delayed = 0;
  completedTrips.forEach(trip => {
    if (trip.scheduledTime && trip.actualCompletionTime) {
      const scheduled = new Date(trip.scheduledTime);
      const actual = new Date(trip.actualCompletionTime);
      if (isNaN(scheduled.getTime()) || isNaN(actual.getTime())) {
        onTime++;
        return;
      }
      if (actual <= scheduled) onTime++;
      else delayed++;
    } else {
      onTime++;
    }
  });
  return { onTime, delayed };
}

function calculateServiceFrequency(trips = [], rosters = [], weeks = 12) {
  const frequency = new Array(weeks).fill(0);
  const now = new Date();
  const weekBoundaries = [];
  for (let i = 0; i < weeks; i++) {
    const weekEnd = new Date(now.getTime() - (i * 7 * 24 * 60 * 60 * 1000));
    const weekStart = new Date(now.getTime() - ((i + 1) * 7 * 24 * 60 * 60 * 1000));
    weekBoundaries.push({ start: weekStart, end: weekEnd });
  }
  weekBoundaries.reverse();
  weekBoundaries.forEach((week, index) => {
    const weekTrips = trips.filter(trip => {
      if (!trip.createdAt && !trip.startTime) return false;
      const tripDate = new Date(trip.createdAt || trip.startTime);
      return !isNaN(tripDate.getTime()) && tripDate >= week.start && tripDate < week.end;
    }).length;
    const weekRosters = rosters.filter(roster => {
      if (!roster.createdAt) return false;
      const rosterDate = new Date(roster.createdAt);
      return !isNaN(rosterDate.getTime()) && rosterDate >= week.start && rosterDate < week.end;
    }).length;
    frequency[index] = weekTrips + weekRosters;
  });
  return frequency;
}

function calculateTopRoutes(trips = [], limit = 3) {
  const routeCount = {};
  trips.forEach(trip => {
    if (trip.pickupLocation && trip.dropoffLocation) {
      const getCoordString = (coords) => {
        if (!Array.isArray(coords)) return null;
        const lat = coords[1];
        const lon = coords[0];
        if (typeof lat === 'number' && typeof lon === 'number') {
          return `${lat.toFixed(3)}, ${lon.toFixed(3)}`;
        }
        return null;
      };
      const pickupCoords = getCoordString(trip.pickupLocation.coordinates);
      const dropoffCoords = getCoordString(trip.dropoffLocation.coordinates);
      const pickup = trip.pickupLocation.address || pickupCoords || 'Pickup Location';
      const dropoff = trip.dropoffLocation.address || dropoffCoords || 'Dropoff Location';
      const route = `${pickup} → ${dropoff}`;
      routeCount[route] = (routeCount[route] || 0) + 1;
    }
  });
  return Object.entries(routeCount)
    .sort(([, a], [, b]) => b - a)
    .slice(0, limit)
    .map(([route, count]) => ({ route, count }));
}

/**
 * Get recent trip details for distance summary display
 * ✅ FIX: Get data from ROSTERS (same as My Trips screen)
 */
function getRecentTripDetailsFromRosters(rosters = []) {
  if (!rosters || rosters.length === 0) return null;
  
  // Filter for completed rosters and sort by date (most recent first)
  const completedRosters = rosters
    .filter(roster => {
      const status = roster.status?.toLowerCase();
      return status === 'completed' || status === 'delivered';
    })
    .sort((a, b) => {
      const dateA = new Date(a.updatedAt || a.completedAt || a.createdAt || 0);
      const dateB = new Date(b.updatedAt || b.completedAt || b.createdAt || 0);
      return dateB.getTime() - dateA.getTime();
    });
  
  if (completedRosters.length === 0) {
    // If no completed rosters, get the most recent roster regardless of status
    const sortedRosters = rosters.sort((a, b) => {
      const dateA = new Date(a.updatedAt || a.createdAt || 0);
      const dateB = new Date(b.updatedAt || b.createdAt || 0);
      return dateB.getTime() - dateA.getTime();
    });
    
    if (sortedRosters.length > 0) {
      const recentRoster = sortedRosters[0];
      return {
        vehicleNumber: recentRoster.vehicleNumber || recentRoster.vehicleReg || 'N/A',
        driverName: recentRoster.driverName || 'N/A',
        driverPhone: recentRoster.driverPhone || 'N/A',
        distance: recentRoster.actualDistance || recentRoster.distance || 0,
        date: recentRoster.updatedAt || recentRoster.createdAt,
        status: recentRoster.status || 'unknown'
      };
    }
    return null;
  }
  
  // Return the most recent completed roster
  const recentRoster = completedRosters[0];
  return {
    vehicleNumber: recentRoster.vehicleNumber || recentRoster.vehicleReg || 'N/A',
    driverName: recentRoster.driverName || 'N/A', 
    driverPhone: recentRoster.driverPhone || 'N/A',
    distance: recentRoster.actualDistance || recentRoster.distance || 0,
    date: recentRoster.updatedAt || recentRoster.completedAt || recentRoster.createdAt,
    status: recentRoster.status || 'completed'
  };
}

/**
 * Calculate distance statistics from ROSTERS
 * ✅ FIX: Use rosters as data source (same as My Trips)
 */
function calculateDistanceStatsFromRosters(rosters = []) {
  let total = 0;
  const monthlyData = {};
  
  rosters.forEach(roster => {
    const distance = roster.actualDistance || roster.distance || 0;
    if (distance > 0 && (roster.createdAt || roster.updatedAt)) {
      total += parseFloat(distance) || 0;
      
      const date = new Date(roster.updatedAt || roster.createdAt);
      if (isNaN(date.getTime())) return;
      
      const monthKey = date.toISOString().substr(0, 7);
      if (!monthlyData[monthKey]) monthlyData[monthKey] = 0;
      monthlyData[monthKey] += parseFloat(distance) || 0;
    }
  });
  
  const monthly = Object.entries(monthlyData)
    .sort(([a], [b]) => a.localeCompare(b))
    .slice(-6)
    .map(([monthKey, distance]) => ({
      month: new Date(monthKey + '-02').toLocaleDateString('en', { month: 'short' }),
      distance: Math.round(distance * 100) / 100
    }));
    
  return { total: Math.round(total * 100) / 100, monthly };
}

/**
 * Calculate delivery performance from ROSTERS
 * ✅ FIX: Use rosters as data source
 */
function calculateDeliveryStatsFromRosters(rosters = []) {
  const checkStatus = (item, statuses) => {
    if (!item.status || typeof item.status !== 'string') return false;
    return statuses.includes(item.status.trim().toLowerCase());
  };
  
  const completedRosters = rosters.filter(roster => checkStatus(roster, ['completed', 'delivered']));
  if (completedRosters.length === 0) return { onTime: 0, delayed: 0 };
  
  let onTime = 0;
  let delayed = 0;
  
  completedRosters.forEach(roster => {
    // For rosters, we consider them on-time if completed
    // You can add more sophisticated logic here if needed
    onTime++;
  });
  
  return { onTime, delayed };
}

/**
 * Calculate top routes from ROSTERS
 * ✅ FIX: Use rosters as data source
 */
function calculateTopRoutesFromRosters(rosters = [], limit = 3) {
  const routeCount = {};
  
  rosters.forEach(roster => {
    const pickup = roster.loginPickupAddress || roster.pickupLocation || 'Pickup Location';
    const dropoff = roster.officeLocation || roster.dropLocation || 'Office Location';
    
    if (pickup && dropoff) {
      const route = `${pickup} → ${dropoff}`;
      routeCount[route] = (routeCount[route] || 0) + 1;
    }
  });
  
  return Object.entries(routeCount)
    .sort(([, a], [, b]) => b - a)
    .slice(0, limit)
    .map(([route, count]) => ({ route, count }));
}

/**
 * Get recent trip details for distance summary display
 * Returns the most recent completed trip with vehicle and driver info
 */
function getRecentTripDetails(trips = []) {
  if (!trips || trips.length === 0) return null;
  
  // Filter for completed trips and sort by date (most recent first)
  const completedTrips = trips
    .filter(trip => {
      const status = trip.status?.toLowerCase();
      return status === 'completed' || status === 'delivered';
    })
    .sort((a, b) => {
      const dateA = new Date(a.scheduledDate || a.createdAt || a.startTime || 0);
      const dateB = new Date(b.scheduledDate || b.createdAt || b.startTime || 0);
      return dateB.getTime() - dateA.getTime();
    });
  
  if (completedTrips.length === 0) {
    // If no completed trips, get the most recent trip regardless of status
    const sortedTrips = trips.sort((a, b) => {
      const dateA = new Date(a.scheduledDate || a.createdAt || a.startTime || 0);
      const dateB = new Date(b.scheduledDate || b.createdAt || b.startTime || 0);
      return dateB.getTime() - dateA.getTime();
    });
    
    if (sortedTrips.length > 0) {
      const recentTrip = sortedTrips[0];
      return {
        vehicleNumber: recentTrip.vehicleNumber || recentTrip.vehicleReg || 'N/A',
        driverName: recentTrip.driverName || 'N/A',
        driverPhone: recentTrip.driverPhone || 'N/A',
        distance: recentTrip.actualDistance || recentTrip.distance || 0,
        date: recentTrip.scheduledDate || recentTrip.createdAt || recentTrip.startTime,
        status: recentTrip.status || 'unknown'
      };
    }
    return null;
  }
  
  // Return the most recent completed trip
  const recentTrip = completedTrips[0];
  return {
    vehicleNumber: recentTrip.vehicleNumber || recentTrip.vehicleReg || 'N/A',
    driverName: recentTrip.driverName || 'N/A', 
    driverPhone: recentTrip.driverPhone || 'N/A',
    distance: recentTrip.actualDistance || recentTrip.distance || 0,
    date: recentTrip.scheduledDate || recentTrip.createdAt || recentTrip.startTime,
    status: recentTrip.status || 'completed'
  };
}

// @route   GET /api/customer/stats/profile
// @desc    Get customer profile data
// @access  Private (Customer)
router.get('/profile', async (req, res) => {
  try {
    const userId = req.user.userId;
    
    console.log('📱 Fetching customer profile for user:', userId);
    
    // Find customer in customers collection
    const customer = await req.db.collection('customers').findOne({
      _id: new ObjectId(userId)
    });
    
    if (!customer) {
      return res.status(404).json({
        success: false,
        message: 'Customer profile not found'
      });
    }
    
    // ✅ Handle both flat structure and nested employeeDetails structure
    const employeeDetails = customer.employeeDetails || {};
    
    // Log what we found
    if (customer.employeeDetails) {
      console.log('✅ employeeDetails found:', {
        name: employeeDetails.name,
        email: employeeDetails.email,
        companyName: employeeDetails.companyName,
        department: employeeDetails.department,
        designation: employeeDetails.designation,
        employeeId: employeeDetails.employeeId
      });
    }
    
    // Return customer profile data - prioritize employeeDetails if it exists
    res.json({
      success: true,
      data: {
        id: customer._id.toString(),
        name: employeeDetails.name || customer.name || '',
        email: employeeDetails.email || customer.email || '',
        phoneNumber: employeeDetails.phoneNumber || customer.phoneNumber || '',
        alternativePhone: employeeDetails.alternativePhone || customer.alternativePhone || '',
        companyName: employeeDetails.companyName || customer.companyName || '',
        department: employeeDetails.department || customer.department || '',
        employeeId: employeeDetails.employeeId || customer.employeeId || '',
        designation: employeeDetails.designation || customer.designation || '',
        photoUrl: customer.photoUrl || null,
        role: customer.role || 'customer',
        status: customer.status || 'active',
        organizationId: customer.organizationId || null,
        createdAt: customer.createdAt,
        updatedAt: customer.updatedAt
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching customer profile:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch customer profile'
    });
  }
});

// @route   PUT /api/customer/stats/profile
// @desc    Update customer profile data
// @access  Private (Customer)
router.put('/profile', async (req, res) => {
  try {
    const userId = req.user.userId;
    const {
      name,
      phoneNumber,
      alternativePhone,
      companyName,
      department,
      employeeId,
      designation
    } = req.body;
    
    console.log('📝 Updating customer profile for user:', userId);
    
    // Build update object for both flat and nested structure
    const updateData = {
      updatedAt: new Date()
    };
    
    // Update both root level and employeeDetails for compatibility
    if (name) {
      updateData.name = name;
      updateData['employeeDetails.name'] = name;
    }
    if (phoneNumber) {
      updateData.phoneNumber = phoneNumber;
      updateData['employeeDetails.phoneNumber'] = phoneNumber;
    }
    if (alternativePhone !== undefined) {
      updateData.alternativePhone = alternativePhone;
      updateData['employeeDetails.alternativePhone'] = alternativePhone;
    }
    if (companyName) {
      updateData.companyName = companyName;
      updateData['employeeDetails.companyName'] = companyName;
    }
    if (department) {
      updateData.department = department;
      updateData['employeeDetails.department'] = department;
    }
    if (employeeId !== undefined) {
      updateData.employeeId = employeeId;
      updateData['employeeDetails.employeeId'] = employeeId;
    }
    if (designation !== undefined) {
      updateData.designation = designation;
      updateData['employeeDetails.designation'] = designation;
    }
    
    // Update customer in database
    const result = await req.db.collection('customers').findOneAndUpdate(
      { _id: new ObjectId(userId) },
      { $set: updateData },
      { returnDocument: 'after' }
    );
    
    if (!result) {
      return res.status(404).json({
        success: false,
        message: 'Customer not found'
      });
    }
    
    console.log('✅ Customer profile updated successfully');
    
    // Return data from employeeDetails if it exists, otherwise from root
    const employeeDetails = result.employeeDetails || {};
    
    res.json({
      success: true,
      message: 'Profile updated successfully',
      data: {
        id: result._id.toString(),
        name: employeeDetails.name || result.name,
        email: employeeDetails.email || result.email,
        phoneNumber: employeeDetails.phoneNumber || result.phoneNumber,
        alternativePhone: employeeDetails.alternativePhone || result.alternativePhone,
        companyName: employeeDetails.companyName || result.companyName,
        department: employeeDetails.department || result.department,
        employeeId: employeeDetails.employeeId || result.employeeId,
        designation: employeeDetails.designation || result.designation
      }
    });
    
  } catch (error) {
    console.error('❌ Error updating customer profile:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update customer profile'
    });
  }
});

// @route   GET /api/customer/stats/recent-activities
// @desc    Get recent activities for customer dashboard
// @access  Private (Customer)
router.get('/recent-activities', async (req, res) => {
  try {
    const userId = req.user.userId;
    
    console.log('📊 Fetching recent activities for customer:', userId);
    
    const activities = [];
    const now = new Date();
    const last30Days = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    
    // 1. Recent Trip Completions
    try {
      const recentTrips = await req.db.collection('trips')
        .find({
          customerId: userId,
          status: { $in: ['completed', 'delivered'] },
          $or: [
            { completedAt: { $gte: last30Days } },
            { updatedAt: { $gte: last30Days } }
          ]
        })
        .sort({ completedAt: -1, updatedAt: -1 })
        .limit(10)
        .toArray();
      
      recentTrips.forEach(trip => {
        const timestamp = trip.completedAt || trip.updatedAt || trip.createdAt;
        activities.push({
          id: `trip_${trip._id}`,
          type: 'trip_completion',
          title: 'Trip Completed',
          subtitle: `${trip.pickupLocation?.address || 'Pickup'} to ${trip.dropoffLocation?.address || 'Drop'}`,
          timestamp: timestamp,
          icon: 'check_circle',
          color: 'green',
          priority: 'medium',
          metadata: {
            tripId: trip.tripId,
            distance: trip.actualDistance || trip.distance,
            driverName: trip.driverName
          }
        });
      });
    } catch (error) {
      console.error('Error fetching recent trips:', error);
    }
    
    // 2. Recent Roster Assignments
    try {
      const recentRosters = await req.db.collection('rosters')
        .find({
          userId: userId,
          status: { $in: ['assigned', 'approved'] },
          $or: [
            { assignedAt: { $gte: last30Days } },
            { updatedAt: { $gte: last30Days } }
          ]
        })
        .sort({ assignedAt: -1, updatedAt: -1 })
        .limit(10)
        .toArray();
      
      recentRosters.forEach(roster => {
        const timestamp = roster.assignedAt || roster.updatedAt || roster.createdAt;
        activities.push({
          id: `roster_${roster._id}`,
          type: 'roster_assignment',
          title: 'Roster Assigned',
          subtitle: `${roster.rosterType || 'Roster'} - ${roster.officeLocation || 'Office'}`,
          timestamp: timestamp,
          icon: 'assignment',
          color: 'blue',
          priority: 'high',
          metadata: {
            driverName: roster.driverName,
            vehicleReg: roster.vehicleReg,
            startDate: roster.startDate
          }
        });
      });
    } catch (error) {
      console.error('Error fetching recent rosters:', error);
    }
    
    // 3. Recent SOS Alerts
    try {
      const recentSOS = await req.db.collection('sos_events')
        .find({
          $or: [
            { customerId: userId },
            { customerFirebaseUid: userId }
          ],
          timestamp: { $gte: last30Days }
        })
        .sort({ timestamp: -1 })
        .limit(5)
        .toArray();
      
      recentSOS.forEach(sos => {
        activities.push({
          id: `sos_${sos._id}`,
          type: 'sos_alert',
          title: 'SOS Alert',
          subtitle: `Status: ${sos.status || 'Pending'} - ${sos.location?.address || 'Location'}`,
          timestamp: sos.timestamp,
          icon: 'warning',
          color: 'red',
          priority: 'high',
          metadata: {
            status: sos.status,
            policeStation: sos.nearestPoliceStation?.name
          }
        });
      });
    } catch (error) {
      console.error('Error fetching recent SOS:', error);
    }
    
    // 4. Recent Notifications
    try {
      const recentNotifications = await req.db.collection('notifications')
        .find({
          userId: userId,
          createdAt: { $gte: last30Days },
          type: { $in: ['roster_assigned', 'trip_started', 'trip_completed'] }
        })
        .sort({ createdAt: -1 })
        .limit(5)
        .toArray();
      
      recentNotifications.forEach(notif => {
        activities.push({
          id: `notif_${notif._id}`,
          type: 'notification',
          title: notif.title || 'Notification',
          subtitle: notif.body || notif.message || '',
          timestamp: notif.createdAt,
          icon: 'notifications',
          color: 'purple',
          priority: 'low'
        });
      });
    } catch (error) {
      console.error('Error fetching recent notifications:', error);
    }
    
    // Sort all activities by timestamp (most recent first)
    activities.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
    
    // Limit to top 20 activities
    const limitedActivities = activities.slice(0, 20);
    
    // Add relative time formatting
    const formatRelativeTime = (timestamp) => {
      const now = new Date();
      const activityTime = new Date(timestamp);
      const diffMs = now - activityTime;
      const diffMins = Math.floor(diffMs / (1000 * 60));
      const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
      const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
      
      if (diffMins < 1) return 'Just now';
      if (diffMins < 60) return `${diffMins} min${diffMins > 1 ? 's' : ''} ago`;
      if (diffHours < 24) return `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`;
      if (diffDays < 7) return `${diffDays} day${diffDays > 1 ? 's' : ''} ago`;
      return activityTime.toLocaleDateString();
    };
    
    // Add formatted time to each activity
    limitedActivities.forEach(activity => {
      activity.timeAgo = formatRelativeTime(activity.timestamp);
    });
    
    console.log(`✅ Found ${limitedActivities.length} recent activities for customer`);
    
    res.json({
      success: true,
      data: limitedActivities,
      totalCount: activities.length
    });
    
  } catch (error) {
    console.error('❌ Error fetching customer recent activities:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch recent activities'
    });
  }
});

module.exports = router;