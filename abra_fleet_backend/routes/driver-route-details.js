// ============================================================================
// FILE: routes/driver_route_routes.js
// COMPLETE FIXED VERSION - Type-safe responses for Flutter
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

// ============================================================================
// HELPER FUNCTIONS FOR TYPE SAFETY
// ============================================================================
function toInt(value) {
  if (value === null || value === undefined) return 0;
  return Math.floor(Number(value) || 0);
}

function toDouble(value) {
  if (value === null || value === undefined) return 0.0;
  return Number(value) || 0.0;
}

// ============================================================================
// GET /api/driver/route/today
// Get today's complete route with all assigned customers
// ============================================================================
router.get('/today', async (req, res) => {
  try {
    console.log('='.repeat(80));
    console.log('🚗 [DRIVER ROUTE] Fetching route for driver');
    console.log('📅 [DRIVER ROUTE] Date:', new Date().toISOString());
    console.log('='.repeat(80));

    const jwtUser = req.user;
    
    console.log('🔑 [JWT TOKEN] Decoded user data:');
    console.log('   - userId:', jwtUser?.userId);
    console.log('   - email:', jwtUser?.email);
    console.log('   - role:', jwtUser?.role);
    
    if (!jwtUser || jwtUser.role !== 'driver') {
      console.log('❌ [DRIVER ROUTE] Invalid user or not a driver');
      return res.json({
        status: 'success',
        data: {
          hasRoute: false,
          message: 'Unauthorized: Not a driver account'
        }
      });
    }

    const driverEmail = jwtUser.email;
    
    if (!driverEmail) {
      console.log('❌ [DRIVER ROUTE] No email in JWT token');
      return res.json({
        status: 'success',
        data: {
          hasRoute: false,
          message: 'Email not found in authentication token'
        }
      });
    }

    const db = req.db;

    // ========================================================================
    // STEP 1: Find driver BY EMAIL ONLY
    // ========================================================================
    console.log('🔍 [DRIVER ROUTE] Searching for driver by email:', driverEmail);
    
    const driver = await db.collection('drivers').findOne({
      $or: [
        { email: driverEmail },
        { 'personalInfo.email': driverEmail }
      ]
    });

    if (!driver) {
      console.log('❌ [DRIVER ROUTE] Driver not found with email:', driverEmail);
      return res.json({
        status: 'success',
        data: {
          hasRoute: false,
          message: 'Driver profile not found'
        }
      });
    }

    console.log('✅ [DRIVER ROUTE] Driver found:', {
      _id: driver._id,
      driverId: driver.driverId,
      name: driver.personalInfo?.name || driver.name,
      email: driver.email || driver.personalInfo?.email
    });

    // ========================================================================
    // STEP 2: ONE-TIME FIX - Add driverEmail to trips if missing
    // ========================================================================
    if (driver.driverId) {
      // console.log('🔧 [DRIVER ROUTE] Ensuring trips have driverEmail field...');
      // Optional: Commented out to reduce log noise, uncomment if needed
      /*
      const updateResult = await db.collection('trips').updateMany(
        { 
          driverId: driver.driverId,
          driverEmail: { $exists: false }
        },
        { 
          $set: { 
            driverEmail: driverEmail,
            driverEmailUpdatedAt: new Date()
          } 
        }
      );
      */
    }

    // ========================================================================
    // STEP 3: Find TRIPS by email OR Driver ID (with active passengers)
    // ========================================================================
    console.log('📋 [DRIVER ROUTE] Searching for trips...');
    
    const trips = await db.collection('trips').find({
      $or: [
        { driverEmail: driverEmail },
        { driverId: driver.driverId }
      ],
      $or: [
        // Active trip status
        { status: { $in: ['assigned', 'scheduled', 'active', 'in_progress', 'ongoing'] } },
        // OR has waiting/active passengers (even if trip status is "completed")
        { 'passengers.status': { $in: ['waiting', 'picked_up', 'in_transit'] } }
      ]
    }).toArray();

    console.log(`📋 [DRIVER ROUTE] Found ${trips.length} trip(s) in trips collection`);

    // If no trips found, try rosters as fallback
    let rosters = [];
    let sourceCollection = 'trips';
    
    if (trips.length === 0) {
      console.log('   → No trips found, checking rosters collection...');
      
      rosters = await db.collection('rosters').find({
        $or: [
          { driverEmail: driverEmail },
          { driverId: driver.driverId }
        ],
        status: { $in: ['assigned', 'pending', 'active', 'in_progress'] }
      }).toArray();
      
      console.log(`📋 [DRIVER ROUTE] Found ${rosters.length} roster(s) in rosters collection`);
      sourceCollection = 'rosters';
    }

    // Debug if nothing found
    if (trips.length === 0 && rosters.length === 0) {
      console.log('⚠️  [DRIVER ROUTE] No active assignments found.');
      return res.json({
        status: 'success',
        data: {
          hasRoute: false,
          message: 'No active route for today'
        }
      });
    }

    // ========================================================================
    // STEP 4: Process data based on source collection
    // ========================================================================
    let enrichedCustomers = [];
    const firstTrip = trips[0];
    const firstRoster = rosters[0];

    if (sourceCollection === 'trips' && trips.length > 0) {
      console.log('👥 [DRIVER ROUTE] Processing passengers from trips...');
      
      // Extract all active passengers from all trips
      trips.forEach(trip => {
        if (trip.passengers && Array.isArray(trip.passengers)) {
          trip.passengers.forEach(passenger => {
            // Only include active passengers
            if (['waiting', 'picked_up', 'in_transit'].includes(passenger.status)) {
              
              // Determine locations (use passenger locations if available, otherwise trip locations)
              const hasPassengerPickup = passenger.pickupLocation && Object.keys(passenger.pickupLocation).length > 0;
              const hasPassengerDrop = passenger.dropLocation && Object.keys(passenger.dropLocation).length > 0;
              
              const fromLocation = hasPassengerPickup 
                ? passenger.pickupLocation.address 
                : (trip.pickupLocation?.address || 'Pickup Location');
              
              const toLocation = hasPassengerDrop 
                ? passenger.dropLocation.address 
                : (trip.dropLocation?.address || 'Drop Location');
              
              const fromCoords = hasPassengerPickup && passenger.pickupLocation.coordinates?.length === 2
                ? { lat: passenger.pickupLocation.coordinates[1], lng: passenger.pickupLocation.coordinates[0] }
                : (trip.pickupLocation?.coordinates?.length === 2 
                    ? { lat: trip.pickupLocation.coordinates[1], lng: trip.pickupLocation.coordinates[0] }
                    : null);
              
              const toCoords = hasPassengerDrop && passenger.dropLocation.coordinates?.length === 2
                ? { lat: passenger.dropLocation.coordinates[1], lng: passenger.dropLocation.coordinates[0] }
                : (trip.dropLocation?.coordinates?.length === 2 
                    ? { lat: trip.dropLocation.coordinates[1], lng: trip.dropLocation.coordinates[0] }
                    : null);
              
              enrichedCustomers.push({
                id: passenger.rosterId?.toString() || new ObjectId().toString(),
                tripId: trip.tripId,
                customerId: passenger.passengerId || 'unknown',
                name: passenger.customerName || 'Unknown Customer',
                phone: passenger.customerPhone || 'N/A',
                email: passenger.customerEmail || 'N/A',
                tripType: trip.tripType || 'pickup',
                tripTypeLabel: (trip.tripType === 'pickup' || trip.tripType === 'login') ? 'LOGIN' : 'LOGOUT',
                shift: trip.shift || 'morning',
                scheduledTime: passenger.estimatedPickupTime || trip.pickupTime || '09:00',
                endTime: passenger.dropTime || trip.dropTime,
                fromLocation: fromLocation,
                toLocation: toLocation,
                fromCoordinates: fromCoords,
                toCoordinates: toCoords,
                status: passenger.status,
                pickupSequence: toInt(passenger.sequence || 1),  // ✅ TYPE SAFE: Integer
                distance: toDouble(trip.distance || 0),  // ✅ TYPE SAFE: Double
                estimatedDuration: toInt(trip.duration || 0)  // ✅ TYPE SAFE: Integer
              });
            }
          });
        }
      });
      
      console.log(`✅ [DRIVER ROUTE] Processed ${enrichedCustomers.length} active passenger(s)`);
      
    } else if (sourceCollection === 'rosters' && rosters.length > 0) {
      console.log('👥 [DRIVER ROUTE] Processing customers from rosters...');
      
      enrichedCustomers = await Promise.all(rosters.map(async (roster, index) => {
        let customerName = roster.customerName || 'Unknown Customer';
        let customerPhone = roster.customerPhone || roster.contactInfo?.phone || 'N/A';
        let customerEmail = roster.customerEmail || roster.contactInfo?.email || 'N/A';
        let customerData = null;

        // Try to enrich customer data
        if (roster.userId) {
          customerData = await db.collection('users').findOne({
            $or: [
              { email: roster.userId  },
              { _id: roster.userId }
            ]
          });
        }

        if (customerData) {
          customerName = customerData.name || customerName;
          customerPhone = customerData.phone || customerPhone;
          customerEmail = customerData.email || customerEmail;
        }

        const tripType = roster.tripType || roster.rosterType || 'pickup';
        const isLogin = tripType === 'pickup' || tripType === 'login';
        
        const fromLocation = isLogin 
          ? (roster.locations?.pickup?.address || roster.pickupLocation || `${customerName}'s Home`)
          : (roster.officeLocation || roster.locations?.pickup?.address || 'Office Location');
        
        const toLocation = isLogin 
          ? (roster.locations?.drop?.address || roster.officeLocation || 'Office Location')
          : (roster.locations?.drop?.address || roster.dropLocation || `${customerName}'s Home`);
        
        const fromCoords = roster.locations?.pickup?.coordinates || roster.pickupCoordinates || 
          (roster.pickupLatitude && roster.pickupLongitude ? { lat: roster.pickupLatitude, lng: roster.pickupLongitude } : null);
        
        const toCoords = roster.locations?.drop?.coordinates || roster.dropCoordinates ||
          (roster.dropLatitude && roster.dropLongitude ? { lat: roster.dropLatitude, lng: roster.dropLongitude } : null);

        return {
          id: roster._id.toString(),
          customerId: roster.userId || roster.customerId || 'unknown',
          name: customerName,
          phone: customerPhone,
          email: customerEmail,
          tripType: isLogin ? 'pickup' : 'drop',
          tripTypeLabel: isLogin ? 'LOGIN' : 'LOGOUT',
          shift: roster.shift || 'morning',
          scheduledTime: roster.pickupTime || roster.startTime || roster.scheduledTime,
          endTime: roster.dropTime || roster.endTime,
          fromLocation: fromLocation,
          toLocation: toLocation,
          fromCoordinates: fromCoords,
          toCoordinates: toCoords,
          status: roster.status || 'pending',
          distance: toDouble(roster.routeDetails?.distanceFromPrevious || roster.distance || 0),  // ✅ TYPE SAFE: Double
          estimatedDuration: toInt(roster.estimatedDuration || 0),  // ✅ TYPE SAFE: Integer
          pickupSequence: toInt(roster.pickupSequence || index + 1),  // ✅ TYPE SAFE: Integer
          optimizedPickupTime: roster.optimizedPickupTime
        };
      }));
    }

    // Sort by pickup sequence
    enrichedCustomers.sort((a, b) => {
      const sequenceA = a.pickupSequence || 999;
      const sequenceB = b.pickupSequence || 999;
      if (sequenceA !== sequenceB) {
        return sequenceA - sequenceB;
      }
      const timeA = String(a.scheduledTime || '');
      const timeB = String(b.scheduledTime || '');
      return timeA.localeCompare(timeB);
    });

    console.log('✅ [DRIVER ROUTE] Sorted customers by sequence');

    // ========================================================================
    // STEP 6: Find Vehicle (ROBUST LOOKUP - FIXED)
    // ========================================================================
    console.log('🚙 [DRIVER ROUTE] Looking for vehicle...');
    
    let vehicle = null;
    let vehicleIdentifier = null;

    // 1. Check Driver's fixed assignment
    if (driver.assignedVehicle) {
        vehicleIdentifier = driver.assignedVehicle;
        console.log('   → Found assignment in Driver Profile:', vehicleIdentifier);
    }

    // 2. Check Trip's assignment (if not found yet)
    if (!vehicleIdentifier && firstTrip) {
        vehicleIdentifier = firstTrip.vehicleNumber || firstTrip.registrationNumber || firstTrip.vehicleId;
        if (vehicleIdentifier) console.log('   → Found assignment in Trip:', vehicleIdentifier);
    }

    // 3. Check Roster's assignment (THIS WAS THE MISSING LINK)
    if (!vehicleIdentifier && rosters.length > 0) {
        const rosterWithVehicle = rosters.find(r => r.vehicleNumber || r.vehicleId);
        if (rosterWithVehicle) {
            vehicleIdentifier = rosterWithVehicle.vehicleNumber || rosterWithVehicle.vehicleId;
            console.log('   → Found assignment in Roster:', vehicleIdentifier);
        }
    }

    // 4. Perform Database Lookup
    if (vehicleIdentifier) {
        try {
            const vehicleQuery = {
                $or: [
                    { vehicleNumber: vehicleIdentifier },
                    { registrationNumber: vehicleIdentifier }
                ]
            };

            // If it looks like a Mongo ID, check _id too
            if (ObjectId.isValid(vehicleIdentifier)) {
                vehicleQuery.$or.push({ _id: new ObjectId(vehicleIdentifier) });
            }

            vehicle = await db.collection('vehicles').findOne(vehicleQuery);
            
            if (vehicle) {
                console.log('✅ [DRIVER ROUTE] Vehicle details retrieved:', vehicle.model);
            } else {
                console.log('❌ [DRIVER ROUTE] Identifier found (' + vehicleIdentifier + ') but not found in Vehicles collection');
            }
        } catch (e) {
            console.log('   → Error querying vehicle:', e.message);
        }
    } else {
        console.log('⚠️  [DRIVER ROUTE] No vehicle identifier found in Driver, Trip, or Roster');
    }

    // ========================================================================
    // STEP 7: Calculate route summary with TYPE SAFETY
    // ========================================================================
    const totalDistance = enrichedCustomers.reduce((sum, c) => sum + (c.distance || 0), 0);
    const totalCustomers = enrichedCustomers.length;
    const completedCustomers = enrichedCustomers.filter(c => 
      c.status === 'completed' || c.status === 'picked_up' || c.status === 'in_transit'
    ).length;

    let totalCapacity = 0;
    let availableSeats = 0;
    if (vehicle && vehicle.capacity) {
      totalCapacity = typeof vehicle.capacity === 'number' 
        ? toInt(vehicle.capacity) 
        : toInt(vehicle.capacity.seating || 0);
      availableSeats = Math.max(0, totalCapacity - totalCustomers);
    }

    // ✅ TYPE SAFE: Ensure estimatedDuration is an integer
    const totalEstimatedDuration = toInt(
      enrichedCustomers.reduce((sum, c) => sum + (c.estimatedDuration || 0), 0)
    );

    console.log('📊 [DRIVER ROUTE] Route summary:', {
      totalCustomers,
      completedCustomers,
      totalDistance: totalDistance.toFixed(2) + ' km',
      availableSeats,
      estimatedDuration: totalEstimatedDuration + ' min'
    });

    console.log('='.repeat(80));
    console.log('✅ [DRIVER ROUTE] Successfully returning route data');
    console.log('='.repeat(80));

    // ========================================================================
    // STEP 8: Return response with TYPE-SAFE VALUES
    // ========================================================================
    res.json({
      status: 'success',
      data: {
        hasRoute: true,
        vehicle: vehicle ? {
          id: vehicle._id.toString(),
          registrationNumber: vehicle.registrationNumber || vehicle.vehicleNumber,
          model: vehicle.model,
          make: vehicle.make,
          capacity: vehicle.capacity,
          totalCapacity: toInt(totalCapacity),  // ✅ TYPE SAFE: Integer
          availableSeats: toInt(availableSeats),  // ✅ TYPE SAFE: Integer
          fuelType: vehicle.fuelType,
          status: vehicle.status
        } : null,
        routeSummary: {
          totalCustomers: toInt(totalCustomers),  // ✅ TYPE SAFE: Integer
          completedCustomers: toInt(completedCustomers),  // ✅ TYPE SAFE: Integer
          pendingCustomers: toInt(totalCustomers - completedCustomers),  // ✅ TYPE SAFE: Integer
          totalDistance: Math.round(totalDistance * 10) / 10,  // ✅ TYPE SAFE: Double (rounded to 1 decimal)
          estimatedDuration: totalEstimatedDuration,  // ✅ TYPE SAFE: Integer
          routeType: sourceCollection === 'trips' ? (firstTrip?.tripType || 'pickup') : (firstRoster?.rosterType || 'mixed'),
          availableSeats: toInt(availableSeats)  // ✅ TYPE SAFE: Integer
        },
        customers: enrichedCustomers,
        tripId: firstTrip?.tripId || null,
        rosterId: enrichedCustomers[0]?.id || (firstRoster?._id.toString()) || null,
        startDate: firstRoster?.startDate || null,
        endDate: firstRoster?.endDate || null
      }
    });

  } catch (error) {
    console.error('❌ [DRIVER ROUTE] ERROR:', error);
    console.error('Stack trace:', error.stack);
    res.status(500).json({
      status: 'error',
      message: 'Failed to fetch route details',
      error: error.message
    });
  }
});

