// ============================================================================
// routes/otp_router.js
// OTP VERIFICATION SYSTEM — ROUTES + MODELS
// ============================================================================

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');
const otpService = require('../services/otp_service');
const notificationService = require('../services/notification_service');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// ============================================================================
// ENSURE UPLOAD DIRECTORY EXISTS
// ============================================================================
const uploadDir = path.join(__dirname, '../uploads/override-photos');
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

// ============================================================================
// MULTER — OVERRIDE PHOTOS
// ============================================================================
const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, uploadDir),
  filename: (_req, file, cb) => {
    const suffix = `${Date.now()}-${Math.round(Math.random() * 1e9)}`;
    cb(null, `override-${suffix}${path.extname(file.originalname)}`);
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const ok = /jpeg|jpg|png/.test(path.extname(file.originalname).toLowerCase()) &&
               /jpeg|jpg|png/.test(file.mimetype);
    ok ? cb(null, true) : cb(new Error('Only JPEG/JPG/PNG allowed'));
  },
});

// ============================================================================
// HELPER — get driver name from userId
// ============================================================================
async function getDriverName(db, driverId) {
  try {
    const driver = await db.collection('drivers').findOne({ _id: new ObjectId(driverId) });
    return driver?.personalInfo?.name || driver?.name || 'Your driver';
  } catch (_) {
    return 'Your driver';
  }
}

async function autoBoardPassenger(req, tripGroupId, stopId, passengerId, otpRecord) {
  if (otpRecord.type !== 'step_in') return;
  const db = req.db;
  
  try {
    // Mark as boarded in roster
    await db.collection('roster-assigned-trips').updateOne(
         { tripGroupId },
         { 
           $set: { 
              passengerStatus: 'boarded',
              passengerStatusUpdatedAt: new Date(),
              updatedAt: new Date()
           } 
         }
    );

    // Find customer
    let customer = null;
    if (ObjectId.isValid(passengerId)) {
       customer = await db.collection('customers').findOne({ _id: new ObjectId(passengerId) });
    } else {
       customer = await db.collection('customers').findOne({ email: passengerId });
    }
    
    if (!customer) {
       const roster = await db.collection('roster-assigned-trips').findOne({ tripGroupId });
       if (roster) {
          for (const stop of roster.stops || []) {
             if (stop.stopId === stopId && stop.customer && (stop.customer.email === passengerId || stop.customer.id === passengerId || stopId === passengerId)) {
                customer = stop.customer;
                break;
             }
          }
       }
    }
    
    if (!customer) return;

    const newOtpData = await otpService.generateStepOutOTP(db, tripGroupId, stopId, customer);
    
    // Send Notification
    if (customer.email && newOtpData.isNew) {
       const customerDoc = await db.collection('customers').findOne({ email: customer.email });
       if (customerDoc) {
          const driverName = req.user && req.user.userId ? await getDriverName(db, req.user.userId) : 'Your driver';
          
          notificationService.sendRealTimeNotification('customer', customerDoc._id.toString(), {
             type: 'otp_step_out',
             title: '[INFO] Your Drop-Off OTP',
             message: `Your drop-off OTP: ${newOtpData.otp}\n\nShare this with ${driverName} at your destination.`,
             data: {
                otp: newOtpData.otp,
                otpType: 'step_out',
                tripGroupId,
                stopId,
                driverName,
                expiresAt: newOtpData.expiresAt.toISOString()
             },
             priority: 'urgent',
             category: 'otp_verification',
          }).catch(e => console.log('FCM failed for auto step-out:', e.message));
       }
    }
  } catch (error) {
    console.error('Error in autoBoardPassenger:', error);
  }
}

// Full driver info — name, phone, email, vehicle
async function getDriverInfo(db, driverId, tripGroupId) {
  try {
    const driver = await db.collection('drivers').findOne({ _id: new ObjectId(driverId) });
    const info = {
      driverName:  driver?.personalInfo?.name  || driver?.name  || 'Unknown Driver',
      driverPhone: driver?.personalInfo?.phone || driver?.phone || '',
      driverEmail: driver?.personalInfo?.email || driver?.email || '',
      driverCode:  driver?.driverId || '',
      vehicleNumber: '',
      vehicleModel: '',
    };

    // Resolve vehicle from trip
    if (tripGroupId) {
      const trip = await db.collection('roster-assigned-trips').findOne(
        { tripGroupId },
        { projection: { vehicleId: 1, vehicleNumber: 1 } }
      );
      if (trip) {
        info.vehicleNumber = trip.vehicleNumber || '';
        if (trip.vehicleId) {
          const vehicle = await db.collection('vehicles').findOne(
            { _id: trip.vehicleId },
            { projection: { registrationNumber: 1, name: 1, model: 1 } }
          );
          if (vehicle) {
            info.vehicleNumber = vehicle.registrationNumber || vehicle.name || info.vehicleNumber;
            info.vehicleModel  = vehicle.model || '';
          }
        }
      }
    }

    return info;
  } catch (_) {
    return { driverName: 'Unknown Driver', driverPhone: '', driverEmail: '', driverCode: '', vehicleNumber: '', vehicleModel: '' };
  }
}

