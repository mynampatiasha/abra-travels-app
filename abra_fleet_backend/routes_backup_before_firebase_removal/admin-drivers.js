const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { createNotification } = require('../models/notification_model');
const emailService = require('../services/email_service');
const { getDriverWelcomeTemplate, getDriverWelcomeText } = require('../services/email_templates');
const bcrypt = require('bcrypt');

// Admin Driver Management APIs - JWT Authentication Only (NO FIREBASE)
// Base route: /api/admin/drivers

// GET /api/drivers/profile - Get current driver's profile (for authenticated drivers)
router.get('/profile', async (req, res) => {
  try {
  
    console.log('🔍 Driver profile request received');
    console.log('   - User:', req.user);
    console.log('   - Headers:', req.headers.authorization ? 'Authorization header present' : 'No auth header');
    
    // ✅ Get the authenticated user from JWT token (NOT Firebase)
    const user = req.user;
    if (!user) {
      console.log('❌ No authenticated user found');
      return res.status(401).json({
        success: false,
        message: 'Authentication required'
      });
    }
    
    console.log('✅ Authenticated user found:', user.userId);
    console.log('   - Email:', user.email);
    console.log('   - Role:', user.role);
    console.log('   - Driver ID from token:', user.driverId);
    
    // ✅ FIX: Find driver using JWT token data
    let driver = await req.db.collection('drivers').findOne({
      $or: [
        { _id: new ObjectId(user.userId) },      // Primary: JWT userId (MongoDB _id)
        { driverId: user.driverId },              // JWT driverId field
        { firebaseUid: user.userId },             // Legacy: Firebase UID
        { uid: user.userId },                     // Legacy: UID field
        { 'personalInfo.email': user.email }      // Fallback: Email match
      ]
    });
    
    if (!driver) {
      console.log('❌ Driver not found in drivers collection');
      console.log('   - Searched for userId:', user.userId);
      console.log('   - Searched for driverId:', user.driverId);
      console.log('   - Searched for email:', user.email);
      
      return res.status(404).json({
        success: false,
        message: 'Driver profile not found'
      });
    }
    
    console.log('✅ Driver found:', driver.driverId);
    console.log('   - Name:', `${driver.personalInfo?.firstName} ${driver.personalInfo?.lastName}`);
    console.log('   - Email:', driver.personalInfo?.email);
    
    // Get assigned vehicle details if any
    let assignedVehicle = null;
    if (driver.assignedVehicle) {
      assignedVehicle = await req.db.collection('vehicles').findOne(
        { vehicleId: driver.assignedVehicle },
        { 
          projection: { 
            vehicleId: 1, 
            registrationNumber: 1, 
            make: 1, 
            model: 1,
            type: 1,
            status: 1
          } 
        }
      );
      console.log('✅ Assigned vehicle found:', assignedVehicle?.vehicleId);
    }
    
    // Get recent trips
    const recentTrips = await req.db.collection('trips')
      .find({ driverId: driver.driverId })
      .sort({ startTime: -1 })
      .limit(5)
      .toArray();
    
    // Get performance stats
    const totalTrips = await req.db.collection('trips')
      .countDocuments({ driverId: driver.driverId });
    
    const completedTrips = await req.db.collection('trips')
      .countDocuments({ 
        driverId: driver.driverId, 
        status: 'completed' 
      });
    
    // Prepare response data compatible with frontend
    const profileData = {
      _id: driver._id,
      firebaseUid: driver.firebaseUid || driver.uid,
      name: `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim(),
      email: driver.personalInfo?.email,
      phoneNumber: driver.personalInfo?.phone,
      role: 'driver',
      status: driver.status || 'active',
      driverId: driver.driverId,
      personalInfo: driver.personalInfo,
      license: driver.license,
      emergencyContact: driver.emergencyContact,
      address: driver.address,
      assignedVehicle,
      stats: {
        totalTrips,
        completedTrips,
        completionRate: totalTrips > 0 ? Math.round((completedTrips / totalTrips) * 100) : 0
      },
      recentTrips,
      joinedDate: driver.joinedDate || driver.createdAt,
      createdAt: driver.createdAt,
      updatedAt: driver.updatedAt
    };
    
    console.log('✅ Profile data prepared successfully');
    
    res.json({
      success: true,
      data: profileData
    });
  } catch (error) {
    console.error('❌ Error fetching driver profile:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch driver profile',
      error: error.message
    });
  }
});

// ✅ Helper function to get trip statistics for a driver (DATE-BASED)
async function getDriverTripStats(db, driverId) {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const todayStr = today.toISOString().split('T')[0]; // "2026-01-21"
  
  const stats = await db.collection('trips').aggregate([
    {
      $match: { driverId }
    },
    {
      $addFields: {
        tripDate: {
          $cond: {
            if: { $eq: [{ $type: "$scheduledDate" }, "string"] },
            then: "$scheduledDate",
            else: {
              $dateToString: { format: "%Y-%m-%d", date: "$scheduledDate" }
            }
          }
        }
      }
    },
    {
      $group: {
        _id: {
          $cond: [
            { $eq: ["$tripDate", todayStr] }, "ongoing",
            {
              $cond: [
                { $lt: ["$tripDate", todayStr] }, "completed",
                "assigned"
              ]
            }
          ]
        },
        count: { $sum: 1 }
      }
    }
  ]).toArray();
  
  return {
    ongoing: stats.find(s => s._id === 'ongoing')?.count || 0,
    assigned: stats.find(s => s._id === 'assigned')?.count || 0,
    completed: stats.find(s => s._id === 'completed')?.count || 0,
    total: stats.reduce((sum, s) => sum + s.count, 0)
  };
}

// ✅ Helper function to get current trip for a driver (TODAY'S TRIP)
async function getDriverCurrentTrip(db, driverId) {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const todayStr = today.toISOString().split('T')[0]; // "2026-01-21"
  
  return await db.collection('trips').findOne({
    driverId,
    $or: [
      { scheduledDate: todayStr },
      {
        scheduledDate: {
          $gte: today,
          $lt: new Date(today.getTime() + 24 * 60 * 60 * 1000)
        }
      }
    ]
  }, {
    projection: {
      tripId: 1,
      tripNumber: 1,
      scheduledDate: 1,
      startTime: 1,
      'customer.name': 1,
      'customer.customerId': 1,
      pickupLocation: 1,
      dropLocation: 1,
      vehicleId: 1
    },
    sort: { startTime: 1 }
  });
}

// GET /api/admin/drivers - Get all drivers with optional filters
router.get('/', async (req, res) => {
  try {
    const { status, page = 1, limit = 20, search, fullDetails } = req.query;
    
    // Build filter
    let filter = {};
    if (status && status !== 'All') filter.status = status;
    
    if (search) {
      filter.$or = [
        { driverId: { $regex: search, $options: 'i' } },
        { 'personalInfo.phone': { $regex: search, $options: 'i' } },
        { 'personalInfo.email': { $regex: search, $options: 'i' } },
        { 'personalInfo.firstName': { $regex: search, $options: 'i' } },
        { 'personalInfo.lastName': { $regex: search, $options: 'i' } }
      ];
    }
    
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    const drivers = await req.db.collection('drivers')
      .find(filter)
      .skip(skip)
      .limit(parseInt(limit))
      .sort({ createdAt: -1 })
      .toArray();
    
    const totalCount = await req.db.collection('drivers').countDocuments(filter);
    
    // If fullDetails is requested, return complete driver objects with flat structure
    if (fullDetails === 'true') {
      const driversWithVehicles = await Promise.all(
        drivers.map(async (driver) => {
          // Get assigned vehicle details if any
          let assignedVehicle = null;
          if (driver.assignedVehicle) {
            assignedVehicle = await req.db.collection('vehicles').findOne(
              { vehicleId: driver.assignedVehicle },
              { projection: { vehicleId: 1, registrationNumber: 1, make: 1, model: 1, type: 1 } }
            );
          }
          
          // Ensure documents is always an array
          const documents = Array.isArray(driver.documents) ? driver.documents : [];
          
          // Return flat structure for frontend compatibility
          return {
            ...driver, // Include all original fields
            driverId: driver.driverId,
            name: `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim() || 'N/A',
            email: driver.personalInfo?.email || 'N/A',
            phone: driver.personalInfo?.phone || 'N/A',
            status: driver.status || 'inactive',
            documents, // ✅ Always an array
            assignedVehicle,
            licenseNumber: driver.license?.licenseNumber,
            licenseExpiry: driver.license?.expiryDate,
            joinedDate: driver.joinedDate || driver.createdAt
          };
        })
      );
      
      return res.json({
        success: true,
        data: driversWithVehicles,
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total: totalCount,
          pages: Math.ceil(totalCount / parseInt(limit))
        }
      });
    }
    
    // Get additional stats for each driver (simplified view)
    const driversWithStats = await Promise.all(
      drivers.map(async (driver) => {
        // Get assigned vehicle details if any
        let assignedVehicle = null;
        if (driver.assignedVehicle) {
          assignedVehicle = await req.db.collection('vehicles').findOne(
            { vehicleId: driver.assignedVehicle },
            { projection: { vehicleId: 1, registrationNumber: 1, make: 1, model: 1 } }
          );
        }
        
        // Get trip count
        const tripCount = await req.db.collection('trips')
          .countDocuments({ driverId: driver.driverId });
        
        // ✅ NEW: Get trip statistics (DATE-BASED)
        const tripStats = await getDriverTripStats(req.db, driver.driverId);
        
        // ✅ NEW: Get current trip if any (TODAY'S TRIP)
        const currentTrip = await getDriverCurrentTrip(req.db, driver.driverId);
        
        // Ensure documents is always an array
        const documents = Array.isArray(driver.documents) ? driver.documents : [];
        
        return {
          driverId: driver.driverId,
          name: `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim() || 'N/A',
          phone: driver.personalInfo?.phone || 'N/A',
          email: driver.personalInfo?.email || 'N/A',
          status: driver.status,
          assignedVehicle,
          documents, // ✅ Include documents array
          totalTrips: tripCount,
          tripStats, // ✅ NEW: Trip statistics by date
          currentTrip, // ✅ NEW: Today's trip if any
          licenseNumber: driver.license?.licenseNumber,
          licenseExpiry: driver.license?.expiryDate,
          joinedDate: driver.joinedDate || driver.createdAt
        };
      })
    );
    
    res.json({
      success: true,
      data: driversWithStats,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalCount,
        pages: Math.ceil(totalCount / parseInt(limit))
      },
      summary: {
        total: totalCount,
        active: await req.db.collection('drivers').countDocuments({ status: 'active' }),
        onLeave: await req.db.collection('drivers').countDocuments({ status: 'on_leave' }),
        inactive: await req.db.collection('drivers').countDocuments({ status: 'inactive' })
      }
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to fetch drivers',
      error: error.message
    });
  }
});

// POST /api/admin/drivers - Add new driver
router.post('/', async (req, res) => {
  console.log('\n🚗 ========== DRIVER CREATION STARTED ==========');
  console.log('📥 Request body:', JSON.stringify(req.body, null, 2));
  
  try {
    const {
      driverId,
      personalInfo,
      license,
      emergencyContact,
      address,
      status = 'active'
    } = req.body;
    
    console.log('✅ Request data extracted successfully');
    console.log('   - Driver ID:', driverId);
    console.log('   - Email:', personalInfo?.email);
    console.log('   - Name:', `${personalInfo?.firstName} ${personalInfo?.lastName}`);
    
    // Validate required fields
    const requiredFields = [
      'driverId',
      'personalInfo.firstName',
      'personalInfo.lastName',
      'personalInfo.phone',
      'personalInfo.email',
      'license.licenseNumber',
      'license.issueDate',
      'license.expiryDate',
      'license.type'
    ];
    
    const missingFields = requiredFields.filter(field => {
      const parts = field.split('.');
      let value = req.body;
      for (const part of parts) {
        value = value?.[part];
        if (value === undefined) return true;
      }
      return false;
    });
    
    if (missingFields.length > 0) {
      console.error('❌ Validation failed - Missing fields:', missingFields);
      return res.status(400).json({
        success: false,
        message: `Missing required fields: ${missingFields.join(', ')}`
      });
    }
    
    console.log('✅ All required fields validated');
    
    // Check if driver already exists
    console.log('🔍 Checking for existing driver...');
    const existingDriver = await req.db.collection('drivers').findOne({
      $or: [
        { driverId },
        { 'personalInfo.phone': personalInfo.phone },
        { 'personalInfo.email': personalInfo.email },
        { 'license.licenseNumber': license.licenseNumber }
      ]
    });
    
    if (existingDriver) {
      console.error('❌ Driver already exists:', {
        existingDriverId: existingDriver.driverId,
        existingEmail: existingDriver.personalInfo?.email
      });
      return res.status(409).json({
        success: false,
        message: 'Driver with the same ID, phone, email, or license number already exists'
      });
    }
    
    console.log('✅ No duplicate driver found');
    
    // 🔥 CREATE FIREBASE AUTH USER FIRST
    console.log('\n🔐 ========== FIREBASE USER CREATION ==========');
    console.log('🔐 Creating Firebase Auth user for:', personalInfo.email);
    
    let firebaseUid = null;
    try {
      // Generate a temporary random password (driver will reset it via email)
      const tempPassword = Math.random().toString(36).slice(-12) + 'Aa1!';
      
      // Create Firebase Auth user
      const firebaseUser = await admin.auth().createUser({
        email: personalInfo.email,
        emailVerified: false,
        password: tempPassword,
        displayName: `${personalInfo.firstName} ${personalInfo.lastName}`,
        disabled: false
      });
      
      firebaseUid = firebaseUser.uid;
      console.log('✅ Firebase user created successfully');
      console.log('   - Firebase UID:', firebaseUid);
      console.log('   - Email:', firebaseUser.email);
      console.log('   - Display Name:', firebaseUser.displayName);
      
      // Set custom claims for driver role
      await admin.auth().setCustomUserClaims(firebaseUid, {
        role: 'driver',
        driverId: driverId
      });
      console.log('✅ Custom claims set: role=driver, driverId=' + driverId);
      
    } catch (firebaseError) {
      console.error('❌ Firebase user creation failed:', firebaseError.message);
      
      // If Firebase user already exists, try to get the existing user
      if (firebaseError.code === 'auth/email-already-exists') {
        console.log('⚠️  Firebase user already exists, fetching existing user...');
        try {
          const existingFirebaseUser = await admin.auth().getUserByEmail(personalInfo.email);
          firebaseUid = existingFirebaseUser.uid;
          console.log('✅ Using existing Firebase UID:', firebaseUid);
        } catch (fetchError) {
          console.error('❌ Failed to fetch existing Firebase user:', fetchError.message);
          return res.status(500).json({
            success: false,
            message: 'Email already registered in Firebase but cannot retrieve user details'
          });
        }
      } else {
        return res.status(500).json({
          success: false,
          message: `Failed to create Firebase user: ${firebaseError.message}`
        });
      }
    }
    
    // 💾 CREATE MONGODB DRIVER RECORD WITH FIREBASE UID
    console.log('\n💾 ========== MONGODB DRIVER CREATION ==========');
    const newDriver = {
      uid: firebaseUid, // ← FIREBASE UID ADDED HERE
      driverId,
      name: `${personalInfo.firstName} ${personalInfo.lastName}`, // ← ADD FLAT NAME FIELD
      email: personalInfo.email, // ← ADD FLAT EMAIL FIELD
      phone: personalInfo.phone, // ← ADD FLAT PHONE FIELD
      personalInfo: {
        firstName: personalInfo.firstName,
        lastName: personalInfo.lastName,
        phone: personalInfo.phone,
        email: personalInfo.email,
        dateOfBirth: personalInfo.dateOfBirth,
        bloodGroup: personalInfo.bloodGroup,
        gender: personalInfo.gender
      },
      license: {
        licenseNumber: license.licenseNumber,
        type: license.type,
        issueDate: new Date(license.issueDate),
        expiryDate: new Date(license.expiryDate),
        issuingAuthority: license.issuingAuthority
      },
      emergencyContact: emergencyContact ? {
        name: emergencyContact.name,
        relationship: emergencyContact.relationship,
        phone: emergencyContact.phone
      } : null,
      address: address ? {
        street: address.street,
        city: address.city,
        state: address.state,
        postalCode: address.postalCode,
        country: address.country
      } : null,
      employment: req.body.employment ? {
        joinDate: req.body.employment.joinDate,
        employmentType: req.body.employment.employmentType,
        salary: req.body.employment.salary,
        employeeId: req.body.employment.employeeId || driverId
      } : null,
      bankDetails: req.body.bankDetails ? {
        bankName: req.body.bankDetails.bankName,
        accountHolderName: req.body.bankDetails.accountHolder || req.body.bankDetails.accountHolderName,
        accountNumber: req.body.bankDetails.accountNumber,
        ifscCode: req.body.bankDetails.ifscCode
      } : null,
      status,
      assignedVehicle: null,
      joinedDate: new Date(),
      createdAt: new Date(),
      updatedAt: new Date()
    };
    
    console.log('💾 Inserting driver into MongoDB drivers collection...');
    const result = await req.db.collection('drivers').insertOne(newDriver);
    console.log('✅ Driver inserted successfully into drivers collection');
    console.log('   - MongoDB _id:', result.insertedId);
    console.log('   - Firebase UID:', firebaseUid);
    console.log('   - Driver ID:', driverId);
    
    // ✅ CENTRALIZED APPROACH: Store ONLY in 'drivers' collection
    // No more dual collection approach - drivers collection is the single source of truth
    console.log('✅ Driver stored in SINGLE collection: drivers');
    console.log('   - Authentication handled via Firebase UID in drivers collection');
    console.log('   - No admin_users collection needed for drivers');
    
    // Send welcome email with password setup link
    console.log('\n📧 ========== EMAIL SENDING PROCESS ==========');
    console.log('📧 Attempting to send welcome email to:', personalInfo.email);
    try {
      // Generate password reset link using Firebase
      console.log('🔐 Generating Firebase password reset link...');
      const passwordResetLink = await admin.auth().generatePasswordResetLink(personalInfo.email);
      console.log('✅ Password reset link generated successfully');
      console.log('   Link (first 50 chars):', passwordResetLink.substring(0, 50) + '...');
      
      // Send welcome email
      console.log('📝 Generating email templates...');
      const emailHtml = getDriverWelcomeTemplate(
        personalInfo.firstName,
        personalInfo.lastName,
        personalInfo.email,
        driverId,
        passwordResetLink
      );
      
      const emailText = getDriverWelcomeText(
        personalInfo.firstName,
        personalInfo.lastName,
        personalInfo.email,
        driverId,
        passwordResetLink
      );
      console.log('✅ Email templates generated');
      
      console.log('📤 Sending email via email service...');
      await emailService.sendEmail(
        personalInfo.email,
        'Welcome to Abra Travels - Set Your Password',
        emailText,
        emailHtml
      );
      
      console.log(`✅ Welcome email sent successfully to: ${personalInfo.email}`);
      console.log('========== EMAIL SENDING COMPLETE ==========\n');
    } catch (emailError) {
      console.error('\n❌ ========== EMAIL SENDING FAILED ==========');
      console.error('Error type:', emailError.name);
      console.error('Error message:', emailError.message);
      console.error('Error code:', emailError.code);
      console.error('Full error:', emailError);
      console.error('Stack trace:', emailError.stack);
      console.error('========== EMAIL ERROR END ==========\n');
      // Don't fail the request if email fails, just log it
    }
    
    console.log('✅ Driver creation completed successfully');
    console.log('========== DRIVER CREATION COMPLETE ==========\n');
    
    res.status(201).json({
      success: true,
      message: 'Driver added successfully. Welcome email sent.',
      data: { ...newDriver, _id: result.insertedId }
    });
  } catch (error) {
    console.error('\n❌ ========== DRIVER CREATION FAILED ==========');
    console.error('Error type:', error.name);
    console.error('Error message:', error.message);
    console.error('Error code:', error.code);
    console.error('Full error:', error);
    console.error('Stack trace:', error.stack);
    console.error('========== ERROR END ==========\n');
    
    res.status(500).json({
      success: false,
      message: 'Failed to add driver',
      error: error.message
    });
  }
});
// GET /api/admin/drivers/:id - Get driver by ID
router.get('/:id', async (req, res) => {
  try {
    const query = {};
    
    // First try to find by driverId (custom ID)
    query.driverId = req.params.id;
    
    // If the ID looks like a MongoDB ObjectId, also try to find by _id
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      query.$or = [
        { driverId: req.params.id },
        { _id: new ObjectId(req.params.id) }
      ];
    }
    
    const driver = await req.db.collection('drivers').findOne(query);
    
    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    // Get assigned vehicle details if any
    let assignedVehicle = null;
    if (driver.assignedVehicle) {
      assignedVehicle = await req.db.collection('vehicles').findOne(
        { vehicleId: driver.assignedVehicle },
        { 
          projection: { 
            vehicleId: 1, 
            registrationNumber: 1, 
            make: 1, 
            model: 1,
            type: 1,
            status: 1
          } 
        }
      );
    }
    
    // Get trip history
    const trips = await req.db.collection('trips')
      .find({ driverId: driver.driverId })
      .sort({ startTime: -1 })
      .limit(10)
      .toArray();
    
    // Get performance metrics
    const totalTrips = await req.db.collection('trips')
      .countDocuments({ driverId: driver.driverId });
    
    const completedTrips = await req.db.collection('trips')
      .countDocuments({ 
        driverId: driver.driverId, 
        status: 'completed' 
      });
    
    const response = {
      ...driver,
      assignedVehicle,
      stats: {
        totalTrips,
        completedTrips,
        completionRate: totalTrips > 0 ? Math.round((completedTrips / totalTrips) * 100) : 0
      },
      recentTrips: trips
    };
    
    // Remove sensitive data
    delete response._id;
    
    res.json({
      success: true,
      data: response
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: 'Failed to fetch driver details',
      error: error.message
    });
  }
});

// PUT /api/admin/drivers/:id - Update driver details (FIXED)
router.put('/:id', async (req, res) => {
    try {
      // Build query to find the driver by ID
      const query = { driverId: req.params.id };
      
      // If the ID looks like a MongoDB ObjectId, also try to find by _id
      if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
        query.$or = [
          { driverId: req.params.id },
          { _id: new ObjectId(req.params.id) }
        ];
      }
      
      // Prepare update operations
      const updateOperations = {
        $set: {
          updatedAt: new Date()
        }
      };
      
      // Handle personalInfo updates properly
      if (req.body.personalInfo) {
        Object.keys(req.body.personalInfo).forEach(key => {
          updateOperations.$set[`personalInfo.${key}`] = req.body.personalInfo[key];
        });
      }
      
      // Handle license updates
      if (req.body.license) {
        Object.keys(req.body.license).forEach(key => {
          if (key === 'issueDate' || key === 'expiryDate') {
            updateOperations.$set[`license.${key}`] = new Date(req.body.license[key]);
          } else {
            updateOperations.$set[`license.${key}`] = req.body.license[key];
          }
        });
      }
      
      // Handle emergencyContact updates
      if (req.body.emergencyContact) {
        Object.keys(req.body.emergencyContact).forEach(key => {
          updateOperations.$set[`emergencyContact.${key}`] = req.body.emergencyContact[key];
        });
      }
      
      // Handle address updates
      if (req.body.address) {
        Object.keys(req.body.address).forEach(key => {
          updateOperations.$set[`address.${key}`] = req.body.address[key];
        });
      }
      
      // Handle direct field updates (status, name, email, phone, etc.)
      const directFields = ['status', 'name', 'email', 'phone'];
      directFields.forEach(field => {
        if (req.body[field] !== undefined) {
          updateOperations.$set[field] = req.body[field];
        }
      });
      
      // ✅ FIX: Also update personalInfo if name/email/phone are provided
      if (req.body.name) {
        updateOperations.$set['personalInfo.firstName'] = req.body.name.split(' ')[0];
        updateOperations.$set['personalInfo.lastName'] = req.body.name.split(' ').slice(1).join(' ') || '';
      }
      if (req.body.email) {
        updateOperations.$set['personalInfo.email'] = req.body.email;
      }
      if (req.body.phone) {
        updateOperations.$set['personalInfo.phone'] = req.body.phone;
      }
      
      // Perform the update
      const result = await req.db.collection('drivers').updateOne(
        query,
        updateOperations
      );
      
      if (result.matchedCount === 0) {
        return res.status(404).json({
          success: false,
          message: 'Driver not found'
        });
      }
      
      // Get updated driver data
      const updatedDriver = await req.db.collection('drivers').findOne(query);
      
      res.json({
        success: true,
        message: 'Driver updated successfully',
        data: updatedDriver
      });
    } catch (error) {
      res.status(500).json({
        success: false,
        message: 'Failed to update driver',
        error: error.message
      });
    }
  });

// ✅ NEW: GET /api/admin/drivers/:id/trips - Get driver's trips with date-based filtering
router.get('/:id/trips', async (req, res) => {
  try {
    const { status, page = 1, limit = 20, startDate, endDate } = req.query;
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    console.log(`\n🚛 FETCHING TRIPS FOR DRIVER: ${req.params.id}`);
    console.log(`   Status filter: ${status || 'all'}`);
    console.log(`   Date range: ${startDate || 'any'} to ${endDate || 'any'}`);
    
    // Build filter
    const filter = { driverId: req.params.id };
    
    // Date-based status filtering
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const todayStr = today.toISOString().split('T')[0]; // "2026-01-21"
    
    if (status && status !== 'all') {
      if (status === 'ongoing') {
        // Today's trips
        filter.scheduledDate = todayStr;
      } else if (status === 'completed') {
        // Past trips (before today)
        filter.scheduledDate = { $lt: todayStr };
      } else if (status === 'assigned' || status === 'scheduled') {
        // Future trips (after today)
        filter.scheduledDate = { $gt: todayStr };
      }
    }
    
    // Custom date range (overrides status filter)
    if (startDate || endDate) {
      filter.scheduledDate = {};
      if (startDate) filter.scheduledDate.$gte = startDate;
      if (endDate) filter.scheduledDate.$lte = endDate;
    }
    
    // Get trips
    const trips = await req.db.collection('trips')
      .find(filter)
      .sort({ scheduledDate: -1, startTime: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();
    
    const totalCount = await req.db.collection('trips').countDocuments(filter);
    
    console.log(`✅ Found ${trips.length} trips (total: ${totalCount})`);
    
    res.json({
      success: true,
      data: trips,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalCount,
        pages: Math.ceil(totalCount / parseInt(limit))
      }
    });
  } catch (error) {
    console.error('❌ Error fetching driver trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch driver trips',
      error: error.message
    });
  }
});

// DELETE /api/admin/drivers/:id - Delete a driver
router.delete('/:id', async (req, res) => {
  try {
    console.log(`[Driver Delete] Attempting to delete driver: ${req.params.id}`);
    
    // First, check if driver has any active assignments
    const driver = await req.db.collection('drivers').findOne({
      $or: [
        { driverId: req.params.id },
        { _id: ObjectId.isValid(req.params.id) ? new ObjectId(req.params.id) : null }
      ]
    });
    
    if (!driver) {
      console.log(`[Driver Delete] Driver not found: ${req.params.id}`);
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    console.log(`[Driver Delete] Found driver: ${driver.driverId}, status: ${driver.status}`);
    
    // Check for active vehicle assignment
    if (driver.status === 'active' && driver.assignedVehicle) {
      console.log(`[Driver Delete] Driver has active vehicle assignment: ${driver.assignedVehicle}`);
      return res.status(400).json({
        success: false,
        message: 'Cannot delete driver with active vehicle assignment. Please unassign the vehicle first.'
      });
    }
    
    // Check for active rosters
    const activeRosters = await req.db.collection('rosters').countDocuments({
      driverId: driver.driverId,
      status: { $in: ['pending', 'approved', 'in_progress'] }
    });
    
    if (activeRosters > 0) {
      console.log(`[Driver Delete] Driver has ${activeRosters} active rosters`);
      return res.status(400).json({
        success: false,
        message: `Cannot delete driver with ${activeRosters} active roster(s). Please reassign or complete them first.`
      });
    }
    
    // Check for active trips
    const activeTrips = await req.db.collection('trips').countDocuments({
      driverId: driver.driverId,
      status: { $in: ['scheduled', 'in_progress'] }
    });
    
    if (activeTrips > 0) {
      console.log(`[Driver Delete] Driver has ${activeTrips} active trips`);
      return res.status(400).json({
        success: false,
        message: `Cannot delete driver with ${activeTrips} active trip(s). Please reassign or complete them first.`
      });
    }
    
    // Soft delete by updating status
    console.log(`[Driver Delete] Soft deleting driver: ${driver.driverId}`);
    const updateResult = await req.db.collection('drivers').updateOne(
      { 
        $or: [
          { driverId: req.params.id },
          { _id: ObjectId.isValid(req.params.id) ? new ObjectId(req.params.id) : null }
        ]
      },
      { 
        $set: { 
          status: 'inactive',
          deletedAt: new Date(),
          updatedAt: new Date()
        } 
      }
    );
    
    console.log(`[Driver Delete] Update result:`, updateResult);
    
    // If driver was assigned to a vehicle, unassign them
    if (driver.assignedVehicle) {
      console.log(`[Driver Delete] Unassigning driver from vehicle: ${driver.assignedVehicle}`);
      await req.db.collection('vehicles').updateOne(
        { vehicleId: driver.assignedVehicle },
        { $set: { assignedDriver: null, updatedAt: new Date() } }
      );
    }
    
    console.log(`[Driver Delete] Successfully deactivated driver: ${driver.driverId}`);
    res.json({
      success: true,
      message: 'Driver deactivated successfully'
    });
  } catch (error) {
    console.error('[Driver Delete] Error:', error);
    console.error('[Driver Delete] Error stack:', error.stack);
    res.status(500).json({
      success: false,
      message: 'Failed to deactivate driver',
      error: error.message
    });
  }
});

// POST /api/admin/drivers/:id/assign-vehicle - Assign vehicle to driver
// POST /api/admin/drivers/:id/assign-vehicle - Assign vehicle to driver
// POST /api/admin/drivers/:id/assign-vehicle - Assign vehicle to driver
router.post('/:id/assign-vehicle', async (req, res) => {
  const session = req.db.client.startSession();
  
  try {
    const { vehicleId } = req.body;
    
    console.log('=== ASSIGN VEHICLE REQUEST ===');
    console.log('Driver ID:', req.params.id);
    console.log('Vehicle ID:', vehicleId);
    console.log('Request body:', req.body);
    
    if (!vehicleId) {
      return res.status(400).json({
        success: false,
        message: 'Vehicle ID is required'
      });
    }
    
    await session.withTransaction(async () => {
      // 1. Get the driver
      const driver = await req.db.collection('drivers').findOne(
        { driverId: req.params.id },
        { session }
      );
      
      if (!driver) {
        throw new Error('Driver not found');
      }
      
      console.log('Found driver:', driver.driverId);
      
      // 2. Get the vehicle - try both vehicleId and _id
      let vehicle = await req.db.collection('vehicles').findOne(
        { vehicleId: vehicleId },
        { session }
      );
      
      // If not found by vehicleId, try _id if it's a valid ObjectId
      if (!vehicle && /^[0-9a-fA-F]{24}$/.test(vehicleId)) {
        vehicle = await req.db.collection('vehicles').findOne(
          { _id: new ObjectId(vehicleId) },
          { session }
        );
      }
      
      if (!vehicle) {
        throw new Error('Vehicle not found');
      }
      
      console.log('Found vehicle:', vehicle.vehicleId || vehicle._id);
      
      // 3. Check if vehicle is already assigned to another driver
      if (vehicle.assignedDriver && 
          typeof vehicle.assignedDriver === 'object' && 
          vehicle.assignedDriver._id?.toString() !== driver._id.toString()) {
        throw new Error(`Vehicle is already assigned to another driver`);
      }
      
      // 4. If driver has another vehicle, unassign it first
      if (driver.assignedVehicle && 
          driver.assignedVehicle.toString() !== vehicle._id.toString()) {
        console.log('Unassigning old vehicle:', driver.assignedVehicle);
        
        // Remove this driver from the old vehicle
        await req.db.collection('vehicles').updateOne(
          { 
            $or: [
              { _id: new ObjectId(driver.assignedVehicle) },
              { vehicleId: driver.assignedVehicle }
            ]
          },
          { 
            $set: { 
              assignedDriver: null,
              updatedAt: new Date()
            } 
          },
          { session }
        );
      }
      
      // 5. ✅ UPDATE DRIVER with vehicle info (TWO-WAY SYNC)
      await req.db.collection('drivers').updateOne(
        { _id: driver._id },
        { 
          $set: { 
            assignedVehicle: vehicle._id, // ✅ Use MongoDB ObjectId
            updatedAt: new Date()
          } 
        },
        { session }
      );
      
      console.log('✅ Driver updated with vehicle ID:', vehicle._id);
      
      // 6. ✅ UPDATE VEHICLE with driver info (TWO-WAY SYNC)
      await req.db.collection('vehicles').updateOne(
        { _id: vehicle._id },
        { 
          $set: { 
            assignedDriver: {
              _id: driver._id,
              driverId: driver.driverId,
              name: `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim(),
              email: driver.personalInfo?.email || driver.email,
              phone: driver.personalInfo?.phone || driver.phone
            },
            status: 'active',
            updatedAt: new Date()
          } 
        },
        { session }
      );
      
      console.log('✅ Vehicle updated with driver info');
      
      // 7. 🔔 TRIGGER NOTIFICATION
      try {
        const targetUserId = driver.firebaseUid || driver.uid || driver.driverId;
        
        console.log(`🔔 Sending notification to Driver: ${targetUserId}`);

        await createNotification(req.db, {
          userId: targetUserId, 
          type: 'vehicle_assigned', 
          title: 'New Vehicle Assigned 🚗',
          body: `You have been assigned to ${vehicle.make || 'Vehicle'} ${vehicle.model || ''} (${vehicle.registrationNumber})`,
          data: {
            vehicleId: vehicle._id.toString(),
            vehicleName: `${vehicle.make || ''} ${vehicle.model || ''}`.trim(),
            registrationNumber: vehicle.registrationNumber
          },
          priority: 'high',
          category: 'system'
        });
        console.log('✅ Notification sent successfully');
      } catch (notifyError) {
        console.error('❌ Failed to send driver notification:', notifyError.message);
      }
    });
    
    await session.endSession();
    console.log('=== ASSIGNMENT SUCCESSFUL ===');
    
    res.json({
      success: true,
      message: 'Vehicle assigned to driver successfully'
    });
    
  } catch (error) {
    await session.endSession();
    console.error('=== ASSIGN VEHICLE ERROR ===');
    console.error('Error:', error.message);
    console.error('Stack:', error.stack);
    
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to assign vehicle to driver'
    });
  }
});


