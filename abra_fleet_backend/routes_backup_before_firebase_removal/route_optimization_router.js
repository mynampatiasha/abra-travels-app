// routes/route_optimization_router.js - Route Optimization Endpoints
// ✅ COMPLETE FIXED VERSION with user-friendly errors
const express = require('express');
const TripModel = require('../models/trip_model');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const { createNotification } = require('../models/notification_model');
const { calculateDistance } = require('../utils/distance_calculator');

// ============================================================================
// ✅ DISTANCE CALCULATION HELPER FUNCTION
// ============================================================================
function calculateDistanceBetweenLocations(location1, location2) {
  try {
    // Handle different location formats
    let coords1, coords2;

    // If locations are strings (addresses), use approximate distance calculation
    if (typeof location1 === 'string' && typeof location2 === 'string') {
      // For now, return a reasonable estimate based on address similarity
      // In production, you'd use a geocoding service to get coordinates
      if (location1.toLowerCase() === location2.toLowerCase()) {
        return 0; // Same location
      }

      // Simple heuristic: estimate 5-15 km for different locations in same city
      const location1Lower = location1.toLowerCase();
      const location2Lower = location2.toLowerCase();

      // Check if both locations contain similar area names
      const commonWords = ['bangalore', 'bengaluru', 'whitefield', 'koramangala', 'indiranagar', 'btm', 'jayanagar'];
      const location1Areas = commonWords.filter(word => location1Lower.includes(word));
      const location2Areas = commonWords.filter(word => location2Lower.includes(word));

      if (location1Areas.length > 0 && location2Areas.length > 0) {
        // Same area, shorter distance
        return Math.random() * 5 + 2; // 2-7 km
      } else {
        // Different areas, longer distance
        return Math.random() * 10 + 8; // 8-18 km
      }
    }

    // If locations have coordinates, use precise calculation
    if (location1 && typeof location1 === 'object' && location1.coordinates) {
      coords1 = location1.coordinates;
    } else if (location1 && typeof location1 === 'object' && location1.latitude) {
      coords1 = { latitude: location1.latitude, longitude: location1.longitude };
    }

    if (location2 && typeof location2 === 'object' && location2.coordinates) {
      coords2 = location2.coordinates;
    } else if (location2 && typeof location2 === 'object' && location2.latitude) {
      coords2 = { latitude: location2.latitude, longitude: location2.longitude };
    }

    if (coords1 && coords2) {
      return calculateDistance(coords1, coords2);
    }

    // Fallback: return reasonable estimate for unknown locations
    return 10; // 10 km default estimate

  } catch (error) {
    console.log(`⚠️  Distance calculation error: ${error.message}`);
    return 10; // 10 km fallback
  }
}

// ============================================================================
// ✅ USER-FRIENDLY ERROR HELPER FUNCTION
// ============================================================================
function getUserFriendlyError(technicalError, customerName) {
  const errorMap = {
    'Roster not found': `❌ ${customerName}: Booking doesn't exist. May have been deleted.`,
    'already assigned': `⚠️  ${customerName}: Already assigned to another vehicle. Unassign first.`,
    'DRIVER_NOT_FOUND': `❌ No driver assigned. Please assign a driver to this vehicle first.`,
    'INSUFFICIENT_CAPACITY': `⚠️  Vehicle is full. Not enough seats available.`,
    'TIME_SLOT_CONFLICT': `⚠️  Time conflict. This slot is already booked.`,
    'Network error': `📡 Connection problem. Check internet and try again.`,
    'timeout': `⏱️  Request timed out. Please try again.`,
    'missing': `❌ ${customerName}: Required information is missing.`,
  };

  const lowerError = technicalError.toLowerCase();
  for (const [key, friendlyMessage] of Object.entries(errorMap)) {
    if (lowerError.includes(key.toLowerCase())) {
      return friendlyMessage;
    }
  }

  return `❌ ${customerName}: Something went wrong. Please try again.`;
}

// @route   POST api/roster/optimize
// @desc    Optimize route assignments for multiple rosters
// @access  Private (Admin/Manager)
router.post('/optimize', verifyToken, async (req, res) => {
  try {
    console.log('🚀 Route optimization request received');
    console.log('Request body:', JSON.stringify(req.body, null, 2));

    const { rosterIds, count } = req.body;

    if (!rosterIds || !Array.isArray(rosterIds) || rosterIds.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'rosterIds array is required'
      });
    }

    const rosters = await req.db.collection('rosters')
      .find({
        _id: { $in: rosterIds.map(id => new ObjectId(id)) },
        status: 'pending_assignment'
      })
      .toArray();

    if (rosters.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'No pending rosters found'
      });
    }

    console.log(`📋 Found ${rosters.length} rosters to optimize`);

    const drivers = await req.db.collection('users')
      .find({
        role: 'driver',
        status: 'active',
        isAvailable: { $ne: false }
      })
      .toArray();

    if (drivers.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'No available drivers found'
      });
    }

    console.log(`🚗 Found ${drivers.length} available drivers`);

    const rostersByOffice = {};
    rosters.forEach(roster => {
      const office = roster.officeLocation || 'Unknown';
      if (!rostersByOffice[office]) {
        rostersByOffice[office] = [];
      }
      rostersByOffice[office].push(roster);
    });

    console.log(`🏢 Grouped into ${Object.keys(rostersByOffice).length} office locations`);

    const assignments = [];
    const usedDriverIds = new Set();

    for (const [office, officeRosters] of Object.entries(rostersByOffice)) {
      console.log(`\n🏢 Processing office: ${office} (${officeRosters.length} rosters)`);

      for (let i = 0; i < officeRosters.length; i++) {
        const roster = officeRosters[i];

        const availableDriver = drivers.find(d => !usedDriverIds.has(d._id.toString()));

        if (!availableDriver) {
          console.log(`⚠️  No more drivers available for roster ${roster._id}`);
          continue;
        }

        const officeTime = roster.startTime || '09:00';
        const distance = 10 + (i * 2);
        const travelTime = Math.round(distance * 3);
        const bufferMinutes = 15 + (i * 2);

        const [hours, minutes] = officeTime.split(':').map(Number);
        const officeDateTime = new Date();
        officeDateTime.setHours(hours, minutes, 0, 0);

        const pickupDateTime = new Date(officeDateTime.getTime() - (travelTime + bufferMinutes) * 60000);
        const pickupTime = `${String(pickupDateTime.getHours()).padStart(2, '0')}:${String(pickupDateTime.getMinutes()).padStart(2, '0')}`;

        const assignment = {
          rosterId: roster._id.toString(),
          customerName: roster.customerName || roster.employeeDetails?.name || 'Unknown',
          customerEmail: roster.customerEmail || roster.employeeDetails?.email || '',
          driverId: availableDriver._id.toString(),
          driverName: availableDriver.name || 'Unknown Driver',
          driverEmail: availableDriver.email || '',
          distance: distance,
          travelTime: travelTime,
          officeLocation: office,
          officeTime: officeTime,
          pickupTime: pickupTime,
          bufferMinutes: bufferMinutes,
          rosterType: roster.rosterType || 'both'
        };

        assignments.push(assignment);
        usedDriverIds.add(availableDriver._id.toString());

        console.log(`✅ Assigned ${availableDriver.name} to ${assignment.customerName}`);
        console.log(`   📍 Distance: ${distance}km, Travel: ${travelTime}min`);
        console.log(`   ⏰ Pickup: ${pickupTime}, Office: ${officeTime}, Buffer: ${bufferMinutes}min`);
      }
    }

    console.log(`\n✅ Optimization complete: ${assignments.length} assignments created`);

    res.json({
      success: true,
      message: `Successfully optimized ${assignments.length} route assignments`,
      data: {
        assignments,
        totalRosters: rosters.length,
        assignedCount: assignments.length,
        availableDrivers: drivers.length
      }
    });

  } catch (error) {
    console.error('❌ Route optimization error:', error);
    res.status(500).json({
      success: false,
      message: 'Route optimization failed',
      error: error.message
    });
  }
});