// ============================================================================
// POST /api/otp/generate-step-in
// Generate Step-In OTPs for ALL customers at a stop (called after driver arrives)
// ============================================================================
router.post('/generate-step-in', verifyToken, async (req, res) => {
  try {
    const { tripGroupId, stopId, customers } = req.body;

    if (!tripGroupId || !stopId || !Array.isArray(customers) || customers.length === 0) {
      return res.status(400).json({ success: false, message: 'tripGroupId, stopId, customers[] required' });
    }

    const otps = await otpService.generateStepInOTPs(req.db, tripGroupId, stopId, customers);
    const driverName = await getDriverName(req.db, req.user.userId);

    // Push notification to each customer
    for (const otpRecord of otps) {
      try {
        // Robust customer lookup — try email first, then passengerId as ObjectId
        let customer = null;
        if (otpRecord.passengerEmail) {
          customer = await req.db.collection('customers').findOne({ email: otpRecord.passengerEmail });
        }
        if (!customer) {
          const { ObjectId } = require('mongodb');
          if (ObjectId.isValid(otpRecord.passengerId)) {
            customer = await req.db.collection('customers').findOne({ _id: new ObjectId(otpRecord.passengerId) });
          }
        }
        // Fallback: find from roster stop
        if (!customer && ObjectId.isValid(stopId)) {
          const { ObjectId } = require('mongodb');
          const rosterStop = await req.db.collection('roster-assigned-trips').findOne(
            { 'stops.stopId': stopId },
            { projection: { 'stops.$': 1 } }
          );
          const stopEmail = rosterStop?.stops?.[0]?.customer?.email;
          if (stopEmail) {
            customer = await req.db.collection('customers').findOne({ email: stopEmail });
          }
        }

        if (!customer) {
          console.warn(`[WARN] Customer not found for OTP notification. email: ${otpRecord.passengerEmail}, passengerId: ${otpRecord.passengerId}`);
          continue;
        }

        if (otpRecord.isNew) {
          await notificationService.sendRealTimeNotification('customer', customer._id.toString(), {
            type: 'otp_step_in',
            title: '[INFO] Your Boarding OTP',
            message: `Your boarding OTP: ${otpRecord.otp}\n\nShow this to ${driverName} when boarding.`,
            data: {
              otp: otpRecord.otp,
              otpType: 'step_in',
              tripGroupId,
              stopId,
              driverName,
              expiresAt: otpRecord.expiresAt ? new Date(otpRecord.expiresAt).toISOString() : new Date().toISOString(),
            },
            priority: 'urgent',
            category: 'otp_verification',
          });
          console.log(`[OK] OTP notification sent to ${customer.email}`);
        } else {
          console.log(`[INFO] OTP already exists for ${customer.email}, skipping duplicate notification.`);
        }
      } catch (e) {
        console.error(`[WARN] OTP notification failed for ${otpRecord.passengerName}:`, e.message);
      }
    }

    res.json({
      success: true,
      message: `Generated ${otps.length} step-in OTP(s)`,
      data: otps.map(o => ({
        passengerId: o.passengerId,
        passengerName: o.passengerName,
        otp: o.otp,
        verified: o.verified,
        attempts: o.attempts,
        overrideStatus: o.overrideStatus,
        expiresAt: o.expiresAt,
      })),
    });
  } catch (error) {
    console.error('[ERROR] generate-step-in error:', error);
    res.status(500).json({ success: false, message: 'Failed to generate OTPs', error: error.message });
  }
});