// POST /api/admin/drivers/:id/unassign-vehicle - Unassign vehicle from driver
// POST /api/admin/drivers/:id/unassign-vehicle - Unassign vehicle from driver
router.post('/:id/unassign-vehicle', async (req, res) => {
  const session = req.db.client.startSession();
  
  try {
    await session.withTransaction(async () => {
      // 1. Get the driver
      const driver = await req.db.collection('drivers').findOne(
        { 
          $or: [
            { driverId: req.params.id },
            { _id: new ObjectId(req.params.id) }
          ]
        },
        { session }
      );
      
      if (!driver) {
        throw new Error('Driver not found');
      }
      
      if (!driver.assignedVehicle) {
        throw new Error('Driver does not have an assigned vehicle');
      }
      
      const vehicleObjectId = driver.assignedVehicle;
      
      // 2. ✅ Update driver - remove vehicle (TWO-WAY SYNC)
      await req.db.collection('drivers').updateOne(
        { _id: driver._id },
        { 
          $set: { 
            assignedVehicle: null,
            updatedAt: new Date()
          } 
        },
        { session }
      );
      
      console.log('✅ Driver updated - vehicle removed');
      
      // 3. ✅ Update vehicle - remove driver (TWO-WAY SYNC)
      await req.db.collection('vehicles').updateOne(
        { _id: vehicleObjectId },
        { 
          $set: { 
            assignedDriver: null,
            updatedAt: new Date()
          } 
        },
        { session }
      );
      
      console.log('✅ Vehicle updated - driver removed');
    });
    
    await session.endSession();
    
    res.json({
      success: true,
      message: 'Vehicle unassigned from driver successfully'
    });
  } catch (error) {
    await session.endSession();
    
    res.status(500).json({
      success: false,
      message: error.message || 'Failed to unassign vehicle from driver'
    });
  }
});

