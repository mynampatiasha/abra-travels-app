// routes/auth.js - JWT-ONLY AUTH ROUTES
// ============================================================================
// USES JWT AUTHENTICATION ONLY - NO FIREBASE
// ============================================================================
const express = require('express');
const router = express.Router();

// Import JWT middleware and utilities
const { verifyJWT } = require('./jwt_router');

/**
 * Legacy auth routes - now redirect to JWT routes
 * These routes are kept for backward compatibility
 */

/**
 * POST /api/auth/login
 * Redirect to JWT login
 */
router.post('/login', (req, res) => {
  res.status(301).json({
    success: false,
    error: 'Deprecated endpoint',
    message: 'Please use JWT authentication endpoints',
    redirect: '/api/auth/login'
  });
});

/**
 * GET /api/auth/profile
 * Get current user profile using JWT
 */
router.get('/profile', verifyJWT, async (req, res) => {
  console.log('\n👤 GET USER PROFILE - JWT Authentication');
  console.log('─'.repeat(80));
  
  try {
    if (!req.user) {
      return res.status(401).json({
        success: false,
        error: 'Unauthorized',
        message: 'User not authenticated'
      });
    }
    
    console.log('   User ID:', req.user.userId);
    console.log('   Email:', req.user.email);
    console.log('   Role:', req.user.role);
    
    // Build response with user data from JWT token
    const response = {
      success: true,
      user: {
        id: req.user.userId,
        email: req.user.email,
        name: req.user.name,
        role: req.user.role,
        organizationId: req.user.organizationId,
        modules: req.user.modules || [],
        permissions: req.user.permissions || {},
        // Include role-specific IDs
        driverId: req.user.driverId || null,
        customerId: req.user.customerId || null,
        clientId: req.user.clientId || null,
        employeeId: req.user.employeeId || null
      }
    };
    
    console.log('✅ Profile retrieved successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.json(response);
    
  } catch (error) {
    console.error('❌ GET PROFILE FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to get profile',
      message: error.message
    });
  }
});

/**
 * GET /api/auth/verify-email/:email
 * Verify user exists and is active - checks ALL collections
 */
router.get('/verify-email/:email', async (req, res) => {
  console.log('\n🔍 VERIFY USER BY EMAIL');
  console.log('─'.repeat(80));
  
  try {
    const { email } = req.params;
    const db = req.db;
    
    console.log('   Email:', email);
    
    if (!email) {
      return res.status(400).json({
        success: false,
        error: 'Missing email',
        message: 'Email parameter is required'
      });
    }
    
    // Check all collections
    const collections = ['admin_users', 'drivers', 'customers', 'clients', 'employee_admins'];
    let user = null;
    let foundIn = null;
    
    for (const collectionName of collections) {
      console.log(`   Checking ${collectionName}...`);
      user = await db.collection(collectionName).findOne({ 
        email: email.toLowerCase() 
      });
      
      if (user) {
        foundIn = collectionName;
        console.log(`   ✅ Found in ${collectionName}`);
        break;
      }
    }
    
    if (!user) {
      console.log('❌ User not found in any collection');
      console.log('─'.repeat(80) + '\n');
      return res.status(404).json({
        success: false,
        error: 'User not found',
        message: 'User not found in database'
      });
    }
    
    // Determine role from collection name if not present
    let userRole = user.role;
    
    if (!userRole) {
      switch (foundIn) {
        case 'drivers':
          userRole = 'driver';
          break;
        case 'customers':
          userRole = 'customer';
          break;
        case 'clients':
          userRole = 'client';
          break;
        case 'admin_users':
        case 'employee_admins':
          userRole = user.role || 'employee';
          break;
        default:
          userRole = 'customer';
      }
      console.log(`   ⚠️  Role not in document, inferred from collection: ${userRole}`);
    }
    
    // Check if user is active
    const isActive = user.isActive !== false && (!user.status || user.status === 'active');
    
    if (!isActive) {
      console.log('❌ User account is inactive');
      console.log('─'.repeat(80) + '\n');
      return res.status(403).json({
        success: false,
        error: 'Account inactive',
        message: 'Your account is currently inactive. Please contact administrator.'
      });
    }
    
    console.log('✅ User verified successfully');
    console.log('   Role:', userRole);
    console.log('   Found in:', foundIn);
    console.log('─'.repeat(80) + '\n');
    
    return res.json({
      success: true,
      message: 'User verified successfully',
      user: {
        email: user.email,
        name: user.name,
        role: userRole,
        phone: user.phone,
        status: isActive ? 'active' : 'inactive',
        modules: user.modules || [],
        permissions: user.permissions || {}
      }
    });
    
  } catch (error) {
    console.error('❌ VERIFY EMAIL FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');
    
    return res.status(500).json({
      success: false,
      error: 'Verification failed',
      message: error.message
    });
  }
});

module.exports = router;