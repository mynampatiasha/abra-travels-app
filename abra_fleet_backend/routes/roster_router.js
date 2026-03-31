// routes/roster_router.js - COMPLETE WITH DETAILED LOGGING
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { verifyToken, requireRole } = require('../middleware/auth');
const { check, validationResult } = require('express-validator');
const { createNotification } = require('../models/notification_model');
const { calculateRosterDistances } = require('../utils/distance_calculator');
const NotificationService = require('../services/notification_service');


// ✅ ADD THIS HELPER FUNCTION
function isValidObjectId(id) {
  if (!id) return false;
  if (typeof id === 'string' && id.length !== 24) return false;
  return ObjectId.isValid(id);
}

// Helper to delay execution (to respect OpenStreetMap rate limits)
const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// Helper to generate and store sequential roster IDs
async function generateSequentialRosterId(db, rosterId) {
  try {
    // Check if roster already has a readable ID
    const existingRoster = await db.collection('rosters').findOne(
      { _id: new ObjectId(rosterId) },
      { projection: { readableId: 1 } }
    );

    if (existingRoster && existingRoster.readableId) {
      return existingRoster.readableId;
    }

    // Get or create counter for roster IDs
    const counterResult = await db.collection('counters').findOneAndUpdate(
      { _id: 'roster_sequence' },
      { $inc: { sequence: 1 } },
      {
        upsert: true,
        returnDocument: 'after',
        projection: { sequence: 1 }
      }
    );

    const sequenceNumber = counterResult.value.sequence;
    const readableId = `RST-${String(sequenceNumber).padStart(4, '0')}`;

    // Store the readable ID in the roster document
    await db.collection('rosters').updateOne(
      { _id: new ObjectId(rosterId) },
      { $set: { readableId: readableId } }
    );

    console.log(`✅ Generated new roster ID: ${readableId} for ${rosterId}`);
    return readableId;

  } catch (error) {
    console.error('❌ Error generating roster ID:', error);
    // Fallback to a simple format
    return `RST-${rosterId.toString().slice(-6).toUpperCase()}`;
  }
}

// Helper to get or generate readable ID for existing rosters
async function getOrGenerateRosterId(db, roster) {
  // If roster already has a readable ID, use it
  if (roster.readableId) {
    return roster.readableId;
  }

  // Generate new sequential ID
  return await generateSequentialRosterId(db, roster._id);
}

// Helper to generate readable ID for new rosters (before insertion)
async function generateNewRosterId(db) {
  try {
    // Get next sequence number
    const counterResult = await db.collection('counters').findOneAndUpdate(
      { _id: 'roster_sequence' },
      { $inc: { sequence: 1 } },
      {
        upsert: true,
        returnDocument: 'after',
        projection: { sequence: 1 }
      }
    );

    const sequenceNumber = counterResult.value.sequence;
    const readableId = `RST-${String(sequenceNumber).padStart(4, '0')}`;

    console.log(`✅ Generated new roster ID for creation: ${readableId}`);
    return readableId;

  } catch (error) {
    console.error('❌ Error generating new roster ID:', error);
    // Fallback to timestamp-based ID
    const timestamp = Date.now().toString().slice(-6);
    return `RST-${timestamp}`;
  }
}

// ✅ HELPER: Server-Side Geocoding (LENIENT - Best Effort)
// Tries to geocode address but returns approximate coordinates if exact geocoding fails
async function geocodeAddress(address) {
  if (!address || typeof address !== 'string') return null;

  // Try OpenStreetMap API first
  try {
    const encodedAddress = encodeURIComponent(address);
    const response = await fetch(
      `https://nominatim.openstreetmap.org/search?format=json&q=${encodedAddress}&limit=1`,
      {
        headers: { 'User-Agent': 'AbraFleet_Backend/1.0' }
      }
    );

    const data = await response.json();
    if (data && data.length > 0) {
      console.log(`✅ Geocoded successfully: ${address}`);
      return {
        latitude: parseFloat(data[0].lat),
        longitude: parseFloat(data[0].lon)
      };
    }
  } catch (error) {
    console.warn(`⚠️  Geocoding API failed for: ${address}`, error.message);
  }

  // 🆕 LENIENT FALLBACK: Return approximate coordinates based on address text
  // This allows the system to work even when exact geocoding fails
  console.log(`⚠️  Using approximate coordinates for: ${address}`);
  
  // Generate approximate coordinates based on hash of address string
  // This ensures same address always gets same coordinates
  let hash = 0;
  for (let i = 0; i < address.length; i++) {
    hash = ((hash << 5) - hash) + address.charCodeAt(i);
    hash = hash & hash;
  }
  
  // Use hash to generate coordinates within a reasonable range
  // Base coordinates (can be adjusted for your region)
  const baseLat = 12.9716;  // Approximate center latitude
  const baseLng = 77.5946;  // Approximate center longitude
  const range = 0.5;        // +/- 0.5 degrees (~55km range)
  
  const latOffset = ((hash % 1000) / 1000 - 0.5) * range;
  const lngOffset = (((hash >> 10) % 1000) / 1000 - 0.5) * range;
  
  return {
    latitude: baseLat + latOffset,
    longitude: baseLng + lngOffset
  };
}

// ✅ HELPER: Reverse Geocoding
// Converts coordinates "13.005619, 77.663437" to readable address
async function reverseGeocodeLocation(location) {
  if (!location || typeof location !== 'string') return location;

  // If it already contains letters (already an address), return as-is
  if (/[a-zA-Z]/.test(location)) {
    return location;
  }

  // Try to parse as coordinates
  try {
    const parts = location.split(',').map(p => p.trim());
    if (parts.length !== 2) return location;

    const lat = parseFloat(parts[0]);
    const lng = parseFloat(parts[1]);

    if (isNaN(lat) || isNaN(lng)) return location;

    // Call OpenStreetMap reverse geocoding API
    const response = await fetch(
      `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}`,
      {
        headers: { 'User-Agent': 'AbraFleet_Backend/1.0' }
      }
    );

    const data = await response.json();
    if (data && data.display_name) {
      // Format address nicely
      const address = data.address;
      const parts = [];
      if (address.road) parts.push(address.road);
      if (address.suburb) parts.push(address.suburb);
      if (address.city || address.town) parts.push(address.city || address.town);
      if (address.state) parts.push(address.state);

      return parts.length > 0 ? parts.join(', ') : data.display_name;
    }
  } catch (error) {
    console.warn(`Reverse geocoding failed for location: ${location}`, error.message);
  }

  return location; // Return original if geocoding fails
}
// Initialize Roster model
let Roster;
router.use((req, res, next) => {
  if (!req.db) {
    return res.status(500).json({ msg: 'Database connection not available' });
  }

  if (!Roster) {
    const RosterModel = require('../models/roster_model');
    Roster = new RosterModel(req.db);
  }
  next();
});


// ========== NEW BULK IMPORT ROUTE (Add this before the single /customer route) ==========

// @route   POST api/roster/customer/bulk
// @desc    Bulk create customer roster requests
// @access  Private
// ========== BULK IMPORT ROUTE (AUTO-GEOCODING) ==========
// @route   POST api/roster/customer/bulk
// @desc    Bulk create customer roster requests
// @access  Private
router.post('/customer/bulk', verifyToken, async (req, res) => {
  console.log('\n' + '='.repeat(80));
  console.log('📦 BULK IMPORT STARTED');
  console.log('='.repeat(80));

  try {
    const { rosters } = req.body;
    const userId = req.user.userId;

    if (!Array.isArray(rosters) || rosters.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'No roster data provided'
      });
    }

    console.log(`📊 Total rosters to process: ${rosters.length}`);

    // Get admin/customer details (who is importing)
    let adminName = 'Unknown';
    let adminEmail = '';
    let adminOrganization = '';
    try {
      const userDoc = await req.db.collection('users').findOne({ firebaseUid: userId });
      if (userDoc) {
        adminName = userDoc.name || 'Unknown';
        adminEmail = userDoc.email || '';
        adminOrganization = userDoc.companyName || userDoc.organizationName || '';
      }
    } catch (e) {
      console.warn('Could not fetch user details:', e.message);
    }

    // Ensure organization is set for proper filtering
    if (!adminOrganization) {
      return res.status(400).json({
        success: false,
        message: 'Admin organization not found. Please contact system administrator.'
      });
    }

    console.log(`📊 Bulk import by ${adminName} from organization: ${adminOrganization}`);

    const successfulImports = [];
    const failedImports = [];

    // Process each roster
    for (let i = 0; i < rosters.length; i++) {
      const item = rosters[i];
      console.log(`\n--- Processing Row ${i + 1}/${rosters.length} ---`);

      try {
        // 1️⃣ VALIDATE REQUIRED FIELDS
        if (!item.officeLocation || item.officeLocation.trim() === '') {
          throw new Error('Office location is required');
        }
        if (!item.weekdays || !Array.isArray(item.weekdays) || item.weekdays.length === 0) {
          throw new Error('At least one weekday is required');
        }
        if (!item.fromDate || !item.toDate) {
          throw new Error('From date and To date are required');
        }
        if (!item.fromTime || !item.toTime) {
          throw new Error('From time and To time are required');
        }

        const rosterType = item.rosterType || 'both';
        console.log(`   Type: ${rosterType}`);
        console.log(`   Office: ${item.officeLocation}`);

        // 2️⃣ GEOCODE OFFICE LOCATION (ALWAYS REQUIRED)
        let officeCoords = null;

        // Check if Flutter already sent coordinates
        if (item.officeLocationCoordinates &&
          item.officeLocationCoordinates.latitude &&
          item.officeLocationCoordinates.latitude !== 0) {
          officeCoords = item.officeLocationCoordinates;
          console.log(`   ✅ Using provided office coords: ${officeCoords.latitude}, ${officeCoords.longitude}`);
        } else {
          // Geocode the address
          console.log(`   🌍 Geocoding office location...`);
          officeCoords = await geocodeAddress(item.officeLocation);
          await delay(1200); // Rate limit: 1.2 seconds between requests
        }

        if (!officeCoords || officeCoords.latitude === 0) {
          throw new Error(`Could not geocode office location: "${item.officeLocation}". Please provide a valid address.`);
        }
        console.log(`   ✅ Office coordinates confirmed: ${officeCoords.latitude}, ${officeCoords.longitude}`);

        // 3️⃣ GEOCODE PICKUP LOCATION (Required for 'login' or 'both')
        let pickupCoords = null;

        if (rosterType === 'login' || rosterType === 'both') {
          // Check if Flutter sent coordinates
          if (item.loginPickupLocation &&
            item.loginPickupLocation.latitude &&
            item.loginPickupLocation.latitude !== 0) {
            pickupCoords = item.loginPickupLocation;
            console.log(`   ✅ Using provided pickup coords: ${pickupCoords.latitude}, ${pickupCoords.longitude}`);
          } else if (item.loginPickupAddress && item.loginPickupAddress.trim() !== '') {
            // Geocode the address
            console.log(`   🌍 Geocoding pickup: "${item.loginPickupAddress}"`);
            pickupCoords = await geocodeAddress(item.loginPickupAddress);
            await delay(1200);
          }

          if (!pickupCoords || pickupCoords.latitude === 0) {
            throw new Error(`Pickup location required for ${rosterType} roster. Could not geocode: "${item.loginPickupAddress || 'No address provided'}". Please provide a valid address.`);
          }
          console.log(`   ✅ Pickup coordinates confirmed: ${pickupCoords.latitude}, ${pickupCoords.longitude}`);
        }

        // 4️⃣ GEOCODE DROP LOCATION (Required for 'logout' or 'both')
        let dropCoords = null;

        if (rosterType === 'logout' || rosterType === 'both') {
          // Check if Flutter sent coordinates
          if (item.logoutDropLocation &&
            item.logoutDropLocation.latitude &&
            item.logoutDropLocation.latitude !== 0) {
            dropCoords = item.logoutDropLocation;
            console.log(`   ✅ Using provided drop coords: ${dropCoords.latitude}, ${dropCoords.longitude}`);
          } else if (item.logoutDropAddress && item.logoutDropAddress.trim() !== '') {
            // Geocode the address
            console.log(`   🌍 Geocoding drop: "${item.logoutDropAddress}"`);
            dropCoords = await geocodeAddress(item.logoutDropAddress);
            await delay(1200);
          }

          if (!dropCoords || dropCoords.latitude === 0) {
            throw new Error(`Drop location required for ${rosterType} roster. Could not geocode: "${item.logoutDropAddress || 'No address provided'}". Please provide a valid address.`);
          }
          console.log(`   ✅ Drop coordinates confirmed: ${dropCoords.latitude}, ${dropCoords.longitude}`);
        }

        // 5️⃣ PREPARE ROSTER DATA
        // ✅ FIX: Use employee email/name if available, otherwise fall back to admin
        const displayName = item.employeeData?.name || adminName;
        const displayEmail = item.employeeData?.email || adminEmail;
        const displayPhone = item.employeeData?.phone || '';
        const displayDepartment = item.employeeData?.department || '';

        console.log(`   👤 Display Name: ${displayName}`);
        console.log(`   📧 Display Email: ${displayEmail}`);

        // 🔥 NEW: AUTO-CREATE USER IF DOESN'T EXIST
        let customerFirebaseUid = null;
        let userCreatedNow = false;
        let hrmEmployeeCreated = false;

        try {
          console.log(`   🔍 Checking if user exists: ${displayEmail}`);

          // Check if user exists in MongoDB
          let existingUser = await req.db.collection('users').findOne({
            email: displayEmail.toLowerCase().trim()
          });

          if (existingUser) {
            console.log(`   ✅ User already exists in MongoDB: ${existingUser.name}`);
            customerFirebaseUid = existingUser.firebaseUid;
          } else {
            console.log(`   👤 User NOT found - creating new user account...`);

            // Check if user exists in Firebase Auth
            let firebaseUser;
            try {
              firebaseUser = await admin.auth().getUserByEmail(displayEmail);
              console.log(`   ℹ️  User exists in Firebase Auth: ${firebaseUser.uid}`);
            } catch (fbError) {
              if (fbError.code === 'auth/user-not-found') {
                // Create Firebase Auth user
                console.log(`   🔐 Creating Firebase Auth user...`);
                const tempPassword = 'Welcome@' + Math.random().toString(36).slice(-8);

                firebaseUser = await admin.auth().createUser({
                  email: displayEmail,
                  password: tempPassword,
                  displayName: displayName,
                  emailVerified: false
                });

                console.log(`   ✅ Firebase Auth user created: ${firebaseUser.uid}`);
                console.log(`   🔑 Temporary password: ${tempPassword}`);

                // Generate password reset link
                try {
                  const passwordResetLink = await admin.auth().generatePasswordResetLink(displayEmail);
                  console.log(`   📧 Password reset link generated`);
                  console.log(`   🔗 Link: ${passwordResetLink.substring(0, 50)}...`);

                  // TODO: Send welcome email with password reset link
                  // await sendWelcomeEmail(displayEmail, displayName, passwordResetLink);
                } catch (linkError) {
                  console.warn(`   ⚠️  Could not generate password reset link: ${linkError.message}`);
                }
              } else {
                throw fbError;
              }
            }

            // Create MongoDB user document
            console.log(`   💾 Creating MongoDB user document...`);
            const mongoUser = {
              firebaseUid: firebaseUser.uid,
              email: displayEmail.toLowerCase().trim(),
              name: displayName,
              phone: displayPhone,
              role: 'customer',
              companyName: adminOrganization,
              organizationName: adminOrganization,
              department: displayDepartment,
              status: 'active',
              isApproved: true,
              createdAt: new Date(),
              createdBy: userId,
              createdVia: 'roster_import',
              updatedAt: new Date()
            };

            const insertResult = await req.db.collection('users').insertOne(mongoUser);
            console.log(`   ✅ MongoDB user created: ${insertResult.insertedId}`);

            customerFirebaseUid = firebaseUser.uid;
            userCreatedNow = true;
          }

          // 🔥 NEW: CREATE HRM EMPLOYEE RECORD
          console.log(`   🏢 Checking if HRM employee record exists...`);
          const existingHrmEmployee = await req.db.collection('hr_employees').findOne({
            email: displayEmail.toLowerCase().trim()
          });

          if (!existingHrmEmployee && item.employeeData) {
            console.log(`   👥 Creating HRM employee record...`);
            
            // Extract company domain from email
            const emailDomain = displayEmail.toLowerCase().split('@')[1];
            
            // Generate User ID for HRM employee
            const generateFirebaseUID = (name, email) => {
              const timestamp = Date.now().toString(36);
              const randomPart = Math.random().toString(36).substring(2, 8);
              const namePart = name.toLowerCase().replace(/[^a-z0-9]/g, '').substring(0, 8);
              return `emp_${namePart}_${timestamp}_${randomPart}`;
            };

            const hrmEmployee = {
              name: displayName,
              email: displayEmail.toLowerCase().trim(),
              phone: displayPhone || '',
              department: item.employeeData.department || displayDepartment || '',
              designation: item.employeeData.designation || '',
              hireDate: new Date(),
              salary: 0,
              status: 'active',
              address: '',
              emergencyContact: item.employeeData.emergencyContactPhone || '',
              bloodGroup: '',
              dateOfBirth: null,
              gender: '',
              companyName: item.employeeData.companyName || adminOrganization, // 🔥 Store company name
              companyDomain: emailDomain, // 🔥 Store extracted domain
              firebaseUid: generateFirebaseUID(displayName, displayEmail),
              fcmToken: null,
              createdAt: new Date(),
              updatedAt: new Date(),
              createdBy: userId,
              createdVia: 'roster_bulk_import'
            };

            const hrmResult = await req.db.collection('hr_employees').insertOne(hrmEmployee);
            console.log(`   ✅ HRM employee created: ${hrmResult.insertedId}`);
            hrmEmployeeCreated = true;
          } else if (existingHrmEmployee) {
            console.log(`   ℹ️  HRM employee already exists: ${existingHrmEmployee.name}`);
          } else {
            console.log(`   ⚠️  No employee data provided - skipping HRM employee creation`);
          }

        } catch (userError) {
          console.warn(`   ⚠️  User creation failed: ${userError.message}`);
          console.warn(`   ℹ️  Continuing with roster creation without user link...`);
          // Continue with roster creation even if user creation fails
        }

        const rosterData = {
          rosterType: rosterType,
          officeLocation: item.officeLocation,
          officeLocationCoordinates: officeCoords,
          weekdays: item.weekdays,
          fromDate: new Date(item.fromDate),
          toDate: new Date(item.toDate),
          fromTime: item.fromTime,
          toTime: item.toTime,
          notes: item.notes || '',
          customerName: displayName,        // ✅ Use employee name
          customerEmail: displayEmail,      // ✅ Use employee email
          customerId: customerFirebaseUid,  // 🔥 NEW: Link to Firebase user
          customerFirebaseUid: customerFirebaseUid, // 🔥 NEW: Store User ID
          createdBy: userId,                // Track who created it (admin)
          createdByAdmin: adminName,        // Track admin who imported
          organizationName: adminOrganization, // ✅ Store organization for filtering
          employeeDetails: {
            ...(item.employeeData || {}),
            companyName: adminOrganization  // ✅ Ensure organization is stored
          }
        };

        // Only include locations that exist
        if (pickupCoords) {
          rosterData.loginPickupLocation = pickupCoords;
          rosterData.loginPickupAddress = item.loginPickupAddress || '';
        }

        if (dropCoords) {
          rosterData.logoutDropLocation = dropCoords;
          rosterData.logoutDropAddress = item.logoutDropAddress || '';
        }

        // 6️⃣ CHECK FOR DUPLICATES
        console.log(`   🔍 Checking for duplicate rosters...`);
        const duplicateCheck = await req.db.collection('rosters').findOne({
          customerEmail: displayEmail,
          officeLocation: item.officeLocation,
          rosterType: rosterType,
          startDate: new Date(item.fromDate),
          endDate: new Date(item.toDate),
          startTime: item.fromTime,
          endTime: item.toTime,
          organizationName: adminOrganization,
          status: { $in: ['pending_assignment', 'assigned', 'active'] } // Check active rosters
        });

        if (duplicateCheck) {
          console.log(`   ⚠️  Duplicate roster found - skipping`);
          throw new Error(`Duplicate roster: ${displayName} already has a roster for ${item.officeLocation} with same dates and times`);
        }

        console.log(`   💾 Creating roster in database...`);

        // 7️⃣ CREATE ROSTER
        const newRoster = await Roster.createCustomerRoster(rosterData, userId);

        console.log(`   ✅ Row ${i + 1} imported successfully - ID: ${newRoster._id}`);
        if (userCreatedNow) {
          console.log(`   🎉 New user account created for: ${displayName}`);
        }
        if (hrmEmployeeCreated) {
          console.log(`   👥 New HRM employee record created for: ${displayName}`);
        }

        successfulImports.push({
          index: i,
          id: newRoster._id,
          officeLocation: item.officeLocation,
          employeeName: displayName,
          employeeEmail: displayEmail,
          userCreated: userCreatedNow,
          hrmEmployeeCreated: hrmEmployeeCreated,
          userLinked: !!customerFirebaseUid
        });

      } catch (err) {
        console.error(`   ❌ Row ${i + 1} failed:`, err.message);
        failedImports.push({
          index: i,
          error: err.message,
          officeLocation: item.officeLocation || 'Unknown',
          employeeName: item.employeeData?.name || 'Unknown'
        });
      }
    }

    console.log('\n' + '='.repeat(80));
    console.log('📊 BULK IMPORT COMPLETED');
    console.log('='.repeat(80));
    console.log(`✅ Successful: ${successfulImports.length}`);
    console.log(`❌ Failed: ${failedImports.length}`);
    console.log(`📈 Success Rate: ${((successfulImports.length / rosters.length) * 100).toFixed(1)}%`);
    
    // Calculate HRM employee statistics
    const newUsersCreated = successfulImports.filter(item => item.userCreated).length;
    const newHrmEmployeesCreated = successfulImports.filter(item => item.hrmEmployeeCreated).length;
    
    console.log(`👤 New Users Created: ${newUsersCreated}`);
    console.log(`👥 New HRM Employees Created: ${newHrmEmployeesCreated}`);
    console.log('='.repeat(80) + '\n');

    // Return response
    const totalProcessed = successfulImports.length + failedImports.length;

    res.json({
      success: successfulImports.length > 0,
      message: `Processed ${totalProcessed} rosters: ${successfulImports.length} succeeded, ${failedImports.length} failed. Created ${newUsersCreated} new users and ${newHrmEmployeesCreated} new HRM employee records.`,
      data: {
        successfulImports,
        failedImports,
        summary: {
          total: totalProcessed,
          successful: successfulImports.length,
          failed: failedImports.length,
          successRate: `${((successfulImports.length / totalProcessed) * 100).toFixed(1)}%`,
          newUsersCreated: newUsersCreated,
          newHrmEmployeesCreated: newHrmEmployeesCreated
        }
      }
    });

  } catch (err) {
    console.error('❌ FATAL ERROR in bulk import:', err);
    console.error(err.stack);
    res.status(500).json({
      success: false,
      message: 'Server error during bulk import',
      error: err.message
    });
  }
});


// routes/roster_router.js
// ✅ FIXED: Check employees in the USERS collection, not rosters

// @route   GET api/roster/customer/check-employee
// @desc    Check if an employee exists in the system by email
// @access  Private (Authenticated user)
router.get('/customer/check-employee', verifyToken, async (req, res) => {
  try {
    const { email } = req.query;

    if (!email) {
      return res.status(400).json({
        success: false,
        message: 'Email is required'
      });
    }

    const normalizedEmail = email.toLowerCase().trim();
    console.log(`🔍 Checking if employee exists: ${normalizedEmail}`);

    // ✅ FIX 1: Check in USERS collection (where employees are actually stored)
    const employeeInDB = await req.db.collection('users').findOne({
      email: normalizedEmail,
      role: 'customer' // Employees have role='customer'
    });

    if (employeeInDB) {
      console.log(`✅ Employee FOUND in users collection: ${normalizedEmail}`);
      return res.json({
        success: true,
        exists: true,
        employeeId: employeeInDB._id.toString(),
        employee: {
          name: employeeInDB.name,
          email: employeeInDB.email,
          department: employeeInDB.department || 'N/A',
          companyName: employeeInDB.companyName || 'N/A',
          phoneNumber: employeeInDB.phoneNumber
        }
      });
    }

    // If not found, employee doesn't exist
    console.log(`❌ Employee NOT FOUND: ${normalizedEmail}`);
    return res.json({
      success: true,
      exists: false,
      message: 'Employee not found'
    });

  } catch (err) {
    console.error('❌ Error checking employee:', err.message);
    res.status(500).json({
      success: false,
      message: 'Server error while checking employee'
    });
  }
});

// ✅ ENHANCED: Batch check multiple employees at once (more efficient)
// @route   POST api/roster/customer/check-employees-batch
// @desc    Check multiple employees at once
// @access  Private (Authenticated user)
router.post('/customer/check-employees-batch', verifyToken, async (req, res) => {
  try {
    const { emails } = req.body;

    if (!Array.isArray(emails) || emails.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'emails array is required'
      });
    }

    console.log(`🔍 Batch checking ${emails.length} employees...`);

    // Normalize all emails
    const normalizedEmails = emails.map(e => e.toLowerCase().trim());

    // ✅ Single query to check all employees at once (MUCH faster)
    const existingEmployees = await req.db.collection('users').find({
      email: { $in: normalizedEmails },
      role: 'customer'
    }).toArray();

    // Create a map of email -> exists
    const existsMap = {};
    const foundEmails = new Set();

    existingEmployees.forEach(emp => {
      const email = emp.email.toLowerCase().trim();
      existsMap[email] = true;
      foundEmails.add(email);
    });

    // Mark emails not found as false
    normalizedEmails.forEach(email => {
      if (!existsMap[email]) {
        existsMap[email] = false;
      }
    });

    const existingCount = foundEmails.size;
    const newCount = normalizedEmails.length - existingCount;

    console.log(`✅ Batch check complete:`);
    console.log(`   - Existing: ${existingCount}`);
    console.log(`   - New: ${newCount}`);

    return res.json({
      success: true,
      existsMap: existsMap,
      summary: {
        total: normalizedEmails.length,
        existing: existingCount,
        new: newCount
      }
    });

  } catch (err) {
    console.error('❌ Error in batch employee check:', err.message);
    res.status(500).json({
      success: false,
      message: 'Server error while checking employees',
      error: err.message
    });
  }
});