// ============================================================================
// POST /api/driver/route/mark-customer-picked
// Mark customer as picked up with location
// ============================================================================
router.post('/mark-customer-picked', async (req, res) => {
  try {
    const jwtUser = req.user;
    const { rosterId, latitude, longitude } = req.body;
    const db = req.db;

    console.log('='.repeat(80));
    console.log('📍 [MARK PICKED] Customer pickup request');
    console.log('   → Roster ID:', rosterId);
    console.log('   → Driver email:', jwtUser?.email);
    console.log('   → Location:', latitude && longitude ? `${latitude}, ${longitude}` : 'Not provided');
    console.log('='.repeat(80));

    if (!rosterId) {
      console.log('❌ [MARK PICKED] Roster ID missing');
      return res.status(400).json({
        status: 'error',
        message: 'Roster ID is required'
      });
    }

    const driverEmail = jwtUser.email;

    // Get driver by email
    const driver = await db.collection('drivers').findOne({
      $or: [
        { email: driverEmail },
        { 'personalInfo.email': driverEmail }
      ]
    });

    if (!driver) {
      console.log('❌ [MARK PICKED] Driver not found');
      return res.status(404).json({
        status: 'error',
        message: 'Driver not found'
      });
    }

    console.log('✅ [MARK PICKED] Driver found:', driver.driverId || driver.name);

    // Try to find in trips collection first
    const trip = await db.collection('trips').findOne({
      driverEmail: driverEmail,
      'passengers.rosterId': new ObjectId(rosterId)
    });

    if (trip) {
      // Update passenger in trip
      const result = await db.collection('trips').updateOne(
        {
          _id: trip._id,
          'passengers.rosterId': new ObjectId(rosterId)
        },
        {
          $set: {
            'passengers.$.status': 'picked_up',
            'passengers.$.pickupTime': new Date(),
            'passengers.$.actualPickupLocation': latitude && longitude ? {
              lat: latitude,
              lng: longitude
            } : null,
            updatedAt: new Date()
          },
          $inc: {
            passengersPickedCount: 1,
            passengersWaitingCount: -1
          }
        }
      );

      console.log('✅ [MARK PICKED] Passenger marked as picked up in trip');

      return res.json({
        status: 'success',
        message: 'Customer marked as picked up',
        data: {
          rosterId,
          pickedUpAt: new Date(),
          location: latitude && longitude ? { latitude, longitude } : null
        }
      });
    }

    // If not in trips, try rosters collection
    const roster = await db.collection('rosters').findOne({
      _id: new ObjectId(rosterId)
    });

    if (!roster) {
      console.log('❌ [MARK PICKED] Roster not found');
      return res.status(404).json({
        status: 'error',
        message: 'Roster not found'
      });
    }

    console.log('✅ [MARK PICKED] Roster found:', {
      customerName: roster.customerName,
      currentStatus: roster.status
    });

    const updateData = {
      status: 'picked_up',
      pickedUpAt: new Date(),
      pickedUpBy: driver.driverId || driver.email,
      lastStatusUpdate: new Date(),
      updatedAt: new Date()
    };

    if (latitude && longitude) {
      updateData.actualPickupLocation = {
        type: 'Point',
        coordinates: [longitude, latitude],
        latitude: latitude,
        longitude: longitude
      };
      console.log('📍 [MARK PICKED] Recording pickup location');
    }

    const result = await db.collection('rosters').updateOne(
      { _id: new ObjectId(rosterId) },
      {
        $set: updateData,
        $push: {
          statusHistory: {
            status: 'picked_up',
            timestamp: new Date(),
            updatedBy: driver.driverId || driver.email,
            location: latitude && longitude ? { latitude, longitude } : null
          }
        }
      }
    );

    console.log('✅ [MARK PICKED] Roster updated successfully');
    console.log('='.repeat(80));

    res.json({
      status: 'success',
      message: 'Customer marked as picked up',
      data: { 
        rosterId, 
        pickedUpAt: updateData.pickedUpAt,
        customerName: roster.customerName,
        location: latitude && longitude ? { latitude, longitude } : null
      }
    });

  } catch (error) {
    console.error('❌ [MARK PICKED] ERROR:', error);
    console.error('Stack trace:', error.stack);
    res.status(500).json({
      status: 'error',
      message: 'Failed to mark customer as picked up',
      error: error.message
    });
  }
});

