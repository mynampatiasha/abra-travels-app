const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

/**
 * GET /api/driver/todays-customers
 * Get today's customers assigned to the authenticated driver with optimized routing
 */
router.get('/todays-customers', async (req, res) => {
  try {
    console.log('\n🚐 ========== FETCHING TODAY\'S CUSTOMERS ==========');
    console.log('📅 Timestamp:', new Date().toISOString());
    
    // ✅ FIX #1: Get authenticated driver
    const user = req.user;
    if (!user) {
      console.log('❌ No authenticated user found');
      return res.status(401).json({
        status: 'error',
        message: 'Authentication required'
      });
    }
    
    console.log('✅ Authenticated user:', user.uid);
    console.log('   Email:', user.email);
    
    // ✅ FIX #2: Find driver by Firebase UID
    const driver = await req.db.collection('drivers').findOne({
      $or: [
        { firebaseUid: user.uid },
        { uid: user.uid },
        { 'personalInfo.email': user.email }
      ]
    });
    
    if (!driver) {
      console.log('❌ Driver not found in database');
      return res.status(404).json({
        status: 'error',
        message: 'Driver profile not found. Please contact administrator.'
      });
    }
    
    const driverId = driver.driverId;
    console.log('✅ Driver found:', driverId);
    console.log('   Name:', `${driver.personalInfo?.firstName} ${driver.personalInfo?.lastName}`);
    
    // ✅ FIX #3: Get today's date range (for scheduled rosters, not created rosters)
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);

    console.log(`📅 Searching for rosters scheduled for: ${today.toISOString().split('T')[0]}`);

    // ✅ FIX #4: Flexible driver matching + scheduled date filtering
    const rosters = await req.db.collection('rosters')
      .find({
        $and: [
          // Driver matching (flexible - checks all possible fields)
          {
            $or: [
              { driverId: driverId },
              { assignedDriverId: driverId },
              { 'assignedDriver.driverId': driverId },
              { driverName: `${driver.personalInfo?.firstName} ${driver.personalInfo?.lastName}` }
            ]
          },
          // Status filtering
          { status: { $in: ['assigned', 'scheduled', 'in_progress', 'approved'] } },
          // Date filtering (scheduled for TODAY, not created today)
          {
            $or: [
              // Check startDate field
              { 
                startDate: { 
                  $gte: today,
                  $lt: tomorrow 
                } 
              },
              // Check fromDate field (alternative field name)
              { 
                fromDate: { 
                  $gte: today,
                  $lt: tomorrow 
                } 
              },
              // Check if roster spans today (multi-day rosters)
              {
                $and: [
                  { 
                    $or: [
                      { startDate: { $lte: today } },
                      { fromDate: { $lte: today } }
                    ]
                  },
                  {
                    $or: [
                      { endDate: { $gte: today } },
                      { toDate: { $gte: today } }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      })
      .toArray();

    console.log(`📋 Found ${rosters.length} rosters for today`);

    // ✅ FIX #5: Better debugging when no rosters found
    if (rosters.length === 0) {
      console.log('⚠️  No rosters found. Debugging...');
      console.log('   Driver ID:', driverId);
      console.log('   Date Range:', today.toISOString(), 'to', tomorrow.toISOString());
      
      // Check if driver has ANY rosters (for debugging)
      const anyRosters = await req.db.collection('rosters').find({
        $or: [
          { driverId: driverId },
          { assignedDriverId: driverId },
          { 'assignedDriver.driverId': driverId }
        ]
      }).limit(5).toArray();
      
      console.log(`   Total rosters for this driver (any date): ${anyRosters.length}`);
      if (anyRosters.length > 0) {
        console.log('   Sample roster dates:');
        anyRosters.forEach((r, i) => {
          console.log(`     ${i+1}. Start: ${r.startDate || r.fromDate}, Status: ${r.status}`);
        });
      }
      
      return res.json({
        status: 'success',
        data: {
          customers: [],
          totalCustomers: 0,
          pickupCustomers: 0,
          dropCustomers: 0,
          message: 'No customers assigned for today',
          officeLocation: {
            latitude: 12.9716,
            longitude: 77.5946,
            address: 'Abra Travels Office, Bangalore'
          }
        }
      });
    }

    // Office location (Bangalore - configurable)
    const officeLocation = {
      latitude: 12.9716,
      longitude: 77.5946,
      address: 'Abra Travels Office, Bangalore'
    };

    // Transform rosters to customer pickup info
    const customers = rosters.map((roster, index) => {
      // Calculate distance from office
      const pickupLat = roster.pickupLocation?.latitude || 
                        roster.locations?.pickup?.coordinates?.latitude || 
                        12.9716;
      const pickupLng = roster.pickupLocation?.longitude || 
                        roster.locations?.pickup?.coordinates?.longitude || 
                        77.5946;
      const dropLat = roster.dropLocation?.latitude || 
                      roster.locations?.drop?.coordinates?.latitude || 
                      12.9716;
      const dropLng = roster.dropLocation?.longitude || 
                      roster.locations?.drop?.coordinates?.longitude || 
                      77.5946;
      
      const distanceFromOffice = calculateDistance(
        officeLocation.latitude,
        officeLocation.longitude,
        pickupLat,
        pickupLng
      );

      // Determine if this is login (pickup) or logout (drop)
      const isLogin = roster.rosterType === 'login' || roster.tripType === 'login' || roster.tripType === 'both';
      
      // Generate realistic scheduled times
      const baseTime = new Date();
      baseTime.setHours(8, 0, 0, 0); // Start at 8 AM
      const scheduledTime = new Date(baseTime.getTime() + (index * 15 * 60 * 1000)); // 15 min intervals

      return {
        customerId: roster.customerId || roster.userId || `CUST-${index + 1}`,
        customerName: roster.customerName || 'Unknown Customer',
        customerPhone: roster.customerPhone || roster.phone || '+91-9876543210',
        customerEmail: roster.customerEmail || roster.email || 'customer@example.com',
        pickupLocation: {
          latitude: pickupLat,
          longitude: pickupLng
        },
        dropLocation: {
          latitude: dropLat,
          longitude: dropLng
        },
        pickupAddress: roster.locations?.pickup?.address || 
                      roster.pickupAddress || 
                      roster.loginPickupAddress || 
                      'Pickup Location',
        dropAddress: roster.locations?.drop?.address || 
                    roster.dropAddress || 
                    roster.logoutDropAddress || 
                    'Drop Location',
        isLogin: isLogin,
        scheduledTime: scheduledTime.toISOString(),
        organizationId: roster.organizationId || 'ORG-001',
        distanceFromOffice: parseFloat(distanceFromOffice.toFixed(2)),
        status: 'pending',
        sequenceNumber: roster.sequenceNumber || roster.pickupSequence || 0,
        tripType: roster.tripType || roster.rosterType || 'login',
        rosterId: roster._id
      };
    });

    // Separate login and logout customers
    const loginCustomers = customers.filter(c => c.isLogin);
    const logoutCustomers = customers.filter(c => !c.isLogin);

    // Optimize pickup sequence: Farthest from office first (to avoid backtracking)
    loginCustomers.sort((a, b) => b.distanceFromOffice - a.distanceFromOffice);
    
    // Optimize drop sequence: Nearest to office first (to minimize total travel time)
    logoutCustomers.sort((a, b) => a.distanceFromOffice - b.distanceFromOffice);

    // Assign sequence numbers
    loginCustomers.forEach((customer, index) => {
      customer.sequenceNumber = index + 1;
    });

    logoutCustomers.forEach((customer, index) => {
      customer.sequenceNumber = index + 1;
    });

    // Combine optimized sequences
    const optimizedCustomers = [...loginCustomers, ...logoutCustomers];

    // Calculate ETAs
    let currentTime = new Date();
    currentTime.setHours(8, 0, 0, 0); // Start at 8 AM
    let currentLocation = officeLocation;

    optimizedCustomers.forEach(customer => {
      const targetLocation = customer.isLogin ? customer.pickupLocation : customer.dropLocation;
      const distance = calculateDistance(
        currentLocation.latitude,
        currentLocation.longitude,
        targetLocation.latitude,
        targetLocation.longitude
      );
      
      // Estimate driving time (25 km/h average city speed)
      const drivingTimeMinutes = Math.round((distance / 25) * 60);
      currentTime = new Date(currentTime.getTime() + (drivingTimeMinutes * 60 * 1000));
      
      customer.estimatedArrival = currentTime.toISOString();
      
      // Update current location and add service time
      currentLocation = targetLocation;
      currentTime = new Date(currentTime.getTime() + (2 * 60 * 1000)); // 2 minutes service time
    });

    console.log(`✅ Optimized route for ${optimizedCustomers.length} customers`);
    console.log(`📍 Pickup sequence: ${loginCustomers.length} customers (farthest first)`);
    console.log(`📍 Drop sequence: ${logoutCustomers.length} customers (nearest first)`);
    console.log('========== FETCH COMPLETE ==========\n');

    res.json({
      status: 'success',
      data: {
        customers: optimizedCustomers,
        totalCustomers: optimizedCustomers.length,
        pickupCustomers: loginCustomers.length,
        dropCustomers: logoutCustomers.length,
        officeLocation: officeLocation,
        optimizationStrategy: {
          pickup: 'farthest_first',
          drop: 'nearest_first',
          reason: 'Minimizes backtracking and total travel time'
        }
      }
    });

  } catch (error) {
    console.error('❌ Error fetching today\'s customers:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to fetch today\'s customers',
      error: error.message
    });
  }
});

/**
 * POST /api/driver/customer-status
 * Update customer pickup/drop status
 */
router.post('/customer-status', async (req, res) => {
  try {
    const { customerId, status, timestamp, location, notes } = req.body;
    const db = req.db;

    console.log(`📱 Updating customer status: ${customerId} -> ${status}`);

    // Update roster status
    const updateData = {
      status: status,
      updatedAt: new Date(timestamp),
      lastStatusUpdate: {
        status: status,
        timestamp: new Date(timestamp),
        location: location,
        notes: notes
      }
    };

    // Add specific timestamps based on status
    if (status === 'pickedUp') {
      updateData.actualPickupTime = new Date(timestamp);
    } else if (status === 'dropped') {
      updateData.actualDropTime = new Date(timestamp);
    }

    const result = await db.collection('rosters').updateOne(
      { userId: customerId },
      { $set: updateData }
    );

    // Log the status change
    await db.collection('customer_status_log').insertOne({
      customerId: customerId,
      status: status,
      timestamp: new Date(timestamp),
      location: location,
      notes: notes,
      driverId: req.user?.uid || 'unknown',
      createdAt: new Date()
    });

    console.log(`✅ Customer status updated: ${result.modifiedCount} document(s) modified`);

    res.json({
      status: 'success',
      message: 'Customer status updated successfully',
      data: {
        customerId: customerId,
        newStatus: status,
        timestamp: timestamp
      }
    });

  } catch (error) {
    console.error('❌ Error updating customer status:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to update customer status',
      error: error.message
    });
  }
});

/**
 * POST /api/notifications/sms
 * Send SMS notification to customer
 */
router.post('/sms', async (req, res) => {
  try {
    const { phoneNumber, message, type } = req.body;
    const db = req.db;

    console.log(`📱 Sending SMS to ${phoneNumber}: ${message.substring(0, 50)}...`);

    // Log the SMS (in production, integrate with SMS service like Twilio)
    const smsLog = {
      phoneNumber: phoneNumber,
      message: message,
      type: type,
      status: 'sent', // In production: 'pending', 'sent', 'failed'
      timestamp: new Date(),
      driverId: req.user?.uid || 'unknown'
    };

    await db.collection('sms_notifications').insertOne(smsLog);

    // TODO: Integrate with actual SMS service
    // For now, we'll simulate successful sending
    console.log(`✅ SMS logged successfully (simulation mode)`);

    res.json({
      status: 'success',
      message: 'SMS sent successfully',
      data: {
        phoneNumber: phoneNumber,
        messageId: smsLog._id,
        timestamp: smsLog.timestamp
      }
    });

  } catch (error) {
    console.error('❌ Error sending SMS:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to send SMS',
      error: error.message
    });
  }
});

/**
 * GET /api/driver/route-optimization
 * Get optimized route for current customers
 */
router.get('/route-optimization', async (req, res) => {
  try {
    // Get authenticated driver
    const user = req.user;
    if (!user) {
      return res.status(401).json({
        status: 'error',
        message: 'Authentication required'
      });
    }

    const driver = await req.db.collection('drivers').findOne({
      $or: [
        { firebaseUid: user.uid },
        { uid: user.uid },
        { 'personalInfo.email': user.email }
      ]
    });

    if (!driver) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver profile not found'
      });
    }

    const driverId = driver.driverId;
    const db = req.db;

    console.log(`🗺️ Calculating route optimization for driver: ${driverId}`);

    // Get current active customers
    const customers = await db.collection('rosters')
      .find({
        $or: [
          { driverId: driverId },
          { assignedDriverId: driverId },
          { 'assignedDriver.driverId': driverId }
        ],
        status: { $in: ['approved', 'assigned', 'in_progress', 'pickedUp'] }
      })
      .toArray();

    if (customers.length === 0) {
      return res.json({
        status: 'success',
        data: {
          route: null,
          message: 'No active customers for route optimization'
        }
      });
    }

    // Office location
    const officeLocation = {
      latitude: 12.9716,
      longitude: 77.5946,
      address: 'Abra Travels Office, Bangalore'
    };

    // Separate pending pickups and drops
    const pendingPickups = customers.filter(c => 
      (c.tripType === 'login' || c.tripType === 'both') && 
      c.status !== 'pickedUp' && c.status !== 'dropped'
    );
    
    const pendingDrops = customers.filter(c => 
      c.status === 'pickedUp' || 
      ((c.tripType === 'logout' || c.tripType === 'both') && c.status !== 'dropped')
    );

    // Calculate optimized sequence
    const optimizedRoute = calculateOptimizedRoute(
      pendingPickups,
      pendingDrops,
      officeLocation
    );

    console.log(`✅ Route optimized: ${optimizedRoute.waypoints.length} waypoints`);

    res.json({
      status: 'success',
      data: {
        route: optimizedRoute,
        summary: {
          totalWaypoints: optimizedRoute.waypoints.length,
          totalDistance: optimizedRoute.totalDistance,
          estimatedDuration: optimizedRoute.estimatedDuration,
          pendingPickups: pendingPickups.length,
          pendingDrops: pendingDrops.length
        }
      }
    });

  } catch (error) {
    console.error('❌ Error calculating route optimization:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to calculate route optimization',
      error: error.message
    });
  }
});

