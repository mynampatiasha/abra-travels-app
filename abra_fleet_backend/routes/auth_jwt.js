// routes/auth_jwt.js - JWT-BASED AUTHENTICATION ROUTES
// ============================================================================
// REPLACES FIREBASE AUTH WITH CUSTOM JWT SYSTEM
// ============================================================================
const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { generateToken, hashPassword, comparePassword } = require('../middleware/jwt_auth');

/**
 * POST /api/auth/login - User Login
 * Supports all user types: admin, driver, customer, client, employee
 */
router.post('/login', async (req, res) => {
  console.log('\n🔐 JWT LOGIN REQUEST');
  console.log('─'.repeat(80));
  
  try {
    const { email, password } = req.body;
    
    if (!email || !password) {
      console.log('❌ Missing email or password');
      return res.status(400).json({
        success: false,
        error: 'Missing credentials',
        message: 'Email and password are required'
      });
    }
    
    console.log('   Email:', email);
    console.log('   Searching for user in all collections...');
    
    // Search for user in all collections
    const collections = [
      { name: 'admin_users', role: 'admin' },
      { name: 'drivers', role: 'driver' },
      { name: 'customers', role: 'customer' },
      { name: 'clients', role: 'client' },
      { name: 'employee_admins', role: 'employee' }
    ];
    
    let user = null;
    let userCollection = null;
    let userRole = null;
    
    for (const collection of collections) {
      user = await req.db.collection(collection.name).findOne({ 
        email: email.toLowerCase() 
      });
      
      if (user) {
        userCollection = collection.name;
        userRole = user.role || collection.role;
        console.log(`   ✅ User found in ${collection.name}`);
        break;
      }
    }
    
    if (!user) {
      console.log('❌ User not found in any collection');
      return res.status(401).json({
        success: false,
        error: 'Invalid credentials',
        message: 'Email or password is incorrect'
      });
    }
    
    // Check if user is active
    const isActive = user.isActive !== false && 
                     (!user.status || user.status === 'active');
    
    if (!isActive) {
      console.log('❌ User account is inactive');
      return res.status(403).json({
        success: false,
        error: 'Account inactive',
        message: 'Your account is currently inactive. Please contact administrator.'
      });
    }
    
    // Verify password
    console.log('   Verifying password...');
    
    // Handle users without hashed passwords (migration case)
    let passwordValid = false;
    
    if (user.password && user.password.startsWith('$2')) {
      // Already hashed password
      passwordValid = await comparePassword(password, user.password);
    } else if (user.password === password) {
      // Plain text password - hash it during login
      console.log('   Upgrading plain text password to hashed...');
      const hashedPassword = await hashPassword(password);
      
      await req.db.collection(userCollection).updateOne(
        { _id: user._id },
        { $set: { password: hashedPassword } }
      );
      
      passwordValid = true;
    } else {
      passwordValid = false;
    }
    
    if (!passwordValid) {
      console.log('❌ Invalid password');
      return res.status(401).json({
        success: false,
        error: 'Invalid credentials',
        message: 'Email or password is incorrect'
      });
    }
    
    console.log('✅ Password verified');
    
    // Prepare user data for token
    const userData = {
      _id: user._id,
      email: user.email,
      name: user.name,
      role: userRole,
      organizationId: user.organizationId,
      modules: user.modules || [],
      permissions: user.permissions || {},
      collectionName: userCollection
    };
    
    // Generate JWT token
    const token = generateToken(userData);
    
    // Update last login timestamp
    await req.db.collection(userCollection).updateOne(
      { _id: user._id },
      { 
        $set: { 
          lastLogin: new Date(),
          lastActive: new Date()
        } 
      }
    );
    
    console.log('✅ Login successful');
    console.log('   User ID:', user._id);
    console.log('   Role:', userRole);
    console.log('   Collection:', userCollection);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Login successful',
      data: {
        token,
        user: {
          id: user._id,
          email: user.email,
          name: user.name,
          role: userRole,
          organizationId: user.organizationId,
          modules: user.modules || [],
          permissions: user.permissions || {},
          collectionName: userCollection
        }
      }
    });
    
  } catch (error) {
    console.error('❌ LOGIN ERROR:', error.message);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Login failed',
      message: 'An error occurred during login',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

/**
 * POST /api/auth/register - User Registration
 * Creates user in appropriate collection based on role
 */
router.post('/register', async (req, res) => {
  console.log('\n📝 JWT REGISTRATION REQUEST');
  console.log('─'.repeat(80));
  
  try {
    const { email, password, name, role = 'customer', organizationId } = req.body;
    
    if (!email || !password || !name) {
      console.log('❌ Missing required fields');
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'Email, password, and name are required'
      });
    }
    
    console.log('   Email:', email);
    console.log('   Name:', name);
    console.log('   Role:', role);
    
    // Determine target collection based on role
    let targetCollection;
    switch (role) {
      case 'admin':
      case 'super_admin':
        targetCollection = 'admin_users';
        break;
      case 'driver':
        targetCollection = 'drivers';
        break;
      case 'customer':
        targetCollection = 'customers';
        break;
      case 'client':
        targetCollection = 'clients';
        break;
      case 'employee':
        targetCollection = 'employee_admins';
        break;
      default:
        targetCollection = 'customers';
    }
    
    console.log('   Target collection:', targetCollection);
    
    // Check if user already exists in any collection
    const collections = ['admin_users', 'drivers', 'customers', 'clients', 'employee_admins'];
    
    for (const collectionName of collections) {
      const existingUser = await req.db.collection(collectionName).findOne({ 
        email: email.toLowerCase() 
      });
      
      if (existingUser) {
        console.log('❌ User already exists in:', collectionName);
        return res.status(409).json({
          success: false,
          error: 'User already exists',
          message: 'An account with this email already exists'
        });
      }
    }
    
    // Hash password
    console.log('   Hashing password...');
    const hashedPassword = await hashPassword(password);
    
    // Create user document
    const newUser = {
      email: email.toLowerCase(),
      password: hashedPassword,
      name,
      role,
      organizationId: organizationId || null,
      modules: [],
      permissions: {},
      status: 'active',
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date(),
      lastLogin: null,
      lastActive: new Date()
    };
    
    // Insert user into appropriate collection
    console.log('   Creating user in collection:', targetCollection);
    const result = await req.db.collection(targetCollection).insertOne(newUser);
    
    // Prepare user data for token
    const userData = {
      _id: result.insertedId,
      email: newUser.email,
      name: newUser.name,
      role: newUser.role,
      organizationId: newUser.organizationId,
      modules: newUser.modules,
      permissions: newUser.permissions,
      collectionName: targetCollection
    };
    
    // Generate JWT token
    const token = generateToken(userData);
    
    console.log('✅ Registration successful');
    console.log('   User ID:', result.insertedId);
    console.log('   Role:', role);
    console.log('   Collection:', targetCollection);
    console.log('─'.repeat(80) + '\n');
    
    res.status(201).json({
      success: true,
      message: 'Registration successful',
      data: {
        token,
        user: {
          id: result.insertedId,
          email: newUser.email,
          name: newUser.name,
          role: newUser.role,
          organizationId: newUser.organizationId,
          modules: newUser.modules,
          permissions: newUser.permissions,
          collectionName: targetCollection
        }
      }
    });
    
  } catch (error) {
    console.error('❌ REGISTRATION ERROR:', error.message);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Registration failed',
      message: 'An error occurred during registration',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

/**
 * POST /api/auth/change-password - Change Password
 */
router.post('/change-password', async (req, res) => {
  console.log('\n🔑 CHANGE PASSWORD REQUEST');
  console.log('─'.repeat(80));
  
  try {
    const { currentPassword, newPassword } = req.body;
    const userEmail = req.user?.email;
    
    if (!currentPassword || !newPassword) {
      return res.status(400).json({
        success: false,
        error: 'Missing passwords',
        message: 'Current password and new password are required'
      });
    }
    
    if (!userEmail) {
      return res.status(401).json({
        success: false,
        error: 'Unauthorized',
        message: 'User not authenticated'
      });
    }
    
    console.log('   User email:', userEmail);
    
    // Find user in appropriate collection
    const collections = ['admin_users', 'drivers', 'customers', 'clients', 'employee_admins'];
    let user = null;
    let userCollection = null;
    
    for (const collectionName of collections) {
      user = await req.db.collection(collectionName).findOne({ 
        email: userEmail.toLowerCase() 
      });
      
      if (user) {
        userCollection = collectionName;
        break;
      }
    }
    
    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'User not found',
        message: 'User account not found'
      });
    }
    
    // Verify current password
    const currentPasswordValid = await comparePassword(currentPassword, user.password);
    
    if (!currentPasswordValid) {
      console.log('❌ Current password invalid');
      return res.status(401).json({
        success: false,
        error: 'Invalid current password',
        message: 'Current password is incorrect'
      });
    }
    
    // Hash new password
    const hashedNewPassword = await hashPassword(newPassword);
    
    // Update password
    await req.db.collection(userCollection).updateOne(
      { _id: user._id },
      { 
        $set: { 
          password: hashedNewPassword,
          updatedAt: new Date()
        } 
      }
    );
    
    console.log('✅ Password changed successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Password changed successfully'
    });
    
  } catch (error) {
    console.error('❌ CHANGE PASSWORD ERROR:', error.message);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Password change failed',
      message: 'An error occurred while changing password',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

/**
 * GET /api/auth/me - Get Current User Info
 */
router.get('/me', async (req, res) => {
  try {
    if (!req.user) {
      return res.status(401).json({
        success: false,
        error: 'Unauthorized',
        message: 'User not authenticated'
      });
    }
    
    res.json({
      success: true,
      data: {
        user: req.user
      }
    });
    
  } catch (error) {
    res.status(500).json({
      success: false,
      error: 'Failed to get user info',
      message: error.message
    });
  }
});

/**
 * POST /api/auth/logout - Logout (client-side token removal)
 */
router.post('/logout', (req, res) => {
  res.json({
    success: true,
    message: 'Logout successful. Please remove token from client storage.'
  });
});

module.exports = router;