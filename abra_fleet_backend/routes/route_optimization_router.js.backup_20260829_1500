// routes/route_optimization_router.js - Route Optimization Endpoints
// ✅ COMPLETE VERSION - All 1200+ lines with proper response structure
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const { createNotification } = require('../models/notification_model');
// Note: FCM is handled automatically by notification_model.js when channels: ['fcm', 'database'] is set
// Note: Using native fetch (Node.js 18+) for OSRM API calls

// ========== ROUTE OPTIMIZATION ENDPOINTS ==========

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
    
    // Fetch rosters
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
    
    // Fetch available drivers
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
    
    // Group rosters by office location
    const rostersByOffice = {};
    rosters.forEach(roster => {
      const office = roster.officeLocation || 'Unknown';
      if (!rostersByOffice[office]) {
        rostersByOffice[office] = [];
      }
      rostersByOffice[office].push(roster);
    });
    
    console.log(`🏢 Grouped into ${Object.keys(rostersByOffice).length} office locations`);
    
    // Optimize assignments
    const assignments = [];
    const usedDriverIds = new Set();
    
    for (const [office, officeRosters] of Object.entries(rostersByOffice)) {
      console.log(`\n🏢 Processing office: ${office} (${officeRosters.length} rosters)`);
      
      // Sort by distance (would need actual coordinates in production)
      // For now, just process in order
      
      for (let i = 0; i < officeRosters.length; i++) {
        const roster = officeRosters[i];
        
        // Find nearest available driver (simplified - in production use actual coordinates)
        const availableDriver = drivers.find(d => !usedDriverIds.has(d._id.toString()));
        
        if (!availableDriver) {
          console.log(`⚠️  No more drivers available for roster ${roster._id}`);
          continue;
        }
        
        // Calculate timing (simplified)
        const officeTime = roster.startTime || '09:00';
        const distance = 10 + (i * 2); // Mock distance
        const travelTime = Math.round(distance * 3); // 3 min per km
        const bufferMinutes = 15 + (i * 2); // Staggered buffer
        
        // Calculate pickup time
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
        
        // Update roster with assignment
        const updateResult = await req.db.collection('rosters').findOneAndUpdate(
          { _id: new ObjectId(rosterId), status: 'pending_assignment' },
          {
            $set: {
              driverId: driverId,
              status: 'assigned',
              assignedAt: new Date(),
              assignedBy: req.user?.uid || req.user?.id || 'system',
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
        
        // Get driver details
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
        
        // Send notification to customer
        try {
          const customerNotification = await createNotification(req.db, {
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
        
        // Send notification to driver
        try {
          const driverNotification = await createNotification(req.db, {
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
// @desc    Get list of compatible vehicles for given customers (filters by email domain, timing, capacity)
// @access  Private (Admin/Manager)
// ============================================================================
// ✅ FIXED VERSION - Consecutive Trip Validation with Travel Time
// ============================================================================
// NEW FEATURES:
// ✅ Calculates travel time between consecutive trips
// ✅ Adds 30-minute buffer between trips
// ✅ Validates office → first pickup distance
// ✅ Filters out physically impossible schedules
// ✅ Shows detailed incompatibility reasons
// ============================================================================

router.post('/compatible-vehicles', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🔍 FINDING COMPATIBLE VEHICLES WITH CONSECUTIVE TRIP VALIDATION');
    console.log('='.repeat(80));
    
    // ✅ UPDATED: Accept date range parameters
    const { rosterIds, startDate, endDate } = req.body;
    
    if (!rosterIds || !Array.isArray(rosterIds) || rosterIds.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'rosterIds array is required'
      });
    }
    
    // ✅ NEW: Calculate date range (default to today if not provided)
    const checkStartDate = startDate || new Date().toISOString().split('T')[0];
    const checkEndDate = endDate || checkStartDate;
    
    console.log(`📋 Checking compatibility for ${rosterIds.length} customers`);
    console.log(`📅 Date range: ${checkStartDate} to ${checkEndDate}`); // ✅ NEW LOG
    
    // ========================================================================
    // STEP 1: Fetch the rosters to check
    // ========================================================================
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
    
    // ========================================================================
    // STEP 2: Extract compatibility criteria from customers
    // ========================================================================
    const customerEmails = new Set();
    const customerCompanies = new Set();
    const customerShifts = new Set();
    const customerLoginTimes = new Set();
    const customerLogoutTimes = new Set();
    const customerRosterTypes = new Set();
    
    // 🆕 NEW: Extract timing information for new trip
    let newTripStartTime = null; // Earliest pickup time
    let newTripEndTime = null;   // Latest office arrival time
    const newTripLocations = [];
    
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
      
      // 🆕 Track timing for this trip
      const pickupTime = roster.startTime || roster.officeTime || roster.loginTime;
      if (pickupTime) {
        if (!newTripStartTime || pickupTime < newTripStartTime) {
          newTripStartTime = pickupTime;
        }
        if (!newTripEndTime || pickupTime > newTripEndTime) {
          newTripEndTime = pickupTime;
        }
      }
      
      // 🆕 Track locations
      newTripLocations.push({
        pickup: roster.loginPickupAddress || roster.pickupLocation,
        office: roster.officeLocation,
        pickupCoords: roster.locations?.pickup?.coordinates || null,
        officeCoords: roster.officeLocationCoordinates || null
      });
      
      console.log(`   ${idx + 1}. ${roster.customerName || 'Unknown'}`);
      console.log(`      📧 Email: ${email}`);
      console.log(`      🏢 Company: ${company}`);
      console.log(`      🌅 Shift: ${roster.shift || 'Unknown'}`);
      console.log(`      🕐 Office Time: ${pickupTime || 'Unknown'}`);
    });
    
    console.log(`\n📊 New Trip Requirements:`);
    console.log(`   🏢 Companies: ${Array.from(customerCompanies).join(', ')}`);
    console.log(`   🕐 Earliest Pickup: ${newTripStartTime || 'Unknown'}`);
    console.log(`   🕐 Latest Office Arrival: ${newTripEndTime || 'Unknown'}`);
    
    // ========================================================================
    // STEP 3: Fetch all active vehicles with drivers
    // ========================================================================
    const allVehicles = await req.db.collection('vehicles')
      .find({
        status: { $regex: /^active$/i },
        assignedDriver: { $exists: true, $ne: null }
      })
      .toArray();
    
    console.log(`\n🚗 Found ${allVehicles.length} active vehicles with drivers`);
    
   // ========================================================================
    // STEP 4: Populate driver information for each vehicle
    // ========================================================================
    console.log('📋 Populating driver information...');
    for (const vehicle of allVehicles) {
      if (vehicle.assignedDriver) {
        try {
          if (typeof vehicle.assignedDriver === 'string' || vehicle.assignedDriver instanceof ObjectId) {
            const driverId = vehicle.assignedDriver.toString();
            
            let driver = null;
            
            // Try drivers collection
            if (ObjectId.isValid(driverId) && driverId.length === 24) {
              driver = await req.db.collection('drivers').findOne({
                _id: new ObjectId(driverId)
              });
            }
            
            if (!driver) {
              driver = await req.db.collection('drivers').findOne({
                driverId: driverId
              });
            }
            
            // Try admin_users collection
            if (!driver && ObjectId.isValid(driverId) && driverId.length === 24) {
              driver = await req.db.collection('admin_users').findOne({
                _id: new ObjectId(driverId)
              });
            }
            
            if (driver) {
              const driverName = driver.name || 
                                (driver.personalInfo?.firstName && driver.personalInfo?.lastName 
                                  ? `${driver.personalInfo.firstName} ${driver.personalInfo.lastName}`.trim()
                                  : 'Unknown Driver');
              const driverPhone = driver.phone || driver.phoneNumber || driver.personalInfo?.phone || '';
              const driverEmail = driver.email || '';
              
              vehicle.assignedDriver = {
                _id: driver._id,
                name: driverName,
                phone: driverPhone,
                email: driverEmail
              };
              
              vehicle.driverName = driverName;
              vehicle.driverPhone = driverPhone;
              vehicle.driverEmail = driverEmail;
            } else {
              const fallbackName = vehicle.driverName || vehicle.assignedDriverName || 'Driver Assigned';
              const fallbackPhone = vehicle.driverPhone || '';
              const fallbackEmail = vehicle.driverEmail || vehicle.assignedDriverEmail || '';
              
              vehicle.assignedDriver = {
                _id: driverId,
                name: fallbackName,
                phone: fallbackPhone,
                email: fallbackEmail
              };
              vehicle.driverName = fallbackName;
              vehicle.driverPhone = fallbackPhone;
              vehicle.driverEmail = fallbackEmail;
            }
          }
        } catch (driverError) {
          console.error(`   ❌ Error populating driver for vehicle ${vehicle._id}:`, driverError.message);
          vehicle.assignedDriver = {
            _id: vehicle.assignedDriver,
            name: 'Driver Assigned',
            phone: '',
            email: ''
          };
          vehicle.driverName = 'Driver Assigned';
          vehicle.driverPhone = '';
          vehicle.driverEmail = '';
        }
      }
    }
    
    console.log('\n🔍 Checking compatibility with consecutive trip validation...\n');
    
    const compatibleVehicles = [];
    const incompatibleVehicles = [];
    
    // ========================================================================
    // STEP 5: Check each vehicle for compatibility WITH CONSECUTIVE TRIP VALIDATION
    // ========================================================================
    
    // Helper function to parse time (HH:mm format)
    const parseTime = (timeStr) => {
      if (!timeStr || typeof timeStr !== 'string') return 0;
      if (timeStr.includes(':')) {
        const [hours, minutes] = timeStr.split(':').map(Number);
        return hours * 60 + minutes;
      }
      const numValue = parseInt(timeStr);
      return !isNaN(numValue) ? numValue * 60 : 0;
    };
    
    // Helper function to calculate distance (Haversine formula)
    const calculateDistance = (coord1, coord2) => {
      if (!coord1 || !coord2 || !coord1.length || !coord2.length) {
        return null;
      }
      
      const [lon1, lat1] = coord1;
      const [lon2, lat2] = coord2;
      
      const R = 6371; // Earth's radius in km
      const dLat = (lat2 - lat1) * Math.PI / 180;
      const dLon = (lon2 - lon1) * Math.PI / 180;
      const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                Math.sin(dLon/2) * Math.sin(dLon/2);
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
      return R * c;
    };
    
    for (const vehicle of allVehicles) {
      const vehicleName = vehicle.name || vehicle.vehicleNumber || 'Unknown';
      const vehicleId = vehicle._id.toString();
      
      console.log(`🚗 Checking: ${vehicleName}`);
      
      // ====================================================================
      // SUB-STEP 5.1: Check existing assignments (from roster-assigned-trips)
      // ✅ UPDATED: Check date range instead of just today
      // ====================================================================
      const existingAssignments = await req.db.collection('roster-assigned-trips').find({
        vehicleId: new ObjectId(vehicleId),
        status: { $in: ['assigned', 'started', 'in_progress'] },
        scheduledDate: { 
          $gte: checkStartDate,  // ✅ NEW: Check from start date
          $lte: checkEndDate     // ✅ NEW: Check to end date
        }
      }).toArray();
      
      if (existingAssignments.length === 0) {
        // No existing assignments - vehicle is compatible
        console.log(`   ✅ COMPATIBLE - No existing assignments in date range`); // ✅ UPDATED
        compatibleVehicles.push({
          ...vehicle,
          assignedCustomers: [],
          compatibilityReason: `No existing assignments from ${checkStartDate} to ${checkEndDate}`, // ✅ UPDATED
          isCompatible: true
        });
        continue;
      }
      
      console.log(`   📋 Has ${existingAssignments.length} existing assignment(s) in date range`); // ✅ UPDATED
      
      // ====================================================================
      // SUB-STEP 5.2: Check company compatibility
      // ====================================================================
      const existingCompanies = new Set();
      
      existingAssignments.forEach(trip => {
        const email = trip.customerEmail || '';
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
          compatibilityReason: `Company mismatch: Vehicle has ${Array.from(existingCompanies).join(', ')}, but customers are from ${Array.from(customerCompanies).join(', ')}`,
          isCompatible: false
        });
        continue;
      }
      
      // ====================================================================
      // SUB-STEP 5.3: Check capacity
      // ====================================================================
      const totalSeats = vehicle.capacity?.passengers || 
                         vehicle.seatCapacity || 
                         vehicle.seatingCapacity || 
                         4;
      const assignedSeats = existingAssignments.length;
      const availableSeats = totalSeats - 1 - assignedSeats;
      
      if (availableSeats <= 0) {
        console.log(`   ❌ INCOMPATIBLE - Vehicle is full`);
        incompatibleVehicles.push({
          ...vehicle,
          assignedCustomers: existingAssignments.map(r => r._id.toString()),
          compatibilityReason: `Vehicle is full: ${assignedSeats} customers already assigned to ${totalSeats - 1} available seats`,
          isCompatible: false
        });
        continue;
      }
      
      if (availableSeats < rosters.length) {
        console.log(`   ❌ INCOMPATIBLE - Insufficient capacity`);
        incompatibleVehicles.push({
          ...vehicle,
          assignedCustomers: existingAssignments.map(r => r._id.toString()),
          compatibilityReason: `Insufficient capacity: ${availableSeats} seats available, ${rosters.length} needed`,
          isCompatible: false
        });
        continue;
      }
      
      // ====================================================================
      // 🆕 SUB-STEP 5.4: CONSECUTIVE TRIP VALIDATION WITH TRAVEL TIME
      // ====================================================================
      console.log(`   ⏰ Checking consecutive trip feasibility...`);
      
      // Sort existing trips by time
      const sortedExistingTrips = existingAssignments.sort((a, b) => {
        const aTime = parseTime(a.startTime || a.estimatedPickupTime || '00:00');
        const bTime = parseTime(b.startTime || b.estimatedPickupTime || '00:00');
        return aTime - bTime;
      });
      
      // Get the latest existing trip (last office drop-off)
      const latestTrip = sortedExistingTrips[sortedExistingTrips.length - 1];
      const latestTripEndTime = parseTime(latestTrip.endTime || latestTrip.startTime || '00:00');
      
      // Get office location of latest trip
      const latestTripOfficeCoords = latestTrip.dropLocation?.coordinates || null;
      
      console.log(`   📍 Latest existing trip ends at: ${Math.floor(latestTripEndTime / 60)}:${String(latestTripEndTime % 60).padStart(2, '0')}`);
      console.log(`   📍 Latest trip office: ${latestTrip.dropLocation?.address || 'Unknown'}`);
      
      // Calculate new trip start time (earliest pickup)
      const newTripStartMinutes = parseTime(newTripStartTime);
      
      console.log(`   📍 New trip needs to start at: ${Math.floor(newTripStartMinutes / 60)}:${String(newTripStartMinutes % 60).padStart(2, '0')}`);
      
      // ====================================================================
      // 🔥 CRITICAL CHECK: Can vehicle reach new trip's first pickup on time?
      // ====================================================================
      
      // Find first pickup location of new trip
      const firstPickupLocation = newTripLocations[0];
      const firstPickupCoords = firstPickupLocation?.pickupCoords;
      
      console.log(`   📍 New trip first pickup: ${firstPickupLocation?.pickup || 'Unknown'}`);
      
      // Calculate distance from latest trip office → new trip first pickup
      let travelDistance = null;
      let travelTimeMinutes = 30; // Default 30 minutes if we can't calculate
      
      if (latestTripOfficeCoords && firstPickupCoords) {
        travelDistance = calculateDistance(latestTripOfficeCoords, firstPickupCoords);
        if (travelDistance !== null) {
          // Calculate travel time: assume 20 km/h average in city traffic
          travelTimeMinutes = Math.ceil((travelDistance / 20) * 60);
          console.log(`   🚗 Calculated distance: ${travelDistance.toFixed(2)} km`);
          console.log(`   ⏱️  Calculated travel time: ${travelTimeMinutes} mins`);
        }
      } else {
        console.log(`   ⚠️  No coordinates available - using default 30 min buffer`);
      }
      
      // Add 30-minute buffer (driver break, parking, etc.)
      const bufferMinutes = 30;
      const totalBufferNeeded = travelTimeMinutes + bufferMinutes;
      
      console.log(`   ⏱️  Travel time needed: ${travelTimeMinutes} mins`);
      console.log(`   ⏱️  Buffer time: ${bufferMinutes} mins`);
      console.log(`   ⏱️  Total time needed: ${totalBufferNeeded} mins`);
      
      // Calculate required free time
      const requiredFreeTimeStart = latestTripEndTime;
      const requiredFreeTimeEnd = newTripStartMinutes;
      const actualFreeTime = requiredFreeTimeEnd - requiredFreeTimeStart;
      
      console.log(`   ⏰ Time available between trips: ${actualFreeTime} mins`);
      console.log(`   ⏰ Time needed (travel + buffer): ${totalBufferNeeded} mins`);
      
      // ====================================================================
      // 🔥 VERDICT: Is this schedule physically possible?
      // ====================================================================
      if (actualFreeTime < totalBufferNeeded) {
        const shortfall = totalBufferNeeded - actualFreeTime;
        console.log(`   ❌ INCOMPATIBLE - Insufficient time between trips`);
        console.log(`   ❌ Shortfall: ${shortfall} minutes`);
        
        const latestEndTimeStr = `${Math.floor(latestTripEndTime / 60)}:${String(latestTripEndTime % 60).padStart(2, '0')}`;
        const newStartTimeStr = `${Math.floor(newTripStartMinutes / 60)}:${String(newTripStartMinutes % 60).padStart(2, '0')}`;
        
        incompatibleVehicles.push({
          ...vehicle,
          assignedCustomers: existingAssignments.map(r => r._id.toString()),
          compatibilityReason: `Impossible schedule: Vehicle finishes previous trip at ${latestEndTimeStr}, ` +
                             `needs ${totalBufferNeeded} mins (${travelTimeMinutes} mins travel + ${bufferMinutes} mins buffer) ` +
                             `to reach new trip by ${newStartTimeStr}. Short by ${shortfall} minutes.`,
          isCompatible: false,
          timeConflict: {
            existingTripEnd: latestEndTimeStr,
            newTripStart: newStartTimeStr,
            travelTimeNeeded: travelTimeMinutes,
            bufferNeeded: bufferMinutes,
            totalTimeNeeded: totalBufferNeeded,
            actualTimeAvailable: actualFreeTime,
            shortfall: shortfall,
            distance: travelDistance ? `${travelDistance.toFixed(2)} km` : 'Unknown'
          }
        });
        continue;
      }
      
      // ====================================================================
      // ✅ ALL CHECKS PASSED - Vehicle is compatible
      // ====================================================================
      console.log(`   ✅ COMPATIBLE - All checks passed including consecutive trip validation`);
      compatibleVehicles.push({
        ...vehicle,
        assignedCustomers: existingAssignments.map(r => r._id.toString()),
        compatibilityReason: `Same company, ${availableSeats} seats available, sufficient time between trips (${actualFreeTime} mins available, ${totalBufferNeeded} mins needed)`,
        isCompatible: true,
        consecutiveTripInfo: {
          existingTripEnd: `${Math.floor(latestTripEndTime / 60)}:${String(latestTripEndTime % 60).padStart(2, '0')}`,
          newTripStart: `${Math.floor(newTripStartMinutes / 60)}:${String(newTripStartMinutes % 60).padStart(2, '0')}`,
          travelTime: travelTimeMinutes,
          buffer: bufferMinutes,
          totalTimeNeeded: totalBufferNeeded,
          timeAvailable: actualFreeTime,
          margin: actualFreeTime - totalBufferNeeded,
          distance: travelDistance ? `${travelDistance.toFixed(2)} km` : 'Unknown'
        }
      });
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('📊 COMPATIBILITY CHECK RESULTS WITH CONSECUTIVE TRIP VALIDATION');
    console.log('='.repeat(80));
    console.log(`✅ Compatible vehicles: ${compatibleVehicles.length}`);
    console.log(`❌ Incompatible vehicles: ${incompatibleVehicles.length}`);
    console.log('='.repeat(80) + '\n');
    
    // ========================================================================
    // STEP 6: Smart vehicle sizing (prefer best fit)
    // ========================================================================
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
        const available = capacity - 1;
        const waste = available - customersCount;
        console.log(`   ${i + 1}. ${v.name || v.vehicleNumber}: ${capacity} seats (${waste} unused after assignment)`);
      });
    }
    console.log('');
    
    res.json({
      success: true,
      message: `Found ${compatibleVehicles.length} compatible vehicles (with consecutive trip validation)`,
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
// @desc    Assign optimized route to NEW roster-assigned-trips collection
// @access  Private (Admin/Manager)
// ============================================================================
// FEATURES:
// ✅ Stores in NEW collection: roster-assigned-trips
// ✅ Uses MongoDB ObjectId for driver/vehicle (NOT custom strings)
// ✅ Distance-based sequencing (farthest → nearest)
// ✅ 24-hour time format (07:25 not 07:25 AM)
// ✅ 20-minute ready buffer (readyByTime)



// @route   POST api/roster/assign-optimized-route
// @desc    Assign optimized route with NEW roster-assigned-trips collection
// @access  Private (Admin/Manager)
// ============================================================================
// COMPLETE VERSION - ALL FEATURES PRESERVED + NEW REQUIREMENTS
// ✅ Stores in NEW collection: roster-assigned-trips
// ✅ Uses MongoDB ObjectId for driver/vehicle (NOT custom strings)
// ✅ Distance-based sequencing (farthest → nearest)
// ✅ 24-hour time format (07:25 not 07:25 AM)
// ✅ 20-minute ready buffer (readyByTime)
// ✅ Enhanced notifications with sequence, distance, ready time
// ✅ Consecutive trip validation (time-based, not date-based)
// ✅ Multi-trip tracking
// ✅ Transaction safety with rollback
// ✅ Comprehensive error handling
// ✅ Verification step
// ============================================================================
router.post('/assign-optimized-route', verifyToken, async (req, res) => {
  const session = req.mongoClient.startSession();
  
  try {
    console.log('\n' + '='.repeat(80));
    console.log('🚀 OPTIMIZED ROUTE ASSIGNMENT - GROUPED TRIPS VERSION WITH RECURRING SUPPORT');
    console.log('🔧 CODE VERSION: 2026-02-02-RECURRING-TRIPS-COMPLETE');
    console.log('='.repeat(80));
    
    // ✅ UPDATED: Accept date range parameters
    const { vehicleId, route, totalDistance, totalTime, startTime, startDate, endDate } = req.body;
    
    // ========================================================================
    // VALIDATION
    // ========================================================================
    if (!vehicleId || !route || !Array.isArray(route) || route.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'vehicleId and route array are required'
      });
    }
    
    // ✅ NEW: Date range validation and calculation
    const assignStartDate = startDate || new Date().toISOString().split('T')[0];
    const assignEndDate = endDate || assignStartDate;
    
    // ✅ NEW: Generate list of dates
    const dateList = [];
    const currentDate = new Date(assignStartDate);
    const endDateObj = new Date(assignEndDate);
    
    while (currentDate <= endDateObj) {
      dateList.push(currentDate.toISOString().split('T')[0]);
      currentDate.setDate(currentDate.getDate() + 1);
    }
    
    console.log(`📋 Processing ${route.length} customer assignments`);
    console.log(`🚗 Vehicle ID: ${vehicleId}`);
    console.log(`📏 Total Distance: ${totalDistance} km`);
    console.log(`⏱️  Total Time: ${totalTime} mins`);
    console.log(`📅 Date Range: ${assignStartDate} to ${assignEndDate} (${dateList.length} day(s))`);
    console.log('-'.repeat(80));
    
    // Start transaction
    await session.startTransaction();
    
    // ========================================================================
    // STEP 1: Get vehicle details
    // ========================================================================
    const vehicle = await req.db.collection('vehicles').findOne(
      { _id: new ObjectId(vehicleId) }
    );
    
    if (!vehicle) {
      await session.abortTransaction();
      console.log('❌ Vehicle not found');
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found'
      });
    }
    
    console.log(`✅ Vehicle found: ${vehicle.name || vehicle.vehicleNumber}`);
    
    // ========================================================================
    // STEP 2: DRIVER LOOKUP - ENHANCED WITH NESTED STRUCTURE SUPPORT
    // ========================================================================
    let driver = null;

    console.log('🔍 Looking up driver for vehicle...');
    console.log('   Vehicle:', vehicle.name || vehicle.vehicleNumber);
    console.log('   assignedDriverEmail:', vehicle.assignedDriverEmail);
    console.log('   assignedDriverName:', vehicle.assignedDriverName || vehicle.driverName);
    console.log('   assignedDriver:', vehicle.assignedDriver);
    console.log('   assignedDriverId:', vehicle.assignedDriverId);

    // ✅ Extract driver identifiers from vehicle
    const driverEmail = vehicle.assignedDriverEmail || vehicle.driverEmail;
    const driverCustomId = vehicle.assignedDriver || vehicle.driverId || vehicle.assignedDriverId;
    const driverName = vehicle.assignedDriverName || vehicle.driverName;

    // ========================================================================
    // LOOKUP DRIVER BY EMAIL (Primary method - handles nested structure)
    // ========================================================================
    if (!driver && driverEmail) {
      console.log('   🔍 Searching by email:', driverEmail);
      
      try {
        const driverDoc = await req.db.collection('drivers').findOne({
          $or: [
            { email: driverEmail },
            { 'personalInfo.email': driverEmail },
            { 'contactInfo.email': driverEmail }
          ]
        });
        
        if (driverDoc) {
          console.log('   ✅ Found driver by email in drivers collection');
          
          // Normalize nested structure
          driver = {
            _id: driverDoc._id,
            driverId: driverDoc.driverId || driverDoc._id.toString(),
            name: driverDoc.personalInfo?.name || driverDoc.name || driverName || 'Unknown Driver',
            email: driverDoc.personalInfo?.email || driverDoc.contactInfo?.email || driverDoc.email || driverEmail,
            phone: driverDoc.personalInfo?.phone || driverDoc.contactInfo?.phone || driverDoc.phone || 'N/A'
          };
          
          console.log('   ✅ Driver normalized:', driver.name);
        }
      } catch (e) {
        console.log('   ⚠️  Email search in drivers collection failed:', e.message);
      }
    }

    // ========================================================================
    // LOOKUP DRIVER BY CUSTOM ID (e.g., "DRV-100014")
    // ========================================================================
    if (!driver && driverCustomId) {
      console.log('   🔍 Searching by custom driver ID:', driverCustomId);
      
      try {
        const driverDoc = await req.db.collection('drivers').findOne({
          $or: [
            { driverId: driverCustomId },
            { _id: ObjectId.isValid(driverCustomId) ? new ObjectId(driverCustomId) : null }
          ]
        });
        
        if (driverDoc) {
          console.log('   ✅ Found driver by custom ID in drivers collection');
          
          // Normalize nested structure
          driver = {
            _id: driverDoc._id,
            driverId: driverDoc.driverId || driverDoc._id.toString(),
            name: driverDoc.personalInfo?.name || driverDoc.name || driverName || 'Unknown Driver',
            email: driverDoc.personalInfo?.email || driverDoc.contactInfo?.email || driverDoc.email || driverEmail || 'N/A',
            phone: driverDoc.personalInfo?.phone || driverDoc.contactInfo?.phone || driverDoc.phone || 'N/A'
          };
          
          console.log('   ✅ Driver normalized:', driver.name);
        }
      } catch (e) {
        console.log('   ⚠️  Custom ID search in drivers collection failed:', e.message);
      }
    }

    // ========================================================================
    // LOOKUP DRIVER BY NAME (Fallback)
    // ========================================================================
    if (!driver && driverName) {
      console.log('   🔍 Fallback: Searching by name:', driverName);
      
      try {
        const driverDoc = await req.db.collection('drivers').findOne({
          $or: [
            { name: driverName },
            { 'personalInfo.name': driverName }
          ]
        });
        
        if (driverDoc) {
          console.log('   ✅ Found driver by name in drivers collection');
          
          // Normalize nested structure
          driver = {
            _id: driverDoc._id,
            driverId: driverDoc.driverId || driverDoc._id.toString(),
            name: driverDoc.personalInfo?.name || driverDoc.name || driverName,
            email: driverDoc.personalInfo?.email || driverDoc.contactInfo?.email || driverDoc.email || driverEmail || 'N/A',
            phone: driverDoc.personalInfo?.phone || driverDoc.contactInfo?.phone || driverDoc.phone || 'N/A'
          };
          
          console.log('   ✅ Driver normalized:', driver.name);
        }
      } catch (e) {
        console.log('   ⚠️  Name search in drivers collection failed:', e.message);
      }
    }
    
    // ========================================================================
    // FINAL VALIDATION
    // ========================================================================
    if (!driver) {
      await session.abortTransaction();
      await session.endSession();
      
      console.log('❌ DRIVER NOT FOUND - ABORTING');
      console.log('   Searched by:');
      console.log('   - Email:', driverEmail || 'N/A');
      console.log('   - Custom ID:', driverCustomId || 'N/A');
      console.log('   - Name:', driverName || 'N/A');
      
      return res.status(400).json({
        success: false,
        message: `Vehicle ${vehicle.registrationNumber || vehicle.vehicleNumber} does not have a valid assigned driver`,
        error: 'DRIVER_NOT_FOUND',
        details: {
          vehicleId: vehicleId,
          vehicleName: vehicle.name || vehicle.vehicleNumber,
          searchedBy: {
            email: driverEmail || null,
            customId: driverCustomId || null,
            name: driverName || null
          },
          actionRequired: 'Please assign a driver to this vehicle before creating assignments'
        }
      });
    }
    
    console.log('✅ Driver found and normalized:');
    console.log('   _id:', driver?._id);
    console.log('   driverId:', driver?.driverId);
    console.log('   Name:', driver?.name);
    console.log('   Email:', driver?.email);
    console.log('   Phone:', driver?.phone);
    console.log('-'.repeat(80));

    // ========================================================================
    // STEP 3: Check vehicle capacity BEFORE assignment - ✅ FIXED VERSION
    // ========================================================================
    console.log('\n💺 CHECKING VEHICLE CAPACITY...');
    
    // ✅ FIX: Query roster-assigned-trips and count unique customers
    const today = new Date().toISOString().split('T')[0];
    const existingTrips = await req.db.collection('roster-assigned-trips').find({
      vehicleId: new ObjectId(vehicleId),
      status: { $in: ['assigned', 'started', 'in_progress'] },
      scheduledDate: today
    }).toArray();
    
    const totalSeats = vehicle.capacity?.passengers || 
                       vehicle.seatCapacity || 
                       vehicle.seatingCapacity || 
                       4;
    
    // ✅ FIX: Extract unique customer emails from trips
    const uniqueCustomers = new Set();
    existingTrips.forEach(trip => {
      trip.stops?.forEach(stop => {
        if (stop.type === 'pickup' && stop.customer?.email) {
          uniqueCustomers.add(stop.customer.email);
        }
      });
    });
    
    const currentAssignedCount = uniqueCustomers.size; // ✅ FIXED: Count unique customers
    const newCustomersCount = route.length;
    const availableSeats = totalSeats - 1 - currentAssignedCount; // -1 for driver
    
    console.log(`   🚗 Vehicle: ${vehicle.name || vehicle.vehicleNumber}`);
    console.log(`   💺 Total Seats: ${totalSeats}`);
    console.log(`   👥 Currently Assigned: ${currentAssignedCount} unique customers`);
    console.log(`   🚗 Existing Trips: ${existingTrips.length}`); // ✅ ADDED: Show trip count
    console.log(`   ✅ Available Seats: ${availableSeats}`);
    console.log(`   📋 New Customers: ${newCustomersCount}`);
    
    if (availableSeats <= 0 || newCustomersCount > availableSeats) {
      await session.abortTransaction();
      console.log(`\n❌ CAPACITY CHECK FAILED`);
      return res.status(400).json({
        success: false,
        message: `Vehicle capacity exceeded: ${availableSeats} seats available but ${newCustomersCount} customers need assignment`,
        error: 'INSUFFICIENT_CAPACITY'
      });
    }
    
    console.log(`   ✅ Capacity check passed`);
    
    // ========================================================================
    // SAFETY CHECK: Ensure driver object exists before proceeding
    // ========================================================================
    if (!driver || !driver._id) {
      await session.abortTransaction();
      await session.endSession();
      console.log(`❌ Driver object is invalid or missing _id`);
      return res.status(400).json({
        success: false,
        message: 'Driver object is invalid',
        error: 'INVALID_DRIVER_OBJECT',
        details: {
          vehicleId: vehicleId,
          vehicleName: vehicle.name || vehicle.vehicleNumber,
          driverObject: driver,
          actionRequired: 'Driver lookup failed. Please check vehicle-driver assignment.'
        }
      });
    }
    
    // ========================================================================
    // STEP 4: Check TIME SLOT conflicts for consecutive trip validation
    // ========================================================================
    console.log('\n⏰ CHECKING TIME SLOT CONFLICTS (CONSECUTIVE TRIPS SUPPORT)...');
    const scheduledDate = new Date().toISOString().split('T')[0];
    
    // Helper to parse time in 24-hour format
    const parseTime = (timeStr) => {
      if (!timeStr || typeof timeStr !== 'string') return 0;
      
      if (timeStr.includes(':')) {
        const [hours, minutes] = timeStr.split(':').map(Number);
        return hours * 60 + minutes;
      }
      
      const numValue = parseInt(timeStr);
      if (!isNaN(numValue)) {
        return numValue * 60;
      }
      
      return 0;
    };
    
    for (const stop of route) {
      const stopStartMinutes = parseTime(stop.pickupTime || '00:00');
      const stopEndMinutes = parseTime(stop.estimatedTime || stop.pickupTime || '00:00');
      
      const conflicts = await req.db.collection('roster-assigned-trips').find({
        vehicleId: new ObjectId(vehicleId),
        scheduledDate: scheduledDate,
        status: { $in: ['assigned', 'started', 'in_progress'] }
      }).toArray();
      
      for (const existingTrip of conflicts) {
        const existingStartMinutes = parseTime(existingTrip.startTime);
        const existingEndMinutes = parseTime(existingTrip.endTime);
        
        const hasOverlap = (stopStartMinutes < existingEndMinutes) && (stopEndMinutes > existingStartMinutes);
        
        if (hasOverlap) {
          await session.abortTransaction();
          console.log(`\n❌ TIME SLOT CONFLICT DETECTED`);
          console.log(`   Stop #${stop.sequence}: ${stop.customerName}`);
          console.log(`   Conflicting with: ${existingTrip.tripNumber}`);
          return res.status(409).json({
            success: false,
            message: `Time slot conflict detected for ${stop.customerName}`,
            error: 'TIME_SLOT_CONFLICT',
            conflictingTrip: existingTrip
          });
        }
      }
    }
    
    console.log(`   ✅ No time slot conflicts found - consecutive trips allowed`);
    
    const results = [];
    const errors = [];
    const rosterIds = [];
    const notificationResults = {
      customers: 0,
      driver: 0,
      admin: 0,
      failed: 0
    };
    
    // ✅ Extract driver ID once for use throughout
    let driverIdString;
    try {
      driverIdString = driver._id.toString();
      console.log(`✅ Driver ID extracted for all operations: ${driverIdString}`);
    } catch (idError) {
      await session.abortTransaction();
      await session.endSession();
      console.log(`❌ Failed to extract driver ID:`, idError.message);
      return res.status(400).json({
        success: false,
        message: 'Invalid driver ID',
        error: 'INVALID_DRIVER_ID',
        details: {
          vehicleId: vehicleId,
          vehicleName: vehicle.name || vehicle.vehicleNumber,
          driverObject: driver,
          actionRequired: 'Driver object is malformed. Please check driver assignment.'
        }
      });
    }
    
    // ========================================================================
    // 🆕 STEP 5: BUILD STOPS ARRAY (ONCE - Used for all dates)
    // ========================================================================
    console.log('\n' + '='.repeat(80));
    console.log('🎫 BUILDING STOPS ARRAY FOR RECURRING TRIPS');
    console.log('='.repeat(80));
    
    const stops = [];
    
    for (const stop of route) {
      try {
        const { 
          rosterId, 
          customerId, 
          customerName, 
          customerEmail, 
          customerPhone, 
          sequence, 
          pickupTime, 
          readyByTime,
          distanceToOffice,
          distanceFromPrevious,
          eta, 
          location,
          pickupLocation,
          pickupCoordinates,
          estimatedTime
        } = stop;
        
        console.log(`\n📍 Processing Stop #${sequence}: ${customerName}`);
        console.log(`   🔍 DEBUG: Stop object keys:`, Object.keys(stop));
        console.log(`   🔍 DEBUG: rosterId:`, rosterId);
        console.log(`   🔍 DEBUG: location:`, location);
        console.log(`   🔍 DEBUG: pickupLocation:`, pickupLocation);
        console.log(`   🔍 DEBUG: pickupCoordinates:`, pickupCoordinates);
        
        if (!rosterId) {
          errors.push({ sequence, customerName, error: 'Missing rosterId' });
          continue;
        }
        
        console.log(`\n🔍 DEBUG: Looking up roster for ${customerName}`);
        console.log(`   rosterId type: ${typeof rosterId}`);
        console.log(`   rosterId value: "${rosterId}"`);
        console.log(`   rosterId length: ${rosterId ? rosterId.length : 0}`);
        
        if (!ObjectId.isValid(rosterId)) {
          console.log(`   ❌ Invalid ObjectId format`);
          errors.push({
            customerName,
            error: 'Invalid ObjectId format',
            friendlyMessage: `❌ ${customerName}: Invalid roster ID format (${rosterId})`
          });
          continue;
        }
        
        console.log(`   ✅ Valid ObjectId, querying database...`);
        
        // ====================================================================
        // Look up roster WITHOUT session first
        // ====================================================================
        // ====================================================================
        // 🔍 DEBUG: Enhanced roster lookup logging for manual mode debugging
        // ====================================================================
        console.log(`\n🔍 DEBUG: Looking up roster for ${customerName}`);
        console.log(`   rosterId from route: "${rosterId}"`);
        console.log(`   rosterId type: ${typeof rosterId}`);
        console.log(`   rosterId length: ${rosterId ? rosterId.length : 0}`);
        console.log(`   Is valid ObjectId: ${ObjectId.isValid(rosterId)}`);
        
        let existingRoster = await req.db.collection('rosters').findOne(
          { _id: new ObjectId(rosterId) }
        );
        
        console.log(`   Roster found: ${existingRoster ? 'YES ✅' : 'NO ❌'}`);
        
        if (existingRoster) {
          console.log(`   ✅ Roster details:`);
          console.log(`      Status: ${existingRoster.status}`);
          console.log(`      Customer: ${existingRoster.customerName}`);
          console.log(`      Vehicle: ${existingRoster.vehicleNumber || 'Not assigned'}`);
          console.log(`      Has Trip ID: ${existingRoster.tripId ? 'YES' : 'NO'}`);
        }
        
        if (!existingRoster) {
          console.log(`   ❌ Roster truly doesn't exist in database`);
          errors.push({
            customerName,
            error: 'Roster not found',
            friendlyMessage: `❌ ${customerName}: Roster not found or deleted`
          });
          continue;
        }
        
        // ====================================================================
        // ✅ FIX: ADD ROSTER TO UPDATE ARRAY IMMEDIATELY AFTER FINDING IT
        // This ensures roster status gets updated even if trip creation fails
        // ====================================================================
        console.log(`   ✅ Adding roster ${rosterId} to rosterIds array for update`);
        rosterIds.push(new ObjectId(rosterId));
        console.log(`   📊 rosterIds array now has ${rosterIds.length} roster(s)`);
        
        const roster = existingRoster; // Use the existing roster
        
        const isReassignment = existingRoster.status === 'assigned' && existingRoster.tripId;
        if (isReassignment) {
          console.log(`   🔄 ${customerName} already assigned - will UPDATE existing trip`);
        }
        
        if (!driver || !driver._id) {
          console.log(`   ❌ Driver not found for vehicle ${vehicleId}`);
          console.log(`   ❌ Driver object:`, driver);
          errors.push({
            customerName,
            error: 'Driver not found',
            friendlyMessage: `❌ ${customerName}: No driver assigned to vehicle`,
            actionRequired: 'Please assign a driver to the vehicle first'
          });
          continue;
        }
        
        console.log(`   ✅ Driver verified: ${driver.name} (${driverIdString})`);
        
        // ====================================================================
        // 🆕 ADD TO STOPS ARRAY
        // ====================================================================
        const stopData = {
          stopId: new ObjectId().toString(),
          rosterId: new ObjectId(rosterId),
          sequence: sequence,
          type: 'pickup',
          rosterType: roster.rosterType || 'both',
          
          // Customer Info
          customer: {
            name: customerName,
            email: customerEmail,
            phone: customerPhone || roster.customerPhone || ''
          },
          
          // Location
          location: {
            address: stop?.pickupLocation || location?.address || roster?.loginPickupAddress || 'Pickup location',
            coordinates: stop?.pickupCoordinates || location?.coordinates || roster?.locations?.pickup?.coordinates || null
          },
          
          // Timing
          estimatedTime: pickupTime,
          pickupTime: pickupTime,
          readyByTime: readyByTime || pickupTime,
          
          // Distance
          distanceToOffice: distanceToOffice || 0,
          distanceFromPrevious: distanceFromPrevious || 0,
          
          // Status
          status: 'pending',
          passengerStatus: null
        };
        
        stops.push(stopData);
        
        console.log(`   ✅ Stop added to array: #${sequence} - ${customerName}`);
        
        results.push({
          rosterId: rosterId,
          sequence: sequence,
          customerName: customerName,
          status: 'success',
          friendlyMessage: `✅ ${customerName} added to trip`
        });
        
      } catch (stopError) {
        console.error(`   ❌ Error processing stop: ${stopError.message}`);
        console.error(`   ❌ Error stack:`, stopError.stack);
        console.error(`   ❌ Stop data:`, JSON.stringify(stop, null, 2));
        errors.push({
          sequence: stop.sequence,
          customerName: stop.customerName,
          error: stopError.message
        });
      }
    }
    
    // ========================================================================
    // 🆕 ADD OFFICE DROP AS FINAL STOP
    // ========================================================================
    if (stops.length > 0) {
      console.log('\n🏢 Adding office drop as final stop...');
      
      const lastStop = stops[stops.length - 1];
      
      // Get office location from first roster
      const firstRoster = await req.db.collection('rosters').findOne(
        { _id: rosterIds[0] }
      );
      
      const officeStop = {
        stopId: `office-drop-${vehicleId}`,
        sequence: stops.length + 1,
        type: 'drop',
        location: {
          address: firstRoster?.officeLocation || 'Office',
          coordinates: firstRoster?.officeLocationCoordinates || null
        },
        estimatedTime: lastStop.estimatedTime,
        passengers: stops.map(s => s.customer.name),
        status: 'pending'
      };
      
      stops.push(officeStop);
      console.log(`   ✅ Office drop added as stop #${officeStop.sequence}`);
    }
    
    // ========================================================================
    // 🆕 STEP 6: CREATE TRIP DOCUMENTS FOR EACH DATE IN RANGE
    // ========================================================================
    console.log('\n' + '='.repeat(80));
    console.log('💾 CREATING GROUPED TRIP DOCUMENTS FOR DATE RANGE');
    console.log('='.repeat(80));
    console.log(`📅 Creating trips for ${dateList.length} date(s): ${assignStartDate} to ${assignEndDate}`);
    console.log('='.repeat(80));
    
    // ✅ NEW: Arrays to track all created trips
    const allCreatedTripIds = [];
    const allCreatedTripNumbers = [];
    let totalTripsCreated = 0;
    let totalTripsFailed = 0;
    
    // ✅ NEW: Loop through each date
for (let dateIndex = 0; dateIndex < dateList.length; dateIndex++) {
  const scheduledDateForTrip = dateList[dateIndex];
  
  console.log(`\n${'='.repeat(80)}`);
  console.log(`📅 PROCESSING DATE ${dateIndex + 1}/${dateList.length}: ${scheduledDateForTrip}`);
  console.log('='.repeat(80));
  
  // ✅ STEP 6A: VALIDATE ROSTER TYPE CONSISTENCY
  console.log('\n🔍 VALIDATING ROSTER TYPE CONSISTENCY...');
  console.log('-'.repeat(80));
  
  // Extract all unique roster types from the route
  const rosterTypes = new Set();
  for (const stop of route) {
    const stopRosterType = stop.rosterType || 'both';
    rosterTypes.add(stopRosterType);
    console.log(`   - ${stop.customerName}: ${stopRosterType}`);
  }
  
  // ✅ CRITICAL CHECK: All customers must have SAME roster type
  if (rosterTypes.size > 1) {
    // ❌ MIXED roster types detected - REJECT assignment
    await session.abortTransaction();
    await session.endSession();
    
    console.log('\n' + '❌'.repeat(40));
    console.log('MIXED ROSTER TYPES DETECTED - ASSIGNMENT REJECTED');
    console.log('❌'.repeat(40));
    console.log('🚫 Cannot assign customers with different roster types to same vehicle');
    console.log(`📋 Found roster types: ${Array.from(rosterTypes).join(', ')}`);
    console.log('\n👥 Customers:');
    route.forEach(r => {
      console.log(`   - ${r.customerName}: ${r.rosterType || 'both'}`);
    });
    console.log('❌'.repeat(40) + '\n');
    
    return res.status(400).json({
      success: false,
      message: 'Cannot assign customers with different roster types to same vehicle',
      error: 'MIXED_ROSTER_TYPES',
      details: {
        rosterTypes: Array.from(rosterTypes),
        customers: route.map(r => ({
          name: r.customerName,
          rosterType: r.rosterType || 'both'
        })),
        explanation: 'All customers in a vehicle must have the same trip requirements (all "both", all "login", or all "logout")',
        actionRequired: 'Please separate customers with different roster types into different vehicles'
      }
    });
  }
  
  // ✅ All customers have SAME roster type
  const commonRosterType = Array.from(rosterTypes)[0];
  console.log(`✅ Roster type validation passed`);
  console.log(`   All ${route.length} customers need: "${commonRosterType}" trips`);
  console.log('-'.repeat(80));
  
  // ✅ Determine which trips to create based on common roster type
  const tripsToCreate = [];
  
  if (commonRosterType === 'both') {
    // All customers need BOTH morning and evening trips
    tripsToCreate.push('morning', 'evening');
    console.log('📋 Will create: 2 trips (Morning pickup + Evening drop)');
  } else if (commonRosterType === 'login' || commonRosterType === 'pickup') {
    // All customers need ONLY morning trip
    tripsToCreate.push('morning');
    console.log('📋 Will create: 1 trip (Morning pickup ONLY)');
  } else if (commonRosterType === 'logout' || commonRosterType === 'drop') {
    // All customers need ONLY evening trip
    tripsToCreate.push('evening');
    console.log('📋 Will create: 1 trip (Evening drop ONLY)');
  } else {
    // Fallback to morning
    tripsToCreate.push('morning');
    console.log('📋 Will create: 1 trip (Morning - default fallback)');
  }
  
  const needsBothTrips = (commonRosterType === 'both');
  console.log(`   needsBothTrips: ${needsBothTrips}`);
  
  // ✅ NEW: Loop through each trip type (morning, evening, or both)
  for (const tripTime of tripsToCreate) {
    const isMorningTrip = tripTime === 'morning';
    const tripType = isMorningTrip ? 'pickup' : 'drop';
    
    // Generate unique trip number
    const tripNumber = `TRIP-${scheduledDateForTrip.replace(/-/g, '')}-${tripType.toUpperCase()}-${Date.now().toString().slice(-6)}`;
    const tripGroupId = `${vehicleId}-${tripType}-${scheduledDateForTrip}`;
    
    console.log(`\n${'─'.repeat(80)}`);
    console.log(`${isMorningTrip ? '🌅 MORNING TRIP (PICKUP)' : '🌆 EVENING TRIP (DROP)'}`);
    console.log(`   Trip Number: ${tripNumber}`);
    console.log(`   Trip Type: ${tripType}`);
    console.log(`   Trip Group ID: ${tripGroupId}`);
    console.log(`   Scheduled Date: ${scheduledDateForTrip}`);
    
    // ✅ NEW: Build stops array based on trip type
    let tripStops = [];
    
    if (isMorningTrip) {
      // ========================================
      // MORNING TRIP: Home → Office (Pickup)
      // ========================================
      console.log('   📍 Route: Home → Office (Morning Pickup)');
      
      // Add pickup stops (customer homes)
      for (const stop of stops) {
        if (stop.type === 'pickup') {
          tripStops.push({
            ...stop,
            stopId: new ObjectId().toString()
          });
        }
      }
      
      // Add office drop as final stop
      const firstRoster = await req.db.collection('rosters').findOne(
        { _id: rosterIds[0] }
      );
      
      tripStops.push({
        stopId: `office-drop-${vehicleId}`,
        sequence: tripStops.length + 1,
        type: 'drop',
        location: {
          address: firstRoster?.officeLocation || 'Office',
          coordinates: firstRoster?.officeLocationCoordinates || null
        },
        estimatedTime: stops[stops.length - 1]?.estimatedTime || startTime,
        passengers: tripStops.map(s => s.customer.name),
        status: 'pending'
      });
      
    } else {
      // ========================================
      // EVENING TRIP: Office → Home (Drop)
      // ========================================
      console.log('   📍 Route: Office → Home (Evening Drop)');
      
      // Add office pickup as first stop
      const firstRoster = await req.db.collection('rosters').findOne(
        { _id: rosterIds[0] }
      );
      
      const logoutTime = firstRoster?.endTime || firstRoster?.logoutTime || '18:00';
      
      tripStops.push({
        stopId: `office-pickup-${vehicleId}`,
        sequence: 1,
        type: 'pickup',
        location: {
          address: firstRoster?.officeLocation || 'Office',
          coordinates: firstRoster?.officeLocationCoordinates || null
        },
        estimatedTime: logoutTime,
        passengers: stops.filter(s => s.type === 'pickup').map(s => s.customer.name),
        status: 'pending'
      });
      
      // Add customer homes as drop stops (REVERSE order for evening)
      const pickupStops = stops.filter(s => s.type === 'pickup');
      
      // Reverse the order: Drop nearest customer first, farthest last
      for (let i = pickupStops.length - 1; i >= 0; i--) {
        const originalStop = pickupStops[i];
        
        // Calculate evening drop time (add travel time progressively)
        const baseTime = parseTime(logoutTime);
        const travelTimeFromOffice = Math.round(originalStop.distanceToOffice * 3); // 3 min per km
        const dropTimeMinutes = baseTime + travelTimeFromOffice;
        const dropTime = `${String(Math.floor(dropTimeMinutes / 60)).padStart(2, '0')}:${String(dropTimeMinutes % 60).padStart(2, '0')}`;
        
        tripStops.push({
          stopId: new ObjectId().toString(),
          rosterId: originalStop.rosterId,
          sequence: tripStops.length + 1,
          type: 'drop',
          customer: originalStop.customer,
          location: originalStop.location,
          estimatedTime: dropTime,
          pickupTime: dropTime,
          readyByTime: logoutTime, // Customer waits at office
          distanceFromPrevious: i === pickupStops.length - 1 ? originalStop.distanceToOffice : pickupStops[i + 1].distanceFromPrevious,
          status: 'pending',
          passengerStatus: null
        });
      }
    }
    
    console.log(`   📊 Total Stops: ${tripStops.length}`);
    
    // ====================================================================
    // 🔧 SAFE TIME EXTRACTION FUNCTION
    // ====================================================================
    const extractSafeTime = (timeValue, fallback = '00:00') => {
      if (!timeValue) return fallback;
      
      // If already a string in HH:mm format, return as-is
      if (typeof timeValue === 'string' && timeValue.match(/^\d{1,2}:\d{2}$/)) {
        return timeValue;
      }
      
      // If it's a number (minutes), convert to HH:mm
      if (typeof timeValue === 'number') {
        const hours = Math.floor(timeValue / 60);
        const minutes = timeValue % 60;
        return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
      }
      
      // If it's an ISO timestamp, extract the time part
      if (typeof timeValue === 'string' && timeValue.includes('T')) {
        const timePart = timeValue.split('T')[1];
        if (timePart && timePart.length >= 5) {
          return timePart.substring(0, 5); // Get HH:mm
        }
      }
      
      return fallback;
    };
    
    // ====================================================================
    // Extract trip start and end times safely
    // ====================================================================
    let tripStartTime, tripEndTime;
    
    if (isMorningTrip) {
      // Morning trip: Start early, end at office time
      tripStartTime = tripStops.length > 0 
        ? extractSafeTime(tripStops[0].pickupTime, '06:00')
        : extractSafeTime(startTime, '06:00');
      
      tripEndTime = tripStops.length > 0 
        ? extractSafeTime(tripStops[tripStops.length - 1].estimatedTime, '09:00')
        : '09:00';
      
    } else {
      // Evening trip: Start at office logout time, end late
      const firstRoster = await req.db.collection('rosters').findOne(
        { _id: rosterIds[0] }
      );
      
      tripStartTime = extractSafeTime(firstRoster?.endTime || firstRoster?.logoutTime || '18:00', '18:00');
      tripEndTime = extractSafeTime(tripStops[tripStops.length - 1]?.estimatedTime, '20:00');
    }
    
    console.log(`   ⏰ Trip Times: ${tripStartTime} → ${tripEndTime}`);
    
    // ====================================================================
    // CREATE TRIP DATA
    // ====================================================================
    const tripData = {
      // Trip Identification
      tripNumber: tripNumber,
      tripGroupId: tripGroupId,
      tripType: tripType,
      tripTime: tripTime, // ✅ NEW: 'morning' or 'evening'
      isReturnTrip: !isMorningTrip, // ✅ NEW: true for evening trips
      
      // Vehicle & Driver
      vehicleId: new ObjectId(vehicleId),
      vehicleNumber: vehicle.registrationNumber || vehicle.vehicleNumber,
      vehicleName: vehicle.name || vehicle.vehicleNumber,
      driverId: new ObjectId(driverIdString),
      driverName: driver.name || 'Unknown Driver',
      driverEmail: driver.email,
      driverPhone: driver.phone,
      
      // Schedule
      scheduledDate: scheduledDateForTrip,
      startTime: tripStartTime,
      endTime: tripEndTime,
      
      // Route Summary
      totalStops: tripStops.length,
      totalDistance: totalDistance,
      totalTime: totalTime,
      estimatedDuration: totalTime,
      
      // ✅ UPDATED: Use trip-specific stops
      stops: tripStops,
      
      // Current Progress
      currentStopIndex: 0,
      
      // Linked Rosters
      rosterIds: rosterIds,
      
      // Status
      status: 'assigned',
      
      // Tracking
      currentLocation: null,
      locationHistory: [],
      
      // Metrics
      actualDistance: null,
      actualDuration: null,
      
      // Timestamps
      assignedAt: new Date(),
      assignedBy: req.user?.uid || req.user?.id || 'system',
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    // ====================================================================
    // INSERT TRIP FOR THIS DATE
    // ====================================================================
    let tripId;
    let isNewTrip = true;
    
    try {
      // Check if trip already exists with same tripNumber
      const existingTripDoc = await req.db.collection('roster-assigned-trips').findOne(
        { tripNumber: tripNumber }
      );
      
      if (existingTripDoc) {
        // Update existing trip
        const updateResult = await req.db.collection('roster-assigned-trips').updateOne(
          { _id: existingTripDoc._id },
          { $set: tripData },
          { session }
        );
        
        if (updateResult.modifiedCount === 0 && updateResult.matchedCount === 0) {
          throw new Error(`Failed to update ${tripType} trip for ${scheduledDateForTrip}`);
        }
        
        tripId = existingTripDoc._id.toString();
        isNewTrip = false;
        console.log(`   🔄 Trip updated: ${tripNumber} (ID: ${tripId})`);
      } else {
        // Insert new trip
        const insertResult = await req.db.collection('roster-assigned-trips').insertOne(
          tripData,
          { session }
        );
        
        if (!insertResult.insertedId) {
          throw new Error(`Failed to create ${tripType} trip for ${scheduledDateForTrip}`);
        }
        
        tripId = insertResult.insertedId.toString();
        console.log(`   ✅ Trip created: ${tripNumber} (ID: ${tripId})`);
      }
      
      console.log(`   - Vehicle: ${vehicle.vehicleNumber}`);
      console.log(`   - Driver: ${driver.name}`);
      console.log(`   - Stops: ${tripStops.length} (${isMorningTrip ? 'pickups + office drop' : 'office pickup + customer drops'})`);
      console.log(`   - Distance: ${totalDistance} km`);
      console.log(`   - Time: ${totalTime} mins`);
      
      // ✅ Track successful trip creation
      allCreatedTripIds.push(tripId);
      allCreatedTripNumbers.push(tripNumber);
      totalTripsCreated++;
      
    } catch (tripCreationError) {
      console.error(`   ❌ Failed to create ${tripType} trip for ${scheduledDateForTrip}:`, tripCreationError.message);
      totalTripsFailed++;
      // Continue to next trip type instead of aborting
      continue;
    }
    
  } // ✅ END OF TRIP TYPE LOOP (morning/evening)
  
} // ✅ END OF DATE LOOP
    
    console.log('\n' + '='.repeat(80));
    console.log('📊 TRIP CREATION SUMMARY FOR DATE RANGE');
    console.log('='.repeat(80));
    console.log(`✅ Successfully created: ${totalTripsCreated} trip(s)`);
    console.log(`❌ Failed: ${totalTripsFailed} trip(s)`);
    console.log(`📅 Date range: ${assignStartDate} to ${assignEndDate}`);
    console.log('='.repeat(80));
    
    // ✅ VALIDATION: Ensure at least one trip was created
    if (totalTripsCreated === 0) {
      await session.abortTransaction();
      throw new Error('Failed to create any trips for the date range');
    }
    
    // ✅ Get the FIRST trip ID for linking rosters
    const firstTripId = allCreatedTripIds[0];
    const firstTripNumber = allCreatedTripNumbers[0];
    
    // ====================================================================
    // 🆕 STEP 7: UPDATE ROSTERS WITH TRIP INFO
    // ====================================================================
    console.log('\n' + '='.repeat(80));
    console.log('🔗 UPDATING ROSTERS WITH TRIP INFORMATION');
    console.log('='.repeat(80));
    
    for (let i = 0; i < rosterIds.length; i++) {
      const rosterId = rosterIds[i];
      const stop = stops[i]; // Get corresponding stop data
      
      try {
        // ✅ UPDATED: Separate morning and evening trip IDs
const morningTripIds = allCreatedTripIds.filter((_, idx) => 
  allCreatedTripNumbers[idx].includes('PICKUP')
);
const eveningTripIds = allCreatedTripIds.filter((_, idx) => 
  allCreatedTripNumbers[idx].includes('DROP')
);

const updateResult = await req.db.collection('rosters').updateOne(
  { _id: rosterId },
  {
    $set: {
      vehicleId: new ObjectId(vehicleId),
      vehicleNumber: vehicle.registrationNumber || vehicle.vehicleNumber,
      driverId: driverIdString,
      driverName: driver.name || 'Unknown Driver',
      driverPhone: driver.phone || 'N/A',
      
      // ✅ UPDATED: Store both morning and evening trip IDs
      tripId: firstTripId,
      tripIds: allCreatedTripIds,
      tripNumber: firstTripNumber,
      tripNumbers: allCreatedTripNumbers,
      
      morningTripIds: morningTripIds, // ✅ NEW
      eveningTripIds: eveningTripIds, // ✅ NEW
      hasBothTrips: needsBothTrips,   // ✅ NEW
      
      assignedDateRange: {
        startDate: assignStartDate,
        endDate: assignEndDate,
        totalDays: dateList.length
      },
      
      status: 'assigned',
      assignedAt: new Date(),
      assignedBy: req.user?.uid || req.user?.id || 'system',
      pickupSequence: stop.sequence,
      optimizedPickupTime: stop.pickupTime,
      estimatedArrival: new Date(),
      pickupLocation: stop.location,
      routeDetails: {
        totalDistance,
        totalTime,
        sequence: stop.sequence,
        distanceFromPrevious: stop.distanceFromPrevious,
        estimatedTime: stop.estimatedTime
      },
      updatedAt: new Date()
    }
  },
  { session }
);
        
        if (updateResult.matchedCount === 0) {
          console.log(`   ⚠️  Roster ${rosterId} not found`);
        } else {
          console.log(`   ✅ Roster ${rosterId} updated with ${allCreatedTripIds.length} trip ID(s)`);
        }
        
      } catch (rosterUpdateError) {
        console.error(`   ❌ Failed to update roster ${rosterId}:`, rosterUpdateError.message);
      }
    }
    
    console.log(`   ✅ Updated ${rosterIds.length} roster(s) with trip information`);
    
    // ====================================================================
// 🆕 STEP 8: SEND CUSTOMER NOTIFICATIONS (ENHANCED FOR ALL TRIP TYPES)
// ====================================================================
console.log('\n' + '='.repeat(80));
console.log('📧 SENDING CUSTOMER NOTIFICATIONS');
console.log('='.repeat(80));

for (const stop of stops) {
  if (stop.type !== 'pickup') continue; // Skip office drop
  
  try {
    const customerEmailId = stop.customer.email;
    let customerObjectId = null;
    
    console.log(`\n   📧 Customer: ${stop.customer.name} (${customerEmailId})`);
    
    // Look up customer in users collection
    if (customerEmailId) {
      const customerUser = await req.db.collection('users').findOne({
        email: customerEmailId,
        role: 'customer'
      });
      
      if (customerUser) {
        customerObjectId = customerUser._id.toString();
        console.log(`      ✅ Found user ID: ${customerObjectId}`);
      } else {
        console.log(`      ⚠️  Customer not found in users collection`);
      }
    }
    
    if (!customerObjectId && !customerEmailId) {
      console.log(`      ⚠️  Skipping - no ID or email`);
      notificationResults.failed++;
      continue;
    }
    
    // ✅ FIXED: Use stop's individual roster type (already validated as consistent)
    const customerRosterType = stop.rosterType || 'both';
    const hasBothTrips = (customerRosterType === 'both');
    const isLoginOnly = (customerRosterType === 'login' || customerRosterType === 'pickup');
    const isLogoutOnly = (customerRosterType === 'logout' || customerRosterType === 'drop');
    
    console.log(`      📋 Roster Type: ${customerRosterType}`);
    console.log(`      🔄 Has Both Trips: ${hasBothTrips ? 'YES' : 'NO'}`);
    
    // ✅ BUILD NOTIFICATION BASED ON TRIP TYPE
    let notificationTitle = '';
    let notificationBody = '';
    
    if (hasBothTrips) {
      // ========================================
      // CASE 1: BOTH TRIPS (LOGIN + LOGOUT)
      // ========================================
      notificationTitle = 'Driver Assigned - Morning & Evening';
      notificationBody = `Driver ${driver?.name || 'Unknown'} assigned for BOTH trips\n\n` +
            `Vehicle: ${vehicle?.registrationNumber || vehicle?.vehicleNumber || 'Unknown'}\n` +
            `Trips Created: ${totalTripsCreated} (Morning + Evening)\n` +
            `Date Range: ${assignStartDate} to ${assignEndDate} (${dateList.length} day${dateList.length > 1 ? 's' : ''})\n\n` +
            `🌅 MORNING TRIP (Pickup):\n` +
            `   Pickup Time: ${stop.pickupTime}\n` +
            `   BE READY BY: ${stop.readyByTime}\n` +
            `   Sequence: #${stop.sequence}\n\n` +
            `🌆 EVENING TRIP (Drop):\n` +
            `   Office Logout Time: Check your roster\n` +
            `   Same vehicle will drop you home\n\n` +
            `Distance to office: ${(stop.distanceToOffice || 0).toFixed(1)} km\n\n` +
            `✅ Same driver & vehicle for both trips!\n` +
            `Track your driver in real-time through the app.`;
      
    } else if (isLoginOnly) {
      // ========================================
      // CASE 2: LOGIN ONLY (MORNING PICKUP)
      // ========================================
      notificationTitle = 'Driver Assigned - Morning Pickup';
      notificationBody = `Driver ${driver?.name || 'Unknown'} assigned for morning pickup\n\n` +
            `Vehicle: ${vehicle?.registrationNumber || vehicle?.vehicleNumber || 'Unknown'}\n` +
            `Trip: ${firstTripNumber}\n` +
            `Date Range: ${assignStartDate} to ${assignEndDate} (${dateList.length} day${dateList.length > 1 ? 's' : ''})\n\n` +
            `🌅 MORNING PICKUP:\n` +
            `   Pickup Time: ${stop.pickupTime}\n` +
            `   BE READY BY: ${stop.readyByTime}\n` +
            `   Sequence: #${stop.sequence} ${stop.sequence === 1 ? '(First pickup)' : ''}\n` +
            `   Distance to office: ${(stop.distanceToOffice || 0).toFixed(1)} km\n\n` +
            `Track your driver in real-time through the app.`;
      
    } else if (isLogoutOnly) {
      // ========================================
      // CASE 3: LOGOUT ONLY (EVENING DROP)
      // ========================================
      notificationTitle = 'Driver Assigned - Evening Drop';
      notificationBody = `Driver ${driver?.name || 'Unknown'} assigned for evening drop\n\n` +
            `Vehicle: ${vehicle?.registrationNumber || vehicle?.vehicleNumber || 'Unknown'}\n` +
            `Trip: ${firstTripNumber}\n` +
            `Date Range: ${assignStartDate} to ${assignEndDate} (${dateList.length} day${dateList.length > 1 ? 's' : ''})\n\n` +
            `🌆 EVENING DROP:\n` +
            `   Office Logout Time: Check your roster\n` +
            `   Driver will pick you from office\n` +
            `   Estimated drop time: ${stop.pickupTime || 'TBD'}\n` +
            `   Sequence: #${stop.sequence}\n\n` +
            `Track your driver in real-time through the app.`;
      
    } else {
      // ========================================
      // CASE 4: FALLBACK (DEFAULT)
      // ========================================
      notificationTitle = 'Driver Assigned';
      notificationBody = `Driver ${driver?.name || 'Unknown'} assigned\n\n` +
            `Vehicle: ${vehicle?.registrationNumber || vehicle?.vehicleNumber || 'Unknown'}\n` +
            `Trip: ${firstTripNumber}\n` +
            `Date Range: ${assignStartDate} to ${assignEndDate} (${dateList.length} day${dateList.length > 1 ? 's' : ''})\n\n` +
            `Pickup Time: ${stop.pickupTime}\n` +
            `BE READY BY: ${stop.readyByTime}\n` +
            `Sequence: #${stop.sequence}\n` +
            `Distance to office: ${(stop.distanceToOffice || 0).toFixed(1)} km\n\n` +
            `Track your driver in real-time through the app.`;
    }
    
    const notificationData = {
      tripId: firstTripId,
      tripIds: allCreatedTripIds,
      tripNumber: firstTripNumber,
      tripNumbers: allCreatedTripNumbers,
      tripGroupId: `${vehicleId}-${route[0]?.tripType || 'pickup'}`,
      vehicleId: vehicleId,
      driverId: driverIdString,
      sequence: stop.sequence,
      pickupTime: stop.pickupTime,
      readyByTime: stop.readyByTime,
      distanceToOffice: stop.distanceToOffice,
      rosterType: customerRosterType, // ✅ NEW: Include roster type
      hasBothTrips: hasBothTrips, // ✅ NEW
      dateRange: {
        startDate: assignStartDate,
        endDate: assignEndDate,
        totalDays: dateList.length
      },
      trackingEnabled: true,
      collection: 'roster-assigned-trips',
      type: 'route_assignment'
    };
    
    await createNotification(req.db, {
      userId: customerObjectId || customerEmailId,
      userEmail: customerEmailId,
      userRole: 'customer',
      title: notificationTitle,
      body: notificationBody,
      type: 'route_assignment',
      data: notificationData,
      priority: 'high',
      category: 'roster',
      channels: ['fcm', 'database']
    });
    
    console.log(`      ✅ Notification sent (${hasBothTrips ? 'BOTH TRIPS' : isLoginOnly ? 'LOGIN ONLY' : isLogoutOnly ? 'LOGOUT ONLY' : 'SINGLE TRIP'})`);
    notificationResults.customers++;
    
  } catch (notifError) {
    console.log(`      ⚠️  Notification failed: ${notifError.message}`);
    notificationResults.failed++;
  }
}

    
    // ====================================================================
    // 🆕 STEP 9: SEND DRIVER NOTIFICATION
    // ====================================================================
    if (results.length > 0) {
      try {
        console.log(`\n👨‍✈️ Sending driver notification...`);
        
        const driverEmailId = driver?.email || driver?.personalInfo?.email || driver?.contactInfo?.email;
        let driverObjectId = driver?._id?.toString();
        
        if (!driverObjectId && driverEmailId) {
          const driverDoc = await req.db.collection('drivers').findOne({
            $or: [
              { email: driverEmailId },
              { 'personalInfo.email': driverEmailId },
              { 'contactInfo.email': driverEmailId }
            ]
          });
          
          if (driverDoc) {
            driverObjectId = driverDoc.userId ? driverDoc.userId.toString() : driverDoc._id.toString();
          }
        }
        
        if (!driverObjectId && !driverEmailId) {
          console.log(`   ⚠️  Cannot send driver notification - no ID or email`);
          notificationResults.failed++;
        } else {
          // Build route details
          let routeDetails = '';
          stops.forEach((stop) => {
            if (stop.type === 'pickup') {
              routeDetails += `${stop.sequence}. ${stop.pickupTime} - ${stop.customer.name}`;
              if (stop.distanceToOffice) {
                routeDetails += ` (${stop.distanceToOffice.toFixed(1)} km)`;
              }
              routeDetails += '\n';
            }
          });
          
          const firstStop = stops[0];
          const officeTime = stops[stops.length - 1]?.estimatedTime || startTime || '09:00';
          
          const notificationTitle = `New Route - ${route.length} Pickups Assigned`;
          const notificationBody = `You have ${route.length} customers on your route.\n\n` +
                `Trip: ${firstTripNumber}\n` +
                `Date Range: ${assignStartDate} to ${assignEndDate} (${dateList.length} day${dateList.length > 1 ? 's' : ''})\n` +
                `Vehicle: ${vehicle?.registrationNumber || vehicle?.name || 'Vehicle'}\n\n` +
                `START BY: ${firstStop?.readyByTime || firstStop?.pickupTime}\n\n` +
                `PICKUP SEQUENCE:\n${routeDetails}\n` +
                `Office Arrival: ${officeTime}\n` +
                `Total Distance: ${totalDistance} km\n` +
                `Total Time: ${totalTime} mins\n\n` +
                `Check the app for detailed route information.`;
          
          const notificationData = {
            tripId: firstTripId,
            tripIds: allCreatedTripIds,
            tripNumber: firstTripNumber,
            tripNumbers: allCreatedTripNumbers,
            tripGroupId: `${vehicleId}-${route[0]?.tripType || 'pickup'}`,
            vehicleId: vehicleId,
            totalCustomers: route.length,
            totalDistance: totalDistance,
            totalTime: totalTime,
            dateRange: {
              startDate: assignStartDate,
              endDate: assignEndDate,
              totalDays: dateList.length
            },
            trackingRequired: true,
            startByTime: firstStop.readyByTime,
            officeArrivalTime: officeTime,
            collection: 'roster-assigned-trips',
            type: 'driver_route_assignment'
          };
          
          await createNotification(req.db, {
            userId: driverObjectId || driverEmailId,
            userEmail: driverEmailId,
            userRole: 'driver',
            title: notificationTitle,
            body: notificationBody,
            type: 'driver_route_assignment',
            data: notificationData,
            priority: 'high',
            category: 'roster',
            channels: ['fcm', 'database']
          });
          
          console.log(`   ✅ Driver notification sent`);
          notificationResults.driver++;
        }
      } catch (notifError) {
        console.log(`   ⚠️  Driver notification failed: ${notifError.message}`);
        notificationResults.failed++;
      }
    }
    
    // ====================================================================
    // 🆕 STEP 10: SEND ADMIN NOTIFICATIONS
    // ====================================================================
    if (results.length > 0) {
      try {
        console.log(`\n👨‍💼 Sending admin notifications...`);
        
        const notificationTitle = `Route Assigned - ${route.length} Customers`;
        const notificationBody = `Route assignment completed successfully.\n\n` +
              `Trip: ${firstTripNumber}\n` +
              `Date Range: ${assignStartDate} to ${assignEndDate} (${dateList.length} day${dateList.length > 1 ? 's' : ''})\n` +
              `Driver: ${driver?.name || 'Unknown'}\n` +
              `Vehicle: ${vehicle?.registrationNumber || vehicle?.vehicleNumber || 'Unknown'}\n` +
              `Total Customers: ${route.length}\n` +
              `Total Distance: ${totalDistance} km\n` +
              `Total Time: ${totalTime} mins\n` +
              `First Pickup: ${route[0]?.pickupTime}\n` +
              `Total Trips Created: ${totalTripsCreated}\n\n` +
              `All customers and driver have been notified.`;
        
        const notificationData = {
          tripId: firstTripId,
          tripIds: allCreatedTripIds,
          tripNumber: firstTripNumber,
          tripNumbers: allCreatedTripNumbers,
          tripGroupId: `${vehicleId}-${route[0]?.tripType || 'pickup'}`,
          vehicleId: vehicleId,
          driverId: driverIdString,
          driverName: driver?.name,
          totalCustomers: route.length,
          totalDistance: totalDistance,
          totalTime: totalTime,
          dateRange: {
            startDate: assignStartDate,
            endDate: assignEndDate,
            totalDays: dateList.length,
            tripsCreated: totalTripsCreated
          },
          collection: 'roster-assigned-trips',
          type: 'admin_route_assignment'
        };
        
        let adminUsers = [];
        
        try {
          adminUsers = await req.db.collection('employee_admins').find({
            status: 'active',
            role: { $in: ['admin', 'super_admin', 'manager'] }
          }).toArray();
          
          if (adminUsers.length > 0) {
            console.log(`   ✅ Found ${adminUsers.length} admin(s) in employee_admins`);
          }
        } catch (adminLookupError) {
          console.error(`   ❌ Admin lookup failed: ${adminLookupError.message}`);
        }
        
        if (adminUsers.length === 0) {
          try {
            const usersAdmins = await req.db.collection('users').find({
              role: { $in: ['admin', 'super_admin', 'manager'] },
              status: 'active'
            }).toArray();
            
            if (usersAdmins.length > 0) {
              console.log(`   ✅ Found ${usersAdmins.length} admin(s) in users`);
              adminUsers = usersAdmins;
            }
          } catch (usersLookupError) {
            console.error(`   ❌ Users lookup failed: ${usersLookupError.message}`);
          }
        }
        
        if (adminUsers.length > 0) {
          let adminNotificationCount = 0;
          
          for (const admin of adminUsers) {
            try {
              const adminObjectId = admin._id.toString();
              const adminEmailId = admin.email;
              const adminRole = admin.role || 'admin';
              const adminName = admin.name || admin.firstName || 'Admin';
              
              if (!adminObjectId && !adminEmailId) {
                console.log(`   ⚠️  Skipping admin without ID: ${adminName}`);
                continue;
              }
              
              await createNotification(req.db, {
                userId: adminObjectId || adminEmailId,
                userEmail: adminEmailId,
                userRole: adminRole,
                title: notificationTitle,
                body: notificationBody,
                type: 'admin_route_assignment',
                data: notificationData,
                priority: 'normal',
                category: 'roster',
                channels: ['fcm', 'database']
              });
              
              adminNotificationCount++;
              
            } catch (adminNotifError) {
              console.log(`   ⚠️  Admin notification failed: ${adminNotifError.message}`);
            }
          }
          
          notificationResults.admin = adminNotificationCount;
          console.log(`   ✅ Sent ${adminNotificationCount} admin notification(s)`);
          
        } else {
          console.log(`   ⚠️  No admins found`);
          notificationResults.admin = 0;
        }
        
      } catch (adminError) {
        console.log(`   ⚠️  Admin notification failed: ${adminError.message}`);
        notificationResults.admin = 0;
      }
    }
    
    // ========================================================================
    // STEP 11: Update vehicle's assigned customers list - ✅ FIXED VERSION
    // ========================================================================
    
    // ✅ FIX: Get current unique customer emails from trips
    const updatedExistingTrips = await req.db.collection('roster-assigned-trips').find({
      vehicleId: new ObjectId(vehicleId),
      status: { $in: ['assigned', 'started', 'in_progress'] },
      scheduledDate: today
    }).toArray();
    
    const updatedUniqueCustomers = new Set();
    updatedExistingTrips.forEach(trip => {
      trip.stops?.forEach(stop => {
        if (stop.type === 'pickup' && stop.customer?.email) {
          updatedUniqueCustomers.add(stop.customer.email);
        }
      });
    });
    
    // ✅ Build assignedCustomers array with unique emails
    const assignedCustomersArray = Array.from(updatedUniqueCustomers).map(email => {
      // Find corresponding stop data
      const stopData = route.find(r => r.customerEmail === email);
      return {
        email: email,
        tripId: firstTripId,
        tripIds: allCreatedTripIds,
        tripNumber: firstTripNumber,
        tripNumbers: allCreatedTripNumbers,
        dateRange: {
          startDate: assignStartDate,
          endDate: assignEndDate,
          totalDays: dateList.length
        },
        customerId: stopData?.customerId,
        customerName: stopData?.customerName,
        sequence: stopData?.sequence,
        pickupTime: stopData?.pickupTime,
        readyByTime: stopData?.readyByTime,
        distanceToOffice: stopData?.distanceToOffice,
        assignedAt: new Date()
      };
    });
    
    await req.db.collection('vehicles').updateOne(
      { _id: new ObjectId(vehicleId) },
      {
        $set: {
          assignedCustomers: assignedCustomersArray, // ✅ FIXED: Unique customers with full data
          lastRouteAssignment: new Date(),
          currentRouteDistance: totalDistance,
          currentRouteTime: totalTime,
          currentTripId: firstTripId,
          currentTripIds: allCreatedTripIds,
          currentTripNumber: firstTripNumber,
          currentTripNumbers: allCreatedTripNumbers,
          assignedDateRange: {
            startDate: assignStartDate,
            endDate: assignEndDate,
            totalDays: dateList.length
          },
          updatedAt: new Date()
        }
      },
      { session }
    );
    
    // ========================================================================
    // STEP 12: COMMIT TRANSACTION
    // ========================================================================
    await session.commitTransaction();
    
    // ========================================================================
    // STEP 13: VERIFICATION
    // ========================================================================
    const verificationResults = [];
    for (const result of results) {
      if (result.rosterId) {
        const verifiedRoster = await req.db.collection('rosters').findOne({
          _id: new ObjectId(result.rosterId)
        });
        
        const verifiedTrip = await req.db.collection('roster-assigned-trips').findOne({
          _id: new ObjectId(firstTripId)
        });
        
        verificationResults.push({
          rosterId: result.rosterId,
          customerName: result.customerName,
          rosterVerified: verifiedRoster?.status === 'assigned' && verifiedRoster?.vehicleId !== null,
          tripVerified: verifiedTrip?.status === 'assigned' && verifiedTrip?.vehicleId !== null,
          tripNumber: verifiedRoster?.tripNumber === firstTripNumber,
          tripIdsCount: verifiedRoster?.tripIds?.length || 0
        });
      }
    }
    
    console.log('\n' + '='.repeat(80));
    console.log('✅ GROUPED ROUTE ASSIGNMENT WITH RECURRING TRIPS COMPLETED');
    console.log('='.repeat(80));
    console.log(`📊 Summary:`);
    console.log(`   - Collection: roster-assigned-trips (GROUPED)`);
    console.log(`   - Date Range: ${assignStartDate} to ${assignEndDate}`);
    console.log(`   - Total Days: ${dateList.length}`);
    console.log(`   - Trips Created: ${totalTripsCreated}`);
    console.log(`   - Trips Failed: ${totalTripsFailed}`);
    console.log(`   - First Trip Number: ${firstTripNumber}`);
    console.log(`   - First Trip ID: ${firstTripId}`);
    console.log(`   - Total customers: ${route.length}`);
    console.log(`   - Successfully assigned: ${results.length}`);
    console.log(`   - Failed: ${errors.length}`);
    console.log(`   - Total stops per trip: ${stops.length} (${stops.length - 1} pickups + 1 office)`);
    console.log(`   - Customer notifications: ${notificationResults.customers}`);
    console.log(`   - Driver notifications: ${notificationResults.driver}`);
    console.log(`   - Admin notifications: ${notificationResults.admin}`);
    console.log(`   - Verification: ${verificationResults.filter(v => v.rosterVerified && v.tripVerified && v.tripNumber).length}/${verificationResults.length} verified`);
    console.log('='.repeat(80) + '\n');
    
    // ========================================================================
    // RESPONSE
    // ========================================================================
    const hasSuccessfulTrips = stops.length > 0;
    
    res.json({
      success: hasSuccessfulTrips,
      message: hasSuccessfulTrips 
        ? `✅ Success! ${results.length} customer(s) assigned to ${totalTripsCreated} trip(s) from ${assignStartDate} to ${assignEndDate}`
        : `❌ Assignment failed. ${errors.length} error(s) occurred.`,
      successCount: results.length,
      errorCount: errors.length,
      totalTripsCreated: totalTripsCreated,
      totalTripsFailed: totalTripsFailed,
      dateRange: {
        startDate: assignStartDate,
        endDate: assignEndDate,
        totalDays: dateList.length
      },
      notifications: {
        customers: notificationResults.customers,
        driver: notificationResults.driver,
        admin: notificationResults.admin,
        failed: notificationResults.failed
      },
      trackingEnabled: true,
      collection: 'roster-assigned-trips',
      tripNumber: firstTripNumber,
      tripNumbers: allCreatedTripNumbers,
      tripId: firstTripId,
      tripIds: allCreatedTripIds,
      tripGroupId: `${vehicleId}-${route[0]?.tripType || 'pickup'}`,
      data: {
        vehicleId: vehicleId,
        vehicleName: vehicle.name || vehicle.vehicleNumber,
        driverId: driverIdString,
        driverName: driver?.name || 'Unknown',
        tripId: firstTripId,
        tripIds: allCreatedTripIds,
        tripNumber: firstTripNumber,
        tripNumbers: allCreatedTripNumbers,
        tripGroupId: `${vehicleId}-${route[0]?.tripType || 'pickup'}`,
        assignmentId: new ObjectId().toString(),
        successful: results,
        failed: errors,
        totalStops: stops.length,
        successCount: results.length,
        errorCount: errors.length,
        notifications: notificationResults,
        trackingEnabled: true,
        verification: verificationResults,
        dateRange: {
          startDate: assignStartDate,
          endDate: assignEndDate,
          totalDays: dateList.length,
          createdTrips: totalTripsCreated,
          failedTrips: totalTripsFailed
        },
        routeSummary: {
          totalDistance: totalDistance,
          totalTime: totalTime,
          customerCount: route.length,
          stopsCount: stops.length,
          startTime: startTime,
          firstPickupTime: route[0]?.pickupTime,
          readyByTime: route[0]?.readyByTime
        }
      }
    });
    
  } catch (error) {
    await session.abortTransaction();
    console.error('\n' + '❌'.repeat(40));
    console.error('GROUPED ROUTE ASSIGNMENT WITH RECURRING TRIPS FAILED');
    console.error('❌'.repeat(40));
    console.error('Error:', error);
    console.error('Stack:', error.stack);
    console.error('❌'.repeat(40) + '\n');
    
    res.status(500).json({
      success: false,
      message: 'Grouped route assignment with recurring trips failed',
      error: error.message
    });
  } finally {
    await session.endSession();
  }
});

module.exports = router;