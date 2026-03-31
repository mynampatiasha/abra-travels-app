const express = require('express');
const router = express.Router();
const { body, validationResult, param, query } = require('express-validator');

// Validation middleware for vehicle creation
const validateVehicle = [
  body('registrationNumber')
    .matches(/^[A-Z]{2}[0-9]{2}[A-Z]{1,2}[0-9]{4}$/)
    .withMessage('Invalid registration number format (e.g., KA01AB1234)'),
  body('vehicleType')
    .isIn(['Bus', 'Van', 'Car', 'Truck', 'Mini Bus'])
    .withMessage('Vehicle type must be one of: Bus, Van, Car, Truck, Mini Bus'),
  body('makeModel')
    .isLength({ min: 2, max: 100 })
    .trim()
    .withMessage('Make and model must be 2-100 characters'),
  body('yearOfManufacture')
    .isInt({ min: 1990, max: new Date().getFullYear() })
    .withMessage(`Year must be between 1990 and ${new Date().getFullYear()}`),
  body('engineType')
    .isIn(['Diesel', 'Petrol', 'CNG', 'Electric', 'Hybrid'])
    .withMessage('Engine type must be one of: Diesel, Petrol, CNG, Electric, Hybrid'),
  body('engineCapacity')
    .isFloat({ min: 100, max: 10000 })
    .withMessage('Engine capacity must be between 100-10000 CC'),
  body('seatingCapacity')
    .isInt({ min: 1, max: 100 })
    .withMessage('Seating capacity must be between 1-100'),
  body('mileage')
    .isFloat({ min: 0, max: 50 })
    .withMessage('Mileage must be between 0-50 km/l')
];

// Validation middleware for vehicle updates
const validateVehicleUpdate = [
  body('registrationNumber')
    .optional()
    .matches(/^[A-Z]{2}[0-9]{2}[A-Z]{1,2}[0-9]{4}$/)
    .withMessage('Invalid registration number format'),
  body('vehicleType')
    .optional()
    .isIn(['Bus', 'Van', 'Car', 'Truck', 'Mini Bus'])
    .withMessage('Invalid vehicle type'),
  body('makeModel')
    .optional()
    .isLength({ min: 2, max: 100 })
    .trim()
    .withMessage('Make and model must be 2-100 characters'),
  body('yearOfManufacture')
    .optional()
    .isInt({ min: 1990, max: new Date().getFullYear() })
    .withMessage('Invalid year of manufacture'),
  body('engineType')
    .optional()
    .isIn(['Diesel', 'Petrol', 'CNG', 'Electric', 'Hybrid'])
    .withMessage('Invalid engine type'),
  body('engineCapacity')
    .optional()
    .isFloat({ min: 100, max: 10000 })
    .withMessage('Invalid engine capacity'),
  body('seatingCapacity')
    .optional()
    .isInt({ min: 1, max: 100 })
    .withMessage('Invalid seating capacity'),
  body('mileage')
    .optional()
    .isFloat({ min: 0, max: 50 })
    .withMessage('Invalid mileage')
];

// Helper function to generate vehicle ID
function generateVehicleId() {
  return `VH${Date.now().toString().slice(-6)}`;
}

// Helper function to handle validation errors
function handleValidationErrors(req, res, next) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      success: false,
      message: 'Validation error',
      errors: errors.array().map(err => err.msg)
    });
  }
  next();
}

// ============================================
// ADD THIS SECTION AFTER THE EXISTING HELPER FUNCTIONS
// (After handleValidationErrors function and before routes)
// ============================================

// Enhanced helper function to check available seats with real-time data
async function checkAvailableSeats(db, vehicleId, requestedSeats = 1, options = {}) {
  try {
    // Get vehicle details
    const vehicle = await db.collection('vehicles').findOne({
      $or: [
        { vehicleId: vehicleId },
        { _id: vehicleId },
        { registrationNumber: vehicleId }
      ]
    });

    if (!vehicle) {
      return {
        available: false,
        message: 'Vehicle not found',
        details: null
      };
    }

    // Get total seating capacity from multiple possible fields
    const totalCapacity = vehicle.capacity?.passengers || 
                         vehicle.seatingCapacity || 
                         vehicle.seatCapacity || 
                         0;

    // Enhanced seat calculation - check multiple collections
    const today = new Date();
    const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());
    const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);

    // Count from rosters (primary source)
    const activeRosters = await db.collection('rosters').countDocuments({
      $or: [
        { vehicleId: vehicle.vehicleId },
        { vehicleNumber: vehicle.registrationNumber }
      ],
      status: { $in: ['assigned', 'active', 'in_progress', 'pending'] },
      // Optional date filter for today's rosters
      ...(options.dateFilter && {
        $or: [
          { startDate: { $lte: todayEnd }, endDate: { $gte: todayStart } },
          { createdAt: { $gte: todayStart, $lt: todayEnd } }
        ]
      })
    });

    // Count from active trips as backup
    const activeTrips = await db.collection('trips').aggregate([
      {
        $match: {
          vehicleId: vehicle.vehicleId,
          status: { $in: ['scheduled', 'in_progress', 'ongoing'] },
          ...(options.dateFilter && {
            scheduledDate: { $gte: todayStart, $lt: todayEnd }
          })
        }
      },
      {
        $group: {
          _id: null,
          totalPassengers: { $sum: '$passengerCount' }
        }
      }
    ]).toArray();

    const tripPassengers = activeTrips.length > 0 ? activeTrips[0].totalPassengers : 0;
    
    // Use the higher count between rosters and trips
    const assignedSeats = Math.max(activeRosters, tripPassengers);
    
    // Reserve 1 seat for driver
    const driverSeats = vehicle.assignedDriver ? 1 : 0;
    const availableSeats = Math.max(0, totalCapacity - assignedSeats - driverSeats);

    // Calculate utilization percentage
    const utilizationPercentage = totalCapacity > 0 
      ? ((assignedSeats + driverSeats) / totalCapacity * 100).toFixed(1)
      : 0;

    return {
      available: availableSeats >= requestedSeats,
      message: availableSeats >= requestedSeats 
        ? `${availableSeats} seats available` 
        : `Insufficient seats. Only ${availableSeats} seats available (${assignedSeats} assigned + ${driverSeats} driver)`,
      details: {
        totalCapacity,
        assignedSeats,
        driverSeats,
        availableSeats,
        requestedSeats,
        utilizationPercentage: parseFloat(utilizationPercentage),
        vehicleInfo: {
          vehicleId: vehicle.vehicleId,
          registrationNumber: vehicle.registrationNumber,
          type: vehicle.type || vehicle.vehicleType,
          status: vehicle.status
        }
      }
    };
  } catch (error) {
    console.error('Error checking available seats:', error);
    return {
      available: false,
      message: 'Error checking seat availability',
      details: null,
      error: error.message
    };
  }
}

