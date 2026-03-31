const express = require('express');
const router = express.Router();
const admin = require('../config/firebase');
const { ObjectId } = require('mongodb');

/**
 * GET /api/admin/users
 * Get all users from MongoDB
 * Admin only
 */
router.get('/', async (req, res) => {
  console.log('\n👥 GET ALL USERS (Admin)');
  console.log('─'.repeat(80));
  
  try {
    const db = req.db;
    
    // Check if user is admin
    if (req.user.role !== 'admin') {
      console.log('❌ Access denied - user is not admin');
      return res.status(403).json({
        success: false,
        error: 'Access denied',
        message: 'Admin privileges required'
      });
    }
    
    console.log('   Fetching all users from MongoDB...');
    
    const users = await db.collection('users')
      .find({})
      .sort({ createdAt: -1 })
      .toArray();
    
    console.log(`✅ Found ${users.length} users`);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      count: users.length,
      users: users.map(user => ({
        id: user._id,
        firebaseUid: user.firebaseUid,
        email: user.email,
        name: user.name,
        role: user.role,
        phone: user.phone,
        organizationId: user.organizationId,
        fcmToken: user.fcmToken ? 'Set' : 'Not set',
        isActive: user.isActive !== false,
        createdAt: user.createdAt,
        lastLogin: user.lastLogin
      }))
    });
    
  } catch (error) {
    console.error('❌ GET ALL USERS FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch users',
      message: error.message
    });
  }
});

/**
 * GET /api/admin/users/:userId
 * Get single user by ID
 * Admin only
 */
router.get('/:userId', async (req, res) => {
  console.log('\n👤 GET USER BY ID (Admin)');
  console.log('─'.repeat(80));
  
  try {
    const db = req.db;
    const { userId } = req.params;
    
    // Check if user is admin
    if (req.user.role !== 'admin') {
      console.log('❌ Access denied - user is not admin');
      return res.status(403).json({
        success: false,
        error: 'Access denied',
        message: 'Admin privileges required'
      });
    }
    
    console.log('   User ID:', userId);
    
    // Try to find by MongoDB _id or firebaseUid
    let user;
    if (ObjectId.isValid(userId)) {
      user = await db.collection('users').findOne({ _id: new ObjectId(userId) });
    }
    
    if (!user) {
      user = await db.collection('users').findOne({ firebaseUid: userId });
    }
    
    if (!user) {
      console.log('❌ User not found');
      return res.status(404).json({
        success: false,
        error: 'User not found',
        message: 'User not found in database'
      });
    }
    
    console.log('✅ User found:', user.email);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      user: {
        id: user._id,
        firebaseUid: user.firebaseUid,
        email: user.email,
        name: user.name,
        role: user.role,
        phone: user.phone,
        organizationId: user.organizationId,
        fcmToken: user.fcmToken,
        isActive: user.isActive !== false,
        createdAt: user.createdAt,
        updatedAt: user.updatedAt,
        lastLogin: user.lastLogin
      }
    });
    
  } catch (error) {
    console.error('❌ GET USER FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to fetch user',
      message: error.message
    });
  }
});

/**
 * POST /api/admin/users
 * Create new user (Firebase Auth + MongoDB)
 * Admin only
 */
router.post('/', async (req, res) => {
  console.log('\n➕ CREATE USER (Admin)');
  console.log('─'.repeat(80));
  
  try {
    const db = req.db;
    const { email, password, name, role, phone, organizationId } = req.body;
    
    // Check if user is admin
    if (req.user.role !== 'admin') {
      console.log('❌ Access denied - user is not admin');
      return res.status(403).json({
        success: false,
        error: 'Access denied',
        message: 'Admin privileges required'
      });
    }
    
    console.log('   Email:', email);
    console.log('   Name:', name);
    console.log('   Role:', role);
    
    // Validate required fields
    if (!email || !password || !name || !role) {
      console.log('❌ Missing required fields');
      return res.status(400).json({
        success: false,
        error: 'Missing required fields',
        message: 'email, password, name, and role are required'
      });
    }
    
    // Validate role
    const validRoles = ['admin', 'driver', 'customer', 'client'];
    if (!validRoles.includes(role.toLowerCase())) {
      console.log('❌ Invalid role');
      return res.status(400).json({
        success: false,
        error: 'Invalid role',
        message: `Role must be one of: ${validRoles.join(', ')}`
      });
    }
    
    // Check if user already exists in MongoDB
    const existingUser = await db.collection('users').findOne({ email });
    if (existingUser) {
      console.log('❌ User already exists in MongoDB');
      return res.status(400).json({
        success: false,
        error: 'User already exists',
        message: 'A user with this email already exists'
      });
    }
    
    // Create user in Firebase Auth
    console.log('   Creating user in Firebase Auth...');
    let firebaseUser;
    try {
      firebaseUser = await admin.auth().createUser({
        email,
        password,
        displayName: name,
        emailVerified: false
      });
      console.log('   Firebase user created:', firebaseUser.uid);
    } catch (firebaseError) {
      console.error('❌ Firebase user creation failed:', firebaseError.message);
      return res.status(400).json({
        success: false,
        error: 'Failed to create Firebase user',
        message: firebaseError.message
      });
    }
    
    // Create user in MongoDB
    console.log('   Creating user in MongoDB...');
    const newUser = {
      firebaseUid: firebaseUser.uid,
      email,
      name,
      role: role.toLowerCase(),
      phone: phone || null,
      organizationId: organizationId || null,
      fcmToken: null,
      isActive: true,
      createdAt: new Date(),
      updatedAt: new Date(),
      lastLogin: null
    };
    
    const result = await db.collection('users').insertOne(newUser);
    
    console.log('✅ User created successfully');
    console.log('   MongoDB ID:', result.insertedId);
    console.log('   Firebase UID:', firebaseUser.uid);
    console.log('─'.repeat(80) + '\n');
    
    res.status(201).json({
      success: true,
      message: 'User created successfully',
      user: {
        id: result.insertedId,
        firebaseUid: firebaseUser.uid,
        email,
        name,
        role: role.toLowerCase(),
        phone,
        organizationId,
        createdAt: newUser.createdAt
      }
    });
    
  } catch (error) {
    console.error('❌ CREATE USER FAILED');
    console.error('   Error:', error.message);
    console.error('─'.repeat(80) + '\n');
    
    res.status(500).json({
      success: false,
      error: 'Failed to create user',
      message: error.message
    });
  }
});