// ============================================================================
// POST /api/driver/route/mark-customer-dropped
// Mark customer as dropped off
// ============================================================================
router.post('/mark-customer-dropped', async (req, res) => {
  try {
    const jwtUser = req.user;
    const { rosterId, latitude, longitude } = req.body;
    const db = req.db;

    console.log(`🏁 [MARK DROPPED] Marking roster ${rosterId} as dropped`);

    if (!rosterId) {
      return res.status(400).json({
        status: 'error',
        message: 'Roster ID is required'
      });
    }

    const driverEmail = jwtUser.email;

    const driver = await db.collection('drivers').findOne({
      $or: [
        { email: driverEmail },
        { 'personalInfo.email': driverEmail }
      ]
    });

    if (!driver) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver not found'
      });
    }

    // Try trips collection first
    const trip = await db.collection('trips').findOne({
      driverEmail: driverEmail,
      'passengers.rosterId': new ObjectId(rosterId)
    });

    if (trip) {
      await db.collection('trips').updateOne(
        {
          _id: trip._id,
          'passengers.rosterId': new ObjectId(rosterId)
        },
        {
          $set: {
            'passengers.$.status': 'dropped_off',
            'passengers.$.dropTime': new Date(),
            'passengers.$.actualDropLocation': latitude && longitude ? {
              lat: latitude,
              lng: longitude
            } : null,
            updatedAt: new Date()
          },
          $inc: {
            passengersDroppedCount: 1,
            passengersPickedCount: -1
          }
        }
      );

      console.log(`✅ [MARK DROPPED] Passenger marked as dropped off in trip`);

      return res.json({
        status: 'success',
        message: 'Customer marked as dropped off',
        data: {
          rosterId,
          droppedOffAt: new Date(),
          location: latitude && longitude ? { latitude, longitude } : null
        }
      });
    }

    // Try rosters collection
    const updateData = {
      status: 'completed',
      droppedOffAt: new Date(),
      droppedOffBy: driver.driverId || driver.email,
      lastStatusUpdate: new Date(),
      updatedAt: new Date()
    };

    if (latitude && longitude) {
      updateData.actualDropLocation = {
        type: 'Point',
        coordinates: [longitude, latitude],
        latitude: latitude,
        longitude: longitude
      };
    }

    await db.collection('rosters').updateOne(
      { _id: new ObjectId(rosterId) },
      {
        $set: updateData,
        $push: {
          statusHistory: {
            status: 'completed',
            timestamp: new Date(),
            updatedBy: driver.driverId || driver.email,
            location: latitude && longitude ? { latitude, longitude } : null
          }
        }
      }
    );

    console.log(`✅ [MARK DROPPED] Customer marked as dropped off`);

    res.json({
      status: 'success',
      message: 'Customer marked as dropped off',
      data: { 
        rosterId, 
        droppedOffAt: updateData.droppedOffAt,
        location: latitude && longitude ? { latitude, longitude } : null
      }
    });

  } catch (error) {
    console.error('❌ [MARK DROPPED] ERROR:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to mark customer as dropped off',
      error: error.message
    });
  }
});

