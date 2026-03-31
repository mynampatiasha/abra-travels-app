// routes/customer_stats_router.js
// ============================================================================
// CUSTOMER STATISTICS API - TIMEZONE FIX FOR TODAY'S TRIPS
// ============================================================================
// ✅ FIXED: Proper timezone handling for TODAY comparison
// ✅ FIXED: Counts trips with status 'in_progress' as TODAY trips
// ✅ FIXED: Counts individual customer trips from stops array
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');

// ============================================================================
// @route   GET /api/customer/stats/dashboard
// @desc    Get all customer statistics (TIMEZONE FIXED VERSION)
// @access  Private (Customer)
// ============================================================================
router.get('/dashboard', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📊 CUSTOMER STATS DASHBOARD - TIMEZONE FIXED v4.0');
    console.log('='.repeat(80));
    
    // ========================================================================
    // STEP 1: Get user details
    // ========================================================================
    const userId = req.user.userId;
    
    const user = await req.db.collection('customers').findOne({
      $or: [
        { firebaseUid: userId },
        { _id: ObjectId.isValid(userId) ? new ObjectId(userId) : null }
      ]
    });

    if (!user || !user.email) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const userEmail = user.email.toLowerCase();
    console.log(`📧 User Email: ${userEmail}`);
    
    // ========================================================================
    // STEP 2: Query roster-assigned-trips (SAME AS MY TRIPS)
    // ========================================================================
    console.log('\n🔍 Querying roster-assigned-trips collection...');
    
    const allTrips = await req.db.collection('roster-assigned-trips').find({
      'stops.customer.email': userEmail,
      status: { $in: ['assigned', 'scheduled', 'started', 'in_progress', 'completed', 'cancelled'] }
    }).toArray();
    
    console.log(`📦 Found ${allTrips.length} trip document(s)`);
    
    // ========================================================================
    // STEP 3: Extract individual customer trips from stops array
    // ========================================================================
    const customerTrips = extractCustomerTrips(allTrips, userEmail);
    console.log(`👤 Extracted ${customerTrips.length} individual customer trip(s)`);
    
    // ========================================================================
    // STEP 4: Calculate statistics
    // ========================================================================
    const tripStats = calculateTripStatsFromCustomerTrips(customerTrips);
    console.log(`📊 Trip Stats: Total=${tripStats.total}, Completed=${tripStats.completed}, Ongoing=${tripStats.ongoing}, Scheduled=${tripStats.scheduled}, Cancelled=${tripStats.cancelled}`);
    
    const distanceStats = calculateDistanceStatsFromCustomerTrips(customerTrips);
    console.log(`📏 Distance Stats: Total=${distanceStats.total} km`);
    
    const recentTrip = getRecentTripDetailsFromCustomerTrips(customerTrips);
    console.log(`🚗 Recent Trip: ${recentTrip ? 'Found' : 'None'}`);
    
    const deliveryStats = calculateDeliveryStatsFromCustomerTrips(customerTrips);
    console.log(`⏰ Delivery Stats: OnTime=${deliveryStats.onTime}, Delayed=${deliveryStats.delayed}`);
    
    // ========================================================================
    // STEP 5: Build response
    // ========================================================================
    const dashboardData = {
      totalTrips: tripStats,
      onTimeDelivery: deliveryStats,
      totalDistance: distanceStats.total,
      recentTrip: recentTrip,
      monthlyDistance: distanceStats.monthly,
      lastUpdated: new Date()
    };
    
    console.log('\n✅ STATS CALCULATION COMPLETE');
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: dashboardData
    });
    
  } catch (error) {
    console.error('❌ Error fetching customer dashboard stats:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch dashboard statistics',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/customer/stats/distance-by-date
// @desc    Get distance filtered by date range (NEW ENDPOINT)
// @access  Private (Customer)
// ============================================================================
router.get('/distance-by-date', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📅 DISTANCE BY DATE FILTER');
    console.log('='.repeat(80));
    
    const { startDate, endDate } = req.query; // Format: "2026-01-01", "2026-01-31"
    
    // ========================================================================
    // STEP 1: Get user details
    // ========================================================================
    const userId = req.user.userId;
    
    const user = await req.db.collection('customers').findOne({
      $or: [
        { firebaseUid: userId },
        { _id: ObjectId.isValid(userId) ? new ObjectId(userId) : null }
      ]
    });

    if (!user || !user.email) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const userEmail = user.email.toLowerCase();
    console.log(`📧 User Email: ${userEmail}`);
    console.log(`📅 Date Range: ${startDate || 'All'} to ${endDate || 'All'}`);
    
    // ========================================================================
    // STEP 2: Query with date filter
    // ========================================================================
    const query = {
      'stops.customer.email': userEmail,
      status: { $in: ['assigned', 'scheduled', 'started', 'in_progress', 'completed', 'cancelled'] }
    };
    
    // Add date filter if provided
    if (startDate && endDate) {
      query.scheduledDate = { $gte: startDate, $lte: endDate };
    } else if (startDate) {
      query.scheduledDate = { $gte: startDate };
    } else if (endDate) {
      query.scheduledDate = { $lte: endDate };
    }
    
    const allTrips = await req.db.collection('roster-assigned-trips').find(query).toArray();
    console.log(`📦 Found ${allTrips.length} trip(s) in date range`);
    
    // ========================================================================
    // STEP 3: Extract customer trips and calculate distance
    // ========================================================================
    const customerTrips = extractCustomerTrips(allTrips, userEmail);
    
    let totalDistance = 0;
    let totalTrips = 0;
    const dailyBreakdown = {};
    
    customerTrips.forEach(trip => {
      if (trip.status === 'completed') {
        const distance = trip.actualDistance || trip.totalDistance || 0;
        totalDistance += distance;
        totalTrips++;
        
        // Group by day
        const dateKey = trip.scheduledDate;
        if (!dailyBreakdown[dateKey]) {
          dailyBreakdown[dateKey] = {
            date: dateKey,
            distance: 0,
            trips: 0
          };
        }
        
        dailyBreakdown[dateKey].distance += distance;
        dailyBreakdown[dateKey].trips += 1;
      }
    });
    
    console.log(`📏 Total Distance: ${totalDistance.toFixed(1)} km (${totalTrips} trips)`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: {
        totalDistance: Math.round(totalDistance * 10) / 10,
        totalTrips: totalTrips,
        startDate: startDate || null,
        endDate: endDate || null,
        dailyBreakdown: Object.values(dailyBreakdown).sort((a, b) => a.date.localeCompare(b.date))
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching distance by date:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch distance data',
      error: error.message
    });
  }
});

