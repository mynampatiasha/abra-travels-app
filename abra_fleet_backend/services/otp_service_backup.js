// ============================================================================
// services/otp_service.js
// OTP GENERATION, VERIFICATION, AND OVERRIDE MANAGEMENT SERVICE
// ============================================================================

class OTPService {
  constructor() {
    console.log('✅ OTPService initialized');
  }

  /**
   * Generate a 6-digit OTP
   */
  generateOTP() {
    return Math.floor(100000 + Math.random() * 900000).toString();
  }

  /**
   * Generate Step-In OTPs for all customers at a stop
   */
  async generateStepInOTPs(db, tripGroupId, stopId, customers) {
    try {
      console.log('\n' + '🔐' * 40);
      console.log('GENERATING STEP-IN OTPs');
      console.log('🔐' * 40);
      console.log(`Trip Group: ${tripGroupId}`);
      console.log(`Stop ID: ${stopId}`);
      console.log(`Customers: ${customers.length}`);

      const otps = [];
      const expiresAt = new Date(Date.now() + 4 * 60 * 60 * 1000); // 4 hours � covers full trip duration

      for (const customer of customers) {
        const otp = this.generateOTP();

        const otpDoc = {
          tripGroupId,
          stopId,
          passengerId: customer.id || customer._id?.toString() || customer.email,
          passengerName: customer.name,
          passengerEmail: customer.email,
          passengerPhone: customer.phone || '',
          otp,
          type: 'step_in',
          attempts: 0,
          verified: false,
          overrideStatus: 'none',
          overrideReason: null,
          overridePhoto: null,
          overrideRequestedBy: null,
          overrideApprovedBy: null,
          createdAt: new Date(),
          expiresAt,
        };

        // ✅ UPSERT: If an unverified OTP already exists for this passenger at this stop,
        // update it with a fresh OTP instead of creating a duplicate
        const passengerId = customer.id || customer._id?.toString() || customer.email;
        const upsertResult = await db.collection('trip_otps').findOneAndUpdate(
          {
            tripGroupId,
            stopId,
            passengerId,
            type: 'step_in',
          },
          {
            $set: {
              expiresAt,
              passengerName: customer.name,
              passengerEmail: customer.email,
              passengerPhone: customer.phone || '',
              updatedAt: new Date(),
            },
            $setOnInsert: {
              otp,
              tripGroupId,
              stopId,
              passengerId,
              type: 'step_in',
              verified: false,
              attempts: 0,
              overrideStatus: 'none',
              overrideReason: null,
              overridePhoto: null,
              overrideRequestedBy: null,
              overrideApprovedBy: null,
              createdAt: new Date(),
            },
          },
          { upsert: true, returnDocument: 'after', includeResultMetadata: true }
        );

        const savedDoc = upsertResult.value || upsertResult;
        
        otps.push({
          ...otpDoc,
          otp: savedDoc?.otp || otpDoc.otp,
          verified: savedDoc?.verified ?? otpDoc.verified,
          attempts: savedDoc?.attempts ?? otpDoc.attempts,
          overrideStatus: savedDoc?.overrideStatus ?? otpDoc.overrideStatus,
          _id: savedDoc?._id || upsertResult?.upsertedId,
          isNew: upsertResult.lastErrorObject ? !upsertResult.lastErrorObject.updatedExisting : true,
        });

        console.log(`✅ OTP upserted for ${customer.name}: ${otp}`);
      }

      console.log(`\n✅ Generated ${otps.length} step-in OTPs`);
      console.log('🔐' * 40 + '\n');

      return otps;
    } catch (error) {
      console.error('❌ Error generating step-in OTPs:', error);
      throw error;
    }
  }