// ============================================================================
// POST /api/driver/route/update-customer-status
// Update customer status (generic)
// ============================================================================
router.post('/update-customer-status', async (req, res) => {
  try {
    const jwtUser = req.user;
    const { rosterId, status } = req.body;
    const db = req.db;

    console.log(`🔄 [UPDATE STATUS] Updating roster ${rosterId} to ${status}`);

    if (!rosterId || !status) {
      return res.status(400).json({
        status: 'error',
        message: 'Roster ID and status are required'
      });
    }

    const validStatuses = ['pending', 'picked_up', 'in_transit', 'dropped_off', 'completed', 'waiting'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({
        status: 'error',
        message: `Invalid status. Valid statuses: ${validStatuses.join(', ')}`
      });
    }

    const driverEmail = jwtUser.email;

    const driver = await db.collection('drivers').findOne({
      $or: [
        { email: driverEmail },
        { 'personalInfo.email': driverEmail }
      ]
    });

    if (!driver) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver not found'
      });
    }

    // Try updating in trips collection first
    const trip = await db.collection('trips').findOne({
      driverEmail: driverEmail,
      'passengers.rosterId': new ObjectId(rosterId)
    });

    if (trip) {
      await db.collection('trips').updateOne(
        {
          _id: trip._id,
          'passengers.rosterId': new ObjectId(rosterId)
        },
        {
          $set: {
            'passengers.$.status': status,
            updatedAt: new Date()
          }
        }
      );

      console.log(`✅ [UPDATE STATUS] Passenger status updated in trip`);

      return res.json({
        status: 'success',
        message: 'Customer status updated successfully',
        data: {
          rosterId,
          newStatus: status,
          updatedAt: new Date()
        }
      });
    }

    // Try rosters collection
    const result = await db.collection('rosters').updateOne(
      { _id: new ObjectId(rosterId) },
      {
        $set: {
          status: status,
          lastStatusUpdate: new Date(),
          updatedAt: new Date()
        },
        $push: {
          statusHistory: {
            status: status,
            timestamp: new Date(),
            updatedBy: driver.driverId || driver.email
          }
        }
      }
    );

    console.log(`✅ [UPDATE STATUS] Status updated: ${result.modifiedCount} document(s)`);

    res.json({
      status: 'success',
      message: 'Customer status updated successfully',
      data: {
        rosterId,
        newStatus: status,
        updatedAt: new Date()
      }
    });

  } catch (error) {
    console.error('❌ [UPDATE STATUS] ERROR:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to update customer status',
      error: error.message
    });
  }
});

