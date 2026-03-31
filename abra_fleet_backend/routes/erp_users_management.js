// backend/routes/erp_users_management.js
// ============================================================================
// 🔐 ERP USERS MANAGEMENT - BACKEND API (Node.js + MongoDB)
// ============================================================================
// Complete CRUD operations for ERP users with permission management
// FIXED: Uses req.db instead of req.app.locals.db
// ============================================================================

const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

// Import authentication middleware
const { verifyJWT } = require('./jwt_router');

// ============================================================================
// 🛡️ ADMIN-ONLY MIDDLEWARE
// ============================================================================
const adminOnlyMiddleware = (req, res, next) => {
  if (req.user.role !== 'super_admin' && req.user.role !== 'admin') {
    return res.status(403).json({ 
      success: false, 
      message: 'Access denied. Admin privileges required.' 
    });
  }
  next();
};

// ============================================================================
// 📦 GET ALL ERP USERS
// ============================================================================
router.get('/api/erp-users', verifyJWT, async (req, res) => {
  try {
    console.log('\n📋 FETCHING ALL ERP USERS');
    console.log('─'.repeat(80));
    
    const db = req.db; // ✅ FIXED: Use req.db from middleware
    
    if (!db) {
      console.error('❌ Database not available');
      return res.status(503).json({ 
        success: false, 
        message: 'Database not available' 
      });
    }
    
    const users = await db.collection('employee_admins').find({}).toArray();
    
    console.log(`✅ Found ${users.length} users`);
    
    // Remove password field from response
    const sanitizedUsers = users.map(user => {
      const { password, pwd, ...rest } = user;
      return rest;
    });
    
    res.json({ success: true, data: sanitizedUsers });
  } catch (error) {
    console.error('❌ Error fetching ERP users:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch users', 
      error: error.message 
    });
  }
});

// ============================================================================
// 🔍 GET SINGLE ERP USER
// ============================================================================
router.get('/api/erp-users/:id', verifyJWT, async (req, res) => {
  try {
    const { ObjectId } = require('mongodb');
    const db = req.db; // ✅ FIXED
    const { id } = req.params;
    
    if (!db) {
      return res.status(503).json({ 
        success: false, 
        message: 'Database not available' 
      });
    }
    
    const user = await db.collection('employee_admins').findOne({ 
      _id: new ObjectId(id) 
    });
    
    if (!user) {
      return res.status(404).json({ 
        success: false, 
        message: 'User not found' 
      });
    }
    
    // Remove password
    const { password, pwd, ...sanitizedUser } = user;
    
    res.json({ success: true, data: sanitizedUser });
  } catch (error) {
    console.error('❌ Error fetching user:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch user', 
      error: error.message 
    });
  }
});


// ============================================================================
// 🔍 GET USER PERMISSIONS BY EMAIL (CRITICAL - WAS MISSING!)
// ============================================================================
router.get('/api/employee-management/permissions/:email', verifyJWT, async (req, res) => {
  try {
    console.log('\n🔐 ========================================');
    console.log('🔐 FETCHING PERMISSIONS BY EMAIL');
    console.log('🔐 ========================================');
    
    const db = req.db;
    const { email } = req.params;
    
    console.log('📧 Email:', email);
    
    if (!db) {
      console.error('❌ Database not available');
      return res.status(503).json({ 
        success: false, 
        message: 'Database not available' 
      });
    }
    
    // ✅ Find user by email
    const user = await db.collection('employee_admins').findOne({ 
      email: email.toLowerCase() 
    });
    
    if (!user) {
      console.error('❌ User not found:', email);
      return res.status(404).json({ 
        success: false, 
        message: 'User not found',
        data: { permissions: {} }
      });
    }
    
    console.log('✅ User found:', user.name_parson || user.username);
    console.log('📋 Role:', user.role);
    
    // ✅ Get permissions (default to empty object if none)
    const permissions = user.permissions || {};
    
    console.log('📋 Permissions loaded:', Object.keys(permissions).length, 'items');
    
    // ✅ Log each permission for debugging
    Object.entries(permissions).forEach(([key, value]) => {
      if (typeof value === 'object' && value !== null) {
        console.log(`   ✓ ${key}: can_access=${value.can_access}, edit_delete=${value.edit_delete || false}`);
      }
    });
    
    console.log('🔐 ========================================');
    
    res.json({ 
      success: true, 
      data: {
        permissions: permissions,
        role: user.role,
        email: user.email,
        name: user.name_parson || user.username
      }
    });
  } catch (error) {
    console.error('❌ Error fetching permissions:', error);
    console.error('Stack:', error.stack);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch permissions', 
      error: error.message,
      data: { permissions: {} }
    });
  }
});