/**
 * PUT /api/admin/users/:userId
 * Update user (MongoDB only, not Firebase Auth)
 * Admin only
 */
router.put('/:userId', async (req, res) => {
  console.log('\n✏️  UPDATE USER (Admin)');
  console.log('─'.repeat(80));
  
  try {
    const db = req.db;
    const { userId } = req.params;
    const { name, role, phone, organizationId, isActive } = req.body;
    
    // Check if user is admin
    if (req.user.role !== 'admin') {
      console.log('❌ Access denied - user is not admin');
      return res.status(403).json({
        success: false,
        error: 'Access denied',
        message: 'Admin privileges required'
      });
    }
    
    console.log('   User ID:', userId);
    console.log('   Update data:', { name, role, phone, organizationId, isActive });
    
    // Build update object
    const updateData = {
      updatedAt: new Date()
    };
    
    if (name !== undefined) updateData.name = name;
    if (phone !== undefined) updateData.phone = phone;
    if (organizationId !== undefined) updateData.organizationId = organizationId;
    if (isActive !== undefined) updateData.isActive = isActive;
    
    // Validate and update role
    if (role !== undefined) {
      const validRoles = ['admin', 'driver', 'customer', 'client'];
      if (!validRoles.includes(role.toLowerCase())) {
        console.log('❌ Invalid role');
        return res.status(400).json({
          success: false,
          error: 'Invalid role',
          message: `Role must be one of: ${validRoles.join(', ')}`
        });
      }
      updateData.role = role.toLowerCase();
    }
    
    // Update in MongoDB
    let result;
    if (ObjectId.isValid(userId)) {
      result = await db.collection('users').updateOne(
        { _id: new ObjectId(userId) },
        { $set: updateData }
      );
    } else {
      result = await db.collection('users').updateOne(
        { firebaseUid: userId },
        { $set: updateData }
      );
    }
    
    if (result.matchedCount === 0) {
      console.log('❌ User not found');
      return res.status(404).json({
        success: false,
        error: 'User not found',
        message: 'User not found in database'
      });
    }
    
    // Fetch updated user
    let user;
    if (ObjectId.isValid(userId)) {
      user = await db.collection('users').findOne({ _id: new ObjectId(userId) });
    } else {
      user = await db.collection('users').findOne({ firebaseUid: userId });
    }
    
    console.log('✅ User updated successfully');
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      message: 'User updated successfully',
      user: {
        id: user._id,
        firebaseUid: user.firebaseUid,
        email: user.email,
        name: user.name,
        role: user.role,
        phone: user.phone,
        organizationId: user.organizationId,
        isActive: user.isActive,
        updatedAt: user.updatedAt
      }
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

/**
 * DELETE /api/admin/users/:userId
 * Delete user (Firebase Auth + MongoDB)
 * Admin only
 */
router.delete('/:userId', async (req, res) => {
  console.log('\n🗑️  DELETE USER (Admin)');
  console.log('─'.repeat(80));
  
  try {
    const db = req.db;
    const { userId } = req.params;
    
    // Check if user is admin
    if (req.user.role !== 'admin') {
      console.log('❌ Access denied - user is not admin');
      return res.status(403).json({
        success: false,
        error: 'Access denied',
        message: 'Admin privileges required'
      });
    }
    
    console.log('   User ID:', userId);
    
    // Find user first
    let user;
    if (ObjectId.isValid(userId)) {
      user = await db.collection('users').findOne({ _id: new ObjectId(userId) });
    } else {
      user = await db.collection('users').findOne({ firebaseUid: userId });
    }
    
    if (!user) {
      console.log('❌ User not found');
      return res.status(404).json({
        success: false,
        error: 'User not found',
        message: 'User not found in database'
      });
    }
    
    // Prevent deleting yourself
    if (user.firebaseUid === req.user.email) {
      console.log('❌ Cannot delete yourself');
      return res.status(400).json({
        success: false,
        error: 'Cannot delete yourself',
        message: 'You cannot delete your own account'
      });
    }
    
    console.log('   Deleting user:', user.email);
    
    // Delete from Firebase Auth
    try {
      await admin.auth().deleteUser(user.firebaseUid);
      console.log('   Deleted from Firebase Auth');
    } catch (firebaseError) {
      console.warn('   Warning: Firebase deletion failed:', firebaseError.message);
      // Continue with MongoDB deletion even if Firebase fails
    }
    
    // Delete from MongoDB
    await db.collection('users').deleteOne({ _id: user._id });
    console.log('   Deleted from MongoDB');
    
    console.log('✅ User deleted successfully');
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

module.exports = router;