  /**
   * Generate Step-Out OTP for a specific customer
   */
  async generateStepOutOTP(db, tripGroupId, stopId, customer) {
    try {
      console.log('\n' + '🔐' * 40);
      console.log('GENERATING STEP-OUT OTP');
      console.log('🔐' * 40);
      console.log(`Trip Group: ${tripGroupId}`);
      console.log(`Stop ID: ${stopId}`);
      console.log(`Customer: ${customer.name}`);

      const otp = this.generateOTP();
      const expiresAt = new Date(Date.now() + 4 * 60 * 60 * 1000); // 4 hours
      const passengerId = customer.id || customer._id?.toString() || customer.email;

      const result = await db.collection('trip_otps').findOneAndUpdate(
        {
          tripGroupId,
          stopId,
          passengerId,
          type: 'step_out',
        },
        {
          $set: {
            expiresAt,
            passengerName: customer.name,
            passengerEmail: customer.email,
            passengerPhone: customer.phone || '',
            updatedAt: new Date(),
          },
          $setOnInsert: {
            otp: otp,
            tripGroupId,
            stopId,
            passengerId,
            type: 'step_out',
            verified: false,
            attempts: 0,
            overrideStatus: 'none',
            overrideReason: null,
            overridePhoto: null,
            overrideRequestedBy: null,
            overrideApprovedBy: null,
            createdAt: new Date(),
          },
        },
          { upsert: true, returnDocument: 'after', includeResultMetadata: true }
        );
  
        const savedDoc = result.value || result;
        const isNew = result.lastErrorObject ? !result.lastErrorObject.updatedExisting : true;
  
        console.log(`✅ Step-out OTP generated/retrieved: ${savedDoc.otp}`);
  
        return {
          _id: savedDoc._id,
          tripGroupId,
          stopId,
          passengerId,
          passengerName: customer.name,
          otp: savedDoc.otp,
          expiresAt: savedDoc.expiresAt,
          isNew,
        };

    } catch (error) {
      console.error('❌ Error generating step-out OTP:', error);
      throw error;
    }
  }

  /**
   * Verify OTP
   */
  async verifyOTP(db, tripGroupId, stopId, passengerId, enteredOTP) {
    try {
      console.log('\n' + '🔍' * 40);
      console.log('VERIFYING OTP');
      console.log('🔍' * 40);
      console.log(`Trip Group: ${tripGroupId}`);
      console.log(`Stop ID: ${stopId}`);
      console.log(`Passenger ID: ${passengerId}`);
      console.log(`Entered OTP: ${enteredOTP}`);

      const { ObjectId } = require('mongodb');
      const passIdOr = [{ passengerId }];
      if (ObjectId.isValid(passengerId)) {
        passIdOr.push({ passengerId: new ObjectId(passengerId) });
      }

      // Find the OTP record - no expiry check, valid for the entire trip stop duration
      let otpRecord = await db.collection('trip_otps').findOne({
        tripGroupId,
        stopId,
        $or: passIdOr,
        verified: false,
      });

      // Fallback for Drop-Off (step_out) OTPs which were created at the Pickup stop
      if (!otpRecord) {
        otpRecord = await db.collection('trip_otps').findOne({
          tripGroupId,
          $or: passIdOr,
          verified: false,
        });
      }

      if (!otpRecord) {
        console.log('❌ OTP not found or expired');
        return {
          success: false,
          message: 'OTP not found or expired. Please request a new OTP.',
          attemptsRemaining: 0,
        };
      }

      console.log(`Found OTP record: ${otpRecord.otp}`);
      console.log(`Current attempts: ${otpRecord.attempts}`);

      // Check if max attempts reached
      if (otpRecord.attempts >= 3) {
        console.log('❌ Max attempts reached');
        return {
          success: false,
          message: 'Maximum attempts reached. Please resend OTP or request override.',
          attemptsRemaining: 0,
          maxAttemptsReached: true,
        };
      }

      // Verify OTP
      if (otpRecord.otp === enteredOTP) {
        // OTP is correct
        await db.collection('trip_otps').updateOne(
          { _id: otpRecord._id },
          {
            $set: {
              verified: true,
              verifiedAt: new Date(),
              attempts: otpRecord.attempts + 1,
            },
          }
        );

        console.log('✅ OTP VERIFIED SUCCESSFULLY');
        console.log('🔍' * 40 + '\n');

        return {
          success: true,
          message: 'OTP verified successfully',
          otpType: otpRecord.type,
          passengerName: otpRecord.passengerName,
        };
      } else {
        // OTP is incorrect
        const newAttempts = otpRecord.attempts + 1;
        const attemptsRemaining = 3 - newAttempts;

        await db.collection('trip_otps').updateOne(
          { _id: otpRecord._id },
          {
            $set: { attempts: newAttempts },
            $push: {
              failedAttempts: {
                attemptNumber: newAttempts,
                enteredOTP,
                timestamp: new Date(),
              },
            },
          }
        );

        console.log(`❌ OTP INCORRECT (Attempt ${newAttempts}/3)`);
        console.log('🔍' * 40 + '\n');

        return {
          success: false,
          message: `Incorrect OTP. ${attemptsRemaining} attempt(s) remaining.`,
          attemptsRemaining,
          maxAttemptsReached: newAttempts >= 3,
        };
      }
    } catch (error) {
      console.error('❌ Error verifying OTP:', error);
      throw error;
    }
  }