// ============================================================================
// POST /api/otp/generate-step-out
// Generate Step-Out OTP for ONE customer (called when driver marks "Boarded")
// ============================================================================
router.post('/generate-step-out', verifyToken, async (req, res) => {
  try {
    const { tripGroupId, stopId, customer } = req.body;

    if (!tripGroupId || !stopId || !customer) {
      return res.status(400).json({ success: false, message: 'tripGroupId, stopId, customer required' });
    }

    const otpRecord = await otpService.generateStepOutOTP(req.db, tripGroupId, stopId, customer);
    const driverName = await getDriverName(req.db, req.user.userId);

    try {
      const customerDoc = await req.db.collection('customers').findOne({ email: customer.email });
      if (customerDoc && otpRecord.isNew) {
        await notificationService.sendRealTimeNotification('customer', customerDoc._id.toString(), {
          type: 'otp_step_out',
          title: '[INFO] Your Drop-Off OTP',
          message: `Your drop-off OTP: ${otpRecord.otp}\n\nShare this with ${driverName} at your destination.`,
          data: {
            otp: otpRecord.otp,
            otpType: 'step_out',
            tripGroupId,
            stopId,
            driverName,
            expiresAt: otpRecord.expiresAt ? new Date(otpRecord.expiresAt).toISOString() : new Date().toISOString(),
          },
          priority: 'urgent',
          category: 'otp_verification',
        });
      }
    } catch (e) {
      console.error('[WARN] Step-out notification failed:', e.message);
    }

    res.json({
      success: true,
      message: 'Step-out OTP generated',
      data: [{
        passengerId: otpRecord.passengerId,
        passengerName: otpRecord.passengerName,
        otp: otpRecord.otp,
        verified: otpRecord.verified,
        attempts: otpRecord.attempts,
        overrideStatus: otpRecord.overrideStatus,
        expiresAt: otpRecord.expiresAt,
      }],
    });
  } catch (error) {
    console.error('[ERROR] generate-step-out error:', error);
    res.status(500).json({ success: false, message: 'Failed to generate OTP', error: error.message });
  }
});

// ============================================================================
// POST /api/otp/verify
// Verify OTP entered by driver
// ============================================================================
router.post('/verify', verifyToken, async (req, res) => {
  try {
    const { tripGroupId, stopId, passengerId, otp } = req.body;

    if (!tripGroupId || !stopId || !passengerId || !otp) {
      return res.status(400).json({ success: false, message: 'tripGroupId, stopId, passengerId, otp required' });
    }

    const result = await otpService.verifyOTP(req.db, tripGroupId, stopId, passengerId, otp);
    
    // Automatically board passenger and generate Drop-Off OTP if this was a Step-In OTP
    if (result.success && result.otpType === 'step_in') {
        // We need to fetch the record just to pass the correct shape, but we already know it's step_in
        autoBoardPassenger(req, tripGroupId, stopId, passengerId, { type: 'step_in' });
    }
    
    res.json(result);
  } catch (error) {
    console.error('[ERROR] verify error:', error);
    res.status(500).json({ success: false, message: 'Failed to verify OTP', error: error.message });
  }
});

// ============================================================================
// POST /api/otp/resend
// Resend OTP — generates fresh code, resets attempts
// ============================================================================
router.post('/resend', verifyToken, async (req, res) => {
  try {
    const { tripGroupId, stopId, passengerId } = req.body;

    if (!tripGroupId || !stopId || !passengerId) {
      return res.status(400).json({ success: false, message: 'tripGroupId, stopId, passengerId required' });
    }

    const otpData = await otpService.resendOTP(req.db, tripGroupId, stopId, passengerId);

    try {
      // Find customer by email from OTP record, or by passengerId as ObjectId fallback
      let customer = null;
      if (otpData.passengerEmail) {
        customer = await req.db.collection('customers').findOne({ email: otpData.passengerEmail });
      }
      // Fallback: try passengerId as ObjectId or Email
      if (!customer) {
        const { ObjectId } = require('mongodb');
        if (ObjectId.isValid(passengerId)) {
          customer = await req.db.collection('customers').findOne({ _id: new ObjectId(passengerId) });
        } else {
          customer = await req.db.collection('customers').findOne({ email: passengerId });
        }
      }
      
        // Fallback: try passengerId as stopId and find customer from roster
        if (!customer) {
           const roster = await req.db.collection('roster-assigned-trips').findOne({ tripGroupId });
           if (roster) {
              const stop = roster.stops?.find(s => s.stopId === stopId);
              if (stop) {
                 if (stop.customer) {
                    if (stop.customer.email === passengerId || stop.customer.id === passengerId || stopId === passengerId) {
                       if (stop.customer.email) {
                          customer = await req.db.collection('customers').findOne({ email: stop.customer.email });
                       }
                    }
                 } else if (stop.passengers && Array.isArray(stop.passengers)) {
                    let pName = passengerId;
                    if (passengerId.startsWith('passenger_')) {
                       const idx = parseInt(passengerId.split('_')[1], 10);
                       if (!isNaN(idx) && stop.passengers[idx]) {
                          pName = stop.passengers[idx];
                       }
                    }
                    customer = await req.db.collection('customers').findOne({ name: pName, email: { $exists: true, $ne: "" } });
                    if (!customer) {
                       customer = await req.db.collection('customers').findOne({ name: pName });
                    }
                 }
              }
           }
        }
  
        if (customer) {
          const targetId = customer._id ? customer._id.toString() : customer.id;
          await notificationService.sendRealTimeNotification('customer', targetId, {
          type: `otp_${otpData.type}_resend`,
          title: '[INFO] New OTP Sent',
          message: `Your new OTP: ${otpData.otp}\n\nValid for 4 hours.`,
          data: {
            otp: otpData.otp,
            otpType: otpData.type,
            tripGroupId,
            stopId,
            expiresAt: otpData.expiresAt.toISOString(),
          },
          priority: 'urgent',
          category: 'otp_verification',
        });
        console.log(`[OK] Resend notification sent to ${customer.email}`);
      } else {
        console.warn(`[WARN] Could not find customer for resend notification. passengerId: ${passengerId}, email: ${otpData.passengerEmail}`);
      }
    } catch (e) {
      console.error('[WARN] Resend notification failed:', e.message);
    }

    res.json({ success: true, message: 'OTP resent', data: { otp: otpData.otp, expiresAt: otpData.expiresAt } });
  } catch (error) {
    console.error('[ERROR] resend error:', error);
    res.status(500).json({ success: false, message: 'Failed to resend OTP', error: error.message });
  }
});

