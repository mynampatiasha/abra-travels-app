// models/UserPermission.js

const mongoose = require('mongoose');

/**
 * ============================================================================
 * USER PERMISSION MODEL
 * ============================================================================
 * Stores permissions for each user in a flexible key-value structure.
 * Each permission can have 'can_access' and 'edit_delete' flags.
 * ============================================================================
 */

const userPermissionSchema = new mongoose.Schema({
  // User identification
  userId: {
    type: String,
    required: true,
    index: true,
    unique: true
  },
  
  email: {
    type: String,
    required: true,
    index: true
  },
  
  userName: {
    type: String,
    required: true
  },
  
  role: {
    type: String,
    required: true,
    enum: [
      'super_admin',
      'superadmin',
      'admin',
      'org_admin',
      'organization_admin',
      'fleet_manager',
      'operations',
      'operations_manager',
      'hr_manager',
      'finance',
      'finance_admin',
      'customer',
      'driver'
    ]
  },
  
  // Permissions object - flexible structure
  // Format: { 'permission_key': { can_access: true, edit_delete: false } }
  // OR: { 'permission_key': true } (for backward compatibility)
  permissions: {
    type: mongoose.Schema.Types.Mixed,
    required: true,
    default: {}
  },
  
  // Audit fields
  createdAt: {
    type: Date,
    default: Date.now
  },
  
  updatedAt: {
    type: Date,
    default: Date.now
  },
  
  createdBy: {
    type: String,
    default: 'system'
  },
  
  updatedBy: {
    type: String,
    default: 'system'
  },
  
  // Optional metadata
  metadata: {
    lastSyncedAt: Date,
    permissionSource: {
      type: String,
      enum: ['manual', 'role_template', 'imported'],
      default: 'manual'
    },
    notes: String
  }
}, {
  collection: 'user_permissions',
  timestamps: true
});

// ========== INDEXES ==========
userPermissionSchema.index({ userId: 1 });
userPermissionSchema.index({ email: 1 });
userPermissionSchema.index({ role: 1 });
userPermissionSchema.index({ updatedAt: -1 });

// ========== INSTANCE METHODS ==========

/**
 * Check if user has a specific permission
 */
userPermissionSchema.methods.hasPermission = function(permissionKey) {
  const permission = this.permissions[permissionKey];
  
  if (!permission) return false;
  
  // Handle both formats:
  // 1. Boolean: { 'dashboard': true }
  // 2. Object: { 'dashboard': { can_access: true, edit_delete: false } }
  if (typeof permission === 'boolean') {
    return permission;
  }
  
  if (typeof permission === 'object') {
    return permission.can_access === true;
  }
  
  return false;
};

/**
 * Check if user can edit/delete for a specific permission
 */
userPermissionSchema.methods.canEdit = function(permissionKey) {
  const permission = this.permissions[permissionKey];
  
  if (!permission || typeof permission !== 'object') {
    return false;
  }
  
  return permission.edit_delete === true;
};

/**
 * Get all permissions as a flat list
 */
userPermissionSchema.methods.getAllPermissions = function() {
  return Object.keys(this.permissions).filter(key => this.hasPermission(key));
};

/**
 * Get permissions count
 */
userPermissionSchema.methods.getPermissionCount = function() {
  return this.getAllPermissions().length;
};

// ========== STATIC METHODS ==========

/**
 * Find permissions by user ID
 */
userPermissionSchema.statics.findByUserId = function(userId) {
  return this.findOne({ userId: userId });
};

/**
 * Find all users with a specific permission
 */
userPermissionSchema.statics.findUsersWithPermission = function(permissionKey) {
  return this.find({
    [`permissions.${permissionKey}`]: { $exists: true }
  });
};

/**
 * Create or update permissions for a user
 */
userPermissionSchema.statics.upsertPermissions = async function(userId, permissionsData, updatedBy = 'system') {
  const updateDoc = {
    ...permissionsData,
    updatedAt: new Date(),
    updatedBy: updatedBy
  };
  
  return this.findOneAndUpdate(
    { userId: userId },
    { 
      $set: updateDoc,
      $setOnInsert: {
        createdAt: new Date(),
        createdBy: updatedBy
      }
    },
    { 
      upsert: true,
      new: true,
      runValidators: true
    }
  );
};

/**
 * Get default permissions for a role
 */
userPermissionSchema.statics.getDefaultPermissionsByRole = function(role) {
  const roleDefaults = {
    'super_admin': {
      dashboard: { can_access: true, edit_delete: true },
      fleet_management: { can_access: true, edit_delete: true },
      fleet_vehicles: { can_access: true, edit_delete: true },
      fleet_drivers: { can_access: true, edit_delete: true },
      fleet_gps_tracking: { can_access: true, edit_delete: true },
      fleet_trips: { can_access: true, edit_delete: true },
      fleet_maintenance: { can_access: true, edit_delete: true },
      customer_fleet: { can_access: true, edit_delete: true },
      fleet_list: { can_access: true, edit_delete: true },
      abra_global_trading: { can_access: true, edit_delete: true },
      abra_food_works: { can_access: true, edit_delete: true },
      hrm_feedback: { can_access: true, edit_delete: true },
    },
    
    'fleet_manager': {
      dashboard: { can_access: true, edit_delete: false },
      fleet_management: { can_access: true, edit_delete: true },
      fleet_vehicles: { can_access: true, edit_delete: true },
      fleet_drivers: { can_access: true, edit_delete: true },
      fleet_gps_tracking: { can_access: true, edit_delete: false },
      fleet_trips: { can_access: true, edit_delete: true },
      fleet_maintenance: { can_access: true, edit_delete: true },
      fleet_list: { can_access: true, edit_delete: false },
    },
    
    'hr_manager': {
      dashboard: { can_access: true, edit_delete: false },
      customer_fleet: { can_access: true, edit_delete: true },
      hrm_feedback: { can_access: true, edit_delete: true },
    },
    
    'finance': {
      dashboard: { can_access: true, edit_delete: false },
      abra_global_trading: { can_access: true, edit_delete: true },
      abra_food_works: { can_access: true, edit_delete: true },
    },
    
    'operations': {
      dashboard: { can_access: true, edit_delete: false },
      fleet_trips: { can_access: true, edit_delete: false },
      fleet_gps_tracking: { can_access: true, edit_delete: false },
      fleet_list: { can_access: true, edit_delete: false },
    }
  };
  
  return roleDefaults[role] || {};
};

// ========== MIDDLEWARE ==========

// Update 'updatedAt' on save
userPermissionSchema.pre('save', function(next) {
  this.updatedAt = new Date();
  next();
});

// ========== VIRTUAL PROPERTIES ==========

// Get formatted role name
userPermissionSchema.virtual('formattedRole').get(function() {
  return this.role
    .split('_')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
});

// Export model
const UserPermission = mongoose.model('UserPermission', userPermissionSchema);

module.exports = UserPermission;