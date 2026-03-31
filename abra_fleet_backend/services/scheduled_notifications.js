// services/scheduled_notifications.js - Scheduled Notification Service
const cron = require('node-cron');
const { ObjectId } = require('mongodb');
const { createNotification } = require('../models/notification_model');
const { sendPushNotification } = require('./firebase_admin');
const { sendSMS } = require('./sms_service');
const { sendEmail } = require('./email_service');

let scheduledTasksRunning = false;

/**
 * Start all scheduled notification tasks
 * @param {object} db - MongoDB database instance
 */
function startScheduledNotifications(db) {
  if (scheduledTasksRunning) {
    console.log('⚠️  Scheduled notifications already running');
    return;
  }

  console.log('\n' + '⏰'*40);
  console.log('STARTING SCHEDULED NOTIFICATION SERVICE');
  console.log('⏰'*40);

  // Task 1: Morning Reminders (30 minutes before pickup)
  // Runs every 5 minutes
  cron.schedule('*/5 * * * *', async () => {
    await sendMorningReminders(db);
  });

  // Task 2: Real-time ETA Updates
  // Runs every 2 minutes
  cron.schedule('*/2 * * * *', async () => {
    await sendETAUpdates(db);
  });

  // Task 3: Late Pickup Alerts
  // Runs every 10 minutes
  cron.schedule('*/10 * * * *', async () => {
    await sendLatePickupAlerts(db);
  });

  // Task 4: Daily Summary (sent at 8 PM)
  cron.schedule('0 20 * * *', async () => {
    await sendDailySummary(db);
  });

  scheduledTasksRunning = true;
  console.log('✅ Scheduled notification tasks started:');
  console.log('   - Morning reminders: Every 5 minutes');
  console.log('   - ETA updates: Every 2 minutes');
  console.log('   - Late pickup alerts: Every 10 minutes');
  console.log('   - Daily summary: 8:00 PM daily');
  console.log('⏰'*40 + '\n');
}

/**
 * Send morning reminders 30 minutes before pickup
 */
async function sendMorningReminders(db) {
  try {
    const now = new Date();
    const in30Minutes = new Date(now.getTime() + 30 * 60000);
    const in35Minutes = new Date(now.getTime() + 35 * 60000);

    // Get today's date in YYYY-MM-DD format
    const today = now.toISOString().split('T')[0];

    // Format times as HH:MM
    const timeFrom = in30Minutes.toTimeString().slice(0, 5);
    const timeTo = in35Minutes.toTimeString().slice(0, 5);

    console.log(`\n⏰ Checking for pickups between ${timeFrom} and ${timeTo}...`);

    // Find rosters with pickup in next 30-35 minutes
    const upcomingRosters = await db.collection('rosters').find({
      status: 'assigned',
      tripDate: today,
      optimizedPickupTime: {
        $gte: timeFrom,
        $lte: timeTo
      },
      morningReminderSent: { $ne: true }
    }).toArray();

    if (upcomingRosters.length === 0) {
      console.log('   No upcoming pickups found');
      return;
    }

    console.log(`   Found ${upcomingRosters.length} upcoming pickups`);

    for (const roster of upcomingRosters) {
      try {
        // Get driver details
        const driver = await db.collection('users').findOne({
          _id: new ObjectId(roster.driverId)
        });

        if (!driver) {
          console.log(`   ⚠️  Driver not found for roster ${roster._id}`);
          continue;
        }

        // Get vehicle details
        const vehicle = await db.collection('vehicles').findOne({
          _id: new ObjectId(roster.vehicleId)
        });

        const vehicleName = vehicle?.name || vehicle?.vehicleNumber || 'Unknown Vehicle';
        const customerName = roster.customerName || 'Customer';

        console.log(`   📱 Sending reminder to ${customerName} for ${roster.optimizedPickupTime}`);

        // Create in-app notification
        await createNotification(db, {
          userId: roster.customerId || roster.customerEmail,
          title: '⏰ Driver Arriving Soon!',
          message: `${driver.name} will arrive in approximately 30 minutes.\n\n` +
                  `🚗 Vehicle: ${vehicleName}\n` +
                  `⏰ Pickup Time: ${roster.optimizedPickupTime}\n` +
                  `📍 Pickup Sequence: Stop #${roster.pickupSequence || 1}\n\n` +
                  `Please be ready at your pickup location.`,
          type: 'pickup_reminder',
          data: {
            rosterId: roster._id.toString(),
            driverId: driver._id.toString(),
            driverName: driver.name,
            driverPhone: driver.phone,
            vehicleId: roster.vehicleId,
            vehicleName: vehicleName,
            pickupTime: roster.optimizedPickupTime,
            sequence: roster.pickupSequence || 1
          },
          priority: 'high',
          category: 'roster'
        });

        // Send push notification
        await sendPushNotification(
          roster.customerId || roster.customerEmail,
          '⏰ Driver Arriving Soon',
          `${driver.name} will arrive in ~30 mins. Pickup: ${roster.optimizedPickupTime}`,
          {
            rosterId: roster._id.toString(),
            type: 'pickup_reminder',
            action: 'track_driver'
          },
          db
        );

        // Send SMS if phone number available
        if (roster.customerPhone) {
          await sendSMS(
            roster.customerPhone,
            `Driver ${driver.name} arriving in ~30 mins. ` +
            `Vehicle: ${vehicleName}. ` +
            `Pickup: ${roster.optimizedPickupTime}. ` +
            `Track: ${process.env.APP_URL || 'app'}/track/${roster._id}`
          );
        }

        // Mark reminder as sent
        await db.collection('rosters').updateOne(
          { _id: roster._id },
          {
            $set: {
              morningReminderSent: true,
              morningReminderSentAt: new Date()
            }
          }
        );

        console.log(`   ✅ Reminder sent successfully`);
      } catch (rosterError) {
        console.error(`   ❌ Error sending reminder for roster ${roster._id}:`, rosterError.message);
      }
    }

    console.log(`✅ Morning reminders complete: ${upcomingRosters.length} sent\n`);
  } catch (error) {
    console.error('❌ Morning reminders error:', error);
  }
}

