// routes/assignment_routes.js
// COMPLETE PRODUCTION VERSION - ALL FEATURES INTEGRATED
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { getRedisClient } = require('../config/redis');
const { getIO } = require('../config/websocket_config');
const { findBestMatches } = require('../utils/assignment_algorithm');
const { acquireLock, releaseLock, acquireMultipleLocks, releaseMultipleLocks } = require('../utils/redis_lock_manager');
const { calculateRosterDistances, calculateGroupDistances } = require('../utils/distance_calculator');

/**
 * ============================================================================
 * ASSIGNMENT ROUTES - REAL-TIME FLEET ASSIGNMENT WITH TRIP CREATION
 * ============================================================================
 * 
 * ENDPOINTS:
 * 1. GET  /api/assignment/pending-rosters     - Get pending rosters with auto-grouping
 * 2. POST /api/assignment/find-matches        - Find best vehicles for roster(s)
 * 3. POST /api/assignment/assign              - Assign single roster + CREATE TRIP
 * 4. POST /api/assignment/assign-group        - Assign group + CREATE TRIP
 * 5. GET  /api/assignment/available-vehicles  - Get real-time vehicle availability
 * 6. POST /api/assignment/unassign            - Unassign roster + REMOVE FROM TRIP
 */

// ============================================================================
// HELPER: Get Admin Organization from Email
// ============================================================================
function getAdminOrganization(email) {
  if (!email || !email.includes('@')) {
    return 'unknown';
  }
  return email.split('@')[1].toLowerCase();
}

// ============================================================================
// HELPER: Extract Phone Number Safely (FIXES "N/A" ISSUE)
// ============================================================================
function extractPhone(roster) {
  // Try all possible phone field locations
  return roster.customerPhone || 
         roster.employeeDetails?.phone || 
         roster.phone ||
         roster.employeeDetails?.mobile ||
         roster.contactNumber ||
         roster.mobileNumber ||
         roster.phoneNumber ||
         'Not provided';
}

// ============================================================================
// HELPER: Extract Address String
// ============================================================================
function extractAddress(location) {
  if (!location) return 'Not provided';
  
  if (typeof location === 'string') return location;
  
  if (location.address) return location.address;
  
  if (location.name) return location.name;
  
  if (location.coordinates) {
    const lat = location.coordinates.latitude || location.coordinates.lat;
    const lng = location.coordinates.longitude || location.coordinates.lng;
    if (lat && lng) {
      return `${lat.toFixed(6)}, ${lng.toFixed(6)}`;
    }
  }
  
  return 'Location not specified';
}

// ============================================================================
// HELPER: Format Date for Display (DD MMM YYYY)
// ============================================================================
function formatDate(date) {
  const d = new Date(date);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const day = d.getDate();
  const month = months[d.getMonth()];
  const year = d.getFullYear();
  return `${day} ${month} ${year}`;
}

// ============================================================================
// HELPER: Format Day of Week
// ============================================================================
function formatDayOfWeek(date) {
  const d = new Date(date);
  const days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  return days[d.getDay()];
}

// ============================================================================
// HELPER: Generate Trip Number
// ============================================================================
async function generateTripNumber(db, date) {
  const dateStr = typeof date === 'string' ? date : date.toISOString().split('T')[0];
  const tripCount = await db.collection('trips').countDocuments({
    scheduledDate: { $regex: `^${dateStr}` },
  });
  return `TRIP-${dateStr}-${String(tripCount + 1).padStart(4, '0')}`;
}

// ============================================================================
// HELPER: Get Trip Sequence for Vehicle
// ============================================================================
async function getVehicleTripSequence(db, vehicleId, date) {
  const dateStr = typeof date === 'string' ? date : date.toISOString().split('T')[0];
  const vehicleTripsToday = await db.collection('trips').countDocuments({
    vehicleId: new ObjectId(vehicleId),
    scheduledDate: { $regex: `^${dateStr}` },
  });
  return vehicleTripsToday + 1;
}

