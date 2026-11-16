const fs = require('fs');

const targetPath = 'routes/driver_trip_router.js';
let content = fs.readFileSync(targetPath, 'utf8');

const newRoute = `
// ============================================================================
// @route   POST /api/driver/trips/:tripGroupId/stop/:stopId/passenger/:passengerId/board
// @desc    Mark passenger as boarded and generate step-out OTP
// @access  Private (Driver only)
// ============================================================================
router.post('/trips/:tripGroupId/stop/:stopId/passenger/:passengerId/board', verifyToken, async (req, res) => {
  try {
    const { tripGroupId, stopId, passengerId } = req.params;
    console.log(\`\\n👥 MARKING PASSENGER BOARDED: \${passengerId}\`);
    
    // 1. Get the customer details
    const { ObjectId } = require('mongodb');
    let customer = null;
    if (ObjectId.isValid(passengerId)) {
      customer = await req.db.collection('customers').findOne({ _id: new ObjectId(passengerId) });
    } else {
      customer = await req.db.collection('customers').findOne({ email: passengerId });
    }
    
    if (!customer) {
      // Try finding from roster
      const roster = await req.db.collection('roster-assigned-trips').findOne({ tripGroupId });
      if (roster) {
         for (const stop of roster.stops || []) {
            if (stop.stopId === stopId && stop.customer && (stop.customer.email === passengerId || stop.customer.id === passengerId)) {
               customer = stop.customer;
               break;
            }
         }
      }
    }
    
    if (!customer) {
      return res.status(404).json({ success: false, message: 'Passenger not found' });
    }

    // 2. Mark attendance as boarded
    // We update the passengerStatus if we track it, or just rely on the OTP verification.
    // The previous code had a general passengerStatus update, but we'll do the minimal update:
    await req.db.collection('roster-assigned-trips').updateOne(
      { tripGroupId },
      { 
        $set: { 
           passengerStatus: 'boarded',
           passengerStatusUpdatedAt: new Date(),
           updatedAt: new Date()
        } 
      }
    );

    // 3. Generate Step-Out OTP
    const otpService = require('../services/otp_service');
    const otpRecord = await otpService.generateStepOutOTP(req.db, tripGroupId, stopId, customer);
    
    // Send Notification to customer about their Step-Out OTP
    const notificationService = require('../services/notification_service');
    // Get Driver name
    let driverName = 'Your driver';
    const driver = await req.db.collection('drivers').findOne({ _id: new ObjectId(req.user.userId) });
    if (driver) {
       driverName = driver.personalInfo?.name || driver.name || 'Your driver';
    }

    if (customer.email) {
      const customerDoc = await req.db.collection('customers').findOne({ email: customer.email });
      if (customerDoc) {
        // Fire and forget notification
        notificationService.sendRealTimeNotification('customer', customerDoc._id.toString(), {
          type: 'otp_step_out',
          title: '🔐 Your Drop-Off OTP',
          message: \`Your drop-off OTP: \${otpRecord.otp}\\n\\nShare this with \${driverName} at your destination.\`,
          data: {
            otp: otpRecord.otp,
            otpType: 'step_out',
            tripGroupId,
            stopId,
            driverName,
            expiresAt: otpRecord.expiresAt.toISOString(),
          },
          priority: 'urgent',
          category: 'otp_verification',
        }).catch(e => console.log('FCM failed for step-out:', e.message));
      }
    }

    res.json({
      success: true,
      message: 'Passenger boarded',
      data: {
        passengerId: otpRecord.passengerId,
        otp: otpRecord.otp,
        expiresAt: otpRecord.expiresAt
      }
    });

  } catch (error) {
    console.error('❌ Error marking boarded:', error);
    res.status(500).json({ success: false, message: 'Failed to mark boarded', error: error.message });
  }
});
`;

content = content.replace(
  "// @route   POST /api/driver/trips/:tripId/attendance",
  newRoute + "\n// ============================================================================\n// @route   POST /api/driver/trips/:tripId/attendance"
);

fs.writeFileSync(targetPath, content, 'utf8');
console.log('Added /board endpoint');
