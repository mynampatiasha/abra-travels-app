// routes/user_role_management.js
// ============================================================================
// USER ROLE & PERMISSION MANAGEMENT API
// ============================================================================
// Complete backend for managing admin users and their navigation permissions
// Uses separate EmployeeAdmin model from regular User model
// Integrates with Flutter's NavigationConfig for centralized permission control

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const EmployeeAdmin = require('../models/EmployeeAdmin');
 

// ============================================================================
// NAVIGATION CONFIGURATION (Mirror of Flutter's navigation_config.dart)
// ============================================================================
const NAVIGATION_CONFIG = {
  // ========== Core ==========
  dashboard: { 
    title: 'Dashboard', 
    category: 'Core', 
    index: 0,
    description: 'Main dashboard with overview and analytics'
  },
  
  // ========== Fleet Management (Parent) ==========
  fleet_management: { 
    title: 'Fleet Management', 
    category: 'Fleet', 
    isParent: true,
    description: 'Complete vehicle fleet management'
  },
  fleet_vehicles: { 
    title: 'Vehicle Master', 
    category: 'Fleet', 
    parent: 'fleet_management', 
    index: 11,
    description: 'Add, edit, delete vehicles'
  },
  fleet_trips: { 
    title: 'Trip Operation', 
    category: 'Fleet', 
    parent: 'fleet_management', 
    index: 12,
    description: 'Start trips, route planning, trip management'
  },
  fleet_gps_tracking: { 
    title: 'GPS Tracking', 
    category: 'Fleet', 
    parent: 'fleet_management', 
    index: 25,
    description: 'Real-time vehicle tracking and monitoring'
  },
  fleet_maintenance: { 
    title: 'Maintenance Management', 
    category: 'Fleet', 
    parent: 'fleet_management', 
    index: 13,
    description: 'Schedule and track vehicle maintenance'
  },
  fleet_list: { 
    title: 'Fleet Map View', 
    category: 'Fleet', 
    index: 5,
    description: 'Real-time fleet tracking on map'
  },
  
  // ========== Drivers ==========
  fleet_drivers: { 
    title: 'Drivers', 
    category: 'Fleet', 
    index: 1,
    description: 'Driver management and monitoring'
  },
  
  // ========== Customer Management (Parent) ==========
  customer_fleet: { 
    title: 'Customer Management', 
    category: 'Customers', 
    isParent: true,
    description: 'Customer and employee management'
  },
  all_customers: {
    title: 'All Customers',
    category: 'Customers',
    parent: 'customer_fleet',
    index: 15,
    description: 'View and manage all customers'
  },
  pending_approvals: {
    title: 'Pending Approvals',
    category: 'Customers',
    parent: 'customer_fleet',
    index: 16,
    description: 'Approve new customer registrations'
  },
  pending_rosters: {
    title: 'Pending Rosters',
    category: 'Customers',
    parent: 'customer_fleet',
    index: 17,
    description: 'Review and assign roster requests'
  },
  approved_rosters: {
    title: 'Approved Rosters',
    category: 'Customers',
    parent: 'customer_fleet',
    index: 18,
    description: 'Manage approved roster assignments'
  },
  trip_cancellation: {
    title: 'Trip Cancellation',
    category: 'Customers',
    parent: 'customer_fleet',
    index: 19,
    description: 'Handle trip cancellations and leaves'
  },
  
  // ========== Client Management (Parent) ==========
  abra_global_trading: { 
    title: 'Client Management', 
    category: 'Clients', 
    isParent: true, 
    index: 20,
    description: 'Corporate client management'
  },
  abra_food_works: { 
    title: 'Abra Food Works', 
    category: 'Clients', 
    parent: 'abra_global_trading',
    description: 'Abra Food Works client management'
  },
  client_details: {
    title: 'Client Details',
    category: 'Clients',
    parent: 'abra_global_trading',
    index: 20,
    description: 'Manage client accounts and details'
  },
  billing_invoices: {
    title: 'Billing & Invoices',
    category: 'Clients',
    parent: 'abra_global_trading',
    index: 21,
    description: 'Invoices, payments, and billing'
  },
  trips: {
    title: 'Trips',
    category: 'Clients',
    parent: 'abra_global_trading',
    index: 22,
    description: 'Client trip scheduling and management'
  },
  
  // ========== Reports ==========
  reports: { 
    title: 'Reports', 
    category: 'Reports', 
    index: 6,
    description: 'Generate system reports and analytics'
  },
  
  // ========== Emergency (Parent) ==========
  sos_alerts: { 
    title: 'SOS Alerts', 
    category: 'Emergency', 
    isParent: true,
    description: 'Emergency SOS alert management'
  },
  incomplete_alerts: {
    title: 'Incomplete Alerts',
    category: 'Emergency',
    parent: 'sos_alerts',
    index: 8,
    description: 'Handle active SOS emergency alerts'
  },
  resolved_alerts: {
    title: 'Resolved Alerts',
    category: 'Emergency',
    parent: 'sos_alerts',
    index: 7,
    description: 'View resolved SOS alerts history'
  },
  
  // ========== HRM Portal (Parent) ==========
  hrm_feedback: { 
    title: 'HRM Portal', 
    category: 'HRM', 
    isParent: true,
    description: 'Human Resource Management'
  },
  hrm_employees: {
    title: 'Employees',
    category: 'HRM',
    parent: 'hrm_feedback',
    index: 32,
    description: 'Employee management and records'
  },
  hrm_departments: {
    title: 'Departments',
    category: 'HRM',
    parent: 'hrm_feedback',
    index: 33,
    description: 'Department management and structure'
  },
  hrm_leave_requests: {
    title: 'Leave Requests',
    category: 'HRM',
    parent: 'hrm_feedback',
    index: 34,
    description: 'Employee leave request management'
  },
  notice_board: {
    title: 'Notice Board',
    category: 'HRM',
    parent: 'hrm_feedback',
    index: 30,
    description: 'Company announcements and notices'
  },
  attendance: {
    title: 'Attendance',
    category: 'HRM',
    parent: 'hrm_feedback',
    index: 31,
    description: 'Employee attendance tracking'
  },
  
  // ========== Feedback (Parent) ==========
  feedback: {
    title: 'Feedback',
    category: 'Feedback',
    isParent: true,
    description: 'Feedback from customers, drivers, and clients'
  },
  customer_feedback: {
    title: 'Customer Feedback',
    category: 'Feedback',
    parent: 'feedback',
    index: 27,
    description: 'View and manage customer feedback'
  },
  driver_feedback: {
    title: 'Driver Feedback',
    category: 'Feedback',
    parent: 'feedback',
    index: 28,
    description: 'View and manage driver feedback'
  },
  client_feedback: {
    title: 'Client Feedback',
    category: 'Feedback',
    parent: 'feedback',
    index: 29,
    description: 'View and manage client feedback'
  },
  
  // ========== Administration ==========
  role_access_control: { 
    title: 'Role Access Control', 
    category: 'Administration', 
    index: 24,
    description: 'Manage user roles and permissions'
  },
};

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/**
 * Get all navigation items sorted by category and index
 */