// ============================================================================
// HELPER: Send Comprehensive Notifications (COMPLETE WITH ALL INFO)
// ============================================================================
async function sendAssignmentNotifications(db, roster, vehicle, driver, trip, io) {
  try {
    console.log('\n📱 SENDING COMPREHENSIVE NOTIFICATIONS...');
    console.log('═'.repeat(80));
    
    const notifications = [];
    const tripDate = formatDate(trip.scheduledDate || new Date());
    const tripDay = formatDayOfWeek(trip.scheduledDate || new Date());
    
    // ────────────────────────────────────────────────────────────────────
    // 1. CUSTOMER NOTIFICATION (Detailed Trip Information)
    // ────────────────────────────────────────────────────────────────────
    if (roster.userId || roster.firebaseUid || roster.customerEmail) {
      console.log('\n📧 Preparing CUSTOMER notification...');
      
      // Determine pickup and drop based on roster type
      const rosterType = (roster.rosterType || 'both').toLowerCase();
      let pickupLocation, dropLocation, tripTypeText;
      
      if (rosterType.includes('login') || rosterType === 'both') {
        pickupLocation = roster.locations?.pickup || roster.pickupLocation;
        dropLocation = roster.locations?.drop || roster.officeCoordinates || roster.dropLocation;
        tripTypeText = 'Login Trip (Home to Office)';
      } else {
        pickupLocation = roster.locations?.drop || roster.officeCoordinates || roster.dropLocation;
        dropLocation = roster.locations?.pickup || roster.pickupLocation;
        tripTypeText = 'Logout Trip (Office to Home)';
      }
      
      const pickupAddress = extractAddress(pickupLocation);
      const dropAddress = extractAddress(dropLocation);
      const customerPhone = extractPhone(roster);
      
      // Build detailed notification body
      const notificationBody = `
🚗 TRIP ASSIGNED - ${trip.tripNumber}

📅 DATE & TIME:
   ${tripDay}, ${tripDate}
   Pickup Time: ${roster.startTime || 'TBD'}
   ${roster.endTime ? `Drop Time: ${roster.endTime}` : ''}

📍 PICKUP LOCATION:
   ${pickupAddress}

📍 DROP LOCATION:
   ${dropAddress}

🚙 VEHICLE DETAILS:
   ${vehicle.make || ''} ${vehicle.model || ''}
   Registration: ${vehicle.registrationNumber}
   ${vehicle.color ? `Color: ${vehicle.color}` : ''}

👨‍✈️ DRIVER DETAILS:
   Name: ${driver.name}
   Phone: ${driver.phone || 'Not provided'}
   ${driver.rating ? `Rating: ${driver.rating}⭐` : ''}

📋 TRIP INFO:
   ${tripTypeText}
   Office: ${roster.officeLocation || 'Not specified'}
   ${trip.isGroupTrip ? `🚌 Group Trip (${trip.totalPassengers} passengers)` : '📦 Individual Trip'}
   ${trip.distanceData?.totalDistanceKm ? `Distance: ${trip.distanceData.totalDistanceKm} km` : ''}

💡 INSTRUCTIONS:
   • Please be ready 5 minutes before pickup time
   • Driver will call you upon arrival
   • Contact driver if you need assistance
   • Have your ID ready for verification

❓ Need help? Contact Support: support@abrafleet.com
      `.trim();
      
      const customerNotification = {
        userId: roster.userId || roster.firebaseUid,
        email: roster.customerEmail,
        type: 'roster_assigned',
        title: `🚗 Trip Assigned: ${trip.tripNumber}`,
        body: notificationBody,
        data: {
          rosterId: roster._id.toString(),
          vehicleId: vehicle._id.toString(),
          driverId: driver._id.toString(),
          tripId: trip._id.toString(),
          tripNumber: trip.tripNumber,
          tripSequence: trip.tripSequence,
          tripType: rosterType,
          isGroupTrip: trip.isGroupTrip,
          totalPassengers: trip.totalPassengers,
          scheduledDate: tripDate,
          scheduledDay: tripDay,
          pickupTime: roster.startTime,
          dropTime: roster.endTime,
          estimatedPickupTime: roster.startTime,
          pickupLocation: pickupAddress,
          dropLocation: dropAddress,
          pickupCoordinates: pickupLocation?.coordinates || null,
          dropCoordinates: dropLocation?.coordinates || null,
          officeLocation: roster.officeLocation,
          vehicleReg: vehicle.registrationNumber,
          vehicleMake: vehicle.make,
          vehicleModel: vehicle.model,
          vehicleColor: vehicle.color,
          vehicleSeats: vehicle.seatingCapacity,
          driverName: driver.name,
          driverPhone: driver.phone,
          driverRating: driver.rating,
          driverPhoto: driver.profilePhoto || null,
          customerName: roster.customerName,
          customerEmail: roster.customerEmail,
          customerPhone: customerPhone,
          distance: trip.distanceData?.totalDistanceKm || null,
          duration: trip.distanceData?.totalDurationMin || null,
          pickupSequence: roster.pickupSequence || 1,
          action: 'roster_assigned',
          deepLink: `abrafleet://trip/${trip._id}`,
        },
        priority: 'high',
        category: 'roster',
        sound: 'default',
        badge: 1,
        createdAt: new Date(),
        read: false,
        expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
      };
      
      notifications.push(customerNotification);
      console.log(`   ✅ Customer: ${roster.customerName} (${roster.customerEmail})`);
      console.log(`      Phone: ${customerPhone}`);
      console.log(`      Pickup: ${pickupAddress.substring(0, 50)}...`);
      console.log(`      Time: ${roster.startTime} on ${tripDate}`);
    }
    
    // ────────────────────────────────────────────────────────────────────
    // 2. DRIVER NOTIFICATION (Comprehensive Trip & Route Information)
    // ────────────────────────────────────────────────────────────────────
    if (driver.firebaseUid || driver.userId || driver.email) {
      console.log('\n📧 Preparing DRIVER notification...');
      
      const allPassengers = trip.passengers || [{
        rosterId: roster._id,
        customerName: roster.customerName,
        customerPhone: extractPhone(roster),
        pickupLocation: roster.locations?.pickup || roster.pickupLocation,
        sequence: 1,
      }];
      
      let passengerList = '';
      allPassengers.forEach((passenger, index) => {
        const passengerPhone = passenger.customerPhone || 'No phone';
        const passengerAddress = extractAddress(passenger.pickupLocation);
        passengerList += `\n   ${passenger.sequence || (index + 1)}. ${passenger.customerName}`;
        passengerList += `\n      📞 ${passengerPhone}`;
        passengerList += `\n      📍 ${passengerAddress.substring(0, 60)}...`;
        if (passenger.estimatedPickupTime) {
          passengerList += `\n      ⏰ ETA: ${passenger.estimatedPickupTime}`;
        }
        passengerList += '\n';
      });
      
      const driverNotificationBody = `
🚗 NEW TRIP ASSIGNED - ${trip.tripNumber}

📅 SCHEDULE:
   ${tripDay}, ${tripDate}
   Start Time: ${roster.startTime || 'TBD'}
   ${roster.endTime ? `End Time: ${roster.endTime}` : ''}

🚙 VEHICLE:
   ${vehicle.registrationNumber}
   ${vehicle.make || ''} ${vehicle.model || ''}

👥 PASSENGERS (${trip.totalPassengers}):
${passengerList}

📍 OFFICE LOCATION:
   ${roster.officeLocation || 'Not specified'}

📊 TRIP SUMMARY:
   Type: ${(roster.rosterType || 'both').toUpperCase()}
   ${trip.isGroupTrip ? `🚌 Group Trip (${trip.totalPassengers} passengers)` : '📦 Individual Trip'}
   ${trip.routeData?.totalDistanceKm ? `Total Distance: ${trip.routeData.totalDistanceKm} km` : ''}
   ${trip.routeData?.totalDurationMin ? `Estimated Duration: ${trip.routeData.totalDurationMin} min` : ''}
   Sequence: Trip #${trip.tripSequence} for today

📋 INSTRUCTIONS:
   • Follow the pickup sequence shown above
   • Call each passenger 10 minutes before arrival
   • Update passenger status in app (Picked/Dropped)
   • Ensure all passengers are safely dropped
   • Contact dispatch for any issues

💡 ROUTE OPTIMIZATION:
   ${trip.isGroupTrip ? 'Route has been optimized for minimum distance' : 'Direct route to office'}

🎯 GOALS:
   ✓ Pick all passengers on time
   ✓ Drive safely and follow traffic rules
   ✓ Maintain vehicle cleanliness
   ✓ Provide excellent service
      `.trim();
      
      const driverNotification = {
        userId: driver.firebaseUid || driver.userId,
        email: driver.email,
        type: 'trip_assigned',
        title: `🚗 New Trip: ${trip.tripNumber} (${trip.totalPassengers} pax)`,
        body: driverNotificationBody,
        data: {
          tripId: trip._id.toString(),
          vehicleId: vehicle._id.toString(),
          driverId: driver._id.toString(),
          tripNumber: trip.tripNumber,
          tripSequence: trip.tripSequence,
          tripType: roster.rosterType,
          isGroupTrip: trip.isGroupTrip,
          totalPassengers: trip.totalPassengers,
          passengersWaiting: trip.passengersWaitingCount,
          passengersList: allPassengers.map(p => ({
            rosterId: p.rosterId.toString(),
            name: p.customerName,
            phone: p.customerPhone,
            pickupAddress: extractAddress(p.pickupLocation),
            dropAddress: extractAddress(p.dropLocation),
            sequence: p.sequence,
            estimatedPickupTime: p.estimatedPickupTime,
          })),
          scheduledDate: tripDate,
          scheduledDay: tripDay,
          scheduledTime: roster.startTime,
          pickupTime: roster.startTime,
          dropTime: roster.endTime,
          officeLocation: roster.officeLocation,
          officeCoordinates: roster.officeCoordinates || null,
          vehicleReg: vehicle.registrationNumber,
          vehicleMake: vehicle.make,
          vehicleModel: vehicle.model,
          totalDistance: trip.routeData?.totalDistanceKm || null,
          totalDuration: trip.routeData?.totalDurationMin || null,
          optimizedSequence: trip.routeData?.optimizedSequence || null,
          action: 'trip_assigned',
          deepLink: `abrafleet://driver/trip/${trip._id}`,
        },
        priority: 'high',
        category: 'trip',
        sound: 'default',
        badge: 1,
        createdAt: new Date(),
        read: false,
        expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      };
      
      notifications.push(driverNotification);
      console.log(`   ✅ Driver: ${driver.name} (${driver.phone})`);
      console.log(`      Passengers: ${trip.totalPassengers}`);
      console.log(`      Time: ${roster.startTime} on ${tripDate}`);
    }
    
    // ────────────────────────────────────────────────────────────────────
    // 3. SAVE TO DATABASE
    // ────────────────────────────────────────────────────────────────────
    if (notifications.length > 0) {
      console.log(`\n💾 Saving ${notifications.length} notifications...`);
      try {
        const result = await db.collection('notifications').insertMany(notifications);
        console.log(`   ✅ ${result.insertedCount} notifications saved`);
      } catch (dbError) {
        console.error(`   ❌ Database save failed:`, dbError.message);
      }
    }
    
    // ────────────────────────────────────────────────────────────────────
    // 4. SEND EMAIL NOTIFICATIONS
    // ────────────────────────────────────────────────────────────────────
    try {
      const emailService = require('../services/email_service');
      
      if (emailService.initialized) {
        console.log('\n📧 Sending emails...');
        
        if (roster.customerEmail) {
          await emailService.sendEmail({
            to: roster.customerEmail,
            subject: `Trip Assigned: ${trip.tripNumber} - ${tripDate}`,
            html: `
              <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
                <h2 style="color: #10B981;">🚗 Your Ride is Confirmed!</h2>
                <p>Dear ${roster.customerName},</p>
                <p>Your trip has been assigned. Here are the details:</p>
                
                <div style="background: #F3F4F6; padding: 20px; border-radius: 8px; margin: 20px 0;">
                  <h3 style="margin-top: 0;">Trip Details</h3>
                  <p><strong>Trip Number:</strong> ${trip.tripNumber}</p>
                  <p><strong>Date:</strong> ${tripDay}, ${tripDate}</p>
                  <p><strong>Pickup Time:</strong> ${roster.startTime}</p>
                </div>
                
                <div style="background: #DBEAFE; padding: 20px; border-radius: 8px; margin: 20px 0;">
                  <h3 style="margin-top: 0;">Driver & Vehicle</h3>
                  <p><strong>Driver:</strong> ${driver.name}</p>
                  <p><strong>Phone:</strong> ${driver.phone || 'Will be shared soon'}</p>
                  <p><strong>Vehicle:</strong> ${vehicle.registrationNumber}</p>
                </div>
                
                <p><strong>Important:</strong> Please be ready 5 minutes before pickup.</p>
                
                <p style="margin-top: 30px;">Best regards,<br><strong>Abra Fleet Team</strong></p>
              </div>
            `,
          });
          console.log(`   ✅ Customer email sent`);
        }
        
        if (driver.email) {
          await emailService.sendEmail({
            to: driver.email,
            subject: `New Trip: ${trip.tripNumber} - ${trip.totalPassengers} Passengers`,
            html: `
              <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
                <h2 style="color: #3B82F6;">🚗 New Trip Assignment</h2>
                <p>Dear ${driver.name},</p>
                <p>A new trip has been assigned:</p>
                
                <div style="background: #F3F4F6; padding: 20px; border-radius: 8px; margin: 20px 0;">
                  <p><strong>Trip:</strong> ${trip.tripNumber}</p>
                  <p><strong>Date:</strong> ${tripDay}, ${tripDate}</p>
                  <p><strong>Time:</strong> ${roster.startTime}</p>
                  <p><strong>Passengers:</strong> ${trip.totalPassengers}</p>
                </div>
                
                <p>Check the app for complete details.</p>
                
                <p style="margin-top: 30px;">Safe driving!<br><strong>Abra Fleet Dispatch</strong></p>
              </div>
            `,
          });
          console.log(`   ✅ Driver email sent`);
        }
      }
    } catch (emailError) {
      console.warn(`   ⚠️ Email failed (non-critical):`, emailError.message);
    }
    
    // ────────────────────────────────────────────────────────────────────
    // 5. WEBSOCKET BROADCAST
    // ────────────────────────────────────────────────────────────────────
    if (io) {
      console.log('\n📡 Broadcasting WebSocket events...');
      
      io.to('admin-room').emit('roster_assigned', {
        rosterId: roster._id.toString(),
        vehicleId: vehicle._id.toString(),
        driverId: driver._id.toString(),
        tripId: trip._id.toString(),
        tripNumber: trip.tripNumber,
        vehicleReg: vehicle.registrationNumber,
        driverName: driver.name,
        customerName: roster.customerName,
        totalPassengers: trip.totalPassengers,
        scheduledDate: tripDate,
        scheduledTime: roster.startTime,
        timestamp: new Date().toISOString(),
      });
      
      io.to(`driver-${driver._id}`).emit('trip_assigned', {
        tripId: trip._id.toString(),
        tripNumber: trip.tripNumber,
        totalPassengers: trip.totalPassengers,
        scheduledTime: roster.startTime,
        timestamp: new Date().toISOString(),
      });
      
      if (roster.userId || roster.firebaseUid) {
        io.to(`customer-${roster.userId || roster.firebaseUid}`).emit('roster_assigned', {
          rosterId: roster._id.toString(),
          tripId: trip._id.toString(),
          tripNumber: trip.tripNumber,
          driverName: driver.name,
          vehicleReg: vehicle.registrationNumber,
          timestamp: new Date().toISOString(),
        });
      }
      
      console.log('   ✅ WebSocket broadcasts sent');
    }
    
    console.log('\n' + '═'.repeat(80));
    console.log('✅ ALL NOTIFICATIONS SENT SUCCESSFULLY');
    console.log('═'.repeat(80) + '\n');
    
  } catch (error) {
    console.error('\n❌ NOTIFICATION ERROR:', error.message);
    console.error(error.stack);
  }
}