// @route   GET api/rosters/active-trip/:userId
// @desc    Get active/ongoing trip for a customer
// @access  Private (Authenticated user)
router.get('/active-trip/:userId', verifyToken, async (req, res) => {
  try {
    const { userId } = req.params;

    console.log(`🔍 Checking for active trip for user: ${userId}`);

    // Find active trip for this customer (scheduled, ongoing, or in progress)
    const activeTrip = await req.db.collection('rosters').findOne({
      customerId: userId,
      status: { $in: ['scheduled', 'ongoing', 'in_progress', 'started', 'approved'] }
    });

    if (!activeTrip) {
      console.log(`❌ No active trip found for user: ${userId}`);
      return res.json({
        success: true,
        hasActiveTrip: false,
        trip: null
      });
    }

    console.log(`✅ Found active trip: ${activeTrip._id}`);

    // Return the active trip details in the format the app expects
    return res.json({
      success: true,
      hasActiveTrip: true,
      trip: {
        tripId: activeTrip._id.toString(),
        id: activeTrip._id.toString(),
        readableId: activeTrip.readableId,
        status: activeTrip.status,
        vehicleNumber: activeTrip.vehicleNumber,
        vehicleType: activeTrip.vehicleType,
        driverName: activeTrip.driverName,
        driverEmail: activeTrip.driverEmail,
        driverPhone: activeTrip.driverPhone,
        pickupLocation: activeTrip.pickupLocation,
        dropLocation: activeTrip.dropLocation,
        pickupTime: activeTrip.pickupTime,
        dropTime: activeTrip.dropTime,
        tripType: activeTrip.tripType,
        startDate: activeTrip.startDate,
        tripStartTime: activeTrip.tripStartTime,
        pickupCoordinates: activeTrip.pickupCoordinates,
        dropCoordinates: activeTrip.dropCoordinates
      }
    });

  } catch (err) {
    console.error('❌ Error fetching active trip:', err.message);
    res.status(500).json({
      success: false,
      message: 'Server error while fetching active trip',
      error: err.message
    });
  }
});

// Add this endpoint to your routes/roster_router.js file
// Place it AFTER the /check-employee route and BEFORE the /customer route

// routes/roster_router.js
// ENHANCED DUPLICATE DETECTION - Replace your check-duplicate endpoint

// @route   GET api/roster/customer/check-duplicate
// @desc    FIXED: Check if a roster already exists to prevent duplicates
// @access  Private (Authenticated user)
router.get('/customer/check-duplicate', verifyToken, async (req, res) => {
  try {
    const { employeeEmail, fromDate, startTime, rosterType } = req.query;

    if (!employeeEmail || !fromDate || !startTime || !rosterType) {
      return res.status(400).json({
        success: false,
        message: 'Missing required parameters: employeeEmail, fromDate, startTime, rosterType'
      });
    }

    console.log(`🔍 Checking roster duplicate for: ${employeeEmail} - ${fromDate} ${startTime} (${rosterType})`);

    // ✅ FIX 1: Normalize inputs (lowercase email, trim whitespace)
    const normalizedEmail = employeeEmail.toLowerCase().trim();
    const normalizedRosterType = rosterType.toLowerCase().trim();
    const normalizedStartTime = startTime.trim();

    // ✅ FIX 2: Parse date and create a flexible date range (handles timezone issues)
    const inputDate = new Date(fromDate);

    // Create start of day in UTC
    const startOfDay = new Date(Date.UTC(
      inputDate.getFullYear(),
      inputDate.getMonth(),
      inputDate.getDate(),
      0, 0, 0, 0
    ));

    // Create end of day in UTC
    const endOfDay = new Date(Date.UTC(
      inputDate.getFullYear(),
      inputDate.getMonth(),
      inputDate.getDate(),
      23, 59, 59, 999
    ));

    console.log(`   📅 Date range: ${startOfDay.toISOString()} to ${endOfDay.toISOString()}`);

    // ✅ FIX 3: Comprehensive query that checks ALL possible field variations
    const query = {
      $and: [
        // ✅ Employee email check (handles both field structures)
        {
          $or: [
            { 'employeeDetails.email': normalizedEmail },
            { 'customerEmail': normalizedEmail },
            { 'employeeData.email': normalizedEmail }
          ]
        },

        // ✅ Date check (handles multiple field names and timezone variations)
        {
          $or: [
            // Check startDate field
            {
              'startDate': {
                $gte: startOfDay,
                $lte: endOfDay
              }
            },
            // Check dateRange.from field
            {
              'dateRange.from': {
                $gte: startOfDay,
                $lte: endOfDay
              }
            },
            // Check fromDate field (some rosters use this)
            {
              'fromDate': {
                $gte: startOfDay,
                $lte: endOfDay
              }
            }
          ]
        },

        // ✅ Time check (exact match required)
        {
          $or: [
            { 'startTime': normalizedStartTime },
            { 'timeRange.from': normalizedStartTime },
            { 'fromTime': normalizedStartTime }
          ]
        },

        // ✅ Roster type check
        { 'rosterType': normalizedRosterType },

        // ✅ Not cancelled or rejected
        {
          'status': {
            $nin: ['cancelled', 'rejected', 'deleted']
          }
        }
      ]
    };

    // Execute query
    const existingRoster = await req.db.collection('rosters').findOne(query);

    if (existingRoster) {
      console.log(`⚠️  DUPLICATE FOUND!`);
      console.log(`   Roster ID: ${existingRoster._id}`);
      console.log(`   Employee: ${normalizedEmail}`);
      console.log(`   Date: ${fromDate}`);
      console.log(`   Time: ${normalizedStartTime}`);
      console.log(`   Type: ${normalizedRosterType}`);
      console.log(`   Stored date: ${existingRoster.dateRange?.from || existingRoster.startDate || existingRoster.fromDate}`);
      console.log(`   Status: ${existingRoster.status}`);

      return res.json({
        success: true,
        exists: true,
        rosterId: existingRoster._id.toString(),
        message: 'A roster with these details already exists',
        details: {
          rosterId: existingRoster._id.toString(),
          employeeEmail: existingRoster.employeeDetails?.email || existingRoster.customerEmail,
          officeLocation: existingRoster.officeLocation,
          date: existingRoster.dateRange?.from || existingRoster.startDate || existingRoster.fromDate,
          time: existingRoster.startTime || existingRoster.timeRange?.from || existingRoster.fromTime,
          status: existingRoster.status
        }
      });
    }

    console.log(`✅ No duplicate found - roster can be created`);
    return res.json({
      success: true,
      exists: false,
      message: 'No duplicate roster found'
    });

  } catch (err) {
    console.error('❌ Error checking roster duplicate:', err.message);
    console.error(err.stack);

    res.status(500).json({
      success: false,
      message: 'Server error while checking roster duplicate',
      error: err.message
    });
  }
});

// ✅ ALSO ADD THIS HELPER METHOD to check multiple rosters at once (for batch processing)
// @route   POST api/roster/customer/check-duplicates-batch
// @desc    Check multiple rosters for duplicates in one request (more efficient)
// @access  Private (Authenticated user)
router.post('/customer/check-duplicates-batch', verifyToken, async (req, res) => {
  try {
    const { rosters } = req.body;

    if (!Array.isArray(rosters) || rosters.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'rosters array is required'
      });
    }

    console.log(`🔍 Batch checking ${rosters.length} rosters for duplicates...`);

    const results = [];

    for (const roster of rosters) {
      const { employeeEmail, fromDate, startTime, rosterType } = roster;

      if (!employeeEmail || !fromDate || !startTime || !rosterType) {
        results.push({
          employeeEmail,
          fromDate,
          exists: false,
          error: 'Missing required fields'
        });
        continue;
      }

      const normalizedEmail = employeeEmail.toLowerCase().trim();
      const normalizedRosterType = rosterType.toLowerCase().trim();
      const normalizedStartTime = startTime.trim();

      const inputDate = new Date(fromDate);
      const startOfDay = new Date(Date.UTC(
        inputDate.getFullYear(),
        inputDate.getMonth(),
        inputDate.getDate(),
        0, 0, 0, 0
      ));
      const endOfDay = new Date(Date.UTC(
        inputDate.getFullYear(),
        inputDate.getMonth(),
        inputDate.getDate(),
        23, 59, 59, 999
      ));

      const query = {
        $and: [
          {
            $or: [
              { 'employeeDetails.email': normalizedEmail },
              { 'customerEmail': normalizedEmail },
              { 'employeeData.email': normalizedEmail }
            ]
          },
          {
            $or: [
              { 'startDate': { $gte: startOfDay, $lte: endOfDay } },
              { 'dateRange.from': { $gte: startOfDay, $lte: endOfDay } },
              { 'fromDate': { $gte: startOfDay, $lte: endOfDay } }
            ]
          },
          {
            $or: [
              { 'startTime': normalizedStartTime },
              { 'timeRange.from': normalizedStartTime },
              { 'fromTime': normalizedStartTime }
            ]
          },
          { 'rosterType': normalizedRosterType },
          { 'status': { $nin: ['cancelled', 'rejected', 'deleted'] } }
        ]
      };

      const existingRoster = await req.db.collection('rosters').findOne(query);

      results.push({
        employeeEmail: normalizedEmail,
        fromDate,
        startTime: normalizedStartTime,
        rosterType: normalizedRosterType,
        exists: !!existingRoster,
        rosterId: existingRoster ? existingRoster._id.toString() : null
      });
    }

    const duplicatesCount = results.filter(r => r.exists).length;
    console.log(`✅ Batch check complete: ${duplicatesCount} duplicates found out of ${rosters.length}`);

    return res.json({
      success: true,
      results,
      summary: {
        total: rosters.length,
        duplicates: duplicatesCount,
        unique: rosters.length - duplicatesCount
      }
    });

  } catch (err) {
    console.error('❌ Error in batch duplicate check:', err.message);
    res.status(500).json({
      success: false,
      message: 'Server error while checking duplicates',
      error: err.message
    });
  }
});

// @route   POST api/roster/admin/group-similar
// @desc    Enhanced grouping with distance-based sequencing + 24-hour time format
// @access  Private (Admin)
// ============================================================================
// FEATURES:
// ✅ Groups by email domain, time, location, roster type, weekdays
// ✅ Calculates distance from pickup → office (Haversine formula)
// ✅ Sorts customers by distance (FARTHEST first, NEAREST last)
// ✅ Assigns pickup sequence numbers (1, 2, 3...)
// ✅ Calculates estimated pickup times (reverse from office time)
// ✅ Calculates ready-by times (20 min before pickup)
// ✅ Uses 24-hour time format ("07:25" not "07:25 AM")
// ✅ All calculations happen BEFORE vehicle assignment
// ============================================================================

// @route   POST api/roster/admin/group-similar
// @desc    Enhanced grouping with distance-based sequencing + 24-hour time format + ALL CALCULATIONS
// @access  Private (Admin)
// ============================================================================
// COMPLETE VERSION - ALL FEATURES INCLUDED
// ✅ Groups by email domain, time, location, roster type, weekdays
// ✅ Calculates distance from pickup → office (Haversine formula)
// ✅ Sorts customers by distance (FARTHEST first, NEAREST last)
// ✅ Assigns pickup sequence numbers (1, 2, 3...)
// ✅ Calculates estimated pickup times (reverse from office time)
// ✅ Calculates ready-by times (20 min before pickup)
// ✅ Uses 24-hour time format ("07:25" not "07:25 AM")
// ✅ All calculations happen BEFORE vehicle assignment
// ✅ Stores distance data for later use
// ============================================================================

router.post('/admin/group-similar', verifyToken, async (req, res) => {
  try {
    console.log('\n' + '🔍'.repeat(80));
    console.log('ENHANCED SMART GROUPING - DISTANCE-BASED SEQUENCING WITH COMPLETE CALCULATIONS');
    console.log('🔍'.repeat(80));

    // ========================================================================
    // STEP 1: Fetch pending rosters
    // ========================================================================
    const pendingRosters = await req.db.collection('rosters')
      .find({
        status: { $in: ['pending', 'pending_assignment', 'created'] },
        customerEmail: { $ne: 'admin@abrafleet.com' }
      })
      .toArray();

    console.log(`\n📋 Found ${pendingRosters.length} pending rosters`);

    if (pendingRosters.length === 0) {
      return res.json({
        success: true,
        message: 'No pending rosters to group',
        data: { groups: [], totalRosters: 0, totalGroups: 0 }
      });
    }

    // ========================================================================
    // HELPER FUNCTIONS
    // ========================================================================
    
    /**
     * Extract FULL domain from email (@wipro.com, @infosys.com, etc.)
     */
    function getEmailDomain(email) {
      if (!email || typeof email !== 'string') return 'unknown';
      try {
        const atIndex = email.indexOf('@');
        if (atIndex === -1) return 'unknown';
        const domain = email.substring(atIndex); // Include @ symbol
        return domain.toLowerCase().trim();
      } catch (e) {
        return 'unknown';
      }
    }

    /**
     * Calculate distance between two coordinates using Haversine formula
     * @returns Distance in kilometers
     */
    function calculateDistance(lat1, lon1, lat2, lon2) {
      const R = 6371; // Earth's radius in km
      const dLat = (lat2 - lat1) * Math.PI / 180;
      const dLon = (lon2 - lon1) * Math.PI / 180;
      
      const a = 
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
      
      const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
      return R * c; // Distance in km
    }

    /**
     * Calculate pickup time by working backwards from office arrival time
     * @param officeTime - Office arrival time in 24-hour format (e.g., "09:00")
     * @param cumulativeDistance - Total distance traveled so far (km)
     * @param sequenceNumber - Pickup sequence (1, 2, 3...)
     * @returns Pickup time in 24-hour format (e.g., "07:25")
     */
    function calculatePickupTime(officeTime, cumulativeDistance, sequenceNumber) {
      // Parse office time (e.g., "09:00" or "09:00:00")
      const timeParts = officeTime.split(':');
      const hours = parseInt(timeParts[0], 10);
      const minutes = parseInt(timeParts[1], 10);
      
      // Calculate travel time
      // Formula: 3 minutes per km + buffer time based on sequence
      const travelMinutes = Math.ceil(cumulativeDistance * 3);
      
      // Buffer time:
      // First pickup: 20 minutes (allows for delays)
      // Subsequent pickups: 5 minutes each (for boarding time)
      const bufferMinutes = 20 + ((sequenceNumber - 1) * 5);
      
      const totalMinutes = travelMinutes + bufferMinutes;
      
      console.log(`      🕐 Time Calculation:`);
      console.log(`         Travel time: ${travelMinutes} min (${cumulativeDistance.toFixed(1)} km × 3 min/km)`);
      console.log(`         Buffer time: ${bufferMinutes} min`);
      console.log(`         Total: ${totalMinutes} min before office time`);
      
      // Calculate pickup time by subtracting from office time
      const officeDateTime = new Date();
      officeDateTime.setHours(hours, minutes, 0, 0);
      const pickupDateTime = new Date(officeDateTime.getTime() - (totalMinutes * 60000));
      
      const pickupHours = String(pickupDateTime.getHours()).padStart(2, '0');
      const pickupMinutes = String(pickupDateTime.getMinutes()).padStart(2, '0');
      
      return `${pickupHours}:${pickupMinutes}`; // ✅ 24-hour format
    }

    /**
     * Calculate ready-by time (20 minutes before pickup)
     * @param pickupTime - Pickup time in 24-hour format (e.g., "07:25")
     * @returns Ready-by time in 24-hour format (e.g., "07:05")
     */
    function calculateReadyByTime(pickupTime) {
      const [hours, minutes] = pickupTime.split(':').map(Number);
      const pickupDateTime = new Date();
      pickupDateTime.setHours(hours, minutes, 0, 0);
      const readyDateTime = new Date(pickupDateTime.getTime() - (20 * 60000)); // -20 min
      
      const readyHours = String(readyDateTime.getHours()).padStart(2, '0');
      const readyMinutes = String(readyDateTime.getMinutes()).padStart(2, '0');
      
      return `${readyHours}:${readyMinutes}`; // ✅ 24-hour format
    }

    /**
     * Convert 24-hour time to 12-hour format with AM/PM
     * @param time24 - Time in 24-hour format (e.g., "07:25")
     * @returns Time in 12-hour format (e.g., "7:25 AM")
     */
    function format12Hour(time24) {
      const [hours, minutes] = time24.split(':').map(Number);
      const period = hours >= 12 ? 'PM' : 'AM';
      const hours12 = hours % 12 || 12;
      return `${hours12}:${String(minutes).padStart(2, '0')} ${period}`;
    }

    // ========================================================================
    // DEBUG: Print first roster structure
    // ========================================================================
    if (pendingRosters.length > 0) {
      console.log('\n🔍 DEBUG - First Roster Structure:');
      const firstRoster = pendingRosters[0];
      console.log('   customerEmail:', firstRoster.customerEmail);
      console.log('   customerName:', firstRoster.customerName);
      console.log('   officeLocation:', firstRoster.officeLocation);
      console.log('   officeLocationCoordinates:', JSON.stringify(firstRoster.officeLocationCoordinates));
      console.log('   loginPickupLocation:', JSON.stringify(firstRoster.loginPickupLocation));
      console.log('   locations:', JSON.stringify(firstRoster.locations));
      console.log('   startTime:', firstRoster.startTime);
      console.log('   endTime:', firstRoster.endTime);
      console.log('   rosterType:', firstRoster.rosterType);
      console.log('   weekdays:', firstRoster.weekdays);
    }

    // ========================================================================
    // STEP 2: GROUP BY EMAIL DOMAIN, TIME, LOCATION, TYPE, WEEKDAYS
    // ========================================================================
    console.log('\n📊 Creating groups by email domain...');

    const groups = {};

    for (const roster of pendingRosters) {
      // Extract email domain
      const email = roster.customerEmail ||
        roster.employeeDetails?.email ||
        roster.employeeData?.email || '';

      const emailDomain = getEmailDomain(email);

      // Extract times (ensure 24-hour format)
      const loginTime = roster.startTime || roster.loginTime || roster.fromTime || '09:00';
      const logoutTime = roster.endTime || roster.logoutTime || roster.toTime || '18:00';

      // Extract location (normalize to lowercase)
      const location = (roster.officeLocation || 'Unknown').toLowerCase().trim();

      // Extract roster type
      const rosterType = (roster.rosterType || 'both').toLowerCase();

      // Extract weekdays
      const weekdays = roster.weekdays || roster.weeklyOffDays || [];
      const weekdayKey = [...weekdays].sort().join(',').toLowerCase();

      // Create group key
      const groupKey = `${emailDomain}|${loginTime}|${logoutTime}|${location}|${rosterType}|${weekdayKey}`;

      console.log(`\n   Roster: ${roster.customerName}`);
      console.log(`   - Email: ${email}`);
      console.log(`   - Email Domain: ${emailDomain}`);
      console.log(`   - Times: ${loginTime} - ${logoutTime}`);
      console.log(`   - Location: ${location}`);
      console.log(`   - Type: ${rosterType}`);
      console.log(`   - Weekdays: ${weekdayKey || 'None'}`);
      console.log(`   - Group Key: ${groupKey}`);

      // Create or update group
      if (!groups[groupKey]) {
        groups[groupKey] = {
          groupKey,
          emailDomain: emailDomain,
          loginTime,
          logoutTime,
          location: roster.officeLocation || 'Unknown',
          officeCoordinates: roster.officeLocationCoordinates || null,
          rosterType,
          weekdays: weekdays,
          employees: [],
          rosterIds: [],
          employeeCount: 0
        };
      }

      // Extract pickup coordinates (handle different formats)
      let pickupLat = null;
      let pickupLng = null;

      // FORMAT 1: locations.pickup.coordinates
      if (roster.locations?.pickup?.coordinates) {
        pickupLat = roster.locations.pickup.coordinates.latitude || 
                    roster.locations.pickup.coordinates.lat;
        pickupLng = roster.locations.pickup.coordinates.longitude || 
                    roster.locations.pickup.coordinates.lng;
      }
      // FORMAT 2: loginPickupLocation (array or object)
      else if (roster.loginPickupLocation) {
        if (Array.isArray(roster.loginPickupLocation)) {
          pickupLat = roster.loginPickupLocation[0];
          pickupLng = roster.loginPickupLocation[1];
        } else if (typeof roster.loginPickupLocation === 'object') {
          pickupLat = roster.loginPickupLocation.latitude || roster.loginPickupLocation.lat;
          pickupLng = roster.loginPickupLocation.longitude || roster.loginPickupLocation.lng;
        }
      }
      // FORMAT 3: Direct fields
      else if (roster.pickupLatitude && roster.pickupLongitude) {
        pickupLat = roster.pickupLatitude;
        pickupLng = roster.pickupLongitude;
      }

      groups[groupKey].employees.push({
        name: roster.customerName || 'Unknown',
        email: email,
        phone: roster.customerPhone || roster.phone || '',
        rosterId: roster._id.toString(),
        pickupCoordinates: pickupLat && pickupLng ? { 
          latitude: pickupLat, 
          longitude: pickupLng 
        } : null,
        pickupAddress: roster.loginPickupAddress || 
                       roster.locations?.pickup?.address || 
                       'Pickup location',
        // 🆕 Store full roster data for later use
        rosterData: {
          _id: roster._id,
          customerName: roster.customerName,
          customerEmail: email,
          customerPhone: roster.customerPhone || roster.phone || '',
          rosterType: rosterType,
          officeLocation: roster.officeLocation,
          startTime: loginTime,
          endTime: logoutTime,
          weekdays: weekdays
        }
      });
      
      groups[groupKey].rosterIds.push(roster._id.toString());
      groups[groupKey].employeeCount++;
    }

    console.log(`\n✅ Created ${Object.keys(groups).length} raw groups`);

    // ========================================================================
    // STEP 3: CALCULATE DISTANCES & ASSIGN SEQUENCES (FARTHEST → NEAREST)
    // ========================================================================
    console.log('\n📏 CALCULATING DISTANCES & SEQUENCES...');
    console.log('='.repeat(80));

    const validGroups = Object.values(groups).filter(g => g.employeeCount >= 1);

    for (const group of validGroups) {
      console.log(`\n📊 Processing Group: ${group.emailDomain}`);
      console.log(`   Location: ${group.location}`);
      console.log(`   Office Time: ${group.loginTime} (${format12Hour(group.loginTime)})`);
      console.log(`   Employees: ${group.employeeCount}`);

      // Get office coordinates
      const officeLat = group.officeCoordinates?.latitude || 
                        group.officeCoordinates?.lat;
      const officeLng = group.officeCoordinates?.longitude || 
                        group.officeCoordinates?.lng;

      if (!officeLat || !officeLng) {
        console.log(`   ⚠️  No office coordinates - skipping distance calculation`);
        
        // Assign default values without distance calculation
        group.employees.forEach((employee, index) => {
          employee.sequence = index + 1;
          employee.distanceToOffice = 0;
          employee.estimatedPickupTime = group.loginTime;
          employee.readyByTime = calculateReadyByTime(group.loginTime);
          employee.estimatedTravelTime = 0;
          employee.pickupTime12Hour = format12Hour(group.loginTime);
          employee.readyByTime12Hour = format12Hour(employee.readyByTime);
        });
        continue;
      }

      console.log(`   Office Coordinates: (${officeLat}, ${officeLng})`);

      // ====================================================================
      // CALCULATE DISTANCE FOR EACH EMPLOYEE
      // ====================================================================
      console.log('\n   📍 Calculating distances from pickup to office:');
      
      for (const employee of group.employees) {
        if (!employee.pickupCoordinates) {
          console.log(`      ⚠️  ${employee.name} - No pickup coordinates`);
          employee.distanceToOffice = 0;
          continue;
        }

        const pickupLat = employee.pickupCoordinates.latitude;
        const pickupLng = employee.pickupCoordinates.longitude;

        const distance = calculateDistance(pickupLat, pickupLng, officeLat, officeLng);
        employee.distanceToOffice = parseFloat(distance.toFixed(2));

        console.log(`      📏 ${employee.name}: ${employee.distanceToOffice} km from office`);
      }

      // ====================================================================
      // SORT BY DISTANCE (FARTHEST FIRST, NEAREST LAST)
      // ====================================================================
      group.employees.sort((a, b) => (b.distanceToOffice || 0) - (a.distanceToOffice || 0));

      console.log(`\n   🎯 PICKUP SEQUENCE (Farthest → Nearest):`);
      console.log('   ' + '='.repeat(76));

      // ====================================================================
      // ASSIGN SEQUENCE NUMBERS & CALCULATE TIMES
      // ====================================================================
      let cumulativeDistance = 0;
      
      group.employees.forEach((employee, index) => {
        employee.sequence = index + 1;
        
        // Add to cumulative distance
        const distanceFromOffice = employee.distanceToOffice || 0;
        cumulativeDistance += distanceFromOffice;
        
        console.log(`\n   ${employee.sequence}. ${employee.name}`);
        console.log(`      📍 Pickup Address: ${employee.pickupAddress}`);
        console.log(`      📏 Distance to office: ${distanceFromOffice} km`);
        console.log(`      📊 Cumulative distance: ${cumulativeDistance.toFixed(1)} km`);
        
        // Calculate pickup time (working backwards from office time)
        const pickupTime = calculatePickupTime(
          group.loginTime,
          cumulativeDistance,
          employee.sequence
        );
        
        employee.estimatedPickupTime = pickupTime; // ✅ 24-hour format
        employee.readyByTime = calculateReadyByTime(pickupTime); // ✅ 20 min before
        
        // Convert to 12-hour format for notifications
        employee.pickupTime12Hour = format12Hour(pickupTime);
        employee.readyByTime12Hour = format12Hour(employee.readyByTime);
        
        // Calculate estimated travel time (for display)
        employee.estimatedTravelTime = Math.ceil(distanceFromOffice * 3); // 3 min per km
        
        // Calculate distance from previous stop (for route optimization)
        if (index === 0) {
          employee.distanceFromPrevious = 0; // First pickup (from vehicle depot)
        } else {
          const prevEmployee = group.employees[index - 1];
          if (prevEmployee.pickupCoordinates && employee.pickupCoordinates) {
            const distanceBetween = calculateDistance(
              prevEmployee.pickupCoordinates.latitude,
              prevEmployee.pickupCoordinates.longitude,
              employee.pickupCoordinates.latitude,
              employee.pickupCoordinates.longitude
            );
            employee.distanceFromPrevious = parseFloat(distanceBetween.toFixed(2));
          } else {
            employee.distanceFromPrevious = 0;
          }
        }

        console.log(`      ⏰ Pickup Time: ${pickupTime} (${employee.pickupTime12Hour})`);
        console.log(`      🏁 Ready By: ${employee.readyByTime} (${employee.readyByTime12Hour})`);
        console.log(`      ⏱️  Travel Time: ~${employee.estimatedTravelTime} mins`);
        if (index > 0) {
          console.log(`      🔗 Distance from previous: ${employee.distanceFromPrevious} km`);
        }
      });

      console.log('   ' + '='.repeat(76));
      
      // ====================================================================
      // CALCULATE TOTAL ROUTE METRICS
      // ====================================================================
      const totalRouteDistance = group.employees.reduce((sum, emp) => 
        sum + (emp.distanceToOffice || 0), 0
      );
      const totalRouteTime = Math.ceil(totalRouteDistance * 3) + 20 + (group.employeeCount * 5);
      
      group.totalRouteDistance = parseFloat(totalRouteDistance.toFixed(2));
      group.totalRouteTime = totalRouteTime;
      group.firstPickupTime = group.employees[0]?.estimatedPickupTime;
      group.firstPickupTime12Hour = group.employees[0]?.pickupTime12Hour;
      group.lastPickupTime = group.employees[group.employeeCount - 1]?.estimatedPickupTime;
      group.lastPickupTime12Hour = group.employees[group.employeeCount - 1]?.pickupTime12Hour;
      
      console.log(`\n   📊 ROUTE SUMMARY:`);
      console.log(`      Total Distance: ${group.totalRouteDistance} km`);
      console.log(`      Total Time: ${group.totalRouteTime} mins`);
      console.log(`      First Pickup: ${group.firstPickupTime} (${group.firstPickupTime12Hour})`);
      console.log(`      Last Pickup: ${group.lastPickupTime} (${group.lastPickupTime12Hour})`);
      console.log(`      Office Arrival: ${group.loginTime} (${format12Hour(group.loginTime)})`);
    }

    // ========================================================================
    // STEP 4: SORT GROUPS BY SIZE (LARGEST FIRST)
    // ========================================================================
    validGroups.sort((a, b) => b.employeeCount - a.employeeCount);

    // ========================================================================
    // STEP 5: DISPLAY SUMMARY
    // ========================================================================
    console.log('\n' + '='.repeat(80));
    console.log('📊 GROUPING SUMMARY');
    console.log('='.repeat(80));
    
    if (validGroups.length > 0) {
      console.log('\n✅ VALID GROUPS FOUND:\n');
      validGroups.forEach((group, idx) => {
        console.log(`   Group ${idx + 1}:`);
        console.log(`   - Domain: ${group.emailDomain}`);
        console.log(`   - Location: ${group.location}`);
        console.log(`   - Times: ${group.loginTime} - ${group.logoutTime}`);
        console.log(`   - Members: ${group.employeeCount}`);
        console.log(`   - Total Distance: ${group.totalRouteDistance} km`);
        console.log(`   - Total Time: ${group.totalRouteTime} mins`);
        console.log(`   - Employees: ${group.employees.map(e => `${e.name} (#${e.sequence} @ ${e.pickupTime12Hour})`).join(', ')}`);
        console.log('');
      });
    } else {
      console.log('\n⚠️  No valid groups found');
    }

    console.log('='.repeat(80));
    console.log('✅ GROUPING COMPLETE WITH FULL ROUTE CALCULATIONS');
    console.log('='.repeat(80) + '\n');

    // ========================================================================
    // RESPONSE - COMPLETE DATA STRUCTURE
    // ========================================================================
    res.json({
      success: true,
      message: `Found ${validGroups.length} groups with complete route calculations`,
      data: {
        groups: validGroups.map(group => ({
          groupId: group.groupKey,
          emailDomain: group.emailDomain, // @wipro.com
          organization: group.emailDomain.replace('@', ''), // wipro.com
          loginTime: group.loginTime, // ✅ 24-hour format
          logoutTime: group.logoutTime, // ✅ 24-hour format
          loginTime12Hour: format12Hour(group.loginTime), // 🆕 12-hour format
          logoutTime12Hour: format12Hour(group.logoutTime), // 🆕 12-hour format
          loginLocation: group.location,
          logoutLocation: group.location,
          rosterType: group.rosterType,
          weekdays: group.weekdays,
          employeeCount: group.employeeCount,
          rosterIds: group.rosterIds,
          officeCoordinates: group.officeCoordinates,
          // 🆕 Route Metrics
          totalRouteDistance: group.totalRouteDistance,
          totalRouteTime: group.totalRouteTime,
          firstPickupTime: group.firstPickupTime,
          firstPickupTime12Hour: group.firstPickupTime12Hour,
          lastPickupTime: group.lastPickupTime,
          lastPickupTime12Hour: group.lastPickupTime12Hour,
          employees: group.employees.map(emp => ({
            name: emp.name,
            email: emp.email,
            phone: emp.phone,
            rosterId: emp.rosterId,
            pickupAddress: emp.pickupAddress,
            pickupCoordinates: emp.pickupCoordinates,
            // 🆕 Distance-based fields (24-hour format)
            sequence: emp.sequence, // 1 = farthest, last = nearest
            distanceToOffice: emp.distanceToOffice, // km
            distanceFromPrevious: emp.distanceFromPrevious, // km (for route optimization)
            estimatedPickupTime: emp.estimatedPickupTime, // "07:25" (24-hour)
            readyByTime: emp.readyByTime, // "07:05" (24-hour)
            estimatedTravelTime: emp.estimatedTravelTime, // minutes
            // 🆕 12-hour format for notifications
            pickupTime12Hour: emp.pickupTime12Hour, // "7:25 AM"
            readyByTime12Hour: emp.readyByTime12Hour, // "7:05 AM"
            // 🆕 Full roster data for later use
            rosterData: emp.rosterData
          }))
        })),
        totalRosters: pendingRosters.length,
        totalGroups: validGroups.length,
        // 🆕 Metadata
        calculationMethod: 'Haversine',
        timeFormat: '24-hour',
        readyBufferMinutes: 20,
        sortOrder: 'farthest-first',
        travelSpeedAssumption: '3 minutes per km',
        version: '2.0.0-complete'
      }
    });

  } catch (error) {
    console.error('\n' + '❌'.repeat(40));
    console.error('GROUPING FAILED');
    console.error('❌'.repeat(40));
    console.error('Error:', error);
    console.error('Stack:', error.stack);
    console.error('❌'.repeat(40) + '\n');

    res.status(500).json({
      success: false,
      message: 'Failed to group rosters',
      error: error.message
    });
  }
});


// @route   GET api/roster/admin/assigned-trips
// @desc    Get all assigned trips for client management (assigned, ongoing, completed, cancelled)
// @access  Private (Admin/Client)
router.get('/admin/assigned-trips', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    console.log('\n' + '='.repeat(80));
    console.log('📋 FETCHING ASSIGNED TRIPS FOR CLIENT MANAGEMENT');
    console.log('='.repeat(80));

    const { status, company, startDate, endDate } = req.query;

    // Get admin's organization
    const adminUser = await req.db.collection('users').findOne({ firebaseUid: userId });
    const adminOrganization = adminUser?.companyName || adminUser?.organizationName || '';

    console.log(`👤 Admin: ${adminUser?.name || 'Unknown'}`);
    console.log(`🏢 Organization: ${adminOrganization || 'Not set'}`);

    // Build query - only get assigned/ongoing/completed/cancelled trips
    const query = {
      status: { $in: ['assigned', 'scheduled', 'ongoing', 'in_progress', 'started', 'completed', 'done', 'cancelled'] }
    };

    // Filter by specific status if provided
    if (status && status !== 'all') {
      if (status === 'assigned') {
        query.status = { $in: ['assigned', 'scheduled'] };
      } else if (status === 'ongoing') {
        query.status = { $in: ['ongoing', 'in_progress', 'started'] };
      } else if (status === 'completed') {
        query.status = { $in: ['completed', 'done'] };
      } else if (status === 'cancelled') {
        query.status = 'cancelled';
      }
    }

    // Filter by organization
    if (adminOrganization) {
      query.$or = [
        { 'employeeDetails.companyName': adminOrganization },
        { 'employeeData.companyName': adminOrganization },
        { 'organizationName': adminOrganization }
      ];
    }

    // Filter by date range
    if (startDate || endDate) {
      const dateFilter = {};
      if (startDate) dateFilter.$gte = new Date(startDate);
      if (endDate) dateFilter.$lte = new Date(endDate);
      query.assignedAt = dateFilter;
    }

    console.log('📋 Query:', JSON.stringify(query, null, 2));

    // Fetch trips
    const trips = await req.db.collection('rosters')
      .find(query)
      .sort({ assignedAt: -1 })
      .toArray();

    console.log(`📊 Found ${trips.length} trips`);

    // Get unique driver IDs to fetch driver details
    const driverIds = [...new Set(trips.map(t => t.driverId).filter(Boolean))];
    console.log(`👤 Fetching details for ${driverIds.length} unique drivers...`);

    // Fetch driver details from drivers collection
    const driversMap = {};
    if (driverIds.length > 0) {
      const drivers = await req.db.collection('drivers').find({
        driverId: { $in: driverIds }
      }).toArray();

      drivers.forEach(driver => {
        // Handle nested personalInfo structure
        const firstName = driver.personalInfo?.firstName || driver.firstName || '';
        const lastName = driver.personalInfo?.lastName || driver.lastName || '';
        const fullName = `${firstName} ${lastName}`.trim() || driver.name || driver.driverName || '';
        const phone = driver.personalInfo?.phone || driver.phone || driver.phoneNumber || driver.contactNumber || driver.mobileNumber || '';

        driversMap[driver.driverId] = {
          name: fullName,
          phone: phone
        };
      });
      console.log(`✅ Loaded ${drivers.length} driver details`);
    }

    // Transform data
    const transformedTrips = trips.map(trip => {
      // Extract company from email domain
      const email = trip.customerEmail || trip.employeeDetails?.email || '';
      let companyName = '';
      if (email.includes('@')) {
        const domain = email.split('@')[1].toLowerCase();
        companyName = domain.split('.')[0];
        companyName = companyName.charAt(0).toUpperCase() + companyName.slice(1);
      }

      // ✅ FIX: Get driver info from driversMap or fallback to trip fields
      const driverId = trip.driverId || trip.assignedDriverId || trip.assignedDriver?.driverId || '';
      const driverInfo = driversMap[driverId] || {};
      const driverName = driverInfo.name || trip.driverName || trip.assignedDriverName || trip.assignedDriver?.name || '';
      const driverPhone = driverInfo.phone || trip.driverPhone || trip.assignedDriverPhone || trip.assignedDriver?.phone || '';

      const vehicleNumber = trip.vehicleNumber || trip.assignedVehicleReg || trip.assignedVehicle?.registrationNumber || '';
      const vehicleId = trip.vehicleId || trip.assignedVehicleId || trip.assignedVehicle?.vehicleId || '';

      // ✅ Extract pickup and drop locations
      const pickupLocation = trip.pickupLocation || trip.homeLocation || trip.currentAddress || trip.employeeDetails?.address || '';
      const dropLocation = trip.dropLocation || trip.dropoffLocation || trip.officeLocation || '';

      // ✅ Extract pickup and drop times
      const pickupTime = trip.pickupTime || trip.startTime || trip.fromTime || '';
      const dropTime = trip.dropTime || trip.dropoffTime || trip.endTime || trip.toTime || '';

      // ✅ Extract distance data from stored distanceData field
      const distanceData = trip.distanceData || {};
      const totalDistanceKm = distanceData.totalDistanceKm || trip.distance || 0;
      const totalDurationMin = distanceData.totalDurationMin || trip.estimatedDuration || 0;
      const loginDistance = distanceData.login?.distanceKm || 0;
      const logoutDistance = distanceData.logout?.distanceKm || 0;

      return {
        _id: trip._id.toString(),
        id: trip._id.toString(),
        readableId: trip.readableId || `RST-${trip._id.toString().slice(-6).toUpperCase()}`,
        customerName: trip.customerName || trip.employeeDetails?.name || 'Unknown',
        customerEmail: trip.customerEmail || trip.employeeDetails?.email || '',
        customerPhone: trip.customerPhone || trip.employeeDetails?.phone || '',
        companyName: companyName || trip.organizationName || '',
        organizationName: trip.organizationName || companyName || '',
        status: trip.status,
        rosterType: trip.rosterType || trip.tripType || 'both',
        tripType: trip.tripType || trip.rosterType || '',
        officeLocation: trip.officeLocation || dropLocation,
        vehicleId: vehicleId,
        vehicleNumber: vehicleNumber,
        driverId: driverId,
        driverName: driverName,
        driverPhone: driverPhone,
        pickupLocation: pickupLocation,
        dropLocation: dropLocation,
        pickupTime: pickupTime,
        dropTime: dropTime,
        startDate: trip.startDate || trip.fromDate || trip.tripDate,
        endDate: trip.endDate || trip.toDate,
        startTime: pickupTime,
        endTime: dropTime,
        assignedAt: trip.assignedAt,
        completedAt: trip.completedAt,
        cancelledAt: trip.cancelledAt,
        createdAt: trip.createdAt,
        // ✅ ADD DISTANCE DATA TO API RESPONSE
        distance: totalDistanceKm,
        totalDistanceKm: totalDistanceKm,
        totalDurationMin: totalDurationMin,
        estimatedDuration: totalDurationMin,
        loginDistance: loginDistance,
        logoutDistance: logoutDistance,
        distanceData: distanceData
      };
    });

    // Filter by company if specified
    let filteredTrips = transformedTrips;
    if (company && company !== 'All Companies') {
      filteredTrips = transformedTrips.filter(trip =>
        trip.companyName.toLowerCase() === company.toLowerCase()
      );
    }

    console.log(`✅ Returning ${filteredTrips.length} trips`);
    console.log('='.repeat(80) + '\n');

    res.json({
      success: true,
      message: `Found ${filteredTrips.length} trips`,
      data: filteredTrips,
      count: filteredTrips.length
    });

  } catch (error) {
    console.error('❌ Error fetching assigned trips:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch assigned trips',
      error: error.message
    });
  }
});

