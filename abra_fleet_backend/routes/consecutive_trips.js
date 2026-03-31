const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { getRedisClient } = require('../config/redis');

// 🚨 EMERGENCY DEBUG - ADD THIS
router.use((req, res, next) => {
  console.log('\n🚨 CONSECUTIVE TRIPS ROUTER HIT!');
  console.log('   Path:', req.path);
  console.log('   Method:', req.method);
  console.log('   Has User?', !!req.user);
  console.log('   User Email:', req.user?.email || 'NONE');
  console.log('   Headers:', Object.keys(req.headers));
  next();
});

console.log('✅ Consecutive Trips Router Loaded');

router.use((req, res, next) => {
  console.log('\n🔐 CONSECUTIVE TRIPS - Request Details');
  console.log('─'.repeat(80));
  console.log('   Path:', req.path);
  console.log('   Method:', req.method);
  console.log('   User:', req.user ? req.user.email : '❌ NOT SET');
  console.log('   User Role:', req.user ? req.user.role : '❌ NOT SET');
  console.log('   Auth Header:', req.headers.authorization ? '✅ Present' : '❌ Missing');
  console.log('─'.repeat(80) + '\n');
  next();
});

// ============================================
// GET ALL VEHICLES WITH LIVE STATUS (NEW!)
// ============================================
router.get('/vehicles/live-status', async (req, res) => {
  console.log('\n🚗 GET ALL VEHICLES LIVE STATUS');
  console.log('─'.repeat(80));
  
  try {
    const db = req.db;
    const redis = getRedisClient();
    
    // Get all active vehicles
    const vehicles = await db.collection('vehicles').find({
      status: { $in: ['active', 'idle'] }
    }).toArray();
    
    console.log('   📊 Found vehicles:', vehicles.length);
    
    // Enhance each vehicle with live data from Redis
    const enhancedVehicles = await Promise.all(vehicles.map(async (vehicle) => {
      const vehicleId = vehicle._id.toString();
      
      let liveLocation = null;
      let currentTrip = null;
      let tripCount = 0;
      let driverInfo = null;
      
      // Fetch driver information if assigned
      if (vehicle.assignedDriver) {
        try {
          const driver = await db.collection('drivers').findOne({
            driverId: vehicle.assignedDriver
          });
          
          if (driver) {
            driverInfo = {
              driverId: driver.driverId,
              name: driver.name,
              phone: driver.phoneNumber || driver.phone,
              email: driver.email
            };
          }
        } catch (err) {
          console.error(`   ⚠️ Error fetching driver ${vehicle.assignedDriver}:`, err.message);
        }
      }
      
      if (redis) {
        // Get live location
        const locationData = await redis.get(`vehicle:${vehicleId}:location`);
        if (locationData) {
          liveLocation = JSON.parse(locationData);
        }
        
        // Get current trip
        const currentTripData = await redis.get(`vehicle:${vehicleId}:current_trip`);
        if (currentTripData) {
          const parsed = JSON.parse(currentTripData);
          currentTrip = {
            tripId: parsed.tripId,
            status: parsed.status,
            startedAt: parsed.startedAt,
          };
        }
      }
      
      // Get trip count for today from MongoDB
      const today = new Date().toISOString().split('T')[0];
      const trips = await db.collection('trips').countDocuments({
        vehicleId: vehicle._id,
        scheduledDate: today,
      });
      tripCount = trips;
      
      return {
        _id: vehicle._id,
        registrationNumber: vehicle.registrationNumber,
        driver: driverInfo,
        capacity: vehicle.capacity,
        status: vehicle.status,
        liveLocation: liveLocation || vehicle.liveLocation || null,
        currentTrip: currentTrip,
        tripsToday: tripCount,
        make: vehicle.make,
        model: vehicle.model,
      };
    }));
    
    console.log('✅ LIVE STATUS FETCHED SUCCESSFULLY');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: enhancedVehicles,
      count: enhancedVehicles.length,
    });
    
  } catch (error) {
    console.error('❌ ERROR FETCHING LIVE STATUS:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch live status',
      message: error.message,
    });
  }
});