  /**
   * Resend OTP (generates new OTP and resets attempts)
   */
  async resendOTP(db, tripGroupId, stopId, passengerId) {
    try {
      console.log('\n' + '🔄' * 40);
      console.log('RESENDING OTP');
      console.log('🔄' * 40);

      const { ObjectId } = require('mongodb');
      const passIdOr = [{ passengerId }];
      if (ObjectId.isValid(passengerId)) {
        passIdOr.push({ passengerId: new ObjectId(passengerId) });
      }

      // Find existing OTP record
      let existingOTP = await db.collection('trip_otps').findOne({
        tripGroupId,
        stopId,
        $or: passIdOr,
        verified: false,
      });

      // Fallback for Drop-Off (step_out) OTPs
      if (!existingOTP) {
        existingOTP = await db.collection('trip_otps').findOne({
          tripGroupId,
          $or: passIdOr,
          verified: false,
        });
      }

      if (!existingOTP) {
        // Auto-heal for Drop-Off stops: if OTP doesn't exist (driver skipped marking as boarded at pickup), generate it now
        if (stopId && stopId.includes('drop')) {
          let customer = null;
          if (ObjectId.isValid(passengerId)) {
            customer = await db.collection('customers').findOne({ _id: new ObjectId(passengerId) });
          }
          if (!customer) {
            customer = await db.collection('customers').findOne({ email: passengerId });
          }
          if (customer) {
            console.log('⚠️ Auto-generating missing step-out OTP during resend...');
            const newOtp = await this.generateStepOutOTP(db, tripGroupId, stopId, customer);
            return {
              otp: newOtp.otp,
              expiresAt: new Date(newOtp.expiresAt),
              type: 'step_out',
              passengerEmail: customer.email,
              passengerId: newOtp.passengerId,
            };
          }
        }
        console.log('❌ No OTP record found');
        throw new Error('No OTP record found for this passenger');
      }

      // Use existing OTP
      const currentOTP = existingOTP.otp;
      const expiresAt = new Date(Date.now() + 30 * 60 * 1000);

      // Update the record
      await db.collection('trip_otps').updateOne(
        { _id: existingOTP._id },
        {
          $set: {
            attempts: 0,
            expiresAt,
            resendCount: (existingOTP.resendCount || 0) + 1,
            lastResendAt: new Date(),
          },
        }
      );

      console.log(`✅ OTP retrieved for resend: ${currentOTP}`);
      console.log('🔄' * 40 + '\n');

      return {
        otp: currentOTP,
        passengerName: existingOTP.passengerName,
        passengerEmail: existingOTP.passengerEmail,
        passengerPhone: existingOTP.passengerPhone,
        type: existingOTP.type,
        expiresAt,
      };
    } catch (error) {
      console.error('❌ Error resending OTP:', error);
      throw error;
    }
  }

  /**
   * Request Override
   */
  async requestOverride(db, tripGroupId, stopId, passengerId, driverId, reason, photoUrl) {
    try {
      console.log('\n' + '⚠️' * 40);
      console.log('OVERRIDE REQUESTED');
      console.log('⚠️' * 40);

      const { ObjectId } = require('mongodb');
      const passIdOr = [{ passengerId }];
      if (ObjectId.isValid(passengerId)) {
        passIdOr.push({ passengerId: new ObjectId(passengerId) });
      }

      let otpRecord = await db.collection('trip_otps').findOne({
        tripGroupId,
        stopId,
        $or: passIdOr,
        verified: false,
      });

      // Fallback for Drop-Off (step_out) OTPs
      if (!otpRecord) {
        otpRecord = await db.collection('trip_otps').findOne({
          tripGroupId,
          $or: passIdOr,
          verified: false,
        });
      }

      if (!otpRecord) {
        throw new Error('OTP record not found');
      }

      const result = await db.collection('trip_otps').updateOne(
        { _id: otpRecord._id },
        {
          $set: {
            overrideStatus: 'requested',
            overrideReason: reason,
            overridePhoto: photoUrl,
            overrideRequestedBy: driverId,
            overrideRequestedAt: new Date(),
          },
        }
      );

      if (result.matchedCount === 0) {
        throw new Error('OTP record not found');
      }

      console.log('✅ Override request recorded');
      console.log('⚠️' * 40 + '\n');

      return { success: true };
    } catch (error) {
      console.error('❌ Error requesting override:', error);
      throw error;
    }
  }