// Add this new route to check seat availability
// @route   GET /api/admin/vehicles/:id/available-seats
// @desc    Check available seats for a vehicle
// @access  Private (Admin)
router.get('/:id/available-seats', async (req, res) => {
  try {
    const vehicleId = req.params.id;
    const requestedSeats = parseInt(req.query.requestedSeats) || 1;

    const seatCheck = await checkAvailableSeats(req.db, vehicleId, requestedSeats);

    res.json({
      success: seatCheck.available,
      message: seatCheck.message,
      data: seatCheck.details
    });
  } catch (error) {
    console.error('Check available seats error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while checking seat availability'
    });
  }
});

// Add this validation middleware for booking/assignment routes
const validateSeatCapacity = async (req, res, next) => {
  try {
    const { vehicleId, numberOfPassengers } = req.body;

    if (!vehicleId || !numberOfPassengers) {
      return res.status(400).json({
        success: false,
        message: 'Vehicle ID and number of passengers are required'
      });
    }

    const seatCheck = await checkAvailableSeats(req.db, vehicleId, numberOfPassengers);

    if (!seatCheck.available) {
      return res.status(400).json({
        success: false,
        message: seatCheck.message,
        details: seatCheck.details
      });
    }

    // Attach seat details to request for later use
    req.seatValidation = seatCheck.details;
    next();
  } catch (error) {
    console.error('Seat capacity validation error:', error);
    res.status(500).json({
      success: false,
      message: 'Error validating seat capacity'
    });
  }
};

// Example: Apply validation to booking creation route
// @route   POST /api/admin/bookings
// @desc    Create a new booking with seat validation
// @access  Private (Admin)
router.post('/bookings', [
  body('vehicleId').notEmpty().withMessage('Vehicle ID is required'),
  body('numberOfPassengers')
    .isInt({ min: 1 })
    .withMessage('Number of passengers must be at least 1'),
  validateSeatCapacity  // Add this middleware
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: errors.array().map(err => err.msg)
      });
    }

    // Create booking logic here
    const bookingData = {
      ...req.body,
      seatValidation: req.seatValidation, // Include validation details
      createdAt: new Date(),
      updatedAt: new Date()
    };

    // Insert booking into database
    const result = await req.db.collection('bookings').insertOne(bookingData);

    res.status(201).json({
      success: true,
      message: 'Booking created successfully',
      data: bookingData,
      seatInfo: req.seatValidation
    });
  } catch (error) {
    console.error('Create booking error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while creating booking'
    });
  }
});



