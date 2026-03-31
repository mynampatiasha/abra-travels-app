// routes/jwt_router.js - COMPLETE JWT AUTHENTICATION SYSTEM
// ============================================================================
// ALL JWT FUNCTIONALITY IN ONE FILE - REPLACES FIREBASE COMPLETELY
// ============================================================================
const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const { ObjectId } = require('mongodb');

// ============================================================================
// JWT CONFIGURATION
// ============================================================================
const JWT_SECRET = process.env.JWT_SECRET || 'abra_fleet_super_secret_key_2024';
const JWT_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '24h';

// ============================================================================
// JWT UTILITY FUNCTIONS
// ============================================================================

/**
 * Generate JWT token for user
 */
const generateToken = (user) => {
  const payload = {
    userId: user._id.toString(),
    email: user.email,
    role: user.role,
    name: user.name,
    organizationId: user.organizationId,
    modules: user.modules || [],
    permissions: user.permissions || {},
    collectionName: user.collectionName
  };

  // Add role-specific IDs to token payload
  if (user.role === 'driver' && user.driverId) {
    payload.driverId = user.driverId;
  } else if (user.role === 'customer' && user.customerId) {
    payload.customerId = user.customerId;
  } else if (user.role === 'client' && user.clientId) {
    payload.clientId = user.clientId;
  } else if (user.role === 'employee' && user.employeeId) {
    payload.employeeId = user.employeeId;
  }

  return jwt.sign(payload, JWT_SECRET, { 
    expiresIn: JWT_EXPIRES_IN,
    issuer: 'abra_fleet_system',
    algorithm: 'HS256'  // ✅ ADD THIS LINE
  });
};

/**
 * Hash password using bcrypt
 */
const hashPassword = async (password) => {
  const saltRounds = 12;
  return await bcrypt.hash(password, saltRounds);
};

/**
 * Compare password with hash
 */
const comparePassword = async (password, hash) => {
  return await bcrypt.compare(password, hash);
};

// ============================================================================
// JWT AUTHENTICATION MIDDLEWARE
// ============================================================================

/**
 * JWT Authentication Middleware - Replaces Firebase Auth
 */