// ============================================================================
// GET /api/driver/route/navigation/:rosterId
// Get navigation details for a specific customer
// ============================================================================
router.get('/navigation/:rosterId', async (req, res) => {
  try {
    const jwtUser = req.user;
    const { rosterId } = req.params;
    const db = req.db;

    console.log(`🗺️  [NAVIGATION] Getting navigation for roster ${rosterId}`);

    const driverEmail = jwtUser.email;

    const driver = await db.collection('drivers').findOne({
      $or: [
        { email: driverEmail },
        { 'personalInfo.email': driverEmail }
      ]
    });

    if (!driver) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver not found'
      });
    }

    // Try finding in trips collection first
    const trip = await db.collection('trips').findOne({
      driverEmail: driverEmail,
      'passengers.rosterId': new ObjectId(rosterId)
    });

    if (trip) {
      const passenger = trip.passengers.find(p => p.rosterId.toString() === rosterId);
      
      if (passenger) {
        const hasPassengerPickup = passenger.pickupLocation && Object.keys(passenger.pickupLocation).length > 0;
        const hasPassengerDrop = passenger.dropLocation && Object.keys(passenger.dropLocation).length > 0;
        
        const pickupAddr = hasPassengerPickup ? passenger.pickupLocation.address : trip.pickupLocation?.address;
        const dropAddr = hasPassengerDrop ? passenger.dropLocation.address : trip.dropLocation?.address;
        
        const pickupCoords = hasPassengerPickup && passenger.pickupLocation.coordinates?.length === 2
          ? { lat: passenger.pickupLocation.coordinates[1], lng: passenger.pickupLocation.coordinates[0] }
          : (trip.pickupLocation?.coordinates?.length === 2 
              ? { lat: trip.pickupLocation.coordinates[1], lng: trip.pickupLocation.coordinates[0] }
              : null);
        
        const dropCoords = hasPassengerDrop && passenger.dropLocation.coordinates?.length === 2
          ? { lat: passenger.dropLocation.coordinates[1], lng: passenger.dropLocation.coordinates[0] }
          : (trip.dropLocation?.coordinates?.length === 2 
              ? { lat: trip.dropLocation.coordinates[1], lng: trip.dropLocation.coordinates[0] }
              : null);

        return res.json({
          status: 'success',
          data: {
            customer: {
              name: passenger.customerName || 'Unknown',
              phone: passenger.customerPhone || 'N/A'
            },
            pickup: {
              address: pickupAddr,
              coordinates: pickupCoords
            },
            drop: {
              address: dropAddr,
              coordinates: dropCoords
            },
            scheduledTime: passenger.estimatedPickupTime || trip.pickupTime,
            distance: toDouble(trip.distance || 0),  // ✅ TYPE SAFE: Double
            estimatedDuration: toInt(trip.duration || 0)  // ✅ TYPE SAFE: Integer
          }
        });
      }
    }

    // Try rosters collection
    const roster = await db.collection('rosters').findOne({
      _id: new ObjectId(rosterId)
    });

    if (!roster) {
      return res.status(404).json({
        status: 'error',
        message: 'Roster not found'
      });
    }

    let customer = null;
    if (roster.userId) {
      customer = await db.collection('users').findOne({
        $or: [
          { email: roster.userId  },
          { _id: roster.userId }
        ]
      });
    }

    const isLogin = (roster.tripType || roster.rosterType) === 'pickup' || (roster.tripType || roster.rosterType) === 'login';
    
    const pickupCoords = roster.locations?.pickup?.coordinates || roster.pickupCoordinates;
    const dropCoords = roster.locations?.drop?.coordinates || roster.dropCoordinates;

    console.log(`✅ [NAVIGATION] Navigation details retrieved`);

    res.json({
      status: 'success',
      data: {
        customer: {
          name: customer?.name || roster.customerName || 'Unknown',
          phone: customer?.phone || roster.customerPhone || 'N/A'
        },
        pickup: {
          address: isLogin 
            ? (roster.locations?.pickup?.address || roster.pickupLocation)
            : (roster.officeLocation || roster.locations?.pickup?.address),
          coordinates: pickupCoords
        },
        drop: {
          address: isLogin 
            ? (roster.locations?.drop?.address || roster.officeLocation)
            : (roster.locations?.drop?.address || roster.dropLocation),
          coordinates: dropCoords
        },
        scheduledTime: roster.pickupTime || roster.scheduledTime,
        distance: toDouble(roster.distance || 0),  // ✅ TYPE SAFE: Double
        estimatedDuration: toInt(roster.estimatedDuration || 0)  // ✅ TYPE SAFE: Integer
      }
    });

  } catch (error) {
    console.error('❌ [NAVIGATION] ERROR:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to fetch navigation details',
      error: error.message
    });
  }
});

module.exports = router;