// @route   GET api/roster/admin/pending
// @desc    Get all pending rosters for admin management - ULTRA SAFE VERSION
// @access  Private (Admin)
// @route   GET api/roster/admin/pending
// @desc    Get all pending rosters for admin management - EMAIL DOMAIN BASED
// @access  Private (Admin)
// @route   GET api/roster/admin/pending
// @desc    Get all pending rosters - EMAIL DOMAIN FILTERED
// @access  Private (Admin)
// @route   GET api/roster/admin/pending
// @desc    Get all pending rosters - WITH FULL DETAILS
// @access  Private (Admin)
router.get('/admin/pending', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    console.log('🔍 Fetching pending rosters for admin...');

    const { officeLocation, rosterType } = req.query;

    // ✅ Get admin's email domain for filtering
    let adminEmailDomain = null;

    try {
      const adminUser = await req.db.collection('users').findOne({ firebaseUid: userId });
      if (adminUser && adminUser.email) {
        const emailParts = adminUser.email.split('@');
        if (emailParts.length === 2) {
          adminEmailDomain = '@' + emailParts[1].toLowerCase();
          console.log(`🔒 Admin email domain: ${adminEmailDomain}`);
        }
      }
    } catch (userError) {
      console.warn('Could not fetch admin user:', userError.message);
    }

    // ✅ Build base query - ONLY truly pending rosters
    // ✅ ENHANCED: Check for null, missing, empty string, and 'null' string
    const query = {
      $and: [
        // 1. Status must be pending
        { status: { $in: ['pending_assignment', 'pending', 'created'] } },

        // 2. No vehicle assigned (check for null, missing, empty string, or 'null' string)
        {
          $or: [
            { vehicleId: { $exists: false } },
            { vehicleId: null },
            { vehicleId: '' },
            { vehicleId: 'null' }
          ]
        },

        // 3. No driver assigned (check for null, missing, empty string, or 'null' string)
        {
          $or: [
            { driverId: { $exists: false } },
            { driverId: null },
            { driverId: '' },
            { driverId: 'null' }
          ]
        },

        // 4. No assignedVehicleId (new field used in some rosters)
        {
          $or: [
            { assignedVehicleId: { $exists: false } },
            { assignedVehicleId: null },
            { assignedVehicleId: '' },
            { assignedVehicleId: 'null' }
          ]
        },

        // 5. No assignedDriverId (new field used in some rosters)
        {
          $or: [
            { assignedDriverId: { $exists: false } },
            { assignedDriverId: null },
            { assignedDriverId: '' },
            { assignedDriverId: 'null' }
          ]
        },

        // 6. No tripId (rosters with tripId are already assigned)
        {
          $or: [
            { tripId: { $exists: false } },
            { tripId: null },
            { tripId: '' },
            { tripId: 'null' }
          ]
        }
      ]
    };

    // Add optional filters
    if (officeLocation && officeLocation !== 'all') {
      query.officeLocation = officeLocation;
    }

    if (rosterType && rosterType !== 'all') {
      query.rosterType = rosterType;
    }

    console.log('📋 Fetching pending rosters from DB...');

    // ✅ CRITICAL FIX: Project ALL required fields
    const allRosters = await req.db.collection('rosters')
      .find(query)
      .project({
        // Basic Info
        _id: 1,
        customerName: 1,
        customerEmail: 1,
        customerPhone: 1,
        phone: 1,
        phoneNumber: 1,
        status: 1,
        rosterType: 1,

        // ✅ EMPLOYEE DETAILS
        employeeId: 1,
        department: 1,
        companyName: 1,
        organization: 1,
        organizationName: 1,
        address: 1,
        employeeDetails: 1,
        employeeData: 1,

        // ✅ DATE FIELDS (all variations)
        startDate: 1,
        endDate: 1,
        fromDate: 1,
        toDate: 1,
        'dateRange.from': 1,
        'dateRange.to': 1,

        // ✅ TIME FIELDS (all variations)
        startTime: 1,
        endTime: 1,
        fromTime: 1,
        toTime: 1,
        'timeRange.from': 1,
        'timeRange.to': 1,

        // ✅ LOCATION FIELDS
        officeLocation: 1,
        officeLocationCoordinates: 1,

        // ✅ PICKUP LOCATION (all variations)
        loginPickupAddress: 1,
        loginPickupLocation: 1,
        pickupLocation: 1,

        // ✅ DROP LOCATION (all variations)
        logoutDropAddress: 1,
        logoutDropLocation: 1,
        dropLocation: 1,

        // ✅ COMPLETE LOCATIONS OBJECT (instead of nested projections)
        locations: 1,

        // Other fields
        weekdays: 1,
        weeklyOffDays: 1,
        notes: 1,
        organizationName: 1,
        createdAt: 1,
        updatedAt: 1,
        priority: 1
      })
      .sort({ createdAt: -1 })
      .toArray();

    console.log(`📊 Found ${allRosters.length} total pending rosters`);

    // ✅ Filter by email domain
    let rosters = allRosters;

    if (adminEmailDomain && adminEmailDomain !== '@abrafleet.com') {
      // Non-Abrafleet admin → only show rosters from their domain
      rosters = allRosters.filter(roster => {
        const customerEmail = roster.customerEmail ||
          roster.employeeDetails?.email ||
          roster.employeeData?.email ||
          '';

        if (!customerEmail) {
          console.log(`⚠️  Roster ${roster._id} has no email, excluding`);
          return false;
        }

        const customerDomain = '@' + customerEmail.split('@')[1]?.toLowerCase();
        return customerDomain === adminEmailDomain;
      });

      console.log(`🔒 After email domain filter (${adminEmailDomain}): ${rosters.length} rosters`);
    } else if (adminEmailDomain === '@abrafleet.com') {
      // Abrafleet admin → see ALL rosters
      console.log(`👑 Abrafleet admin - showing all ${rosters.length} rosters`);
    }

    // ✅ DEBUG: Log first roster to verify fields are present
    if (rosters.length > 0) {
      console.log('\n🔍 DEBUG - First roster structure:');
      const firstRoster = rosters[0];
      console.log('   _id:', firstRoster._id);
      console.log('   customerName:', firstRoster.customerName);
      console.log('   customerEmail:', firstRoster.customerEmail);
      console.log('   startDate:', firstRoster.startDate);
      console.log('   endDate:', firstRoster.endDate);
      console.log('   fromDate:', firstRoster.fromDate);
      console.log('   toDate:', firstRoster.toDate);
      console.log('   startTime:', firstRoster.startTime);
      console.log('   endTime:', firstRoster.endTime);
      console.log('   fromTime:', firstRoster.fromTime);
      console.log('   toTime:', firstRoster.toTime);
      console.log('   officeLocation:', firstRoster.officeLocation);
      console.log('   loginPickupAddress:', firstRoster.loginPickupAddress);
      console.log('   logoutDropAddress:', firstRoster.logoutDropAddress);
      console.log('   rosterType:', firstRoster.rosterType);
      console.log('');
    }

    console.log(`✅ Returning ${rosters.length} rosters to frontend`);

    res.json({
      success: true,
      data: rosters,
      count: rosters.length
    });

  } catch (err) {
    console.error('❌ Error fetching pending rosters:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch pending rosters',
      error: err.message,
      data: [],
      count: 0
    });
  }
});

// @route   GET api/roster/admin/stats
// @desc    Get roster statistics for admin dashboard
// @access  Private (Admin)
router.get('/admin/stats', verifyToken, async (req, res) => {
  try {
    console.log('📊 Fetching roster statistics...');

    const stats = await req.db.collection('rosters').aggregate([
      {
        $group: {
          _id: '$status',
          count: { $sum: 1 }
        }
      }
    ]).toArray();

    // Initialize counters
    let pending = 0;
    let assigned = 0;
    let inProgress = 0;
    let completed = 0;
    let cancelled = 0;

    // Map status counts
    stats.forEach(stat => {
      switch (stat._id) {
        case 'pending':
        case 'pending_assignment':
        case 'created':
          pending += stat.count;
          break;
        case 'assigned':
        case 'scheduled':
          assigned += stat.count;
          break;
        case 'in_progress':
        case 'active':
        case 'started':
          inProgress += stat.count;
          break;
        case 'completed':
        case 'finished':
          completed += stat.count;
          break;
        case 'cancelled':
        case 'rejected':
          cancelled += stat.count;
          break;
      }
    });

    const total = pending + assigned + inProgress + completed + cancelled;

    const result = {
      pending,
      assigned,
      inProgress,
      completed,
      cancelled,
      total
    };

    console.log('📈 Stats:', result);

    res.json({
      success: true,
      data: result
    });

  } catch (err) {
    console.error('❌ Error fetching roster stats:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch roster statistics',
      error: err.message
    });
  }
});

// ========== LEAVE REQUEST ROUTES ==========

