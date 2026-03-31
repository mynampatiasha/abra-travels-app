const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken } = require('../middleware/auth');

// ============================================
// CUSTOMER ENDPOINTS
// ============================================

// GET /api/address-change/customer/current-addresses - Get customer's current addresses
router.get('/customer/current-addresses', verifyToken, async (req, res) => {
  try {
    const db = req.db;
    
    // ✅ Get customer details from CUSTOMERS collection (not users/firebaseUid)
    const customer = await db.collection('customers').findOne({ 
      _id: new ObjectId(req.user._id)
    });

    if (!customer) {
      return res.status(404).json({ 
        success: false, 
        message: 'Customer not found' 
      });
    }

    // Also check for latest assigned roster
    const latestRoster = await db.collection('rosters')
      .findOne(
        { 
          customerId: req.user._id.toString(),
          status: { $in: ['assigned', 'pending'] }
        },
        { sort: { createdAt: -1 } }
      );

    res.json({
      success: true,
      data: {
        pickupLocation: latestRoster?.pickupLocation || customer.pickupLocation || '',
        dropLocation: latestRoster?.dropLocation || customer.dropLocation || '',
        pickupLat: latestRoster?.pickupLat || customer.pickupLat || null,
        pickupLng: latestRoster?.pickupLng || customer.pickupLng || null,
        dropLat: latestRoster?.dropLat || customer.dropLat || null,
        dropLng: latestRoster?.dropLng || customer.dropLng || null,
      }
    });

  } catch (error) {
    console.error('Error fetching current addresses:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch current addresses',
      error: error.message 
    });
  }
});