// ============================================
// GET VEHICLE WITH CURRENT + QUEUED TRIPS
// ============================================
// ============================================
// GET VEHICLE WITH CURRENT + QUEUED TRIPS
// ============================================
router.get('/vehicle/:vehicleId/consecutive-trips', async (req, res) => {
  console.log('\n🚗 GET CONSECUTIVE TRIPS FOR VEHICLE');
  console.log('─'.repeat(80));
  
  try {
    const { vehicleId } = req.params;
    console.log('   Vehicle ID:', vehicleId);
    
    const db = req.db;
    const redis = getRedisClient();
    
    // 1. Get vehicle details
    const vehicle = await db.collection('vehicles').findOne({
      _id: new ObjectId(vehicleId)
    });
    
    if (!vehicle) {
      return res.status(404).json({
        success: false,
        error: 'Vehicle not found',
      });
    }
    
    console.log('   ✅ Vehicle found:', vehicle.registrationNumber);
    
    // 2. Get current trip from Redis (FAST!)
    let currentTrip = null;
    let currentTripData = null;
    
    if (redis) {
      const currentTripKey = await redis.get(`vehicle:${vehicleId}:current_trip`);
      if (currentTripKey) {
        currentTripData = JSON.parse(currentTripKey);
        console.log('   📍 Current trip from Redis:', currentTripData.tripId);
        
        // Get full trip details from MongoDB
        currentTrip = await db.collection('trips').findOne({
          _id: new ObjectId(currentTripData.tripId)
        });
        
        if (currentTrip) {
          // Get passenger statuses from Redis
          const passengerStatuses = await redis.hgetall(`trip:${currentTripData.tripId}:passengers`);
          const tripStats = await redis.hgetall(`trip:${currentTripData.tripId}:stats`);
          
          // Enhance passengers with real-time status
          if (currentTrip.passengers) {
            currentTrip.passengers = currentTrip.passengers.map(p => {
              const statusData = passengerStatuses[p.rosterId || p.passengerId];
              if (statusData) {
                const parsed = JSON.parse(statusData);
                p.status = parsed.status;
                p.pickupTime = parsed.timestamp;
              }
              return p;
            });
          }
          
          // Add real-time stats
          currentTrip.passengersPickedCount = parseInt(tripStats.pickedCount || 0);
          currentTrip.passengersWaitingCount = parseInt(tripStats.waitingCount || currentTrip.totalPassengers || 0);
          currentTrip.passengersDroppedCount = parseInt(tripStats.droppedCount || 0);
        }
      }
    }
    
    // ✅ FIX: Use Date objects for comparison instead of strings
    // Get today's date range (start and end of day)
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    
    const todayEnd = new Date();
    todayEnd.setHours(23, 59, 59, 999);
    
    console.log('   📅 Looking for trips between:', todayStart.toISOString(), 'and', todayEnd.toISOString());
    
    // If no Redis data, get current trip from MongoDB (status = in-progress or assigned)
    if (!currentTrip) {
      currentTrip = await db.collection('trips').findOne({
        vehicleId: new ObjectId(vehicleId),
        status: { $in: ['assigned', 'in-progress'] },
        scheduledDate: {
          $gte: todayStart,
          $lte: todayEnd
        }
      }, {
        sort: { tripSequence: 1 } // Get earliest trip
      });
      
      if (currentTrip) {
        console.log('   📍 Current trip from MongoDB:', currentTrip.tripNumber || currentTrip.tripId);
      } else {
        console.log('   ⚠️  No current trip found for today');
      }
    }
    
    // 3. Get queued trips (remaining trips for today)
    const queuedTrips = await db.collection('trips').find({
      vehicleId: new ObjectId(vehicleId),
      status: 'assigned',
      scheduledDate: {
        $gte: todayStart,
        $lte: todayEnd
      },
      tripSequence: currentTrip ? { $gt: currentTrip.tripSequence } : { $exists: true }
    }).sort({ tripSequence: 1 }).toArray();
    
    console.log('   📋 Queued trips:', queuedTrips.length);
    
    // 4. Get vehicle live location from Redis
    let liveLocation = null;
    if (redis) {
      const locationData = await redis.get(`vehicle:${vehicleId}:location`);
      if (locationData) {
        liveLocation = JSON.parse(locationData);
        console.log('   📍 Live location from Redis');
      }
    }
    
    console.log('✅ CONSECUTIVE TRIPS FETCHED SUCCESSFULLY');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: {
        vehicle: {
          _id: vehicle._id,
          registrationNumber: vehicle.registrationNumber,
          model: vehicle.model || 'N/A',
          capacity: vehicle.capacity,
          driver: vehicle.assignedDriver || null,
          liveLocation: liveLocation || vehicle.liveLocation || null,
        },
        currentTrip: currentTrip,
        queuedTrips: queuedTrips,
        totalTripsToday: (currentTrip ? 1 : 0) + queuedTrips.length,
      }
    });
    
  } catch (error) {
    console.error('❌ ERROR FETCHING CONSECUTIVE TRIPS:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch consecutive trips',
      message: error.message,
    });
  }
});

