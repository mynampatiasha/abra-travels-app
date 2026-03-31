// models/AdminUser.js
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

// ============================================================================
// ADMIN USER MODEL - For Admin Panel Access Only
// ============================================================================
// This is separate from the regular User model
// Used for managing admin panel permissions and access control

const adminUserSchema = new mongoose.Schema({
  // Basic Information
  name_parson: {
    type: String,
    required: true,
    trim: true
  },
  name: {
    type: String,
    required: true,
    trim: true,
    unique: true
  },
  email: {
    type: String,
    required: true,
    unique: true,
    lowercase: true,
    trim: true
  },
  phone: {
    type: String,
    trim: true,
    default: ''
  },
  pwd: {
    type: String,
    required: true
  },
  
  // Firebase Integration
  firebaseUid: {
    type: String,
    unique: true,
    sparse: true
  },
  
  // Role & Status
  role: {
    type: String,
    enum: ['super_admin', 'admin', 'employee', 'manager'],
    default: 'employee'
  },
  isActive: {
    type: Boolean,
    default: true
  },
  
  // Navigation-Based Permissions
  // Each key corresponds to a navigation item from NavigationConfig
  permissions: {
    type: Map,
    of: {
      can_access: { type: Boolean, default: false },
      edit_delete: { type: Boolean, default: false }
    },
    default: {}
  },
  
  // Office & Department (Optional)
  office: {
    type: String,
    default: ''
  },
  department: {
    type: String,
    default: ''
  },
  
  // Tracking
  createdBy: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'AdminUser'
  },
  lastLogin: {
    type: Date
  },
  loginAttempts: {
    type: Number,
    default: 0
  },
  lockUntil: {
    type: Date
  }
}, {
  timestamps: true, // Adds createdAt and updatedAt
  collection: 'admin_users' // Separate collection from regular users
});

// ============================================================================
// INDEXES
// ============================================================================
adminUserSchema.index({ email: 1 });
adminUserSchema.index({ name: 1 });
adminUserSchema.index({ firebaseUid: 1 });
adminUserSchema.index({ isActive: 1 });

// ============================================================================
// VIRTUALS
// ============================================================================
adminUserSchema.virtual('isLocked').get(function() {
  return !!(this.lockUntil && this.lockUntil > Date.now());
});

// ============================================================================
// PRE-SAVE HOOKS
// ============================================================================

// Hash password before saving
adminUserSchema.pre('save', async function(next) {
  // Only hash if password is new or modified
  if (!this.isModified('pwd')) return next();
  
  try {
    const salt = await bcrypt.genSalt(10);
    this.pwd = await bcrypt.hash(this.pwd, salt);
    next();
  } catch (error) {
    next(error);
  }
});

// Initialize default permissions for new users
adminUserSchema.pre('save', function(next) {
  if (this.isNew && (!this.permissions || this.permissions.size === 0)) {
    // Set dashboard access by default
    this.permissions = new Map();
    this.permissions.set('dashboard', {
      can_access: true,
      edit_delete: false
    });
  }
  next();
});

// ============================================================================
// INSTANCE METHODS
// ============================================================================

/**
 * Compare password during login
 */
adminUserSchema.methods.comparePassword = async function(candidatePassword) {
  return await bcrypt.compare(candidatePassword, this.pwd);
};

/**
 * Check if user has specific permission
 * ✅ UPDATED: Added safety checks for undefined permissions
 */
adminUserSchema.methods.hasPermission = function(permissionKey) {
  // Super admin has all permissions
  if (this.role === 'super_admin') return true;
  
  // Check if account is active
  if (!this.isActive) return false;
  
  // Check if account is locked
  if (this.isLocked) return false;
  
  // ✅ SAFETY CHECK: Ensure permissions exists
  if (!this.permissions) {
    console.warn('⚠️  User has no permissions object:', this.email);
    return false;
  }
  
  // Handle both Map and plain object
  let permission;
  if (this.permissions instanceof Map) {
    permission = this.permissions.get(permissionKey);
  } else if (typeof this.permissions === 'object') {
    permission = this.permissions[permissionKey];
  } else {
    console.warn('⚠️  Invalid permissions type:', typeof this.permissions);
    return false;
  }
  
  return permission && permission.can_access === true;
};

/**
 * Check if user can edit/delete in a module
 * ✅ UPDATED: Added safety checks for undefined permissions
 */
adminUserSchema.methods.canEditDelete = function(permissionKey) {
  // Super admin can do everything
  if (this.role === 'super_admin') return true;
  
  // Check if account is active
  if (!this.isActive) return false;
  
  // ✅ SAFETY CHECK: Ensure permissions exists
  if (!this.permissions) {
    console.warn('⚠️  User has no permissions object:', this.email);
    return false;
  }
  
  // Handle both Map and plain object
  let permission;
  if (this.permissions instanceof Map) {
    permission = this.permissions.get(permissionKey);
  } else if (typeof this.permissions === 'object') {
    permission = this.permissions[permissionKey];
  } else {
    console.warn('⚠️  Invalid permissions type:', typeof this.permissions);
    return false;
  }
  
  return permission && permission.edit_delete === true;
};