/**
 * Send real-time ETA updates
 */
async function sendETAUpdates(db) {
  try {
    const now = new Date();
    const today = now.toISOString().split('T')[0];

    // Find active trips (driver en route)
    const activeTrips = await db.collection('rosters').find({
      status: 'assigned',
      tripDate: today,
      tripStarted: true,
      tripCompleted: { $ne: true }
    }).toArray();

    if (activeTrips.length === 0) {
      return;
    }

    console.log(`\n🕐 Updating ETAs for ${activeTrips.length} active trips...`);

    for (const trip of activeTrips) {
      try {
        // Get driver's current location
        const driver = await db.collection('users').findOne({
          _id: new ObjectId(trip.driverId)
        });

        if (!driver || !driver.currentLocation) {
          continue;
        }

        // Calculate ETA based on current location and pickup location
        // (In production, use Google Maps Distance Matrix API)
        const estimatedMinutes = calculateETA(
          driver.currentLocation,
          trip.pickupLocation
        );

        // Only send update if ETA changed significantly (>2 minutes)
        if (Math.abs(estimatedMinutes - (trip.lastETAMinutes || 0)) > 2) {
          await createNotification(db, {
            userId: trip.customerId || trip.customerEmail,
            title: '🕐 Updated ETA',
            message: `Driver ${driver.name} is approximately ${estimatedMinutes} minutes away.`,
            type: 'eta_update',
            data: {
              rosterId: trip._id.toString(),
              etaMinutes: estimatedMinutes,
              driverLocation: driver.currentLocation
            },
            priority: 'medium',
            category: 'roster'
          });

          // Update last ETA
          await db.collection('rosters').updateOne(
            { _id: trip._id },
            {
              $set: {
                lastETAMinutes: estimatedMinutes,
                lastETAUpdate: new Date()
              }
            }
          );

          console.log(`   ✅ ETA updated for ${trip.customerName}: ${estimatedMinutes} mins`);
        }
      } catch (tripError) {
        console.error(`   ❌ Error updating ETA for trip ${trip._id}:`, tripError.message);
      }
    }
  } catch (error) {
    console.error('❌ ETA updates error:', error);
  }
}

/**
 * Send late pickup alerts
 */