// @route   GET /api/admin/vehicles
// @desc    Get all vehicles with pagination and filtering
// @access  Private (Admin)
// @route   GET /api/admin/vehicles
// @desc    Get all vehicles with pagination and filtering
// @access  Private (Admin)
router.get('/', [
  query('page').optional().isInt({ min: 1 }).withMessage('Page must be a positive integer'),
  query('limit').optional().isInt({ min: 1, max: 100 }).withMessage('Limit must be 1-100'),
  query('status').optional().isIn(['Active', 'Inactive', 'Maintenance', 'Retired', 'ACTIVE', 'INACTIVE', 'MAINTENANCE', 'RETIRED']),
  query('vehicleType').optional().isIn(['Bus', 'Van', 'Car', 'Truck', 'Mini Bus']),
  query('engineType').optional().isIn(['Diesel', 'Petrol', 'CNG', 'Electric', 'Hybrid'])
], async (req, res) => {
  try {
    // Handle validation errors
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Invalid query parameters',
        errors: errors.array().map(err => err.msg)
      });
    }

    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const skip = (page - 1) * limit;

    // Build filter object
    let filter = {};
    if (req.query.status) {
      // Handle both uppercase and mixed case status
      filter.status = new RegExp(`^${req.query.status}$`, 'i');
    }
    if (req.query.vehicleType) filter.vehicleType = req.query.vehicleType;
    if (req.query.engineType) filter.engineType = req.query.engineType;
    if (req.query.search) {
      filter.$or = [
        { registrationNumber: { $regex: req.query.search, $options: 'i' } },
        { makeModel: { $regex: req.query.search, $options: 'i' } },
        { vehicleId: { $regex: req.query.search, $options: 'i' } },
        { make: { $regex: req.query.search, $options: 'i' } },
        { model: { $regex: req.query.search, $options: 'i' } }
      ];
    }

    console.log('[Vehicle API] Fetching vehicles with filter:', JSON.stringify(filter));

    const vehicles = await req.db.collection('vehicles')
      .find(filter)
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .toArray();

    console.log(`[Vehicle API] Found ${vehicles.length} vehicles`);

    const total = await req.db.collection('vehicles').countDocuments(filter);

    // ✅ POPULATE ASSIGNED DRIVER DETAILS & NORMALIZE VEHICLE DATA
    const vehiclesWithDrivers = await Promise.all(
      vehicles.map(async (vehicle) => {
        let populatedVehicle = { ...vehicle };

        // 🔥 NORMALIZE VEHICLE DATA STRUCTURE
        // Ensure consistent naming and data availability
        populatedVehicle.name = vehicle.name || 
                               vehicle.vehicleNumber || 
                               vehicle.makeModel || 
                               vehicle.registrationNumber || 
                               `Vehicle ${vehicle.vehicleId}`;
        
        populatedVehicle.vehicleNumber = vehicle.vehicleNumber || 
                                        vehicle.registrationNumber || 
                                        vehicle.vehicleId;
        
        // 🔥 NORMALIZE SEAT CAPACITY - prioritize capacity.passengers
        populatedVehicle.seatCapacity = vehicle.capacity?.passengers || 
                                       vehicle.seatCapacity || 
                                       vehicle.seatingCapacity || 
                                       4; // default fallback
        
        // 🔥 CALCULATE REAL-TIME ASSIGNED CUSTOMERS COUNT
        // Query rosters collection for today's assigned customers
        // Use vehicleNumber (registration) instead of vehicleId
        const assignedRostersCount = await req.db.collection('rosters').countDocuments({
          vehicleNumber: vehicle.registrationNumber,
          status: { $in: ['assigned', 'pending', 'active', 'in_progress'] }
        });
        
        populatedVehicle.assignedCustomersCount = assignedRostersCount;
        populatedVehicle.assignedCustomers = vehicle.assignedCustomers || [];

        // Calculate expiring documents
        if (vehicle.documents && vehicle.documents.length > 0) {
          const expiringDocs = vehicle.documents.filter(doc => {
            if (!doc.expiryDate) return false;
            const expiryDate = new Date(doc.expiryDate);
            const thirtyDaysFromNow = new Date();
            thirtyDaysFromNow.setDate(thirtyDaysFromNow.getDate() + 30);
            return expiryDate <= thirtyDaysFromNow;
          });
          populatedVehicle.expiringDocuments = expiringDocs;
        } else {
          populatedVehicle.expiringDocuments = [];
        }

        // Populate driver details if assigned
        if (vehicle.assignedDriver) {
          // Check if assignedDriver is already an object (has name field) or just a string/ID
          if (typeof vehicle.assignedDriver === 'object' && vehicle.assignedDriver.name) {
            // Already populated - use as is
            console.log(`[Vehicle API] Vehicle ${vehicle.vehicleId} has driver object: ${vehicle.assignedDriver.name}`);
            populatedVehicle.assignedDriver = vehicle.assignedDriver;
          } else {
            // It's a string ID - need to look up driver details
            const driverId = typeof vehicle.assignedDriver === 'string' 
              ? vehicle.assignedDriver 
              : vehicle.assignedDriver.driverId || vehicle.assignedDriver._id;
            
            console.log(`[Vehicle API] Vehicle ${vehicle.vehicleId} has assigned driver ID: ${driverId}`);
            
            const driver = await req.db.collection('drivers').findOne(
              { driverId: driverId },
              { 
                projection: { 
                  driverId: 1, 
                  'personalInfo.firstName': 1,
                  'personalInfo.lastName': 1,
                  'personalInfo.phone': 1,
                  'personalInfo.email': 1,
                  status: 1
                } 
              }
            );
            
            if (driver) {
              console.log(`[Vehicle API] Found driver details for ${driverId}`);
              
              // ✅ SAFETY CHECK: Ensure personalInfo exists
              const firstName = driver.personalInfo?.firstName || driver.firstName || '';
              const lastName = driver.personalInfo?.lastName || driver.lastName || '';
              const phone = driver.personalInfo?.phone || driver.phone || '';
              const email = driver.personalInfo?.email || driver.email || '';
              
              // Replace the driver ID string with a full driver object
              populatedVehicle.assignedDriver = {
                _id: driver._id,
                driverId: driver.driverId,
                name: `${firstName} ${lastName}`.trim() || driver.driverId,
                phone: phone,
                email: email,
                status: driver.status,
                personalInfo: {
                  firstName: firstName,
                  lastName: lastName
                }
              };
            } else {
              console.log(`[Vehicle API] Driver ${driverId} not found in database`);
              // Keep the driver ID but mark as not found
              populatedVehicle.assignedDriver = null;
            }
          }
        } else {
          // Ensure assignedDriver is null if not assigned
          populatedVehicle.assignedDriver = null;
        }

        console.log(`[Vehicle API] Normalized vehicle ${vehicle.vehicleId}:`);
        console.log(`   - Name: ${populatedVehicle.name}`);
        console.log(`   - Vehicle Number: ${populatedVehicle.vehicleNumber}`);
        console.log(`   - Seat Capacity: ${populatedVehicle.seatCapacity}`);
        console.log(`   - Driver: ${populatedVehicle.assignedDriver?.name || 'None'}`);
        console.log(`   - Assigned Customers: ${populatedVehicle.assignedCustomers.length}`);

        return populatedVehicle;
      })
    );

    console.log('[Vehicle API] Successfully populated driver details');

    res.json({
      success: true,
      data: vehiclesWithDrivers,
      pagination: {
        current: page,
        pages: Math.ceil(total / limit),
        total,
        limit
      }
    });
  } catch (error) {
    console.error('[Vehicle API] Get vehicles error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while fetching vehicles',
      error: error.message
    });
  }
});
// @route   POST /api/admin/vehicles
// @desc    Create a new vehicle
// @access  Private (Admin)
// @route   POST /api/admin/vehicles
// @desc    Create a new vehicle
// @access  Private (Admin)
router.post('/', validateVehicle, handleValidationErrors, async (req, res) => {
  try {
    // Handle validation errors
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: errors.array().map(err => err.msg)
      });
    }

    // Check if registration number already exists
    const existingVehicle = await req.db.collection('vehicles').findOne({
      registrationNumber: req.body.registrationNumber.toUpperCase()
    });

    if (existingVehicle) {
      return res.status(400).json({
        success: false,
        message: 'Vehicle with this registration number already exists'
      });
    }

    // Parse makeModel into make and model
    const makeModelParts = req.body.makeModel.trim().split(' ');
    const make = makeModelParts[0];
    const model = makeModelParts.slice(1).join(' ') || makeModelParts[0];

    // Generate vehicle ID
    const vehicleId = `VH${Date.now().toString().slice(-6)}`;

    // Create vehicle data matching your existing schema
    const vehicleData = {
      vehicleId: vehicleId,
      registrationNumber: req.body.registrationNumber.toUpperCase(),
      make: make,
      model: model,
      year: parseInt(req.body.yearOfManufacture),
      type: req.body.vehicleType.toLowerCase(), // Convert to lowercase to match existing data
      capacity: {
        passengers: parseInt(req.body.seatingCapacity),
        luggage: 0
      },
      specifications: {
        engineType: req.body.engineType,
        engineCapacity: parseFloat(req.body.engineCapacity),
        fuelType: req.body.engineType,
        transmission: 'Manual',
        mileage: parseFloat(req.body.mileage)
      },
      status: req.body.status || 'active',
      vendor: req.body.vendor || null, // Vendor from which vehicle is sourced
      currentLocation: {
        type: 'Point',
        coordinates: [77.5946, 12.9716] // Default to Bangalore coordinates
      },
      assignedDriver: null,
      insurance: {
        provider: '',
        policyNumber: '',
        expiryDate: null
      },
      registration: {
        expiryDate: null,
        rcNumber: req.body.registrationNumber.toUpperCase()
      },
      maintenance: {
        lastServiceDate: req.body.lastServiceDate ? new Date(req.body.lastServiceDate) : null,
        nextServiceDue: req.body.nextServiceDue ? new Date(req.body.nextServiceDue) : null,
        serviceHistory: []
      },
      fuelLevel: 100,
      createdBy: {
        uid: req.user?.uid || 'system',
        email: req.user?.email || 'system',
        name: req.user?.name || req.user?.email || 'System'
      },
      createdAt: new Date(),
      updatedAt: new Date()
    };

    const result = await req.db.collection('vehicles').insertOne(vehicleData);
    
    if (!result.insertedId) {
      throw new Error('Failed to create vehicle');
    }

    // Get the created vehicle
    const createdVehicle = await req.db.collection('vehicles').findOne({
      _id: result.insertedId
    });

    // Broadcast vehicle creation via WebSocket if available
    const wsServer = req.app.get('wsServer');
    if (wsServer) {
      wsServer.clients.forEach(client => {
        if (client.readyState === 1) { // WebSocket.OPEN
          client.send(JSON.stringify({
            type: 'vehicle_created',
            data: createdVehicle
          }));
        }
      });
    }

    res.status(201).json({
      success: true,
      message: 'Vehicle created successfully',
      data: createdVehicle
    });
  } catch (error) {
    console.error('Create vehicle error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while creating vehicle',
      error: error.message
    });
  }
});
// @route   GET /api/admin/vehicles/:id
// @desc    Get vehicle by ID
// @access  Private (Admin)
// @route   GET /api/admin/vehicles/:id
// @desc    Get vehicle by MongoDB _id or vehicleId
// @access  Private (Admin)
router.get('/:id', async (req, res) => {
  try {
    const { ObjectId } = require('mongodb');
    let vehicle;

    // Check if it's a MongoDB ObjectId format
    if (/^[0-9a-fA-F]{24}$/.test(req.params.id)) {
      vehicle = await req.db.collection('vehicles').findOne({
        _id: new ObjectId(req.params.id)
      });
    } else {
      // Otherwise search by vehicleId
      vehicle = await req.db.collection('vehicles').findOne({
        vehicleId: req.params.id
      });
    }

    if (!vehicle) {
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found'
      });
    }

    // Check for expiring documents
    let expiringDocs = [];
    if (vehicle.documents && vehicle.documents.length > 0) {
      expiringDocs = vehicle.documents.filter(doc => {
        if (!doc.expiryDate) return false;
        const expiryDate = new Date(doc.expiryDate);
        const thirtyDaysFromNow = new Date();
        thirtyDaysFromNow.setDate(thirtyDaysFromNow.getDate() + 30);
        return expiryDate <= thirtyDaysFromNow;
      });
    }

    res.json({
      success: true,
      data: {
        ...vehicle,
        expiringDocuments: expiringDocs
      }
    });
  } catch (error) {
    console.error('Get vehicle error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while fetching vehicle'
    });
  }
});