// POST /api/address-change/customer/request - Submit address change request
router.post('/customer/request', verifyToken, async (req, res) => {
  console.log('\n' + '='.repeat(80));
  console.log('📍 ADDRESS CHANGE REQUEST RECEIVED');
  console.log('='.repeat(80));
  
  try {
    const db = req.db;
    const { 
      currentPickupAddress, 
      newPickupAddress, 
      newPickupLat,
      newPickupLng,
      currentDropAddress, 
      newDropAddress,
      newDropLat,
      newDropLng,
      reason 
    } = req.body;

    console.log(`👤 Customer ID: ${req.user._id}`);
    console.log(`📧 Customer Email: ${req.user.email}`);
    console.log(`📍 New Pickup: ${newPickupAddress}`);
    console.log(`📍 New Drop: ${newDropAddress}`);
    console.log(`📝 Reason: ${reason || 'Not provided'}`);

    // Validate required fields
    if (!newPickupAddress || !newDropAddress) {
      console.log('❌ Validation failed: Missing required addresses');
      return res.status(400).json({ 
        success: false, 
        message: 'New pickup and drop addresses are required' 
      });
    }

    // ✅ Get customer details from CUSTOMERS collection
    console.log('🔍 Looking up customer in customers collection...');
    const customer = await db.collection('customers').findOne({ 
      _id: new ObjectId(req.user._id)
    });

    if (!customer) {
      console.log('❌ Customer not found in customers collection');
      console.log(`   Customer ID: ${req.user._id}`);
      return res.status(404).json({ 
        success: false, 
        message: 'Customer not found. Please ensure you are registered as a customer.' 
      });
    }

    console.log(`✅ Customer found: ${customer.name || customer.email}`);
    console.log(`   Organization: ${customer.organizationName || customer.companyName || 'None'}`);
    console.log(`   Email: ${customer.email}`);

    // Find affected upcoming trips (rosters)
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    const affectedTrips = await db.collection('rosters')
      .find({
        customerId: req.user._id.toString(),
        tripDate: { $gte: today },
        status: { $in: ['pending', 'assigned'] }
      })
      .sort({ tripDate: 1 })
      .toArray();

    // Create address change request
    const addressChangeRequest = {
      customerId: req.user._id.toString(),
      customerName: customer.name || customer.email,
      customerEmail: customer.email,
      customerPhone: customer.phone || customer.phoneNumber || '',
      organizationName: customer.organizationName || customer.companyName || '',
      
      currentPickupAddress: currentPickupAddress || customer.pickupLocation || '',
      newPickupAddress,
      newPickupLat: newPickupLat || null,
      newPickupLng: newPickupLng || null,
      
      currentDropAddress: currentDropAddress || customer.dropLocation || '',
      newDropAddress,
      newDropLat: newDropLat || null,
      newDropLng: newDropLng || null,
      
      reason: reason || '',
      status: 'under_review', // under_review, processing, completed, rejected
      
      affectedTripIds: affectedTrips.map(trip => trip._id),
      affectedTripsCount: affectedTrips.length,
      
      createdAt: new Date(),
      updatedAt: new Date()
    };

    const result = await db.collection('address_change_requests').insertOne(addressChangeRequest);

    // ✅ Send notification to ALL admins
    console.log('📧 Finding ALL admins to notify...');
    
    // Get admins from admin_users collection
    const admins = await db.collection('admin_users').find({
      status: 'active',
      isActive: true
    }).toArray();

    // Also get clients who might need to see this
    const clients = await db.collection('clients').find({
      status: 'active',
      isActive: true
    }).toArray();

    const allAdmins = [...admins, ...clients];

    console.log(`📧 Sending address change notification to ${allAdmins.length} admin(s)/client(s)`);

    // Send notification to each admin
    const adminNotifications = allAdmins.map(admin => ({
      userId: admin._id.toString(),
      userRole: admin.role || 'admin',
      title: 'New Address Change Request',
      message: `${customer.name || customer.email} has requested an address change`,
      type: 'address_change_request',
      data: {
        requestId: result.insertedId.toString(),
        customerId: req.user._id.toString(),
        customerName: customer.name || customer.email,
        customerEmail: customer.email,
        customerPhone: customer.phoneNumber || customer.phone || '',
        affectedTripsCount: affectedTrips.length,
        organizationName: customer.organizationName || customer.companyName || 'N/A'
      },
      read: false,
      createdAt: new Date()
    }));

    if (adminNotifications.length > 0) {
      await db.collection('notifications').insertMany(adminNotifications);
      console.log(`✅ Sent ${adminNotifications.length} notification(s) to admins`);
      
      // Log each admin who received notification
      allAdmins.forEach((admin, index) => {
        console.log(`   ${index + 1}. ${admin.name || admin.email} (${admin.role || 'admin'}) - ${admin.email}`);
      });
    } else {
      console.warn(`⚠️ No admins found in the system`);
    }

    console.log('\n' + '='.repeat(80));
    console.log('✅ ADDRESS CHANGE REQUEST COMPLETED SUCCESSFULLY');
    console.log('='.repeat(80));
    console.log(`📋 Request ID: ${result.insertedId}`);
    console.log(`👤 Customer: ${customer.name || customer.email}`);
    console.log(`📧 Email: ${customer.email}`);
    console.log(`🏢 Organization: ${customer.organizationName || customer.companyName || 'None'}`);
    console.log(`📊 Affected Trips: ${affectedTrips.length}`);
    console.log(`🔔 Admins Notified: ${adminNotifications.length}`);
    console.log('='.repeat(80) + '\n');

    res.json({
      success: true,
      message: 'Address change request submitted successfully. Processing will take 4-5 working days.',
      data: {
        requestId: result.insertedId,
        affectedTripsCount: affectedTrips.length,
        estimatedProcessingDays: '4-5 working days'
      }
    });

  } catch (error) {
    console.error('Error submitting address change request:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to submit address change request',
      error: error.message 
    });
  }
});