// GET /api/admin/drivers/:id/trips - Get driver's trip history (FIXED)
router.get('/:id/trips', async (req, res) => {
    try {
      const { page = 1, limit = 10, status, startDate, endDate } = req.query;
      const skip = (parseInt(page) - 1) * parseInt(limit);
      
      // Build query to find driver - fix the ObjectId issue
      let driverQuery = { driverId: req.params.id };
      
      // Only add ObjectId query if the ID is a valid MongoDB ObjectId format
      if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
        driverQuery = {
          $or: [
            { driverId: req.params.id },
            { _id: new ObjectId(req.params.id) }
          ]
        };
      }
      
      // Find the driver to get the driverId
      const driver = await req.db.collection('drivers').findOne(driverQuery);
      
      if (!driver) {
        return res.status(404).json({
          success: false,
          message: 'Driver not found'
        });
      }
      
      // Build query for trips using the driver's driverId
      const query = { driverId: driver.driverId };
      
      if (status) {
        query.status = status;
      }
      
      if (startDate || endDate) {
        query.startTime = {};
        if (startDate) query.startTime.$gte = new Date(startDate);
        if (endDate) query.startTime.$lte = new Date(endDate);
      }
      
      // Get trips with pagination
      const trips = await req.db.collection('trips')
        .find(query)
        .sort({ startTime: -1 })
        .skip(skip)
        .limit(parseInt(limit))
        .toArray();
      
      const totalTrips = await req.db.collection('trips').countDocuments(query);
      
      // Get trip statistics
      const stats = {
        total: totalTrips,
        completed: await req.db.collection('trips').countDocuments({ 
          ...query, 
          status: 'completed' 
        }),
        inProgress: await req.db.collection('trips').countDocuments({ 
          ...query, 
          status: 'in_progress' 
        }),
        cancelled: await req.db.collection('trips').countDocuments({ 
          ...query, 
          status: 'cancelled' 
        })
      };
      
      res.json({
        success: true,
        data: trips,
        pagination: {
          page: parseInt(page),
          limit: parseInt(limit),
          total: totalTrips,
          pages: Math.ceil(totalTrips / parseInt(limit))
        },
        stats
      });
    } catch (error) {
      res.status(500).json({
        success: false,
        message: 'Failed to fetch driver trips',
        error: error.message
      });
    }
  });