// ============================================================================
// HELPER: Auto-Group Similar Rosters (RELAXED GROUPING - FIXES "0 GROUPS")
// ============================================================================
function groupSimilarRosters(rosters) {
  console.log(`\n${'═'.repeat(80)}`);
  console.log(`📦 AUTO-GROUPING ${rosters.length} ROSTERS`);
  console.log(`${'═'.repeat(80)}\n`);
  
  const groups = new Map();
  
  for (const roster of rosters) {
    const emailDomain = roster.customerEmail?.split('@')[1] || 'unknown';
    const officeLocation = roster.officeLocation || 'unknown';
    const rosterType = roster.rosterType || 'both';
    
    // ✅ RELAXED TIME GROUPING - Round to nearest 30 minutes
    let startTime = roster.startTime || '00:00';
    const [hours, minutes] = startTime.split(':').map(Number);
    const roundedMinutes = Math.round(minutes / 30) * 30;
    const roundedHours = hours + Math.floor(roundedMinutes / 60);
    const finalMinutes = roundedMinutes % 60;
    startTime = `${String(roundedHours).padStart(2, '0')}:${String(finalMinutes).padStart(2, '0')}`;
    
    // ✅ SIMPLIFIED DATE - Only use date part, not timestamp
    let startDate = roster.startDate || 'unknown';
    if (startDate !== 'unknown') {
      try {
        startDate = new Date(startDate).toISOString().split('T')[0];
      } catch (e) {
        startDate = 'unknown';
      }
    }
    
    // ✅ SIMPLIFIED GROUPING - Don't use weekdays (too strict)
    const groupKey = `${emailDomain}|${officeLocation}|${rosterType}|${startTime}|${startDate}`;
    
    if (!groups.has(groupKey)) {
      groups.set(groupKey, {
        groupKey,
        emailDomain,
        officeLocation,
        rosterType,
        startTime,
        startDate,
        weekdays: [],
        rosters: [],
        rosterIds: [],
        employeeCount: 0,
      });
    }
    
    const group = groups.get(groupKey);
    group.rosters.push(roster);
    group.rosterIds.push(roster._id.toString());
    group.employeeCount++;
  }
  
  const groupsArray = Array.from(groups.values()).sort((a, b) => b.employeeCount - a.employeeCount);
  
  console.log(`✅ Created ${groupsArray.length} potential groups:`);
  groupsArray.forEach((group, index) => {
    console.log(`   ${index + 1}. ${group.emailDomain} | ${group.officeLocation} | ${group.startTime} (${group.employeeCount} rosters)`);
  });
  console.log('');
  
  return groupsArray;
}