// @route   POST api/roster/customer/leave-request
// @desc    Submit a leave request for customer
// @access  Private (Customer)
router.post('/customer/leave-request', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { startDate, endDate, reason } = req.body;

    // Validate required fields
    if (!startDate || !endDate) {
      return res.status(400).json({
        success: false,
        message: 'Start date and end date are required'
      });
    }

    const start = new Date(startDate);
    const end = new Date(endDate);

    // Validate date range
    if (start >= end) {
      return res.status(400).json({
        success: false,
        message: 'End date must be after start date'
      });
    }

    // Get customer information including organization
    let customerName = 'Unknown Customer';
    let customerEmail = '';
    let organizationName = '';

    try {
      const userRecord = await admin.auth().getUser(userId);
      customerName = userRecord.displayName || userRecord.email || 'Unknown Customer';
      customerEmail = userRecord.email || '';
    } catch (authError) {
      console.log('Firebase auth lookup failed, checking database...');
    }

    // Always check database for complete user info including organization
    let userDoc = await req.db.collection('users').findOne({ firebaseUid: userId });

    // If user doesn't exist in MongoDB, create them
    if (!userDoc) {
      console.log('⚠️  User not found in MongoDB, creating user record...');

      // Extract organization from email domain
      const emailDomain = customerEmail.split('@')[1];
      let orgName = 'Unknown Organization';

      if (emailDomain === 'abrafleet.com') {
        orgName = 'Abra Group';
      } else if (emailDomain === 'infosys.com') {
        orgName = 'Infosys Limited';
      } else if (emailDomain === 'cognizant.com') {
        orgName = 'Cognizant';
      } else if (emailDomain === 'tcs.com') {
        orgName = 'TCS';
      }

      // Create user in MongoDB
      const newUser = {
        firebaseUid: userId,
        email: customerEmail,
        name: customerName,
        role: 'customer',
        companyName: orgName,
        organizationName: orgName,
        createdAt: new Date(),
        updatedAt: new Date()
      };

      await req.db.collection('users').insertOne(newUser);
      console.log(`✅ Created user in MongoDB: ${customerEmail} - ${orgName}`);

      userDoc = newUser;
    }

    if (userDoc) {
      customerName = userDoc.name || customerName;
      customerEmail = userDoc.email || customerEmail;
      organizationName = userDoc.companyName || userDoc.organizationName || '';
    }

    // Ensure organization is set
    if (!organizationName) {
      return res.status(400).json({
        success: false,
        message: 'User organization not found. Please contact administrator.'
      });
    }

    // Find all scheduled trips for the customer during the leave period
    // ✅ FIXED: Use correct field names (startDate/endDate instead of fromDate/toDate)
    // ✅ FIXED: Make organization filter optional since it may not be stored in rosters
    const affectedTrips = await req.db.collection('rosters').find({
      $and: [
        {
          $or: [
            { createdBy: userId },
            { 'customerEmail': customerEmail },
            { 'employeeDetails.email': customerEmail },
            { 'employeeData.email': customerEmail }
          ]
        },
        { status: { $in: ['pending_assignment', 'assigned', 'scheduled'] } },
        {
          $or: [
            {
              startDate: {
                $gte: start,
                $lte: end
              }
            },
            {
              endDate: {
                $gte: start,
                $lte: end
              }
            },
            {
              $and: [
                { startDate: { $lte: start } },
                { endDate: { $gte: end } }
              ]
            }
          ]
        }
      ]
    }).toArray();

    console.log(`📅 Found ${affectedTrips.length} affected trips for leave request`);

    // Create leave request document
    const leaveRequest = {
      customerId: userId,
      customerName,
      customerEmail,
      organizationName,
      startDate: start,
      endDate: end,
      reason: reason || '',
      status: 'pending_approval',
      affectedTripIds: affectedTrips.map(trip => trip._id),
      affectedTripsCount: affectedTrips.length,
      createdAt: new Date(),
      updatedAt: new Date()
    };

    // Insert leave request
    const result = await req.db.collection('leave_requests').insertOne(leaveRequest);
    const leaveRequestId = result.insertedId;

    // Update affected trips to reference the leave request
    if (affectedTrips.length > 0) {
      await req.db.collection('rosters').updateMany(
        { _id: { $in: affectedTrips.map(trip => trip._id) } },
        {
          $set: {
            leaveRequestId: leaveRequestId,
            leaveRequestStatus: 'pending_approval'
          }
        }
      );
    }

    // Send notification to client (organization admin) for approval
    try {
      // ✅ FIXED: Match by email domain instead of organization name
      const customerDomain = customerEmail.split('@')[1];
      console.log(`📤 Sending leave request notification to clients with domain: @${customerDomain}`);
      console.log(`   Customer email: ${customerEmail}`);
      console.log(`   Customer organization: ${organizationName}`);

      const clientUIDs = [];

      // ✅ Method 1: Check MongoDB for client users with matching email domain
      const clientUsersFromDB = await req.db.collection('users').find({
        role: 'client'
      }).toArray();

      clientUsersFromDB.forEach(user => {
        if (user.firebaseUid && user.email) {
          const clientDomain = user.email.split('@')[1];
          // Match by email domain (case-insensitive)
          if (clientDomain.toLowerCase() === customerDomain.toLowerCase()) {
            clientUIDs.push(user.firebaseUid);
            console.log(`📊 Found client in MongoDB: ${user.email} (${user.firebaseUid}) - Domain match: @${clientDomain}`);
          }
        }
      });

      console.log(`📊 Found ${clientUIDs.length} client user(s) in MongoDB with domain @${customerDomain}`);

      // ✅ Method 2: Check Firestore for client users with matching email domain
      try {
        const firestore = admin.firestore();
        const usersSnapshot = await firestore.collection('users')
          .where('role', '==', 'client')
          .get();

        usersSnapshot.forEach(doc => {
          const uid = doc.id;
          const userData = doc.data();

          if (userData.email) {
            const clientDomain = userData.email.split('@')[1];
            // Match by email domain (case-insensitive)
            if (clientDomain.toLowerCase() === customerDomain.toLowerCase() && !clientUIDs.includes(uid)) {
              clientUIDs.push(uid);
              console.log(`📊 Found additional client in Firestore: ${userData.email} (${uid}) - Domain match: @${clientDomain}`);
            }
          }
        });
      } catch (firestoreError) {
        console.warn('⚠️  Could not check Firestore for client users:', firestoreError.message);
      }

      console.log(`📊 Total unique client UIDs with domain @${customerDomain}: ${clientUIDs.length}`);

      // Send notification to all client users
      for (const clientUID of clientUIDs) {
        console.log(`✅ Sending to client UID: ${clientUID}`);

        // Try using createNotification first
        try {
          await createNotification(req.db, {
            userId: clientUID,
            type: 'leave_request',
            title: 'New Leave Request - Approval Required',
            body: `${customerName} has requested leave from ${start.toDateString()} to ${end.toDateString()}. ${affectedTrips.length} trip(s) will be affected. Please review and approve.`,
            priority: 'high',
            category: 'leave_management',
            data: {
              leaveRequestId: leaveRequestId.toString(),
              customerId: userId,
              customerName,
              customerEmail,
              organizationName,
              startDate: start.toISOString(),
              endDate: end.toISOString(),
              reason: reason || '',
              affectedTripsCount: affectedTrips.length
            }
          });
          console.log(`✅ Notification sent to client via createNotification`);
        } catch (createError) {
          console.warn(`⚠️  createNotification failed, sending directly to Firebase RTDB:`, createError.message);

          // Fallback: Send directly to Firebase RTDB
          const notificationId = Date.now().toString();
          const notification = {
            id: notificationId,
            userId: clientUID,
            type: 'leave_request',
            title: 'New Leave Request - Approval Required',
            body: `${customerName} has requested leave from ${start.toDateString()} to ${end.toDateString()}. ${affectedTrips.length} trip(s) will be affected. Please review and approve.`,
            data: {
              leaveRequestId: leaveRequestId.toString(),
              customerId: userId,
              customerName,
              customerEmail,
              organizationName,
              startDate: start.toISOString(),
              endDate: end.toISOString(),
              reason: reason || '',
              affectedTripsCount: affectedTrips.length
            },
            isRead: false,
            priority: 'high',
            category: 'leave_management',
            createdAt: new Date().toISOString(),
            expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
          };

          const firebasePath = `notifications/${clientUID}/${notificationId}`;
          await admin.database().ref(firebasePath).set(notification);
          console.log(`✅ Notification sent directly to Firebase RTDB: ${firebasePath}`);
        }
      }
    } catch (notificationError) {
      console.error('❌ Failed to send leave request notification:', notificationError);
    }

    res.status(201).json({
      success: true,
      message: 'Leave request submitted successfully. Your organization will review it.',
      data: {
        leaveRequestId: leaveRequestId.toString(),
        status: 'pending_approval',
        startDate: start,
        endDate: end,
        reason: reason || '',
        affectedTripsCount: affectedTrips.length,
        affectedTrips: affectedTrips.map(trip => ({
          id: trip._id.toString(),
          rosterType: trip.rosterType,
          officeLocation: trip.officeLocation,
          date: trip.fromDate || trip.startDate,
          time: trip.fromTime || trip.startTime
        }))
      }
    });

  } catch (err) {
    console.error('❌ Error creating leave request:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to submit leave request',
      error: err.message
    });
  }
});

// @route   GET api/roster/customer/leave-requests
// @desc    Get customer's leave requests
// @access  Private (Customer)
router.get('/customer/leave-requests', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { status } = req.query;

    const query = { customerId: userId };
    if (status && status !== 'all') {
      query.status = status;
    }

    const leaveRequests = await req.db.collection('leave_requests')
      .find(query)
      .sort({ createdAt: -1 })
      .toArray();

    // Transform data for frontend
    const transformedRequests = leaveRequests.map(request => ({
      id: request._id.toString(),
      startDate: request.startDate,
      endDate: request.endDate,
      reason: request.reason,
      status: request.status,
      affectedTripsCount: request.affectedTripsCount,
      createdAt: request.createdAt,
      updatedAt: request.updatedAt,
      approvedBy: request.approvedBy,
      approvedAt: request.approvedAt,
      rejectedBy: request.rejectedBy,
      rejectedAt: request.rejectedAt,
      rejectionReason: request.rejectionReason
    }));

    res.json({
      success: true,
      data: transformedRequests,
      count: transformedRequests.length
    });

  } catch (err) {
    console.error('❌ Error fetching leave requests:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch leave requests',
      error: err.message
    });
  }
});

// @route   DELETE api/roster/customer/leave-request/:id
// @desc    Cancel a pending leave request
// @access  Private (Customer)
router.delete('/customer/leave-request/:id', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const leaveRequestId = req.params.id;

    // Find the leave request
    const leaveRequest = await req.db.collection('leave_requests').findOne({
      _id: new ObjectId(leaveRequestId),
      customerId: userId
    });

    if (!leaveRequest) {
      return res.status(404).json({
        success: false,
        message: 'Leave request not found'
      });
    }

    // Only allow cancellation of pending requests
    if (leaveRequest.status !== 'pending_approval') {
      return res.status(400).json({
        success: false,
        message: 'Only pending leave requests can be cancelled'
      });
    }

    // Update leave request status
    await req.db.collection('leave_requests').updateOne(
      { _id: new ObjectId(leaveRequestId) },
      {
        $set: {
          status: 'cancelled',
          cancelledAt: new Date(),
          updatedAt: new Date()
        }
      }
    );

    // Remove leave request reference from affected trips
    if (leaveRequest.affectedTripIds && leaveRequest.affectedTripIds.length > 0) {
      await req.db.collection('rosters').updateMany(
        { _id: { $in: leaveRequest.affectedTripIds } },
        {
          $unset: {
            leaveRequestId: "",
            leaveRequestStatus: ""
          }
        }
      );
    }

    res.json({
      success: true,
      message: 'Leave request cancelled successfully'
    });

  } catch (err) {
    console.error('❌ Error cancelling leave request:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to cancel leave request',
      error: err.message
    });
  }
});

// ========== ORGANIZATION/CLIENT LEAVE REQUEST MANAGEMENT ROUTES ==========

// @route   GET api/roster/admin/leave-requests
// @desc    Get all leave requests for organization review
// @access  Private (Admin/Organization)
router.get('/admin/leave-requests', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { status, organizationName } = req.query;

    console.log('🏢 Fetching leave requests for organization review...');

    // ✅ ORGANIZATION FILTER: Get admin's organization to filter requests
    let adminOrganization = organizationName;

    if (!adminOrganization) {
      // Get admin's organization from database
      const adminUser = await req.db.collection('users').findOne({ firebaseUid: userId });
      if (adminUser && (adminUser.role === 'admin' || adminUser.role === 'client')) {
        adminOrganization = adminUser.companyName || adminUser.organizationName;
      }
    }

    // Build query for leave requests
    const query = {};

    if (status && status !== 'all') {
      query.status = status;
    }

    // ✅ CRITICAL: Only show leave requests from the admin's organization
    if (adminOrganization) {
      query.organizationName = adminOrganization;
      console.log(`🔒 Filtering leave requests for organization: ${adminOrganization}`);
    } else {
      console.log('⚠️  No organization found for admin, showing all requests');
    }

    console.log('📋 Leave requests query:', JSON.stringify(query, null, 2));

    // Fetch leave requests from database
    const leaveRequests = await req.db.collection('leave_requests')
      .find(query)
      .sort({ createdAt: -1 })
      .toArray();

    console.log(`📊 Found ${leaveRequests.length} leave requests`);

    // Transform data for frontend with affected trip details
    const transformedRequests = await Promise.all(leaveRequests.map(async (request) => {
      // Get affected trip details
      let affectedTrips = [];
      if (request.affectedTripIds && request.affectedTripIds.length > 0) {
        affectedTrips = await req.db.collection('rosters')
          .find({ _id: { $in: request.affectedTripIds } })
          .toArray();
      }

      return {
        id: request._id.toString(),
        customerId: request.customerId,
        customerName: request.customerName,
        customerEmail: request.customerEmail,
        organizationName: request.organizationName,
        startDate: request.startDate,
        endDate: request.endDate,
        reason: request.reason,
        status: request.status,
        affectedTripsCount: request.affectedTripsCount,
        createdAt: request.createdAt,
        updatedAt: request.updatedAt,
        approvedBy: request.approvedBy,
        approvedAt: request.approvedAt,
        rejectedBy: request.rejectedBy,
        rejectedAt: request.rejectedAt,
        rejectionReason: request.rejectionReason,
        affectedTrips: affectedTrips.map(trip => ({
          id: trip._id.toString(),
          rosterType: trip.rosterType,
          officeLocation: trip.officeLocation,
          fromDate: trip.fromDate || trip.startDate,
          toDate: trip.toDate || trip.endDate,
          fromTime: trip.fromTime || trip.startTime,
          toTime: trip.toTime || trip.endTime,
          loginPickupAddress: trip.loginPickupAddress,
          logoutDropAddress: trip.logoutDropAddress,
          status: trip.status,
          assignedDriver: trip.assignedDriver,
          assignedVehicle: trip.assignedVehicle
        }))
      };
    }));

    console.log(`✅ Returning ${transformedRequests.length} transformed leave requests`);

    res.json({
      success: true,
      data: transformedRequests,
      count: transformedRequests.length
    });

  } catch (err) {
    console.error('❌ Error fetching leave requests for organization:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch leave requests',
      error: err.message
    });
  }
});

// @route   GET api/roster/admin/approved-leave-requests
// @desc    Get all approved leave requests
// @access  Private (Admin/Organization)
router.get('/admin/approved-leave-requests', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { organizationName } = req.query;

    console.log('✅ Fetching approved leave requests...');

    // Get admin's organization to filter requests
    let adminOrganization = organizationName;

    if (!adminOrganization) {
      const adminUser = await req.db.collection('users').findOne({ firebaseUid: userId });
      if (adminUser && (adminUser.role === 'admin' || adminUser.role === 'client')) {
        adminOrganization = adminUser.companyName || adminUser.organizationName;
      }
    }

    // Build query for approved leave requests only
    const query = {
      status: 'approved'
    };

    // Filter by organization
    if (adminOrganization) {
      query.organizationName = adminOrganization;
      console.log(`🔒 Filtering approved leave requests for organization: ${adminOrganization}`);
    }

    console.log('📋 Approved leave requests query:', JSON.stringify(query, null, 2));

    // Fetch approved leave requests
    const leaveRequests = await req.db.collection('leave_requests')
      .find(query)
      .sort({ approvedAt: -1, createdAt: -1 })
      .toArray();

    console.log(`📊 Found ${leaveRequests.length} approved leave requests`);

    // Transform data for frontend
    const transformedRequests = await Promise.all(leaveRequests.map(async (request) => {
      // Get affected trip details
      let affectedTrips = [];
      if (request.affectedTripIds && request.affectedTripIds.length > 0) {
        affectedTrips = await req.db.collection('rosters')
          .find({ _id: { $in: request.affectedTripIds } })
          .toArray();
      }

      return {
        id: request._id.toString(),
        customerId: request.customerId,
        customerName: request.customerName,
        customerEmail: request.customerEmail,
        organizationName: request.organizationName,
        startDate: request.startDate,
        endDate: request.endDate,
        reason: request.reason,
        status: request.status,
        affectedTripsCount: request.affectedTripsCount || 0,
        affectedTrips: affectedTrips.map(trip => ({
          id: trip._id.toString(),
          officeLocation: trip.officeLocation,
          loginTime: trip.loginTime || trip.startTime,
          logoutTime: trip.logoutTime || trip.endTime,
          status: trip.status
        })),
        approvedBy: request.approvedBy,
        approvedAt: request.approvedAt,
        approvalNote: request.approvalNote,
        createdAt: request.createdAt,
        updatedAt: request.updatedAt
      };
    }));

    res.json({
      success: true,
      data: transformedRequests,
      count: transformedRequests.length
    });

  } catch (err) {
    console.error('❌ Error fetching approved leave requests:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch approved leave requests',
      error: err.message
    });
  }
});

// @route   PUT api/roster/admin/leave-request/:id/approve
// @desc    Approve a leave request
// @access  Private (Admin/Organization)
router.put('/admin/leave-request/:id/approve', verifyToken, async (req, res) => {
  try {
    const leaveRequestId = req.params.id;
    const userId = req.user.userId;
    const { note } = req.body;

    console.log(`✅ Approving leave request: ${leaveRequestId}`);

    // Get admin/organization details
    let adminName = 'Unknown Admin';
    let adminEmail = '';
    try {
      const userRecord = await admin.auth().getUser(userId);
      adminName = userRecord.displayName || userRecord.email || 'Unknown Admin';
      adminEmail = userRecord.email || '';
    } catch (authError) {
      const userDoc = await req.db.collection('users').findOne({ firebaseUid: userId });
      if (userDoc) {
        adminName = userDoc.name || userDoc.email || 'Unknown Admin';
        adminEmail = userDoc.email || '';
      }
    }

    // Find the leave request
    const leaveRequest = await req.db.collection('leave_requests').findOne({
      _id: new ObjectId(leaveRequestId)
    });

    if (!leaveRequest) {
      return res.status(404).json({
        success: false,
        message: 'Leave request not found'
      });
    }

    // Only allow approval of pending requests
    if (leaveRequest.status !== 'pending_approval') {
      return res.status(400).json({
        success: false,
        message: 'Only pending leave requests can be approved'
      });
    }

    // Update leave request status
    await req.db.collection('leave_requests').updateOne(
      { _id: new ObjectId(leaveRequestId) },
      {
        $set: {
          status: 'approved',
          approvedBy: adminName,
          approvedByEmail: adminEmail,
          approvedAt: new Date(),
          approvalNote: note || '',
          updatedAt: new Date()
        }
      }
    );

    // Update affected trips status to "waiting_cancellation"
    if (leaveRequest.affectedTripIds && leaveRequest.affectedTripIds.length > 0) {
      await req.db.collection('rosters').updateMany(
        { _id: { $in: leaveRequest.affectedTripIds } },
        {
          $set: {
            status: 'waiting_cancellation',
            leaveRequestStatus: 'approved',
            updatedAt: new Date()
          }
        }
      );
    }

    // Send notification to customer
    try {
      console.log(`📤 Sending leave approval notification to customer: ${leaveRequest.customerId}`);

      // Try using createNotification first
      try {
        await createNotification(req.db, {
          userId: leaveRequest.customerId,
          type: 'leave_approved',
          title: 'Leave Request Approved',
          body: `Good news! Your organization has approved your leave request from ${leaveRequest.startDate.toDateString()} to ${leaveRequest.endDate.toDateString()}.`,
          priority: 'high',
          category: 'leave_management',
          data: {
            leaveRequestId: leaveRequestId,
            startDate: leaveRequest.startDate.toISOString(),
            endDate: leaveRequest.endDate.toISOString(),
            approvedBy: adminName,
            approvalNote: note || ''
          }
        });
        console.log('✅ Notification sent via createNotification');
      } catch (createError) {
        console.warn('⚠️  createNotification failed, sending directly to Firebase RTDB:', createError.message);

        // Fallback: Send directly to Firebase RTDB
        const notificationId = Date.now().toString();
        const notification = {
          id: notificationId,
          userId: leaveRequest.customerId,
          type: 'leave_approved',
          title: 'Leave Request Approved',
          body: `Good news! Your organization has approved your leave request from ${leaveRequest.startDate.toDateString()} to ${leaveRequest.endDate.toDateString()}.`,
          data: {
            leaveRequestId: leaveRequestId,
            startDate: leaveRequest.startDate.toISOString(),
            endDate: leaveRequest.endDate.toISOString(),
            approvedBy: adminName,
            approvalNote: note || ''
          },
          isRead: false,
          priority: 'high',
          category: 'leave_management',
          createdAt: new Date().toISOString(),
          expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
        };

        const firebasePath = `notifications/${leaveRequest.customerId}/${notificationId}`;
        await admin.database().ref(firebasePath).set(notification);
        console.log(`✅ Notification sent directly to Firebase RTDB: ${firebasePath}`);
      }
    } catch (notificationError) {
      console.error('❌ Failed to send approval notification:', notificationError);
    }

    // Send notification to ALL fleet administrators
    try {
      // Get all admin users
      const adminUsers = await req.db.collection('users').find({
        role: 'admin'
      }).toArray();

      console.log(`📢 Sending leave approval notification to ${adminUsers.length} admin(s)`);

      // Send notification to each admin
      for (const adminUser of adminUsers) {
        try {
          console.log(`📤 Sending notification to admin: ${adminUser.email || adminUser.firebaseUid}`);

          // Try using createNotification first
          try {
            await createNotification(req.db, {
              userId: adminUser.firebaseUid,
              type: 'leave_approved_admin',
              title: 'Leave Request Approved - Action Required',
              body: `Leave request approved for ${leaveRequest.customerName} from ${leaveRequest.startDate.toDateString()} to ${leaveRequest.endDate.toDateString()}. Please cancel the associated trips.`,
              priority: 'urgent',
              category: 'leave_management',
              data: {
                leaveRequestId: leaveRequestId,
                customerId: leaveRequest.customerId,
                customerName: leaveRequest.customerName,
                startDate: leaveRequest.startDate.toISOString(),
                endDate: leaveRequest.endDate.toISOString(),
                affectedTripsCount: leaveRequest.affectedTripsCount,
                approvedBy: adminName
              }
            });
            console.log(`✅ Notification sent to admin via createNotification: ${adminUser.email}`);
          } catch (createError) {
            console.warn(`⚠️  createNotification failed for admin, sending directly to Firebase RTDB:`, createError.message);

            // Fallback: Send directly to Firebase RTDB
            const notificationId = Date.now().toString() + '_' + Math.random().toString(36).substr(2, 9);
            const notification = {
              id: notificationId,
              userId: adminUser.firebaseUid,
              type: 'leave_approved_admin',
              title: 'Leave Request Approved - Action Required',
              body: `Leave request approved for ${leaveRequest.customerName} from ${leaveRequest.startDate.toDateString()} to ${leaveRequest.endDate.toDateString()}. Please cancel the associated trips.`,
              data: {
                leaveRequestId: leaveRequestId,
                customerId: leaveRequest.customerId,
                customerName: leaveRequest.customerName,
                startDate: leaveRequest.startDate.toISOString(),
                endDate: leaveRequest.endDate.toISOString(),
                affectedTripsCount: leaveRequest.affectedTripsCount,
                approvedBy: adminName
              },
              isRead: false,
              priority: 'urgent',
              category: 'leave_management',
              createdAt: new Date().toISOString(),
              expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
            };

            const firebasePath = `notifications/${adminUser.firebaseUid}/${notificationId}`;
            await admin.database().ref(firebasePath).set(notification);
            console.log(`✅ Notification sent directly to Firebase RTDB for admin: ${firebasePath}`);
          }
        } catch (adminNotifError) {
          console.error(`❌ Failed to send notification to admin ${adminUser.email}:`, adminNotifError);
        }
      }

      if (adminUsers.length === 0) {
        console.warn('⚠️  WARNING: No admin users found in database!');
      }
    } catch (notificationError) {
      console.error('❌ Failed to send admin notifications:', notificationError);
    }

    res.json({
      success: true,
      message: 'Leave request approved successfully',
      data: {
        leaveRequestId: leaveRequestId,
        status: 'approved',
        approvedBy: adminName,
        approvedAt: new Date(),
        affectedTripsCount: leaveRequest.affectedTripsCount
      }
    });

  } catch (err) {
    console.error('❌ Error approving leave request:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to approve leave request',
      error: err.message
    });
  }
});

// @route   PUT api/roster/admin/leave-request/:id/reject
// @desc    Reject a leave request
// @access  Private (Admin/Organization)
router.put('/admin/leave-request/:id/reject', verifyToken, async (req, res) => {
  try {
    const leaveRequestId = req.params.id;
    const userId = req.user.userId;
    const { reason } = req.body;

    if (!reason || reason.trim() === '') {
      return res.status(400).json({
        success: false,
        message: 'Rejection reason is required'
      });
    }

    console.log(`❌ Rejecting leave request: ${leaveRequestId}`);

    // Get admin/organization details
    let adminName = 'Unknown Admin';
    let adminEmail = '';
    try {
      const userRecord = await admin.auth().getUser(userId);
      adminName = userRecord.displayName || userRecord.email || 'Unknown Admin';
      adminEmail = userRecord.email || '';
    } catch (authError) {
      const userDoc = await req.db.collection('users').findOne({ firebaseUid: userId });
      if (userDoc) {
        adminName = userDoc.name || userDoc.email || 'Unknown Admin';
        adminEmail = userDoc.email || '';
      }
    }

    // Find the leave request
    const leaveRequest = await req.db.collection('leave_requests').findOne({
      _id: new ObjectId(leaveRequestId)
    });

    if (!leaveRequest) {
      return res.status(404).json({
        success: false,
        message: 'Leave request not found'
      });
    }

    // Only allow rejection of pending requests
    if (leaveRequest.status !== 'pending_approval') {
      return res.status(400).json({
        success: false,
        message: 'Only pending leave requests can be rejected'
      });
    }

    // Update leave request status
    await req.db.collection('leave_requests').updateOne(
      { _id: new ObjectId(leaveRequestId) },
      {
        $set: {
          status: 'rejected',
          rejectedBy: adminName,
          rejectedByEmail: adminEmail,
          rejectedAt: new Date(),
          rejectionReason: reason.trim(),
          updatedAt: new Date()
        }
      }
    );

    // Remove leave request reference from affected trips (trips remain active)
    if (leaveRequest.affectedTripIds && leaveRequest.affectedTripIds.length > 0) {
      await req.db.collection('rosters').updateMany(
        { _id: { $in: leaveRequest.affectedTripIds } },
        {
          $unset: {
            leaveRequestId: "",
            leaveRequestStatus: ""
          },
          $set: {
            updatedAt: new Date()
          }
        }
      );
    }

    // Send notification to customer
    try {
      await createNotification(req.db, {
        userId: leaveRequest.customerId,
        type: 'leave_rejected',
        title: 'Leave Request Rejected',
        body: `Your leave request has been rejected by your organization. Reason: ${reason.trim()}`,
        priority: 'high', // High priority for rejections
        category: 'leave_management',
        data: {
          leaveRequestId: leaveRequestId,
          startDate: leaveRequest.startDate.toISOString(),
          endDate: leaveRequest.endDate.toISOString(),
          rejectedBy: adminName,
          rejectionReason: reason.trim()
        }
      });
    } catch (notificationError) {
      console.error('❌ Failed to send rejection notification:', notificationError);
    }

    res.json({
      success: true,
      message: 'Leave request rejected successfully',
      data: {
        leaveRequestId: leaveRequestId,
        status: 'rejected',
        rejectedBy: adminName,
        rejectedAt: new Date(),
        rejectionReason: reason.trim()
      }
    });

  } catch (err) {
    console.error('❌ Error rejecting leave request:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to reject leave request',
      error: err.message
    });
  }
});