// POST /api/admin/drivers/:id/documents - Upload driver document
router.post('/:id/documents', async (req, res) => {
  try {
    const { documentType, documentName, documentUrl, expiryDate } = req.body;
    
    if (!documentType || !documentName) {
      return res.status(400).json({
        success: false,
        message: 'Document type and name are required'
      });
    }
    
    // Find the driver
    const driverQuery = { driverId: req.params.id };
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      driverQuery.$or = [
        { driverId: req.params.id },
        { _id: new ObjectId(req.params.id) }
      ];
    }
    
    const driver = await req.db.collection('drivers').findOne(driverQuery);
    
    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    // Create new document
    const newDocument = {
      id: new ObjectId().toString(),
      documentType,
      documentName,
      documentUrl: documentUrl || '',
      expiryDate: expiryDate ? new Date(expiryDate) : null,
      uploadedAt: new Date(),
      uploadedBy: req.user?.uid || 'admin'
    };
    
    // Add document to driver's documents array
    await req.db.collection('drivers').updateOne(
      { _id: driver._id },
      { 
        $push: { documents: newDocument },
        $set: { updatedAt: new Date() }
      }
    );
    
    res.json({
      success: true,
      message: 'Document added successfully',
      data: newDocument
    });
  } catch (error) {
    console.error('Error adding driver document:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to add document',
      error: error.message
    });
  }
});