const verifyJWT = async (req, res, next) => {
  console.log('\n🔐 JWT AUTH MIDDLEWARE - Token Verification');
  console.log('─'.repeat(80));
  
  try {
    // Check for authorization header
    const authHeader = req?.headers?.authorization;
    
    console.log('   Auth header present:', !!authHeader);
    console.log('   Path:', req?.path || 'unknown');
    console.log('   Method:', req?.method || 'unknown');
    
    // Check for test mode (development only)
    if (process.env.NODE_ENV === 'development' && req.headers['x-test-user-id']) {
      console.log('🧪 TEST MODE DETECTED');
      const testUserId = req.headers['x-test-user-id'];
      const testRole = req.headers['x-test-role'] || 'customer';
      
      req.user = {
        userId: testUserId,
        email: 'test@abrafleet.com',
        name: 'Test User',
        role: testRole,
        modules: [],
        permissions: {},
        collectionName: testRole === 'admin' ? 'admin_users' : `${testRole}s`
      };
      
      console.log('   Test User ID:', testUserId);
      console.log('   Test Role:', testRole);
      console.log('✅ Test authentication bypassed');
      console.log('─'.repeat(80) + '\n');
      return next();
    }

    if (!authHeader || typeof authHeader !== 'string' || !authHeader.startsWith('Bearer ')) {
      console.log('❌ No valid authorization header');
      console.log('─'.repeat(80) + '\n');
      return res.status(401).json({ 
        success: false,
        error: 'Unauthorized', 
        message: 'No valid authorization token provided',
        code: 'MISSING_TOKEN'
      });
    }

    const tokenParts = authHeader.split('Bearer ');
    const token = tokenParts.length > 1 ? tokenParts[1] : null;
    
    if (!token || token.trim() === '') {
      console.log('❌ Token missing after Bearer');
      console.log('─'.repeat(80) + '\n');
      return res.status(401).json({ 
        success: false,
        error: 'Unauthorized', 
        message: 'Invalid token format',
        code: 'INVALID_TOKEN_FORMAT'
      });
    }

    console.log('   Token length:', token.length);

    // Verify the JWT token
console.log('   Verifying JWT token...');
const decoded = jwt.verify(token, JWT_SECRET, {
  algorithms: ['HS256']  // ✅ ADD THIS LINE
});

    
    // Add user info to request object
    req.user = {
      userId: decoded.userId,
      email: decoded.email,
      name: decoded.name,
      role: decoded.role,
      organizationId: decoded.organizationId,
      modules: decoded.modules || [],
      permissions: decoded.permissions || {},
      collectionName: decoded.collectionName,
      // Include role-specific IDs for all user types
      driverId: decoded.driverId || null,
      customerId: decoded.customerId || null,
      clientId: decoded.clientId || null,
      employeeId: decoded.employeeId || null
    };
    
    // Validate critical user data
    if (!req.user.userId || !req.user.email) {
      console.log('❌ Invalid token - missing critical user data');
      console.log('─'.repeat(80) + '\n');
      return res.status(401).json({ 
        success: false,
        error: 'Invalid token', 
        message: 'Token does not contain required user information',
        code: 'INCOMPLETE_TOKEN'
      });
    }

    console.log('✅ JWT token verified successfully');
    console.log('   User ID:', req.user.userId);
    console.log('   User Email:', req.user.email);
    console.log('   User Role:', req.user.role);
    
    // ========================================================================
    // SPECIAL CASE: admin@abrafleet.com = superAdmin (ALWAYS)
    // ========================================================================
    if (req.user.email === 'admin@abrafleet.com') {
      console.log('   👑 SUPER ADMIN EMAIL DETECTED');
      req.user.role = 'super_admin';
      req.user.modules = ['fleet', 'drivers', 'routes', 'customers', 'billing', 'users', 'system', 'tracking', 'reports'];
      req.user.permissions = {};
      console.log('   ✅ Super Admin role + full permissions granted');
      console.log('─'.repeat(80) + '\n');
      return next();
    }
    
    // ========================================================================
    // VERIFY USER EXISTS IN CORRECT MONGODB COLLECTION
    // ========================================================================
    
   // ========================================================================
// VERIFY USER EXISTS IN DATABASE - SEARCH ALL COLLECTIONS
// ========================================================================

try {
  console.log('   Verifying user exists in database...');
  
  if (req?.db && typeof req.db.collection === 'function') {
    // ✅ FIX: Search ALL collections instead of just one
    const collections = [
      'admin_users',
      'drivers',
      'customers',
      'clients',           // ← CRITICAL: Must include this!
      'employee_admins'
    ];
    
    let user = null;
    let foundIn = null;
    
    // Search through each collection
    for (const collectionName of collections) {
      try {
        user = await req.db.collection(collectionName).findOne({ 
          _id: new ObjectId(req.user.userId)
        });
        
        if (user) {
          foundIn = collectionName;
          console.log(`   ✅ User found in ${collectionName}`);
          break;
        }
      } catch (err) {
        // Continue to next collection if ObjectId is invalid
        continue;
      }
    }
    
    if (!user) {
      console.log('   ❌ User not found in any database collection');
      console.log('   Searched collections:', collections.join(', '));
      console.log('─'.repeat(80) + '\n');
      return res.status(401).json({
        success: false,
        error: 'User not found',
        message: 'User account does not exist or has been deleted',
        code: 'USER_NOT_FOUND'
      });
    }
        
       
        
        // Check if user is active
        const isActive = user.isActive !== false && 
                         (!user.status || user.status === 'active');

        if (!isActive) {
          console.log('   ❌ User account is inactive');
          console.log('─'.repeat(80) + '\n');
          return res.status(403).json({
            success: false,
            error: 'Account inactive',
            message: 'Your account is currently inactive. Please contact administrator.',
            code: 'ACCOUNT_INACTIVE'
          });
        }
        
       // Update last active timestamp
await req.db.collection(foundIn).updateOne(
  { _id: user._id },
  { $set: { lastActive: new Date() } }
);

console.log('   ✅ User verified in collection:', foundIn);
        
        console.log('   ✅ User verified in collection:', collectionName);
        console.log('   User status:', user.status || (user.isActive ? 'active' : 'inactive'));
        
      } else {
        console.log('   ⚠️  Database not available - skipping user verification');
      }
    } catch (dbError) {
      console.error('⚠️  Could not verify user in database:', dbError.message);
      // Continue with token data if DB verification fails
    }
    
    console.log('✅ JWT Authentication complete');
    console.log('   Final role:', req.user.role);
    console.log('─'.repeat(80) + '\n');
    
    next();
    
  } catch (error) {
    console.error('❌ JWT TOKEN VERIFICATION FAILED');
    console.error('─'.repeat(80));
    console.error('   Error Message:', error.message);
    console.error('   Error Name:', error.name);
    console.error('─'.repeat(80) + '\n');
    
    // Token expired
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ 
        success: false,
        error: 'Token expired', 
        message: 'Your session has expired. Please login again.',
        code: 'TOKEN_EXPIRED'
      });
    }
    
    // Invalid token
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({
        success: false,
        error: 'Invalid token',
        message: 'The provided token is malformed or invalid.',
        code: 'INVALID_TOKEN'
      });
    }
    
    // Generic auth failure
    return res.status(401).json({ 
      success: false,
      error: 'Authentication failed', 
      message: 'Token verification failed. Please login again.',
      code: error.code || 'AUTH_FAILED',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
};

/**
 * Role-based access middleware
 * Checks if user has one of the required roles
 */
const requireRole = (roles) => {
  return async (req, res, next) => {
    try {
      console.log('\n👮 ROLE CHECK MIDDLEWARE');
      console.log('─'.repeat(80));
      console.log('   Required roles:', roles);
      console.log('   User email:', req.user?.email);
      console.log('   User current role:', req.user?.role);
      
      if (!req.user) {
        console.log('❌ No user in request');
        console.log('─'.repeat(80) + '\n');
        return res.status(401).json({
          success: false,
          error: 'Unauthorized',
          message: 'Authentication required'
        });
      }

      // Special handling for super_admin
      if (req.user.role === 'super_admin') {
        console.log('✅ Super Admin - bypassing role check');
        console.log('─'.repeat(80) + '\n');
        return next();
      }

      // Check if user has required role
      if (!roles.includes(req.user.role)) {
        console.log('❌ Insufficient permissions');
        console.log('   User has:', req.user.role);
        console.log('   Needs one of:', roles);
        console.log('─'.repeat(80) + '\n');
        return res.status(403).json({ 
          success: false,
          error: 'Insufficient permissions', 
          message: `Required role: ${roles.join(' or ')}`,
          userRole: req.user.role
        });
      }
      
      console.log('✅ Role check passed');
      console.log('─'.repeat(80) + '\n');
      next();
      
    } catch (error) {
      console.error('❌ ROLE VERIFICATION FAILED');
      console.error('   Error:', error.message);
      console.error('─'.repeat(80) + '\n');
      
      return res.status(403).json({ 
        success: false,
        error: 'Access denied', 
        message: 'Role verification failed',
        details: process.env.NODE_ENV === 'development' ? error.message : undefined
      });
    }
  };
};

// ============================================================================
// JWT AUTHENTICATION ROUTES
// ============================================================================

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
console.log('   📝 Password from DB:', user.password ? `${user.password.substring(0, 10)}...` : 'NULL');
console.log('   📝 Password type:', typeof user.password);
console.log('   📝 Password starts with $2:', user.password?.startsWith('$2'));

// Handle users without hashed passwords (migration case)
let passwordValid = false;

if (!user.password) {
  console.log('❌ No password field in database');
  passwordValid = false;
} else if (user.password.startsWith('$2')) {
  // Already hashed password (bcrypt hash starts with $2a, $2b, $2y)
  console.log('   Using bcrypt comparison...');
  passwordValid = await comparePassword(password, user.password);
  console.log('   Bcrypt result:', passwordValid);
} else {
  // Plain text password - compare and upgrade
  console.log('   Plain text password detected');
  console.log('   Input password:', password);
  console.log('   Stored password:', user.password);
  console.log('   Direct match:', user.password === password);
  
  if (user.password === password) {
    console.log('   ✅ Plain text password matched - upgrading to hash...');
    const hashedPassword = await hashPassword(password);
    
    await req.db.collection(userCollection).updateOne(
      { _id: user._id },
      { $set: { password: hashedPassword } }
    );
    
    passwordValid = true;
    console.log('   ✅ Password upgraded to bcrypt hash');
  } else {
    console.log('   ❌ Plain text password does not match');
    passwordValid = false;
  }
}

if (!passwordValid) {
  console.log('❌ Invalid password');
  console.log('   Expected:', user.password);
  console.log('   Got:', password);
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
      // ✅ FIX: Set default organizationId if missing
      organizationId: user.organizationId || 'default_org',
      modules: user.modules || [],
      permissions: user.permissions || {},
      collectionName: userCollection
    };
    
    // Add role-specific IDs to token payload
    if (userRole === 'driver' && user.driverId) {
      userData.driverId = user.driverId;
      console.log('   ✅ Added driverId to token:', user.driverId);
    } else if (userRole === 'customer' && user.customerId) {
      userData.customerId = user.customerId;
      console.log('   ✅ Added customerId to token:', user.customerId);
    } else if (userRole === 'client' && user.clientId) {
      userData.clientId = user.clientId;
      console.log('   ✅ Added clientId to token:', user.clientId);
    } else if (userRole === 'employee' && user.employeeId) {
      userData.employeeId = user.employeeId;
      console.log('   ✅ Added employeeId to token:', user.employeeId);
    }
    
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
          collectionName: userCollection,
          // Include role-specific IDs for all user types
          driverId: user.driverId || null,
          customerId: user.customerId || null,
          clientId: user.clientId || null,
          employeeId: user.employeeId || null
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
          collectionName: targetCollection,
          // Include role-specific IDs for all user types
          driverId: newUser.driverId || null,
          customerId: newUser.customerId || null,
          clientId: newUser.clientId || null,
          employeeId: newUser.employeeId || null
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
router.post('/change-password', verifyJWT, async (req, res) => {
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
router.get('/me', verifyJWT, async (req, res) => {
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

/**
 * POST /api/auth/forgot-password - Send Password Reset Email
 */
router.post('/forgot-password', async (req, res) => {
  console.log('\n📧 FORGOT PASSWORD REQUEST');
  console.log('─'.repeat(80));
  
  try {
    const { email } = req.body;
    
    if (!email) {
      return res.status(400).json({
        success: false,
        error: 'Missing email',
        message: 'Email is required'
      });
    }
    
    console.log('   Email:', email);
    
    // Find user in any collection
    const collections = ['admin_users', 'drivers', 'customers', 'clients', 'employee_admins'];
    let user = null;
    let userCollection = null;
    
    for (const collectionName of collections) {
      user = await req.db.collection(collectionName).findOne({ 
        email: email.toLowerCase() 
      });
      
      if (user) {
        userCollection = collectionName;
        console.log(`   ✅ User found in ${collectionName}`);
        break;
      }
    }
    
    if (!user) {
      console.log('❌ User not found');
      // Don't reveal if user exists or not for security
      return res.json({
        success: true,
        message: 'If an account with this email exists, a password reset link has been sent.'
      });
    }
    
    // Generate password reset token (expires in 1 hour)
    const resetToken = jwt.sign(
      { 
        userId: user._id.toString(),
        email: user.email,
        type: 'password_reset'
      },
      JWT_SECRET,
      { 
        expiresIn: '1h',
        algorithm: 'HS256'
      }
    );
    
    // Store reset token in database
    await req.db.collection(userCollection).updateOne(
      { _id: user._id },
      { 
        $set: { 
          resetToken,
          resetTokenExpires: new Date(Date.now() + 3600000), // 1 hour
          updatedAt: new Date()
        } 
      }
    );
    
    console.log('✅ Password reset token generated');
    console.log('─'.repeat(80) + '\n');
    
    // In a real application, you would send an email here
    // For now, we'll just return success
    res.json({
      success: true,
      message: 'If an account with this email exists, a password reset link has been sent.',
      // In development, include the token for testing
      ...(process.env.NODE_ENV === 'development' && { resetToken })
    });
    
  } catch (error) {
    console.error('❌ FORGOT PASSWORD ERROR:', error.message);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Password reset failed',
      message: 'An error occurred while processing password reset',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

/**
 * POST /api/auth/reset-password - Reset Password with Token
 */
router.post('/reset-password', async (req, res) => {
  console.log('\n🔄 RESET PASSWORD REQUEST');
  console.log('─'.repeat(80));
  
  try {
    const { token, newPassword } = req.body;
    
    if (!token || !newPassword) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'Reset token and new password are required'
      });
    }
    
    console.log('   Verifying reset token...');
    
    // Verify reset token
    // Verify reset token
let decoded;
try {
  decoded = jwt.verify(token, JWT_SECRET, {
    algorithms: ['HS256']  // ✅ ADD THIS LINE
  });
} catch (error) {
  console.log('❌ Invalid or expired reset token');
  return res.status(400).json({
    success: false,
    error: 'Invalid token',
    message: 'Reset token is invalid or expired'
  });
}
    
    if (decoded.type !== 'password_reset') {
      return res.status(400).json({
        success: false,
        error: 'Invalid token type',
        message: 'Token is not a password reset token'
      });
    }
    
    console.log('   Token verified for user:', decoded.email);
    
    // Find user in appropriate collection
    const collections = ['admin_users', 'drivers', 'customers', 'clients', 'employee_admins'];
    let user = null;
    let userCollection = null;
    
    for (const collectionName of collections) {
      user = await req.db.collection(collectionName).findOne({ 
        _id: new ObjectId(decoded.userId)
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
    
    // Check if token matches stored token and is not expired
    if (user.resetToken !== token || 
        !user.resetTokenExpires || 
        user.resetTokenExpires < new Date()) {
      console.log('❌ Reset token expired or doesn\'t match');
      return res.status(400).json({
        success: false,
        error: 'Token expired',
        message: 'Reset token has expired or is invalid'
      });
    }
    
    // Hash new password
    const hashedPassword = await hashPassword(newPassword);
    
    // Update password and clear reset token
    await req.db.collection(userCollection).updateOne(
      { _id: user._id },
      { 
        $set: { 
          password: hashedPassword,
          updatedAt: new Date()
        },
        $unset: {
          resetToken: "",
          resetTokenExpires: ""
        }
      }
    );
    
    console.log('✅ Password reset successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Password has been reset successfully'
    });
    
  } catch (error) {
    console.error('❌ RESET PASSWORD ERROR:', error.message);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Password reset failed',
      message: 'An error occurred while resetting password',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

/**
 * POST /api/auth/setup-password - Set password for users without one
 * This is a one-time setup endpoint for users created without passwords
 */
router.post('/setup-password', async (req, res) => {
  console.log('\n🔧 SETUP PASSWORD REQUEST');
  console.log('─'.repeat(80));
  
  try {
    const { email, newPassword, adminKey } = req.body;
    
    // Security: Require an admin key for this operation
    const ADMIN_SETUP_KEY = process.env.ADMIN_SETUP_KEY || 'abra_fleet_setup_2024';
    
    if (adminKey !== ADMIN_SETUP_KEY) {
      console.log('❌ Invalid admin key');
      return res.status(403).json({
        success: false,
        error: 'Unauthorized',
        message: 'Invalid admin setup key'
      });
    }
    
    if (!email || !newPassword) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'Email and new password are required'
      });
    }
    
    console.log('   Email:', email);
    
    // Find user in any collection
    const collections = ['admin_users', 'drivers', 'customers', 'clients', 'employee_admins'];
    let user = null;
    let userCollection = null;
    
    for (const collectionName of collections) {
      user = await req.db.collection(collectionName).findOne({ 
        email: email.toLowerCase() 
      });
      
      if (user) {
        userCollection = collectionName;
        console.log(`   ✅ User found in ${collectionName}`);
        break;
      }
    }
    
    if (!user) {
      console.log('❌ User not found');
      return res.status(404).json({
        success: false,
        error: 'User not found',
        message: 'No user found with this email'
      });
    }
    
    // Check if user already has a password
    if (user.password && user.password.startsWith('$2')) {
      console.log('⚠️  User already has a hashed password');
      return res.status(400).json({
        success: false,
        error: 'Password already exists',
        message: 'User already has a password set. Use change-password endpoint instead.'
      });
    }
    
    // Hash the new password
    console.log('   Hashing new password...');
    const hashedPassword = await hashPassword(newPassword);
    
    // Update user with new password
    await req.db.collection(userCollection).updateOne(
      { _id: user._id },
      { 
        $set: { 
          password: hashedPassword,
          updatedAt: new Date()
        } 
      }
    );
    
    console.log('✅ Password setup successfully');
    console.log('   User:', user.email);
    console.log('   Collection:', userCollection);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Password has been set successfully. You can now login with this password.',
      data: {
        email: user.email,
        name: user.name,
        role: user.role
      }
    });
    
  } catch (error) {
    console.error('❌ SETUP PASSWORD ERROR:', error.message);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Password setup failed',
      message: 'An error occurred while setting up password',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});


/**
 * POST /api/auth/bulk-setup-passwords - Set passwords for all users without one
 * This is a one-time bulk setup endpoint for migration
 */
router.post('/bulk-setup-passwords', async (req, res) => {
  console.log('\n🔧 BULK PASSWORD SETUP REQUEST');
  console.log('─'.repeat(80));
  
  try {
    const { adminKey, defaultPassword = 'abrafleet123' } = req.body;
    
    // Security: Require an admin key for this operation
    const ADMIN_SETUP_KEY = process.env.ADMIN_SETUP_KEY || 'abra_fleet_setup_2024';
    
    if (adminKey !== ADMIN_SETUP_KEY) {
      console.log('❌ Invalid admin key');
      return res.status(403).json({
        success: false,
        error: 'Unauthorized',
        message: 'Invalid admin setup key'
      });
    }
    
    console.log('   Default password:', defaultPassword);
    console.log('   Processing all collections...');
    
    // Hash the default password once
    const hashedPassword = await hashPassword(defaultPassword);
    
    const collections = [
      'admin_users',
      'drivers', 
      'customers',
      'clients',
      'employee_admins'
    ];
    
    const results = {
      total: 0,
      updated: 0,
      skipped: 0,
      errors: 0,
      details: []
    };
    
    for (const collectionName of collections) {
      console.log(`\n   📁 Processing collection: ${collectionName}`);
      
      try {
        // Find all users in this collection
        const users = await req.db.collection(collectionName).find({}).toArray();
        
        console.log(`   Found ${users.length} users`);
        results.total += users.length;
        
        for (const user of users) {
          try {
            // Check if user already has a hashed password
            if (user.password && user.password.startsWith('$2')) {
              console.log(`   ⏭️  Skipping ${user.email} - already has hashed password`);
              results.skipped++;
              results.details.push({
                email: user.email,
                collection: collectionName,
                status: 'skipped',
                reason: 'Already has hashed password'
              });
              continue;
            }
            
            // Check if user has a plain text password
            if (user.password && !user.password.startsWith('$2')) {
              console.log(`   🔄 Upgrading plain text password for ${user.email}`);
              const plainTextHash = await hashPassword(user.password);
              
              await req.db.collection(collectionName).updateOne(
                { _id: user._id },
                { 
                  $set: { 
                    password: plainTextHash,
                    updatedAt: new Date()
                  } 
                }
              );
              
              results.updated++;
              results.details.push({
                email: user.email,
                collection: collectionName,
                status: 'updated',
                reason: 'Upgraded plain text password to hash'
              });
              continue;
            }
            
            // User has no password - set default password
            if (!user.password) {
              console.log(`   ✅ Setting default password for ${user.email}`);
              
              await req.db.collection(collectionName).updateOne(
                { _id: user._id },
                { 
                  $set: { 
                    password: hashedPassword,
                    updatedAt: new Date()
                  } 
                }
              );
              
              results.updated++;
              results.details.push({
                email: user.email,
                collection: collectionName,
                status: 'updated',
                reason: 'Set default password'
              });
            }
            
          } catch (userError) {
            console.error(`   ❌ Error processing user ${user.email}:`, userError.message);
            results.errors++;
            results.details.push({
              email: user.email,
              collection: collectionName,
              status: 'error',
              reason: userError.message
            });
          }
        }
        
      } catch (collectionError) {
        console.error(`   ❌ Error processing collection ${collectionName}:`, collectionError.message);
        results.errors++;
      }
    }
    
    console.log('\n✅ Bulk password setup completed');
    console.log('   Total users:', results.total);
    console.log('   Updated:', results.updated);
    console.log('   Skipped:', results.skipped);
    console.log('   Errors:', results.errors);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'Bulk password setup completed',
      data: {
        summary: {
          total: results.total,
          updated: results.updated,
          skipped: results.skipped,
          errors: results.errors
        },
        defaultPassword: defaultPassword,
        details: results.details
      }
    });
    
  } catch (error) {
    console.error('❌ BULK PASSWORD SETUP ERROR:', error.message);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Bulk password setup failed',
      message: 'An error occurred during bulk password setup',
      details: process.env.NODE_ENV === 'development' ? error.message : undefined
    });
  }
});

/**
 * GET /api/auth/users-without-passwords - Check which users don't have passwords
 * Diagnostic endpoint to see who needs password setup
 */
router.get('/users-without-passwords', async (req, res) => {
  console.log('\n🔍 CHECKING USERS WITHOUT PASSWORDS');
  console.log('─'.repeat(80));
  
  try {
    const { adminKey } = req.query;
    
    // Security: Require an admin key for this operation
    const ADMIN_SETUP_KEY = process.env.ADMIN_SETUP_KEY || 'abra_fleet_setup_2024';
    
    if (adminKey !== ADMIN_SETUP_KEY) {
      console.log('❌ Invalid admin key');
      return res.status(403).json({
        success: false,
        error: 'Unauthorized',
        message: 'Invalid admin setup key'
      });
    }
    
    const collections = [
      'admin_users',
      'drivers',
      'customers', 
      'clients',
      'employee_admins'
    ];
    
    const usersWithoutPasswords = [];
    const usersWithPlainTextPasswords = [];
    const usersWithHashedPasswords = [];
    
    for (const collectionName of collections) {
      const users = await req.db.collection(collectionName).find({}).toArray();
      
      for (const user of users) {
        const userInfo = {
          email: user.email,
          name: user.name,
          role: user.role,
          collection: collectionName
        };
        
        if (!user.password) {
          usersWithoutPasswords.push(userInfo);
        } else if (user.password.startsWith('$2')) {
          usersWithHashedPasswords.push(userInfo);
        } else {
          usersWithPlainTextPasswords.push(userInfo);
        }
      }
    }
    
    console.log('✅ Analysis complete');
    console.log('   No password:', usersWithoutPasswords.length);
    console.log('   Plain text:', usersWithPlainTextPasswords.length);
    console.log('   Hashed:', usersWithHashedPasswords.length);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: {
        summary: {
          noPassword: usersWithoutPasswords.length,
          plainText: usersWithPlainTextPasswords.length,
          hashed: usersWithHashedPasswords.length,
          total: usersWithoutPasswords.length + usersWithPlainTextPasswords.length + usersWithHashedPasswords.length
        },
        usersWithoutPasswords,
        usersWithPlainTextPasswords,
        usersWithHashedPasswords
      }
    });
    
  } catch (error) {
    console.error('❌ CHECK ERROR:', error.message);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Check failed',
      message: error.message
    });
  }
});


// ============================================================================
// EXPORT ROUTER AND MIDDLEWARE
// ============================================================================

// Export the router
module.exports = router;

// Also export middleware functions for use in other routes
module.exports.verifyJWT = verifyJWT;
module.exports.requireRole = requireRole;
module.exports.generateToken = generateToken;
module.exports.hashPassword = hashPassword;
module.exports.comparePassword = comparePassword;