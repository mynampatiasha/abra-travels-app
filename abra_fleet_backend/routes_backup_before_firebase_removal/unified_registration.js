// routes/unified_registration.js - UNIFIED REGISTRATION API (Clients & Customers)
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

// Middleware to attach database
router.use((req, res, next) => {
  if (!req.db) {
    return res.status(500).json({ msg: 'Database connection not available' });
  }
  next();
});

/**
 * POST /api/auth/register - Unified registration for clients and customers
 * Automatically routes to correct collection based on role
 */
router.post('/register', async (req, res) => {
  try {
    console.log('\n🔐 UNIFIED REGISTRATION STARTED');
    console.log('─'.repeat(80));
    console.log('📥 Request body:', JSON.stringify(req.body, null, 2));
    
    const {
      name,
      email,
      password,
      phone,
      role, // 'client' or 'customer'
      companyName,
      organizationName,
      department,
      branch,
      employeeId,
      status = 'active'
    } = req.body;

    // Validate required fields
    if (!name || !email || !password || !role) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'Name, email, password, and role are required'
      });
    }

    // Validate role
    if (!['client', 'customer'].includes(role.toLowerCase())) {
      return res.status(400).json({
        success: false,
        error: 'Invalid role',
        message: 'Role must be either "client" or "customer"'
      });
    }

    const userRole = role.toLowerCase();
    const collectionName = userRole === 'client' ? 'clients' : 'customers';
    
    console.log(`👤 Registering as: ${userRole}`);
    console.log(`📂 Target collection: ${collectionName}`);

    // Check if user already exists in the appropriate collection
    const existingUser = await req.db.collection(collectionName).findOne({
      $or: [
        { email: email.toLowerCase() },
        ...(employeeId ? [{ employeeId }] : [])
      ]
    });

    if (existingUser) {
      return res.status(409).json({
        success: false,
        error: 'User already exists',
        message: `A ${userRole} with this email${employeeId ? ' or employee ID' : ''} already exists`
      });
    }

    let firebaseUid = null;

    // 🔥 CREATE FIREBASE AUTH USER
    console.log('🔐 Creating Firebase Auth user for:', email);
    try {
      const firebaseUser = await admin.auth().createUser({
        email: email.toLowerCase(),
        password,
        displayName: name,
        emailVerified: false,
        disabled: false
      });
      
      firebaseUid = firebaseUser.uid;
      console.log('✅ Firebase user created successfully');
      console.log('   - Firebase UID:', firebaseUid);
      
      // Set custom claims based on role
      await admin.auth().setCustomUserClaims(firebaseUid, {
        role: userRole
      });
      console.log(`✅ Custom claims set: role=${userRole}`);
      
    } catch (firebaseError) {
      console.error('❌ Firebase user creation failed:', firebaseError.message);
      return res.status(400).json({
        success: false,
        error: 'Failed to create Firebase user',
        message: firebaseError.message
      });
    }

    // 💾 CREATE USER RECORD IN APPROPRIATE COLLECTION
    console.log(`💾 Creating ${userRole} in ${collectionName} collection...`);
    
    let newUser;
    
    if (userRole === 'client') {
      // Create client record
      newUser = {
        clientId: `CLIENT${Date.now()}`,
        name: name.trim(),
        email: email.toLowerCase().trim(),
        phone: phone?.trim() || '',
        companyName: companyName?.trim() || organizationName?.trim() || '',
        organizationName: organizationName?.trim() || companyName?.trim() || '',
        status: status.toLowerCase(),
        role: 'client',
        firebaseUid,
        totalCustomers: 0,
        createdAt: new Date(),
        updatedAt: new Date(),
        registrationMethod: 'self-registration'
      };
    } else {
      // Create customer record
      newUser = {
        customerId: employeeId || `CUST${Date.now()}`,
        name: name.trim(),
        email: email.toLowerCase().trim(),
        phone: phone?.trim() || '',
        companyName: companyName?.trim() || '',
        department: department?.trim() || '',
        branch: branch?.trim() || '',
        employeeId: employeeId?.trim() || '',
        status: status.toLowerCase(),
        role: 'customer',
        firebaseUid,
        createdAt: new Date(),
        updatedAt: new Date(),
        registrationMethod: 'self-registration'
      };
    }

    const result = await req.db.collection(collectionName).insertOne(newUser);
    console.log(`✅ ${userRole} created in MongoDB:`, result.insertedId);

    // Update Firebase custom claims with user ID
    if (firebaseUid) {
      const customClaims = {
        role: userRole,
        [userRole === 'client' ? 'clientId' : 'customerId']: result.insertedId.toString()
      };
      
      await admin.auth().setCustomUserClaims(firebaseUid, customClaims);
      console.log('✅ Custom claims updated with user ID');
    }

    // 🔄 SYNC TO FIRESTORE FOR COMPATIBILITY
    if (firebaseUid) {
      try {
        const firestoreData = {
          name,
          email: email.toLowerCase(),
          phone: phone || '',
          role: userRole,
          status: status.toLowerCase(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        };

        if (userRole === 'client') {
          firestoreData.companyName = companyName || organizationName || '';
          firestoreData.organizationName = organizationName || companyName || '';
          firestoreData.clientId = result.insertedId.toString();
        } else {
          firestoreData.companyName = companyName || '';
          firestoreData.department = department || '';
          firestoreData.branch = branch || '';
          firestoreData.employeeId = employeeId || '';
          firestoreData.customerId = result.insertedId.toString();
        }

        await admin.firestore().collection('users').doc(firebaseUid).set(firestoreData);
        console.log('✅ User synced to Firestore');
      } catch (firestoreError) {
        console.warn('⚠️ Firestore sync failed:', firestoreError.message);
      }
    }

    // Additional sync for clients to Firebase Realtime Database (compatibility)
    if (userRole === 'client' && firebaseUid) {
      try {
        const clientRef = admin.database().ref('clients').push();
        await clientRef.set({
          email: email.toLowerCase(),
          name: name,
          organizationName: organizationName || companyName || '',
          companyName: companyName || organizationName || '',
          phoneNumber: phone || '',
          totalCustomers: 0,
          createdAt: new Date().toISOString()
        });
        console.log('✅ Client also synced to Firebase Realtime Database');
      } catch (realtimeDbError) {
        console.warn('⚠️ Realtime DB sync failed:', realtimeDbError.message);
      }
    }

    console.log(`✅ ${userRole} registration completed successfully`);

    res.status(201).json({
      success: true,
      message: `${userRole.charAt(0).toUpperCase() + userRole.slice(1)} registered successfully`,
      data: {
        id: result.insertedId.toString(),
        [userRole === 'client' ? 'clientId' : 'customerId']: newUser[userRole === 'client' ? 'clientId' : 'customerId'],
        firebaseUid,
        role: userRole,
        ...newUser
      }
    });

  } catch (error) {
    console.error('❌ Error during registration:', error);
    res.status(500).json({
      success: false,
      error: 'Registration failed',
      message: error.message
    });
  }
});

/**
 * POST /api/auth/register/client - Specific client registration endpoint
 */
router.post('/register/client', async (req, res) => {
  req.body.role = 'client';
  return router.handle({ ...req, url: '/register', method: 'POST' }, res);
});

/**
 * POST /api/auth/register/customer - Specific customer registration endpoint
 */
router.post('/register/customer', async (req, res) => {
  req.body.role = 'customer';
  return router.handle({ ...req, url: '/register', method: 'POST' }, res);
});

module.exports = router;