// ============================================================================
// ENDPOINT 1: GET PENDING ROSTERS
// ============================================================================

router.get('/pending-rosters', async (req, res) => {
  console.log('\n' + '═'.repeat(80));
  console.log('📋 GET PENDING ROSTERS REQUEST');
  console.log('═'.repeat(80));
  
  try {
    const db = req.db;
    const userId = req.user.email;
    
    const adminUser = await db.collection('users').findOne({ firebaseUid: userId });
    if (!adminUser) {
      return res.status(404).json({
        success: false,
        message: 'Admin user not found',
      });
    }
    
    const adminOrg = getAdminOrganization(adminUser.email);
    console.log(`\n🔒 Admin organization: ${adminOrg}`);
    
    console.log('\n📊 Querying pending rosters...');
    
    const pendingRosters = await db.collection('rosters').find({
      status: { $in: ['pending_assignment', 'pending', 'created'] },
      $and: [
        {
          $or: [
            { assignedVehicleId: { $exists: false } },
            { assignedVehicleId: null },
          ]
        },
        {
          $or: [
            { assignedDriverId: { $exists: false } },
            { assignedDriverId: null },
          ]
        },
      ]
    }).sort({ priority: -1, createdAt: 1 }).toArray();
    
    console.log(`   Found ${pendingRosters.length} pending rosters`);
    
    const filteredRosters = pendingRosters.filter(roster => {
      const customerEmail = roster.customerEmail || '';
      const customerDomain = customerEmail.split('@')[1]?.toLowerCase();
      return adminOrg === 'abrafleet.com' || customerDomain === adminOrg;
    });
    
    console.log(`   Filtered to ${filteredRosters.length} rosters`);
    
    const groups = groupSimilarRosters(filteredRosters);
    
    const groupedRosters = groups.filter(g => g.employeeCount > 1);
    const individualRosterIds = new Set(
      groups.filter(g => g.employeeCount === 1).flatMap(g => g.rosterIds)
    );
    
    const individualRosters = filteredRosters.filter(r => 
      individualRosterIds.has(r._id.toString())
    );
    
    console.log(`\n✅ Returning: ${groupedRosters.length} groups, ${individualRosters.length} individuals\n`);
    
    res.json({
      success: true,
      data: {
        groups: groupedRosters,
        individuals: individualRosters,
        totalPending: filteredRosters.length,
        totalGroups: groupedRosters.length,
        totalIndividuals: individualRosters.length,
      },
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    console.error('\n❌ Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch pending rosters',
      error: error.message,
    });
  }
});

// ============================================================================
// ENDPOINT 2: FIND MATCHING VEHICLES
// ============================================================================

router.post('/find-matches', async (req, res) => {
  console.log('\n' + '═'.repeat(80));
  console.log('🔍 FIND MATCHES REQUEST');
  console.log('═'.repeat(80));
  
  try {
    const db = req.db;
    const { rosterIds, rosterId } = req.body;
    
    if (!rosterIds && !rosterId) {
      return res.status(400).json({
        success: false,
        message: 'rosterIds or rosterId is required',
      });
    }
    
    const idsToMatch = rosterIds || [rosterId];
    
    const rosters = await db.collection('rosters').find({
      _id: { $in: idsToMatch.map(id => new ObjectId(id)) }
    }).toArray();
    
    if (rosters.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'No rosters found',
      });
    }
    
    const matches = await findBestMatches(rosters, db);
    
    res.json({
      success: true,
      data: {
        bestMatch: matches.bestMatch,
        alternatives: matches.alternatives,
        allOptions: matches.allOptions,
        rejected: matches.rejected,
        stats: {
          totalChecked: matches.totalChecked,
          compatible: matches.compatibleCount,
          rejected: matches.rejected?.length || 0,
        }
      },
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    console.error('\n❌ Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to find matches',
      error: error.message,
    });
  }
});