// ============================================================================
// POST /api/otp/override-request
// Driver submits override request with reason + optional photo
// ============================================================================
router.post('/override-request', verifyToken, upload.single('photo'), async (req, res) => {
  try {
    const { tripGroupId, stopId, passengerId, reason } = req.body;
    const driverId = req.user.userId;

    if (!tripGroupId || !stopId || !passengerId || !reason) {
      return res.status(400).json({ success: false, message: 'tripGroupId, stopId, passengerId, reason required' });
    }

    const photoUrl = req.file ? `/uploads/override-photos/${req.file.filename}` : null;

    await otpService.requestOverride(req.db, tripGroupId, stopId, passengerId, driverId, reason, photoUrl);

    // Notify all admins — include full driver + passenger info so approval screen shows everything
    try {
      const driverInfo = await getDriverInfo(req.db, driverId, tripGroupId);
      const otpRecord = await req.db.collection('trip_otps').findOne({ tripGroupId, stopId, passengerId });

      // Also store driver info on the OTP record so getFailedOTPLog enrichment has it
      await req.db.collection('trip_otps').updateOne(
        { tripGroupId, stopId, passengerId },
        {
          $set: {
            driverName:    driverInfo.driverName,
            driverPhone:   driverInfo.driverPhone,
            driverEmail:   driverInfo.driverEmail,
            driverCode:    driverInfo.driverCode,
            vehicleNumber: driverInfo.vehicleNumber,
            vehicleModel:  driverInfo.vehicleModel,
          }
        }
      );

      await notificationService.sendNotificationToRole('admin', {
        type: 'otp_override_request',
        title: '[WARN] OTP Override Request',
        message: `${driverInfo.driverName} requests override for ${otpRecord?.passengerName || 'passenger'}`,
        data: {
          tripGroupId,
          stopId,
          passengerId,
          driverId,
          // [OK] Full driver info stored in notification data
          driverName:    driverInfo.driverName,
          driverPhone:   driverInfo.driverPhone,
          driverEmail:   driverInfo.driverEmail,
          driverCode:    driverInfo.driverCode,
          vehicleNumber: driverInfo.vehicleNumber,
          vehicleModel:  driverInfo.vehicleModel,
          // Passenger info
          passengerName:  otpRecord?.passengerName  || '',
          passengerEmail: otpRecord?.passengerEmail || '',
          passengerPhone: otpRecord?.passengerPhone || '',
          // Override details
          reason,
          photoUrl,
          otpType: otpRecord?.type || 'step_in',
          attempts: otpRecord?.attempts || 0,
          overrideRequestedAt: new Date().toISOString(),
        },
        priority: 'high',
        category: 'otp_override',
      });
    } catch (e) {
      console.error('[WARN] Admin notification failed:', e.message);
    }

    res.json({ success: true, message: 'Override request submitted. Awaiting admin approval.' });
  } catch (error) {
    console.error('[ERROR] override-request error:', error);
    res.status(500).json({ success: false, message: 'Failed to request override', error: error.message });
  }
});