// ============================================
// UPDATE PASSENGER STATUS (FROM DRIVER APP)
// ============================================
router.post('/trip/:tripId/passenger/:rosterId/status', async (req, res) => {
  console.log('\n✅ UPDATE PASSENGER STATUS');
  console.log('─'.repeat(80));
  
  try {
    const { tripId, rosterId } = req.params;
    const { status, timestamp } = req.body; // status: 'picked' or 'dropped'
    
    console.log('   Trip ID:', tripId);
    console.log('   Roster ID:', rosterId);
    console.log('   Status:', status);
    
    const db = req.db;
    const redis = getRedisClient();
    
    // Update in MongoDB
    const trip = await db.collection('trips').findOne({
      _id: new ObjectId(tripId)
    });
    
    if (!trip) {
      return res.status(404).json({
        success: false,
        error: 'Trip not found',
      });
    }
    
    // Update passenger status in trip
    const passengerIndex = trip.passengers.findIndex(p => 
      p.rosterId.toString() === rosterId
    );
    
    if (passengerIndex === -1) {
      return res.status(404).json({
        success: false,
        error: 'Passenger not found in trip',
      });
    }
    
    // Update in MongoDB
    await db.collection('trips').updateOne(
      { _id: new ObjectId(tripId), 'passengers.rosterId': new ObjectId(rosterId) },
      {
        $set: {
          'passengers.$.status': status,
          'passengers.$.pickupTime': status === 'picked' ? timestamp : trip.passengers[passengerIndex].pickupTime,
          'passengers.$.dropTime': status === 'dropped' ? timestamp : null,
        }
      }
    );
    
    // Calculate counts
    const pickedCount = trip.passengers.filter(p => p.status === 'picked').length + (status === 'picked' ? 1 : 0);
    const droppedCount = trip.passengers.filter(p => p.status === 'dropped').length + (status === 'dropped' ? 1 : 0);
    const waitingCount = trip.totalPassengers - pickedCount - droppedCount;
    
    await db.collection('trips').updateOne(
      { _id: new ObjectId(tripId) },
      {
        $set: {
          passengersPickedCount: pickedCount,
          passengersDroppedCount: droppedCount,
          passengersWaitingCount: waitingCount,
        }
      }
    );
    
    // Update in Redis (INSTANT!)
    if (redis) {
      await redis.hset(
        `trip:${tripId}:passengers`,
        rosterId,
        JSON.stringify({ status, timestamp })
      );
      
      await redis.hset(`trip:${tripId}:stats`, 'pickedCount', pickedCount);
      await redis.hset(`trip:${tripId}:stats`, 'droppedCount', droppedCount);
      await redis.hset(`trip:${tripId}:stats`, 'waitingCount', waitingCount);
    }
    
    // Emit WebSocket event to admin
    const io = req.app.get('wsServer');
    if (io) {
      io.to('admin-room').emit('passenger_status_changed', {
        tripId,
        rosterId,
        vehicleId: trip.vehicleId.toString(),
        status,
        timestamp,
        pickedCount,
        droppedCount,
        waitingCount,
      });
    }
    
    console.log('✅ PASSENGER STATUS UPDATED');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Passenger status updated',
      data: {
        tripId,
        rosterId,
        status,
        pickedCount,
        droppedCount,
        waitingCount,
      }
    });
    
  } catch (error) {
    console.error('❌ ERROR UPDATING PASSENGER STATUS:', error);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to update passenger status',
      message: error.message,
    });
  }
});

module.exports = router;