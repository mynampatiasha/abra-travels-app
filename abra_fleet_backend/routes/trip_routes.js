// File: routes/trip_routes.js
// ✅ ADD THESE FUNCTIONS TO YOUR EXISTING trip_routes.js FILE

const { createNotification } = require('../models/notification_model');

// ============================================
// ✅ ADD THIS: Trip Notification Helper Functions
// ============================================

async function sendTripNotification(db, tripId, notificationType, additionalData = {}) {
  try {
    console.log(`📤 Sending trip notification: ${notificationType} for trip ${tripId}`);

    const trips = db.collection('trips');
    const users = db.collection('users');
    const drivers = db.collection('drivers');
    const vehicles = db.collection('vehicles');

    // Fetch trip details
    const trip = await trips.findOne({ _id: new ObjectId(tripId) });
    if (!trip) {
      throw new Error(`Trip not found: ${tripId}`);
    }

    // Fetch related data
    const customer = await users.findOne({ _id: new ObjectId(trip.customerId) });
    const driver = trip.driverId ? await drivers.findOne({ _id: new ObjectId(trip.driverId) }) : null;
    const vehicle = trip.vehicleId ? await vehicles.findOne({ _id: new ObjectId(trip.vehicleId) }) : null;

    // Prepare notification data
    const data = {
      tripId: tripId.toString(),
      pickupAddress: trip.pickupLocation?.address || 'Pickup location',
      dropAddress: trip.dropLocation?.address || 'Drop location',
      scheduledTime: formatTime(trip.scheduledPickupTime),
      driverName: driver ? `${driver.firstName} ${driver.lastName}` : 'Driver',
      vehicleNumber: vehicle?.vehicleNumber || 'N/A',
      ...additionalData
    };

    // Get notification template
    const template = getTripNotificationTemplate(notificationType, data);

    // Send to customer
    if (customer) {
      await createNotification(db, {
        userId: customer._id.toString(),
        title: template.title,
        body: template.body,
        type: notificationType,
        priority: template.priority,
        data: {
          ...data,
          category: template.category
        },
        channels: ['fcm', 'firebase_rtdb', 'database']
      });
    }

    // Send to driver if needed
    if (driver && notificationType.startsWith('driver_')) {
      await createNotification(db, {
        userId: driver.userId,
        title: template.title,
        body: template.body,
        type: notificationType,
        priority: template.priority,
        data: {
          ...data,
          category: template.category
        },
        channels: ['fcm', 'firebase_rtdb', 'database']
      });
    }

    console.log(`✅ Trip notification sent successfully`);
    return { success: true };
  } catch (error) {
    console.error(`❌ Error sending trip notification:`, error);
    throw error;
  }
}

function getTripNotificationTemplate(type, data) {
  const templates = {
    trip_assigned: {
      title: '🚗 Trip Assigned',
      body: `Your trip to ${data.dropAddress} has been scheduled for ${data.scheduledTime}.`,
      priority: 'high',
      category: 'trip_update'
    },
    trip_started: {
      title: '🚀 Driver is on the way!',
      body: `${data.driverName} has started your trip. Estimated arrival: ${data.eta || '15'} minutes.`,
      priority: 'high',
      category: 'trip_update'
    },
    eta_15min: {
      title: '⏰ 15 Minutes Away',
      body: `${data.driverName} will arrive in approximately 15 minutes. Please be ready!`,
      priority: 'high',
      category: 'eta_alert'
    },
    eta_5min: {
      title: '🔔 5 Minutes Away',
      body: `${data.driverName} is 5 minutes away. Vehicle: ${data.vehicleNumber}`,
      priority: 'urgent',
      category: 'eta_alert'
    },
    driver_arrived: {
      title: '✅ Driver Arrived',
      body: `${data.driverName} has arrived at your pickup location. Vehicle: ${data.vehicleNumber}`,
      priority: 'urgent',
      category: 'arrival'
    },
    trip_delayed: {
      title: '⚠️ Trip Delayed',
      body: `Your trip is running ${data.delayMinutes} minutes late. New ETA: ${data.newEta}`,
      priority: 'high',
      category: 'delay'
    },
    trip_completed: {
      title: '✅ Trip Completed',
      body: `Your trip to ${data.dropAddress} has been completed. Thank you for riding with us!`,
      priority: 'normal',
      category: 'trip_update'
    },
    trip_cancelled: {
      title: '❌ Trip Cancelled',
      body: `Your trip scheduled for ${data.scheduledTime} has been cancelled.`,
      priority: 'high',
      category: 'trip_update'
    },
  };

  return templates[type] || {
    title: 'Trip Notification',
    body: 'You have a trip update',
    priority: 'normal',
    category: 'trip_update'
  };
}

function formatTime(date) {
  if (!date) return 'N/A';
  const d = new Date(date);
  return d.toLocaleString('en-US', {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    hour12: true
  });
}

function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth's radius in km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

async function calculateETA(currentLocation, targetLocation) {
  if (!currentLocation || !targetLocation) {
    return 30; // Default 30 minutes
  }

  const distance = calculateDistance(
    currentLocation.coordinates[1],
    currentLocation.coordinates[0],
    targetLocation.coordinates[1],
    targetLocation.coordinates[0]
  );

  // Assume average speed of 30 km/h in city
  const eta = Math.ceil((distance / 30) * 60);
  return eta;
}

// ============================================
// ✅ MODIFY YOUR EXISTING: Update Trip Status Route
// ADD THIS CODE TO YOUR EXISTING /api/trips/:tripId/status ROUTE
// ============================================