function getAllNavigationItems() {
  return Object.entries(NAVIGATION_CONFIG)
    .map(([key, config]) => ({
      key,
      title: config.title,
      category: config.category,
      index: config.index || 999,
      isParent: config.isParent || false,
      parent: config.parent || null,
      description: config.description || '',
    }))
    .sort((a, b) => {
      // Sort by category first, then by index
      if (a.category !== b.category) {
        return a.category.localeCompare(b.category);
      }
      return a.index - b.index;
    });
}

/**
 * Initialize default permissions for new admin user
 * Only dashboard access is granted by default
 */
function getDefaultPermissions() {
  const permissions = {};
  Object.keys(NAVIGATION_CONFIG).forEach(key => {
    permissions[key] = {
      can_access: key === 'dashboard', // Only dashboard is true by default
      edit_delete: false,
    };
  });
  return permissions;
}

/**
 * Validate permission structure
 */
function validatePermissions(permissions) {
  if (!permissions || typeof permissions !== 'object') {
    return false;
  }
  
  // Check if all keys are valid navigation keys
  for (const key in permissions) {
    if (!NAVIGATION_CONFIG[key]) {
      console.warn(`⚠️  Unknown permission key: ${key}`);
      continue;
    }
    
    const perm = permissions[key];
    if (typeof perm !== 'object' || 
        typeof perm.can_access !== 'boolean' || 
        typeof perm.edit_delete !== 'boolean') {
      return false;
    }
  }
  
  return true;
}

/**
 * Sanitize admin user data for response
 */