// @route   PUT /api/admin/vehicles/:id
// @desc    Update vehicle by ID
// @access  Private (Admin)
router.put('/:id', [
  param('id').isMongoId().withMessage('Invalid vehicle ID'),
  ...validateVehicleUpdate
], handleValidationErrors, async (req, res) => {
  try {
    const { ObjectId } = require('mongodb');
    const vehicleId = new ObjectId(req.params.id);

    // Check if vehicle exists
    const existingVehicle = await req.db.collection('vehicles').findOne({
      _id: vehicleId
    });

    if (!existingVehicle) {
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found'
      });
    }

    // Check if new registration number conflicts with existing ones
    if (req.body.registrationNumber && 
        req.body.registrationNumber.toUpperCase() !== existingVehicle.registrationNumber) {
      const conflictingVehicle = await req.db.collection('vehicles').findOne({
        registrationNumber: req.body.registrationNumber.toUpperCase(),
        _id: { $ne: vehicleId }
      });

      if (conflictingVehicle) {
        return res.status(400).json({
          success: false,
          message: 'Vehicle with this registration number already exists'
        });
      }
    }

    // Prepare update data
    const updateData = {
      ...req.body,
      updatedAt: new Date(),
      updatedBy: {
        uid: req.user.uid,
        email: req.user.email,
        name: req.user.name || req.user.email
      }
    };

    // Handle specific field transformations
    if (updateData.registrationNumber) {
      updateData.registrationNumber = updateData.registrationNumber.toUpperCase();
    }
    if (updateData.makeModel) {
      updateData.makeModel = updateData.makeModel.trim();
    }
    if (updateData.yearOfManufacture) {
      updateData.yearOfManufacture = parseInt(updateData.yearOfManufacture);
    }
    if (updateData.engineCapacity) {
      updateData.engineCapacity = parseFloat(updateData.engineCapacity);
    }
    if (updateData.seatingCapacity) {
      updateData.seatingCapacity = parseInt(updateData.seatingCapacity);
    }
    if (updateData.mileage) {
      updateData.mileage = parseFloat(updateData.mileage);
    }
    if (updateData.lastServiceDate) {
      updateData.lastServiceDate = new Date(updateData.lastServiceDate);
    }
    if (updateData.nextServiceDue) {
      updateData.nextServiceDue = new Date(updateData.nextServiceDue);
    }

    const result = await req.db.collection('vehicles').updateOne(
      { _id: vehicleId },
      { $set: updateData }
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found'
      });
    }

    // Get updated vehicle
    const updatedVehicle = await req.db.collection('vehicles').findOne({
      _id: vehicleId
    });

    // Broadcast vehicle update via WebSocket if available
    const wsServer = req.app.get('wsServer');
    if (wsServer) {
      wsServer.clients.forEach(client => {
        if (client.readyState === 1) { // WebSocket.OPEN
          client.send(JSON.stringify({
            type: 'vehicle_updated',
            data: updatedVehicle
          }));
        }
      });
    }

    res.json({
      success: true,
      message: 'Vehicle updated successfully',
      data: updatedVehicle
    });
  } catch (error) {
    console.error('Update vehicle error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while updating vehicle'
    });
  }
});