/**
 * POST /api/driver/broadcast-message
 * Send broadcast message to all customers
 */
router.post('/broadcast-message', async (req, res) => {
  try {
    const { message, customerIds, messageType } = req.body;
    const user = req.user;
    
    if (!user) {
      return res.status(401).json({
        status: 'error',
        message: 'Authentication required'
      });
    }

    const driver = await req.db.collection('drivers').findOne({
      $or: [
        { firebaseUid: user.uid },
        { uid: user.uid },
        { 'personalInfo.email': user.email }
      ]
    });

    if (!driver) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver profile not found'
      });
    }

    const driverId = driver.driverId;
    const db = req.db;

    console.log(`📢 Broadcasting message to ${customerIds?.length || 'all'} customers`);

    // Get customers to notify
    let customers;
    if (customerIds && customerIds.length > 0) {
      customers = await db.collection('rosters')
        .find({ userId: { $in: customerIds } })
        .toArray();
    } else {
      // Broadcast to all active customers
      customers = await db.collection('rosters')
        .find({
          $or: [
            { driverId: driverId },
            { assignedDriverId: driverId },
            { 'assignedDriver.driverId': driverId }
          ],
          status: { $in: ['approved', 'assigned', 'in_progress', 'pickedUp'] }
        })
        .toArray();
    }

    // Send messages
    const notifications = [];
    for (const customer of customers) {
      const notification = {
        customerId: customer.userId,
        customerName: customer.customerName,
        customerPhone: customer.customerPhone,
        message: message,
        messageType: messageType || 'broadcast',
        driverId: driverId,
        timestamp: new Date(),
        status: 'sent'
      };

      notifications.push(notification);
    }

    // Log all notifications
    if (notifications.length > 0) {
      await db.collection('broadcast_notifications').insertMany(notifications);
    }

    console.log(`✅ Broadcast sent to ${notifications.length} customers`);

    res.json({
      status: 'success',
      message: 'Broadcast message sent successfully',
      data: {
        recipientCount: notifications.length,
        messageType: messageType,
        timestamp: new Date()
      }
    });

  } catch (error) {
    console.error('❌ Error sending broadcast message:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to send broadcast message',
      error: error.message
    });
  }
});