// ============================================================================
// ENDPOINT 3: ASSIGN SINGLE ROSTER + CREATE TRIP
// ============================================================================

router.post('/assign', async (req, res) => {
  console.log('\n' + '═'.repeat(80));
  console.log('✅ ASSIGN ROSTER REQUEST');
  console.log('═'.repeat(80));
  
  const db = req.db;
  const io = getIO();
  const userId = req.user.email;
  
  let vehicleLock = null;
  let rosterLock = null;
  
  try {
    const { rosterId, vehicleId } = req.body;
    
    if (!rosterId || !vehicleId) {
      return res.status(400).json({
        success: false,
        message: 'rosterId and vehicleId are required',
      });
    }
    
    console.log(`\n📋 Roster: ${rosterId}`);
    console.log(`🚗 Vehicle: ${vehicleId}\n`);
    
    // Acquire locks
    vehicleLock = await acquireLock('vehicle', vehicleId, userId, 30);
    if (!vehicleLock.success) {
      return res.status(409).json({
        success: false,
        message: vehicleLock.message,
        error: 'VEHICLE_LOCKED',
      });
    }
    
    rosterLock = await acquireLock('roster', rosterId, userId, 30);
    if (!rosterLock.success) {
      await releaseLock(vehicleLock.lockId, userId);
      return res.status(409).json({
        success: false,
        message: rosterLock.message,
        error: 'ROSTER_LOCKED',
      });
    }
    
    console.log('✅ Locks acquired\n');
    
    // Fetch data
    const roster = await db.collection('rosters').findOne({ _id: new ObjectId(rosterId) });
    if (!roster) throw new Error('Roster not found');
    
    if (roster.assignedVehicleId || roster.assignedDriverId) {
      throw new Error('Roster already assigned');
    }
    
    const vehicle = await db.collection('vehicles').findOne({ _id: new ObjectId(vehicleId) });
    if (!vehicle) throw new Error('Vehicle not found');
    
    const driverId = vehicle.assignedDriver || vehicle.driverId;
    if (!driverId) throw new Error('Vehicle has no driver');
    
    const driver = await db.collection('drivers').findOne({driverId: String(driverId)});
    if (!driver) throw new Error('Driver not found');
    
    console.log(`✅ Data validated\n`);
    
    // Calculate distances
    const distanceData = await calculateRosterDistances(vehicle, roster);
    
    // Create trip
    const now = new Date();
    const today = now.toISOString().split('T')[0];
    
    const tripNumber = await generateTripNumber(db, today);
    const tripSequence = await getVehicleTripSequence(db, vehicleId, today);
    
    let tripType = 'login';
    if (roster.rosterType === 'logout' || roster.rosterType === 'drop') {
      tripType = 'logout';
    }
    
    let pickupLocation, dropLocation;
    if (tripType === 'login') {
      pickupLocation = roster.locations?.pickup || {};
      dropLocation = roster.locations?.drop || {};
    } else {
      pickupLocation = roster.locations?.drop || {};
      dropLocation = roster.locations?.pickup || {};
    }
    
    const newTrip = {
      tripNumber,
      tripSequence,
      tripType: tripType,
      vehicleId: vehicle._id,
      vehicleReg: vehicle.registrationNumber,
      driverId: driver._id,
      driverName: driver.name,
      driverPhone: driver.phone,
      scheduledDate: today,
      scheduledTime: roster.startTime,
      pickupTime: roster.startTime,
      dropoffTime: roster.endTime,
      rosterType: roster.rosterType || 'both',
      officeLocation: roster.officeLocation,
      company: roster.employeeDetails?.companyName || 'N/A',
      passengers: [{
        rosterId: roster._id,
        passengerId: roster.userId,
        customerName: roster.customerName,
        customerEmail: roster.customerEmail,
        customerPhone: extractPhone(roster),
        pickupLocation: pickupLocation,
        dropLocation: dropLocation,
        estimatedPickupTime: roster.startTime,
        sequence: 1,
        status: 'waiting',
        pickupTime: null,
        dropTime: null,
      }],
      totalPassengers: 1,
      passengersPickedCount: 0,
      passengersWaitingCount: 1,
      passengersDroppedCount: 0,
      distance: distanceData.totalDistanceKm || 0,
      actualDistance: null,
      distanceData: distanceData.error ? null : distanceData,
      status: 'assigned',
      isGroupTrip: false,
      createdAt: now,
      createdBy: userId,
      updatedAt: now,
    };
    
    const tripResult = await db.collection('trips').insertOne(newTrip);
    const tripId = tripResult.insertedId;
    
    console.log(`✅ Trip created: ${tripNumber}\n`);
    
    // Update roster
    await db.collection('rosters').updateOne(
      { _id: new ObjectId(rosterId) },
      {
        $set: {
          assignedVehicleId: vehicle._id,
          assignedVehicleReg: vehicle.registrationNumber,
          assignedDriverId: driver._id,
          assignedDriverName: driver.name,
          assignedDriverPhone: driver.phone,
          tripId: tripId,
          tripNumber: tripNumber,
          tripSequence: tripSequence,
          status: 'assigned',
          assignedAt: now,
          assignedBy: userId,
          distanceData: distanceData.error ? null : distanceData,
          updatedAt: now,
        }
      }
    );
    
    // Update vehicle
    const assignedCustomers = vehicle.assignedCustomers || [];
    assignedCustomers.push(roster._id);
    
    await db.collection('vehicles').updateOne(
      { _id: new ObjectId(vehicleId) },
      {
        $set: {
          assignedCustomers,
          updatedAt: now,
        }
      }
    );
    
    // Cache in Redis
    const redis = getRedisClient();
    if (redis) {
      try {
        await redis.setex(
          `vehicle:${vehicleId}:trip:${tripSequence}`,
          86400,
          JSON.stringify({
            tripId: tripId.toString(),
            tripNumber,
            status: 'assigned',
            passengers: 1,
          })
        );
        
        await redis.hset(
          `trip:${tripId}:stats`,
          'pickedCount', '0',
          'waitingCount', '1',
          'droppedCount', '0'
        );
      } catch (e) {
        console.warn('Redis cache failed');
      }
    }
    
    // Send notifications
    await sendAssignmentNotifications(db, roster, vehicle, driver, { _id: tripId, ...newTrip }, io);
    
    console.log('✅ ASSIGNMENT COMPLETE\n');
    
    res.json({
      success: true,
      message: 'Roster assigned successfully',
      data: {
        rosterId: roster._id.toString(),
        vehicleId: vehicle._id.toString(),
        driverId: driver._id.toString(),
        tripId: tripId.toString(),
        tripNumber,
        tripSequence,
        vehicleReg: vehicle.registrationNumber,
        driverName: driver.name,
        customerName: roster.customerName,
        distanceData,
        assignedAt: now,
      },
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    console.error('\n❌ ERROR:', error.message);
    console.error(error.stack);
    
    res.status(500).json({
      success: false,
      message: 'Failed to assign roster',
      error: error.message,
    });
    
  } finally {
    if (vehicleLock?.lockId) {
      await releaseLock(vehicleLock.lockId, userId);
    }
    
    if (rosterLock?.lockId) {
      await releaseLock(rosterLock.lockId, userId);
    }
    
    console.log('═'.repeat(80) + '\n');
  }
});

// ============================================================================
// ENDPOINT 4: ASSIGN GROUP + CREATE TRIP
// ============================================================================

router.post('/assign-group', async (req, res) => {
  console.log('\n' + '═'.repeat(80));
  console.log('✅ ASSIGN GROUP REQUEST');
  console.log('═'.repeat(80));
  
  const db = req.db;
  const io = getIO();
  const userId = req.user?.uid || 'system';
  
  try {
    const { rosterIds, vehicleId } = req.body;
    
    // ────────────────────────────────────────────────────────────────────
    // STEP 1: VALIDATE INPUT
    // ────────────────────────────────────────────────────────────────────
    console.log('\n📝 STEP 1: Validating input...');
    
    if (!rosterIds || !Array.isArray(rosterIds) || rosterIds.length === 0) {
      console.log('❌ Invalid rosterIds');
      return res.status(400).json({
        success: false,
        message: 'rosterIds array is required and must not be empty',
      });
    }
    
    if (!vehicleId) {
      console.log('❌ Missing vehicleId');
      return res.status(400).json({
        success: false,
        message: 'vehicleId is required',
      });
    }
    
    console.log(`   ✅ Rosters: ${rosterIds.length}`);
    console.log(`   ✅ Vehicle: ${vehicleId}`);
    
    // ────────────────────────────────────────────────────────────────────
    // STEP 2: FETCH ROSTERS
    // ────────────────────────────────────────────────────────────────────
    console.log('\n📊 STEP 2: Fetching rosters...');
    
    const rosters = await db.collection('rosters').find({
      _id: { $in: rosterIds.map(id => new ObjectId(id)) }
    }).toArray();
    
    console.log(`   ✅ Found ${rosters.length} rosters`);
    
    if (rosters.length === 0) {
      return res.status(404).json({
        success: false,
        message: 'No rosters found with provided IDs',
      });
    }
    
    // ────────────────────────────────────────────────────────────────────
    // STEP 3: FETCH VEHICLE
    // ────────────────────────────────────────────────────────────────────
    console.log('\n🚗 STEP 3: Fetching vehicle...');
    
    const vehicle = await db.collection('vehicles').findOne({ 
      _id: new ObjectId(vehicleId) 
    });
    
    if (!vehicle) {
      console.log('❌ Vehicle not found');
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found',
      });
    }
    
    console.log(`   ✅ Vehicle: ${vehicle.registrationNumber}`);
    console.log(`   📍 Location:`, vehicle.currentLocation?.coordinates);
    
    // ────────────────────────────────────────────────────────────────────
    // STEP 4: FETCH DRIVER (FIXED FOR STRING 'DRV-100001')
    // ────────────────────────────────────────────────────────────────────
    console.log('\n👨‍✈️ STEP 4: Fetching driver...');
    
    // ✅ Extract driver code (it's a STRING like 'DRV-100001')
    const driverCode = vehicle.assignedDriver || vehicle.driverId;
    
    if (!driverCode) {
      console.log('❌ Vehicle has no driver assigned');
      return res.status(400).json({
        success: false,
        message: 'Vehicle has no assigned driver',
        vehicleReg: vehicle.registrationNumber,
      });
    }
    
    console.log(`   🔍 Driver code: "${driverCode}" (type: ${typeof driverCode})`);
    
    // ✅ Search by driverId field (matches driver.driverId = 'DRV-100001')
    const driver = await db.collection('drivers').findOne({ 
      driverId: String(driverCode)  // Force to string to avoid [object Object]
    });
    
    if (!driver) {
      console.log('❌ Driver not found in database');
      
      // Debug: Show available drivers
      const allDrivers = await db.collection('drivers').find({}).limit(5).toArray();
      console.log('\n📊 Available drivers in DB:');
      allDrivers.forEach(d => {
        console.log(`   - ${d.name}: driverId="${d.driverId}"`);
      });
      
      return res.status(404).json({
        success: false,
        message: `Driver with code "${driverCode}" not found`,
        debug: {
          searchedFor: String(driverCode),
          vehicleReg: vehicle.registrationNumber,
          availableDrivers: allDrivers.map(d => ({
            name: d.name,
            driverId: d.driverId
          }))
        }
      });
    }
    
    console.log(`   ✅ Driver found: ${driver.name}`);
    console.log(`   📞 Phone: ${driver.phone || driver.personalInfo?.phone || 'N/A'}`);
    
    // ────────────────────────────────────────────────────────────────────
    // STEP 5: CALCULATE TRIP DISTANCE (PICKUP → DROP FOR EACH ROSTER)
    // ────────────────────────────────────────────────────────────────────
    console.log('\n📏 STEP 5: Calculating trip distance...');
    
    let totalDistanceKm = 0;
    const passengerDistances = [];
    
    // Haversine formula
    function calculateDistance(lat1, lon1, lat2, lon2) {
      const R = 6371; // Earth radius in km
      const dLat = (lat2 - lat1) * Math.PI / 180;
      const dLon = (lon2 - lon1) * Math.PI / 180;
      const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2);
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
      return R * c;
    }
    
    for (const roster of rosters) {
      const pickupLat = roster.locations?.pickup?.coordinates?.latitude;
      const pickupLon = roster.locations?.pickup?.coordinates?.longitude;
      const dropLat = roster.locations?.drop?.coordinates?.latitude;
      const dropLon = roster.locations?.drop?.coordinates?.longitude;
      
      if (pickupLat && pickupLon && dropLat && dropLon) {
        const distance = calculateDistance(pickupLat, pickupLon, dropLat, dropLon);
        totalDistanceKm += distance;
        passengerDistances.push({
          customerName: roster.customerName,
          distance: distance.toFixed(2)
        });
        console.log(`   📍 ${roster.customerName}: ${distance.toFixed(2)} km (pickup → drop)`);
      } else {
        console.log(`   ⚠️ ${roster.customerName}: Missing coordinates`);
      }
    }
    
    console.log(`   ✅ Total trip distance: ${totalDistanceKm.toFixed(2)} km`);
    
    // ────────────────────────────────────────────────────────────────────
    // STEP 6: CREATE TRIP
    // ────────────────────────────────────────────────────────────────────
    console.log('\n🚗 STEP 6: Creating trip...');
    
    const now = new Date();
    const today = now.toISOString().split('T')[0];
    
    const randomNum = Math.floor(Math.random() * 9999) + 1;
    const tripNumber = `TRIP-${today}-${String(randomNum).padStart(4, '0')}`;
    const tripSequence = 1;
    
    console.log(`   Trip Number: ${tripNumber}`);
    
    // Build passengers array
    const passengers = rosters.map((roster, index) => {
      const customerPhone = roster.customerPhone || 
                           roster.personalInfo?.phone || 
                           roster.phone ||
                           'Not provided';
      
      return {
        rosterId: roster._id,
        passengerId: roster.userId || roster.firebaseUid,
        customerName: roster.customerName || 'Unknown',
        customerEmail: roster.customerEmail || '',
        customerPhone: customerPhone,
        pickupLocation: roster.locations?.pickup || {},
        dropLocation: roster.locations?.drop || {},
        estimatedPickupTime: roster.startTime || '09:00',
        sequence: index + 1,
        status: 'waiting',
        pickupTime: null,
        dropTime: null,
      };
    });
    
    // Create trip document
    const newTrip = {
      tripNumber,
      tripSequence,
      tripType: 'login',
      vehicleId: vehicle._id,
      vehicleReg: vehicle.registrationNumber,
      driverId: driver._id,
      driverName: driver.name,
      driverPhone: driver.phone || driver.personalInfo?.phone || 'Not provided',
      scheduledDate: today,
      scheduledTime: rosters[0].startTime || rosters[0].loginTime || '09:00',
      pickupTime: rosters[0].startTime || rosters[0].loginTime || '09:00',
      dropoffTime: rosters[0].endTime || rosters[0].logoutTime || '18:00',
      rosterType: rosters[0].rosterType || 'both',
      officeLocation: rosters[0].officeLocation || 'Office',
      company: rosters[0].organization || rosters[0].employeeDetails?.companyName || 'N/A',
      passengers,
      totalPassengers: rosters.length,
      passengersPickedCount: 0,
      passengersWaitingCount: rosters.length,
      passengersDroppedCount: 0,
      distance: totalDistanceKm,
      actualDistance: null,
      distanceBreakdown: passengerDistances,
      status: 'assigned',
      isGroupTrip: true,
      createdAt: now,
      createdBy: userId,
      updatedAt: now,
    };
    
    const tripResult = await db.collection('trips').insertOne(newTrip);
    const tripId = tripResult.insertedId;
    
    console.log(`   ✅ Trip created: ${tripNumber}`);
    console.log(`   ✅ Trip ID: ${tripId}`);
    
    // ────────────────────────────────────────────────────────────────────
    // STEP 7: UPDATE ROSTERS
    // ────────────────────────────────────────────────────────────────────
    console.log('\n💾 STEP 7: Updating rosters...');
    
    for (let i = 0; i < rosters.length; i++) {
      const roster = rosters[i];
      
      await db.collection('rosters').updateOne(
        { _id: roster._id },
        {
          $set: {
            assignedVehicleId: vehicle._id,
            assignedVehicleReg: vehicle.registrationNumber,
            assignedDriverId: driver._id,
            assignedDriverName: driver.name,
            assignedDriverPhone: driver.phone || driver.personalInfo?.phone,
            tripId: tripId,
            tripNumber: tripNumber,
            tripSequence: tripSequence,
            status: 'assigned',
            assignedAt: now,
            assignedBy: userId,
            pickupSequence: i + 1,
            groupAssignment: true,
            totalGroupSize: rosters.length,
            updatedAt: now,
          }
        }
      );
      
      console.log(`   ✅ ${i + 1}. ${roster.customerName} updated`);
    }
    
    // ────────────────────────────────────────────────────────────────────
    // STEP 8: UPDATE VEHICLE
    // ────────────────────────────────────────────────────────────────────
    console.log('\n🚙 STEP 8: Updating vehicle...');
    
    const assignedCustomers = vehicle.assignedCustomers || [];
    assignedCustomers.push(...rosters.map(r => r._id));
    
    await db.collection('vehicles').updateOne(
      { _id: vehicle._id },
      {
        $set: {
          assignedCustomers,
          updatedAt: now,
        }
      }
    );
    
    console.log(`   ✅ Vehicle updated`);
    
    // ────────────────────────────────────────────────────────────────────
    // STEP 9: SEND NOTIFICATIONS
    // ────────────────────────────────────────────────────────────────────
    console.log('\n📧 STEP 9: Sending notifications...');
    
    try {
      for (const roster of rosters) {
        try {
          await sendAssignmentNotifications(db, roster, vehicle, driver, { _id: tripId, ...newTrip }, io);
        } catch (notifError) {
          console.warn(`   ⚠️ Notification failed for ${roster.customerName}:`, notifError.message);
        }
      }
      console.log(`   ✅ Notifications sent`);
    } catch (error) {
      console.warn(`   ⚠️ Notifications failed (non-critical):`, error.message);
    }
    
    // ────────────────────────────────────────────────────────────────────
    // SUCCESS RESPONSE
    // ────────────────────────────────────────────────────────────────────
    console.log('\n✅ GROUP ASSIGNMENT COMPLETE');
    console.log('═'.repeat(80) + '\n');
    
    return res.json({
      success: true,
      message: `Successfully assigned ${rosters.length} rosters to ${vehicle.registrationNumber}`,
      data: {
        tripId: tripId.toString(),
        tripNumber,
        tripSequence,
        vehicleId: vehicle._id.toString(),
        vehicleReg: vehicle.registrationNumber,
        driverId: driver._id.toString(),
        driverName: driver.name,
        driverPhone: driver.phone || driver.personalInfo?.phone,
        totalPassengers: rosters.length,
        totalDistance: totalDistanceKm.toFixed(2),
        distanceBreakdown: passengerDistances,
        assignments: rosters.map((r, i) => ({
          rosterId: r._id.toString(),
          customerName: r.customerName,
          sequence: i + 1,
        })),
        assignedAt: now,
      },
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    console.error('\n❌ UNEXPECTED ERROR:', error.message);
    console.error('Stack:', error.stack);
    
    return res.status(500).json({
      success: false,
      message: 'Unexpected error during group assignment',
      error: error.message,
      stack: process.env.NODE_ENV === 'development' ? error.stack : undefined,
    });
  }
});



// ============================================================================
// ENDPOINT 5: GET AVAILABLE VEHICLES
// ============================================================================

router.get('/available-vehicles', async (req, res) => {
  console.log('\n' + '═'.repeat(80));
  console.log('🚗 GET AVAILABLE VEHICLES');
  console.log('═'.repeat(80));
  
  try {
    const db = req.db;
    const redis = getRedisClient();
    
    const vehicles = await db.collection('vehicles').find({
      status: { $in: ['idle', 'active'] }
    }).toArray();
    
    const enhancedVehicles = await Promise.all(vehicles.map(async (vehicle) => {
      const vehicleId = vehicle._id.toString();
      
      let liveLocation = null;
      if (redis) {
        try {
          const locationData = await redis.get(`vehicle:${vehicleId}:location`);
          if (locationData) {
            liveLocation = JSON.parse(locationData);
          }
        } catch (e) {}
      }
      
      let currentTrip = null;
      let isAvailable = true;
      
      if (redis) {
        try {
          const tripData = await redis.get(`vehicle:${vehicleId}:current_trip`);
          if (tripData) {
            currentTrip = JSON.parse(tripData);
            isAvailable = currentTrip.status !== 'in-progress';
          }
        } catch (e) {}
      }
      
      let driver = null;
      if (vehicle.assignedDriver || vehicle.driverId) {
        driver = await db.collection('drivers').findOne({
          _id: vehicle.assignedDriver || vehicle.driverId
        });
      }
      
      const totalSeats = vehicle.seatingCapacity || 4;
      const assignedSeats = (vehicle.assignedCustomers || []).length;
      const availableSeats = totalSeats - 1 - assignedSeats;
      
      return {
        vehicleId: vehicle._id.toString(),
        registrationNumber: vehicle.registrationNumber,
        make: vehicle.make,
        model: vehicle.model,
        totalSeats,
        assignedSeats,
        availableSeats,
        hasDriver: !!driver,
        driver: driver ? {
          driverId: driver._id.toString(),
          name: driver.name,
          phone: driver.phone,
          rating: driver.rating || 4.0,
        } : null,
        isAvailable,
        currentStatus: currentTrip ? 'on_trip' : 'idle',
        liveLocation: liveLocation || vehicle.lastKnownLocation,
        currentTrip: currentTrip ? {
          tripId: currentTrip.tripId,
          status: currentTrip.status,
        } : null,
        fuelLevel: vehicle.fuelLevel || 100,
        lastUpdated: liveLocation?.timestamp || vehicle.updatedAt,
      };
    }));
    
    const available = enhancedVehicles.filter(v => 
      v.isAvailable && v.hasDriver && v.availableSeats > 0
    );
    
    console.log(`✅ ${available.length} vehicles available\n`);
    
    res.json({
      success: true,
      data: {
        available,
        all: enhancedVehicles,
        stats: {
          total: vehicles.length,
          available: available.length,
          onTrip: enhancedVehicles.filter(v => v.currentStatus === 'on_trip').length,
          noDriver: enhancedVehicles.filter(v => !v.hasDriver).length,
          noSeats: enhancedVehicles.filter(v => v.availableSeats <= 0).length,
        }
      },
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    console.error('\n❌ Error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch available vehicles',
      error: error.message,
    });
  }
});

// ============================================================================
// ENDPOINT 6: UNASSIGN ROSTER
// ============================================================================

router.post('/unassign', async (req, res) => {
  console.log('\n' + '═'.repeat(80));
  console.log('❌ UNASSIGN ROSTER');
  console.log('═'.repeat(80));
  
  const db = req.db;
  const io = getIO();
  const userId = req.user.email;
  
  let rosterLock = null;
  
  try {
    const { rosterId, reason } = req.body;
    
    if (!rosterId) {
      return res.status(400).json({
        success: false,
        message: 'rosterId is required',
      });
    }
    
    rosterLock = await acquireLock('roster', rosterId, userId, 30);
    if (!rosterLock.success) {
      return res.status(409).json({
        success: false,
        message: rosterLock.message,
      });
    }
    
    const roster = await db.collection('rosters').findOne({ _id: new ObjectId(rosterId) });
    if (!roster) {
      throw new Error('Roster not found');
    }
    
    if (!roster.assignedVehicleId) {
      throw new Error('Roster not assigned');
    }
    
    const vehicleId = roster.assignedVehicleId;
    const tripId = roster.tripId;
    
    if (tripId) {
      const trip = await db.collection('trips').findOne({ _id: tripId });
      
      if (trip) {
        const updatedPassengers = trip.passengers.filter(
          p => p.rosterId.toString() !== rosterId
        );
        
        if (updatedPassengers.length === 0) {
          await db.collection('trips').deleteOne({ _id: tripId });
          
          const redis = getRedisClient();
          if (redis) {
            await redis.del(`vehicle:${vehicleId}:trip:${trip.tripSequence}`);
            await redis.del(`trip:${tripId}:stats`);
          }
        } else {
          await db.collection('trips').updateOne(
            { _id: tripId },
            {
              $set: {
                passengers: updatedPassengers,
                totalPassengers: updatedPassengers.length,
                passengersWaitingCount: updatedPassengers.filter(p => p.status === 'waiting').length,
                updatedAt: new Date(),
              }
            }
          );
        }
      }
    }
    
    await db.collection('rosters').updateOne(
      { _id: new ObjectId(rosterId) },
      {
        $set: {
          status: 'pending_assignment',
          updatedAt: new Date(),
        },
        $unset: {
          assignedVehicleId: '',
          assignedVehicleReg: '',
          assignedDriverId: '',
          assignedDriverName: '',
          assignedDriverPhone: '',
          assignedAt: '',
          assignedBy: '',
          tripId: '',
          tripNumber: '',
          tripSequence: '',
        },
      }
    );
    
    await db.collection('vehicles').updateOne(
      { _id: vehicleId },
      {
        $pull: { assignedCustomers: roster._id },
        $set: { updatedAt: new Date() }
      }
    );
    
    if (io) {
      io.to('admin-room').emit('roster_unassigned', {
        rosterId: roster._id.toString(),
        vehicleId: vehicleId.toString(),
        timestamp: new Date().toISOString(),
      });
    }
    
    console.log('✅ Roster unassigned\n');
    
    res.json({
      success: true,
      message: 'Roster unassigned successfully',
      data: {
        rosterId: roster._id.toString(),
        status: 'pending_assignment',
        tripRemoved: !!tripId,
      },
      timestamp: new Date().toISOString(),
    });
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    res.status(500).json({
      success: false,
      message: 'Failed to unassign roster',
      error: error.message,
    });
  } finally {
    if (rosterLock?.lockId) {
      await releaseLock(rosterLock.lockId, userId);
    }
    console.log('═'.repeat(80) + '\n');
  }
});


// ============================================================================
// EXPORT ROUTER
// ============================================================================
module.exports = router;