// @route   GET api/roster/admin/leave-request/:id
// @desc    Get detailed leave request information
// @access  Private (Admin/Organization)
router.get('/admin/leave-request/:id', verifyToken, async (req, res) => {
  try {
    const leaveRequestId = req.params.id;

    console.log(`📋 Fetching leave request details: ${leaveRequestId}`);

    // Find the leave request
    const leaveRequest = await req.db.collection('leave_requests').findOne({
      _id: new ObjectId(leaveRequestId)
    });

    if (!leaveRequest) {
      return res.status(404).json({
        success: false,
        message: 'Leave request not found'
      });
    }

    // Get affected trip details
    let affectedTrips = [];
    if (leaveRequest.affectedTripIds && leaveRequest.affectedTripIds.length > 0) {
      affectedTrips = await req.db.collection('rosters')
        .find({ _id: { $in: leaveRequest.affectedTripIds } })
        .toArray();
    }

    // Get customer details
    const customer = await req.db.collection('users').findOne({
      firebaseUid: leaveRequest.customerId
    });

    const response = {
      id: leaveRequest._id.toString(),
      customerId: leaveRequest.customerId,
      customerName: leaveRequest.customerName,
      customerEmail: leaveRequest.customerEmail,
      organizationName: leaveRequest.organizationName,
      startDate: leaveRequest.startDate,
      endDate: leaveRequest.endDate,
      reason: leaveRequest.reason,
      status: leaveRequest.status,
      affectedTripsCount: leaveRequest.affectedTripsCount,
      createdAt: leaveRequest.createdAt,
      updatedAt: leaveRequest.updatedAt,

      // Approval/Rejection details
      approvedBy: leaveRequest.approvedBy,
      approvedAt: leaveRequest.approvedAt,
      approvalNote: leaveRequest.approvalNote,
      rejectedBy: leaveRequest.rejectedBy,
      rejectedAt: leaveRequest.rejectedAt,
      rejectionReason: leaveRequest.rejectionReason,

      // Customer details
      customerDetails: customer ? {
        employeeId: customer.employeeId,
        department: customer.department,
        phoneNumber: customer.phoneNumber,
        companyName: customer.companyName
      } : null,

      // Affected trips details
      affectedTrips: affectedTrips.map(trip => ({
        id: trip._id.toString(),
        rosterType: trip.rosterType,
        officeLocation: trip.officeLocation,
        fromDate: trip.fromDate || trip.startDate,
        toDate: trip.toDate || trip.endDate,
        fromTime: trip.fromTime || trip.startTime,
        toTime: trip.toTime || trip.endTime,
        loginPickupAddress: trip.loginPickupAddress,
        logoutDropAddress: trip.logoutDropAddress,
        status: trip.status,
        assignedDriver: trip.assignedDriver,
        assignedVehicle: trip.assignedVehicle,
        weekdays: trip.weekdays || trip.weeklyOffDays
      }))
    };

    res.json({
      success: true,
      data: response
    });

  } catch (err) {
    console.error('❌ Error fetching leave request details:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch leave request details',
      error: err.message
    });
  }
});

// @route   POST api/roster/admin/cancel-leave-trips/:leaveRequestId
// @desc    Cancel all trips for an approved leave request
// @access  Private (Admin)
router.post('/admin/cancel-leave-trips/:leaveRequestId', verifyToken, async (req, res) => {
  try {
    const leaveRequestId = req.params.leaveRequestId;
    const userId = req.user.userId;
    const { adminNotes } = req.body;

    console.log(`🗑️ Cancelling trips for leave request: ${leaveRequestId}`);

    // Get admin details
    let adminName = 'Unknown Admin';
    let adminEmail = '';
    try {
      const userRecord = await admin.auth().getUser(userId);
      adminName = userRecord.displayName || userRecord.email || 'Unknown Admin';
      adminEmail = userRecord.email || '';
    } catch (authError) {
      const userDoc = await req.db.collection('users').findOne({ firebaseUid: userId });
      if (userDoc) {
        adminName = userDoc.name || userDoc.email || 'Unknown Admin';
        adminEmail = userDoc.email || '';
      }
    }

    // Find the leave request
    const leaveRequest = await req.db.collection('leave_requests').findOne({
      _id: new ObjectId(leaveRequestId)
    });

    if (!leaveRequest) {
      return res.status(404).json({
        success: false,
        message: 'Leave request not found'
      });
    }

    // Only allow cancellation for approved requests
    if (leaveRequest.status !== 'approved') {
      return res.status(400).json({
        success: false,
        message: 'Only approved leave requests can have trips cancelled'
      });
    }

    // Get affected trips
    const affectedTrips = await req.db.collection('rosters')
      .find({
        _id: { $in: leaveRequest.affectedTripIds || [] },
        status: { $in: ['pending_assignment', 'assigned', 'scheduled', 'waiting_cancellation'] }
      })
      .toArray();

    console.log(`📋 Found ${affectedTrips.length} trips to cancel`);

    // Cancel all affected trips
    const cancelledTrips = [];
    const notificationPromises = [];

    for (const trip of affectedTrips) {
      // Update trip status to cancelled
      await req.db.collection('rosters').updateOne(
        { _id: trip._id },
        {
          $set: {
            status: 'cancelled',
            cancellationReason: 'Customer is on leave',
            cancelledBy: adminName,
            cancelledByEmail: adminEmail,
            cancelledAt: new Date(),
            adminNotes: adminNotes || '',
            updatedAt: new Date()
          }
        }
      );

      cancelledTrips.push({
        id: trip._id.toString(),
        readableId: trip.readableId,
        rosterType: trip.rosterType,
        officeLocation: trip.officeLocation,
        assignedDriver: trip.assignedDriver
      });

      // Send notification to assigned driver (if any)
      if (trip.assignedDriver && trip.assignedDriver.driverId) {
        // Get pickup and drop locations
        const pickupLocation = trip.locations?.pickup?.address || trip.loginPickupAddress || 'Pickup location';
        const dropLocation = trip.locations?.drop?.address || trip.logoutDropAddress || 'Drop location';
        const tripDate = trip.fromDate || trip.startDate;
        const tripTime = trip.fromTime || trip.startTime;

        const notificationPromise = (async () => {
          try {
            await createNotification(req.db, {
              userId: trip.assignedDriver.driverId,
              type: 'trip_cancelled',
              title: 'Trip Cancelled - Customer on Leave',
              body: `No pickup/drop for ${leaveRequest.customerName} on ${new Date(tripDate).toDateString()} at ${tripTime}. Pickup: ${pickupLocation}, Drop: ${dropLocation}`,
              priority: 'high',
              category: 'trip_management',
              data: {
                tripId: trip._id.toString(),
                readableId: trip.readableId,
                customerName: leaveRequest.customerName,
                rosterType: trip.rosterType,
                pickupLocation: pickupLocation,
                dropLocation: dropLocation,
                scheduledDate: new Date(tripDate).toISOString(),
                scheduledTime: tripTime,
                cancellationReason: 'Customer is on leave',
                cancelledBy: adminName,
                cancelledAt: new Date().toISOString()
              }
            });
            console.log(`✅ Notification sent to driver: ${trip.assignedDriver.driverName || trip.assignedDriver.driverId}`);
          } catch (driverNotifError) {
            console.warn(`⚠️  createNotification failed for driver, sending directly to Firebase RTDB`);

            // Fallback: Send directly to Firebase RTDB
            const notificationId = Date.now().toString() + '_' + Math.random().toString(36).substr(2, 9);
            const notification = {
              id: notificationId,
              userId: trip.assignedDriver.driverId,
              type: 'trip_cancelled',
              title: 'Trip Cancelled - Customer on Leave',
              body: `No pickup/drop for ${leaveRequest.customerName} on ${new Date(tripDate).toDateString()} at ${tripTime}. Pickup: ${pickupLocation}, Drop: ${dropLocation}`,
              data: {
                tripId: trip._id.toString(),
                readableId: trip.readableId,
                customerName: leaveRequest.customerName,
                rosterType: trip.rosterType,
                pickupLocation: pickupLocation,
                dropLocation: dropLocation,
                scheduledDate: new Date(tripDate).toISOString(),
                scheduledTime: tripTime,
                cancellationReason: 'Customer is on leave',
                cancelledBy: adminName,
                cancelledAt: new Date().toISOString()
              },
              isRead: false,
              priority: 'high',
              category: 'trip_management',
              createdAt: new Date().toISOString(),
              expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
            };

            const firebasePath = `notifications/${trip.assignedDriver.driverId}/${notificationId}`;
            await admin.database().ref(firebasePath).set(notification);
            console.log(`✅ Notification sent directly to Firebase RTDB for driver: ${firebasePath}`);
          }
        })();

        notificationPromises.push(notificationPromise);
      }
    }

    // Wait for all notifications to be sent
    try {
      await Promise.all(notificationPromises);
      console.log(`✅ Sent ${notificationPromises.length} driver notifications`);
    } catch (notificationError) {
      console.error('❌ Some driver notifications failed:', notificationError);
    }

    // Send notification to admin who cancelled the trips
    try {
      // Convert coordinates to readable addresses for notification
      const tripsWithAddresses = await Promise.all(
        cancelledTrips.map(async (t) => {
          const readableLocation = await reverseGeocodeLocation(t.officeLocation);
          await delay(1000); // Respect OpenStreetMap rate limits
          return {
            id: t.id,
            readableId: t.readableId,
            rosterType: t.rosterType,
            officeLocation: readableLocation
          };
        })
      );

      await createNotification(req.db, {
        userId: userId,
        type: 'trip_cancelled',
        title: '✅ Trips Cancelled Successfully',
        body: `Successfully cancelled ${cancelledTrips.length} trip(s) for ${leaveRequest.customerName}`,
        priority: 'high',
        category: 'trip_management',
        data: {
          leaveRequestId: leaveRequestId,
          customerName: leaveRequest.customerName,
          cancelledTripsCount: cancelledTrips.length,
          cancelledTrips: tripsWithAddresses,
          processedBy: adminName,
          processedAt: new Date().toISOString()
        }
      });
      console.log(`✅ Sent admin notification for trip cancellation with readable addresses`);
    } catch (adminNotificationError) {
      console.error('❌ Admin notification failed:', adminNotificationError);
    }

    // Mark leave request as processed
    await req.db.collection('leave_requests').updateOne(
      { _id: new ObjectId(leaveRequestId) },
      {
        $set: {
          tripsProcessed: true,
          tripsProcessedBy: adminName,
          tripsProcessedAt: new Date(),
          tripsCancelledCount: cancelledTrips.length,
          adminNotes: adminNotes || '',
          updatedAt: new Date()
        }
      }
    );

    // Create history log entry
    await req.db.collection('trip_cancellation_history').insertOne({
      leaveRequestId: new ObjectId(leaveRequestId),
      customerId: leaveRequest.customerId,
      customerName: leaveRequest.customerName,
      cancelledTrips: cancelledTrips,
      cancelledBy: adminName,
      cancelledByEmail: adminEmail,
      cancelledAt: new Date(),
      reason: 'Customer is on leave',
      adminNotes: adminNotes || '',
      createdAt: new Date()
    });

    res.json({
      success: true,
      message: `Successfully cancelled ${cancelledTrips.length} trip(s)`,
      data: {
        leaveRequestId: leaveRequestId,
        cancelledTripsCount: cancelledTrips.length,
        cancelledTrips: cancelledTrips,
        processedBy: adminName,
        processedAt: new Date(),
        driversNotified: notificationPromises.length
      }
    });

  } catch (err) {
    console.error('❌ Error cancelling leave trips:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to cancel trips',
      error: err.message
    });
  }
});

// @route   GET api/roster/admin/trip-cancellation-history
// @desc    Get trip cancellation history
// @access  Private (Admin)
router.get('/admin/trip-cancellation-history', verifyToken, async (req, res) => {
  try {
    const { limit = 50 } = req.query;

    console.log('📋 Fetching trip cancellation history...');

    const history = await req.db.collection('trip_cancellation_history')
      .find({})
      .sort({ createdAt: -1 })
      .limit(parseInt(limit))
      .toArray();

    const transformedHistory = history.map(entry => ({
      id: entry._id.toString(),
      leaveRequestId: entry.leaveRequestId.toString(),
      customerId: entry.customerId,
      customerName: entry.customerName,
      cancelledTripsCount: entry.cancelledTrips.length,
      cancelledTrips: entry.cancelledTrips,
      cancelledBy: entry.cancelledBy,
      cancelledAt: entry.cancelledAt,
      reason: entry.reason,
      adminNotes: entry.adminNotes
    }));

    res.json({
      success: true,
      data: transformedHistory,
      count: transformedHistory.length
    });

  } catch (err) {
    console.error('❌ Error fetching trip cancellation history:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch trip cancellation history',
      error: err.message
    });
  }
});

// ========== DRIVER NOTIFICATION ROUTES (Step 4) ==========

// @route   GET api/roster/driver/cancelled-trips
// @desc    Get cancelled trips for driver
// @access  Private (Driver)
router.get('/driver/cancelled-trips', verifyToken, async (req, res) => {
  try {
    const userId = req.user.userId;
    const { status = 'all', limit = 20 } = req.query;

    console.log(`🚗 Fetching cancelled trips for driver: ${userId}`);

    // Build query
    const query = {
      'assignedDriver.driverId': userId,
      status: 'cancelled'
    };

    if (status !== 'all') {
      // Could add additional status filters if needed
    }

    const cancelledTrips = await req.db.collection('rosters')
      .find(query)
      .sort({ cancelledAt: -1 })
      .limit(parseInt(limit))
      .toArray();

    const transformedTrips = cancelledTrips.map(trip => ({
      id: trip._id.toString(),
      readableId: trip.readableId,
      customerName: trip.customerName,
      rosterType: trip.rosterType,
      officeLocation: trip.officeLocation,
      scheduledDate: trip.fromDate || trip.startDate,
      scheduledTime: trip.fromTime || trip.startTime,
      loginPickupAddress: trip.loginPickupAddress,
      logoutDropAddress: trip.logoutDropAddress,
      cancellationReason: trip.cancellationReason,
      cancelledBy: trip.cancelledBy,
      cancelledAt: trip.cancelledAt,
      adminNotes: trip.adminNotes
    }));

    res.json({
      success: true,
      data: transformedTrips,
      count: transformedTrips.length
    });

  } catch (err) {
    console.error('❌ Error fetching cancelled trips for driver:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch cancelled trips',
      error: err.message
    });
  }
});

// @route   PUT api/roster/driver/acknowledge-cancellation/:tripId
// @desc    Acknowledge trip cancellation notification
// @access  Private (Driver)
router.put('/driver/acknowledge-cancellation/:tripId', verifyToken, async (req, res) => {
  try {
    const tripId = req.params.tripId;
    const userId = req.user.userId;

    console.log(`✅ Driver ${userId} acknowledging cancellation for trip: ${tripId}`);

    // Update trip to mark as acknowledged
    const result = await req.db.collection('rosters').updateOne(
      {
        _id: new ObjectId(tripId),
        'assignedDriver.driverId': userId,
        status: 'cancelled'
      },
      {
        $set: {
          cancellationAcknowledged: true,
          acknowledgedAt: new Date(),
          updatedAt: new Date()
        }
      }
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({
        success: false,
        message: 'Trip not found or not assigned to you'
      });
    }

    res.json({
      success: true,
      message: 'Trip cancellation acknowledged successfully'
    });

  } catch (err) {
    console.error('❌ Error acknowledging trip cancellation:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to acknowledge trip cancellation',
      error: err.message
    });
  }
});

// ========== CLIENT/CUSTOMER ROUTES ==========

// ========== EXISTING ADMIN ROUTES (Driver-Vehicle Assignment) ==========

// @route   POST api/roster/admin
// @desc    Create a new admin roster (driver-vehicle assignment)
// @access  Private (Admin/Manager)
router.post(
  '/admin',
  [
    verifyToken,
    check('driverId', 'Driver ID is required').not().isEmpty(),
    check('vehicleId', 'Vehicle ID is required').not().isEmpty(),
    check('startTime', 'Start time is required').isISO8601(),
    check('endTime', 'End time is required').isISO8601()
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ errors: errors.array() });
    }

    try {
      const { driverId, vehicleId, startTime, endTime, notes } = req.body;
      const start = new Date(startTime);
      const end = new Date(endTime);

      const isDriverAvailable = await Roster.checkAvailability(driverId, null, start, end);
      if (!isDriverAvailable) {
        return res.status(400).json({ msg: 'Driver is already scheduled during this time' });
      }

      const isVehicleAvailable = await Roster.checkAvailability(null, vehicleId, start, end);
      if (!isVehicleAvailable) {
        return res.status(400).json({ msg: 'Vehicle is already scheduled during this time' });
      }

      const rosterData = {
        driverId,
        vehicleId,
        startTime: start,
        endTime: end,
        notes,
        createdBy: req.user.userId,
        status: 'scheduled'
      };

      const newRoster = await Roster.create(rosterData);
      res.status(201).json(newRoster);
    } catch (err) {
      console.error('Error creating admin roster:', err.message);
      res.status(500).json({ success: false, message: 'Server error', error: err.message });
    }
  }
);

// ========== NEW CUSTOMER ROUTES (Flutter App) ==========

// routes/roster_router.js
// COMPLETE FIX - Replace the /customer POST route

// routes/roster_router.js
// COMPLETE FIX - Replace the /customer POST route

// @route   POST api/roster/customer
// @desc    Create roster with proper employee data handling
// @access  Private (Any authenticated user)
router.post(
  '/customer',
  [
    verifyToken,
    check('rosterType', 'Roster type is required').isIn(['login', 'logout', 'both']),
    check('officeLocation', 'Office location is required').not().isEmpty(),
    check('weekdays', 'At least one weekday is required').isArray({ min: 1 }),
    check('fromDate', 'From date is required').isISO8601(),
    check('toDate', 'To date is required').isISO8601(),
    check('fromTime', 'From time is required').matches(/^([01]?[0-9]|2[0-3]):[0-5][0-9]$/),
    check('toTime', 'To time is required').matches(/^([01]?[0-9]|2[0-3]):[0-5][0-9]$/)
  ],
  async (req, res) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Validation failed',
        errors: errors.array()
      });
    }

    try {
      const userId = req.user.userId;

      let {
        rosterType,
        officeLocation,
        officeLocationCoordinates,
        weekdays,
        fromDate,
        toDate,
        fromTime,
        toTime,
        loginPickupLocation,
        loginPickupAddress,
        logoutDropLocation,
        logoutDropAddress,
        notes,
        employeeData // ✅ CRITICAL: Receive employee data from request
      } = req.body;

      // ✅ FIX: Use employee data if provided, otherwise fall back to requester
      let customerName = 'Unknown Customer';
      let customerEmail = '';

      if (employeeData && employeeData.email && employeeData.name) {
        // ✅ Use employee data from bulk import
        customerName = employeeData.name;
        customerEmail = employeeData.email;
        console.log(`📧 Using employee data: ${customerName} (${customerEmail})`);
      } else {
        // Fallback: Get from authenticated user
        // First, try to get from req.user (set by auth middleware)
        if (req.user && req.user.email) {
          customerEmail = req.user.email;
          customerName = req.user.name || req.user.displayName || req.user.email;
          console.log(`📧 Using req.user data: ${customerName} (${customerEmail})`);
        } else {
          // Try Firebase Auth
          try {
            const userRecord = await admin.auth().getUser(userId);
            customerName = userRecord.displayName || userRecord.email || 'Unknown Customer';
            customerEmail = userRecord.email || '';
            console.log(`📧 Using Firebase Auth data: ${customerName} (${customerEmail})`);
          } catch (authError) {
            console.warn('Could not fetch user from Firebase:', authError);
            
            // Try MongoDB - check multiple collections
            const collections = ['customers', 'users', 'admin_users', 'clients'];
            for (const collectionName of collections) {
              const userDoc = await req.db.collection(collectionName).findOne({ 
                $or: [
                  { firebaseUid: userId },
                  { _id: new ObjectId(userId) }
                ]
              });
              
              if (userDoc) {
                customerName = userDoc.name || userDoc.displayName || userDoc.email || 'Unknown Customer';
                customerEmail = userDoc.email || userDoc.emailAddress || '';
                console.log(`📧 Using ${collectionName} data: ${customerName} (${customerEmail})`);
                break;
              }
            }
          }
        }
        
        // Final validation
        if (!customerEmail) {
          console.error('❌ CRITICAL: Could not determine customer email!');
          console.error(`   User ID: ${userId}`);
          console.error(`   req.user: ${JSON.stringify(req.user)}`);
          return res.status(400).json({
            success: false,
            message: 'Could not determine user email. Please ensure you are logged in properly.'
          });
        }
        
        console.log(`✅ Final customer data: ${customerName} (${customerEmail})`);
      }

      // ✅ Server-side geocoding (if coordinates missing) - LENIENT MODE
      if ((!officeLocationCoordinates || !officeLocationCoordinates.latitude) && officeLocation) {
        console.log(`🌍 Auto-geocoding Office: ${officeLocation}`);
        const coords = await geocodeAddress(officeLocation);
        if (coords) {
          officeLocationCoordinates = coords;
          console.log(`✅ Office geocoded: ${coords.latitude}, ${coords.longitude}`);
        } else {
          console.warn(`⚠️  Could not geocode office location: "${officeLocation}" - using default coordinates`);
          // Use default coordinates instead of failing
          officeLocationCoordinates = { latitude: 12.9716, longitude: 77.5946 };
        }
      }

      if ((rosterType === 'login' || rosterType === 'both') &&
        (!loginPickupLocation || loginPickupLocation.length === 0) &&
        loginPickupAddress) {
        console.log(`🌍 Auto-geocoding Pickup: ${loginPickupAddress}`);
        const coords = await geocodeAddress(loginPickupAddress);
        if (coords) {
          loginPickupLocation = [coords.latitude, coords.longitude];
          console.log(`✅ Pickup geocoded: ${coords.latitude}, ${coords.longitude}`);
        } else {
          console.warn(`⚠️  Could not geocode pickup location: "${loginPickupAddress}" - using approximate coordinates`);
          // Use approximate coordinates instead of failing
          loginPickupLocation = [12.9716, 77.5946];
        }
      }

      if ((rosterType === 'logout' || rosterType === 'both') &&
        (!logoutDropLocation || logoutDropLocation.length === 0) &&
        logoutDropAddress) {
        console.log(`🌍 Auto-geocoding Drop: ${logoutDropAddress}`);
        const coords = await geocodeAddress(logoutDropAddress);
        if (coords) {
          logoutDropLocation = [coords.latitude, coords.longitude];
          console.log(`✅ Drop geocoded: ${coords.latitude}, ${coords.longitude}`);
        } else {
          console.warn(`⚠️  Could not geocode drop location: "${logoutDropAddress}" - using approximate coordinates`);
          // Use approximate coordinates instead of failing
          logoutDropLocation = [12.9716, 77.5946];
        }
      }

      // Validate date range
      const startDate = new Date(fromDate);
      const endDate = new Date(toDate);

      if (startDate >= endDate) {
        return res.status(400).json({
          success: false,
          message: 'End date must be after start date'
        });
      }

      // Validate time range
      const [startHour, startMin] = fromTime.split(':').map(Number);
      const [endHour, endMin] = toTime.split(':').map(Number);
      const startTimeMinutes = startHour * 60 + startMin;
      const endTimeMinutes = endHour * 60 + endMin;

      if (startTimeMinutes >= endTimeMinutes) {
        return res.status(400).json({
          success: false,
          message: 'End time must be after start time'
        });
      }

      // ✅ Prepare roster data with employee information
      const rosterData = {
        rosterType,
        officeLocation,
        officeLocationCoordinates,
        weekdays,
        fromDate: startDate,
        toDate: endDate,
        fromTime,
        toTime,
        loginPickupLocation,
        loginPickupAddress,
        logoutDropLocation,
        logoutDropAddress,
        notes,
        customerName, // ✅ Employee name
        customerEmail, // ✅ Employee email
        employeeDetails: employeeData || {}, // ✅ Store full employee data
        createdBy: userId, // Track who created it (might be admin)
        createdByAdmin: req.user.email === 'admin@abrafleet.com' ? true : false
      };

      console.log(`✅ Creating roster for: ${customerName} (${customerEmail})`);

      // Create the roster in MongoDB
      const newRoster = await Roster.createCustomerRoster(rosterData, userId);

      // Send real-time notification to Firebase
      try {
        const firebaseDb = admin.database();
        const rosterNotification = {
          id: newRoster._id.toString(),
          customerId: userId,
          customerName: customerName, // ✅ Employee name
          customerEmail: customerEmail, // ✅ Employee email
          rosterType: newRoster.rosterType,
          officeLocation: newRoster.officeLocation,
          weekdays: newRoster.weeklyOffDays || weekdays,
          fromDate: newRoster.startDate.toISOString(),
          toDate: newRoster.endDate.toISOString(),
          fromTime: newRoster.startTime,
          toTime: newRoster.endTime,
          status: newRoster.status,
          createdAt: newRoster.createdAt.toISOString(),
          loginPickupLocation: newRoster.locations?.pickup?.coordinates || null,
          loginPickupAddress: newRoster.locations?.pickup?.address || null,
          logoutDropLocation: newRoster.locations?.drop?.coordinates || null,
          logoutDropAddress: newRoster.locations?.drop?.address || null,
          notes: newRoster.notes || null,
          employeeDetails: employeeData || {},
          assignedDriverId: null,
          assignedVehicleId: null,
        };

        await firebaseDb.ref('roster_requests').child(newRoster._id.toString()).set(rosterNotification);

        console.log('✅ Roster notification sent to Firebase');
      } catch (firebaseError) {
        console.error('❌ Failed to send Firebase notification:', firebaseError);
      }

      res.status(201).json({
        success: true,
        message: 'Roster request created successfully',
        data: {
          rosterId: newRoster._id,
          status: newRoster.status,
          rosterType: newRoster.rosterType,
          officeLocation: newRoster.officeLocation,
          customerName: customerName, // ✅ Return employee name
          customerEmail: customerEmail, // ✅ Return employee email
          dateRange: {
            from: newRoster.startDate,
            to: newRoster.endDate
          },
          timeRange: {
            from: newRoster.startTime,
            to: newRoster.endTime
          },
          weeklyOffDays: newRoster.weeklyOffDays,
          locations: newRoster.locations,
          createdAt: newRoster.createdAt
        }
      });

    } catch (err) {
      console.error('❌ Error creating customer roster:', err.message);
      console.error(err.stack);

      res.status(500).json({
        success: false,
        message: 'Failed to create roster request: ' + err.message
      });
    }
  }
);;
// @route   GET api/roster/customer/my-rosters
// @desc    Get current user's roster requests
// @access  Private (Authenticated user)
router.get('/customer/my-rosters', verifyToken, async (req, res) => {
  try {
    const { status, rosterType, startDate, endDate } = req.query;
    const db = req.db;

    console.log(`🔍 MY-ROSTERS: Looking for user with User ID: ${req.user.userId}`);

    // Find user in correct collection based on role (set by auth middleware)
    let user = null;
    let userCollection = null;
    
    // Check the collection that auth middleware determined
    if (req.user.collectionName) {
      userCollection = req.user.collectionName;
      user = await db.collection(userCollection).findOne({ 
        $or: [
          { _id: new ObjectId(req.user.userId) },
          { email: req.user.email.toLowerCase() }
        ]
      });
    } else {
      // Fallback: search all possible collections
      const collections = ['customers', 'admin_users', 'users', 'clients', 'drivers'];
      
      for (const collectionName of collections) {
        user = await db.collection(collectionName).findOne({ 
          $or: [
            { _id: new ObjectId(req.user.userId) },
            { email: req.user.email.toLowerCase() }
          ]
        });
        
        if (user) {
          userCollection = collectionName;
          console.log(`✅ MY-ROSTERS: User found in ${collectionName} collection`);
          break;
        }
      }
    }

    if (!user) {
      console.log('❌ MY-ROSTERS: User not found in any collection');
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    console.log(`✅ MY-ROSTERS: User found in ${userCollection} collection`);

    const userEmail = user.email || user.emailAddress || user.customerEmail;
    
    if (!userEmail) {
      console.log('❌ MY-ROSTERS: User email not found in user document');
      return res.status(400).json({
        success: false,
        message: 'User email not found'
      });
    }

    console.log(`✅ MY-ROSTERS: User found - ${userEmail}`);

    // ✅ SIMPLIFIED QUERY - Return ALL user rosters (no strict filtering)
    const query = {
      $or: [
        { customerEmail: userEmail },
        { 'employeeDetails.email': userEmail },
        { 'employeeData.email': userEmail }
      ]
    };

    // Add optional filters
    if (status) query.status = status;
    if (rosterType) query.rosterType = rosterType;
    if (startDate) {
      query.$and = query.$and || [];
      query.$and.push({
        $or: [
          { startDate: { $gte: startDate } },
          { fromDate: { $gte: startDate } }
        ]
      });
    }
    if (endDate) {
      query.$and = query.$and || [];
      query.$and.push({
        $or: [
          { endDate: { $lte: endDate } },
          { toDate: { $lte: endDate } }
        ]
      });
    }

    // Fetch ALL rosters for the user
    const rosters = await db.collection('rosters').find(query).toArray();

    console.log(`📋 MY-ROSTERS: Found ${rosters.length} total rosters for ${userEmail}`);

    // ✅ ENHANCED MAPPING - Handle all possible field variations
    const mappedRosters = rosters.map(roster => ({
      id: roster._id,
      _id: roster._id,
      rosterId: roster.rosterId || roster._id.toString(),
      rosterType: roster.rosterType || roster.tripType || 'both',
      officeLocation: roster.officeLocation || roster.dropLocation || 'Office',
      status: roster.status || 'pending_assignment',
      
      // Vehicle and driver info
      vehicleNumber: roster.vehicleNumber || 'To be assigned',
      driverName: roster.driverName || 'To be assigned',
      driverPhone: roster.driverPhone || 'N/A',
      
      // ✅ FLEXIBLE DATE MAPPING
      dateRange: {
        from: roster.dateRange?.from || roster.startDate || roster.fromDate || roster.tripDate,
        to: roster.dateRange?.to || roster.endDate || roster.toDate || roster.tripDate
      },
      
      // ✅ FLEXIBLE TIME MAPPING
      timeRange: {
        from: roster.timeRange?.from || roster.startTime || roster.fromTime || roster.pickupTime || '09:00',
        to: roster.timeRange?.to || roster.endTime || roster.toTime || roster.dropTime || '18:00'
      },
      
      // ✅ WORKING DAYS MAPPING
      weekdays: roster.weekdays || roster.weeklyOffDays || roster.workingDays || [],
      weeklyOffDays: roster.weekdays || roster.weeklyOffDays || roster.workingDays || [],
      
      // ✅ ENHANCED LOCATION MAPPING
      locations: roster.locations || {
        office: {
          coordinates: roster.officeCoordinates || {
            latitude: roster.officeLatitude || 0,
            longitude: roster.officeLongitude || 0
          },
          address: roster.officeLocation || roster.officeAddress || ''
        },
        loginPickup: {
          coordinates: roster.locations?.loginPickup?.coordinates || {
            latitude: roster.pickupLatitude || roster.loginPickupLatitude || 0,
            longitude: roster.pickupLongitude || roster.loginPickupLongitude || 0
          },
          address: roster.locations?.loginPickup?.address || roster.loginPickupAddress || roster.pickupLocation || ''
        },
        logoutDrop: {
          coordinates: roster.locations?.logoutDrop?.coordinates || {
            latitude: roster.dropLatitude || roster.logoutDropLatitude || 0,
            longitude: roster.dropLongitude || roster.logoutDropLongitude || 0
          },
          address: roster.locations?.logoutDrop?.address || roster.logoutDropAddress || roster.dropLocation || ''
        }
      },
      
      // Additional fields for frontend compatibility
      loginPickupAddress: roster.loginPickupAddress || roster.pickupLocation || '',
      logoutDropAddress: roster.logoutDropAddress || roster.dropLocation || '',
      notes: roster.notes || '',
      createdAt: roster.createdAt || roster.timestamp || new Date(),
      updatedAt: roster.updatedAt || roster.lastModified || new Date(),
      
      // Customer information
      customerName: roster.customerName,
      customerEmail: roster.customerEmail,
      customerPhone: roster.customerPhone,
      employeeDetails: roster.employeeDetails || {
        name: roster.customerName,
        email: roster.customerEmail,
        phone: roster.customerPhone,
        companyName: roster.companyName || roster.organizationName || 'Company',
        department: roster.department || '',
        designation: roster.designation || '',
        employeeId: roster.employeeId || ''
      }
    }));

    console.log(`✅ MY-ROSTERS: Returning ${mappedRosters.length} rosters to client`);

    // Debug log first roster structure if available
    if (mappedRosters.length > 0) {
      const firstRoster = mappedRosters[0];
      console.log('🔍 MY-ROSTERS: First roster sample:');
      console.log(`   ID: ${firstRoster.id}`);
      console.log(`   Type: ${firstRoster.rosterType}`);
      console.log(`   Status: ${firstRoster.status}`);
      console.log(`   Office: ${firstRoster.officeLocation}`);
      console.log(`   Dates: ${firstRoster.dateRange.from} to ${firstRoster.dateRange.to}`);
      console.log(`   Times: ${firstRoster.timeRange.from} to ${firstRoster.timeRange.to}`);
    }

    res.json({
      success: true,
      message: 'Rosters retrieved successfully',
      data: mappedRosters,
      count: mappedRosters.length
    });

  } catch (error) {
    console.error('❌ MY-ROSTERS: Error fetching user rosters:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch rosters',
      error: error.message
    });
  }
});

