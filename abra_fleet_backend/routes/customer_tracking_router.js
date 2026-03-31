// routes/customer_tracking_router.js
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');

// ============================================================================
// @route   GET /api/customer/track-trip/:tripId
// @desc    Get complete trip tracking data for customer (FIXED FOR PRE-GROUPED TRIPS)
// @access  Private (Customer only)
// ============================================================================
router.get('/track-trip/:tripId', verifyToken, async (req, res) => {
  try {
    const { tripId } = req.params;
    const customerEmail = req.user.email; // From JWT token
    
    console.log('\n' + '='.repeat(80));
    console.log('📍 CUSTOMER TRACKING REQUEST');
    console.log('='.repeat(80));
    console.log(`Trip ID: ${tripId}`);
    console.log(`Customer: ${customerEmail}`);
    
    // ========================================================================
    // STEP 1: Get trip document
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
    console.log(`   Status: ${trip.status}`);
    console.log(`   Vehicle: ${trip.vehicleNumber}`);
    console.log(`   Total stops: ${trip.stops?.length || 0}`);
    
    // ========================================================================
    // STEP 2: Find which stop belongs to this customer
    // ========================================================================
    const stops = trip.stops || [];
    const customerStop = stops.find(stop => {
      const stopEmail = stop.customer?.email?.toLowerCase();
      return stopEmail === customerEmail.toLowerCase();
    });
    
    if (!customerStop) {
      console.log('❌ Customer stop not found in trip');
      console.log(`   Available stops: ${stops.map(s => s.customer?.email).join(', ')}`);
      return res.status(404).json({
        success: false,
        message: 'Your stop not found in this trip'
      });
    }
    
    console.log(`✅ Found customer stop: ${customerStop.customer?.name}`);
    console.log(`   Sequence: ${customerStop.sequence}`);
    console.log(`   Address: ${customerStop.location?.address}`);
    console.log(`   Coordinates: ${customerStop.location?.coordinates?.latitude}, ${customerStop.location?.coordinates?.longitude}`);
    
    // ========================================================================
    // STEP 3: Get driver details
    // ========================================================================
    let driver = null;
    if (trip.driverId) {
      const driverDoc = await req.db.collection('drivers').findOne({
        _id: trip.driverId
      });
      
      if (driverDoc) {
        driver = {
          driverId: driverDoc.driverId || driverDoc._id.toString(),
          name: driverDoc.personalInfo?.name || driverDoc.name || trip.driverName || 'Unknown Driver',
          phone: driverDoc.personalInfo?.phone || driverDoc.phone || trip.driverPhone || '',
          email: driverDoc.personalInfo?.email || driverDoc.email || trip.driverEmail || ''
        };
      } else {
        // Fallback to trip document data
        driver = {
          driverId: trip.driverId.toString(),
          name: trip.driverName || 'Unknown Driver',
          phone: trip.driverPhone || '',
          email: trip.driverEmail || ''
        };
      }
    }
    
    console.log(`✅ Driver: ${driver?.name || 'Unknown'}`);
    
    // ========================================================================
    // STEP 4: Get vehicle details
    // ========================================================================
    let vehicle = null;
    if (trip.vehicleId) {
      const vehicleDoc = await req.db.collection('vehicles').findOne({
        _id: trip.vehicleId
      });
      
      if (vehicleDoc) {
        vehicle = {
          vehicleId: vehicleDoc._id.toString(),
          registrationNumber: vehicleDoc.registrationNumber || vehicleDoc.vehicleNumber || trip.vehicleNumber || 'N/A',
          make: vehicleDoc.make,
          model: vehicleDoc.model,
          color: vehicleDoc.color
        };
      } else {
        // Fallback to trip document data
        vehicle = {
          vehicleId: trip.vehicleId.toString(),
          registrationNumber: trip.vehicleNumber || 'N/A',
          make: trip.vehicleName,
          model: null,
          color: null
        };
      }
    }
    
    console.log(`✅ Vehicle: ${vehicle?.registrationNumber || 'Unknown'}`);
    
    // ========================================================================
    // STEP 5: Extract driver location with stale detection
    // ========================================================================
    let driverLocation = null;
    let isLocationStale = false;
    let locationAgeMinutes = 0;
    
    if (trip.currentLocation && 
        trip.currentLocation.latitude && 
        trip.currentLocation.longitude) {
      
      // Check if location is stale (>5 minutes old)
      const locationTimestamp = trip.currentLocation.timestamp?.$date 
        ? new Date(trip.currentLocation.timestamp.$date)
        : (trip.currentLocation.timestamp 
          ? new Date(trip.currentLocation.timestamp)
          : null);
      
      if (locationTimestamp) {
        const now = new Date();
        const ageMs = now - locationTimestamp;
        locationAgeMinutes = Math.floor(ageMs / 60000);
        isLocationStale = locationAgeMinutes > 5;
      }
      
      driverLocation = {
        latitude: trip.currentLocation.latitude,
        longitude: trip.currentLocation.longitude,
        timestamp: locationTimestamp?.toISOString(),
        speed: trip.currentLocation.speed || 0,
        heading: trip.currentLocation.heading || 0
      };
      
      console.log(`📍 Driver location: ${driverLocation.latitude}, ${driverLocation.longitude}`);
      console.log(`   Timestamp: ${driverLocation.timestamp}`);
      console.log(`   Age: ${locationAgeMinutes} minutes ${isLocationStale ? '(STALE ⚠️)' : '(FRESH ✅)'}`);
    } else {
      console.log('⚠️  No driver location available');
    }
    
    // ========================================================================
    // STEP 6: Use customer's specific pickup location from their stop
    // ========================================================================
    const customerLocation = {
      latitude: customerStop.location?.coordinates?.latitude || 0,
      longitude: customerStop.location?.coordinates?.longitude || 0,
      address: customerStop.location?.address || ''
    };
    
    console.log(`📍 Customer location: ${customerLocation.latitude}, ${customerLocation.longitude}`);
    console.log(`   Address: ${customerLocation.address}`);
    
    // ========================================================================
    // STEP 7: Calculate distance and ETA
    // ========================================================================
    let distanceToCustomer = 0;
    let eta = 0;
    
    if (driverLocation && 
        customerLocation.latitude && 
        customerLocation.longitude &&
        !isLocationStale) {
      
      // Haversine distance formula
      const R = 6371000; // Earth radius in meters
      const lat1 = driverLocation.latitude * Math.PI / 180;
      const lat2 = customerLocation.latitude * Math.PI / 180;
      const dLat = (customerLocation.latitude - driverLocation.latitude) * Math.PI / 180;
      const dLon = (customerLocation.longitude - driverLocation.longitude) * Math.PI / 180;
      
      const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                Math.cos(lat1) * Math.cos(lat2) *
                Math.sin(dLon/2) * Math.sin(dLon/2);
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
      distanceToCustomer = R * c; // Distance in meters
      
      console.log(`📏 Distance to customer: ${(distanceToCustomer/1000).toFixed(2)} km`);
      
      // Calculate ETA
      const currentSpeedMps = driverLocation.speed || 0;
      const averageSpeedMps = 20 / 3.6; // 20 km/h default city speed
      const speedMps = currentSpeedMps > 1 ? currentSpeedMps : averageSpeedMps;
      
      eta = Math.ceil(distanceToCustomer / speedMps / 60); // in minutes
      
      console.log(`⏱️  ETA: ${eta} minutes (using speed: ${(speedMps * 3.6).toFixed(1)} km/h)`);
    } else if (isLocationStale) {
      console.log('⚠️  Distance/ETA set to 0 due to stale location');
      distanceToCustomer = 0;
      eta = 0;
    } else {
      console.log('⚠️  Cannot calculate distance - missing location data');
    }
    
    // ========================================================================
    // STEP 8: Determine trip state and status
    // ========================================================================
    let tripState = 'not_started';
    let status = 'not_started';
    
    const tripStatus = trip.status?.toLowerCase() || 'pending';
    
    if (tripStatus === 'completed' || tripStatus === 'ended') {
      tripState = 'completed';
      status = 'completed';
    } else if (!driverLocation) {
      if (tripStatus === 'assigned' || tripStatus === 'scheduled' || tripStatus === 'pending') {
        tripState = 'not_started';
        status = 'not_started';
      } else {
        tripState = 'location_unavailable';
        status = 'location_unavailable';
      }
    } else if (isLocationStale) {
      tripState = 'location_unavailable';
      status = 'location_unavailable';
    } else {
      tripState = 'active';
      
      if (distanceToCustomer < 50) {
        status = 'arrived';
      } else if (distanceToCustomer < 500) {
        status = 'nearby';
      } else if (tripStatus === 'started' || tripStatus === 'in_progress') {
        status = 'on_the_way';
      } else {
        status = 'not_started';
      }
    }
    
    console.log(`🚦 Trip state: ${tripState}`);
    console.log(`   Status: ${status}`);
    
    // ========================================================================
    // STEP 9: Prepare response
    // ========================================================================
    const response = {
      trip: {
        id: trip._id.toString(),
        tripNumber: trip.tripNumber,
        status: trip.status,
        scheduledPickupTime: customerStop.readyByTime || customerStop.estimatedTime || 'N/A',
        actualStartTime: trip.actualStartTime?.$date 
          ? new Date(trip.actualStartTime.$date).toISOString()
          : (trip.actualStartTime || null)
      },
      driver,
      vehicle,
      driverLocation,
      customerLocation,
      distanceToCustomer,
      eta,
      status,
      tripState,
      isLocationStale,
      locationAgeMinutes,
      customerStop: {
        sequence: customerStop.sequence,
        type: customerStop.type,
        estimatedTime: customerStop.estimatedTime,
        readyByTime: customerStop.readyByTime,
        status: customerStop.status
      }
    };
    
    console.log('\n📤 RESPONSE SUMMARY:');
    console.log(`   Distance: ${(distanceToCustomer/1000).toFixed(2)} km`);
    console.log(`   ETA: ${eta} min`);
    console.log(`   Speed: ${driverLocation?.speed || 0} m/s`);
    console.log(`   Scheduled: ${response.trip.scheduledPickupTime}`);
    console.log(`   State: ${tripState}, Status: ${status}`);
    console.log('='.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: response
    });
    
  } catch (error) {
    console.error('\n❌ ERROR IN CUSTOMER TRACKING:');
    console.error(error);
    console.error('Stack trace:', error.stack);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch tracking data',
      error: error.message
    });
  }
});

module.exports = router;