  /**
   * Approve/Reject Override
   */
  async processOverride(db, tripGroupId, stopId, passengerId, adminId, approved, adminNotes) {
    try {
      console.log('\n' + '👮' * 40);
      console.log(`OVERRIDE ${approved ? 'APPROVED' : 'REJECTED'}`);
      console.log('👮' * 40);

      const updateData = {
        overrideStatus: approved ? 'approved' : 'rejected',
        overrideApprovedBy: adminId,
        overrideApprovedAt: new Date(),
        overrideAdminNotes: adminNotes,
      };

      if (approved) {
        updateData.verified = true;
        updateData.verifiedAt = new Date();
        updateData.verificationMethod = 'manual_override';
      }

      // Match on tripGroupId + stopId — try multiple fallbacks since passengerId format may differ
      let result = await db.collection('trip_otps').updateOne(
        { tripGroupId, stopId, overrideStatus: { $in: ['requested', 'approved', 'rejected'] } },
        { $set: updateData }
      );

      if (result.matchedCount === 0 && passengerId) {
        result = await db.collection('trip_otps').updateOne(
          { tripGroupId, passengerId, overrideStatus: { $in: ['requested', 'approved', 'rejected'] } },
          { $set: updateData }
        );
      }

      if (result.matchedCount === 0) {
        result = await db.collection('trip_otps').updateOne(
          { tripGroupId, overrideStatus: { $in: ['requested', 'approved', 'rejected'] } },
          { $set: updateData }
        );
      }

      // Final fallback — match any record for this trip (in case overrideStatus was reset)
      if (result.matchedCount === 0) {
        result = await db.collection('trip_otps').updateOne(
          { tripGroupId },
          { $set: updateData }
        );
      }

      if (result.matchedCount === 0) {
        throw new Error('Override request not found');
      }

      console.log(`✅ Override ${approved ? 'approved' : 'rejected'}`);
      console.log('👮' * 40 + '\n');

      return { success: true };
    } catch (error) {
      console.error('❌ Error processing override:', error);
      throw error;
    }
  }

  /**
   * Get OTP status for a stop
   */
  async getStopOTPStatus(db, tripGroupId, stopId) {
    try {
      const otps = await db.collection('trip_otps').find({
        tripGroupId,
        stopId,
      }).toArray();

      return otps.map(otp => ({
        passengerId: otp.passengerId,
        passengerName: otp.passengerName,
        type: otp.type,
        verified: otp.verified,
        attempts: otp.attempts,
        overrideStatus: otp.overrideStatus,
        expiresAt: otp.expiresAt,
        createdAt: otp.createdAt,
      }));
    } catch (error) {
      console.error('❌ Error getting OTP status:', error);
      throw error;
    }
  }