// @route   POST api/roster/assign-bulk
// @desc    Bulk assign drivers to rosters with notifications
// @access  Private (Admin/Manager)
router.post('/assign-bulk', verifyToken, async (req, res) => {
  try {
    console.log('📦 Bulk assignment request received');
    console.log('Request body:', JSON.stringify(req.body, null, 2));

    const { assignments } = req.body;

    if (!assignments || !Array.isArray(assignments) || assignments.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'assignments array is required'
      });
    }

    const results = [];
    const errors = [];

    for (const assignment of assignments) {
      try {
        const { rosterId, driverId, pickupTime, officeTime, distance, travelTime, bufferMinutes } = assignment;

        if (!rosterId || !driverId) {
          errors.push({
            rosterId,
            error: 'Missing rosterId or driverId'
          });
          continue;
        }

        const updateResult = await req.db.collection('rosters').findOneAndUpdate(
          { _id: new ObjectId(rosterId), status: 'pending_assignment' },
          {
            $set: {
              driverId: driverId,
              status: 'assigned',
              assignedAt: new Date(),
              assignedBy: req.user.userId,
              optimizedPickupTime: pickupTime,
              optimizedOfficeTime: officeTime,
              estimatedDistance: distance,
              estimatedTravelTime: travelTime,
              bufferMinutes: bufferMinutes,
              updatedAt: new Date()
            }
          },
          { returnDocument: 'after' }
        );

        if (!updateResult.value) {
          errors.push({
            rosterId,
            error: 'Roster not found or already assigned'
          });
          continue;
        }

        const roster = updateResult.value;

        const driver = await req.db.collection('users').findOne({
          _id: new ObjectId(driverId)
        });

        if (!driver) {
          errors.push({
            rosterId,
            error: 'Driver not found'
          });
          continue;
        }

        try {
          await createNotification(req.db, {
            userId: roster.customerId || roster.customerEmail,
            title: 'Driver Assigned',
            message: `Driver ${driver.name} has been assigned to your trip. Pickup time: ${pickupTime}`,
            type: 'roster_assignment',
            data: {
              rosterId: roster._id.toString(),
              driverId: driver._id.toString(),
              driverName: driver.name,
              pickupTime: pickupTime,
              officeTime: officeTime,
              distance: distance,
              travelTime: travelTime
            },
            priority: 'high',
            category: 'roster'
          });

          console.log(`✅ Customer notification sent for roster ${rosterId}`);
        } catch (notifError) {
          console.log(`⚠️  Customer notification failed for roster ${rosterId}:`, notifError.message);
        }

        try {
          await createNotification(req.db, {
            userId: driver.email || driver._id.toString(),
            title: 'New Assignment',
            message: `You have been assigned to pick up ${roster.customerName || 'customer'} at ${pickupTime}`,
            type: 'driver_assignment',
            data: {
              rosterId: roster._id.toString(),
              customerName: roster.customerName,
              pickupTime: pickupTime,
              officeLocation: roster.officeLocation,
              distance: distance,
              travelTime: travelTime
            },
            priority: 'high',
            category: 'roster'
          });

          console.log(`✅ Driver notification sent to ${driver.name}`);
        } catch (notifError) {
          console.log(`⚠️  Driver notification failed for driver ${driverId}:`, notifError.message);
        }

        results.push({
          rosterId: roster._id.toString(),
          status: 'success',
          driverName: driver.name,
          customerName: roster.customerName
        });

        console.log(`✅ Successfully assigned roster ${rosterId} to driver ${driver.name}`);

      } catch (assignError) {
        console.error(`❌ Error assigning roster ${assignment.rosterId}:`, assignError);
        errors.push({
          rosterId: assignment.rosterId,
          error: assignError.message
        });
      }
    }

    console.log(`\n✅ Bulk assignment complete: ${results.length} successful, ${errors.length} failed`);

    res.json({
      success: true,
      message: `Bulk assignment completed: ${results.length} successful, ${errors.length} failed`,
      data: {
        successful: results,
        failed: errors,
        totalProcessed: assignments.length,
        successCount: results.length,
        errorCount: errors.length
      }
    });

  } catch (error) {
    console.error('❌ Bulk assignment error:', error);
    res.status(500).json({
      success: false,
      message: 'Bulk assignment failed',
      error: error.message
    });
  }
});

// @route   GET api/roster/drivers/available
// @desc    Get list of available drivers for route optimization
// @access  Private (Admin/Manager)
router.get('/drivers/available', verifyToken, async (req, res) => {
  try {
    console.log('🚗 Fetching available drivers...');

    const drivers = await req.db.collection('users')
      .find({
        role: 'driver',
        status: 'active',
        isAvailable: { $ne: false }
      })
      .project({
        _id: 1,
        name: 1,
        email: 1,
        phone: 1,
        currentLocation: 1,
        isAvailable: 1
      })
      .toArray();

    console.log(`✅ Found ${drivers.length} available drivers`);

    res.json({
      success: true,
      message: 'Available drivers retrieved successfully',
      data: drivers,
      count: drivers.length
    });

  } catch (error) {
    console.error('❌ Error fetching available drivers:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch available drivers',
      error: error.message
    });
  }
});