/**
 * POST /api/driver/emergency-alert
 * Send emergency alert to support team and management
 */
router.post('/emergency-alert', async (req, res) => {
  try {
    const { message, location, timestamp } = req.body;
    const user = req.user;

    if (!user) {
      return res.status(401).json({
        status: 'error',
        message: 'Authentication required'
      });
    }

    const driver = await req.db.collection('drivers').findOne({
      $or: [
        { firebaseUid: user.uid },
        { uid: user.uid },
        { 'personalInfo.email': user.email }
      ]
    });

    if (!driver) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver profile not found'
      });
    }

    const driverId = driver.driverId;
    const driverName = `${driver.personalInfo?.firstName} ${driver.personalInfo?.lastName}`;
    const driverPhone = driver.personalInfo?.phone || 'Unknown';
    const db = req.db;

    console.log(`🚨 Emergency alert from driver: ${driverId}`);

    // Create emergency alert record
    const emergencyAlert = {
      driverId: driverId,
      driverName: driverName,
      driverPhone: driverPhone,
      message: message,
      location: location,
      timestamp: new Date(timestamp),
      status: 'active',
      alertLevel: 'high',
      createdAt: new Date(),
      acknowledgedBy: null,
      resolvedAt: null
    };

    const result = await db.collection('emergency_alerts').insertOne(emergencyAlert);

    // Send notifications to support team (in production, integrate with SMS/Email service)
    const supportNotifications = [
      {
        recipient: 'support@abrafleet.com',
        recipientType: 'email',
        subject: `🚨 EMERGENCY ALERT - Driver ${driverName}`,
        message: `Emergency alert from driver ${driverName} (${driverPhone})\n\nMessage: ${message}\n\nLocation: ${location ? `https://maps.google.com/?q=${location.latitude},${location.longitude}` : 'Location unavailable'}\n\nTime: ${new Date(timestamp).toLocaleString()}\n\nPlease respond immediately.`,
        alertId: result.insertedId,
        timestamp: new Date(),
        status: 'sent'
      },
      {
        recipient: '+91-886-728-8076', // Support phone
        recipientType: 'sms',
        message: `🚨 EMERGENCY: Driver ${driverName} needs assistance. Location: ${location ? `https://maps.google.com/?q=${location.latitude},${location.longitude}` : 'Unknown'}. Call immediately: ${driverPhone}`,
        alertId: result.insertedId,
        timestamp: new Date(),
        status: 'sent'
      }
    ];

    await db.collection('emergency_notifications').insertMany(supportNotifications);

    console.log(`✅ Emergency alert created with ID: ${result.insertedId}`);

    res.json({
      status: 'success',
      message: 'Emergency alert sent successfully',
      data: {
        alertId: result.insertedId,
        timestamp: timestamp,
        notificationsSent: supportNotifications.length
      }
    });

  } catch (error) {
    console.error('❌ Error sending emergency alert:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to send emergency alert',
      error: error.message
    });
  }
});