// DELETE /api/admin/drivers/:id/documents/:documentId - Delete driver document
router.delete('/:id/documents/:documentId', async (req, res) => {
  try {
    // Find the driver
    const driverQuery = { driverId: req.params.id };
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      driverQuery.$or = [
        { driverId: req.params.id },
        { _id: new ObjectId(req.params.id) }
      ];
    }
    
    const driver = await req.db.collection('drivers').findOne(driverQuery);
    
    if (!driver) {
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    // Remove document from driver's documents array
    const result = await req.db.collection('drivers').updateOne(
      { _id: driver._id },
      { 
        $pull: { documents: { id: req.params.documentId } },
        $set: { updatedAt: new Date() }
      }
    );
    
    if (result.modifiedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Document not found'
      });
    }
    
    res.json({
      success: true,
      message: 'Document deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting driver document:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete document',
      error: error.message
    });
  }
});

// POST /api/admin/drivers/bulk-import - Bulk import drivers from CSV
router.post('/bulk-import', async (req, res) => {
  console.log('\n🚗 ========== BULK DRIVER IMPORT STARTED ==========');
  console.log('📥 Request body:', JSON.stringify(req.body, null, 2));
  
  try {
    const { drivers } = req.body;
    
    if (!drivers || !Array.isArray(drivers) || drivers.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'No driver data provided'
      });
    }
    
    console.log(`📊 Processing ${drivers.length} drivers for bulk import`);
    
    const results = {
      successful: [],
      failed: [],
      skipped: []
    };
    
    // Process each driver
    for (let i = 0; i < drivers.length; i++) {
      const driverData = drivers[i];
      console.log(`\n📋 Processing driver ${i + 1}/${drivers.length}: ${driverData.firstName} ${driverData.lastName}`);
      
      try {
        // Generate unique driver ID
        const driverId = `DRV${Date.now()}${Math.floor(Math.random() * 1000).toString().padStart(3, '0')}`;
        
        // Check if driver already exists
        const existingDriver = await req.db.collection('drivers').findOne({
          $or: [
            { 'personalInfo.phone': driverData.phone },
            { 'personalInfo.email': driverData.email },
            { 'license.licenseNumber': driverData.licenseNumber }
          ]
        });
        
        if (existingDriver) {
          console.log(`⚠️  Driver already exists: ${driverData.email}`);
          results.skipped.push({
            data: driverData,
            reason: 'Driver with same phone, email, or license already exists'
          });
          continue;
        }
        
        // Create Firebase Auth user
        console.log(`🔐 Creating Firebase user for: ${driverData.email}`);
        let firebaseUid = null;
        
        try {
          const tempPassword = Math.random().toString(36).slice(-12) + 'Aa1!';
          const firebaseUser = await admin.auth().createUser({
            email: driverData.email,
            emailVerified: false,
            password: tempPassword,
            displayName: `${driverData.firstName} ${driverData.lastName}`,
            disabled: false
          });
          
          firebaseUid = firebaseUser.uid;
          
          // Set custom claims
          await admin.auth().setCustomUserClaims(firebaseUid, {
            role: 'driver',
            driverId: driverId
          });
          
          console.log(`✅ Firebase user created: ${firebaseUid}`);
        } catch (firebaseError) {
          if (firebaseError.code === 'auth/email-already-exists') {
            const existingFirebaseUser = await admin.auth().getUserByEmail(driverData.email);
            firebaseUid = existingFirebaseUser.uid;
            console.log(`⚠️  Using existing Firebase UID: ${firebaseUid}`);
          } else {
            throw firebaseError;
          }
        }
        
        // Create MongoDB driver record
        const newDriver = {
          uid: firebaseUid,
          driverId,
          name: `${driverData.firstName} ${driverData.lastName}`,
          email: driverData.email,
          phone: driverData.phone,
          personalInfo: {
            firstName: driverData.firstName,
            lastName: driverData.lastName,
            phone: driverData.phone,
            email: driverData.email,
            dateOfBirth: driverData.dob ? new Date(driverData.dob) : null,
            bloodGroup: driverData.bloodGroup,
            gender: driverData.gender
          },
          license: {
            licenseNumber: driverData.licenseNumber,
            type: driverData.licenseType,
            issueDate: new Date(driverData.issueDate),
            expiryDate: new Date(driverData.expiryDate),
            issuingAuthority: driverData.issuingAuthority
          },
          emergencyContact: driverData.emergencyContactName ? {
            name: driverData.emergencyContactName,
            relationship: driverData.emergencyContactRelationship,
            phone: driverData.emergencyContactPhone
          } : null,
          address: driverData.street ? {
            street: driverData.street,
            city: driverData.city,
            state: driverData.state,
            postalCode: driverData.postalCode,
            country: driverData.country
          } : null,
          employment: driverData.employeeId ? {
            joinDate: driverData.joinDate ? new Date(driverData.joinDate) : new Date(),
            employmentType: driverData.employmentType,
            salary: driverData.salary ? parseFloat(driverData.salary) : null,
            employeeId: driverData.employeeId
          } : null,
          bankDetails: driverData.bankName ? {
            bankName: driverData.bankName,
            accountHolderName: driverData.accountHolder,
            accountNumber: driverData.accountNumber,
            ifscCode: driverData.ifscCode
          } : null,
          status: driverData.status || 'active',
          assignedVehicle: null,
          joinedDate: new Date(),
          createdAt: new Date(),
          updatedAt: new Date()
        };
        
        // Insert into drivers collection
        const result = await req.db.collection('drivers').insertOne(newDriver);
        console.log(`✅ Driver inserted into drivers collection: ${result.insertedId}`);
        
        // ✅ CENTRALIZED: No admin_users insertion needed
        // Driver authentication handled via Firebase UID in drivers collection
        console.log(`✅ Driver authentication handled via Firebase UID in drivers collection`);
        
        // Send welcome email
        try {
          const passwordResetLink = await admin.auth().generatePasswordResetLink(driverData.email);
          const emailHtml = getDriverWelcomeTemplate(
            driverData.firstName,
            driverData.lastName,
            driverData.email,
            driverId,
            passwordResetLink
          );
          const emailText = getDriverWelcomeText(
            driverData.firstName,
            driverData.lastName,
            driverData.email,
            driverId,
            passwordResetLink
          );
          
          await emailService.sendEmail(
            driverData.email,
            'Welcome to Abra Travels - Set Your Password',
            emailText,
            emailHtml
          );
          console.log(`✅ Welcome email sent to: ${driverData.email}`);
        } catch (emailError) {
          console.error(`❌ Failed to send email to ${driverData.email}:`, emailError.message);
        }
        
        results.successful.push({
          driverId,
          name: `${driverData.firstName} ${driverData.lastName}`,
          email: driverData.email
        });
        
      } catch (error) {
        console.error(`❌ Failed to process driver ${driverData.firstName} ${driverData.lastName}:`, error.message);
        results.failed.push({
          data: driverData,
          error: error.message
        });
      }
    }
    
    console.log('\n✅ ========== BULK DRIVER IMPORT COMPLETED ==========');
    console.log(`📊 Results: ${results.successful.length} successful, ${results.failed.length} failed, ${results.skipped.length} skipped`);
    
    res.status(201).json({
      success: true,
      message: `Bulk import completed. ${results.successful.length} drivers imported successfully.`,
      results
    });
    
  } catch (error) {
    console.error('\n❌ ========== BULK DRIVER IMPORT FAILED ==========');
    console.error('Error:', error.message);
    console.error('Stack:', error.stack);
    
    res.status(500).json({
      success: false,
      message: 'Failed to process bulk driver import',
      error: error.message
    });
  }
});

