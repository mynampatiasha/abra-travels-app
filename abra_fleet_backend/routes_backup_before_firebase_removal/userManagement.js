// routes/userManagement.js - JWT ONLY VERSION
const express = require('express');
const router = express.Router();
const User = require('../models/User');
const { verifyJWT, requireRole } = require('./jwt_router');

// ============================================
// CREATE USER WITH PERMISSIONS
// ============================================
router.post('/users', verifyJWT, requireRole(['super', 'admin']), async (req, res) => {
  console.log('\n📝 CREATE USER WITH PERMISSIONS');
  console.log('─'.repeat(80));
  
  try {
    const {
      name,
      email,
      phone,
      password,
      role,
      standardPermissions,
      customPermissions
    } = req.body;

    console.log('   Creating user:', email);
    console.log('   Role:', role);
    console.log('   Standard permissions:', standardPermissions?.length || 0);
    console.log('   Custom permissions:', customPermissions?.length || 0);

    // Validation
    if (!name || !email || !password) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'Name, email, and password are required'
      });
    }

    // Check if user already exists in MongoDB
    const existingUser = await User.findOne({ email: email.toLowerCase() });
    if (existingUser) {
      return res.status(400).json({
        success: false,
        error: 'User already exists',
        message: 'A user with this email already exists'
      });
    }

    // Step 1: Create user in Firebase Authentication
    console.log('   Step 1: Creating Firebase user...');
    let firebaseUser;
    try {
      firebaseUser = await admin.auth().createUser({
        email: email.toLowerCase(),
        password: password,
        displayName: name,
        emailVerified: false
      });
      console.log('   ✅ Firebase user created:', firebaseUser.uid);
    } catch (firebaseError) {
      console.error('   ❌ Firebase creation failed:', firebaseError.message);
      
      if (firebaseError.code === 'auth/email-already-exists') {
        return res.status(400).json({
          success: false,
          error: 'Email already exists',
          message: 'This email is already registered in Firebase'
        });
      }
      
      throw firebaseError;
    }

    // Step 2: Set custom claims in Firebase (for role-based access)
    console.log('   Step 2: Setting Firebase custom claims...');
    try {
      await admin.auth().setCustomUserClaims(firebaseUser.uid, {
        role: role || 'custom',
        hasPermissions: true
      });
      console.log('   ✅ Custom claims set');
    } catch (claimError) {
      console.error('   ⚠️  Custom claims failed:', claimError.message);
      // Continue anyway - not critical
    }

    // Step 3: Save user with permissions to MongoDB
    console.log('   Step 3: Saving to MongoDB...');
    const newUser = new User({
      name,
      email: email.toLowerCase(),
      phone: phone || '',
      password, // Will be hashed by pre-save hook
      role: role || 'custom',
      standardPermissions: standardPermissions || [],
      customPermissions: customPermissions || [],
      firebaseUid: firebaseUser.uid,
      isActive: true,
      createdBy: req.user.mongoId
    });

    await newUser.save();
    console.log('   ✅ User saved to MongoDB');

    // Remove password from response
    const userResponse = newUser.toObject();
    delete userResponse.password;

    console.log('✅ USER CREATED SUCCESSFULLY');
    console.log('─'.repeat(80) + '\n');

    res.status(201).json({
      success: true,
      message: 'User created successfully',
      data: {
        user: userResponse,
        firebaseUid: firebaseUser.uid
      }
    });

  } catch (error) {
    console.error('❌ CREATE USER FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      error: 'Failed to create user',
      message: error.message,
      details: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
});

