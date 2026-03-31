// routes/unified_registration.js - UNIFIED REGISTRATION API (Clients & Customers)
// ✅ FIXED VERSION - Firebase removed, using JWT authentication
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const bcrypt = require('bcryptjs');

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

    // 🔐 HASH PASSWORD (JWT Authentication)
    console.log('🔐 Hashing password...');
    const hashedPassword = await bcrypt.hash(password, 10);
    console.log('✅ Password hashed successfully');

    // 💾 CREATE USER RECORD IN APPROPRIATE COLLECTION
    console.log(`💾 Creating ${userRole} in ${collectionName} collection...`);
    
    let newUser;
    
    if (userRole === 'client') {
      // Create client record
      newUser = {
        clientId: `CLIENT${Date.now()}`,
        name: name.trim(),
        email: email.toLowerCase().trim(),
        password: hashedPassword, // ✅ Store hashed password
        phone: phone?.trim() || '',
        companyName: companyName?.trim() || organizationName?.trim() || '',
        organizationName: organizationName?.trim() || companyName?.trim() || '',
        status: status.toLowerCase(),
        role: 'client', // ✅ Store role directly (not in customClaims)
        totalCustomers: 0,
        isActive: true,
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
        password: hashedPassword, // ✅ Store hashed password
        phone: phone?.trim() || '',
        companyName: companyName?.trim() || '',
        department: department?.trim() || '',
        branch: branch?.trim() || '',
        employeeId: employeeId?.trim() || '',
        status: status.toLowerCase(),
        role: 'customer', // ✅ Store role directly (not in customClaims)
        isActive: true,
        createdAt: new Date(),
        updatedAt: new Date(),
        registrationMethod: 'self-registration'
      };
    }

    const result = await req.db.collection(collectionName).insertOne(newUser);
    console.log(`✅ ${userRole} created in MongoDB:`, result.insertedId);

    // ✅ ALSO CREATE IN USERS COLLECTION FOR UNIFIED LOGIN
    console.log('💾 Creating user in unified users collection...');
    const unifiedUser = {
      email: email.toLowerCase().trim(),
      password: hashedPassword,
      name: name.trim(),
      phone: phone?.trim() || '',
      role: userRole, // ✅ Role stored directly
      status: status.toLowerCase(),
      isActive: true,
      [`${userRole}Id`]: result.insertedId.toString(), // Reference to client/customer
      createdAt: new Date(),
      updatedAt: new Date()
    };

    try {
      await req.db.collection('users').insertOne(unifiedUser);
      console.log('✅ User created in unified users collection');
    } catch (userError) {
      // If user already exists in users collection, update it
      console.log('⚠️ User exists in users collection, updating...');
      await req.db.collection('users').updateOne(
        { email: email.toLowerCase().trim() },
        { 
          $set: {
            [`${userRole}Id`]: result.insertedId.toString(),
            role: userRole,
            updatedAt: new Date()
          }
        }
      );
      console.log('✅ User updated in users collection');
    }

    console.log(`✅ ${userRole} registration completed successfully`);
    console.log('─'.repeat(80) + '\n');

    // Return response without password
    const { password: _, ...userWithoutPassword } = newUser;

    res.status(201).json({
      success: true,
      message: `${userRole.charAt(0).toUpperCase() + userRole.slice(1)} registered successfully`,
      data: {
        id: result.insertedId.toString(),
        [userRole === 'client' ? 'clientId' : 'customerId']: newUser[userRole === 'client' ? 'clientId' : 'customerId'],
        role: userRole,
        ...userWithoutPassword
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