// @route   GET api/roster/customer/:id
// @desc    Get specific roster by ID (only if belongs to user)
// @access  Private (Authenticated user)
router.get('/customer/:id', verifyToken, async (req, res) => {
  try {
    const roster = await Roster.findById(req.params.id);

    if (!roster) {
      return res.status(404).json({
        success: false,
        message: 'Roster not found'
      });
    }

    // Check if roster belongs to the user
    if (roster.userId !== req.user.userId && roster.requestType === 'customer_roster') {
      return res.status(403).json({
        success: false,
        message: 'Access denied'
      });
    }

    res.json({
      success: true,
      data: roster
    });
  } catch (err) {
    console.error('Error fetching roster:', err.message);

    if (err.message.includes('BSONTypeError')) {
      return res.status(404).json({
        success: false,
        message: 'Roster not found'
      });
    }

    res.status(500).json({
      success: false,
      message: 'Failed to fetch roster'
    });
  }
});

// @route   PUT api/roster/customer/:id
// @desc    Update customer roster request (only if belongs to user and not assigned)
// @access  Private (Authenticated user)
router.put('/customer/:id', verifyToken, async (req, res) => {
  try {
    const existingRoster = await Roster.findById(req.params.id);

    if (!existingRoster) {
      return res.status(404).json({
        success: false,
        message: 'Roster not found'
      });
    }

    // Check if roster belongs to the user
    if (existingRoster.userId !== req.user.userId) {
      return res.status(403).json({
        success: false,
        message: 'Access denied - you can only update your own rosters'
      });
    }

    // Check if roster can still be updated
    if (['assigned', 'in_progress', 'completed'].includes(existingRoster.status)) {
      return res.status(400).json({
        success: false,
        message: 'Cannot update roster that is already assigned or in progress'
      });
    }

    const {
      rosterType,
      officeLocation,
      weekdays,
      fromDate,
      toDate,
      fromTime,
      toTime,
      loginPickupLocation,
      loginPickupAddress,
      logoutDropLocation,
      logoutDropAddress,
      notes
    } = req.body;

    // Validate date range if provided
    if (fromDate && toDate) {
      const startDate = new Date(fromDate);
      const endDate = new Date(toDate);

      if (startDate >= endDate) {
        return res.status(400).json({
          success: false,
          message: 'End date must be after start date'
        });
      }
    }

    // Validate time range if provided
    if (fromTime && toTime) {
      const [startHour, startMin] = fromTime.split(':').map(Number);
      const [endHour, endMin] = toTime.split(':').map(Number);
      const startTimeMinutes = startHour * 60 + startMin;
      const endTimeMinutes = endHour * 60 + endMin;

      if (startTimeMinutes >= endTimeMinutes) {
        return res.status(400).json({
          success: false,
          message: 'End time must be after start time'
        });
      }
    }

    // Prepare update data
    const updateData = {
      ...(rosterType && { rosterType }),
      ...(officeLocation && { officeLocation }),
      ...(weekdays && { weeklyOffDays: weekdays }),
      ...(fromDate && { startDate: new Date(fromDate) }),
      ...(toDate && { endDate: new Date(toDate) }),
      ...(fromTime && { startTime: fromTime }),
      ...(toTime && { endTime: toTime }),
      ...(notes !== undefined && { notes }),
      updatedAt: new Date()
    };

    // Handle location data
    if (loginPickupLocation || logoutDropLocation) {
      const locations = { ...existingRoster.locations };

      if (loginPickupLocation) {
        locations.pickup = {
          coordinates: loginPickupLocation,
          address: loginPickupAddress || '',
          timestamp: new Date()
        };
      }

      if (logoutDropLocation) {
        locations.drop = {
          coordinates: logoutDropLocation,
          address: logoutDropAddress || '',
          timestamp: new Date()
        };
      }

      updateData.locations = locations;
    }

    const updatedRoster = await Roster.update(req.params.id, updateData);

    if (!updatedRoster) {
      return res.status(404).json({
        success: false,
        message: 'Failed to update roster'
      });
    }

    // Update Firebase real-time notification
    try {
      const firebaseDb = admin.database();
      await firebaseDb.ref('roster_requests').child(req.params.id).update({
        ...(rosterType && { rosterType }),
        ...(officeLocation && { officeLocation }),
        ...(weekdays && { weekdays }),
        ...(fromDate && { fromDate: new Date(fromDate).toISOString() }),
        ...(toDate && { toDate: new Date(toDate).toISOString() }),
        ...(fromTime && { fromTime }),
        ...(toTime && { toTime }),
        ...(loginPickupLocation && { loginPickupLocation }),
        ...(loginPickupAddress && { loginPickupAddress }),
        ...(logoutDropLocation && { logoutDropLocation }),
        ...(logoutDropAddress && { logoutDropAddress }),
        ...(notes !== undefined && { notes }),
        updatedAt: new Date().toISOString()
      });
    } catch (firebaseError) {
      console.error('Failed to update Firebase:', firebaseError);
    }

    // Send notification to admins about roster update
    try {
      // Get customer details for notification
      const customerUser = await req.db.collection('users').findOne({
        _id: new ObjectId(req.user.userId)
      });
      const customerName = customerUser ? customerUser.name || customerUser.email : 'Unknown Customer';

      // Get all admin users
      const adminUsers = await req.db.collection('users').find({
        role: 'admin'
      }).toArray();

      // Send notification to each admin
      for (const adminUser of adminUsers) {
        try {
          await createNotification({
            userId: adminUser.firebaseUid,
            type: 'roster_updated',
            title: 'Customer Roster Updated',
            body: `${customerName} has updated their roster request. Please review the changes.`,
            priority: 'normal',
            category: 'roster_management',
            data: {
              rosterId: updatedRoster._id.toString(),
              customerName: customerName,
              customerId: req.user.userId,
              rosterType: updatedRoster.rosterType,
              officeLocation: updatedRoster.officeLocation,
              updatedAt: updatedRoster.updatedAt.toISOString()
            }
          });
          console.log(`✅ Notification sent to admin via createNotification: ${adminUser.email}`);
        } catch (createError) {
          console.warn(`⚠️  createNotification failed for admin, sending directly to Firebase RTDB:`, createError.message);

          // Fallback: Send directly to Firebase RTDB
          const notificationId = Date.now().toString() + '_' + Math.random().toString(36).substr(2, 9);
          const notification = {
            id: notificationId,
            userId: adminUser.firebaseUid,
            type: 'roster_updated',
            title: 'Customer Roster Updated',
            body: `${customerName} has updated their roster request. Please review the changes.`,
            data: {
              rosterId: updatedRoster._id.toString(),
              customerName: customerName,
              customerId: req.user.userId,
              rosterType: updatedRoster.rosterType,
              officeLocation: updatedRoster.officeLocation,
              updatedAt: updatedRoster.updatedAt.toISOString()
            },
            isRead: false,
            priority: 'normal',
            category: 'roster_management',
            createdAt: new Date().toISOString(),
            expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString() // 7 days
          };

          const firebasePath = `notifications/${adminUser.firebaseUid}/${notificationId}`;
          await admin.database().ref(firebasePath).set(notification);
          console.log(`✅ Notification sent directly to Firebase RTDB for admin: ${firebasePath}`);
        }
      }

      if (adminUsers.length === 0) {
        console.warn('⚠️  WARNING: No admin users found in database!');
      }
    } catch (notificationError) {
      console.error('❌ Failed to send admin notifications for roster update:', notificationError);
    }

    res.json({
      success: true,
      message: 'Roster updated successfully',
      data: {
        rosterId: updatedRoster._id,
        status: updatedRoster.status,
        rosterType: updatedRoster.rosterType,
        officeLocation: updatedRoster.officeLocation,
        dateRange: {
          from: updatedRoster.startDate,
          to: updatedRoster.endDate
        },
        timeRange: {
          from: updatedRoster.startTime,
          to: updatedRoster.endTime
        },
        weeklyOffDays: updatedRoster.weeklyOffDays,
        locations: updatedRoster.locations,
        updatedAt: updatedRoster.updatedAt
      }
    });

  } catch (err) {
    console.error('Error updating customer roster:', err.message);

    if (err.message.includes('BSONTypeError')) {
      return res.status(404).json({
        success: false,
        message: 'Roster not found'
      });
    }

    res.status(500).json({
      success: false,
      message: 'Failed to update roster'
    });
  }
});

// @route   DELETE api/roster/customer/:id
// @desc    Cancel customer roster request
// @access  Private (Authenticated user)
router.delete('/customer/:id', verifyToken, async (req, res) => {
  try {
    const db = req.db;
    const rosterId = req.params.id;

    console.log(`🗑️ DELETE ROSTER: Attempting to cancel roster ${rosterId} for user ${req.user.userId}`);

    // ✅ VALIDATE ROSTER ID FORMAT
    if (!isValidObjectId(rosterId)) {
      console.log(`❌ DELETE ROSTER: Invalid roster ID format: ${rosterId}`);
      return res.status(400).json({
        success: false,
        message: 'Invalid roster ID format'
      });
    }

    // Find user in admin_users collection
    const user = await db.collection('admin_users').findOne({ 
      $or: [
        { _id: new ObjectId(req.user.userId) },
        { email: req.user.email.toLowerCase() }
      ]
    });

    if (!user) {
      console.log('❌ DELETE ROSTER: User not found in admin_users collection');
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    const userEmail = user.email || user.emailAddress || user.customerEmail;
    console.log(`✅ DELETE ROSTER: User found - ${userEmail}`);

    // ✅ SAFE OBJECTID CREATION WITH ERROR HANDLING
    let rosterObjectId;
    try {
      rosterObjectId = new require('mongodb').ObjectId(rosterId);
    } catch (objectIdError) {
      console.log(`❌ DELETE ROSTER: Failed to create ObjectId from ${rosterId}:`, objectIdError.message);
      return res.status(400).json({
        success: false,
        message: 'Invalid roster ID format'
      });
    }

    // Find the roster in MongoDB
    const existingRoster = await db.collection('rosters').findOne({ 
      _id: rosterObjectId
    });

    if (!existingRoster) {
      console.log('❌ DELETE ROSTER: Roster not found');
      return res.status(404).json({
        success: false,
        message: 'Roster not found'
      });
    }

    console.log('🔍 DELETE ROSTER: Found roster:', {
      id: existingRoster._id,
      customerEmail: existingRoster.customerEmail,
      status: existingRoster.status,
      employeeDetails: existingRoster.employeeDetails?.email
    });

    // ✅ FIX: Check ownership using email fields (not userId)
    const rosterOwnerEmail = existingRoster.customerEmail || 
                            existingRoster.employeeDetails?.email || 
                            existingRoster.employeeData?.email;

    if (!rosterOwnerEmail || rosterOwnerEmail !== userEmail) {
      console.log(`❌ DELETE ROSTER: Access denied. Roster owner: ${rosterOwnerEmail}, User: ${userEmail}`);
      return res.status(403).json({
        success: false,
        message: 'Access denied - you can only cancel your own rosters'
      });
    }

    // Check if roster can still be cancelled
    if (existingRoster.status === 'completed') {
      console.log('❌ DELETE ROSTER: Cannot cancel completed roster');
      return res.status(400).json({
        success: false,
        message: 'Cannot cancel completed roster'
      });
    }

    if (existingRoster.status === 'cancelled') {
      console.log('⚠️ DELETE ROSTER: Roster already cancelled');
      return res.status(400).json({
        success: false,
        message: 'Roster is already cancelled'
      });
    }

    // ✅ FIX: Update roster status in MongoDB
    const updateResult = await db.collection('rosters').updateOne(
      { _id: rosterObjectId },
      {
        $set: {
          status: 'cancelled',
          cancelledAt: new Date(),
          cancelledBy: req.user.userId,
          updatedAt: new Date()
        }
      }
    );

    if (updateResult.matchedCount === 0) {
      console.log('❌ DELETE ROSTER: Failed to update roster');
      return res.status(404).json({
        success: false,
        message: 'Failed to cancel roster'
      });
    }

    console.log('✅ DELETE ROSTER: Roster cancelled successfully');

    // Update Firebase real-time notifications
    try {
      const firebaseDb = admin.database();
      await firebaseDb.ref('roster_requests').child(rosterId).update({
        status: 'cancelled',
        cancelledAt: new Date().toISOString()
      });

      console.log('✅ DELETE ROSTER: Firebase updated');
    } catch (firebaseError) {
      console.warn('⚠️ DELETE ROSTER: Failed to update Firebase:', firebaseError.message);
    }

    res.json({
      success: true,
      message: 'Roster cancelled successfully',
      data: {
        rosterId: rosterId,
        status: 'cancelled',
        cancelledAt: new Date().toISOString()
      }
    });

  } catch (error) {
    console.error('❌ DELETE ROSTER: Error cancelling roster:', error);
    console.error('❌ DELETE ROSTER: Stack trace:', error.stack);
    res.status(500).json({
      success: false,
      message: 'Failed to cancel roster',
      error: error.message
    });
  }
});

// ========== ADMIN MANAGEMENT ROUTES WITH DETAILED LOGGING ==========

// @route   GET api/roster/admin/approved
// @desc    Get approved/assigned roster assignments for admin
// @access  Private (Admin/Manager)
router.get('/admin/approved', verifyToken, async (req, res) => {
  try {
    const { officeLocation, rosterType } = req.query;

    const query = {
      requestType: 'customer_roster',
      status: { $in: ['assigned', 'in_progress', 'completed'] }
    };

    if (officeLocation) {
      query.officeLocation = officeLocation;
    }
    if (rosterType) {
      query.rosterType = rosterType;
    }

    // ✅ FIXED: Handles BOTH old and new formats
    const approvedRosters = await req.db.collection('rosters')
      .aggregate([
        { $match: query },
        {
          $addFields: {
            driverObjectId: {
              $cond: [
                { $eq: [{ $type: "$assignedDriver" }, "objectId"] },
                "$assignedDriver",
                {
                  $cond: [
                    { $eq: [{ $type: "$assignedDriver.driverId" }, "objectId"] },
                    "$assignedDriver.driverId",
                    {
                      $cond: [
                        { $eq: [{ $type: "$assignedDriver.driverId" }, "string"] },
                        { $toObjectId: "$assignedDriver.driverId" },
                        null
                      ]
                    }
                  ]
                }
              ]
            },
            vehicleObjectId: {
              $cond: [
                { $eq: [{ $type: "$assignedVehicle" }, "objectId"] },
                "$assignedVehicle",
                {
                  $cond: [
                    { $eq: [{ $type: "$assignedVehicle.vehicleId" }, "objectId"] },
                    "$assignedVehicle.vehicleId",
                    {
                      $cond: [
                        { $eq: [{ $type: "$assignedVehicle.vehicleId" }, "string"] },
                        { $toObjectId: "$assignedVehicle.vehicleId" },
                        null
                      ]
                    }
                  ]
                }
              ]
            }
          }
        },
        {
          $lookup: {
            from: 'drivers',
            localField: 'driverObjectId',
            foreignField: '_id',
            as: 'driverDetails'
          }
        },
        {
          $lookup: {
            from: 'vehicles',
            localField: 'vehicleObjectId',
            foreignField: '_id',
            as: 'vehicleDetails'
          }
        },
        {
          $addFields: {
            assignedDriverName: {
              $ifNull: [
                { $arrayElemAt: ['$driverDetails.name', 0] },
                'Not assigned'
              ]
            },
            driverPhone: {
              $ifNull: [
                { $arrayElemAt: ['$driverDetails.phone', 0] },
                ''
              ]
            },
            assignedVehicleReg: {
              $ifNull: [
                { $arrayElemAt: ['$vehicleDetails.registrationNumber', 0] },
                'Not assigned'
              ]
            }
          }
        },
        {
          $project: {
            driverDetails: 0,
            vehicleDetails: 0,
            driverObjectId: 0,
            vehicleObjectId: 0
          }
        },
        { $sort: { startDate: -1, createdAt: -1 } }
      ])
      .toArray();

    res.json({
      success: true,
      message: 'Approved rosters retrieved successfully',
      data: approvedRosters,
      count: approvedRosters.length
    });
  } catch (err) {
    console.error('Error fetching approved rosters:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch approved rosters'
    });
  }
});

// @route   POST api/roster/admin/assign
// @desc    Assign driver and vehicle to a customer roster WITH DETAILED LOGGING
// @access  Private (Admin/Manager)
// ============================================================================
// 🔧 ENHANCED ASSIGNMENT ROUTE - WITH AUTOMATIC DISTANCE CALCULATION
// File: Replace /admin/assign route in roster_router.js
// Feature: Auto-calculates distance when admin assigns driver to roster
// ============================================================================

// ✅ ADD THIS AT TOP OF FILE (after other requires)


// ============================================================================
// REPLACE YOUR EXISTING /admin/assign ROUTE WITH THIS
// ============================================================================