// ============================================================================
// POST /api/otp/override-approve
// Admin approves or rejects an override
// ============================================================================
router.post('/override-approve', verifyToken, async (req, res) => {
  try {
    const { tripGroupId, stopId, passengerId, approved, adminNotes } = req.body;
    const adminId = req.user.userId;

    if (!tripGroupId || approved === undefined) {
      return res.status(400).json({ success: false, message: 'tripGroupId and approved required' });
    }

    if (!['admin', 'super_admin'].includes(req.user.role)) {
      return res.status(403).json({ success: false, message: 'Only admins can approve overrides' });
    }

    await otpService.processOverride(req.db, tripGroupId, stopId, passengerId, adminId, approved, adminNotes);

    // Notify driver — find the record by tripGroupId (most flexible)
    try {
      const otpRecord = await req.db.collection('trip_otps').findOne({
        tripGroupId,
        overrideStatus: approved ? 'approved' : 'rejected',
      });

      // Auto-board passenger if this override is for a step-in
      if (approved && otpRecord && otpRecord.type === 'step_in') {
          autoBoardPassenger(req, tripGroupId, stopId, passengerId, otpRecord);
      }

      if (otpRecord?.overrideRequestedBy) {
        await notificationService.sendRealTimeNotification('driver', otpRecord.overrideRequestedBy, {
          type: 'otp_override_response',
          title: approved ? '[OK] Override Approved' : '[ERROR] Override Rejected',
          message: approved
            ? `Override approved for ${otpRecord.passengerName}`
            : `Override rejected for ${otpRecord.passengerName}. ${adminNotes || 'Please retry OTP.'}`,
          data: { tripGroupId, stopId, passengerId, approved, adminNotes },
          priority: 'high',
          category: 'otp_override',
        });
      }
    } catch (e) {
      console.error('[WARN] Driver notification failed:', e.message);
    }

    res.json({ success: true, message: approved ? 'Override approved' : 'Override rejected' });
  } catch (error) {
    console.error('[ERROR] override-approve error:', error);
    res.status(500).json({ success: false, message: 'Failed to process override', error: error.message });
  }
});

// ============================================================================
// POST /api/otp/no-show
// Driver marks a passenger as no-show (customer did not arrive at stop)
// This sets overrideStatus = 'no_show' so departure is not blocked
// ============================================================================
router.post('/no-show', verifyToken, async (req, res) => {
  try {
    const { tripGroupId, stopId, passengerId, passengerName } = req.body;

    if (!tripGroupId || !stopId || !passengerId) {
      return res.status(400).json({ success: false, message: 'tripGroupId, stopId, passengerId are required' });
    }

    const db = req.db;

    // Update the OTP record — mark as no_show so depart check skips it
    const result = await db.collection('trip_otps').updateOne(
      { tripGroupId, stopId, passengerId },
      {
        $set: {
          overrideStatus: 'no_show',
          noShowAt: new Date(),
          noShowBy: req.user?.email || req.user?.id || 'driver',
          updatedAt: new Date(),
        }
      },
      { upsert: true } // create record if OTP was never generated (edge case)
    );

    console.log(`[OK] Passenger ${passengerName || passengerId} marked as no-show for stop ${stopId}`);

    res.json({ success: true, message: 'Passenger marked as no-show' });
  } catch (error) {
    console.error('[ERROR] no-show error:', error);
    res.status(500).json({ success: false, message: 'Failed to mark no-show', error: error.message });
  }
});

// ============================================================================
// GET /api/otp/status/:tripGroupId/:stopId
// Get OTP verification status for all passengers at a stop
// ============================================================================
router.get('/status/:tripGroupId/:stopId', verifyToken, async (req, res) => {
  try {
    const { tripGroupId, stopId } = req.params;
    const status = await otpService.getStopOTPStatus(req.db, tripGroupId, stopId);
    res.json({ success: true, data: status });
  } catch (error) {
    console.error('[ERROR] status error:', error);
    res.status(500).json({ success: false, message: 'Failed to get OTP status', error: error.message });
  }
});

// ============================================================================
// GET /api/otp/failed-log
// Admin: get ALL OTP records with optional filters
// ============================================================================
router.get('/failed-log', verifyToken, async (req, res) => {
  try {
    // Allow admin roles — but don't block other roles from viewing their own data
    const filters = {
      startDate: req.query.startDate,
      endDate: req.query.endDate,
      driverId: req.query.driverId,
      status: req.query.status,
      limit: parseInt(req.query.limit) || 500,
    };

    const logs = await otpService.getFailedOTPLog(req.db, filters);
    res.json({ success: true, data: logs, count: logs.length });
  } catch (error) {
    console.error('[ERROR] failed-log error:', error);
    res.status(500).json({ success: false, message: 'Failed to get log', error: error.message });
  }
});

module.exports = router;