function sanitizeEmployeeAdmin(user) {
  const userObj = user.toObject ? user.toObject() : user;
  
  // Convert Map to plain object if needed
  let permissions = userObj.permissions;
  if (permissions instanceof Map) {
    const permObj = {};
    permissions.forEach((value, key) => {
      permObj[key] = value;
    });
    permissions = permObj;
  } else if (typeof permissions === 'object' && permissions !== null) {
    // Already a plain object, use as-is
    permissions = permissions;
  } else {
    // Fallback to default permissions
    permissions = getDefaultPermissions();
  }
  
  return {
    id: userObj._id.toString(),
    name_parson: userObj.name_parson,
    name: userObj.name,
    email: userObj.email,
    phone: userObj.phone || '',
    role: userObj.role,
    isActive: userObj.isActive,
    office: userObj.office || '',
    department: userObj.department || '',
    permissions: permissions,
    createdAt: userObj.createdAt,
    updatedAt: userObj.updatedAt,
    lastLogin: userObj.lastLogin,
  };
}

/**
 * Convert plain object permissions to Map
 */
function permissionsToMap(permissions) {
  const permissionsMap = new Map();
  Object.entries(permissions).forEach(([key, value]) => {
    permissionsMap.set(key, {
      can_access: value.can_access || false,
      edit_delete: value.edit_delete || false,
    });
  });
  return permissionsMap;
}

// ============================================================================
// MIDDLEWARE - Permission Checking
// ============================================================================

/**
 * Check if current user has permission to manage users
 */
function checkPermission(requiredPermission) {
  return async (req, res, next) => {
    try {
      // Get current user's email from JWT
      const currentUserEmail = req.user?.email;
      if (!currentUserEmail) {
        return res.status(401).json({
          success: false,
          error: 'Unauthorized',
          message: 'User not authenticated',
        });
      }

      // Find current admin user in database
      const currentUser = await EmployeeAdmin.findOne({ email: currentUserEmail });

      if (!currentUser) {
        return res.status(404).json({
          success: false,
          error: 'Admin user not found',
          message: 'Current user not found in admin database',
        });
      }

      // Check if account is active
      if (!currentUser.isActive) {
        return res.status(403).json({
          success: false,
          error: 'Account inactive',
          message: 'Your account is currently inactive',
        });
      }

      // Check if user has required permission using model method
      const hasPermission = currentUser.hasPermission(requiredPermission);

      if (!hasPermission) {
        return res.status(403).json({
          success: false,
          error: 'Forbidden',
          message: `You don't have permission to access ${requiredPermission}`,
        });
      }

      // Attach current admin user to request for later use
      req.currentEmployeeAdmin = currentUser;
      next();
    } catch (error) {
      console.error('❌ Permission check failed:', error);
      res.status(500).json({
        success: false,
        error: 'Permission check failed',
        message: error.message,
      });
    }
  };
}

// ============================================================================
// ROUTES - Admin User Management
// ============================================================================

/**
 * GET /api/user-management/users
 * Get all admin users with their permissions
 */
router.get('/users', checkPermission('role_access_control'), async (req, res) => {
  console.log('\n📋 GET ALL ADMIN USERS');
  console.log('─'.repeat(80));

  try {
    const users = await EmployeeAdmin.find({})
      .select('-pwd')
      .sort({ createdAt: -1 })
      .lean();

    console.log(`✅ Found ${users.length} admin users`);

    res.json({
      success: true,
      message: 'Admin users retrieved successfully',
      data: users.map(sanitizeEmployeeAdmin),
      count: users.length,
    });
  } catch (error) {
    console.error('❌ Failed to get admin users:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve admin users',
      message: error.message,
    });
  }
});

/**
 * GET /api/user-management/users/:id
 * Get single admin user with permissions
 */
router.get('/users/:id', checkPermission('role_access_control'), async (req, res) => {
  console.log('\n👤 GET ADMIN USER BY ID');
  console.log('─'.repeat(80));

  try {
    const userId = req.params.id;
    console.log('   User ID:', userId);

    // Validate ObjectId
    if (!ObjectId.isValid(userId)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid user ID',
        message: 'The provided user ID is not valid',
      });
    }

    const user = await EmployeeAdmin.findById(userId).select('-pwd').lean();

    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'Admin user not found',
        message: 'Admin user with this ID does not exist',
      });
    }

    console.log('✅ Admin user found:', user.name);

    res.json({
      success: true,
      message: 'Admin user retrieved successfully',
      data: sanitizeEmployeeAdmin(user),
    });
  } catch (error) {
    console.error('❌ Failed to get admin user:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve admin user',
      message: error.message,
    });
  }
});