// @route   DELETE /api/admin/vehicles/:id
// @desc    Delete vehicle by ID
// @access  Private (Admin)
router.delete('/:id', [
  param('id').isMongoId().withMessage('Invalid vehicle ID')
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Invalid vehicle ID format'
      });
    }

    const { ObjectId } = require('mongodb');
    const vehicleId = new ObjectId(req.params.id);

    // Check if vehicle exists
    const vehicle = await req.db.collection('vehicles').findOne({
      _id: vehicleId
    });

    if (!vehicle) {
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found'
      });
    }

    // Check if vehicle is being used in active trips/rosters
    const activeTrips = await req.db.collection('trips').countDocuments({
      vehicleId: vehicle.vehicleId,
      status: { $in: ['scheduled', 'in_progress'] }
    });

    const activeRosters = await req.db.collection('rosters').countDocuments({
      vehicleId: vehicle.vehicleId,
      endTime: { $gte: new Date() }
    });

    if (activeTrips > 0 || activeRosters > 0) {
      return res.status(400).json({
        success: false,
        message: 'Cannot delete vehicle. It has active trips or roster assignments.'
      });
    }

    const result = await req.db.collection('vehicles').deleteOne({
      _id: vehicleId
    });

    if (result.deletedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found'
      });
    }

    // Broadcast vehicle deletion via WebSocket if available
    const wsServer = req.app.get('wsServer');
    if (wsServer) {
      wsServer.clients.forEach(client => {
        if (client.readyState === 1) { // WebSocket.OPEN
          client.send(JSON.stringify({
            type: 'vehicle_deleted',
            data: { vehicleId: vehicle.vehicleId }
          }));
        }
      });
    }

    res.json({
      success: true,
      message: 'Vehicle deleted successfully'
    });
  } catch (error) {
    console.error('Delete vehicle error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while deleting vehicle'
    });
  }
});

// @route   GET /api/admin/vehicles/stats/overview
// @desc    Get vehicle statistics
// @access  Private (Admin)
router.get('/stats/overview', async (req, res) => {
  try {
    const totalVehicles = await req.db.collection('vehicles').countDocuments();
    const activeVehicles = await req.db.collection('vehicles').countDocuments({ status: 'Active' });
    const maintenanceVehicles = await req.db.collection('vehicles').countDocuments({ status: 'Maintenance' });
    const inactiveVehicles = await req.db.collection('vehicles').countDocuments({ status: 'Inactive' });

    // Vehicle type distribution
    const typeDistribution = await req.db.collection('vehicles').aggregate([
      {
        $group: {
          _id: '$vehicleType',
          count: { $sum: 1 }
        }
      }
    ]).toArray();

    // Engine type distribution
    const engineDistribution = await req.db.collection('vehicles').aggregate([
      {
        $group: {
          _id: '$engineType',
          count: { $sum: 1 }
        }
      }
    ]).toArray();

    // Documents expiring in next 30 days
    const thirtyDaysFromNow = new Date();
    thirtyDaysFromNow.setDate(thirtyDaysFromNow.getDate() + 30);

    const vehiclesWithExpiringDocs = await req.db.collection('vehicles').aggregate([
      { $unwind: { path: '$documents', preserveNullAndEmptyArrays: true } },
      {
        $match: {
          'documents.expiryDate': {
            $exists: true,
            $lte: thirtyDaysFromNow
          }
        }
      },
      {
        $group: {
          _id: '$_id',
          vehicleId: { $first: '$vehicleId' },
          registrationNumber: { $first: '$registrationNumber' },
          expiringDocsCount: { $sum: 1 }
        }
      }
    ]).toArray();

    res.json({
      success: true,
      data: {
        overview: {
          total: totalVehicles,
          active: activeVehicles,
          maintenance: maintenanceVehicles,
          inactive: inactiveVehicles
        },
        distributions: {
          vehicleTypes: typeDistribution,
          engineTypes: engineDistribution
        },
        alerts: {
          expiringDocuments: vehiclesWithExpiringDocs.length,
          vehiclesWithExpiringDocs: vehiclesWithExpiringDocs
        }
      }
    });
  } catch (error) {
    console.error('Get stats error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while fetching statistics'
    });
  }
});

