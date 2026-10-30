// ============================================================================
// routes/otp_no_show_router.js
// NO-SHOW endpoint — driver marks a passenger as not present at pickup
// ============================================================================

const express = require('express');
const router = express.Router();
const { verifyToken } = require('../middleware/auth');
const notificationService = require('../services/notification_service');

// ============================================================================
// POST /api/otp/no-show
// Driver marks a passenger as No-Show (customer didn't arrive at pickup)
// This unblocks departure for that passenger without requiring OTP
// ============================================================================
router.post('/no-show', verifyToken, async (req, res) => {
  try {
    const { tripGroupId, stopId, passengerId, passengerName, passengerEmail } = req.body;
    const driverId = req.user.userId;

    if (!tripGroupId || !stopId) {
      return res.status(400).json({
        success: false,
        message: 'tripGroupId and stopId required',
      });
    }

    console.log(`\n[ERROR] NO-SHOW: ${passengerName || passengerId} at stop ${stopId}`);

    // [OK] Strategy: Update ALL unverified OTP records for this stop to no_show
    // This handles cases where passengerId format may differ between OTP record and request
    // Also handles the case where no OTP record exists yet (upsert)
    
    const updateResult = await req.db.collection('trip_otps').updateMany(
      {
        tripGroupId,
        stopId,
        verified: { $ne: true }, // Don't touch already-verified records
      },
      {
        $set: {
          overrideStatus: 'no_show',
          noShowAt: new Date(),
          noShowBy: driverId,
        },
      }
    );

    console.log(`[OK] Updated ${updateResult.modifiedCount} OTP record(s) to no_show`);

    // If no records existed, create one
    if (updateResult.matchedCount === 0) {
      await req.db.collection('trip_otps').insertOne({
        tripGroupId,
        stopId,
        passengerId: passengerId || stopId, // fallback to stopId if passengerId not provided
        passengerName: passengerName || 'Unknown',
        passengerEmail: passengerEmail || '',
        otp: null,
        type: 'step_in',
        attempts: 0,
        verified: false,
        overrideStatus: 'no_show',
        noShowAt: new Date(),
        noShowBy: driverId,
        createdAt: new Date(),
        expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
      });
      console.log(`[OK] Created new no-show record for ${passengerName || passengerId}`);
    }

    // Notify admin about no-show
    try {
      const { ObjectId } = require('mongodb');
      const driverObjId = ObjectId.isValid(driverId) ? new ObjectId(driverId) : null;
      const driver = driverObjId
        ? await req.db.collection('drivers').findOne({ _id: driverObjId })
        : null;
      const driverName = driver?.personalInfo?.name || driver?.name || 'Driver';

      await notificationService.sendNotificationToRole('admin', {
        type: 'passenger_no_show',
        title: '[ERROR] Passenger No-Show',
        message: `${passengerName || 'Passenger'} did not arrive at pickup. Marked as No-Show by ${driverName}.`,
        data: {
          tripGroupId,
          stopId,
          passengerId,
          passengerName,
          driverId,
          driverName,
          noShowAt: new Date().toISOString(),
        },
        priority: 'high',
        category: 'trip_updates',
      });
    } catch (notifErr) {
      console.error('[WARN] No-show admin notification failed:', notifErr.message);
    }

    // Notify customer that they were marked as no-show
    try {
      if (passengerEmail) {
        const customer = await req.db.collection('customers').findOne({ email: passengerEmail });
        if (customer) {
          await notificationService.sendRealTimeNotification(
            'customer',
            customer._id.toString(),
            {
              type: 'trip_no_show',
              title: '[ERROR] Marked as No-Show',
              message: `You were marked as No-Show for today's pickup. If this is incorrect, please contact your admin.`,
              data: { tripGroupId, stopId },
              priority: 'normal',
              category: 'trip_updates',
            }
          );
        }
      }
    } catch (custNotifErr) {
      console.error('[WARN] Customer no-show notification failed:', custNotifErr.message);
    }

    console.log(`[OK] No-show complete for ${passengerName || passengerId}`);

    res.json({
      success: true,
      message: `${passengerName || 'Passenger'} marked as No-Show`,
    });
  } catch (error) {
    console.error('[ERROR] No-show error:', error);
    res.status(500).json({ success: false, message: 'Failed to mark no-show', error: error.message });
  }
});

module.exports = router;