/**
 * POST /api/user-management/users
 * Create new admin user with permissions
 */
/**
 * POST /api/user-management/users
 * Create new admin user with permissions
 */
router.post('/users', checkPermission('role_access_control'), async (req, res) => {
  console.log('\n➕ CREATE NEW ADMIN USER');
  console.log('─'.repeat(80));

  try {
    const { name_parson, name, email, phone, pwd, permissions, office, department } = req.body;

    // Validate required fields
    if (!name_parson || !name || !email || !pwd) {
      return res.status(400).json({
        success: false,
        error: 'Validation failed',
        message: 'Missing required fields: name_parson, name, email, pwd',
      });
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid email',
        message: 'Please provide a valid email address',
      });
    }

    // Validate password length
    if (pwd.length < 6) {
      return res.status(400).json({
        success: false,
        error: 'Weak password',
        message: 'Password must be at least 6 characters long',
      });
    }

    console.log('   Creating admin user:', email);

    // Check if admin user already exists in MongoDB
    const existingUser = await EmployeeAdmin.findOne({ email: email.toLowerCase() });
    if (existingUser) {
      return res.status(409).json({
        success: false,
        error: 'Admin user already exists',
        message: 'An admin user with this email already exists',
      });
    }

    // Check if username already exists
    const existingUsername = await EmployeeAdmin.findOne({ name: name });
    if (existingUsername) {
      return res.status(409).json({
        success: false,
        error: 'Username already exists',
        message: 'This username is already taken',
      });
    }

    // Validate permissions if provided
    let userPermissions = permissions || getDefaultPermissions();
    if (!validatePermissions(userPermissions)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid permissions',
        message: 'Permission structure is invalid',
      });
    }

    // Create permissions Map
    const permissionsMap = permissionsToMap(userPermissions);

    // 🔥 STEP 1: CREATE USER IN FIREBASE AUTH FIRST
    console.log('   Creating Firebase Auth account...');
    let firebaseUser;
    try {
      firebaseUser = await admin.auth().createUser({
        email: email.toLowerCase(),
        password: pwd, // Firebase will hash this
        displayName: name_parson,
      });
      console.log('   ✅ Firebase user created:', firebaseUser.uid);
    } catch (firebaseError) {
      console.error('   ❌ Firebase user creation failed:', firebaseError);
      
      // Handle Firebase-specific errors
      if (firebaseError.code === 'auth/email-already-exists') {
        return res.status(409).json({
          success: false,
          error: 'Email already exists in Firebase',
          message: 'This email is already registered in the system',
        });
      }
      
      return res.status(500).json({
        success: false,
        error: 'Firebase user creation failed',
        message: firebaseError.message,
      });
    }

    // 🔥 STEP 2: CREATE USER IN MONGODB WITH FIREBASE UID
    console.log('   Creating MongoDB admin user...');
    const newUser = new EmployeeAdmin({
      name_parson,
      name,
      email: email.toLowerCase(),
      phone: phone || '',
      pwd, // Will be hashed by pre-save hook
      permissions: permissionsMap,
      office: office || '',
      department: department || '',
      role: 'employee',
      isActive: true,
      createdBy: req.currentEmployeeAdmin?._id,
      firebaseUid: firebaseUser.uid, // 🔥 LINK TO FIREBASE ACCOUNT
    });

    await newUser.save();

    console.log('✅ Admin user created successfully in both Firebase and MongoDB');
    console.log('   Email:', newUser.email);
    console.log('   Firebase UID:', firebaseUser.uid);

    res.status(201).json({
      success: true,
      message: 'Admin user created successfully',
      data: sanitizeEmployeeAdmin(newUser),
    });
  } catch (error) {
    console.error('❌ Failed to create admin user:', error);
    
    // Handle duplicate key errors
    if (error.code === 11000) {
      const field = Object.keys(error.keyPattern)[0];
      return res.status(409).json({
        success: false,
        error: 'Duplicate entry',
        message: `This ${field} is already registered`,
      });
    }
    
    res.status(500).json({
      success: false,
      error: 'Failed to create admin user',
      message: error.message,
    });
  }
});