// GET /api/address-change/customer/requests - Get customer's address change requests
router.get('/customer/requests', verifyToken, async (req, res) => {
  try {
    const db = req.db;
    const { status } = req.query;

    const query = { customerId: req.user._id.toString() };
    if (status && status !== 'all') {
      query.status = status;
    }

    const requests = await db.collection('address_change_requests')
      .find(query)
      .sort({ createdAt: -1 })
      .toArray();

    res.json({
      success: true,
      data: requests
    });

  } catch (error) {
    console.error('Error fetching address change requests:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch address change requests',
      error: error.message 
    });
  }
});

// ============================================
// ADMIN ENDPOINTS
// ============================================

// GET /api/address-change/admin/requests - Get all address change requests
router.get('/admin/requests', verifyToken, async (req, res) => {
  try {
    const db = req.db;
    const { status } = req.query;

    const query = {};
    if (status && status !== 'all') {
      query.status = status;
    }

    const requests = await db.collection('address_change_requests')
      .find(query)
      .sort({ createdAt: -1 })
      .toArray();

    res.json({
      success: true,
      data: requests
    });

  } catch (error) {
    console.error('Error fetching address change requests:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch address change requests',
      error: error.message 
    });
  }
});

// GET /api/address-change/admin/request/:id - Get specific request details
router.get('/admin/request/:id', verifyToken, async (req, res) => {
  try {
    const db = req.db;
    const requestId = req.params.id;

    const request = await db.collection('address_change_requests')
      .findOne({ _id: new ObjectId(requestId) });

    if (!request) {
      return res.status(404).json({ 
        success: false, 
        message: 'Address change request not found' 
      });
    }

    // Get affected trips details
    const affectedTrips = await db.collection('rosters')
      .find({ _id: { $in: request.affectedTripIds } })
      .toArray();

    res.json({
      success: true,
      data: {
        ...request,
        affectedTrips
      }
    });

  } catch (error) {
    console.error('Error fetching address change request:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch address change request',
      error: error.message 
    });
  }
});

