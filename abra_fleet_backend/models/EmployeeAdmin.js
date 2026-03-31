// models/EmployeeAdmin.js
// ============================================================================
// EMPLOYEE ADMIN MODEL - For Admin Panel Users ONLY
// ============================================================================
// This collection stores ONLY admin panel users (not customers, drivers, clients)
// Roles: super_admin, admin, employee, hr_manager, fleet_manager, finance, operations

const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const employeeAdminSchema = new mongoose.Schema({
  // ============================================================================
  // BASIC INFORMATION
  // ============================================================================
  name_parson: {
    type: String,
    required: true,
    trim: true
  },
  name: {
    type: String,
    required: true,
    trim: true
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
  
  // ============================================================================
  // FIREBASE INTEGRATION
  // ============================================================================
  firebaseUid: {
    type: String,
    unique: true,
    sparse: true
  },
  
  // ============================================================================
  // ROLE & STATUS
  // ============================================================================
  role: {
    type: String,
    enum: ['super_admin', 'admin', 'employee', 'hr_manager', 'fleet_manager', 'finance', 'operations'],
    default: 'employee'
  },
  isActive: {
    type: Boolean,
    default: true
  },
  
  // ============================================================================
  // NAVIGATION-BASED PERMISSIONS
  // ============================================================================
  // Each key corresponds to a navigation item from NavigationConfig
  // Example: { 'dashboard': { can_access: true, edit_delete: false } }
  permissions: {
    type: Map,
    of: {
      can_access: { type: Boolean, default: false },
      edit_delete: { type: Boolean, default: false }
    },
    default: {}
  },
  
  // ============================================================================
  // OPTIONAL FIELDS
  // ============================================================================
  office: {
    type: String,
    default: ''
  },
  department: {
    type: String,
    default: ''
  },
  
  // ============================================================================
  // TRACKING & METADATA
  // ============================================================================
  createdBy: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'EmployeeAdmin'
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
  timestamps: true,
  collection: 'employee_admins'
});

// ============================================================================
// INDEXES
// ============================================================================
employeeAdminSchema.index({ email: 1 });
employeeAdminSchema.index({ firebaseUid: 1 });
employeeAdminSchema.index({ isActive: 1 });

// ============================================================================
// PRE-SAVE HOOKS
// ============================================================================
employeeAdminSchema.pre('save', async function(next) {
  if (!this.isModified('pwd')) return next();
  
  try {
    const salt = await bcrypt.genSalt(10);
    this.pwd = await bcrypt.hash(this.pwd, salt);
    next();
  } catch (error) {
    next(error);
  }
});

// ============================================================================
// INSTANCE METHODS
// ============================================================================
employeeAdminSchema.methods.comparePassword = async function(candidatePassword) {
  return await bcrypt.compare(candidatePassword, this.pwd);
};

employeeAdminSchema.methods.hasPermission = function(permissionKey) {
  if (this.role === 'super_admin') return true;
  if (!this.isActive) return false;
  if (!this.permissions) return false;
  
  let permission;
  if (this.permissions instanceof Map) {
    permission = this.permissions.get(permissionKey);
  } else {
    permission = this.permissions[permissionKey];
  }
  
  return permission && permission.can_access === true;
};

employeeAdminSchema.methods.canEditDelete = function(permissionKey) {
  if (this.role === 'super_admin') return true;
  if (!this.isActive) return false;
  if (!this.permissions) return false;
  
  let permission;
  if (this.permissions instanceof Map) {
    permission = this.permissions.get(permissionKey);
  } else {
    permission = this.permissions[permissionKey];
  }
  
  return permission && permission.edit_delete === true;
};

module.exports = mongoose.model('EmployeeAdmin', employeeAdminSchema);