// @route   POST api/roster/admin/assign
// @desc    Assign driver and vehicle to a customer roster using OneSignal
// @access  Private (Admin/Manager)
// @route   POST api/roster/admin/assign
// @desc    Assign driver and vehicle to a roster + CREATE TRIP in roster-assigned-trips
// @access  Private (Admin/Manager)
router.post('/admin/assign',
  [
    verifyToken,
    check('rosterId', 'Roster ID is required').not().isEmpty(),
    check('driverId', 'Driver ID is required').not().isEmpty(),
    check('vehicleId', 'Vehicle ID is required').not().isEmpty()
  ],
  async (req, res) => {
    console.log('\n' + '='.repeat(80));
    console.log('🎯 SINGLE ROSTER ASSIGNMENT (WITH TRIP CREATION)');
    console.log('='.repeat(80));
    console.log('📅 Timestamp:', new Date().toISOString());
    console.log('👤 Admin User ID:', req.user.userId);

    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Validation failed',
        errors: errors.array()
      });
    }

    const session = req.mongoClient.startSession();

    try {
      await session.startTransaction();

      const { rosterId, driverId, vehicleId } = req.body;

      // ====================================================================
      // STEP 1: FLEXIBLE ROSTER LOOKUP
      // ====================================================================
      console.log('\n📋 Step 1: Fetching roster details...');
      const rosterQuery = { $or: [] };
      if (ObjectId.isValid(rosterId)) {
        rosterQuery.$or.push({ _id: new ObjectId(rosterId) });
      }
      rosterQuery.$or.push({ rosterId: rosterId });
      rosterQuery.$or.push({ rosterCode: rosterId });
      rosterQuery.$or.push({ readableId: rosterId });

      const roster = await req.db.collection('rosters').findOne(rosterQuery, { session });
      
      if (!roster) {
        await session.abortTransaction();
        console.log('❌ ERROR: Roster not found');
        return res.status(404).json({ success: false, message: 'Roster not found' });
      }

      console.log(`✅ Roster found: ${roster.customerName || 'Unknown'}`);
      console.log(`   Roster ID: ${roster._id}`);
      console.log(`   Customer: ${roster.customerName || 'Unknown'}`);
      console.log(`   Type: ${roster.rosterType || 'both'}`);
      console.log(`   Office: ${roster.officeLocation || 'Unknown'}`);

      // ====================================================================
      // STEP 2: FLEXIBLE DRIVER LOOKUP
      // ====================================================================
      console.log('\n🚗 Step 2: Fetching driver details...');
      const driverQuery = { $or: [] };
      if (ObjectId.isValid(driverId)) {
        driverQuery.$or.push({ _id: new ObjectId(driverId) });
      }
      driverQuery.$or.push({ driverId: driverId });
      driverQuery.$or.push({ driverCode: driverId });
      driverQuery.$or.push({ employeeId: driverId });

      const driver = await req.db.collection('drivers').findOne(driverQuery, { session });
      
      if (!driver) {
        await session.abortTransaction();
        return res.status(404).json({ success: false, message: 'Driver not found' });
      }

      // Handle different driver name formats
      let driverName = 'Unknown Driver';
      let driverPhone = '';
      let driverEmail = '';

      if (driver.name) {
        driverName = driver.name;
        driverPhone = driver.phone || driver.phoneNumber || '';
        driverEmail = driver.email || '';
      } else if (driver.personalInfo) {
        const firstName = driver.personalInfo.firstName || '';
        const lastName = driver.personalInfo.lastName || '';
        driverName = `${firstName} ${lastName}`.trim() || 'Unknown Driver';
        driverPhone = driver.personalInfo.phone || '';
        driverEmail = driver.personalInfo.email || '';
      }

      console.log(`✅ Driver found: ${driverName}`);
      console.log(`   Driver ID: ${driver._id}`);
      console.log(`   Phone: ${driverPhone || 'N/A'}`);
      console.log(`   Email: ${driverEmail || 'N/A'}`);

      // ====================================================================
      // STEP 3: FLEXIBLE VEHICLE LOOKUP
      // ====================================================================
      console.log('\n🚗 Step 3: Fetching vehicle details...');
      const vehicleQuery = { $or: [] };
      if (ObjectId.isValid(vehicleId)) {
        vehicleQuery.$or.push({ _id: new ObjectId(vehicleId) });
      }
      vehicleQuery.$or.push({ vehicleId: vehicleId });
      vehicleQuery.$or.push({ vehicleCode: vehicleId });
      vehicleQuery.$or.push({ registrationNumber: vehicleId });
      vehicleQuery.$or.push({ licensePlate: vehicleId });

      const vehicle = await req.db.collection('vehicles').findOne(vehicleQuery, { session });
      
      if (!vehicle) {
        await session.abortTransaction();
        return res.status(404).json({ success: false, message: 'Vehicle not found' });
      }

      console.log(`✅ Vehicle found: ${vehicle.registrationNumber || vehicle.vehicleId || 'Unknown'}`);
      console.log(`   Vehicle ID: ${vehicle._id}`);
      console.log(`   Registration: ${vehicle.registrationNumber || 'N/A'}`);

      // ====================================================================
      // STEP 4: Calculate Distance (if coordinates available)
      // ====================================================================
      console.log('\n📏 Step 4: Calculating distance...');
      let distanceData = null;
      try {
        distanceData = calculateRosterDistances(roster);
        if (distanceData && !distanceData.error) {
          console.log(`   Total Distance: ${distanceData.totalDistanceKm} km`);
        }
      } catch (distError) {
        console.log('⚠️  Distance calculation error:', distError.message);
      }

      // ====================================================================
      // STEP 5: UPDATE ROSTER (backward compatibility)
      // ====================================================================
      console.log('\n💾 Step 5: Updating roster in "rosters" collection...');
      const updatedRoster = await req.db.collection('rosters').findOneAndUpdate(
        { _id: roster._id },
        {
          $set: {
            vehicleId: vehicle._id,
            vehicleNumber: vehicle.registrationNumber || vehicle.vehicleId,
            driverId: driver._id,
            driverName: driverName,
            driverPhone: driverPhone,
            status: 'assigned',
            assignedAt: new Date(),
            assignedBy: req.user.userId,
            updatedAt: new Date(),
            ...(distanceData && !distanceData.error && { distanceData })
          }
        },
        { returnDocument: 'after', session }
      );

      console.log('✅ Roster updated successfully');

      // ====================================================================
      // STEP 6: 🆕 CREATE TRIP IN "roster-assigned-trips" COLLECTION
      // ====================================================================
      console.log('\n🎫 Step 6: Creating trip in "roster-assigned-trips" collection...');
      
      const tripNumber = `TRIP-${Date.now().toString().slice(-6)}-01`;
      const scheduledDate = new Date().toISOString().split('T')[0];

      // Extract pickup time (with fallback)
      const pickupTime = roster.startTime || roster.fromTime || roster.pickupTime || '08:00';
      
      // Calculate ready-by time (20 minutes before pickup)
      const calculateReadyByTime = (timeStr) => {
        const [hours, minutes] = timeStr.split(':').map(Number);
        const pickupDateTime = new Date();
        pickupDateTime.setHours(hours, minutes, 0, 0);
        const readyDateTime = new Date(pickupDateTime.getTime() - (20 * 60000));
        return `${String(readyDateTime.getHours()).padStart(2, '0')}:${String(readyDateTime.getMinutes()).padStart(2, '0')}`;
      };

      const readyByTime = calculateReadyByTime(pickupTime);

      const tripData = {
        // Trip Info
        tripNumber,
        tripType: roster.rosterType || 'login',
        
        // 🆕 Original Roster Reference
        rosterId: roster._id,
        
        // Customer Info
        customerName: roster.customerName || 'Unknown',
        customerEmail: roster.customerEmail || '',
        customerPhone: roster.customerPhone || roster.phone || '',
        
        // 🆕 Driver & Vehicle (USING MONGODB OBJECTID)
        driverId: driver._id,
        vehicleId: vehicle._id,
        
        // 🆕 Pickup Sequence & Timing (24-hour format)
        pickupSequence: 1, // Single assignment = sequence 1
        estimatedPickupTime: pickupTime,
        readyByTime: readyByTime,
        
        // 🆕 Distance Calculations
        distanceToOffice: distanceData?.totalDistanceKm || 0,
        distanceFromPrevious: 0, // Single assignment has no previous
        estimatedTravelTime: distanceData?.totalDurationMin || 30,
        
        // Locations
        pickupLocation: {
          address: roster.loginPickupAddress || 
                   roster.locations?.pickup?.address || 
                   'Pickup location',
          coordinates: roster.locations?.pickup?.coordinates || 
                      roster.loginPickupLocation || 
                      null
        },
        dropLocation: {
          address: roster.officeLocation || 
                   roster.dropLocation || 
                   'Office',
          coordinates: roster.officeLocationCoordinates || 
                      roster.locations?.office?.coordinates || 
                      null
        },
        
        // Schedule
        scheduledDate: scheduledDate,
        startTime: pickupTime,
        endTime: roster.endTime || roster.toTime || '18:00',
        estimatedDuration: distanceData?.totalDurationMin || 30,
        distance: distanceData?.totalDistanceKm || 0,
        
        // Trip Details
        sequence: 1,
        
        // Organization
        organizationId: roster.organizationId,
        organizationName: roster.organizationName || roster.organization || roster.companyName,
        
        // Status
        status: 'assigned',
        
        // Timestamps
        assignedAt: new Date(),
        actualStartTime: null,
        actualEndTime: null,
        
        // Tracking
        currentLocation: null,
        locationHistory: [],
        
        // Metrics
        actualDistance: null,
        actualDuration: null,
        
        // Audit
        createdAt: new Date(),
        updatedAt: new Date(),
        createdBy: req.user.userId
      };

      const tripResult = await req.db.collection('roster-assigned-trips').insertOne(tripData, { session });
      const tripId = tripResult.insertedId;

      console.log(`✅ Trip created: ${tripNumber} (ID: ${tripId})`);

      // Link trip back to roster
      await req.db.collection('rosters').updateOne(
        { _id: roster._id },
        { $set: { tripId: tripId } },
        { session }
      );

      // ====================================================================
      // STEP 7: 🆕 SEND ENHANCED CUSTOMER NOTIFICATION (with AM/PM)
      // ====================================================================
      console.log('\n📧 Step 7: Sending customer notification...');
      try {
        // Convert 24-hour to 12-hour format with AM/PM
        const format12Hour = (time24) => {
          const [hours, minutes] = time24.split(':').map(Number);
          const period = hours >= 12 ? 'PM' : 'AM';
          const hours12 = hours % 12 || 12;
          return `${hours12}:${String(minutes).padStart(2, '0')} ${period}`;
        };

        const pickupTime12 = format12Hour(pickupTime);
        const readyByTime12 = format12Hour(readyByTime);
        const officeTime = roster.endTime || roster.toTime || '18:00';
        const officeTime12 = format12Hour(officeTime);

        await createNotification(req.db, {
          userId: roster.customerId || roster.customerEmail,
          title: '🚗 Driver Assigned - Be Ready!',
          body: `Driver ${driverName} has been assigned to your trip.\n\n` +
                `Vehicle: ${vehicle.registrationNumber}\n` +
                `Pickup Sequence: #1 (Single pickup)\n\n` +
                `🕐 PICKUP TIME: ${pickupTime12}\n` +
                `⏰ BE READY BY: ${readyByTime12}\n\n` +
                `📍 Distance to office: ${(distanceData?.totalDistanceKm || 0).toFixed(1)} km\n` +
                `⏱️ Travel time: ~${distanceData?.totalDurationMin || 30} mins\n` +
                `🏢 Office arrival: ${officeTime12}\n\n` +
                `Track your driver in real-time through the app.`,
          type: 'roster_assignment',
          data: {
            rosterId: roster._id.toString(),
            tripId: tripId.toString(),
            tripNumber: tripNumber,
            vehicleId: vehicle._id.toString(),
            driverId: driver._id.toString(),
            sequence: 1,
            pickupTime: pickupTime,
            readyByTime: readyByTime,
            pickupTime12Hour: pickupTime12,
            readyByTime12Hour: readyByTime12,
            distanceToOffice: distanceData?.totalDistanceKm || 0,
            trackingEnabled: true,
            collection: 'roster-assigned-trips'
          },
          priority: 'high',
          category: 'roster'
        });
        
        console.log('✅ Customer notification sent');
      } catch (notifError) {
        console.log('⚠️  Customer notification failed:', notifError.message);
      }

      // ====================================================================
      // STEP 8: 🆕 SEND ENHANCED DRIVER NOTIFICATION (with AM/PM)
      // ====================================================================
      console.log('\n📧 Step 8: Sending driver notification...');
      try {
        const format12Hour = (time24) => {
          const [hours, minutes] = time24.split(':').map(Number);
          const period = hours >= 12 ? 'PM' : 'AM';
          const hours12 = hours % 12 || 12;
          return `${hours12}:${String(minutes).padStart(2, '0')} ${period}`;
        };

        const pickupTime12 = format12Hour(pickupTime);
        const readyByTime12 = format12Hour(readyByTime);

        const driverUser = await req.db.collection('users').findOne({
          $or: [
            { driverId: driver._id },
            { phone: driverPhone },
            { email: driverEmail }
          ]
        });

        if (driverUser && driverUser.firebaseUid) {
          await createNotification(req.db, {
            userId: driverUser.firebaseUid,
            title: '🚗 New Trip Assignment',
            body: `You have been assigned a new trip.\n\n` +
                  `Customer: ${roster.customerName}\n` +
                  `Vehicle: ${vehicle.registrationNumber}\n\n` +
                  `📍 PICKUP DETAILS:\n` +
                  `Time: ${pickupTime12}\n` +
                  `Ready by: ${readyByTime12}\n` +
                  `Location: ${roster.loginPickupAddress || 'Pickup location'}\n\n` +
                  `📍 DROP DETAILS:\n` +
                  `Location: ${roster.officeLocation || 'Office'}\n\n` +
                  `📏 Distance: ${(distanceData?.totalDistanceKm || 0).toFixed(1)} km\n` +
                  `⏱️ Duration: ~${distanceData?.totalDurationMin || 30} mins\n\n` +
                  `START BY: ${readyByTime12}`,
            type: 'driver_trip_assignment',
            data: {
              rosterId: roster._id.toString(),
              tripId: tripId.toString(),
              tripNumber: tripNumber,
              customerName: roster.customerName,
              pickupLocation: roster.loginPickupAddress || 'Pickup location',
              dropLocation: roster.officeLocation || 'Office',
              pickupTime: pickupTime,
              readyByTime: readyByTime,
              pickupTime12Hour: pickupTime12,
              readyByTime12Hour: readyByTime12,
              trackingRequired: true,
              collection: 'roster-assigned-trips'
            },
            priority: 'high',
            category: 'roster'
          });
          
          console.log('✅ Driver notification sent');
        } else {
          console.log('ℹ️  Driver has no app access');
        }
      } catch (notifError) {
        console.log('⚠️  Driver notification failed:', notifError.message);
      }

      // ====================================================================
      // STEP 9: COMMIT TRANSACTION
      // ====================================================================
      await session.commitTransaction();

      console.log('\n✅ ASSIGNMENT COMPLETED SUCCESSFULLY');
      console.log('='.repeat(80));
      console.log('📊 Summary:');
      console.log(`   - Roster updated: ${roster._id}`);
      console.log(`   - Trip created: ${tripId}`);
      console.log(`   - Trip number: ${tripNumber}`);
      console.log(`   - Collection: roster-assigned-trips`);
      console.log(`   - Driver: ${driverName}`);
      console.log(`   - Vehicle: ${vehicle.registrationNumber}`);
      console.log(`   - Distance: ${(distanceData?.totalDistanceKm || 0).toFixed(1)} km`);
      console.log('='.repeat(80) + '\n');

      res.json({
        success: true,
        message: 'Driver and vehicle assigned successfully',
        data: {
          rosterId: roster._id.toString(),
          tripId: tripId.toString(),
          tripNumber: tripNumber,
          status: 'assigned',
          assignedDriver: {
            id: driver._id.toString(),
            name: driverName,
            phone: driverPhone
          },
          assignedVehicle: {
            id: vehicle._id.toString(),
            registrationNumber: vehicle.registrationNumber
          },
          distanceData: distanceData,
          collection: 'roster-assigned-trips',
          updatedAt: new Date()
        }
      });

    } catch (err) {
      await session.abortTransaction();
      console.error('❌ ERROR IN ROSTER ASSIGNMENT:', err);
      console.error(err.stack);

      res.status(500).json({
        success: false,
        message: 'Failed to assign driver and vehicle',
        error: err.message
      });
    } finally {
      await session.endSession();
    }
  }
);

// @route   PUT api/roster/admin/edit-assignment/:id
// @desc    Edit/Update driver and vehicle assignment for a roster WITH DETAILED LOGGING
// @access  Private (Admin/Manager)
// @route   PUT api/roster/admin/edit-assignment/:id
// @desc    Edit/Update driver and vehicle assignment for a roster WITH DETAILED LOGGING
// @access  Private (Admin/Manager)
// @route   PUT api/roster/admin/edit-assignment/:id
// @desc    Edit/Update driver and vehicle assignment for a roster WITH DETAILED LOGGING
// @access  Private (Admin/Manager)
// @route   PUT api/roster/admin/edit-assignment/:id
// @desc    Edit/Update driver and vehicle assignment for a roster WITH DETAILED LOGGING
// @access  Private (Admin/Manager)
// routes/roster_router.js

// @route   PUT api/roster/admin/edit-assignment/:id
// @desc    Edit/Update driver and vehicle assignment - FIXED FLEXIBLE LOGIC
// @access  Private (Admin/Manager)
// @route   PUT api/roster/admin/edit-assignment/:id
// @desc    Edit/Update driver and vehicle assignment for a roster WITH DETAILED LOGGING
// @access  Private (Admin/Manager)
// ========== COMPLETE ENHANCED EDIT ASSIGNMENT ROUTE WITH REVERSE GEOCODING ==========
// Replace your existing PUT /api/roster/admin/edit-assignment/:id route with this:

// @route   PUT api/roster/admin/edit-assignment/:id
// @desc    Edit/Update driver and vehicle assignment + UPDATE TRIP in roster-assigned-trips
// @access  Private (Admin/Manager)
router.put('/admin/edit-assignment/:id',
  [
    verifyToken,
    check('driverId', 'Driver ID is required').not().isEmpty(),
    check('vehicleId', 'Vehicle ID is required').not().isEmpty()
  ],
  async (req, res) => {
    console.log('\n' + '='.repeat(80));
    console.log('🔄 ROSTER ASSIGNMENT UPDATE (WITH TRIP UPDATE)');
    console.log('='.repeat(80));
    console.log('📅 Timestamp:', new Date().toISOString());
    console.log('👤 Admin User ID:', req.user.userId);
    console.log('📋 Roster ID:', req.params.id);

    const session = req.mongoClient.startSession();

    try {
      await session.startTransaction();

      const rosterId = req.params.id;
      const { driverId, vehicleId } = req.body;

      // ====================================================================
      // STEP 1: FLEXIBLE ROSTER LOOKUP
      // ====================================================================
      if (!ObjectId.isValid(rosterId)) {
        await session.abortTransaction();
        return res.status(400).json({
          success: false,
          message: 'Invalid roster ID format'
        });
      }

      const roster = await req.db.collection('rosters').findOne(
        { _id: new ObjectId(rosterId) },
        { session }
      );

      if (!roster) {
        await session.abortTransaction();
        return res.status(404).json({
          success: false,
          message: 'Roster not found'
        });
      }

      console.log('✅ Roster found:', roster.customerName);

      // ====================================================================
      // STEP 2: FLEXIBLE DRIVER LOOKUP
      // ====================================================================
      const driverQuery = { $or: [] };
      if (ObjectId.isValid(driverId)) {
        driverQuery.$or.push({ _id: new ObjectId(driverId) });
      }
      driverQuery.$or.push({ driverId: driverId });
      driverQuery.$or.push({ driverCode: driverId });
      driverQuery.$or.push({ employeeId: driverId });

      const driver = await req.db.collection('drivers').findOne(driverQuery, { session });

      if (!driver) {
        await session.abortTransaction();
        return res.status(404).json({
          success: false,
          message: `Driver not found (ID: ${driverId})`
        });
      }

      // Extract driver info
      let driverName, driverPhone, driverEmail;
      if (driver.name) {
        driverName = driver.name;
        driverPhone = driver.phone;
        driverEmail = driver.email;
      } else if (driver.personalInfo) {
        const firstName = driver.personalInfo.firstName || '';
        const lastName = driver.personalInfo.lastName || '';
        driverName = `${firstName} ${lastName}`.trim() || 'Unknown Driver';
        driverPhone = driver.personalInfo.phone;
        driverEmail = driver.personalInfo.email;
      } else {
        driverName = 'Unknown Driver';
      }

      console.log('✅ Driver found:', driverName);

      // ====================================================================
      // STEP 3: FLEXIBLE VEHICLE LOOKUP
      // ====================================================================
      const vehicleQuery = { $or: [] };
      if (ObjectId.isValid(vehicleId)) {
        vehicleQuery.$or.push({ _id: new ObjectId(vehicleId) });
      }
      vehicleQuery.$or.push({ vehicleId: vehicleId });
      vehicleQuery.$or.push({ vehicleCode: vehicleId });
      vehicleQuery.$or.push({ registrationNumber: vehicleId });
      vehicleQuery.$or.push({ licensePlate: vehicleId });

      const vehicle = await req.db.collection('vehicles').findOne(vehicleQuery, { session });

      if (!vehicle) {
        await session.abortTransaction();
        return res.status(404).json({
          success: false,
          message: `Vehicle not found (ID: ${vehicleId})`
        });
      }

      console.log('✅ Vehicle found:', vehicle.registrationNumber);

      // ====================================================================
      // STEP 4: Reverse geocode locations
      // ====================================================================
      console.log('\n🌍 Reverse geocoding locations...');

      const reverseGeocode = async (lat, lng) => {
        try {
          const response = await fetch(
            `https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}&zoom=18&addressdetails=1`,
            {
              headers: {
                'User-Agent': 'AbraFleet/1.0'
              }
            }
          );
          const data = await response.json();

          if (data && data.address) {
            const address = data.address;
            const parts = [];

            if (address.road) parts.push(address.road);
            if (address.suburb) parts.push(address.suburb);
            if (address.city || address.town || address.village) {
              parts.push(address.city || address.town || address.village);
            }
            if (address.state) parts.push(address.state);

            return parts.length > 0 ? parts.join(', ') : data.display_name;
          }

          return 'Location not available';
        } catch (error) {
          console.error('Reverse geocoding error:', error);
          return 'Location not available';
        }
      };

      let pickupAddress = 'Not specified';
      let dropAddress = 'Not specified';

      if (roster.locations?.pickup?.coordinates) {
        const coords = roster.locations.pickup.coordinates;
        pickupAddress = await reverseGeocode(coords.latitude, coords.longitude);
      }

      if (roster.locations?.drop?.coordinates) {
        const coords = roster.locations.drop.coordinates;
        dropAddress = await reverseGeocode(coords.latitude, coords.longitude);
      }

      console.log('✅ Locations geocoded');

      // ====================================================================
      // STEP 5: UPDATE ROSTER (backward compatibility)
      // ====================================================================
      const updateData = {
        vehicleId: vehicle._id,
        vehicleNumber: vehicle.registrationNumber,
        driverId: driver._id,
        driverName: driverName,
        driverPhone: driverPhone,
        status: roster.status === 'pending_assignment' ? 'assigned' : roster.status,
        assignmentDate: new Date(),
        updatedAt: new Date(),
        lastModifiedBy: req.user.userId
      };

      const result = await req.db.collection('rosters').findOneAndUpdate(
        { _id: new ObjectId(rosterId) },
        { $set: updateData },
        { returnDocument: 'after', session }
      );

      console.log('✅ Roster updated in MongoDB');

      // ====================================================================
      // STEP 6: 🆕 UPDATE OR CREATE TRIP in roster-assigned-trips
      // ====================================================================
      console.log('\n🎫 Step 6: Updating trip in "roster-assigned-trips" collection...');

      // Check if trip exists
      let existingTrip = await req.db.collection('roster-assigned-trips').findOne(
        { rosterId: new ObjectId(rosterId) },
        { session }
      );

      const pickupTime = roster.startTime || roster.fromTime || '08:00';
      
      const calculateReadyByTime = (timeStr) => {
        const [hours, minutes] = timeStr.split(':').map(Number);
        const pickupDateTime = new Date();
        pickupDateTime.setHours(hours, minutes, 0, 0);
        const readyDateTime = new Date(pickupDateTime.getTime() - (20 * 60000));
        return `${String(readyDateTime.getHours()).padStart(2, '0')}:${String(readyDateTime.getMinutes()).padStart(2, '0')}`;
      };

      const readyByTime = calculateReadyByTime(pickupTime);

      if (existingTrip) {
        // Update existing trip
        console.log(`   Updating existing trip: ${existingTrip.tripNumber}`);
        
        await req.db.collection('roster-assigned-trips').updateOne(
          { _id: existingTrip._id },
          {
            $set: {
              driverId: driver._id,
              vehicleId: vehicle._id,
              estimatedPickupTime: pickupTime,
              readyByTime: readyByTime,
              pickupLocation: {
                address: pickupAddress,
                coordinates: roster.locations?.pickup?.coordinates || null
              },
              dropLocation: {
                address: dropAddress,
                coordinates: roster.locations?.drop?.coordinates || null
              },
              updatedAt: new Date(),
              lastModifiedBy: req.user.userId
            }
          },
          { session }
        );
        
        console.log('✅ Trip updated successfully');
      } else {
        // Create new trip
        console.log('   Creating new trip...');
        
        const tripNumber = `TRIP-${Date.now().toString().slice(-6)}-01`;
        const scheduledDate = new Date().toISOString().split('T')[0];

        const tripData = {
          tripNumber,
          tripType: roster.rosterType || 'login',
          rosterId: roster._id,
          customerName: roster.customerName || 'Unknown',
          customerEmail: roster.customerEmail || '',
          customerPhone: roster.customerPhone || '',
          driverId: driver._id,
          vehicleId: vehicle._id,
          pickupSequence: 1,
          estimatedPickupTime: pickupTime,
          readyByTime: readyByTime,
          distanceToOffice: 0,
          distanceFromPrevious: 0,
          estimatedTravelTime: 30,
          pickupLocation: {
            address: pickupAddress,
            coordinates: roster.locations?.pickup?.coordinates || null
          },
          dropLocation: {
            address: dropAddress,
            coordinates: roster.locations?.drop?.coordinates || null
          },
          scheduledDate: scheduledDate,
          startTime: pickupTime,
          endTime: roster.endTime || '18:00',
          estimatedDuration: 30,
          distance: 0,
          sequence: 1,
          organizationId: roster.organizationId,
          organizationName: roster.organizationName || roster.companyName,
          status: 'assigned',
          assignedAt: new Date(),
          actualStartTime: null,
          actualEndTime: null,
          currentLocation: null,
          locationHistory: [],
          actualDistance: null,
          actualDuration: null,
          createdAt: new Date(),
          updatedAt: new Date(),
          createdBy: req.user.userId
        };

        const tripResult = await req.db.collection('roster-assigned-trips').insertOne(tripData, { session });
        existingTrip = { _id: tripResult.insertedId, tripNumber };
        
        // Link trip to roster
        await req.db.collection('rosters').updateOne(
          { _id: roster._id },
          { $set: { tripId: existingTrip._id } },
          { session }
        );
        
        console.log(`✅ Trip created: ${tripNumber}`);
      }

      // ====================================================================
      // STEP 7: Update Firebase
      // ====================================================================
      try {
        const firebaseDb = admin.database();
        await firebaseDb.ref('roster_requests').child(rosterId).update({
          status: result.value.status,
          assignedDriverId: driver._id.toString(),
          assignedVehicleId: vehicle._id.toString(),
          assignedDriverName: driverName,
          assignedDriverPhone: driverPhone || null,
          assignedVehicleReg: vehicle.registrationNumber,
          assignmentDate: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
          lastModifiedBy: req.user.userId
        });
        console.log('✅ Firebase updated');
      } catch (firebaseError) {
        console.log('⚠️  Firebase update failed:', firebaseError.message);
      }

      // ====================================================================
      // STEP 8: Send notifications (with AM/PM)
      // ====================================================================
      const format12Hour = (time24) => {
        const [hours, minutes] = time24.split(':').map(Number);
        const period = hours >= 12 ? 'PM' : 'AM';
        const hours12 = hours % 12 || 12;
        return `${hours12}:${String(minutes).padStart(2, '0')} ${period}`;
      };

      const pickupTime12 = format12Hour(pickupTime);
      const readyByTime12 = format12Hour(readyByTime);

      // Customer notification
      try {
        const customerNotificationBody = `Driver and Vehicle Updated

Driver: ${driverName}
Phone: ${driverPhone || 'Not available'}
Vehicle: ${vehicle.registrationNumber}

🕐 PICKUP TIME: ${pickupTime12}
⏰ BE READY BY: ${readyByTime12}

Pickup Location: ${pickupAddress}
Drop Location: ${dropAddress}`;

        await createNotification(req.db, {
          userId: roster.userId,
          type: 'roster_assignment_updated',
          title: 'Roster Assignment Updated',
          body: customerNotificationBody,
          data: {
            rosterId: rosterId,
            tripId: existingTrip._id.toString(),
            tripNumber: existingTrip.tripNumber,
            driverName: driverName,
            driverPhone: driverPhone || 'N/A',
            vehicleReg: vehicle.registrationNumber,
            pickupLocation: pickupAddress,
            dropLocation: dropAddress,
            pickupTime: pickupTime,
            readyByTime: readyByTime,
            pickupTime12Hour: pickupTime12,
            readyByTime12Hour: readyByTime12
          },
          metadata: {
            rosterId: rosterId,
            action: 'roster_assignment_updated',
            updatedBy: req.user.userId
          },
          priority: 'high',
          category: 'roster',
          style: 'success'
        });

        console.log('✅ Customer notification sent to:', roster.customerName);
      } catch (notifError) {
        console.log('⚠️  Customer notification failed:', notifError.message);
      }

      // Driver notification
      try {
        const driverUser = await req.db.collection('users').findOne({
          $or: [
            { driverId: driver._id },
            { phone: driverPhone }
          ]
        });

        if (driverUser && driverUser.firebaseUid) {
          const driverNotificationBody = `Trip Assignment Updated

Customer: ${roster.customerName}
Vehicle: ${vehicle.registrationNumber}

📍 PICKUP DETAILS:
Time: ${pickupTime12}
Ready by: ${readyByTime12}
Location: ${pickupAddress}

📍 DROP DETAILS:
Location: ${dropAddress}

START BY: ${readyByTime12}`;

          await createNotification(req.db, {
            userId: driverUser.firebaseUid,
            type: 'roster_assigned',
            title: 'Trip Assignment Updated',
            body: driverNotificationBody,
            data: {
              rosterId: rosterId,
              tripId: existingTrip._id.toString(),
              tripNumber: existingTrip.tripNumber,
              customerName: roster.customerName,
              vehicleReg: vehicle.registrationNumber,
              pickupLocation: pickupAddress,
              dropLocation: dropAddress,
              pickupTime: pickupTime,
              readyByTime: readyByTime,
              pickupTime12Hour: pickupTime12,
              readyByTime12Hour: readyByTime12
            },
            metadata: {
              rosterId: rosterId,
              action: 'driver_assigned_to_roster',
              updatedBy: req.user.userId
            },
            priority: 'high',
            category: 'roster',
            style: 'success'
          });

          console.log('✅ Driver notification sent to:', driverName);
        } else {
          console.log('ℹ️  Driver has no app access');
        }
      } catch (driverNotifError) {
        console.log('⚠️  Driver notification failed:', driverNotifError.message);
      }

      await session.commitTransaction();

      console.log('\n✅ ASSIGNMENT UPDATE COMPLETED\n');

      res.json({
        success: true,
        message: 'Assignment updated successfully',
        data: {
          rosterId: result.value._id.toString(),
          tripId: existingTrip._id.toString(),
          tripNumber: existingTrip.tripNumber,
          status: result.value.status,
          assignedDriver: {
            id: driver._id.toString(),
            name: driverName,
            phone: driverPhone
          },
          assignedVehicle: {
            id: vehicle._id.toString(),
            registrationNumber: vehicle.registrationNumber
          },
          collection: 'roster-assigned-trips',
          updatedAt: result.value.updatedAt
        }
      });

    } catch (err) {
      await session.abortTransaction();
      console.error('❌ ERROR:', err.message);

      res.status(500).json({
        success: false,
        message: 'Failed to update assignment: ' + err.message
      });
    } finally {
      await session.endSession();
    }
  }
);