// @route   POST api/roster/compatible-vehicles
// @desc    Get list of compatible vehicles for given customers (WITH MULTI-TRIP VALIDATION)
// @access  Private (Admin/Manager)
router.post('/compatible-vehicles', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🔍 FINDING COMPATIBLE VEHICLES WITH MULTI-TRIP VALIDATION');
    console.log('='.repeat(80));

    const { rosterIds } = req.body;

    if (!rosterIds || !Array.isArray(rosterIds) || rosterIds.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'rosterIds array is required'
      });
    }

    console.log(`📋 Checking compatibility for ${rosterIds.length} customers`);

    // STEP 1: Get roster details
    const rosters = await req.db.collection('rosters')
      .find({
        _id: { $in: rosterIds.map(id => new ObjectId(id)) }
      })
      .toArray();

    if (rosters.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'No rosters found'
      });
    }

    // Extract customer information
    const customerEmails = new Set();
    const customerCompanies = new Set();
    const customerShifts = new Set();
    const customerLoginTimes = new Set();
    const customerLogoutTimes = new Set();
    const customerRosterTypes = new Set();

    console.log('\n📊 Customer Details:');
    rosters.forEach((roster, idx) => {
      const email = roster.customerEmail || roster.employeeDetails?.email || '';
      const emailDomain = email.includes('@') ? email.split('@')[1].toLowerCase() : 'unknown';
      const company = emailDomain.split('.')[0];

      customerEmails.add(email);
      customerCompanies.add(company);
      customerShifts.add(roster.shift || roster.shiftType || 'Unknown');
      customerLoginTimes.add(roster.startTime || roster.officeTime || roster.loginTime || 'Unknown');
      customerLogoutTimes.add(roster.endTime || roster.officeEndTime || roster.logoutTime || 'Unknown');
      customerRosterTypes.add(roster.rosterType || 'both');

      console.log(`   ${idx + 1}. ${roster.customerName || 'Unknown'}`);
      console.log(`      📧 Email: ${email}`);
      console.log(`      🏢 Company: ${company}`);
      console.log(`      🕐 Login: ${roster.startTime || 'Unknown'}`);
      console.log(`      🕔 Logout: ${roster.endTime || 'Unknown'}`);
      console.log(`      📋 Type: ${roster.rosterType || 'both'}`);
    });

    console.log(`\n📊 Required Criteria:`);
    console.log(`   🏢 Companies: ${Array.from(customerCompanies).join(', ')}`);
    console.log(`   🕐 Login Times: ${Array.from(customerLoginTimes).join(', ')}`);
    console.log(`   🕔 Logout Times: ${Array.from(customerLogoutTimes).join(', ')}`);

    // STEP 2: Get ALL active vehicles
    const allVehicles = await req.db.collection('vehicles')
      .find({
        status: { $regex: /^active$/i }
      })
      .toArray();

    console.log(`\n🚗 Found ${allVehicles.length} active vehicles`);
    console.log('🔍 Checking compatibility...\n');

    // Initialize TripModel for timing validation
    const tripModel = new TripModel(req.db);
    const scheduledDate = new Date().toISOString().split('T')[0];

    const compatibleVehicles = [];
    const incompatibleVehicles = [];

    // STEP 3: Check each vehicle
    for (const vehicle of allVehicles) {
      const vehicleName = vehicle.registrationNumber || vehicle.vehicleId || 'Vehicle';
      const vehicleId = vehicle._id.toString();

      console.log(`\n🚗 Checking: ${vehicleName}`);

      // CHECK 1: Driver Assignment
      let hasDriver = false;

      if (vehicle.assignedDriver) {
        if (typeof vehicle.assignedDriver === 'object' && vehicle.assignedDriver !== null) {
          if (vehicle.assignedDriver.name || vehicle.assignedDriver.driverId || vehicle.assignedDriver._id) {
            hasDriver = true;
          }
        } else if (typeof vehicle.assignedDriver === 'string' && vehicle.assignedDriver.trim() !== '') {
          hasDriver = true;
        }
      } else if (vehicle.driverId && vehicle.driverId.toString().trim() !== '') {
        hasDriver = true;
      }

      console.log(`   👨‍✈️ Driver: ${hasDriver ? 'Assigned' : 'NOT ASSIGNED'}`);

      if (!hasDriver) {
        console.log(`   ❌ INCOMPATIBLE - No driver assigned`);
        incompatibleVehicles.push({
          ...vehicle,
          assignedCustomers: [],
          compatibilityReason: 'No driver assigned to this vehicle',
          isCompatible: false,
          requiresAction: 'Assign a driver first'
        });
        continue;
      }

      // CHECK 2: Existing Assignments
      const existingAssignments = await req.db.collection('rosters').find({
        vehicleId: vehicleId,
        status: 'assigned',
        assignedAt: { $gte: new Date(new Date().setHours(0, 0, 0, 0)) }
      }).toArray();

      console.log(`   📋 Existing assignments: ${existingAssignments.length}`);

      if (existingAssignments.length === 0) {
        console.log(`   ✅ COMPATIBLE - No existing assignments`);
        compatibleVehicles.push({
          ...vehicle,
          assignedCustomers: [],
          compatibilityReason: 'No existing assignments',
          isCompatible: true
        });
        continue;
      }

      // CHECK 3: Company Compatibility
      const existingCompanies = new Set();

      existingAssignments.forEach(roster => {
        const email = roster.customerEmail || roster.employeeDetails?.email || '';
        const emailDomain = email.includes('@') ? email.split('@')[1].toLowerCase() : 'unknown';
        const company = emailDomain.split('.')[0];
        existingCompanies.add(company);
      });

      console.log(`   🏢 Existing companies: ${Array.from(existingCompanies).join(', ')}`);

      const companiesMatch = Array.from(customerCompanies).every(company =>
        existingCompanies.has(company)
      );

      if (!companiesMatch) {
        console.log(`   ❌ INCOMPATIBLE - Company mismatch`);
        incompatibleVehicles.push({
          ...vehicle,
          assignedCustomers: existingAssignments.map(r => r._id.toString()),
          compatibilityReason: `Company mismatch: Vehicle serves ${Array.from(existingCompanies).join(', ')}, but customers are from ${Array.from(customerCompanies).join(', ')}`,
          isCompatible: false,
          requiresAction: 'Choose a vehicle serving the same company'
        });
        continue;
      }

      // CHECK 4: Capacity
      const totalSeats = vehicle.capacity?.passengers ||
        vehicle.seatCapacity ||
        vehicle.seatingCapacity ||
        4;

      const assignedSeats = existingAssignments.length;
      const availableSeats = totalSeats - 1 - assignedSeats;

      console.log(`   💺 Seats: ${totalSeats} total, ${assignedSeats} assigned, ${availableSeats} available`);
      console.log(`   📋 Need: ${rosters.length} seats`);

      if (availableSeats <= 0) {
        console.log(`   ❌ INCOMPATIBLE - Vehicle is full`);
        incompatibleVehicles.push({
          ...vehicle,
          assignedCustomers: existingAssignments.map(r => r._id.toString()),
          compatibilityReason: `Vehicle is full: ${assignedSeats} customers already assigned`,
          isCompatible: false,
          requiresAction: 'Choose a different vehicle with available seats'
        });
        continue;
      }

      if (availableSeats < rosters.length) {
        console.log(`   ❌ INCOMPATIBLE - Insufficient capacity`);
        incompatibleVehicles.push({
          ...vehicle,
          assignedCustomers: existingAssignments.map(r => r._id.toString()),
          compatibilityReason: `Insufficient capacity: ${availableSeats} seats available, ${rosters.length} needed`,
          isCompatible: false,
          requiresAction: `Choose a vehicle with at least ${rosters.length} available seats`
        });
        continue;
      }

      // ✅ CHECK 5: MULTI-TRIP TIMING VALIDATION USING TRIPMODEL
      console.log(`   ⏰ Checking multi-trip timing conflicts...`);

      const timingConflicts = [];

      for (const roster of rosters) {
        const loginTime = roster.startTime || roster.loginTime || roster.officeTime || '09:00';
        const logoutTime = roster.endTime || roster.logoutTime || roster.officeEndTime || '18:00';
        const type = roster.rosterType || 'both';
        const customerName = roster.customerName || 'Unknown';

        // Check LOGIN trip timing
        if (type === 'login' || type === 'both') {
          // Calculate pickup start time (1 hour before office time)
          const [hours, minutes] = loginTime.split(':').map(Number);
          const pickupHour = Math.max(0, hours - 1);
          const pickupStartTime = `${String(pickupHour).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
          const pickupEndTime = loginTime;

          console.log(`      Checking LOGIN: ${customerName} (${pickupStartTime} - ${pickupEndTime})`);

          try {
            const validation = await tripModel.canVehicleTakeTrip(
              vehicleId,
              scheduledDate,
              pickupStartTime,
              pickupEndTime
            );

            if (!validation.canTakeTrip) {
              console.log(`         ❌ CONFLICT: ${validation.reason}`);
              timingConflicts.push({
                customerName,
                tripType: 'login',
                timeSlot: `${pickupStartTime} - ${pickupEndTime}`,
                officeTime: loginTime,
                reason: validation.reason,
                conflictingTrip: validation.conflictingTrip ? {
                  tripNumber: validation.conflictingTrip.tripNumber,
                  startTime: validation.conflictingTrip.startTime,
                  endTime: validation.conflictingTrip.endTime
                } : null
              });
            } else {
              console.log(`         ✅ Available (${validation.currentTrips} existing trips)`);
            }
          } catch (err) {
            console.log(`         ⚠️  Validation error: ${err.message}`);
          }
        }

        // Check LOGOUT trip timing
        if (type === 'logout' || type === 'both') {
          // Calculate dropoff end time (1 hour after office end time)
          const [hours, minutes] = logoutTime.split(':').map(Number);
          const dropoffHour = Math.min(23, hours + 1);
          const dropoffStartTime = logoutTime;
          const dropoffEndTime = `${String(dropoffHour).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;

          console.log(`      Checking LOGOUT: ${customerName} (${dropoffStartTime} - ${dropoffEndTime})`);

          try {
            const validation = await tripModel.canVehicleTakeTrip(
              vehicleId,
              scheduledDate,
              dropoffStartTime,
              dropoffEndTime
            );

            if (!validation.canTakeTrip) {
              console.log(`         ❌ CONFLICT: ${validation.reason}`);
              timingConflicts.push({
                customerName,
                tripType: 'logout',
                timeSlot: `${dropoffStartTime} - ${dropoffEndTime}`,
                officeTime: logoutTime,
                reason: validation.reason,
                conflictingTrip: validation.conflictingTrip ? {
                  tripNumber: validation.conflictingTrip.tripNumber,
                  startTime: validation.conflictingTrip.startTime,
                  endTime: validation.conflictingTrip.endTime
                } : null
              });
            } else {
              console.log(`         ✅ Available (${validation.currentTrips} existing trips)`);
            }
          } catch (err) {
            console.log(`         ⚠️  Validation error: ${err.message}`);
          }
        }
      }

      // If any timing conflicts found, mark vehicle as incompatible
      if (timingConflicts.length > 0) {
        console.log(`   ❌ INCOMPATIBLE - ${timingConflicts.length} timing conflict(s)`);
        
        const conflictSummary = timingConflicts.map(c => 
          `${c.customerName} (${c.tripType} at ${c.officeTime}): ${c.reason}`
        ).join('; ');

        incompatibleVehicles.push({
          ...vehicle,
          assignedCustomers: existingAssignments.map(r => r._id.toString()),
          compatibilityReason: `Timing conflicts: ${timingConflicts.length} customer(s) cannot be accommodated`,
          isCompatible: false,
          requiresAction: 'Choose a different vehicle - this one has time conflicts',
          timingConflicts: timingConflicts,
          detailedReason: conflictSummary
        });
        continue;
      }

      // ALL CHECKS PASSED
      console.log(`   ✅ COMPATIBLE - All checks passed`);
      compatibleVehicles.push({
        ...vehicle,
        assignedCustomers: existingAssignments.map(r => r._id.toString()),
        compatibilityReason: `Same company (${Array.from(existingCompanies).join(', ')}), ${availableSeats} seats available, no timing conflicts`,
        isCompatible: true
      });
    }

    console.log('\n' + '='.repeat(80));
    console.log('📊 COMPATIBILITY CHECK RESULTS');
    console.log('='.repeat(80));
    console.log(`✅ Compatible vehicles: ${compatibleVehicles.length}`);
    console.log(`❌ Incompatible vehicles: ${incompatibleVehicles.length}`);
    console.log('='.repeat(80) + '\n');

    // Sort compatible vehicles by best fit
    const customersCount = rosters.length;

    compatibleVehicles.sort((a, b) => {
      const aCapacity = a.capacity?.passengers || a.seatCapacity || a.seatingCapacity || 4;
      const bCapacity = b.capacity?.passengers || b.seatCapacity || b.seatingCapacity || 4;
      const aAvailable = aCapacity - 1;
      const bAvailable = bCapacity - 1;
      const aWaste = aAvailable - customersCount;
      const bWaste = bAvailable - customersCount;

      if (aWaste >= 0 && bWaste >= 0) {
        return aWaste - bWaste;
      }
      if (aWaste >= 0) return -1;
      if (bWaste >= 0) return 1;
      return bCapacity - aCapacity;
    });

    console.log('🎯 SMART VEHICLE SIZING APPLIED');
    console.log(`   Customers to assign: ${customersCount}`);
    if (compatibleVehicles.length > 0) {
      console.log('   Top 3 best-fit vehicles:');
      compatibleVehicles.slice(0, 3).forEach((v, i) => {
        const capacity = v.capacity?.passengers || v.seatCapacity || v.seatingCapacity || 4;
        console.log(`   ${i + 1}. ${v.registrationNumber || v.name}: ${capacity} seats`);
      });
    }
    console.log('');

    res.json({
      success: true,
      message: `Found ${compatibleVehicles.length} compatible vehicles`,
      data: {
        compatible: compatibleVehicles,
        incompatible: incompatibleVehicles,
        customerCriteria: {
          companies: Array.from(customerCompanies),
          shifts: Array.from(customerShifts),
          loginTimes: Array.from(customerLoginTimes),
          logoutTimes: Array.from(customerLogoutTimes),
          rosterTypes: Array.from(customerRosterTypes),
          count: rosters.length
        }
      },
      count: compatibleVehicles.length
    });

  } catch (error) {
    console.error('❌ Error finding compatible vehicles:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to find compatible vehicles',
      error: error.message
    });
  }
});