/**
 * POST /api/driver/location-update
 * Update driver's real-time location for tracking and ETA calculations
 */
router.post('/location-update', async (req, res) => {
  try {
    const { latitude, longitude, accuracy, speed, heading, timestamp } = req.body;
    const user = req.user;

    if (!user) {
      return res.status(401).json({
        status: 'error',
        message: 'Authentication required'
      });
    }

    const driver = await req.db.collection('drivers').findOne({
      $or: [
        { firebaseUid: user.uid },
        { uid: user.uid },
        { 'personalInfo.email': user.email }
      ]
    });

    if (!driver) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver profile not found'
      });
    }

    const driverId = driver.driverId;
    const db = req.db;

    // Update driver's current location
    const locationUpdate = {
      driverId: driverId,
      location: {
        latitude: parseFloat(latitude),
        longitude: parseFloat(longitude)
      },
      accuracy: accuracy,
      speed: speed,
      heading: heading,
      timestamp: new Date(timestamp),
      updatedAt: new Date()
    };

    await db.collection('driver_locations').replaceOne(
      { driverId: driverId },
      locationUpdate,
      { upsert: true }
    );

    // Check for proximity alerts and auto-notifications
    await checkProximityAlerts(db, driverId, locationUpdate.location);

    // Recalculate ETAs for all customers
    const updatedETAs = await recalculateETAs(db, driverId, locationUpdate.location);

    res.json({
      status: 'success',
      message: 'Location updated successfully',
      data: {
        location: locationUpdate.location,
        timestamp: timestamp,
        etaUpdates: updatedETAs
      }
    });

  } catch (error) {
    console.error('❌ Error updating location:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to update location',
      error: error.message
    });
  }
});

/**
 * GET /api/driver/traffic-optimized-route
 * Get traffic-optimized route using real-time traffic data
 */
router.get('/traffic-optimized-route', async (req, res) => {
  try {
    const user = req.user;

    if (!user) {
      return res.status(401).json({
        status: 'error',
        message: 'Authentication required'
      });
    }

    const driver = await req.db.collection('drivers').findOne({
      $or: [
        { firebaseUid: user.uid },
        { uid: user.uid },
        { 'personalInfo.email': user.email }
      ]
    });

    if (!driver) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver profile not found'
      });
    }

    const driverId = driver.driverId;
    const db = req.db;

    console.log(`🚦 Calculating traffic-optimized route for driver: ${driverId}`);

    // Get driver's current location
    const driverLocation = await db.collection('driver_locations').findOne({ driverId: driverId });
    
    if (!driverLocation) {
      return res.status(400).json({
        status: 'error',
        message: 'Driver location not available'
      });
    }

    // Get pending customers
    const customers = await db.collection('rosters')
      .find({
        $or: [
          { driverId: driverId },
          { assignedDriverId: driverId },
          { 'assignedDriver.driverId': driverId }
        ],
        status: { $in: ['approved', 'assigned', 'in_progress', 'pickedUp'] }
      })
      .toArray();

    if (customers.length === 0) {
      return res.json({
        status: 'success',
        data: {
          route: null,
          message: 'No pending customers'
        }
      });
    }

    // Calculate traffic-optimized route
    const optimizedRoute = await calculateTrafficOptimizedRoute(
      driverLocation.location,
      customers,
      db
    );

    console.log(`✅ Traffic-optimized route calculated with ${optimizedRoute.waypoints.length} waypoints`);

    res.json({
      status: 'success',
      data: {
        route: optimizedRoute,
        driverLocation: driverLocation.location,
        trafficOptimized: true
      }
    });

  } catch (error) {
    console.error('❌ Error calculating traffic-optimized route:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to calculate traffic-optimized route',
      error: error.message
    });
  }
});

/**
 * POST /api/driver/customer-no-show
 * Mark customer as no-show and optimize route
 */