// ============================================================================
// ➕ CREATE NEW ERP USER (ADMIN ONLY)
// ============================================================================
router.post('/api/erp-users', verifyJWT, adminOnlyMiddleware, async (req, res) => {
  try {
    console.log('\n➕ CREATING NEW ERP USER');
    console.log('─'.repeat(80));
    
    const db = req.db; // ✅ FIXED
    
    if (!db) {
      console.error('❌ Database not available');
      return res.status(503).json({ 
        success: false, 
        message: 'Database not available' 
      });
    }
    
    const { name_parson, email, phone, username, password, office, role } = req.body;
    
    console.log('📝 User data:', { name_parson, email, phone, username, office, role });
    
    // Validation
    if (!name_parson || !email || !phone || !username || !password) {
      console.error('❌ Missing required fields');
      return res.status(400).json({ 
        success: false, 
        message: 'Missing required fields: name, email, phone, username, password' 
      });
    }
    
    // Check if email or username already exists
    const existingUser = await db.collection('employee_admins').findOne({
      $or: [{ email }, { username }]
    });
    
    if (existingUser) {
      console.error('❌ User already exists:', existingUser.email);
      return res.status(409).json({ 
        success: false, 
        message: 'User with this email or username already exists' 
      });
    }
    
    // Hash password
    console.log('🔐 Hashing password...');
    const hashedPassword = await bcrypt.hash(password, 10);
    
    // Create user object
    const newUser = {
      name_parson,
      username,
      email,
      phone,
      office: office || '',
      role: role || 'employee',
      password: hashedPassword,
      pwd: hashedPassword, // For compatibility
      status: 'active',
      estado: 'active', // For compatibility
      permissions: {}, // Empty permissions by default
      createdAt: new Date(),
      createdBy: req.user.email || req.user.username
    };
    
    console.log('💾 Inserting user into database...');
    const result = await db.collection('employee_admins').insertOne(newUser);
    
    console.log('✅ User created with ID:', result.insertedId);
    
    // Return without password
    const { password: _, pwd: __, ...userResponse } = newUser;
    userResponse._id = result.insertedId;
    
    res.status(201).json({ 
      success: true, 
      message: 'User created successfully', 
      data: userResponse 
    });
  } catch (error) {
    console.error('❌ Error creating user:', error);
    console.error('Stack:', error.stack);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to create user', 
      error: error.message 
    });
  }
});

// ============================================================================
// ✏️ UPDATE ERP USER (ADMIN ONLY)
// ============================================================================
router.put('/api/erp-users/:id', verifyJWT, adminOnlyMiddleware, async (req, res) => {
  try {
    console.log('\n✏️ UPDATING ERP USER');
    console.log('─'.repeat(80));
    
    const { ObjectId } = require('mongodb');
    const db = req.db; // ✅ FIXED
    const { id } = req.params;
    const { name_parson, email, phone, username, password, office, role, status } = req.body;
    
    if (!db) {
      return res.status(503).json({ 
        success: false, 
        message: 'Database not available' 
      });
    }
    
    console.log('📝 Updating user:', id);
    
    // Build update object
    const updateData = {
      updatedAt: new Date(),
      updatedBy: req.user.email || req.user.username
    };
    
    if (name_parson) updateData.name_parson = name_parson;
    if (email) updateData.email = email;
    if (phone) updateData.phone = phone;
    if (username) updateData.username = username;
    if (office !== undefined) updateData.office = office;
    if (role) updateData.role = role;
    if (status) {
      updateData.status = status;
      updateData.estado = status; // For compatibility
    }
    
    // Hash password if provided
    if (password) {
      console.log('🔐 Hashing new password...');
      const hashedPassword = await bcrypt.hash(password, 10);
      updateData.password = hashedPassword;
      updateData.pwd = hashedPassword;
    }
    
    const result = await db.collection('employee_admins').updateOne(
      { _id: new ObjectId(id) },
      { $set: updateData }
    );
    
    if (result.matchedCount === 0) {
      console.error('❌ User not found');
      return res.status(404).json({ 
        success: false, 
        message: 'User not found' 
      });
    }
    
    console.log('✅ User updated successfully');
    res.json({ success: true, message: 'User updated successfully' });
  } catch (error) {
    console.error('❌ Error updating user:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to update user', 
      error: error.message 
    });
  }
});