// @route   GET api/admin/vehicles/:id/assigned-customers
// @desc    Get detailed information about customers assigned to a vehicle
// @access  Private (Admin)
router.get('/:id/assigned-customers', async (req, res) => {
  try {
    const { ObjectId } = require('mongodb');
    const vehicleId = req.params.id;
    
    console.log(`\n🔍 Fetching assigned customers for vehicle: ${vehicleId}`);
    
    // Validate ObjectId format
    if (!ObjectId.isValid(vehicleId)) {
      console.log(`❌ Invalid vehicle ID format: ${vehicleId}`);
      return res.status(400).json({
        success: false,
        message: 'Invalid vehicle ID format'
      });
    }
    
    // Get vehicle details
    const vehicle = await req.db.collection('vehicles').findOne({
      _id: new ObjectId(vehicleId)
    });
    
    if (!vehicle) {
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found'
      });
    }
    
    console.log(`✅ Vehicle found: ${vehicle.name || vehicle.vehicleNumber}`);
    console.log(`   Seat Capacity: ${vehicle.seatingCapacity || 'Unknown'}`);
    
    // Get all assigned rosters for this vehicle
    const assignedRosters = await req.db.collection('rosters').find({
      vehicleId: vehicleId,
      status: { $in: ['assigned', 'active', 'in_progress'] }
    }).sort({ pickupSequence: 1 }).toArray();
    
    console.log(`   Assigned Customers: ${assignedRosters.length}`);
    
    // Get driver details
    let driver = null;
    if (vehicle.assignedDriver) {
      const driverId = typeof vehicle.assignedDriver === 'object' 
        ? vehicle.assignedDriver._id || vehicle.assignedDriver 
        : vehicle.assignedDriver;
      
      // Validate driverId before creating ObjectId
      if (driverId && ObjectId.isValid(driverId)) {
        driver = await req.db.collection('users').findOne({
          _id: new ObjectId(driverId)
        });
      } else {
        console.log(`⚠️ Invalid driver ID format: ${driverId}`);
      }
    }
    
    // Format customer details
    const customers = assignedRosters.map((roster, index) => {
      const loginTime = roster.startTime || roster.officeTime || roster.loginTime || 'N/A';
      const logoutTime = roster.endTime || roster.officeEndTime || roster.logoutTime || 'N/A';
      const loginLocation = roster.loginPickupAddress || roster.pickupLocation || roster.officeLocation || 'N/A';
      const logoutLocation = roster.logoutDropAddress || roster.dropLocation || roster.officeLocation || 'N/A';
      
      return {
        sequence: roster.pickupSequence || (index + 1),
        rosterId: roster._id.toString(),
        customerName: roster.customerName || roster.employeeDetails?.name || 'Unknown',
        customerEmail: roster.customerEmail || roster.employeeDetails?.email || 'N/A',
        customerPhone: roster.customerPhone || roster.employeeDetails?.phone || 'N/A',
        organization: roster.organizationName || roster.organization || roster.companyName || 'N/A',
        rosterType: roster.rosterType || 'both',
        loginTime: loginTime,
        logoutTime: logoutTime,
        loginLocation: loginLocation,
        logoutLocation: logoutLocation,
        loginCoordinates: roster.loginPickupLocation || roster.officeLocationCoordinates || null,
        logoutCoordinates: roster.logoutDropLocation || roster.officeLocationCoordinates || null,
        officeLocation: roster.officeLocation || 'N/A',
        optimizedPickupTime: roster.optimizedPickupTime || loginTime,
        estimatedArrival: roster.estimatedArrival || null,
        assignedAt: roster.assignedAt || null,
        status: roster.status || 'assigned',
        weekdays: roster.weekdays || [],
        dateRange: {
          from: roster.startDate || roster.fromDate || null,
          to: roster.endDate || roster.toDate || null
        }
      };
    });
    
    // Calculate capacity usage - check multiple possible fields for seat capacity
    const totalSeats = vehicle.seatingCapacity || 
                       vehicle.capacity?.passengers || 
                       vehicle.seatCapacity || 
                       0;
    const occupiedSeats = assignedRosters.length + 1; // +1 for driver
    const availableSeats = Math.max(0, totalSeats - occupiedSeats);
    const capacityPercentage = totalSeats > 0 ? ((occupiedSeats / totalSeats) * 100).toFixed(1) : 0;
    
    console.log(`   📊 Capacity: ${occupiedSeats}/${totalSeats} (${capacityPercentage}%)`);
    console.log(`   🪑 Available Seats: ${availableSeats}`);
    
    res.json({
      success: true,
      data: {
        vehicle: {
          id: vehicle._id.toString(),
          name: vehicle.name || vehicle.vehicleNumber,
          vehicleNumber: vehicle.vehicleNumber,
          vehicleType: vehicle.vehicleType,
          seatingCapacity: totalSeats,
          currentOrganization: vehicle.currentOrganization || 'N/A',
          currentShift: vehicle.currentShift || 'N/A',
          currentLoginTime: vehicle.currentLoginTime || 'N/A',
          currentLogoutTime: vehicle.currentLogoutTime || 'N/A'
        },
        driver: driver ? {
          id: driver._id.toString(),
          name: driver.name,
          email: driver.email,
          phone: driver.phone || driver.phoneNumber || 'N/A'
        } : null,
        capacity: {
          total: totalSeats,
          occupied: occupiedSeats,
          available: availableSeats,
          percentage: parseFloat(capacityPercentage),
          breakdown: {
            driver: 1,
            customers: assignedRosters.length
          }
        },
        customers: customers,
        summary: {
          totalCustomers: assignedRosters.length,
          organizations: [...new Set(customers.map(c => c.organization))],
          rosterTypes: [...new Set(customers.map(c => c.rosterType))],
          loginTimes: [...new Set(customers.map(c => c.loginTime))],
          logoutTimes: [...new Set(customers.map(c => c.logoutTime))]
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Error fetching assigned customers:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch assigned customers',
      error: error.message
    });
  }
});