/**
 * Get all accessible navigation keys
 * ✅ UPDATED: Added safety checks for undefined permissions
 */
adminUserSchema.methods.getAccessibleNavigationKeys = function() {
  // ✅ SAFETY CHECK
  if (!this.permissions) {
    console.warn('⚠️  User has no permissions object:', this.email);
    return [];
  }
  
  if (this.role === 'super_admin') {
    // Return all possible navigation keys
    if (this.permissions instanceof Map) {
      return Array.from(this.permissions.keys());
    } else {
      return Object.keys(this.permissions);
    }
  }
  
  const accessible = [];
  
  if (this.permissions instanceof Map) {
    this.permissions.forEach((value, key) => {
      if (value.can_access) {
        accessible.push(key);
      }
    });
  } else if (typeof this.permissions === 'object') {
    Object.entries(this.permissions).forEach(([key, value]) => {
      if (value.can_access) {
        accessible.push(key);
      }
    });
  }
  
  return accessible;
};

/**
 * Record login attempt
 */
adminUserSchema.methods.recordLoginAttempt = async function(success) {
  if (success) {
    this.loginAttempts = 0;
    this.lastLogin = new Date();
    this.lockUntil = undefined;
  } else {
    this.loginAttempts += 1;
    
    // Lock account after 5 failed attempts
    if (this.loginAttempts >= 5) {
      this.lockUntil = new Date(Date.now() + 30 * 60 * 1000); // Lock for 30 minutes
    }
  }
  
  await this.save();
};

/**
 * Grant super admin permissions
 */
adminUserSchema.methods.grantSuperAdminPermissions = function() {
  const allPermissions = [
    'dashboard',
    'fleet_management',
    'fleet_vehicles',
    'fleet_drivers',
    'fleet_trips',
    'fleet_gps_tracking',
    'fleet_maintenance',
    'fleet_list',
    'customer_fleet',
    'all_customers',
    'pending_approvals',
    'pending_rosters',
    'approved_rosters',
    'trip_cancellation',
    'abra_global_trading',
    'abra_food_works',
    'client_details',
    'billing_invoices',
    'trips',
    'reports',
    'sos_alerts',
    'incomplete_alerts',
    'resolved_alerts',
    'hrm_feedback',
    'hrm_employees',
    'hrm_departments',
    'hrm_leave_requests',
    'notice_board',
    'attendance',
    'feedback',
    'customer_feedback',
    'driver_feedback',
    'client_feedback',
    'role_access_control',
  ];
  
  this.permissions = new Map();
  allPermissions.forEach(key => {
    this.permissions.set(key, {
      can_access: true,
      edit_delete: true
    });
  });
};

// ============================================================================
// STATIC METHODS
// ============================================================================

/**
 * Find user by email (case-insensitive)
 */
adminUserSchema.statics.findByEmail = function(email) {
  return this.findOne({ email: email.toLowerCase() });
};

/**
 * Find user by username
 */
adminUserSchema.statics.findByUsername = function(username) {
  return this.findOne({ name: username });
};

/**
 * Find active users only
 */
adminUserSchema.statics.findActive = function() {
  return this.find({ isActive: true });
};

/**
 * Count users by role
 */
adminUserSchema.statics.countByRole = function(role) {
  return this.countDocuments({ role: role });
};

// ============================================================================
// EXPORT
// ============================================================================
module.exports = mongoose.model('AdminUser', adminUserSchema);

// ============================================================================
// EXAMPLE ADMIN USER DOCUMENT IN MONGODB:
// ============================================================================
/*
{
  "_id": ObjectId("507f1f77bcf86cd799439011"),
  "name_parson": "John Doe",
  "name": "johndoe",
  "email": "john@abrafleet.com",
  "phone": "+91 9876543210",
  "pwd": "$2a$10$hashed_password_here",
  "firebaseUid": "firebase_uid_12345",
  "role": "admin",
  "isActive": true,
  "permissions": {
    "dashboard": {
      "can_access": true,
      "edit_delete": false
    },
    "fleet_vehicles": {
      "can_access": true,
      "edit_delete": true
    },
    "fleet_drivers": {
      "can_access": true,
      "edit_delete": false
    },
    "customer_fleet": {
      "can_access": true,
      "edit_delete": true
    },
    "role_access_control": {
      "can_access": true,
      "edit_delete": true
    }
  },
  "office": "Bangalore HQ",
  "department": "Fleet Management",
  "createdBy": ObjectId("507f1f77bcf86cd799439012"),
  "lastLogin": ISODate("2025-12-30T10:30:00.000Z"),
  "loginAttempts": 0,
  "createdAt": ISODate("2025-01-15T10:30:00.000Z"),
  "updatedAt": ISODate("2025-12-30T10:30:00.000Z")
}
*/