/**
 * PUT /api/user-management/users/:id
 * Update admin user details (not permissions)
 */
router.put('/users/:id', checkPermission('role_access_control'), async (req, res) => {
  console.log('\n✏️  UPDATE ADMIN USER');
  console.log('─'.repeat(80));

  try {
    const userId = req.params.id;
    const { name_parson, name, email, phone, isActive, office, department } = req.body;

    console.log('   Updating admin user:', userId);

    // Validate ObjectId
    if (!ObjectId.isValid(userId)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid user ID',
        message: 'The provided user ID is not valid',
      });
    }

    const user = await AdminUser.findById(userId);

    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'Admin user not found',
        message: 'Admin user with this ID does not exist',
      });
    }

    // Update fields
    if (name_parson) user.name_parson = name_parson;
    
    if (name) {
      // Check if new username is already taken by another user
      const existingUsername = await EmployeeAdmin.findOne({ 
        name: name,
        _id: { $ne: userId }
      });
      if (existingUsername) {
        return res.status(409).json({
          success: false,
          error: 'Username already exists',
          message: 'This username is already taken',
        });
      }
      user.name = name;
    }
    
    if (email) {
      // Validate email format
      const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
      if (!emailRegex.test(email)) {
        return res.status(400).json({
          success: false,
          error: 'Invalid email',
          message: 'Please provide a valid email address',
        });
      }
      
      // Check if new email is already taken by another user
      const existingEmail = await EmployeeAdmin.findOne({ 
        email: email.toLowerCase(),
        _id: { $ne: userId }
      });
      if (existingEmail) {
        return res.status(409).json({
          success: false,
          error: 'Email already exists',
          message: 'This email is already registered',
        });
      }
      
      user.email = email.toLowerCase();
    }
    
    if (phone !== undefined) user.phone = phone;
    if (isActive !== undefined) user.isActive = isActive;
    if (office !== undefined) user.office = office;
    if (department !== undefined) user.department = department;

    await user.save();

    console.log('✅ Admin user updated successfully:', user.email);

    res.json({
      success: true,
      message: 'Admin user updated successfully',
      data: sanitizeEmployeeAdmin(user),
    });
  } catch (error) {
    console.error('❌ Failed to update admin user:', error);
    
    // Handle duplicate key errors
    if (error.code === 11000) {
      const field = Object.keys(error.keyPattern)[0];
      return res.status(409).json({
        success: false,
        error: 'Duplicate entry',
        message: `This ${field} is already registered`,
      });
    }
    
    res.status(500).json({
      success: false,
      error: 'Failed to update admin user',
      message: error.message,
    });
  }
});

/**
 * PUT /api/user-management/users/:id/permissions
 * Update admin user permissions
 */
router.put('/users/:id/permissions', checkPermission('role_access_control'), async (req, res) => {
  console.log('\n🔐 UPDATE ADMIN USER PERMISSIONS');
  console.log('─'.repeat(80));

  try {
    const userId = req.params.id;
    const { permissions } = req.body;

    console.log('   Updating permissions for admin user:', userId);

    // Validate ObjectId
    if (!ObjectId.isValid(userId)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid user ID',
        message: 'The provided user ID is not valid',
      });
    }

    if (!permissions) {
      return res.status(400).json({
        success: false,
        error: 'Missing permissions',
        message: 'Permissions object is required',
      });
    }

    if (!validatePermissions(permissions)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid permissions',
        message: 'Permission structure is invalid',
      });
    }

    const user = await EmployeeAdmin.findById(userId);

    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'Admin user not found',
        message: 'Admin user with this ID does not exist',
      });
    }

    // Convert permissions object to Map
    const permissionsMap = permissionsToMap(permissions);

    // Update permissions
    user.permissions = permissionsMap;

    await user.save();

    console.log('✅ Permissions updated successfully');
    console.log('   Total permissions:', permissionsMap.size);
    console.log('   Active permissions:', 
      Array.from(permissionsMap.values()).filter(p => p.can_access).length
    );

    res.json({
      success: true,
      message: 'Permissions updated successfully',
      data: sanitizeEmployeeAdmin(user),
    });
  } catch (error) {
    console.error('❌ Failed to update permissions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update permissions',
      message: error.message,
    });
  }
});

/**
 * DELETE /api/user-management/users/:id
 * Delete admin user
 */