// @route   GET /api/admin/vehicles/analytics/utilization
// @desc    Get vehicle utilization analytics
// @access  Private (Admin)
router.get('/analytics/utilization', async (req, res) => {
  try {
    const { timeframe = '7d', organizationId } = req.query;
    
    // Calculate date range based on timeframe
    const endDate = new Date();
    const startDate = new Date();
    
    switch (timeframe) {
      case '1d':
        startDate.setDate(endDate.getDate() - 1);
        break;
      case '7d':
        startDate.setDate(endDate.getDate() - 7);
        break;
      case '30d':
        startDate.setDate(endDate.getDate() - 30);
        break;
      case '90d':
        startDate.setDate(endDate.getDate() - 90);
        break;
      default:
        startDate.setDate(endDate.getDate() - 7);
    }

    // Build match criteria
    let matchCriteria = {
      createdAt: { $gte: startDate, $lte: endDate }
    };
    
    if (organizationId) {
      matchCriteria.organizationId = organizationId;
    }

    // Get vehicle utilization data
    const utilizationData = await req.db.collection('vehicles').aggregate([
      {
        $lookup: {
          from: 'rosters',
          let: { vehicleId: '$vehicleId', regNumber: '$registrationNumber' },
          pipeline: [
            {
              $match: {
                $expr: {
                  $or: [
                    { $eq: ['$vehicleId', '$$vehicleId'] },
                    { $eq: ['$vehicleNumber', '$$regNumber'] }
                  ]
                },
                ...matchCriteria
              }
            }
          ],
          as: 'rosters'
        }
      },
      {
        $addFields: {
          totalCapacity: {
            $ifNull: ['$capacity.passengers', { $ifNull: ['$seatingCapacity', 0] }]
          },
          assignedSeats: { $size: '$rosters' },
          utilizationPercentage: {
            $cond: {
              if: { $gt: [{ $ifNull: ['$capacity.passengers', { $ifNull: ['$seatingCapacity', 0] }] }, 0] },
              then: {
                $multiply: [
                  { $divide: [{ $size: '$rosters' }, { $ifNull: ['$capacity.passengers', { $ifNull: ['$seatingCapacity', 1] }] }] },
                  100
                ]
              },
              else: 0
            }
          }
        }
      },
      {
        $group: {
          _id: null,
          totalVehicles: { $sum: 1 },
          averageUtilization: { $avg: '$utilizationPercentage' },
          highUtilization: {
            $sum: { $cond: [{ $gte: ['$utilizationPercentage', 80] }, 1, 0] }
          },
          mediumUtilization: {
            $sum: { $cond: [{ $and: [{ $gte: ['$utilizationPercentage', 50] }, { $lt: ['$utilizationPercentage', 80] }] }, 1, 0] }
          },
          lowUtilization: {
            $sum: { $cond: [{ $lt: ['$utilizationPercentage', 50] }, 1, 0] }
          },
          totalCapacity: { $sum: '$totalCapacity' },
          totalAssigned: { $sum: '$assignedSeats' }
        }
      }
    ]).toArray();

    const result = utilizationData[0] || {
      totalVehicles: 0,
      averageUtilization: 0,
      highUtilization: 0,
      mediumUtilization: 0,
      lowUtilization: 0,
      totalCapacity: 0,
      totalAssigned: 0
    };

    res.json({
      success: true,
      data: {
        timeframe,
        period: { startDate, endDate },
        utilization: {
          average: parseFloat(result.averageUtilization?.toFixed(2) || '0'),
          distribution: {
            high: result.highUtilization,
            medium: result.mediumUtilization,
            low: result.lowUtilization
          }
        },
        capacity: {
          total: result.totalCapacity,
          assigned: result.totalAssigned,
          available: result.totalCapacity - result.totalAssigned,
          utilizationPercentage: result.totalCapacity > 0 
            ? parseFloat(((result.totalAssigned / result.totalCapacity) * 100).toFixed(2))
            : 0
        },
        fleet: {
          totalVehicles: result.totalVehicles
        }
      }
    });
  } catch (error) {
    console.error('Vehicle utilization analytics error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while fetching utilization analytics',
      error: error.message
    });
  }
});