async function sendLatePickupAlerts(db) {
  try {
    const now = new Date();
    const today = now.toISOString().split('T')[0];
    const currentTime = now.toTimeString().slice(0, 5);

    // Find rosters where pickup time has passed but trip not started
    const latePickups = await db.collection('rosters').find({
      status: 'assigned',
      tripDate: today,
      optimizedPickupTime: { $lt: currentTime },
      tripStarted: { $ne: true },
      lateAlertSent: { $ne: true }
    }).toArray();

    if (latePickups.length === 0) {
      return;
    }

    console.log(`\n⚠️  Found ${latePickups.length} late pickups`);

    for (const roster of latePickups) {
      try {
        const driver = await db.collection('users').findOne({
          _id: new ObjectId(roster.driverId)
        });

        // Notify customer
        await createNotification(db, {
          userId: roster.customerId || roster.customerEmail,
          title: '⚠️ Pickup Delayed',
          message: `Your scheduled pickup time has passed. ` +
                  `Driver ${driver?.name || 'your driver'} is on the way. ` +
                  `We apologize for the delay.`,
          type: 'late_pickup',
          priority: 'high',
          category: 'roster'
        });

        // Notify admin
        const admins = await db.collection('users').find({ role: 'admin' }).toArray();
        for (const admin of admins) {
          await createNotification(db, {
            userId: admin.email,
            title: '⚠️ Late Pickup Alert',
            message: `Pickup for ${roster.customerName} is late. ` +
                    `Scheduled: ${roster.optimizedPickupTime}, Driver: ${driver?.name}`,
            type: 'admin_alert',
            priority: 'high',
            category: 'operations'
          });
        }

        // Mark alert as sent
        await db.collection('rosters').updateOne(
          { _id: roster._id },
          { $set: { lateAlertSent: true, lateAlertSentAt: new Date() } }
        );

        console.log(`   ⚠️  Late alert sent for ${roster.customerName}`);
      } catch (rosterError) {
        console.error(`   ❌ Error sending late alert:`, rosterError.message);
      }
    }
  } catch (error) {
    console.error('❌ Late pickup alerts error:', error);
  }
}

/**
 * Send daily summary to admins
 */
async function sendDailySummary(db) {
  try {
    const today = new Date().toISOString().split('T')[0];

    console.log(`\n📊 Generating daily summary for ${today}...`);

    // Get statistics
    const totalRosters = await db.collection('rosters').countDocuments({
      tripDate: today
    });

    const completedTrips = await db.collection('rosters').countDocuments({
      tripDate: today,
      tripCompleted: true
    });

    const cancelledTrips = await db.collection('rosters').countDocuments({
      tripDate: today,
      status: 'cancelled'
    });

    const latePickups = await db.collection('rosters').countDocuments({
      tripDate: today,
      lateAlertSent: true
    });

    // Send to all admins
    const admins = await db.collection('users').find({ role: 'admin' }).toArray();

    for (const admin of admins) {
      await sendEmail({
        to: admin.email,
        subject: `Daily Fleet Summary - ${today}`,
        template: 'daily_summary',
        data: {
          date: today,
          totalRosters: totalRosters,
          completedTrips: completedTrips,
          cancelledTrips: cancelledTrips,
          latePickups: latePickups,
          completionRate: totalRosters > 0 ? ((completedTrips / totalRosters) * 100).toFixed(1) : 0
        }
      });
    }

    console.log(`✅ Daily summary sent to ${admins.length} admins`);
  } catch (error) {
    console.error('❌ Daily summary error:', error);
  }
}

/**
 * Calculate ETA based on distance (simplified)
 * In production, use Google Maps Distance Matrix API
 */
function calculateETA(driverLocation, pickupLocation) {
  if (!driverLocation || !pickupLocation) {
    return 15; // Default 15 minutes
  }

  // Haversine formula for distance
  const R = 6371; // Earth radius in km
  const dLat = (pickupLocation.latitude - driverLocation.coordinates[1]) * Math.PI / 180;
  const dLon = (pickupLocation.longitude - driverLocation.coordinates[0]) * Math.PI / 180;

  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(driverLocation.coordinates[1] * Math.PI / 180) *
            Math.cos(pickupLocation.latitude * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const distance = R * c;

  // Assume average speed of 25 km/h in city traffic
  const minutes = Math.ceil((distance / 25) * 60);

  return Math.max(minutes, 1); // At least 1 minute
}

/**
 * Stop all scheduled tasks
 */
function stopScheduledNotifications() {
  scheduledTasksRunning = false;
  console.log('⏰ Scheduled notifications stopped');
}

module.exports = {
  startScheduledNotifications,
  stopScheduledNotifications,
  sendMorningReminders,
  sendETAUpdates,
  sendLatePickupAlerts,
  sendDailySummary
};