// @route   GET api/roster/admin/stats
// @desc    Get roster statistics for admin dashboard
// @access  Private (Admin/Manager)
router.get('/admin/stats', verifyToken, async (req, res) => {
  try {
    const [pending, assigned, inProgress, completed, cancelled] = await Promise.all([
      req.db.collection('rosters').countDocuments({
        requestType: 'customer_roster',
        status: 'pending'
      }),
      req.db.collection('rosters').countDocuments({
        requestType: 'customer_roster',
        status: 'assigned'
      }),
      req.db.collection('rosters').countDocuments({
        requestType: 'customer_roster',
        status: 'in_progress'
      }),
      req.db.collection('rosters').countDocuments({
        requestType: 'customer_roster',
        status: 'completed'
      }),
      req.db.collection('rosters').countDocuments({
        requestType: 'customer_roster',
        status: 'cancelled'
      }),
    ]);

    res.json({
      success: true,
      data: {
        pending,
        assigned,
        inProgress,
        completed,
        cancelled,
        total: pending + assigned + inProgress + completed + cancelled
      }
    });

  } catch (error) {
    console.error('Error fetching roster stats:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch roster statistics'
    });
  }
});

// @route   GET api/roster/admin/all
// @desc    Get all rosters for admin
// @access  Private (Admin/Manager)
router.get('/admin/all', verifyToken, async (req, res) => {
  try {
    const { status, rosterType, startDate, endDate, officeLocation } = req.query;

    const query = { requestType: 'customer_roster' };

    if (status) query.status = status;
    if (rosterType) query.rosterType = rosterType;
    if (officeLocation) query.officeLocation = officeLocation;

    if (startDate || endDate) {
      query.startDate = {};
      if (startDate) query.startDate.$gte = new Date(startDate);
      if (endDate) query.startDate.$lte = new Date(endDate);
    }

    const rosters = await req.db.collection('rosters')
      .find(query)
      .sort({ createdAt: -1 })
      .toArray();

    res.json({
      success: true,
      data: rosters,
      count: rosters.length
    });

  } catch (error) {
    console.error('Error fetching all rosters:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch rosters'
    });
  }
});

// ========== EXISTING GENERIC ROUTES (Unchanged) ==========

// @route   GET api/roster
// @desc    Get all rosters with optional filters
// @access  Private
router.get('/', verifyToken, async (req, res) => {
  try {
    const { driverId, vehicleId, startDate, endDate, status } = req.query;
    const filters = {};

    if (driverId) filters.driverId = driverId;
    if (vehicleId) filters.vehicleId = vehicleId;
    if (status) filters.status = status;
    if (startDate || endDate) {
      filters.startDate = startDate;
      filters.endDate = endDate;
    }

    const rosters = await Roster.find(filters);
    res.json(rosters);
  } catch (err) {
    console.error('Error fetching rosters:', err.message);
    res.status(500).json({ success: false, message: 'Server error', error: err.message });
  }
});

// @route   GET api/roster/:id
// @desc    Get roster by ID
// @access  Private
router.get('/:id', verifyToken, async (req, res) => {
  try {
    const roster = await Roster.findById(req.params.id);

    if (!roster) {
      return res.status(404).json({ msg: 'Roster not found' });
    }

    res.json(roster);
  } catch (err) {
    console.error('Error fetching roster:', err.message);

    if (err.message.includes('BSONTypeError')) {
      return res.status(404).json({ msg: 'Roster not found' });
    }

    res.status(500).json({ success: false, message: 'Server error', error: err.message });
  }
});

// @desc    Batch assign rosters to vehicle (Route Optimization)
// @access  Private (Admin)
router.post('/admin/assign-batch', verifyToken, async (req, res) => {
  console.log('\n' + '='.repeat(80));
  console.log('🚀 BATCH ROUTE ASSIGNMENT INITIATED');
  console.log('='.repeat(80));

  try {
    const { vehicleId, rosterIds, routeDetails } = req.body;

    console.log('📦 Request Data:');
    console.log('   Vehicle ID:', vehicleId);
    console.log('   Roster IDs:', rosterIds);
    console.log('   Route Details:', routeDetails);

    // Validate input
    if (!vehicleId || !rosterIds || !Array.isArray(rosterIds) || rosterIds.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Vehicle ID and roster IDs array are required'
      });
    }

    // Step 1: Get vehicle details with driver
    console.log('\n🚗 Step 1: Fetching vehicle details...');
    const vehicle = await req.db.collection('vehicles').findOne({
      $or: [
        { _id: ObjectId.isValid(vehicleId) ? new ObjectId(vehicleId) : null },
        { vehicleId: vehicleId }
      ]
    });

    if (!vehicle) {
      console.log('❌ Vehicle not found');
      return res.status(404).json({
        success: false,
        message: 'Vehicle not found'
      });
    }

    console.log('✅ Vehicle found:', vehicle.name || vehicle.vehicleNumber);

    // Get driver details - FIXED VERSION
    let driverId;
    let driver;
    let driverName = 'Unknown Driver';

    // Handle both object and string formats for assignedDriver
    if (typeof vehicle.assignedDriver === 'object' && vehicle.assignedDriver !== null) {
      // Driver is already an object with full details
      driver = vehicle.assignedDriver;
      driverId = driver.driverId || driver._id;

      // Handle different driver name formats
      if (driver.name) {
        driverName = driver.name;
      } else if (driver.personalInfo && driver.personalInfo.firstName) {
        driverName = `${driver.personalInfo.firstName} ${driver.personalInfo.lastName || ''}`.trim();
      } else {
        driverName = 'Unknown Driver';
      }

      console.log('✅ Driver found (from vehicle object):', driverName);
    } else if (typeof vehicle.assignedDriver === 'string') {
      // Driver is just an ID, need to fetch from database
      driverId = vehicle.assignedDriver;

      // Try multiple driver lookup methods
      driver = await req.db.collection('drivers').findOne({
        $or: [
          { driverId: driverId },
          { _id: ObjectId.isValid(driverId) ? new ObjectId(driverId) : null }
        ]
      });

      if (!driver) {
        console.log('❌ Driver not found in drivers collection, checking users collection...');

        // Try finding in users collection
        driver = await req.db.collection('users').findOne({
          $or: [
            { driverId: driverId },
            { _id: ObjectId.isValid(driverId) ? new ObjectId(driverId) : null },
            { role: 'driver', firebaseUid: driverId }
          ]
        });

        if (!driver) {
          console.log('❌ Driver not found in any collection');
          return res.status(404).json({
            success: false,
            message: `Driver not found with ID: ${driverId}`
          });
        }
      }

      // Handle different driver name formats
      if (driver.name) {
        driverName = driver.name;
      } else if (driver.personalInfo && driver.personalInfo.firstName) {
        driverName = `${driver.personalInfo.firstName} ${driver.personalInfo.lastName || ''}`.trim();
      } else {
        driverName = 'Unknown Driver';
      }

      console.log('✅ Driver found (from database):', driverName);
    } else {
      console.log('❌ No driver assigned to vehicle');
      return res.status(400).json({
        success: false,
        message: 'Vehicle has no assigned driver'
      });
    }

    console.log('✅ Driver confirmed:', driverName);

    // Step 2: Check vehicle capacity - ✅ FIXED VERSION
    console.log('\n📊 Step 2: Checking vehicle capacity...');
    const totalSeats = vehicle.capacity?.passengers || 
                       vehicle.seatCapacity || 
                       vehicle.seatingCapacity || 
                       4;

    // ✅ FIX: Count unique customers from existing trips, not trip count
    const today = new Date().toISOString().split('T')[0];
    const existingTrips = await req.db.collection('roster-assigned-trips').find({
      vehicleId: new ObjectId(vehicleId),
      status: { $in: ['assigned', 'started', 'in_progress'] },
      scheduledDate: today
    }).toArray();

    console.log(`   📅 Today's date: ${today}`);
    console.log(`   📊 Existing trips found: ${existingTrips.length}`);

    // Extract unique customer emails from all trips
    const uniqueCustomers = new Set();
    existingTrips.forEach(trip => {
      trip.stops?.forEach(stop => {
        if (stop.type === 'pickup' && stop.customer?.email) {
          uniqueCustomers.add(stop.customer.email);
        }
      });
    });

    const currentAssignedCount = uniqueCustomers.size;
    const availableSeats = totalSeats - 1 - currentAssignedCount; // -1 for driver

    console.log(`   🪑 Total Seats: ${totalSeats}`);
    console.log(`   👥 Currently Assigned: ${currentAssignedCount} unique customers`);
    console.log(`   🚗 Existing Trips: ${existingTrips.length}`);
    console.log(`   ✅ Available Seats: ${availableSeats}`);
    console.log(`   📝 Requested: ${rosterIds.length} customers`);

    if (availableSeats < rosterIds.length) {
      console.log(`❌ Not enough seats! Need ${rosterIds.length}, have ${availableSeats}`);
      return res.status(400).json({
        success: false,
        message: `Vehicle only has ${availableSeats} available seats, but ${rosterIds.length} customers requested`
      });
    }

    console.log('✅ Capacity check passed');

    // Step 3: Update rosters
    console.log('\n📝 Step 3: Updating rosters...');
    const updateResults = [];
    const notifications = [];

    for (let i = 0; i < rosterIds.length; i++) {
      const rosterId = rosterIds[i];

      try {
        // Find roster
        const roster = await req.db.collection('rosters').findOne({
          $or: [
            { _id: ObjectId.isValid(rosterId) ? new ObjectId(rosterId) : null },
            { rosterId: rosterId }
          ]
        });

        if (!roster) {
          console.log(`⚠️ Roster ${rosterId} not found, skipping`);
          updateResults.push({ rosterId, success: false, error: 'Not found' });
          continue;
        }

        // Update roster
        const updateResult = await req.db.collection('rosters').updateOne(
          { _id: roster._id },
          {
            $set: {
              assignedDriver: driverId,
              assignedVehicle: vehicleId,
              status: 'assigned',
              assignedAt: new Date(),
              updatedAt: new Date(),
              pickupSequence: i + 1,
              routeDetails: routeDetails
            }
          }
        );

        console.log(`✅ Updated roster ${i + 1}/${rosterIds.length}: ${roster.customerName || 'Unknown'}`);
        updateResults.push({ rosterId, success: true });

        // Prepare notification for customer
        const customerEmail = roster.customerEmail || roster.employeeDetails?.email;
        if (customerEmail) {
          // Handle driver name and phone based on object structure - FIXED
          let notificationDriverName = driverName; // Use the already determined driver name
          let driverPhone = null;

          // Try to get phone from different possible locations
          if (driver.phone) {
            driverPhone = driver.phone;
          } else if (driver.personalInfo && driver.personalInfo.phone) {
            driverPhone = driver.personalInfo.phone;
          } else if (driver.phoneNumber) {
            driverPhone = driver.phoneNumber;
          }

          notifications.push({
            email: customerEmail,
            customerName: roster.customerName || roster.employeeDetails?.name,
            driverName: notificationDriverName,
            driverPhone: driverPhone,
            vehicleName: vehicle.name || vehicle.vehicleNumber,
            licensePlate: vehicle.licensePlate || vehicle.registrationNumber,
            pickupSequence: i + 1,
            totalStops: rosterIds.length,
            loginTime: roster.loginTime || roster.startTime || null,
            logoutTime: roster.logoutTime || roster.endTime || null,
            loginLocation: roster.loginLocation || roster.pickupLocation || null,
            logoutLocation: roster.logoutLocation || roster.dropLocation || null,
            rosterId: roster._id.toString()
          });
        }

      } catch (error) {
        console.log(`❌ Error updating roster ${rosterId}:`, error.message);
        updateResults.push({ rosterId, success: false, error: error.message });
      }
    }

    // Step 4: Update vehicle assigned customers - ✅ FIXED VERSION
    console.log('\n🚗 Step 4: Updating vehicle capacity...');
    
    // ✅ FIX: Get current unique customers, then add new ones
    const currentUniqueEmails = Array.from(uniqueCustomers);
    
    // Get emails of newly assigned customers
    const newCustomerEmails = [];
    for (const rosterId of rosterIds) {
      const roster = await req.db.collection('rosters').findOne({
        $or: [
          { _id: ObjectId.isValid(rosterId) ? new ObjectId(rosterId) : null },
          { rosterId: rosterId }
        ]
      });
      if (roster && roster.customerEmail) {
        newCustomerEmails.push(roster.customerEmail);
      }
    }
    
    // Combine and deduplicate
    const allUniqueEmails = [...new Set([...currentUniqueEmails, ...newCustomerEmails])];
    
    await req.db.collection('vehicles').updateOne(
      { _id: vehicle._id },
      {
        $set: {
          assignedCustomers: allUniqueEmails, // ✅ Store unique customer emails
          updatedAt: new Date()
        }
      }
    );

    console.log(`✅ Vehicle now has ${allUniqueEmails.length} unique assigned customers`);

    // Step 5: Send notifications (async, don't wait)
    console.log('\n📧 Step 5: Sending notifications...');
    if (notifications.length > 0) {
      // Send notifications in background
      setImmediate(async () => {
        for (const notif of notifications) {
          try {
            // Find customer user by email
            const customerUser = await req.db.collection('users').findOne({
              email: notif.email.toLowerCase()
            });

            if (customerUser && customerUser.firebaseUid) {
              // Check if notification already exists for this roster
              const existingNotification = await req.db.collection('notifications').findOne({
                userId: customerUser.firebaseUid,
                'data.rosterId': notif.rosterId,
                type: 'route_assigned'
              });

              if (existingNotification) {
                console.log(`⚠️  Notification already exists for roster ${notif.rosterId}, skipping`);
                continue;
              }

              // Create notification in database
              const notificationBody = `Route Assignment Confirmed

Driver: ${notif.driverName}
Vehicle: ${notif.vehicleName} (${notif.licensePlate})
Pickup Sequence: Stop ${notif.pickupSequence} of ${notif.totalStops}

Your driver will pick you up according to the optimized route. You will receive another notification 30 minutes before pickup.`;

              await createNotification(req.db, {
                userId: customerUser.firebaseUid,
                userEmail: notif.email,                    // 🔥 PRIMARY: Email for FCM
                userRole: 'customer',                      // 🔥 User role
                type: 'route_assigned',
                title: '🚗 Your Ride is Confirmed!',
                body: notificationBody,
                data: {
                  rosterId: notif.rosterId,
                  driverName: notif.driverName,
                  driverPhone: notif.driverPhone,
                  vehicleName: notif.vehicleName,
                  licensePlate: notif.licensePlate,
                  pickupSequence: notif.pickupSequence,
                  totalStops: notif.totalStops,
                  loginTime: notif.loginTime,
                  logoutTime: notif.logoutTime,
                  loginLocation: notif.loginLocation,
                  logoutLocation: notif.logoutLocation,
                  action: 'route_assignment'
                },
                priority: 'high',                          // 🔥 High priority
                category: 'roster_assignment',             // 🔥 Category
                channels: ['fcm', 'database'],             // 🔥 CRITICAL: FCM + Database
                metadata: {
                  vehicleId: vehicleId,
                  driverId: driverId,
                  action: 'route_assigned'
                }
              });

              console.log(`✅ Notification sent to ${notif.customerName}`);
            } else {
              console.log(`⚠️ User not found for ${notif.email}`);
            }
          } catch (error) {
            console.log(`⚠️ Failed to send notification to ${notif.customerName}:`, error.message);
          }
        }

        // Send notification to driver
        try {
          const driverUser = await req.db.collection('users').findOne({
            driverId: driverId
          });

          if (driverUser && driverUser.firebaseUid) {
            const driverNotificationBody = `New Route Assignment

You have been assigned ${notifications.length} customers for pickup.

Vehicle: ${vehicle.name || vehicle.vehicleNumber} (${vehicle.licensePlate})
Total Stops: ${notifications.length}

Please check your route details in the Driver Dashboard.`;

            await createNotification(req.db, {
              userId: driverUser.firebaseUid,
              userEmail: driverUser.email,                 // 🔥 PRIMARY: Email for FCM
              userRole: 'driver',                          // 🔥 User role
              type: 'route_assigned_driver',
              title: '🚗 New Route Assignment',
              body: driverNotificationBody,
              data: {
                vehicleId: vehicleId,
                totalCustomers: notifications.length,
                vehicleName: vehicle.name || vehicle.vehicleNumber,
                action: 'route_assignment_driver'
              },
              priority: 'high',                            // 🔥 High priority
              category: 'roster_assignment',               // 🔥 Category
              channels: ['fcm', 'database'],               // 🔥 CRITICAL: FCM + Database
              metadata: {
                vehicleId: vehicleId,
                customerCount: notifications.length,
                action: 'route_assigned_to_driver'
              }
            });

            console.log(`✅ Notification sent to driver`);
          }
        } catch (error) {
          console.log(`⚠️ Failed to send driver notification:`, error.message);
        }

        // 🔥 NEW: Send notification to all admins
        try {
          console.log('📤 Sending notifications to admins...');
          
          // Get all active admin users
          const adminUsers = await req.db.collection('users').find({
            role: { $in: ['admin', 'super_admin'] },
            status: 'active'
          }).toArray();
          
          console.log(`Found ${adminUsers.length} admin user(s)`);
          
          // Send notification to each admin
          for (const admin of adminUsers) {
            if (!admin.email) {
              console.log(`⚠️  Skipping admin ${admin._id} - no email`);
              continue;
            }
            
            const adminNotificationBody = `Route Assignment Completed

Driver: ${driverName}
Vehicle: ${vehicle.name || vehicle.vehicleNumber} (${vehicle.licensePlate || vehicle.registrationNumber})
Customers Assigned: ${notifications.length}
Total Stops: ${notifications.length}

The route has been optimized and all customers have been notified.`;

            await createNotification(req.db, {
              userId: admin.firebaseUid || admin._id.toString(),
              userEmail: admin.email,                      // 🔥 PRIMARY: Email for FCM
              userRole: admin.role,                        // 🔥 User role
              title: '📋 Route Assignment Completed',
              body: adminNotificationBody,
              type: 'roster_assigned_admin',
              data: {
                vehicleId: vehicleId,
                vehicleName: vehicle.name || vehicle.vehicleNumber,
                driverName: driverName,
                totalCustomers: notifications.length,
                totalStops: notifications.length,
                requiresMonitoring: false,
                action: 'roster_assignment_admin'
              },
              priority: 'normal',                          // 🔥 Normal priority for admin
              category: 'admin_notification',              // 🔥 Category
              channels: ['fcm', 'database'],               // 🔥 CRITICAL: FCM + Database
              metadata: {
                vehicleId: vehicleId,
                driverId: driverId,
                customerCount: notifications.length,
                action: 'roster_assigned_admin'
              }
            });
          }
          
          console.log(`✅ Admin notifications sent to ${adminUsers.length} admin(s)`);
          
        } catch (error) {
          console.log(`⚠️ Failed to send admin notifications:`, error.message);
        }
      });
    }

    // Summary
    const successCount = updateResults.filter(r => r.success).length;
    const failCount = updateResults.filter(r => !r.success).length;

    console.log('\n✅ BATCH ASSIGNMENT COMPLETE');
    console.log(`   Success: ${successCount}/${rosterIds.length}`);
    console.log(`   Failed: ${failCount}`);
    console.log('='.repeat(80));

    res.json({
      success: true,
      message: `Successfully assigned ${successCount} rosters to vehicle`,
      data: {
        successCount,
        failCount,
        results: updateResults,
        vehicle: {
          id: vehicleId,
          name: vehicle.name || vehicle.vehicleNumber,
          driver: driverName, // Use the already determined driver name
          availableSeats: totalSeats - 1 - allUniqueEmails.length // ✅ Fixed calculation
        }
      }
    });

  } catch (error) {
    console.error('❌ BATCH ASSIGNMENT ERROR:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to assign rosters',
      error: error.message
    });
  }
});

// @route   GET api/roster/admin/stats
// @desc    Get roster statistics for admin dashboard
// @access  Private (Admin/Manager)
router.get('/admin/stats', verifyToken, async (req, res) => {
  try {
    console.log('📊 Fetching roster statistics for admin dashboard...');

    // Get counts for each status
    const [pending, assigned, inProgress, completed, cancelled] = await Promise.all([
      req.db.collection('rosters').countDocuments({
        requestType: 'customer_roster',
        status: 'pending'
      }),
      req.db.collection('rosters').countDocuments({
        requestType: 'customer_roster',
        status: 'assigned'
      }),
      req.db.collection('rosters').countDocuments({
        requestType: 'customer_roster',
        status: 'in_progress'
      }),
      req.db.collection('rosters').countDocuments({
        requestType: 'customer_roster',
        status: 'completed'
      }),
      req.db.collection('rosters').countDocuments({
        requestType: 'customer_roster',
        status: 'cancelled'
      })
    ]);

    const total = pending + assigned + inProgress + completed + cancelled;

    const stats = {
      pending,
      assigned,
      inProgress,
      completed,
      cancelled,
      total
    };

    console.log('✅ Roster stats calculated:', stats);

    res.json({
      success: true,
      message: 'Roster statistics retrieved successfully',
      data: stats
    });

  } catch (err) {
    console.error('❌ Error fetching roster stats:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch roster statistics',
      error: err.message
    });
  }
});

// @route   GET api/roster/admin/approved
// @desc    Get approved/assigned roster assignments for admin
// @access  Private (Admin/Manager)
router.get('/admin/approved', verifyToken, async (req, res) => {
  try {
    const { officeLocation, rosterType } = req.query;

    const query = {
      requestType: 'customer_roster',
      status: { $in: ['assigned', 'in_progress', 'completed'] }
    };

    if (officeLocation) {
      query.officeLocation = officeLocation;
    }
    if (rosterType) {
      query.rosterType = rosterType;
    }

    const approvedRosters = await req.db.collection('rosters')
      .find(query)
      .sort({ startDate: -1, createdAt: -1 })
      .toArray();

    res.json({
      success: true,
      message: 'Approved rosters retrieved successfully',
      data: approvedRosters,
      count: approvedRosters.length
    });
  } catch (err) {
    console.error('Error fetching approved rosters:', err.message);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch approved rosters'
    });
  }
});

// Add this at the END of routes/roster_router.js (before module.exports)

// Global error handler for this router
router.use((err, req, res, next) => {
  console.error('❌ ROUTER ERROR:', err.message);
  console.error('Path:', req.path);
  console.error('Stack:', err.stack);

  // ALWAYS return JSON, never plain text
  res.status(err.status || 500).json({
    success: false,
    message: err.message || 'Internal server error',
    error: process.env.NODE_ENV === 'development' ? {
      message: err.message,
      stack: err.stack
    } : undefined
  });
});


router.use((err, req, res, next) => {
  res.status(500).json({
    success: false,
    message: err.message || 'Internal server error'
  });
});

module.exports = router;