// POST /api/admin/drivers/:id/send-password-reset - Send password reset email to driver
router.post('/:id/send-password-reset', async (req, res) => {
  console.log('\n📧 ========== SEND PASSWORD RESET EMAIL ==========');
  console.log('🔍 Step 1: Request received');
  console.log('   Driver ID:', req.params.id);
  console.log('   Request headers:', JSON.stringify(req.headers, null, 2));
  
  try {
    // Find the driver
    console.log('\n🔍 Step 2: Building driver query...');
    const driverQuery = { driverId: req.params.id };
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      driverQuery.$or = [
        { driverId: req.params.id },
        { _id: new ObjectId(req.params.id) }
      ];
    }
    console.log('   Query:', JSON.stringify(driverQuery, null, 2));
    
    console.log('\n🔍 Step 3: Searching for driver in database...');
    const driver = await req.db.collection('drivers').findOne(driverQuery);
    console.log('   Driver found:', driver ? 'YES' : 'NO');
    
    if (!driver) {
      console.log('❌ Driver not found in database');
      return res.status(404).json({
        success: false,
        message: 'Driver not found'
      });
    }
    
    console.log('   Driver data:', JSON.stringify({
      driverId: driver.driverId,
      personalInfo: driver.personalInfo,
      hasEmail: !!driver.personalInfo?.email
    }, null, 2));
    
    const email = driver.personalInfo?.email;
    const firstName = driver.personalInfo?.firstName;
    const lastName = driver.personalInfo?.lastName;
    
    console.log('\n🔍 Step 4: Validating email...');
    console.log('   Email:', email);
    console.log('   First Name:', firstName);
    console.log('   Last Name:', lastName);
    
    if (!email || email === 'N/A') {
      console.log('❌ Driver does not have a valid email address');
      return res.status(400).json({
        success: false,
        message: 'Driver does not have a valid email address'
      });
    }
    
    console.log('✅ Driver found:', firstName, lastName);
    console.log('📧 Email:', email);
    
    // Generate password reset link using Firebase
    console.log('\n🔍 Step 5: Generating Firebase password reset link...');
    console.log('   Firebase Admin initialized:', !!admin.auth);
    
    try {
      // First, check if Firebase user exists
      console.log('🔍 Step 5a: Checking if Firebase user exists...');
      let firebaseUser = null;
      try {
        firebaseUser = await admin.auth().getUserByEmail(email);
        console.log('✅ Firebase user found:', firebaseUser.uid);
      } catch (userError) {
        if (userError.code === 'auth/user-not-found') {
          console.log('⚠️  Firebase user not found, creating new user...');
          
          // Create Firebase user with temporary password
          const tempPassword = Math.random().toString(36).slice(-12) + 'Aa1!';
          firebaseUser = await admin.auth().createUser({
            email: email,
            emailVerified: false,
            password: tempPassword,
            displayName: `${firstName} ${lastName}`,
            disabled: false
          });
          
          console.log('✅ Firebase user created:', firebaseUser.uid);
          
          // Set custom claims for driver role
          await admin.auth().setCustomUserClaims(firebaseUser.uid, {
            role: 'driver',
            driverId: driver.driverId
          });
          console.log('✅ Custom claims set for driver');
          
          // Update MongoDB driver record with Firebase UID
          await req.db.collection('drivers').updateOne(
            { driverId: driver.driverId },
            { 
              $set: { 
                uid: firebaseUser.uid,
                updatedAt: new Date()
              } 
            }
          );
          console.log('✅ Driver record updated with Firebase UID');
          
        } else {
          throw userError;
        }
      }
      
      // Now generate password reset link
      console.log('🔍 Step 5b: Generating password reset link...');
      const passwordResetLink = await admin.auth().generatePasswordResetLink(email);
      console.log('✅ Password reset link generated successfully');
      console.log('   Link length:', passwordResetLink.length);
      console.log('   Link preview:', passwordResetLink.substring(0, 50) + '...');
      
      // Send password reset email
      console.log('\n🔍 Step 6: Preparing email templates...');
      const emailHtml = getDriverWelcomeTemplate(
        firstName,
        lastName,
        email,
        driver.driverId,
        passwordResetLink
      );
      
      const emailText = getDriverWelcomeText(
        firstName,
        lastName,
        email,
        driver.driverId,
        passwordResetLink
      );
      
      console.log('✅ Email templates generated');
      console.log('   HTML length:', emailHtml.length);
      console.log('   Text length:', emailText.length);
      
      console.log('\n🔍 Step 7: Sending email via email service...');
      console.log('   To:', email);
      console.log('   Subject: Password Reset - Abra Travels');
      
      await emailService.sendEmail(
        email,
        'Password Reset - Abra Travels',
        emailText,
        emailHtml
      );
      
      console.log('✅ Password reset email sent successfully');
      console.log('========== EMAIL SENT COMPLETE ==========\n');
      
      res.json({
        success: true,
        message: `Password reset email sent successfully to ${email}`
      });
      
    } catch (firebaseError) {
      console.error('\n❌ Firebase Error:');
      console.error('   Error name:', firebaseError.name);
      console.error('   Error message:', firebaseError.message);
      console.error('   Error code:', firebaseError.code);
      console.error('   Full error:', JSON.stringify(firebaseError, null, 2));
      throw firebaseError;
    }
    
  } catch (error) {
    console.error('\n❌ ========== SEND PASSWORD RESET FAILED ==========');
    console.error('Error type:', error.constructor.name);
    console.error('Error name:', error.name);
    console.error('Error message:', error.message);
    console.error('Error code:', error.code);
    console.error('Error details:', JSON.stringify(error, Object.getOwnPropertyNames(error), 2));
    console.error('Stack trace:', error.stack);
    console.error('========== ERROR END ==========\n');
    
    res.status(500).json({
      success: false,
      message: 'Failed to send password reset email',
      error: error.message,
      errorCode: error.code,
      errorName: error.name
    });
  }
});