// @route   POST /api/admin/vehicles/bulk-assign
// @desc    Bulk assign vehicles to drivers or routes
// @access  Private (Admin)
router.post('/bulk-assign', [
  body('assignments').isArray().withMessage('Assignments must be an array'),
  body('assignments.*.vehicleId').notEmpty().withMessage('Vehicle ID is required'),
  body('assignments.*.type').isIn(['driver', 'route']).withMessage('Assignment type must be driver or route'),
], async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: errors.array().map(err => err.msg)
      });
    }

    const { assignments } = req.body;
    const results = [];
    const { ObjectId } = require('mongodb');

    for (const assignment of assignments) {
      try {
        const { vehicleId, type, targetId, notes } = assignment;
        
        // Validate vehicle exists
        const vehicle = await req.db.collection('vehicles').findOne({
          $or: [
            { _id: ObjectId.isValid(vehicleId) ? new ObjectId(vehicleId) : null },
            { vehicleId: vehicleId }
          ]
        });

        if (!vehicle) {
          results.push({
            vehicleId,
            success: false,
            message: 'Vehicle not found'
          });
          continue;
        }

        let updateData = {
          updatedAt: new Date(),
          updatedBy: {
            uid: req.user?.uid || 'system',
            email: req.user?.email || 'system'
          }
        };

        if (type === 'driver') {
          // Validate driver exists
          const driver = await req.db.collection('drivers').findOne({
            driverId: targetId
          });

          if (!driver) {
            results.push({
              vehicleId,
              success: false,
              message: 'Driver not found'
            });
            continue;
          }

          updateData.assignedDriver = {
            driverId: driver.driverId,
            name: `${driver.personalInfo?.firstName || ''} ${driver.personalInfo?.lastName || ''}`.trim(),
            phone: driver.personalInfo?.phone || '',
            assignedAt: new Date()
          };
        }

        if (notes) {
          updateData.assignmentNotes = notes;
        }

        // Update vehicle
        const updateResult = await req.db.collection('vehicles').updateOne(
          { _id: vehicle._id },
          { $set: updateData }
        );

        results.push({
          vehicleId,
          success: updateResult.modifiedCount > 0,
          message: updateResult.modifiedCount > 0 ? 'Assignment successful' : 'No changes made'
        });

      } catch (error) {
        results.push({
          vehicleId: assignment.vehicleId,
          success: false,
          message: error.message
        });
      }
    }

    const successCount = results.filter(r => r.success).length;
    const failureCount = results.length - successCount;

    res.json({
      success: true,
      message: `Bulk assignment completed: ${successCount} successful, ${failureCount} failed`,
      data: {
        summary: {
          total: results.length,
          successful: successCount,
          failed: failureCount
        },
        results
      }
    });

  } catch (error) {
    console.error('Bulk assign error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error during bulk assignment',
      error: error.message
    });
  }
});

// @route   GET /api/admin/vehicles/maintenance/due
// @desc    Get vehicles with maintenance due
// @access  Private (Admin)
router.get('/maintenance/due', async (req, res) => {
  try {
    const { days = 30 } = req.query;
    const daysAhead = parseInt(days);
    const checkDate = new Date();
    checkDate.setDate(checkDate.getDate() + daysAhead);

    const vehiclesDue = await req.db.collection('vehicles').find({
      $or: [
        { 'maintenance.nextServiceDue': { $lte: checkDate } },
        { 'insurance.expiryDate': { $lte: checkDate } },
        { 'registration.expiryDate': { $lte: checkDate } }
      ]
    }).toArray();

    const categorized = {
      serviceDue: [],
      insuranceExpiring: [],
      registrationExpiring: [],
      overdue: []
    };

    const now = new Date();

    vehiclesDue.forEach(vehicle => {
      const serviceDate = vehicle.maintenance?.nextServiceDue ? new Date(vehicle.maintenance.nextServiceDue) : null;
      const insuranceDate = vehicle.insurance?.expiryDate ? new Date(vehicle.insurance.expiryDate) : null;
      const registrationDate = vehicle.registration?.expiryDate ? new Date(vehicle.registration.expiryDate) : null;

      if (serviceDate && serviceDate <= checkDate) {
        const item = {
          vehicleId: vehicle.vehicleId,
          registrationNumber: vehicle.registrationNumber,
          makeModel: `${vehicle.make || ''} ${vehicle.model || ''}`.trim(),
          dueDate: serviceDate,
          daysUntilDue: Math.ceil((serviceDate - now) / (1000 * 60 * 60 * 24)),
          type: 'service'
        };
        
        if (serviceDate < now) {
          categorized.overdue.push(item);
        } else {
          categorized.serviceDue.push(item);
        }
      }

      if (insuranceDate && insuranceDate <= checkDate) {
        const item = {
          vehicleId: vehicle.vehicleId,
          registrationNumber: vehicle.registrationNumber,
          makeModel: `${vehicle.make || ''} ${vehicle.model || ''}`.trim(),
          dueDate: insuranceDate,
          daysUntilDue: Math.ceil((insuranceDate - now) / (1000 * 60 * 60 * 24)),
          type: 'insurance'
        };
        
        if (insuranceDate < now) {
          categorized.overdue.push(item);
        } else {
          categorized.insuranceExpiring.push(item);
        }
      }

      if (registrationDate && registrationDate <= checkDate) {
        const item = {
          vehicleId: vehicle.vehicleId,
          registrationNumber: vehicle.registrationNumber,
          makeModel: `${vehicle.make || ''} ${vehicle.model || ''}`.trim(),
          dueDate: registrationDate,
          daysUntilDue: Math.ceil((registrationDate - now) / (1000 * 60 * 60 * 24)),
          type: 'registration'
        };
        
        if (registrationDate < now) {
          categorized.overdue.push(item);
        } else {
          categorized.registrationExpiring.push(item);
        }
      }
    });

    // Sort by days until due (most urgent first)
    Object.keys(categorized).forEach(key => {
      categorized[key].sort((a, b) => a.daysUntilDue - b.daysUntilDue);
    });

    res.json({
      success: true,
      data: {
        checkPeriod: `${daysAhead} days`,
        summary: {
          total: vehiclesDue.length,
          serviceDue: categorized.serviceDue.length,
          insuranceExpiring: categorized.insuranceExpiring.length,
          registrationExpiring: categorized.registrationExpiring.length,
          overdue: categorized.overdue.length
        },
        vehicles: categorized
      }
    });

  } catch (error) {
    console.error('Maintenance due check error:', error);
    res.status(500).json({
      success: false,
      message: 'Server error while checking maintenance due',
      error: error.message
    });
  }
});

module.exports = router;
module.exports.checkAvailableSeats = checkAvailableSeats;
module.exports.validateSeatCapacity = validateSeatCapacity;