// @route   POST api/roster/assign-optimized-route
// @desc    Assign optimized route with full notifications and user-friendly errors
// @access  Private (Admin/Manager)
// ✅ COMPLETE FIXED VERSION - With roster existence check
router.post('/assign-optimized-route', verifyToken, async (req, res) => {
  const session = req.mongoClient.startSession();

  try {
    console.log('\n' + '='.repeat(80));
    console.log('🚀 OPTIMIZED ROUTE ASSIGNMENT WITH MULTI-TRIP CREATION');
    console.log('='.repeat(80));

    const { vehicleId, route, totalDistance, totalTime, startTime } = req.body;

    if (!vehicleId || !route || !Array.isArray(route) || route.length === 0) {
      return res.status(400).json({
        success: false,
        message: '❌ Missing required information',
        advice: '💡 Make sure you selected a vehicle and customers to assign.',
        error: 'INVALID_REQUEST'
      });
    }

    console.log(`📋 Processing ${route.length} customer assignments`);
    console.log(`🚗 Vehicle ID: ${vehicleId}`);
    console.log(`📏 Total Distance: ${totalDistance} km`);
    console.log(`⏱️  Total Time: ${totalTime} mins`);
    console.log('-'.repeat(80));

    await session.startTransaction();

    const vehicle = await req.db.collection('vehicles').findOne(
      { _id: new ObjectId(vehicleId) },
      { session }
    );

    if (!vehicle) {
      await session.abortTransaction();
      console.log('❌ Vehicle not found');
      return res.status(404).json({
        success: false,
        message: '❌ Vehicle Not Found',
        advice: '💡 This vehicle may have been deleted. Please refresh the page and try again.',
        error: 'VEHICLE_NOT_FOUND'
      });
    }

    console.log(`✅ Vehicle found: ${vehicle.registrationNumber || vehicle.name || 'Vehicle'}`);

    // Get driver details
    let driver = null;
    let driverIdToSearch = null;

    console.log('🔍 Checking vehicle.assignedDriver format...');
    console.log('   Type:', typeof vehicle.assignedDriver);

    if (vehicle.assignedDriver) {
      if (typeof vehicle.assignedDriver === 'object' && vehicle.assignedDriver.name) {
        console.log('   ✅ Format 1: Complete object with driver details');
        driver = {
          _id: vehicle.assignedDriver._id || vehicle.assignedDriver.driverId,
          name: vehicle.assignedDriver.name,
          email: vehicle.assignedDriver.email || '',
          phone: vehicle.assignedDriver.phone || vehicle.assignedDriver.phoneNumber || ''
        };
      }
      else if (typeof vehicle.assignedDriver === 'string') {
        console.log('   ✅ Format 2: String driver ID');
        driverIdToSearch = vehicle.assignedDriver;
      }
      else if (typeof vehicle.assignedDriver === 'object' && vehicle.assignedDriver.driverId) {
        console.log('   ✅ Format 3: Object with driverId field only');
        driverIdToSearch = vehicle.assignedDriver.driverId;
      }
      else if (typeof vehicle.assignedDriver === 'object' && vehicle.assignedDriver._id) {
        console.log('   ✅ Format 4: Object with _id field only');
        driverIdToSearch = vehicle.assignedDriver._id;
      }
    }

    if (!driver && driverIdToSearch) {
      console.log('   🔍 Searching for driver with ID:', driverIdToSearch);

      try {
        driver = await req.db.collection('drivers').findOne(
          { driverId: driverIdToSearch },
          { session }
        );

        if (driver) {
          console.log('   ✅ Found in drivers collection (by driverId)');
          const firstName = driver.personalInfo?.firstName || driver.firstName || '';
          const lastName = driver.personalInfo?.lastName || driver.lastName || '';
          const fullName = `${firstName} ${lastName}`.trim() || driver.name || 'Unknown Driver';

          driver = {
            _id: driver._id,
            name: fullName,
            email: driver.personalInfo?.email || driver.email || '',
            phone: driver.personalInfo?.phone || driver.phone || driver.phoneNumber || ''
          };
        }
      } catch (e) {
        console.log('   ⚠️  Not found in drivers collection (by driverId)');
      }

      if (!driver && ObjectId.isValid(driverIdToSearch)) {
        try {
          driver = await req.db.collection('drivers').findOne(
            { _id: new ObjectId(driverIdToSearch) },
            { session }
          );

          if (driver) {
            console.log('   ✅ Found in drivers collection (by _id)');
            const firstName = driver.personalInfo?.firstName || driver.firstName || '';
            const lastName = driver.personalInfo?.lastName || driver.lastName || '';
            const fullName = `${firstName} ${lastName}`.trim() || driver.name || 'Unknown Driver';

            driver = {
              _id: driver._id,
              name: fullName,
              email: driver.personalInfo?.email || driver.email || '',
              phone: driver.personalInfo?.phone || driver.phone || driver.phoneNumber || ''
            };
          }
        } catch (e) {
          console.log('   ⚠️  Not found in drivers collection (by _id)');
        }
      }

      if (!driver) {
        try {
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
            console.log('   ✅ Found in users collection');
            driver = {
              _id: driver._id,
              name: driver.name || driver.displayName || 'Unknown Driver',
              email: driver.email || '',
              phone: driver.phone || driver.phoneNumber || ''
            };
          }
        } catch (e) {
          console.log('   ⚠️  Not found in users collection');
        }
      }
    }

    if (!driver) {
      await session.abortTransaction();
      console.log('❌ DRIVER NOT FOUND');

      return res.status(404).json({
        success: false,
        message: '❌ No Driver Assigned',
        advice: '💡 This vehicle doesn\'t have a driver yet.\n\n' +
          'How to fix:\n' +
          '1. Go to Vehicle Management page\n' +
          '2. Find vehicle: ' + (vehicle.registrationNumber || vehicle.name || 'this vehicle') + '\n' +
          '3. Click "Assign Driver"\n' +
          '4. Select a driver from the list\n' +
          '5. Click Save\n' +
          '6. Come back and try assigning customers again',
        error: 'DRIVER_NOT_FOUND',
        details: {
          vehicleId: vehicleId,
          vehicleName: vehicle.registrationNumber || vehicle.name || 'Vehicle',
          assignedDriver: vehicle.assignedDriver
        }
      });
    }

    console.log(`✅ Driver found: ${driver.name}`);
    console.log(`   Email: ${driver.email || 'N/A'}`);
    console.log(`   Phone: ${driver.phone || 'N/A'}`);
    console.log('-'.repeat(80));

    console.log('\n💺 CHECKING VEHICLE CAPACITY...');
    const existingAssignments = await req.db.collection('rosters').find({
      vehicleId: vehicleId,
      status: 'assigned',
      assignedAt: { $gte: new Date(new Date().setHours(0, 0, 0, 0)) }
    }, { session }).toArray();

    const totalSeats = vehicle.capacity?.passengers ||
      vehicle.seatCapacity ||
      vehicle.seatingCapacity ||
      4;
    const currentAssignedCount = existingAssignments.length;
    const newCustomersCount = route.length;
    const availableSeats = totalSeats - 1 - currentAssignedCount;

    console.log(`   🚗 Vehicle: ${vehicle.registrationNumber || vehicle.name || 'Vehicle'}`);
    console.log(`   💺 Total Seats: ${totalSeats}`);
    console.log(`   👥 Currently Assigned: ${currentAssignedCount}`);
    console.log(`   ✅ Available Seats: ${availableSeats}`);
    console.log(`   📋 New Customers: ${newCustomersCount}`);

    if (availableSeats <= 0 || newCustomersCount > availableSeats) {
      await session.abortTransaction();
      console.log(`\n❌ CAPACITY CHECK FAILED`);

      let adviceMessage = '';
      if (availableSeats <= 0) {
        adviceMessage = '💡 This vehicle is already FULL (0 seats available).\n\n' +
          'How to fix:\n' +
          '1. Go to Vehicle Management page\n' +
          '2. Find vehicle: ' + (vehicle.registrationNumber || vehicle.name || 'this vehicle') + '\n' +
          '3. Unassign some customers from this vehicle\n' +
          '4. Come back and try again\n\n' +
          'OR choose a different vehicle with more seats.';
      } else {
        adviceMessage = `💡 Not enough seats!\n\n` +
          `This vehicle has only ${availableSeats} seat(s) available,\n` +
          `but you're trying to assign ${newCustomersCount} customer(s).\n\n` +
          `How to fix:\n` +
          `1. Choose a bigger vehicle (with ${newCustomersCount + 1} or more seats)\n` +
          `OR\n` +
          `2. Split customers into 2 smaller groups and assign separately`;
      }

      return res.status(400).json({
        success: false,
        message: '⚠️  Vehicle Full',
        advice: adviceMessage,
        error: 'INSUFFICIENT_CAPACITY',
        details: {
          totalSeats: totalSeats,
          availableSeats: availableSeats,
          requestedSeats: newCustomersCount,
          vehicleName: vehicle.registrationNumber || vehicle.name || 'Vehicle'
        }
      });
    }

    console.log(`   ✅ Capacity check passed`);

    console.log('\n⏰ CHECKING TIME SLOT CONFLICTS...');
    const scheduledDate = new Date().toISOString().split('T')[0];

    for (const stop of route) {
      const conflicts = await req.db.collection('trips').find({
        vehicleId: vehicleId,
        scheduledDate: scheduledDate,
        status: { $in: ['assigned', 'started', 'in_progress'] },
        $or: [
          { startTime: { $lte: stop.pickupTime }, endTime: { $gt: stop.pickupTime } },
          { startTime: { $lt: stop.pickupTime }, endTime: { $gte: stop.pickupTime } }
        ]
      }, { session }).toArray();

      if (conflicts.length > 0) {
        await session.abortTransaction();
        console.log(`\n❌ TIME SLOT CONFLICT DETECTED`);
        console.log(`   Stop #${stop.sequence}: ${stop.customerName}`);
        console.log(`   Conflicting with: ${conflicts[0].tripNumber}`);

        return res.status(409).json({
          success: false,
          message: `⚠️  Time Slot Conflict`,
          advice: `💡 Customer ${stop.customerName} has a time conflict.\n\n` +
            `This time slot is already booked.\n\n` +
            `Please choose a different time or vehicle.`,
          error: 'TIME_SLOT_CONFLICT',
          conflictingTrip: conflicts[0],
          details: {
            customerName: stop.customerName,
            requestedTime: stop.pickupTime,
            conflictingTripNumber: conflicts[0].tripNumber
          }
        });
      }
    }

    console.log(`   ✅ No time slot conflicts found`);

    const results = [];
    const errors = [];
    const tripIds = [];
    const notificationResults = {
      customers: 0,
      driver: 0,
      failed: 0
    };

    for (const stop of route) {
      try {
        const { rosterId, customerId, customerName, customerEmail, customerPhone, sequence, pickupTime, eta, location } = stop;

        console.log(`\n📍 Processing Stop #${sequence}: ${customerName}`);
        console.log(`   🔑 Roster ID: ${rosterId}`);

        if (!rosterId) {
          console.log(`   ❌ MISSING ROSTER ID`);
          errors.push({
            sequence,
            customerName,
            error: 'Missing rosterId',
            friendlyMessage: `❌ ${customerName}: Missing roster ID`,
            actionRequired: 'Please refresh the page and try again'
          });
          continue;
        }

        // ✅ STEP 1: CHECK IF ROSTER EXISTS
        console.log(`   🔍 STEP 1: Checking if roster exists in database...`);
        
        let existingRoster;
        try {
          existingRoster = await req.db.collection('rosters').findOne(
            { _id: new ObjectId(rosterId) },
            { session }
          );
        } catch (idError) {
          console.log(`   ❌ Invalid Roster ID format: ${idError.message}`);
          errors.push({
            sequence,
            customerName,
            error: 'Invalid roster ID',
            friendlyMessage: `❌ ${customerName}: Invalid booking ID format`,
            actionRequired: 'Contact support'
          });
          continue;
        }

        if (!existingRoster) {
          console.log(`   ❌ ROSTER DELETED - No longer exists in database`);
          errors.push({
            sequence,
            customerName,
            error: 'Roster deleted',
            friendlyMessage: `❌ ${customerName}: This booking was deleted or doesn't exist`,
            actionRequired: 'Refresh the page to see current bookings'
          });
          continue;
        }

        console.log(`   ✅ Roster exists in database`);

        // ✅ STEP 2: CHECK CURRENT STATE
        console.log(`   🔍 STEP 2: Checking current roster state...`);
        console.log(`      📊 Current Status: '${existingRoster.status}'`);
        console.log(`      🚗 vehicleId: ${existingRoster.vehicleId || 'null'}`);
        console.log(`      👤 driverId: ${existingRoster.driverId || 'null'}`);
        console.log(`      🎫 tripId: ${existingRoster.tripId || 'null'}`);

        // ✅ STEP 3: CHECK IF ASSIGNED TO DIFFERENT VEHICLE
        console.log(`   🔍 STEP 3: Checking vehicle assignment...`);
        
        if (existingRoster.vehicleId && existingRoster.vehicleId.toString() !== vehicleId) {
          console.log(`   ⚠️⚠️⚠️ ASSIGNED TO DIFFERENT VEHICLE - SKIPPING ⚠️⚠️⚠️`);
          
          let otherVehicleName = 'Unknown Vehicle';
          try {
            const otherVehicle = await req.db.collection('vehicles').findOne(
              { _id: new ObjectId(existingRoster.vehicleId) },
              { session }
            );
            otherVehicleName = otherVehicle?.registrationNumber || otherVehicle?.vehicleNumber || 'Unknown Vehicle';
          } catch (e) {
            console.log(`      ⚠️  Could not fetch other vehicle: ${e.message}`);
          }
          
          console.log(`      Assigned to vehicle: ${otherVehicleName}`);
          console.log(`      Current driver: ${existingRoster.driverName || 'Unknown'}`);
          
          errors.push({
            sequence,
            customerName,
            error: 'assigned to different vehicle',
            friendlyMessage: `⚠️  ${customerName} is already assigned to vehicle ${otherVehicleName}`,
            actionRequired: 'Go to Vehicle Management → Unassign them → Try again'
          });
          continue;
        }

        console.log(`   ✅ Roster is available for assignment to this vehicle`);

        // ✅ STEP 3.5: CHECK IF ALREADY ASSIGNED TO THIS SAME VEHICLE
        console.log(`   🔍 STEP 3.5: Checking if already assigned to THIS vehicle...`);

        if (existingRoster.vehicleId && 
            existingRoster.vehicleId.toString() === vehicleId &&
            existingRoster.status === 'assigned') {
          console.log(`   ℹ️ℹ️ℹ️  ALREADY ASSIGNED TO THIS VEHICLE ℹ️ℹ️ℹ️`);
          console.log(`      This is NOT an error - roster is correctly assigned`);
          console.log(`      Vehicle: ${vehicle.registrationNumber || vehicle.name}`);
          console.log(`      Driver: ${driver.name}`);
          console.log(`      Status: ${existingRoster.status}`);
          console.log(`      Assigned At: ${existingRoster.assignedAt}`);
          
          // ✅ Count as success (already assigned = mission accomplished!)
          results.push({
            rosterId: rosterId,
            tripId: existingRoster.tripId || 'N/A',
            tripNumber: existingRoster.tripNumber || 'N/A',
            sequence: sequence,
            customerName: customerName,
            status: 'already_assigned',
            friendlyMessage: `✅ ${customerName} (already assigned to this vehicle)`
          });
          
          console.log(`   ✅✅✅ STOP #${sequence} ALREADY ASSIGNED (SUCCESS) ✅✅✅`);
          continue; // Skip to next customer
        }

        console.log(`   ✅ Roster needs assignment - proceeding with database update`);

        // ✅ STEP 4: ATTEMPT DATABASE UPDATE
        console.log(`   🔍 STEP 4: Attempting database update...`);
        console.log(`      Using findOneAndUpdate with _id only (no status filter)`);

        const updateResult = await req.db.collection('rosters').findOneAndUpdate(
          { 
            _id: new ObjectId(rosterId)
            // ✅ No status filter - allows re-assignment
          },
          {
            $set: {
              vehicleId: new ObjectId(vehicleId),
              vehicleNumber: vehicle.registrationNumber || vehicle.name,
              driverId: driver._id.toString(),
              driverName: driver.name,
              driverPhone: driver.phone || '',
              status: 'assigned',
              assignedAt: new Date(),
              assignedBy: req.user.userId,
              pickupSequence: sequence,
              optimizedPickupTime: pickupTime,
              estimatedArrival: new Date(eta),
              pickupLocation: location,
              routeDetails: {
                totalDistance,
                totalTime,
                sequence,
                distanceFromPrevious: stop.distanceFromPrevious,
                estimatedTime: stop.estimatedTime
              },
              updatedAt: new Date()
            }
          },
          { returnDocument: 'after', session }
        );

        if (!updateResult.value) {
          console.log(`   ❌❌❌ UPDATE FAILED - This should NOT happen! ❌❌❌`);
          console.log(`      The roster existed in STEP 1 but update returned null`);
          console.log(`      Possible causes:`);
          console.log(`         1. Roster was deleted between STEP 1 and STEP 4`);
          console.log(`         2. Database lock or transaction issue`);
          console.log(`         3. MongoDB error`);
          
          errors.push({
            sequence,
            customerName,
            error: 'Database update failed',
            friendlyMessage: `❌ ${customerName}: Database rejected the update`,
            actionRequired: 'This booking may be locked. Refresh and try again, or contact support.'
          });
          continue;
        }

        const roster = updateResult.value;
        console.log(`   ✅✅✅ ROSTER UPDATED SUCCESSFULLY ✅✅✅`);

        // ✅ STEP 5: CREATE TRIP
        console.log(`   🔍 STEP 5: Creating trip record...`);

        const tripNumber = `TRIP-${Date.now().toString().slice(-6)}-${sequence.toString().padStart(2, '0')}`;

        const tripData = {
          tripNumber,
          rosterId: rosterId,
          vehicleId: new ObjectId(vehicleId),
          driverId: driver._id.toString(),
          customer: {
            customerId: customerId || customerEmail,
            name: customerName,
            email: customerEmail,
            phone: customerPhone
          },
          pickupLocation: {
            address: location,
            coordinates: null
          },
          dropLocation: {
            address: roster.officeLocation || roster.dropLocation || 'Office',
            coordinates: null
          },
          scheduledDate: scheduledDate,
          startTime: pickupTime,
          endTime: stop.estimatedTime || pickupTime,
          estimatedDuration: stop.estimatedTime || 30,
          distance: stop.distanceFromPrevious || 0,
          tripType: roster.rosterType || 'login',
          sequence: sequence,
          organizationId: roster.organizationId,
          organizationName: roster.organizationName || roster.organization,
          status: 'assigned',
          assignedAt: new Date(),
          actualStartTime: null,
          actualEndTime: null,
          currentLocation: null,
          locationHistory: [],
          actualDistance: null,
          actualDuration: null,
          createdAt: new Date(),
          updatedAt: new Date(),
          createdBy: req.user.userId
        };

        const tripResult = await req.db.collection('trips').insertOne(tripData, { session });
        const tripId = tripResult.insertedId.toString();
        tripIds.push(tripId);

        console.log(`   ✅ Trip created: ${tripNumber} (ID: ${tripId})`);

        // ✅ STEP 6: UPDATE ROSTER WITH TRIP ID
        console.log(`   🔍 STEP 6: Updating roster with trip ID...`);
        
        await req.db.collection('rosters').updateOne(
          { _id: new ObjectId(rosterId) },
          { $set: { tripId: tripId } },
          { session }
        );

        console.log(`   ✅ Roster updated with trip ID`);

        // ✅ STEP 7: SEND NOTIFICATIONS
        console.log(`   🔍 STEP 7: Sending customer notification...`);

        try {
          await createNotification(req.db, {
            userId: customerId || customerEmail,
            title: '🚗 Driver Assigned - Route Optimized!',
            body: `Driver ${driver.name} has been assigned.\n\n` +
              `🚗 Vehicle: ${vehicle.registrationNumber || vehicle.name || 'Vehicle'}\n` +
              `📍 Pickup: Stop #${sequence}\n` +
              `⏰ Time: ${pickupTime}\n` +
              `📏 Distance: ${stop.distanceFromPrevious?.toFixed(1)} km\n\n` +
              `Track your driver in real-time through the app.`,
            type: 'route_assignment',
            data: {
              rosterId: rosterId,
              tripId: tripId,
              tripNumber: tripNumber,
              vehicleId: vehicleId,
              driverId: driver._id.toString(),
              sequence: sequence,
              pickupTime: pickupTime,
              trackingEnabled: true
            },
            priority: 'high',
            category: 'roster'
          });

          console.log(`   ✅ Customer notification sent`);
          notificationResults.customers++;
        } catch (notifError) {
          console.log(`   ⚠️  Customer notification failed: ${notifError.message}`);
          notificationResults.failed++;
        }

        results.push({
          rosterId: rosterId,
          tripId: tripId,
          tripNumber: tripNumber,
          sequence: sequence,
          customerName: customerName,
          status: 'success',
          friendlyMessage: `✅ ${customerName} assigned successfully`
        });

        console.log(`   ✅✅✅ STOP #${sequence} COMPLETED SUCCESSFULLY ✅✅✅`);

      } catch (stopError) {
        console.error(`\n   ❌❌❌ ERROR PROCESSING STOP ❌❌❌`);
        console.error(`   Customer: ${stop.customerName}`);
        console.error(`   Error message: ${stopError.message}`);
        console.error(`   Error stack:`, stopError.stack);

        errors.push({
          sequence: stop.sequence,
          customerName: stop.customerName,
          error: stopError.message,
          friendlyMessage: `❌ ${stop.customerName}: ${stopError.message}`,
          actionRequired: 'Contact support if this continues'
        });
      }
    }

    // ✅ Notify driver only if there were successful assignments
    if (results.length > 0) {
      try {
        console.log(`\n👨‍✈️ Sending notification to driver: ${driver.name}`);

        const driverUserId = driver._id ? driver._id.toString() : driver.email.replace(/\./g, '_');

        await createNotification(req.db, {
          userId: driverUserId,
          title: '🎯 New Optimized Route Assigned',
          body: `You have ${results.length} new customers on your route.\n\n` +
            `🚗 Vehicle: ${vehicle.registrationNumber || vehicle.name || 'Vehicle'}\n` +
            `📏 Distance: ${totalDistance} km\n` +
            `⏱️  Time: ${totalTime} mins\n` +
            `⏰ First Pickup: ${route[0].pickupTime}\n\n` +
            `Check the app for detailed route information.`,
          type: 'driver_route_assignment',
          data: {
            vehicleId: vehicleId,
            totalCustomers: results.length,
            totalDistance: totalDistance,
            totalTime: totalTime,
            tripIds: tripIds,
            trackingRequired: true
          },
          priority: 'high',
          category: 'roster'
        });

        console.log(`✅ Driver notification sent`);
        notificationResults.driver++;
      } catch (notifError) {
        console.log(`⚠️  Driver notification failed: ${notifError.message}`);
        notificationResults.failed++;
      }
    } else {
      console.log(`\nℹ️  Skipping driver notification - no new assignments made`);
    }

    await req.db.collection('vehicles').updateOne(
      { _id: new ObjectId(vehicleId) },
      {
        $push: {
          assignedCustomers: {
            $each: route.map(stop => ({
              rosterId: stop.rosterId,
              tripId: results.find(r => r.rosterId === stop.rosterId)?.tripId,
              customerId: stop.customerId,
              customerName: stop.customerName,
              sequence: stop.sequence,
              pickupTime: stop.pickupTime,
              assignedAt: new Date()
            }))
          }
        },
        $set: {
          lastRouteAssignment: new Date(),
          currentRouteDistance: totalDistance,
          currentRouteTime: totalTime,
          updatedAt: new Date()
        }
      },
      { session }
    );

    await session.commitTransaction();

    // ✅ VERIFICATION STEP
    console.log('\n🔍 VERIFYING ASSIGNMENTS...');
    const verificationResults = [];

    for (const result of results) {
      try {
        const verifiedRoster = await req.db.collection('rosters').findOne({
          _id: new ObjectId(result.rosterId)
        });

        if (verifiedRoster && verifiedRoster.status === 'assigned' && verifiedRoster.vehicleId) {
          console.log(`   ✅ ${result.customerName}: Verified assigned`);
          verificationResults.push({
            rosterId: result.rosterId,
            customerName: result.customerName,
            verified: true
          });
        } else {
          console.log(`   ❌ ${result.customerName}: Assignment verification failed`);
          verificationResults.push({
            rosterId: result.rosterId,
            customerName: result.customerName,
            verified: false,
            issue: 'Assignment not persisted in database'
          });
        }
      } catch (verifyError) {
        console.log(`   ⚠️  ${result.customerName}: Verification error: ${verifyError.message}`);
        verificationResults.push({
          rosterId: result.rosterId,
          customerName: result.customerName,
          verified: false,
          issue: verifyError.message
        });
      }
    }

    const verifiedCount = verificationResults.filter(v => v.verified).length;
    const failedVerification = verificationResults.filter(v => !v.verified);

    console.log('\n' + '='.repeat(80));
    console.log('✅ OPTIMIZED ROUTE ASSIGNMENT COMPLETED');
    console.log('='.repeat(80));
    console.log(`📊 Final Summary:`);
    console.log(`   - Total requested: ${route.length}`);
    console.log(`   - Successfully assigned: ${results.length}`);
    console.log(`   - Verified assignments: ${verifiedCount}`);
    console.log(`   - Trips created: ${tripIds.length}`);
    console.log(`   - Failed: ${errors.length}`);
    console.log(`   - Customer notifications: ${notificationResults.customers}`);
    console.log(`   - Driver notifications: ${notificationResults.driver}`);
    if (failedVerification.length > 0) {
      console.log(`   - ⚠️  Verification failures: ${failedVerification.length}`);
    }    
    if (errors.length > 0) {
      console.log(`\n❌ ERRORS DETAIL:`);
      errors.forEach(err => {
        console.log(`   - ${err.customerName}: ${err.error}`);
      });
    }
    
    console.log('='.repeat(80) + '\n');

    // ✅ USER-FRIENDLY RESPONSE
    const successCount = results.length;
    const errorCount = errors.length;

    let responseMessage = '';
    let userAdvice = null;

    if (successCount > 0 && errorCount === 0) {
      responseMessage = `✅ Success! All ${successCount} customer(s) assigned successfully.`;
    } else if (successCount > 0 && errorCount > 0) {
      responseMessage = `⚠️  Partial Success: ${successCount} assigned, ${errorCount} failed.`;

      if (errors.some(e => e.error.includes('assigned to different vehicle'))) {
        userAdvice = '💡 Some customers are already assigned to other vehicles.\n\n' +
          'The list will refresh automatically.\n' +
          'Please try assigning the remaining customers again.';
      } else if (errors.some(e => e.error.includes('deleted'))) {
        userAdvice = '💡 Some bookings were deleted or no longer exist.\n\n' +
          'The list will refresh to show current bookings.';
      } else {
        userAdvice = '💡 Check the error details below. If problems continue, contact your administrator.';
      }
    } else {
      responseMessage = `❌ Assignment Failed: Unable to assign any customers.`;

      if (errors.some(e => e.error.includes('assigned to different vehicle'))) {
        userAdvice = '💡 All customers are already assigned to other vehicles.\n\n' +
          'The list will refresh automatically.';
      } else if (errors.some(e => e.error.includes('deleted'))) {
        userAdvice = '💡 These bookings were deleted or no longer exist.\n\n' +
          'The list will refresh to show current bookings.';
      } else if (errors.some(e => e.error.includes('DRIVER_NOT_FOUND'))) {
        userAdvice = '💡 This vehicle needs a driver.\n\n' +
          'Go to Vehicle Management → Assign a driver → Try again';
      } else {
        userAdvice = '💡 Something went wrong. Please refresh the page and try again.\n\n' +
          'If this keeps happening:\n' +
          '1. Check if customers are already assigned\n' +
          '2. Verify the vehicle has a driver\n' +
          '3. Contact your administrator';
      }
    }

    res.json({
      success: successCount > 0,
      message: responseMessage,
      advice: userAdvice,
      successCount: successCount,
      errorCount: errorCount,
      notifications: {
        customers: notificationResults.customers,
        driver: notificationResults.driver,
        failed: notificationResults.failed
      },
      trackingEnabled: true,
      data: {
        vehicleId: vehicleId,
        vehicleName: vehicle.registrationNumber || vehicle.name || 'Vehicle',
        driverId: driver._id.toString(),
        driverName: driver.name,
        assignmentId: new ObjectId().toString(),
        successful: results,
        failed: errors,
        tripIds: tripIds,
        successCount: results.length,
        errorCount: errors.length,
        notifications: notificationResults,
        trackingEnabled: true,
        routeSummary: {
          totalDistance: totalDistance,
          totalTime: totalTime,
          customerCount: route.length,
          startTime: startTime
        }
      }
    });

  } catch (error) {
    await session.abortTransaction();
    console.error('\n' + '❌'.repeat(40));
    console.error('OPTIMIZED ROUTE ASSIGNMENT FAILED');
    console.error('❌'.repeat(40));
    console.error('Error:', error);
    console.error('Stack:', error.stack);
    console.error('❌'.repeat(40) + '\n');

    res.status(500).json({
      success: false,
      message: '❌ Assignment Failed',
      advice: '💡 Something went wrong on the server.\n\n' +
        'Please try again. If the problem continues, contact your system administrator.',
      error: error.message
    });
  } finally {
    await session.endSession();
  }
});


module.exports = router;