  /**
   * Get ALL OTP records (not just failed) — for admin log screen
   * Enriches each record with driver info, vehicle info, and readable trip/stop details
   */
  async getFailedOTPLog(db, filters = {}) {
    try {
      const query = {};

      if (filters.startDate) {
        query.createdAt = { $gte: new Date(filters.startDate) };
      }
      if (filters.endDate) {
        query.createdAt = { ...query.createdAt, $lte: new Date(filters.endDate) };
      }
      if (filters.driverId) {
        query.overrideRequestedBy = filters.driverId;
      }
      if (filters.status) {
        query.overrideStatus = filters.status;
      }

      const logs = await db.collection('trip_otps')
        .find(query)
        .sort({ createdAt: -1 })
        .limit(filters.limit || 500)
        .toArray();

      // ── Enrich each record with readable driver + trip info
      const { ObjectId } = require('mongodb');

      const enriched = await Promise.all(logs.map(async (log) => {
        const result = { ...log };

        // ── 1. Resolve driver info from overrideRequestedBy or noShowBy
        const driverIdRaw = log.overrideRequestedBy || log.noShowBy;
        if (driverIdRaw) {
          try {
            const driverObjId = ObjectId.isValid(driverIdRaw) ? new ObjectId(driverIdRaw) : null;
            if (driverObjId) {
              const driver = await db.collection('drivers').findOne(
                { _id: driverObjId },
                { projection: { personalInfo: 1, name: 1, email: 1, driverId: 1 } }
              );
              if (driver) {
                result.driverName  = driver.personalInfo?.name  || driver.name  || 'Unknown Driver';
                result.driverPhone = driver.personalInfo?.phone || driver.phone || '';
                result.driverEmail = driver.personalInfo?.email || driver.email || '';
                result.driverCode  = driver.driverId || '';
              }
            }
          } catch (_) {}
        }

        // ── 2. Resolve trip info from tripGroupId → roster-assigned-trips
        if (log.tripGroupId) {
          try {
            const trip = await db.collection('roster-assigned-trips').findOne(
              { tripGroupId: log.tripGroupId },
              { projection: { vehicleId: 1, vehicleNumber: 1, tripNumber: 1, scheduledDate: 1, stops: 1 } }
            );
            if (trip) {
              result.tripNumber    = trip.tripNumber || '';
              result.scheduledDate = trip.scheduledDate || '';
              result.vehicleNumber = trip.vehicleNumber || '';

              // Resolve vehicle details
              if (trip.vehicleId) {
                try {
                  const vehicleObjId = ObjectId.isValid(trip.vehicleId.toString())
                    ? new ObjectId(trip.vehicleId.toString()) : null;
                  if (vehicleObjId) {
                    const vehicle = await db.collection('vehicles').findOne(
                      { _id: vehicleObjId },
                      { projection: { registrationNumber: 1, name: 1, model: 1 } }
                    );
                    if (vehicle) {
                      result.vehicleNumber = vehicle.registrationNumber || vehicle.name || result.vehicleNumber;
                      result.vehicleModel  = vehicle.model || '';
                    }
                  }
                } catch (_) {}
              }

              // Resolve stop address from stops array
              if (log.stopId && trip.stops) {
                const stop = trip.stops.find(s => s.stopId === log.stopId);
                if (stop) {
                  result.stopAddress = stop.location?.address || stop.address || '';
                  result.stopSequence = stop.sequence || '';
                }
              }
            }
          } catch (_) {}
        }

        // ── 3. Resolve customer company name + employee ID from passengerEmail
        if (log.passengerEmail || log.passengerId) {
          try {
            let customer = null;

            // Try by email first
            if (log.passengerEmail) {
              customer = await db.collection('customers').findOne(
                { email: log.passengerEmail },
                { projection: { companyName: 1, company: 1, employeeId: 1, customerId: 1, phone: 1 } }
              );
            }

            // Fallback: try by phone from OTP record
            if (!customer && log.passengerPhone) {
              customer = await db.collection('customers').findOne(
                { phone: log.passengerPhone },
                { projection: { companyName: 1, company: 1, employeeId: 1, customerId: 1, phone: 1 } }
              );
            }

            // Fallback: find from roster stop using stopId
            if (!customer && log.stopId) {
              const rosterStop = await db.collection('roster-assigned-trips').findOne(
                { 'stops.stopId': log.stopId },
                { projection: { 'stops.$': 1 } }
              );
              const stopEmail = rosterStop?.stops?.[0]?.customer?.email;
              if (stopEmail) {
                customer = await db.collection('customers').findOne(
                  { email: stopEmail },
                  { projection: { companyName: 1, company: 1, employeeId: 1, customerId: 1, phone: 1 } }
                );
                // Also backfill email on the OTP record for future lookups
                if (customer && !log.passengerEmail) {
                  result.passengerEmail = stopEmail;
                }
              }
            }

            if (customer) {
              result.companyName = customer.companyName
                || customer.company?.name
                || customer.name?.companyName
                || '';
              result.employeeId = customer.employeeId || customer.customerId || '';
            }
          } catch (_) {}
        }

        // ── 4. If driver info not resolved yet, look up from trip document
        if (!result.driverName && log.tripGroupId) {
          try {
            const trip = await db.collection('roster-assigned-trips').findOne(
              { tripGroupId: log.tripGroupId },
              { projection: { driverId: 1 } }
            );
            if (trip?.driverId) {
              const driver = await db.collection('drivers').findOne(
                { _id: trip.driverId },
                { projection: { personalInfo: 1, name: 1, email: 1, driverId: 1 } }
              );
              if (driver) {
                result.driverName  = driver.personalInfo?.name  || driver.name  || '';
                result.driverPhone = driver.personalInfo?.phone || driver.phone || '';
                result.driverEmail = driver.personalInfo?.email || driver.email || '';
                result.driverCode  = driver.driverId || '';
              }
            }
          } catch (_) {}
        }

        return result;
      }));

      return enriched;
    } catch (error) {
      console.error('❌ Error getting OTP log:', error);
      throw error;
    }
  }

  /**
   * Create TTL index on trip_otps collection
   */
  async createTTLIndex(db) {
    try {
      await db.collection('trip_otps').createIndex(
        { expiresAt: 1 },
        { expireAfterSeconds: 0 }
      );
      console.log('✅ TTL index created on trip_otps collection');
    } catch (error) {
      console.error('❌ Error creating TTL index:', error);
      throw error;
    }
  }
}

module.exports = new OTPService();
