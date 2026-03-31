// routes/my_trips_screen.js
// ============================================================================
// CUSTOMER TRIP MANAGEMENT - Complete API for My Trips Screen
// ============================================================================
// Features:
// ✅ Get daily trips from roster-assigned-trips collection
// ✅ Cancel individual trips with driver notification
// ✅ Restore cancelled trips
// ✅ Get trip details with actual/estimated times
// ✅ Support for recurring rosters (date ranges)
// 🔥 NEW: FCM push notifications to driver on trip cancellation
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { createNotification } = require('../models/notification_model');
const notificationService = require('../services/fcm_service'); // ✅ ADD FCM SERVICE

// Note: Authentication is handled by verifyJWT middleware in index.js
// All routes in this router are already protected

// ============================================================================
// @route   GET /api/customer/trips/daily-trips
// @desc    Get daily trips for customer from roster-assigned-trips
// @access  Private (Customer)
// ============================================================================
// ============================================================================
// @route   GET /api/customer/trips/daily-trips
// @desc    Get daily trips for customer from roster-assigned-trips
// @access  Private (Customer)
// ============================================================================
router.get('/daily-trips', async (req, res) => {
  try {
    const userId = req.user.userId;
    const { rosterId, startDate, endDate } = req.query;

    console.log('\n📋 FETCHING DAILY TRIPS FOR CUSTOMER - TIMEZONE FIXED v2.0');
    console.log('   User ID:', userId);
    console.log('   Roster ID:', rosterId);
    console.log('   Date Range:', startDate, 'to', endDate);

    // Get user email
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
    console.log('   User Email:', userEmail);

    // Build query for roster-assigned-trips
    const query = {
      'stops.customer.email': userEmail,
      status: { $in: ['assigned', 'scheduled', 'started', 'in_progress', 'completed', 'cancelled'] }
    };

    // Add optional filters
    if (rosterId) {
      query['stops.rosterId'] = ObjectId.isValid(rosterId) ? new ObjectId(rosterId) : rosterId;
    }

    if (startDate || endDate) {
      query.scheduledDate = {};
      if (startDate) query.scheduledDate.$gte = startDate;
      if (endDate) query.scheduledDate.$lte = endDate;
    }

    console.log('   Query:', JSON.stringify(query, null, 2));

    // Fetch trips from roster-assigned-trips collection
    const trips = await req.db.collection('roster-assigned-trips')
      .find(query)
      .sort({ scheduledDate: 1, startTime: 1 })
      .toArray();

    console.log(`   Found ${trips.length} trip(s)`);

    // ✅ FIX: Get today's date as string (no timezone issues)
    const getTodayDateString = () => {
      const now = new Date();
      const year = now.getFullYear();
      const month = String(now.getMonth() + 1).padStart(2, '0');
      const day = String(now.getDate()).padStart(2, '0');
      return `${year}-${month}-${day}`;
    };

    const todayString = getTodayDateString();
    console.log(`   📅 Today's date: ${todayString}`);

    // Transform trips to daily format
    const dailyTrips = [];

    for (const trip of trips) {
      // Find customer's stop in this trip
      const customerStop = trip.stops.find(stop => 
        stop.customer && stop.customer.email.toLowerCase() === userEmail
      );

      if (!customerStop) continue;

      // Get office drop stop
      const officeStop = trip.stops.find(stop => stop.type === 'drop');

      // ✅ FIX: Determine trip status using STRING comparison
      const scheduledDate = trip.scheduledDate; // "2026-02-03"
      let tripStatus = trip.status;

      console.log(`   🔍 Trip ${trip.tripNumber}:`);
      console.log(`      Scheduled: ${scheduledDate}, Today: ${todayString}, Trip Status: ${trip.status}`);

      if (scheduledDate < todayString && trip.status !== 'cancelled') {
        tripStatus = 'completed';
        console.log(`      ✅ Past trip → completed`);
      } else if (scheduledDate === todayString) {
        // ✅ FIX: TODAY's trip - check actual status
        if (trip.status === 'started' || trip.status === 'in_progress') {
          tripStatus = 'ongoing';
          console.log(`      🚗 TODAY's trip is ACTIVE → ongoing (trip status: ${trip.status})`);
        } else if (trip.status === 'completed') {
          tripStatus = 'completed';
          console.log(`      ✅ TODAY's trip COMPLETED → completed`);
        } else if (trip.status === 'cancelled') {
          tripStatus = 'cancelled';
          console.log(`      ❌ TODAY's trip CANCELLED → cancelled`);
        } else {
          tripStatus = 'scheduled';
          console.log(`      📅 TODAY's trip not started yet → scheduled`);
        }
      } else if (scheduledDate > todayString) {
        tripStatus = trip.status === 'cancelled' ? 'cancelled' : 'scheduled';
        console.log(`      📅 Future trip → ${tripStatus}`);
      }

      // ✅ Check if customer's stop is cancelled individually
      if (customerStop.status === 'cancelled') {
        tripStatus = 'cancelled';
        console.log(`      ❌ Customer stop cancelled → cancelled`);
      }

      dailyTrips.push({
        tripId: trip._id.toString(),
        tripNumber: trip.tripNumber,
        rosterId: customerStop.rosterId ? customerStop.rosterId.toString() : null,
        date: trip.scheduledDate,
        dateString: new Date(trip.scheduledDate).toLocaleDateString('en-US', {
          weekday: 'short',
          year: 'numeric',
          month: 'short',
          day: 'numeric'
        }),
        status: tripStatus,
        
        // Customer pickup details
        pickupTime: customerStop.pickupTime || customerStop.estimatedTime,
        readyByTime: customerStop.readyByTime,
        pickupSequence: customerStop.sequence,
        pickupLocation: customerStop.location.address,
        pickupCoordinates: customerStop.location.coordinates,
        
        // Office drop details
        officeArrivalTime: officeStop ? officeStop.estimatedTime : trip.endTime,
        officeLocation: officeStop ? officeStop.location.address : 'Office',
        officeCoordinates: officeStop ? officeStop.location.coordinates : null,
        
        // Distance and timing
        distanceToOffice: customerStop.distanceToOffice || 0,
        estimatedTravelTime: customerStop.estimatedTravelTime || 0,
        
        // Vehicle and driver
        vehicleNumber: trip.vehicleNumber,
        vehicleName: trip.vehicleName,
        driverName: trip.driverName,
        driverPhone: trip.driverPhone,
        driverEmail: trip.driverEmail,
        
        // Actual times (if completed)
        actualPickupTime: customerStop.arrivedAt ? 
          new Date(customerStop.arrivedAt).toLocaleTimeString('en-US', { 
            hour: '2-digit', 
            minute: '2-digit' 
          }) : null,
        actualDropTime: trip.actualEndTime ? 
          new Date(trip.actualEndTime).toLocaleTimeString('en-US', { 
            hour: '2-digit', 
            minute: '2-digit' 
          }) : null,
        actualDistance: trip.actualDistance || null,
        
        // Cancellation info
        canCancel: scheduledDate > todayString && tripStatus !== 'cancelled' && tripStatus !== 'started' && tripStatus !== 'in_progress' && tripStatus !== 'ongoing',
        cancelledAt: customerStop.cancelledAt || trip.cancelledAt,
        cancellationReason: customerStop.cancellationReason || trip.cancellationReason,
        
        // Trip metadata
        totalStops: trip.totalStops,
        totalPassengers: trip.stops.filter(s => s.type === 'pickup').length,
        tripType: trip.tripType
      });
    }

    console.log(`   ✅ Transformed ${dailyTrips.length} daily trip(s)`);
    console.log('   📊 Status breakdown:');
    const statusCounts = dailyTrips.reduce((acc, trip) => {
      acc[trip.status] = (acc[trip.status] || 0) + 1;
      return acc;
    }, {});
    console.log(statusCounts);

    res.json({
      success: true,
      message: `Found ${dailyTrips.length} trip(s)`,
      data: dailyTrips,
      count: dailyTrips.length
    });

  } catch (error) {
    console.error('❌ Error fetching daily trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch daily trips',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/customer/trips/cancel-single
// @desc    Cancel a specific trip date for customer + SEND FCM TO DRIVER
// @access  Private (Customer)
// ============================================================================
// ============================================================================
// @route   POST /api/customer/trips/cancel-single
// @desc    Cancel a specific trip date for customer + SEND FCM TO DRIVER
// @access  Private (Customer)
// ============================================================================
router.post('/cancel-single', async (req, res) => {
  try {
    const userId = req.user.userId;
    const { tripDate, tripId, reason } = req.body;

    console.log('\n🚫 CANCELLING SINGLE TRIP');
    console.log('   User ID:', userId);
    console.log('   Trip ID:', tripId);
    console.log('   Trip Date:', tripDate);
    console.log('   Reason:', reason);

    // Validate required fields
    if (!tripId || !tripDate) {
      return res.status(400).json({
        success: false,
        message: 'tripId and tripDate are required'
      });
    }

    // Get user details
    const user = await req.db.collection('customers').findOne({
      $or: [
        { firebaseUid: userId },
        { _id: ObjectId.isValid(userId) ? new ObjectId(userId) : null }
      ]
    });

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const userEmail = user.email.toLowerCase();
    const userName = user.name || user.email;

    // Find the trip
    const trip = await req.db.collection('roster-assigned-trips').findOne({
      _id: new ObjectId(tripId),
      scheduledDate: tripDate
    });

    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }

    // Find customer's stop in the trip
    const stopIndex = trip.stops.findIndex(stop => 
      stop.customer && stop.customer.email.toLowerCase() === userEmail
    );

    if (stopIndex === -1) {
      return res.status(403).json({
        success: false,
        message: 'You are not assigned to this trip'
      });
    }

    const customerStop = trip.stops[stopIndex];

    // Check if trip can be cancelled
    const scheduledDate = new Date(trip.scheduledDate);
    const todayDate = new Date();
    todayDate.setHours(0, 0, 0, 0);

    if (scheduledDate <= todayDate) {
      return res.status(400).json({
        success: false,
        message: 'Cannot cancel trips for today or past dates'
      });
    }

    if (trip.status === 'started' || trip.status === 'in_progress') {
      return res.status(400).json({
        success: false,
        message: 'Cannot cancel trip that is already in progress'
      });
    }

    // Update the customer's stop status
    const updateResult = await req.db.collection('roster-assigned-trips').updateOne(
      { _id: trip._id },
      {
        $set: {
          [`stops.${stopIndex}.status`]: 'cancelled',
          [`stops.${stopIndex}.passengerStatus`]: 'cancelled',
          [`stops.${stopIndex}.cancelledAt`]: new Date(),
          [`stops.${stopIndex}.cancelledBy`]: userId,
          [`stops.${stopIndex}.cancellationReason`]: reason || 'Customer cancelled',
          updatedAt: new Date()
        }
      }
    );

    if (updateResult.modifiedCount === 0) {
      return res.status(500).json({
        success: false,
        message: 'Failed to cancel trip'
      });
    }

    console.log('   ✅ Trip cancelled successfully');

    // ========================================================================
    // 🔥 SEND FCM PUSH NOTIFICATION TO DRIVER - FIXED VERSION
    // ========================================================================
    console.log('\n📲 SENDING FCM NOTIFICATION TO DRIVER');
    console.log('='.repeat(60));
    
    try {
      if (trip.driverEmail) {
        console.log(`🔍 Looking for driver with email: ${trip.driverEmail}`);
        
        // Find driver in 'drivers' collection
        const driver = await req.db.collection('drivers').findOne({
          $or: [
            { 'personalInfo.email': trip.driverEmail.toLowerCase() },
            { email: trip.driverEmail.toLowerCase() }
          ]
        });

        if (!driver) {
          console.log(`⚠️  Driver not found with email: ${trip.driverEmail}`);
        } else {
          console.log(`✅ Driver found: ${driver.personalInfo?.name || driver.name || 'Unknown'}`);
          console.log(`   Driver MongoDB _id: ${driver._id}`);
          
          // Get driver's devices for FCM
          const driverDevices = await req.db.collection('user_devices').find({
            $or: [
              { userEmail: trip.driverEmail.toLowerCase() },
              { userId: driver._id.toString() }
            ],
            isActive: true
          }).toArray();

          console.log(`📱 Found ${driverDevices.length} active device(s) for driver`);

          let fcmSuccessCount = 0;
          const fcmErrors = [];

          // Send FCM to all driver's devices
          for (const device of driverDevices) {
            try {
              console.log(`📤 Sending FCM to ${device.deviceType} device...`);
              
              await notificationService.send({
                deviceToken: device.deviceToken,
                deviceType: device.deviceType || 'android',
                title: '🚫 Pickup Cancelled',
                body: `${userName} cancelled pickup for ${tripDate}. Vehicle: ${trip.vehicleNumber}`,
                data: {
                  type: 'trip_cancelled',
                  tripId: trip._id.toString(),
                  tripNumber: trip.tripNumber,
                  tripDate: tripDate,
                  customerName: userName,
                  customerEmail: userEmail,
                  pickupLocation: customerStop.location.address,
                  pickupTime: customerStop.pickupTime,
                  vehicleNumber: trip.vehicleNumber,
                  reason: reason || 'Customer cancelled',
                  action: 'refresh_trips',
                },
                priority: 'high'
              });

              fcmSuccessCount++;
              console.log(`   ✅ FCM sent successfully to ${device.deviceType}`);
            } catch (fcmError) {
              console.log(`   ❌ FCM failed for ${device.deviceType}: ${fcmError.message}`);
              fcmErrors.push({
                deviceType: device.deviceType,
                error: fcmError.message
              });
            }
          }

          // ✅ FIXED: Save to database notifications using the SAME helper function pattern
          console.log('\n💾 Saving to database notifications...');
          
          // Create notification helper (inline - matches driver_trip_router.js pattern)
          const createTripNotification = async (db, driver, notificationData) => {
            try {
              const notification = {
                userId: driver._id,
                userEmail: driver.personalInfo?.email || driver.email || null,
                userRole: 'driver',
                type: notificationData.type,
                title: notificationData.title,
                body: notificationData.body || notificationData.message,
                message: notificationData.message || notificationData.body,
                data: notificationData.data || {},
                priority: notificationData.priority || 'normal',
                category: notificationData.category || 'trip_updates',
                isRead: false,
                createdAt: new Date(),
                updatedAt: new Date(),
                expiresAt: notificationData.expiresAt || new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
                deliveryStatus: notificationData.deliveryStatus || {
                  fcm: 'no_devices',
                  database: 'success'
                },
                fcmResponse: notificationData.fcmResponse || null,
                channels: notificationData.channels || ['database']
              };

              const result = await db.collection('notifications').insertOne(notification);
              console.log(`✅ Notification created in database: ${result.insertedId}`);
              return result;
            } catch (error) {
              console.error(`❌ Failed to create notification: ${error.message}`);
              return null;
            }
          };

          await createTripNotification(req.db, driver, {
            type: 'trip_cancelled',
            title: '🚫 Pickup Cancelled',
            body: `${userName} has cancelled pickup for ${tripDate}`,
            message: `${userName} has cancelled pickup for ${tripDate}.\n\n` +
                    `Trip: ${trip.tripNumber}\n` +
                    `Vehicle: ${trip.vehicleNumber}\n` +
                    `Pickup Location: ${customerStop.location.address}\n` +
                    `Scheduled Time: ${customerStop.pickupTime}\n\n` +
                    `Reason: ${reason || 'Not specified'}\n\n` +
                    `No pickup required for this customer on this date.`,
            data: {
              tripId: trip._id.toString(),
              tripNumber: trip.tripNumber,
              tripDate: tripDate,
              customerName: userName,
              customerEmail: userEmail,
              pickupLocation: customerStop.location.address,
              pickupTime: customerStop.pickupTime,
              reason: reason || 'Customer cancelled'
            },
            priority: 'high',
            category: 'trip_updates',
            expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
            deliveryStatus: {
              fcm: fcmSuccessCount > 0 ? 'success' : 'no_devices',
              database: 'success'
            },
            fcmResponse: {
              success: fcmSuccessCount,
              failed: driverDevices.length - fcmSuccessCount,
              errors: fcmErrors
            },
            channels: fcmSuccessCount > 0 ? ['fcm', 'database'] : ['database']
          });

          console.log(`✅ Database notification created`);
          console.log(`📊 NOTIFICATION SUMMARY:`);
          console.log(`   FCM sent to: ${fcmSuccessCount}/${driverDevices.length} device(s)`);
          console.log(`   Database: Saved`);
          console.log('='.repeat(60));
        }
      } else {
        console.log('⚠️  No driver email found in trip');
      }
    } catch (notifError) {
      console.error('❌ Driver notification failed:');
      console.error('   Error:', notifError.message);
      console.error('   Stack:', notifError.stack);
      // Don't fail the cancellation if notification fails
    }

    res.json({
      success: true,
      message: 'Trip cancelled successfully',
      data: {
        tripId: trip._id.toString(),
        tripDate: tripDate,
        status: 'cancelled',
        cancelledAt: new Date()
      }
    });

  } catch (error) {
    console.error('❌ Error cancelling trip:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to cancel trip',
      error: error.message
    });
  }
});

// ============================================================================
// @route   POST /api/customer/trips/restore-single
// @desc    Restore a cancelled trip + SEND FCM TO DRIVER
// @access  Private (Customer)
// ============================================================================
router.post('/restore-single', async (req, res) => {
  try {
    const userId = req.user.userId;
    const { tripDate, tripId } = req.body;

    console.log('\n🔄 RESTORING CANCELLED TRIP');
    console.log('   User ID:', userId);
    console.log('   Trip ID:', tripId);
    console.log('   Trip Date:', tripDate);

    if (!tripId || !tripDate) {
      return res.status(400).json({
        success: false,
        message: 'tripId and tripDate are required'
      });
    }

    // Get user details
    const user = await req.db.collection('customers').findOne({
      $or: [
        { firebaseUid: userId },
        { _id: ObjectId.isValid(userId) ? new ObjectId(userId) : null }
      ]
    });

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const userEmail = user.email.toLowerCase();
    const userName = user.name || user.email;

    // Find the trip
    const trip = await req.db.collection('roster-assigned-trips').findOne({
      _id: new ObjectId(tripId),
      scheduledDate: tripDate
    });

    if (!trip) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found'
      });
    }

    // Find customer's stop
    const stopIndex = trip.stops.findIndex(stop => 
      stop.customer && stop.customer.email.toLowerCase() === userEmail
    );

    if (stopIndex === -1) {
      return res.status(403).json({
        success: false,
        message: 'You are not assigned to this trip'
      });
    }

    // Restore the stop
    const updateResult = await req.db.collection('roster-assigned-trips').updateOne(
      { _id: trip._id },
      {
        $set: {
          [`stops.${stopIndex}.status`]: 'pending',
          [`stops.${stopIndex}.passengerStatus`]: null,
          updatedAt: new Date()
        },
        $unset: {
          [`stops.${stopIndex}.cancelledAt`]: "",
          [`stops.${stopIndex}.cancelledBy`]: "",
          [`stops.${stopIndex}.cancellationReason`]: ""
        }
      }
    );

    if (updateResult.modifiedCount === 0) {
      return res.status(500).json({
        success: false,
        message: 'Failed to restore trip'
      });
    }

    console.log('   ✅ Trip restored successfully');

    // ========================================================================
    // 🔥 SEND FCM PUSH NOTIFICATION TO DRIVER
    // ========================================================================
    console.log('\n📲 SENDING FCM NOTIFICATION TO DRIVER');
    console.log('='.repeat(60));
    
    try {
      if (trip.driverEmail) {
        const driver = await req.db.collection('drivers').findOne({
          $or: [
            { 'personalInfo.email': trip.driverEmail.toLowerCase() },
            { email: trip.driverEmail.toLowerCase() }
          ]
        });

        if (driver) {
          const driverDevices = await req.db.collection('user_devices').find({
            $or: [
              { userEmail: trip.driverEmail.toLowerCase() },
              { userId: driver._id.toString() }
            ],
            isActive: true
          }).toArray();

          console.log(`📱 Found ${driverDevices.length} active device(s)`);

          let fcmSuccessCount = 0;

          const customerStop = trip.stops[stopIndex];

          for (const device of driverDevices) {
            try {
              await notificationService.send({
                deviceToken: device.deviceToken,
                deviceType: device.deviceType || 'android',
                title: '✅ Pickup Restored',
                body: `${userName} restored pickup for ${tripDate}. Vehicle: ${trip.vehicleNumber}`,
                data: {
                  type: 'trip_restored',
                  tripId: trip._id.toString(),
                  tripNumber: trip.tripNumber,
                  tripDate: tripDate,
                  customerName: userName,
                  customerEmail: userEmail,
                  pickupLocation: customerStop.location.address,
                  pickupTime: customerStop.pickupTime,
                  action: 'refresh_trips',
                },
                priority: 'high'
              });

              fcmSuccessCount++;
              console.log(`   ✅ FCM sent to ${device.deviceType}`);
            } catch (fcmError) {
              console.log(`   ❌ FCM failed: ${fcmError.message}`);
            }
          }

          await createNotification(req.db, {
            userId: driver._id,
            userEmail: trip.driverEmail,
            userRole: 'driver',
            title: '✅ Pickup Restored',
            body: `${userName} has restored their pickup for ${tripDate}.\n\n` +
                  `Trip: ${trip.tripNumber}\n` +
                  `Vehicle: ${trip.vehicleNumber}\n` +
                  `Pickup Location: ${customerStop.location.address}\n` +
                  `Pickup Time: ${customerStop.pickupTime}\n` +
                  `Ready By: ${customerStop.readyByTime}\n\n` +
                  `Please resume normal pickup for this customer.`,
            type: 'trip_restored',
            data: {
              tripId: trip._id.toString(),
              tripNumber: trip.tripNumber,
              tripDate: tripDate,
              customerName: userName,
              customerEmail: userEmail,
              pickupLocation: customerStop.location.address,
              pickupTime: customerStop.pickupTime
            },
            priority: 'high',
            category: 'trip_updates',
            channels: fcmSuccessCount > 0 ? ['fcm', 'database'] : ['database']
          });

          console.log(`✅ Notifications sent to ${fcmSuccessCount} device(s)`);
          console.log('='.repeat(60));
        }
      }
    } catch (notifError) {
      console.error('   ⚠️  Driver notification failed:', notifError.message);
    }

    res.json({
      success: true,
      message: 'Trip restored successfully',
      data: {
        tripId: trip._id.toString(),
        tripDate: tripDate,
        status: 'pending'
      }
    });

  } catch (error) {
    console.error('❌ Error restoring trip:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to restore trip',
      error: error.message
    });
  }
});

module.exports = router;