// PUT /api/address-change/admin/request/:id/process - Process and assign roster
router.put('/admin/request/:id/process', verifyToken, async (req, res) => {
  try {
    const db = req.db;
    const requestId = req.params.id;
    const { 
      driverId, 
      driverName,
      vehicleId, 
      vehicleNumber,
      vehicleType,
      vehicleModel,
      pickupTime,
      startDate,
      serviceDays,
      adminNotes 
    } = req.body;

    // Validate required fields
    if (!driverId || !vehicleId || !pickupTime || !startDate) {
      return res.status(400).json({ 
        success: false, 
        message: 'Driver, vehicle, pickup time, and start date are required' 
      });
    }

    const request = await db.collection('address_change_requests')
      .findOne({ _id: new ObjectId(requestId) });

    if (!request) {
      return res.status(404).json({ 
        success: false, 
        message: 'Address change request not found' 
      });
    }

    if (request.status !== 'under_review') {
      return res.status(400).json({ 
        success: false, 
        message: 'Only requests under review can be processed' 
      });
    }

    // ✅ Update customer's default addresses in CUSTOMERS collection
    await db.collection('customers').updateOne(
      { _id: new ObjectId(request.customerId) },
      { 
        $set: { 
          pickupLocation: request.newPickupAddress,
          pickupLat: request.newPickupLat,
          pickupLng: request.newPickupLng,
          dropLocation: request.newDropAddress,
          dropLat: request.newDropLat,
          dropLng: request.newDropLng,
          updatedAt: new Date()
        } 
      }
    );

    // Create new roster assignment with new addresses
    const newRoster = {
      customerId: request.customerId,
      customerName: request.customerName,
      customerEmail: request.customerEmail,
      customerPhone: request.customerPhone,
      
      pickupLocation: request.newPickupAddress,
      pickupLat: request.newPickupLat,
      pickupLng: request.newPickupLng,
      
      dropLocation: request.newDropAddress,
      dropLat: request.newDropLat,
      dropLng: request.newDropLng,
      
      driverId,
      driverName,
      vehicleId,
      vehicleNumber,
      vehicleType,
      vehicleModel,
      
      pickupTime,
      startDate: new Date(startDate),
      serviceDays: serviceDays || ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
      
      status: 'assigned',
      addressChangeRequestId: new ObjectId(requestId),
      
      createdAt: new Date(),
      updatedAt: new Date()
    };

    const rosterResult = await db.collection('rosters').insertOne(newRoster);

    // Update address change request
    await db.collection('address_change_requests').updateOne(
      { _id: new ObjectId(requestId) },
      { 
        $set: { 
          status: 'completed',
          processedBy: req.user._id.toString(),
          processedAt: new Date(),
          assignedRosterId: rosterResult.insertedId,
          driverId,
          driverName,
          vehicleId,
          vehicleNumber,
          adminNotes: adminNotes || '',
          updatedAt: new Date()
        } 
      }
    );

    // Send notification to driver
    await db.collection('notifications').insertOne({
      userId: driverId,
      userRole: 'driver',
      title: 'New Roster Assigned',
      message: `New roster assigned for ${request.customerName}`,
      type: 'roster_assignment',
      data: {
        rosterId: rosterResult.insertedId.toString(),
        customerName: request.customerName,
        pickupLocation: request.newPickupAddress,
        dropLocation: request.newDropAddress,
        pickupTime,
        startDate
      },
      read: false,
      createdAt: new Date()
    });

    // Send notification to customer
    await db.collection('notifications').insertOne({
      userId: request.customerId,
      userRole: 'customer',
      title: 'Your Transportation is Ready!',
      message: `Good news! Your address change has been processed. Your vehicle is ready from ${new Date(startDate).toLocaleDateString()} onwards.`,
      type: 'address_change_completed',
      data: {
        requestId: requestId,
        rosterId: rosterResult.insertedId.toString(),
        vehicleNumber,
        vehicleType,
        vehicleModel,
        driverName,
        pickupLocation: request.newPickupAddress,
        dropLocation: request.newDropAddress,
        pickupTime,
        startDate
      },
      read: false,
      createdAt: new Date()
    });

    res.json({
      success: true,
      message: 'Address change request processed and roster assigned successfully',
      data: {
        requestId,
        rosterId: rosterResult.insertedId,
        customerNotified: true,
        driverNotified: true
      }
    });

  } catch (error) {
    console.error('Error processing address change request:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to process address change request',
      error: error.message 
    });
  }
});

// PUT /api/address-change/admin/request/:id/reject - Reject address change request
router.put('/admin/request/:id/reject', verifyToken, async (req, res) => {
  try {
    const db = req.db;
    const requestId = req.params.id;
    const { rejectionReason } = req.body;

    if (!rejectionReason) {
      return res.status(400).json({ 
        success: false, 
        message: 'Rejection reason is required' 
      });
    }

    const request = await db.collection('address_change_requests')
      .findOne({ _id: new ObjectId(requestId) });

    if (!request) {
      return res.status(404).json({ 
        success: false, 
        message: 'Address change request not found' 
      });
    }

    // Update request status
    await db.collection('address_change_requests').updateOne(
      { _id: new ObjectId(requestId) },
      { 
        $set: { 
          status: 'rejected',
          rejectedBy: req.user._id.toString(),
          rejectedAt: new Date(),
          rejectionReason,
          updatedAt: new Date()
        } 
      }
    );

    // Send notification to customer
    await db.collection('notifications').insertOne({
      userId: request.customerId,
      userRole: 'customer',
      title: 'Address Change Request Rejected',
      message: `Your address change request has been rejected. Reason: ${rejectionReason}`,
      type: 'address_change_rejected',
      data: {
        requestId: requestId,
        rejectionReason
      },
      read: false,
      createdAt: new Date()
    });

    res.json({
      success: true,
      message: 'Address change request rejected',
      data: {
        requestId,
        customerNotified: true
      }
    });

  } catch (error) {
    console.error('Error rejecting address change request:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to reject address change request',
      error: error.message 
    });
  }
});

module.exports = router;