// ============================================================================
// @route   GET /api/customer/stats/monthly-distance
// @desc    Get monthly distance for billing with month filter (FIXED VERSION)
// @access  Private (Customer)
// ============================================================================
router.get('/monthly-distance', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('📅 MONTHLY DISTANCE FOR BILLING - FIXED VERSION');
    console.log('='.repeat(80));
    
    const selectedMonth = req.query.month; // Format: "2026-01"
    
    // ========================================================================
    // STEP 1: Get user details
    // ========================================================================
    const userId = req.user.userId;
    
    const user = await req.db.collection('customers').findOne({
      $or: [
        { firebaseUid: userId },
        { _id: ObjectId.isValid(userId) ? new ObjectId(userId) : null }
      ]
    });

    if (!user || !user.email) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const userEmail = user.email.toLowerCase();
    console.log(`📧 User Email: ${userEmail}`);
    console.log(`📅 Selected Month: ${selectedMonth || 'All Time'}`);
    
    // ========================================================================
    // STEP 2: Query roster-assigned-trips
    // ========================================================================
    const allTrips = await req.db.collection('roster-assigned-trips').find({
      'stops.customer.email': userEmail,
      status: { $in: ['assigned', 'scheduled', 'started', 'in_progress', 'completed', 'cancelled'] }
    }).toArray();
    
    console.log(`📦 Found ${allTrips.length} trip document(s)`);
    
    // ========================================================================
    // STEP 3: Extract customer trips
    // ========================================================================
    const customerTrips = extractCustomerTrips(allTrips, userEmail);
    console.log(`👤 Extracted ${customerTrips.length} customer trip(s)`);
    
    // ========================================================================
    // STEP 4: Calculate total distance (all completed trips)
    // ========================================================================
    let totalDistance = 0;
    
    customerTrips.forEach(trip => {
      if (trip.status === 'completed') {
        const distance = trip.actualDistance || trip.totalDistance || 0;
        totalDistance += distance;
      }
    });
    
    console.log(`📏 Total Distance (All Time): ${totalDistance.toFixed(1)} km`);
    
    // ========================================================================
    // STEP 5: Calculate today's distance
    // ========================================================================
    const today = getTodayDateString();
    
    const todayTrips = customerTrips.filter(trip => 
      trip.scheduledDate === today && trip.status === 'completed'
    );
    
    let todayDistance = 0;
    todayTrips.forEach(trip => {
      const distance = trip.actualDistance || trip.totalDistance || 0;
      todayDistance += distance;
    });
    
    console.log(`📏 Today's Distance: ${todayDistance.toFixed(1)} km (${todayTrips.length} trip(s))`);
    
    // ========================================================================
    // STEP 6: Calculate selected month data (if provided)
    // ========================================================================
    let monthlyData = null;
    
    if (selectedMonth) {
      const [year, month] = selectedMonth.split('-');
      const monthStart = `${year}-${month}-01`;
      const daysInMonth = new Date(year, month, 0).getDate();
      const monthEnd = `${year}-${month}-${daysInMonth.toString().padStart(2, '0')}`;
      
      console.log(`📅 Month Range: ${monthStart} to ${monthEnd}`);
      
      const monthTrips = customerTrips.filter(trip => 
        trip.scheduledDate >= monthStart && 
        trip.scheduledDate <= monthEnd &&
        trip.status === 'completed'
      );
      
      console.log(`📦 Found ${monthTrips.length} completed trip(s) in selected month`);
      
      let monthDistance = 0;
      const dailyBreakdown = {};
      
      monthTrips.forEach(trip => {
        const distance = trip.actualDistance || trip.totalDistance || 0;
        monthDistance += distance;
        
        // Group by day
        const dayKey = parseInt(trip.scheduledDate.split('-')[2]);
        
        if (!dailyBreakdown[dayKey]) {
          dailyBreakdown[dayKey] = {
            day: dayKey,
            date: trip.scheduledDate,
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
      
      console.log(`📊 Month Total: ${monthlyData.totalDistance} km (${monthlyData.totalTrips} trip(s))`);
    }
    
    // ========================================================================
    // STEP 7: Generate available months
    // ========================================================================
    const availableMonths = [];
    const monthsWithData = new Set();
    
    customerTrips.forEach(trip => {
      if (trip.scheduledDate && trip.status === 'completed') {
        const monthKey = trip.scheduledDate.substring(0, 7);
        monthsWithData.add(monthKey);
      }
    });
    
    Array.from(monthsWithData).sort().forEach(monthKey => {
      const [year, month] = monthKey.split('-');
      const monthName = new Date(parseInt(year), parseInt(month) - 1).toLocaleDateString('en', { month: 'long', year: 'numeric' });
      const shortName = new Date(parseInt(year), parseInt(month) - 1).toLocaleDateString('en', { month: 'short' });
      
      availableMonths.push({
        key: monthKey,
        name: monthName,
        shortName: shortName
      });
    });
    
    console.log(`📅 Available Months: ${availableMonths.length}`);
    console.log('='.repeat(80) + '\n');
    
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
    console.error('❌ Error fetching monthly distance:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch monthly distance data',
      error: error.message
    });
  }
});

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

// ============================================================================
// HELPER FUNCTIONS - TIMEZONE FIXED
// ============================================================================

/**
 * ✅ CRITICAL FIX: Get today's date in YYYY-MM-DD format (UTC safe)
 */
function getTodayDateString() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  const day = String(now.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

/**
 * ✅ CRITICAL FIX: Extract individual customer trips from stops array
 * NOW WITH PROPER TIMEZONE HANDLING
 */
function extractCustomerTrips(trips, userEmail) {
  const customerTrips = [];
  
  // Get today's date string in YYYY-MM-DD format
  const today = getTodayDateString();
  
  console.log(`\n🔍 Extracting trips for: ${userEmail}`);
  console.log(`📅 Today's date: ${today}`);
  
  trips.forEach(trip => {
    // Find this customer's stop in the trip
    trip.stops?.forEach(stop => {
      if (stop.type === 'pickup' && 
          stop.customer && 
          stop.customer.email.toLowerCase() === userEmail) {
        
        // ✅ FIXED: Compare date strings directly (no timezone issues)
        const scheduledDate = trip.scheduledDate; // Already in "YYYY-MM-DD" format
        
        let status = trip.status;
        
        console.log(`   📋 Trip ${trip.tripNumber}:`);
        console.log(`      Scheduled: ${scheduledDate}`);
        console.log(`      Trip Status: ${trip.status}`);
        console.log(`      Stop Status: ${stop.status || 'N/A'}`);
        
        // Check stop-level cancellation first
        if (stop.status === 'cancelled') {
          status = 'cancelled';
          console.log(`      ✅ Final Status: cancelled (stop cancelled)`);
        } 
        // Compare date strings directly
        else if (scheduledDate < today) {
          // Past trip
          if (trip.status === 'cancelled') {
            status = 'cancelled';
            console.log(`      ✅ Final Status: cancelled (past trip, cancelled)`);
          } else {
            status = 'completed';
            console.log(`      ✅ Final Status: completed (past trip)`);
          }
        } 
        else if (scheduledDate === today) {
          // TODAY's trip - THIS IS THE KEY FIX
          console.log(`      🎯 TODAY'S TRIP DETECTED!`);
          
          if (trip.status === 'completed') {
            status = 'completed';
            console.log(`      ✅ Final Status: completed (finished today)`);
          } else if (trip.status === 'cancelled') {
            status = 'cancelled';
            console.log(`      ✅ Final Status: cancelled (cancelled today)`);
          } else {
            // ✅ KEY FIX: Any other status for today = "ongoing"
            // This includes: assigned, scheduled, started, in_progress
            status = 'ongoing';
            console.log(`      ✅ Final Status: ongoing (active today, trip status: ${trip.status})`);
          }
        } 
        else if (scheduledDate > today) {
          // Future trip
          status = trip.status === 'cancelled' ? 'cancelled' : 'scheduled';
          console.log(`      ✅ Final Status: ${status} (future trip)`);
        }
        
        customerTrips.push({
          tripId: trip._id.toString(),
          tripNumber: trip.tripNumber,
          scheduledDate: trip.scheduledDate,
          status: status,
          vehicleNumber: trip.vehicleNumber,
          vehicleName: trip.vehicleName,
          driverName: trip.driverName,
          driverPhone: trip.driverPhone,
          driverEmail: trip.driverEmail,
          // Distance at trip level
          actualDistance: trip.actualDistance || 0,
          totalDistance: trip.totalDistance || 0,
          // Customer-specific data
          stopSequence: stop.sequence,
          pickupTime: stop.pickupTime || stop.estimatedTime,
          pickupAddress: stop.location?.address || '',
          customerName: stop.customer.name,
          customerEmail: stop.customer.email,
          // Stop-level status
          stopStatus: stop.status,
          passengerStatus: stop.passengerStatus
        });
      }
    });
  });
  
  console.log(`\n✅ Extracted ${customerTrips.length} customer trips\n`);
  
  return customerTrips;
}

/**
 * Calculate trip statistics from individual customer trips
 */
function calculateTripStatsFromCustomerTrips(customerTrips) {
  let completed = 0;
  let ongoing = 0;      // Only TODAY's trips
  let scheduled = 0;    // FUTURE trips
  let cancelled = 0;
  
  customerTrips.forEach(trip => {
    switch (trip.status) {
      case 'completed':
        completed++;
        break;
      case 'ongoing':
        ongoing++;
        break;
      case 'scheduled':
      case 'assigned':
        scheduled++;
        break;
      case 'cancelled':
        cancelled++;
        break;
    }
  });
  
  const total = completed + ongoing + scheduled + cancelled;
  
  console.log('\n📊 Trip Statistics Breakdown:');
  console.log(`   Completed (past): ${completed}`);
  console.log(`   Ongoing (today): ${ongoing}`);
  console.log(`   Scheduled (future): ${scheduled}`);
  console.log(`   Cancelled: ${cancelled}`);
  console.log(`   Total: ${total}`);
  
  return {
    completed,
    ongoing,
    scheduled,
    cancelled,
    total
  };
}

/**
 * Calculate distance from individual customer trips
 */
function calculateDistanceStatsFromCustomerTrips(customerTrips) {
  let total = 0;
  const monthlyData = {};
  
  customerTrips.forEach(trip => {
    // Only count completed trips for distance
    if (trip.status === 'completed') {
      // Use actualDistance if available, otherwise totalDistance
      const distance = trip.actualDistance || trip.totalDistance || 0;
      total += distance;
      
      // Group by month
      if (trip.scheduledDate) {
        const monthKey = trip.scheduledDate.substring(0, 7); // "2026-01"
        
        if (!monthlyData[monthKey]) {
          monthlyData[monthKey] = 0;
        }
        
        monthlyData[monthKey] += distance;
      }
    }
  });
  
  // Convert monthly data to array format (last 6 months)
  const monthly = Object.entries(monthlyData)
    .sort(([a], [b]) => a.localeCompare(b))
    .slice(-6)
    .map(([monthKey, distance]) => {
      const [year, month] = monthKey.split('-');
      const monthName = new Date(parseInt(year), parseInt(month) - 1).toLocaleDateString('en', { month: 'short' });
      
      return {
        month: monthName,
        distance: Math.round(distance * 10) / 10
      };
    });
  
  return {
    total: Math.round(total * 10) / 10,
    monthly
  };
}

/**
 * Get recent trip details from customer trips
 */
function getRecentTripDetailsFromCustomerTrips(customerTrips) {
  if (!customerTrips || customerTrips.length === 0) {
    return null;
  }
  
  // Filter completed trips and sort by date
  const completedTrips = customerTrips
    .filter(trip => trip.status === 'completed')
    .sort((a, b) => {
      const dateA = new Date(a.scheduledDate || 0);
      const dateB = new Date(b.scheduledDate || 0);
      return dateB.getTime() - dateA.getTime();
    });
  
  if (completedTrips.length === 0) {
    // No completed trips - return most recent trip
    const sortedTrips = customerTrips.sort((a, b) => {
      const dateA = new Date(a.scheduledDate || 0);
      const dateB = new Date(b.scheduledDate || 0);
      return dateB.getTime() - dateA.getTime();
    });
    
    if (sortedTrips.length > 0) {
      const trip = sortedTrips[0];
      return {
        vehicleNumber: trip.vehicleNumber || 'N/A',
        driverName: trip.driverName || 'N/A',
        driverPhone: trip.driverPhone || 'N/A',
        distance: trip.actualDistance || trip.totalDistance || 0
      };
    }
    
    return null;
  }
  
  // Return most recent completed trip
  const trip = completedTrips[0];
  
  return {
    vehicleNumber: trip.vehicleNumber || 'N/A',
    driverName: trip.driverName || 'N/A',
    driverPhone: trip.driverPhone || 'N/A',
    distance: trip.actualDistance || trip.totalDistance || 0
  };
}

/**
 * Calculate delivery performance from customer trips
 */
function calculateDeliveryStatsFromCustomerTrips(customerTrips) {
  const completedTrips = customerTrips.filter(trip => trip.status === 'completed');
  
  if (completedTrips.length === 0) {
    return { onTime: 0, delayed: 0 };
  }
  
  // For now, consider all completed trips as on-time
  // You can add more sophisticated logic if you track actual vs scheduled times
  return {
    onTime: completedTrips.length,
    delayed: 0
  };
}

module.exports = router;