// Example: Modify your existing status update route like this:
/*
router.patch('/api/trips/:tripId/status', async (req, res) => {
  try {
    const { tripId } = req.params;
    const { status } = req.body;

    console.log(`📝 Updating trip ${tripId} status to: ${status}`);

    const trips = db.collection('trips');
    
    // ✅ GET OLD STATUS FIRST (for comparison)
    const oldTrip = await trips.findOne({ _id: new ObjectId(tripId) });
    const oldStatus = oldTrip?.status;

    const updateData = {
      status,
      updatedAt: new Date(),
      [`statusHistory.${status}`]: new Date()
    };

    const result = await trips.findOneAndUpdate(
      { _id: new ObjectId(tripId) },
      { $set: updateData },
      { returnDocument: 'after' }
    );

    if (!result) {
      return res.status(404).json({ error: 'Trip not found' });
    }

    // ✅ SEND AUTOMATIC NOTIFICATIONS BASED ON STATUS CHANGE
    if (oldStatus !== status) {
      switch (status) {
        case 'assigned':
          await sendTripNotification(db, tripId, 'trip_assigned');
          break;
        case 'started':
        case 'in_progress':
          await sendTripNotification(db, tripId, 'trip_started');
          break;
        case 'completed':
          await sendTripNotification(db, tripId, 'trip_completed');
          break;
        case 'cancelled':
          await sendTripNotification(db, tripId, 'trip_cancelled');
          break;
      }
    }

    res.json({
      success: true,
      trip: result,
      message: `Trip status updated to ${status}`
    });
  } catch (error) {
    console.error('❌ Error updating trip status:', error);
    res.status(500).json({ error: error.message });
  }
});
*/

// ============================================
// ✅ MODIFY YOUR EXISTING: Update Location Route
// ADD THIS CODE TO YOUR EXISTING /api/trips/:tripId/location ROUTE
// ============================================

/*
router.patch('/api/trips/:tripId/location', async (req, res) => {
  try {
    const { tripId } = req.params;
    const { latitude, longitude } = req.body;

    console.log(`📍 Updating trip ${tripId} location: ${latitude}, ${longitude}`);

    const trips = db.collection('trips');
    
    const trip = await trips.findOne({ _id: new ObjectId(tripId) });
    if (!trip) {
      return res.status(404).json({ error: 'Trip not found' });
    }

    const updateData = {
      currentLocation: {
        type: 'Point',
        coordinates: [longitude, latitude]
      },
      lastLocationUpdate: new Date()
    };

    await trips.updateOne(
      { _id: new ObjectId(tripId) },
      { $set: updateData }
    );

    // ✅ CHECK AND SEND ETA ALERTS
    if (trip.status === 'in_progress' && trip.pickupLocation) {
      const eta = await calculateETA(
        { coordinates: [longitude, latitude] },
        trip.pickupLocation
      );

      console.log(`📍 Trip ${tripId} ETA: ${eta} minutes`);

      const etaAlerts = trip.etaAlerts || {};

      // Send 15min alert
      if (eta <= 15 && eta > 5 && !etaAlerts.sent15min) {
        await sendTripNotification(db, tripId, 'eta_15min', { eta });
        await trips.updateOne(
          { _id: new ObjectId(tripId) },
          { $set: { 'etaAlerts.sent15min': true } }
        );
      }

      // Send 5min alert
      if (eta <= 5 && eta > 1 && !etaAlerts.sent5min) {
        await sendTripNotification(db, tripId, 'eta_5min', { eta });
        await trips.updateOne(
          { _id: new ObjectId(tripId) },
          { $set: { 'etaAlerts.sent5min': true } }
        );
      }

      // Send arrival alert
      if (eta <= 1 && !etaAlerts.sentArrival) {
        await sendTripNotification(db, tripId, 'driver_arrived');
        await trips.updateOne(
          { _id: new ObjectId(tripId) },
          { $set: { 'etaAlerts.sentArrival': true } }
        );
      }
    }

    // ✅ CHECK FOR DELAYS
    if (trip.scheduledPickupTime && ['assigned', 'started'].includes(trip.status)) {
      const scheduledTime = new Date(trip.scheduledPickupTime);
      const currentTime = new Date();
      const delayMinutes = Math.floor((currentTime - scheduledTime) / 60000);

      if (delayMinutes > 10 && !trip.delayAlertSent) {
        const eta = await calculateETA(
          { coordinates: [longitude, latitude] },
          trip.pickupLocation
        );
        const newEta = formatTime(new Date(Date.now() + eta * 60000));

        await sendTripNotification(db, tripId, 'trip_delayed', {
          delayMinutes,
          newEta
        });

        await trips.updateOne(
          { _id: new ObjectId(tripId) },
          { $set: { delayAlertSent: true } }
        );
      }
    }

    res.json({
      success: true,
      message: 'Location updated successfully'
    });
  } catch (error) {
    console.error('❌ Error updating trip location:', error);
    res.status(500).json({ error: error.message });
  }
});
*/

// ============================================
// ✅ NEW: Manual Notification Test Endpoint
// ADD THIS NEW ROUTE TO YOUR trip_routes.js
// ============================================

router.post('/api/trips/:tripId/notify/:notificationType', async (req, res) => {
  try {
    const { tripId, notificationType } = req.params;
    const additionalData = req.body || {};

    console.log(`📤 Manual notification: ${notificationType} for trip ${tripId}`);

    await sendTripNotification(db, tripId, notificationType, additionalData);

    res.json({
      success: true,
      message: `Notification ${notificationType} sent successfully`
    });
  } catch (error) {
    console.error('❌ Error sending manual notification:', error);
    res.status(500).json({ error: error.message });
  }
});

// ============================================
// ✅ Export the helper functions so you can use them
// ============================================
module.exports = {
  sendTripNotification,
  getTripNotificationTemplate,
  calculateETA,
  formatTime
};