// ============================================
// GET ALL USERS (WITH PAGINATION) - ADMIN ROLES ONLY
// ============================================
router.get('/users', verifyJWT, requireRole(['super', 'admin']), async (req, res) => {
  console.log('\n📋 GET ALL ADMIN USERS');
  console.log('─'.repeat(80));
  
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const skip = (page - 1) * limit;
    const search = req.query.search || '';
    const roleFilter = req.query.role || '';

    console.log('   Page:', page);
    console.log('   Limit:', limit);
    console.log('   Search:', search);
    console.log('   Role filter:', roleFilter);

    // Define admin roles only - exclude driver, customer, client
    const adminRoles = [
      'super_admin', 'superadmin', 'admin',
      'org_admin', 'organization_admin',
      'fleet_manager',
      'operations', 'operations_manager',
      'hr_manager',
      'finance', 'finance_admin'
    ];

    // Build query - only include admin roles
    const query = {
      role: { $in: adminRoles }
    };
    
    if (search) {
      query.$and = [
        { role: { $in: adminRoles } },
        {
          $or: [
            { name: { $regex: search, $options: 'i' } },
            { email: { $regex: search, $options: 'i' } }
          ]
        }
      ];
    }
    
    if (roleFilter && adminRoles.includes(roleFilter)) {
      query.role = roleFilter;
    }

    console.log('   Query filter: Only admin roles -', adminRoles.join(', '));

    // Get users
    const users = await User.find(query)
      .select('-password')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .populate('createdBy', 'name email');

    const total = await User.countDocuments(query);

    // Filter out any non-admin users that might have slipped through
    const filteredUsers = users.filter(user => 
      adminRoles.includes(user.role?.toLowerCase()?.trim()?.replace(' ', '_'))
    );

    console.log('   Found:', filteredUsers.length, 'admin users');
    console.log('   Total admin users:', total);
    console.log('   Excluded roles: driver, customer, client');
    console.log('✅ ADMIN USERS RETRIEVED');
    console.log('─'.repeat(80) + '\n');

    res.json({
      success: true,
      data: filteredUsers,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit)
      }
    });

  } catch (error) {
    console.error('❌ GET ADMIN USERS FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      error: 'Failed to retrieve admin users',
      message: error.message
    });
  }
});

// ============================================
// GET USER BY ID
// ============================================
router.get('/users/:id', verifyJWT, requireRole(['super', 'admin']), async (req, res) => {
  console.log('\n👤 GET USER BY ID');
  console.log('─'.repeat(80));
  
  try {
    const userId = req.params.id;
    console.log('   User ID:', userId);

    const user = await User.findById(userId)
      .select('-password')
      .populate('createdBy', 'name email');

    if (!user) {
      console.log('   ❌ User not found');
      return res.status(404).json({
        success: false,
        error: 'User not found',
        message: 'No user found with this ID'
      });
    }

    console.log('   ✅ User found:', user.email);
    console.log('─'.repeat(80) + '\n');

    res.json({
      success: true,
      data: { user }
    });

  } catch (error) {
    console.error('❌ GET USER FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      error: 'Failed to retrieve user',
      message: error.message
    });
  }
});

// ============================================
// UPDATE USER PERMISSIONS
// ============================================
router.put('/users/:id', verifyJWT, requireRole(['super', 'admin']), async (req, res) => {
  console.log('\n✏️  UPDATE USER PERMISSIONS');
  console.log('─'.repeat(80));
  
  try {
    const userId = req.params.id;
    const {
      name,
      phone,
      role,
      standardPermissions,
      customPermissions,
      isActive
    } = req.body;

    console.log('   User ID:', userId);
    console.log('   Updating fields:', Object.keys(req.body));

    const user = await User.findById(userId);
    
    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'User not found',
        message: 'No user found with this ID'
      });
    }

    // Update fields
    if (name) user.name = name;
    if (phone !== undefined) user.phone = phone;
    if (role) user.role = role;
    if (standardPermissions) user.standardPermissions = standardPermissions;
    if (customPermissions) user.customPermissions = customPermissions;
    if (isActive !== undefined) user.isActive = isActive;

    await user.save();

    // Update Firebase custom claims if role changed
    if (role && user.firebaseUid) {
      try {
        await admin.auth().setCustomUserClaims(user.firebaseUid, {
          role: role,
          hasPermissions: true
        });
        console.log('   ✅ Firebase claims updated');
      } catch (claimError) {
        console.error('   ⚠️  Firebase claims update failed:', claimError.message);
      }
    }

    const updatedUser = user.toObject();
    delete updatedUser.password;

    console.log('✅ USER UPDATED');
    console.log('─'.repeat(80) + '\n');

    res.json({
      success: true,
      message: 'User updated successfully',
      data: { user: updatedUser }
    });

  } catch (error) {
    console.error('❌ UPDATE USER FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      error: 'Failed to update user',
      message: error.message
    });
  }
});