// ✅ NEW: GET /api/admin/drivers/:id/trips - Get driver's trips with date-based filtering
router.get('/:id/trips', async (req, res) => {
  try {
    const { status, page = 1, limit = 20, startDate, endDate } = req.query;
    const skip = (parseInt(page) - 1) * parseInt(limit);
    
    console.log(`\n🚛 FETCHING TRIPS FOR DRIVER: ${req.params.id}`);
    console.log(`   Status filter: ${status || 'all'}`);
    console.log(`   Date range: ${startDate || 'any'} to ${endDate || 'any'}`);
    
    // Build filter
    const filter = { driverId: req.params.id };
    
    // Date-based status filtering
    if (status && status !== 'all') {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      const todayStr = today.toISOString().split('T')[0];
      
      if (status === 'ongoing') {
        // Today's trips
        filter.$or = [
          { scheduledDate: todayStr },
          {
            scheduledDate: {
              $gte: today,
              $lt: new Date(today.getTime() + 24 * 60 * 60 * 1000)
            }
          }
        ];
      } else if (status === 'completed') {
        // Past trips (before today)
        filter.$or = [
          { scheduledDate: { $lt: todayStr } },
          { scheduledDate: { $lt: today } }
        ];
      } else if (status === 'assigned' || status === 'scheduled') {
        // Future trips (after today)
        filter.$or = [
          { scheduledDate: { $gt: todayStr } },
          { scheduledDate: { $gt: today } }
        ];
      }
    }
    
    // Custom date range filter
    if (startDate || endDate) {
      filter.scheduledDate = {};
      if (startDate) {
        filter.scheduledDate.$gte = startDate;
      }
      if (endDate) {
        filter.scheduledDate.$lte = endDate;
      }
    }
    
    console.log('   Filter:', JSON.stringify(filter));
    
    // Get trips
    const trips = await req.db.collection('trips')
      .find(filter)
      .sort({ scheduledDate: -1, startTime: -1 })
      .skip(skip)
      .limit(parseInt(limit))
      .toArray();
    
    const totalCount = await req.db.collection('trips').countDocuments(filter);
    
    console.log(`✅ Found ${trips.length} trips (total: ${totalCount})`);
    
    res.json({
      success: true,
      data: trips,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: totalCount,
        pages: Math.ceil(totalCount / parseInt(limit))
      }
    });
  } catch (error) {
    console.error('❌ Error fetching driver trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch driver trips',
      error: error.message
    });
  }
});

module.exports = router;