// ============================================================================
// 🗑️ DELETE ERP USER (ADMIN ONLY)
// ============================================================================
router.delete('/api/erp-users/:id', verifyJWT, adminOnlyMiddleware, async (req, res) => {
  try {
    console.log('\n🗑️ DELETING ERP USER');
    console.log('─'.repeat(80));
    
    const { ObjectId } = require('mongodb');
    const db = req.db; // ✅ FIXED
    const { id } = req.params;
    
    if (!db) {
      return res.status(503).json({ 
        success: false, 
        message: 'Database not available' 
      });
    }
    
    console.log('🗑️ Deleting user:', id);
    
    const result = await db.collection('employee_admins').deleteOne({ 
      _id: new ObjectId(id) 
    });
    
    if (result.deletedCount === 0) {
      console.error('❌ User not found');
      return res.status(404).json({ 
        success: false, 
        message: 'User not found' 
      });
    }
    
    console.log('✅ User deleted successfully');
    res.json({ success: true, message: 'User deleted successfully' });
  } catch (error) {
    console.error('❌ Error deleting user:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to delete user', 
      error: error.message 
    });
  }
});

// ============================================================================
// 🔐 GET USER PERMISSIONS
// ============================================================================
router.get('/api/erp-users/:id/permissions', verifyJWT, async (req, res) => {
  try {
    const { ObjectId } = require('mongodb');
    const db = req.db; // ✅ FIXED
    const { id } = req.params;
    
    if (!db) {
      return res.status(503).json({ 
        success: false, 
        message: 'Database not available' 
      });
    }
    
    const user = await db.collection('employee_admins').findOne({ 
      _id: new ObjectId(id) 
    });
    
    if (!user) {
      return res.status(404).json({ 
        success: false, 
        message: 'User not found' 
      });
    }
    
    res.json({ success: true, data: user.permissions || {} });
  } catch (error) {
    console.error('❌ Error fetching permissions:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to fetch permissions', 
      error: error.message 
    });
  }
});

// ============================================================================
// 💾 SAVE USER PERMISSIONS (ADMIN ONLY)
// ============================================================================
router.post('/api/erp-users/:id/permissions', verifyJWT, adminOnlyMiddleware, async (req, res) => {
  try {
    console.log('\n💾 SAVING USER PERMISSIONS');
    console.log('─'.repeat(80));
    
    const { ObjectId } = require('mongodb');
    const db = req.db; // ✅ FIXED
    const { id } = req.params;
    const { permissions } = req.body;
    
    if (!db) {
      return res.status(503).json({ 
        success: false, 
        message: 'Database not available' 
      });
    }
    
    if (!permissions || typeof permissions !== 'object') {
      return res.status(400).json({ 
        success: false, 
        message: 'Invalid permissions format' 
      });
    }
    
    console.log('💾 Saving permissions for user:', id);
    console.log('📝 Permissions:', JSON.stringify(permissions, null, 2));
    
    const result = await db.collection('employee_admins').updateOne(
      { _id: new ObjectId(id) },
      { 
        $set: { 
          permissions,
          permissionsUpdatedAt: new Date(),
          permissionsUpdatedBy: req.user.email || req.user.username
        }
      }
    );
    
    if (result.matchedCount === 0) {
      console.error('❌ User not found');
      return res.status(404).json({ 
        success: false, 
        message: 'User not found' 
      });
    }
    
    console.log('✅ Permissions saved successfully');
    res.json({ success: true, message: 'Permissions updated successfully' });
  } catch (error) {
    console.error('❌ Error saving permissions:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Failed to save permissions', 
      error: error.message 
    });
  }
});

module.exports = router;