// ============================================
// DELETE USER (SOFT DELETE)
// ============================================
router.delete('/users/:id', verifyJWT, requireRole(['super']), async (req, res) => {
  console.log('\n🗑️  DELETE USER');
  console.log('─'.repeat(80));
  
  try {
    const userId = req.params.id;
    console.log('   User ID:', userId);

    const user = await User.findById(userId);
    
    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'User not found',
        message: 'No user found with this ID'
      });
    }

    // Soft delete - just deactivate
    user.isActive = false;
    await user.save();

    // Optionally disable in Firebase
    if (user.firebaseUid) {
      try {
        await admin.auth().updateUser(user.firebaseUid, {
          disabled: true
        });
        console.log('   ✅ Firebase user disabled');
      } catch (firebaseError) {
        console.error('   ⚠️  Firebase disable failed:', firebaseError.message);
      }
    }

    console.log('✅ USER DELETED (SOFT)');
    console.log('─'.repeat(80) + '\n');

    res.json({
      success: true,
      message: 'User deleted successfully'
    });

  } catch (error) {
    console.error('❌ DELETE USER FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      error: 'Failed to delete user',
      message: error.message
    });
  }
});

// ============================================
// TOGGLE USER STATUS (ACTIVATE/DEACTIVATE)
// ============================================
router.patch('/users/:id/toggle-status', verifyJWT, requireRole(['super', 'admin']), async (req, res) => {
  console.log('\n🔄 TOGGLE USER STATUS');
  console.log('─'.repeat(80));
  
  try {
    const userId = req.params.id;
    console.log('   User ID:', userId);

    const user = await User.findById(userId);
    
    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'User not found',
        message: 'No user found with this ID'
      });
    }

    // Toggle status
    user.isActive = !user.isActive;
    await user.save();

    // Update Firebase
    if (user.firebaseUid) {
      try {
        await admin.auth().updateUser(user.firebaseUid, {
          disabled: !user.isActive
        });
        console.log('   ✅ Firebase user status updated');
      } catch (firebaseError) {
        console.error('   ⚠️  Firebase update failed:', firebaseError.message);
      }
    }

    console.log('   New status:', user.isActive ? 'Active' : 'Inactive');
    console.log('✅ STATUS TOGGLED');
    console.log('─'.repeat(80) + '\n');

    res.json({
      success: true,
      message: `User ${user.isActive ? 'activated' : 'deactivated'} successfully`,
      data: {
        isActive: user.isActive
      }
    });

  } catch (error) {
    console.error('❌ TOGGLE STATUS FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      error: 'Failed to toggle user status',
      message: error.message
    });
  }
});

module.exports = router;

// ============================================
// VERIFY USER STATUS BY EMAIL (FOR LOGIN) - NO AUTH REQUIRED
// ============================================
router.get('/verify-user/:email', async (req, res) => {
  console.log('\n🔍 VERIFY USER STATUS');
  console.log('─'.repeat(80));
  
  try {
    const email = req.params.email.toLowerCase();
    console.log('   Email:', email);

    // Find user in MongoDB
    const user = await User.findOne({ email: email });
    
    if (!user) {
      console.log('   ❌ User not found in MongoDB');
      return res.status(404).json({
        success: false,
        error: 'User not found',
        message: 'No user found with this email'
      });
    }

    console.log('   ✅ User found:', user.name);
    console.log('   Role:', user.role);
    console.log('   Status:', user.isActive ? 'Active' : 'Inactive');
    console.log('   Firebase UID:', user.firebaseUid);

    // Check if user is active
    if (!user.isActive) {
      console.log('   ⚠️  User account is inactive');
      return res.status(403).json({
        success: false,
        error: 'Account inactive',
        message: 'Your account is currently inactive. Please contact administrator.'
      });
    }

    console.log('✅ USER VERIFICATION SUCCESSFUL');
    console.log('─'.repeat(80) + '\n');

    res.json({
      success: true,
      message: 'User verification successful',
      data: {
        id: user._id,
        name: user.name,
        email: user.email,
        role: user.role,
        phone: user.phone,
        isActive: user.isActive,
        firebaseUid: user.firebaseUid,
        createdAt: user.createdAt
      }
    });

  } catch (error) {
    console.error('❌ USER VERIFICATION FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');

    res.status(500).json({
      success: false,
      error: 'Failed to verify user',
      message: error.message
    });
  }
});