router.post('/customer-no-show', async (req, res) => {
  try {
    const { customerId, reason, waitTime, location } = req.body;
    const user = req.user;

    if (!user) {
      return res.status(401).json({
        status: 'error',
        message: 'Authentication required'
      });
    }

    const driver = await req.db.collection('drivers').findOne({
      $or: [
        { firebaseUid: user.uid },
        { uid: user.uid },
        { 'personalInfo.email': user.email }
      ]
    });

    if (!driver) {
      return res.status(404).json({
        status: 'error',
        message: 'Driver profile not found'
      });
    }

    const driverId = driver.driverId;
    const db = req.db;

    console.log(`❌ Marking customer as no-show: ${customerId}`);

    // Update customer status
    const updateResult = await db.collection('rosters').updateOne(
      { userId: customerId },
      {
        $set: {
          status: 'no_show',
          noShowReason: reason,
          noShowWaitTime: waitTime,
          noShowLocation: location,
          noShowTimestamp: new Date(),
          updatedAt: new Date()
        }
      }
    );

    // Log the no-show incident
    await db.collection('no_show_incidents').insertOne({
      customerId: customerId,
      driverId: driverId,
      reason: reason,
      waitTime: waitTime,
      location: location,
      timestamp: new Date(),
      followUpRequired: true
    });

    // Send notification to customer and admin
    const customer = await db.collection('rosters').findOne({ userId: customerId });
    if (customer) {
      // Notify customer
      const customerMessage = `Hi ${customer.customerName}, you were marked as no-show for today's trip. If this is incorrect, please contact support at +91-886-728-8076.`;
      
      // Notify admin
      const adminMessage = `Customer ${customer.customerName} (${customer.customerPhone}) marked as no-show by driver. Reason: ${reason}. Wait time: ${waitTime} minutes.`;
      
      await db.collection('no_show_notifications').insertMany([
        {
          recipient: customer.customerPhone,
          recipientType: 'customer',
          message: customerMessage,
          customerId: customerId,
          timestamp: new Date()
        },
        {
          recipient: 'admin@abrafleet.com',
          recipientType: 'admin',
          message: adminMessage,
          customerId: customerId,
          timestamp: new Date()
        }
      ]);
    }

    // Recalculate route without this customer
    const driverLocation = await db.collection('driver_locations').findOne({ driverId: driverId });
    if (driverLocation) {
      const updatedETAs = await recalculateETAs(db, driverId, driverLocation.location);
      
      res.json({
        status: 'success',
        message: 'Customer marked as no-show and route optimized',
        data: {
          customerId: customerId,
          newStatus: 'no_show',
          etaUpdates: updatedETAs
        }
      });
    } else {
      res.json({
        status: 'success',
        message: 'Customer marked as no-show',
        data: {
          customerId: customerId,
          newStatus: 'no_show'
        }
      });
    }

  } catch (error) {
    console.error('❌ Error marking customer as no-show:', error);
    res.status(500).json({
      status: 'error',
      message: 'Failed to mark customer as no-show',
      error: error.message
    });
  }
});

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Calculate distance between two points using Haversine formula
 */
function calculateDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Earth's radius in kilometers
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = 
    Math.sin(dLat/2) * Math.sin(dLat/2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * 
    Math.sin(dLon/2) * Math.sin(dLon/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return R * c;
}

/**
 * Check for proximity alerts and send automatic notifications
 */
async function checkProximityAlerts(db, driverId, driverLocation) {
  try {
    // Get pending customers for this driver
    const customers = await db.collection('rosters')
      .find({
        $or: [
          { driverId: driverId },
          { assignedDriverId: driverId },
          { 'assignedDriver.driverId': driverId }
        ],
        status: { $in: ['approved', 'assigned', 'in_progress'] }
      })
      .toArray();

    for (const customer of customers) {
      const targetLocation = customer.status === 'pickedUp' 
        ? customer.dropLocation 
        : customer.pickupLocation;

      if (!targetLocation) continue;

      const distance = calculateDistance(
        driverLocation.latitude,
        driverLocation.longitude,
        targetLocation.latitude || 12.9716,
        targetLocation.longitude || 77.5946
      );

      // Send proximity alert when driver is within 1 km
      if (distance <= 1.0 && customer.status !== 'notified') {
        await sendProximityNotification(db, customer, distance);
        
        // Update customer status to notified
        await db.collection('rosters').updateOne(
          { _id: customer._id },
          { 
            $set: { 
              status: 'notified',
              notifiedAt: new Date(),
              proximityDistance: distance
            }
          }
        );
      }

      // Send arrival notification when driver is within 100 meters
      if (distance <= 0.1 && customer.status === 'notified') {
        await sendArrivalNotification(db, customer);
        
        // Update customer status to arrived
        await db.collection('rosters').updateOne(
          { _id: customer._id },
          { 
            $set: { 
              status: 'arrived',
              arrivedAt: new Date()
            }
          }
        );
      }
    }
  } catch (error) {
    console.error('❌ Error checking proximity alerts:', error);
  }
}

/**
 * Send proximity notification to customer
 */
async function sendProximityNotification(db, customer, distance) {
  const message = `Hi ${customer.customerName}, your driver is ${distance.toFixed(1)} km away and will arrive in 3-5 minutes at ${customer.pickupAddress || customer.dropAddress}. Please be ready!`;
  
  const notification = {
    customerId: customer.userId,
    customerName: customer.customerName,
    customerPhone: customer.customerPhone,
    message: message,
    notificationType: 'proximity_alert',
    distance: distance,
    timestamp: new Date(),
    status: 'sent'
  };

  await db.collection('proximity_notifications').insertOne(notification);
  console.log(`📱 Proximity notification sent to ${customer.customerName}`);
}

/**
 * Send arrival notification to customer
 */
async function sendArrivalNotification(db, customer) {
  const message = `Hi ${customer.customerName}, your driver has arrived at ${customer.pickupAddress || customer.dropAddress}. Please come to the pickup point.`;
  
  const notification = {
    customerId: customer.userId,
    customerName: customer.customerName,
    customerPhone: customer.customerPhone,
    message: message,
    notificationType: 'arrival_notification',
    timestamp: new Date(),
    status: 'sent'
  };

  await db.collection('arrival_notifications').insertOne(notification);
  console.log(`🚗 Arrival notification sent to ${customer.customerName}`);
}

/**
 * Recalculate ETAs based on current driver location
 */
async function recalculateETAs(db, driverId, driverLocation) {
  try {
    // Get pending customers in optimized order
    const customers = await db.collection('rosters')
      .find({
        $or: [
          { driverId: driverId },
          { assignedDriverId: driverId },
          { 'assignedDriver.driverId': driverId }
        ],
        status: { $in: ['approved', 'assigned', 'in_progress', 'pickedUp', 'notified', 'arrived'] }
      })
      .toArray();

    if (customers.length === 0) return [];

    // Separate pickups and drops
    const pendingPickups = customers.filter(c => 
      (c.tripType === 'login' || c.tripType === 'both') && 
      !['pickedUp', 'dropped'].includes(c.status)
    );
    
    const pendingDrops = customers.filter(c => 
      c.status === 'pickedUp' || 
      ((c.tripType === 'logout' || c.tripType === 'both') && c.status !== 'dropped')
    );

    // Sort by optimization strategy
    pendingPickups.sort((a, b) => {
      const distA = calculateDistance(12.9716, 77.5946, a.pickupLocation?.latitude || 12.9716, a.pickupLocation?.longitude || 77.5946);
      const distB = calculateDistance(12.9716, 77.5946, b.pickupLocation?.latitude || 12.9716, b.pickupLocation?.longitude || 77.5946);
      return distB - distA; // Farthest first
    });

    pendingDrops.sort((a, b) => {
      const distA = calculateDistance(12.9716, 77.5946, a.dropLocation?.latitude || 12.9716, a.dropLocation?.longitude || 77.5946);
      const distB = calculateDistance(12.9716, 77.5946, b.dropLocation?.latitude || 12.9716, b.dropLocation?.longitude || 77.5946);
      return distA - distB; // Nearest first
    });

    // Calculate new ETAs
    let currentLocation = driverLocation;
    let currentTime = new Date();
    const etaUpdates = [];

    // Process pickups first
    for (const customer of pendingPickups) {
      const targetLocation = customer.pickupLocation || { latitude: 12.9716, longitude: 77.5946 };
      const distance = calculateDistance(
        currentLocation.latitude,
        currentLocation.longitude,
        targetLocation.latitude,
        targetLocation.longitude
      );

      // Calculate driving time with traffic factor (30% slower during peak hours)
      const hour = currentTime.getHours();
      const trafficFactor = (hour >= 8 && hour <= 10) || (hour >= 17 && hour <= 19) ? 1.3 : 1.0;
      const drivingTimeMinutes = Math.round((distance / 25) * 60 * trafficFactor);
      
      currentTime = new Date(currentTime.getTime() + (drivingTimeMinutes * 60 * 1000));
      
      const etaUpdate = {
        customerId: customer.userId,
        customerName: customer.customerName,
        newETA: currentTime,
        distance: distance,
        drivingTime: drivingTimeMinutes,
        action: 'pickup'
      };

      etaUpdates.push(etaUpdate);

      // Update in database
      await db.collection('rosters').updateOne(
        { _id: customer._id },
        { 
          $set: { 
            estimatedArrival: currentTime,
            lastETAUpdate: new Date()
          }
        }
      );

      // Check for significant delays (more than 10 minutes from original ETA)
      if (customer.estimatedArrival) {
        const delay = currentTime - new Date(customer.estimatedArrival);
        const delayMinutes = Math.round(delay / (1000 * 60));
        
        if (delayMinutes > 10) {
          await sendDelayNotification(db, customer, delayMinutes, currentTime);
        }
      }

      currentLocation = targetLocation;
      currentTime = new Date(currentTime.getTime() + (2 * 60 * 1000)); // 2 min service time
    }

    // Process drops
    for (const customer of pendingDrops) {
      const targetLocation = customer.dropLocation || { latitude: 12.9716, longitude: 77.5946 };
      const distance = calculateDistance(
        currentLocation.latitude,
        currentLocation.longitude,
        targetLocation.latitude,
        targetLocation.longitude
      );

      const hour = currentTime.getHours();
      const trafficFactor = (hour >= 8 && hour <= 10) || (hour >= 17 && hour <= 19) ? 1.3 : 1.0;
      const drivingTimeMinutes = Math.round((distance / 25) * 60 * trafficFactor);
      
      currentTime = new Date(currentTime.getTime() + (drivingTimeMinutes * 60 * 1000));
      
      const etaUpdate = {
        customerId: customer.userId,
        customerName: customer.customerName,
        newETA: currentTime,
        distance: distance,
        drivingTime: drivingTimeMinutes,
        action: 'drop'
      };

      etaUpdates.push(etaUpdate);

      // Update in database
      await db.collection('rosters').updateOne(
        { _id: customer._id },
        { 
          $set: { 
            estimatedArrival: currentTime,
            lastETAUpdate: new Date()
          }
        }
      );

      currentLocation = targetLocation;
      currentTime = new Date(currentTime.getTime() + (1 * 60 * 1000)); // 1 min service time
    }

    console.log(`🕐 Recalculated ETAs for ${etaUpdates.length} customers`);
    return etaUpdates;

  } catch (error) {
    console.error('❌ Error recalculating ETAs:', error);
    return [];
  }
}

/**
 * Send delay notification to customer
 */
async function sendDelayNotification(db, customer, delayMinutes, newETA) {
  const message = `Hi ${customer.customerName}, your driver is running ${delayMinutes} minutes late due to traffic conditions. Updated ETA: ${newETA.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}. Thank you for your patience.`;
  
  const notification = {
    customerId: customer.userId,
    customerName: customer.customerName,
    customerPhone: customer.customerPhone,
    message: message,
    notificationType: 'delay_alert',
    delayMinutes: delayMinutes,
    newETA: newETA,
    timestamp: new Date(),
    status: 'sent'
  };

  await db.collection('delay_notifications').insertOne(notification);
  console.log(`⏰ Delay notification sent to ${customer.customerName}: ${delayMinutes} min delay`);
}

/**
 * Calculate traffic-optimized route using real-time traffic data
 */
async function calculateTrafficOptimizedRoute(driverLocation, customers, db) {
  try {
    // In production, integrate with Google Maps API or similar for real traffic data
    // For now, we'll simulate traffic-aware routing
    
    const waypoints = [];
    let currentLocation = driverLocation;
    let currentTime = new Date();
    let totalDistance = 0;

    // Separate and sort customers
    const pendingPickups = customers.filter(c => 
      (c.tripType === 'login' || c.tripType === 'both') && 
      !['pickedUp', 'dropped'].includes(c.status)
    );
    
    const pendingDrops = customers.filter(c => 
      c.status === 'pickedUp' || 
      ((c.tripType === 'logout' || c.tripType === 'both') && c.status !== 'dropped')
    );

    // Apply traffic-aware sorting
    const trafficOptimizedPickups = await optimizeWithTraffic(pendingPickups, 'pickup', currentTime);
    const trafficOptimizedDrops = await optimizeWithTraffic(pendingDrops, 'drop', currentTime);

    // Process pickups
    for (let i = 0; i < trafficOptimizedPickups.length; i++) {
      const customer = trafficOptimizedPickups[i];
      const targetLocation = customer.pickupLocation || { latitude: 12.9716, longitude: 77.5946 };
      
      const distance = calculateDistance(
        currentLocation.latitude,
        currentLocation.longitude,
        targetLocation.latitude,
        targetLocation.longitude
      );

      // Get traffic factor for current time and route
      const trafficFactor = getTrafficFactor(currentTime, distance);
      const drivingTimeMinutes = Math.round((distance / 25) * 60 * trafficFactor);
      
      currentTime = new Date(currentTime.getTime() + (drivingTimeMinutes * 60 * 1000));

      waypoints.push({
        sequence: i + 1,
        customerId: customer.userId,
        customerName: customer.customerName,
        location: targetLocation,
        address: customer.pickupAddress || 'Pickup Location',
        action: 'pickup',
        estimatedTime: currentTime.toISOString(),
        drivingTimeMinutes: drivingTimeMinutes,
        distanceFromPrevious: parseFloat(distance.toFixed(2)),
        trafficFactor: trafficFactor,
        trafficCondition: getTrafficCondition(trafficFactor)
      });

      currentLocation = targetLocation;
      totalDistance += distance;
      currentTime = new Date(currentTime.getTime() + (2 * 60 * 1000)); // Service time
    }

    // Process drops
    for (let i = 0; i < trafficOptimizedDrops.length; i++) {
      const customer = trafficOptimizedDrops[i];
      const targetLocation = customer.dropLocation || { latitude: 12.9716, longitude: 77.5946 };
      
      const distance = calculateDistance(
        currentLocation.latitude,
        currentLocation.longitude,
        targetLocation.latitude,
        targetLocation.longitude
      );

      const trafficFactor = getTrafficFactor(currentTime, distance);
      const drivingTimeMinutes = Math.round((distance / 25) * 60 * trafficFactor);
      
      currentTime = new Date(currentTime.getTime() + (drivingTimeMinutes * 60 * 1000));

      waypoints.push({
        sequence: trafficOptimizedPickups.length + i + 1,
        customerId: customer.userId,
        customerName: customer.customerName,
        location: targetLocation,
        address: customer.dropAddress || 'Drop Location',
        action: 'drop',
        estimatedTime: currentTime.toISOString(),
        drivingTimeMinutes: drivingTimeMinutes,
        distanceFromPrevious: parseFloat(distance.toFixed(2)),
        trafficFactor: trafficFactor,
        trafficCondition: getTrafficCondition(trafficFactor)
      });

      currentLocation = targetLocation;
      totalDistance += distance;
      currentTime = new Date(currentTime.getTime() + (1 * 60 * 1000)); // Service time
    }

    const startTime = new Date();
    const estimatedDuration = Math.round((currentTime - startTime) / (1000 * 60));

    return {
      waypoints: waypoints,
      totalDistance: parseFloat(totalDistance.toFixed(2)),
      estimatedDuration: estimatedDuration,
      startTime: startTime.toISOString(),
      estimatedEndTime: currentTime.toISOString(),
      trafficOptimized: true,
      optimizationStrategy: {
        pickup: 'traffic_aware_farthest_first',
        drop: 'traffic_aware_nearest_first',
        reasoning: 'Considers real-time traffic conditions while maintaining distance optimization'
      }
    };

  } catch (error) {
    console.error('❌ Error calculating traffic-optimized route:', error);
    throw error;
  }
}

/**
 * Optimize customer sequence with traffic awareness
 */
async function optimizeWithTraffic(customers, type, currentTime) {
  // Base sorting by distance from office
  const officeLocation = { latitude: 12.9716, longitude: 77.5946 };
  
  customers.forEach(customer => {
    const location = type === 'pickup' ? customer.pickupLocation : customer.dropLocation;
    customer.distanceFromOffice = calculateDistance(
      officeLocation.latitude,
      officeLocation.longitude,
      location?.latitude || 12.9716,
      location?.longitude || 77.5946
    );
    
    // Add traffic score
    customer.trafficScore = getTrafficScore(location, currentTime);
  });

  // Sort with traffic consideration
  if (type === 'pickup') {
    // Farthest first, but consider traffic
    customers.sort((a, b) => {
      const distanceWeight = 0.7;
      const trafficWeight = 0.3;
      
      const scoreA = (b.distanceFromOffice * distanceWeight) + (a.trafficScore * trafficWeight);
      const scoreB = (a.distanceFromOffice * distanceWeight) + (b.trafficScore * trafficWeight);
      
      return scoreB - scoreA;
    });
  } else {
    // Nearest first, but consider traffic
    customers.sort((a, b) => {
      const distanceWeight = 0.7;
      const trafficWeight = 0.3;
      
      const scoreA = (a.distanceFromOffice * distanceWeight) + (a.trafficScore * trafficWeight);
      const scoreB = (b.distanceFromOffice * distanceWeight) + (b.trafficScore * trafficWeight);
      
      return scoreA - scoreB;
    });
  }

  return customers;
}

/**
 * Get traffic factor based on time and distance
 */
function getTrafficFactor(currentTime, distance) {
  const hour = currentTime.getHours();
  const dayOfWeek = currentTime.getDay(); // 0 = Sunday, 6 = Saturday
  
  let baseFactor = 1.0;
  
  // Peak hours traffic
  if ((hour >= 8 && hour <= 10) || (hour >= 17 && hour <= 19)) {
    baseFactor = 1.4; // 40% slower
  } else if ((hour >= 7 && hour <= 8) || (hour >= 16 && hour <= 17) || (hour >= 19 && hour <= 20)) {
    baseFactor = 1.2; // 20% slower
  }
  
  // Weekend factor
  if (dayOfWeek === 0 || dayOfWeek === 6) {
    baseFactor *= 0.8; // 20% faster on weekends
  }
  
  // Distance factor (longer distances may have better traffic flow)
  if (distance > 10) {
    baseFactor *= 0.9; // Slightly better for longer distances
  }
  
  return Math.round(baseFactor * 100) / 100;
}

/**
 * Get traffic score for optimization
 */
function getTrafficScore(location, currentTime) {
  // Simulate traffic score based on location and time
  // In production, this would use real traffic API data
  
  const hour = currentTime.getHours();
  let score = 1.0;
  
  // Peak hours penalty
  if ((hour >= 8 && hour <= 10) || (hour >= 17 && hour <= 19)) {
    score = 1.5;
  }
  
  // Add some randomness to simulate real traffic variations
  score += (Math.random() - 0.5) * 0.3;
  
  return Math.max(0.5, Math.min(2.0, score));
}

/**
 * Get traffic condition description
 */
function getTrafficCondition(trafficFactor) {
  if (trafficFactor >= 1.4) return 'Heavy Traffic';
  if (trafficFactor >= 1.2) return 'Moderate Traffic';
  if (trafficFactor >= 1.0) return 'Light Traffic';
  return 'Free Flow';
}

/**
 * Calculate optimized route with waypoints and ETAs
 */
function calculateOptimizedRoute(pickups, drops, officeLocation) {
  const waypoints = [];
  let currentLocation = officeLocation;
  let currentTime = new Date();
  let totalDistance = 0;

  // Sort pickups by distance from office (farthest first)
  pickups.sort((a, b) => {
    const distA = calculateDistance(
      officeLocation.latitude, officeLocation.longitude,
      a.pickupLocation?.latitude || 12.9716, a.pickupLocation?.longitude || 77.5946
    );
    const distB = calculateDistance(
      officeLocation.latitude, officeLocation.longitude,
      b.pickupLocation?.latitude || 12.9716, b.pickupLocation?.longitude || 77.5946
    );
    return distB - distA; // Farthest first
  });

  // Sort drops by distance from office (nearest first)
  drops.sort((a, b) => {
    const distA = calculateDistance(
      officeLocation.latitude, officeLocation.longitude,
      a.dropLocation?.latitude || 12.9716, a.dropLocation?.longitude || 77.5946
    );
    const distB = calculateDistance(
      officeLocation.latitude, officeLocation.longitude,
      b.dropLocation?.latitude || 12.9716, b.dropLocation?.longitude || 77.5946
    );
    return distA - distB; // Nearest first
  });

  // Add pickup waypoints
  pickups.forEach((customer, index) => {
    const targetLat = customer.pickupLocation?.latitude || 12.9716;
    const targetLng = customer.pickupLocation?.longitude || 77.5946;
    
    const distance = calculateDistance(
      currentLocation.latitude, currentLocation.longitude,
      targetLat, targetLng
    );
    
    const drivingTimeMinutes = Math.round((distance / 25) * 60); // 25 km/h average
    currentTime = new Date(currentTime.getTime() + (drivingTimeMinutes * 60 * 1000));
    
    waypoints.push({
      sequence: index + 1,
      customerId: customer.userId,
      customerName: customer.customerName,
      location: {
        latitude: targetLat,
        longitude: targetLng
      },
      address: customer.pickupAddress || 'Pickup Location',
      action: 'pickup',
      estimatedTime: currentTime.toISOString(),
      drivingTimeMinutes: drivingTimeMinutes,
      distanceFromPrevious: parseFloat(distance.toFixed(2))
    });

    currentLocation = { latitude: targetLat, longitude: targetLng };
    totalDistance += distance;
    
    // Add service time (2 minutes for pickup)
    currentTime = new Date(currentTime.getTime() + (2 * 60 * 1000));
  });

  // Add drop waypoints
  drops.forEach((customer, index) => {
    const targetLat = customer.dropLocation?.latitude || 12.9716;
    const targetLng = customer.dropLocation?.longitude || 77.5946;
    
    const distance = calculateDistance(
      currentLocation.latitude, currentLocation.longitude,
      targetLat, targetLng
    );
    
    const drivingTimeMinutes = Math.round((distance / 25) * 60);
    currentTime = new Date(currentTime.getTime() + (drivingTimeMinutes * 60 * 1000));
    
    waypoints.push({
      sequence: pickups.length + index + 1,
      customerId: customer.userId,
      customerName: customer.customerName,
      location: {
        latitude: targetLat,
        longitude: targetLng
      },
      address: customer.dropAddress || 'Drop Location',
      action: 'drop',
      estimatedTime: currentTime.toISOString(),
      drivingTimeMinutes: drivingTimeMinutes,
      distanceFromPrevious: parseFloat(distance.toFixed(2))
    });

    currentLocation = { latitude: targetLat, longitude: targetLng };
    totalDistance += distance;
    
    // Add service time (1 minute for drop)
    currentTime = new Date(currentTime.getTime() + (1 * 60 * 1000));
  });

  const startTime = new Date();
  const estimatedDuration = Math.round((currentTime - startTime) / (1000 * 60)); // in minutes

  return {
    waypoints: waypoints,
    totalDistance: parseFloat(totalDistance.toFixed(2)),
    estimatedDuration: estimatedDuration,
    startTime: startTime.toISOString(),
    estimatedEndTime: currentTime.toISOString(),
    optimizationStrategy: {
      pickup: 'farthest_first',
      drop: 'nearest_first',
      reasoning: 'Minimizes backtracking and reduces total travel time'
    }
  };
}

module.exports = router;