router.delete('/users/:id', checkPermission('role_access_control'), async (req, res) => {
  console.log('\n🗑️  DELETE ADMIN USER');
  console.log('─'.repeat(80));

  try {
    const userId = req.params.id;
    console.log('   Deleting admin user:', userId);

    // Validate ObjectId
    if (!ObjectId.isValid(userId)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid user ID',
        message: 'The provided user ID is not valid',
      });
    }

    const user = await EmployeeAdmin.findById(userId);

    if (!user) {
      return res.status(404).json({
        success: false,
        error: 'Admin user not found',
        message: 'Admin user with this ID does not exist',
      });
    }

    // Prevent deletion of current user
    if (user.email === req.user?.email) {
      return res.status(403).json({
        success: false,
        error: 'Cannot delete self',
        message: 'You cannot delete your own account',
      });
    }

    // Prevent deletion of super admin (optional safety measure)
    if (user.role === 'super_admin') {
      return res.status(403).json({
        success: false,
        error: 'Cannot delete super admin',
        message: 'Super admin accounts cannot be deleted',
      });
    }

    await EmployeeAdmin.findByIdAndDelete(userId);

    console.log('✅ Admin user deleted successfully:', user.email);

    res.json({
      success: true,
      message: 'Admin user deleted successfully',
      data: {
        deletedUserId: userId,
        deletedUserEmail: user.email,
        deletedUserName: user.name_parson,
      },
    });
  } catch (error) {
    console.error('❌ Failed to delete admin user:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete admin user',
      message: error.message,
    });
  }
});

// ============================================================================
// ROUTES - Navigation & Permission Configuration
// ============================================================================

/**
 * GET /api/user-management/navigation-config
 * Get all navigation items for permission UI
 */
router.get('/navigation-config', checkPermission('role_access_control'), async (req, res) => {
  console.log('\n🧭 GET NAVIGATION CONFIG');
  console.log('─'.repeat(80));

  try {
    const navigationItems = getAllNavigationItems();

    console.log(`✅ Returning ${navigationItems.length} navigation items`);

    res.json({
      success: true,
      message: 'Navigation configuration retrieved successfully',
      data: navigationItems,
      count: navigationItems.length,
    });
  } catch (error) {
    console.error('❌ Failed to get navigation config:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve navigation config',
      message: error.message,
    });
  }
});

/**
 * GET /api/user-management/default-permissions
 * Get default permission structure for new users
 */
router.get('/default-permissions', async (req, res) => {
  console.log('\n🔐 GET DEFAULT PERMISSIONS');
  console.log('─'.repeat(80));

  try {
    const defaultPermissions = getDefaultPermissions();

    console.log(`✅ Returning ${Object.keys(defaultPermissions).length} default permissions`);

    res.json({
      success: true,
      message: 'Default permissions retrieved successfully',
      data: defaultPermissions,
      count: Object.keys(defaultPermissions).length,
    });
  } catch (error) {
    console.error('❌ Failed to get default permissions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve default permissions',
      message: error.message,
    });
  }
});

/**
 * GET /api/user-management/stats
 * Get admin user statistics
 */
router.get('/stats', checkPermission('role_access_control'), async (req, res) => {
  console.log('\n📊 GET ADMIN USER STATS');
  console.log('─'.repeat(80));

  try {
    const totalUsers = await EmployeeAdmin.countDocuments();
    const activeUsers = await EmployeeAdmin.countDocuments({ isActive: true });
    const inactiveUsers = await EmployeeAdmin.countDocuments({ isActive: false });
    
    const usersByRole = await EmployeeAdmin.aggregate([
      {
        $group: {
          _id: '$role',
          count: { $sum: 1 }
        }
      }
    ]);

    console.log('✅ Stats retrieved successfully');

    res.json({
      success: true,
      message: 'Statistics retrieved successfully',
      data: {
        total: totalUsers,
        active: activeUsers,
        inactive: inactiveUsers,
        byRole: usersByRole.reduce((acc, item) => {
          acc[item._id] = item.count;
          return acc;
        }, {}),
      },
    });
  } catch (error) {
    console.error('❌ Failed to get stats:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve statistics',
      message: error.message,
    });
  }
});

// ============================================================================
// EXPORT
// ============================================================================

module.exports = {
  router,
  checkPermission,
  NAVIGATION_CONFIG,
  getAllNavigationItems,
  getDefaultPermissions,
  sanitizeEmployeeAdmin,
  validatePermissions,
};