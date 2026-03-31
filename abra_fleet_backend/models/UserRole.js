// models/UserRole.js - User model for Abra Travel with Hierarchical Permissions
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const userSchema = new mongoose.Schema({
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
    trim: true,
    index: true
  },
  phone: {
    type: String,
    trim: true
  },
  password: {
    type: String,
    required: false,  // Optional since some users might authenticate via Firebase only
    minlength: 6
  },
  role: {
    type: String,
    required: true,
    enum: ['superAdmin', 'orgAdmin', 'fleetManager', 'operations', 'hrManager', 'finance'],
    default: 'operations',
    index: true
  },
  status: {
    type: String,
    enum: ['active', 'inactive'],
    default: 'active',
    index: true
  },
  lastActive: {
    type: Date,
    default: Date.now
  },
  // Firebase UID for integration
  firebaseUid: {
    type: String,
    sparse: true,
    unique: true,
    index: true
  },
  // HIERARCHICAL PERMISSIONS - Custom permissions for this specific user
  // Format from Flutter: 
  // { 
  //   "Vehicle Management": { 
  //     "Vehicle Master": { enabled: true, index: 12, description: "..." },
  //     "Trip Operations": { enabled: false, index: 13, description: "..." }
  //   },
  //   "Customer Management": { ... }
  // }
  customPermissions: {
    type: mongoose.Schema.Types.Mixed,
    default: null  // null means use role defaults, {} means custom permissions set
  },
  // Track when permissions were last updated
  permissionsUpdatedAt: {
    type: Date,
    default: null
  }
}, {
  timestamps: true
});

// Hash password before saving
userSchema.pre('save', async function(next) {
  // Update lastActive on any activity
  this.lastActive = Date.now();
  
  // Only hash password if it exists and has been modified (or is new)
  if (!this.password || !this.isModified('password')) {
    return next();
  }

  try {
    // Generate salt and hash password
    const salt = await bcrypt.genSalt(10);
    this.password = await bcrypt.hash(this.password, salt);
    next();
  } catch (error) {
    next(error);
  }
});

// Method to compare password for login
userSchema.methods.comparePassword = async function(candidatePassword) {
  if (!this.password) {
    throw new Error('User does not have a password set');
  }
  
  try {
    return await bcrypt.compare(candidatePassword, this.password);
  } catch (error) {
    throw error;
  }
};

// Method to check if user has a specific permission
userSchema.methods.hasPermission = async function(module, subModule) {
  // If user has custom permissions, check those first
  if (this.customPermissions && typeof this.customPermissions === 'object') {
    const modulePerms = this.customPermissions[module];
    if (modulePerms && typeof modulePerms === 'object') {
      const subModulePerm = modulePerms[subModule];
      if (subModulePerm && typeof subModulePerm === 'object') {
        return subModulePerm.enabled === true;
      }
    }
  }
  
  // Fallback to role-based permissions
  const Role = mongoose.model('Role');
  const role = await Role.findOne({ id: this.role });
  if (!role) return false;
  
  return role.hasPermission(module, subModule);
};

// Method to get all enabled modules for the user
userSchema.methods.getEnabledModules = function() {
  if (!this.customPermissions || typeof this.customPermissions !== 'object') {
    return [];
  }
  
  const enabledModules = [];
  for (const module in this.customPermissions) {
    const modulePerms = this.customPermissions[module];
    if (typeof modulePerms === 'object') {
      // Check if any sub-module is enabled
      const hasEnabledSubModule = Object.values(modulePerms).some(
        perm => perm && typeof perm === 'object' && perm.enabled === true
      );
      if (hasEnabledSubModule) {
        enabledModules.push(module);
      }
    }
  }
  
  return enabledModules;
};

// Method to check if user has custom permissions
userSchema.methods.hasCustomPermissions = function() {
  return !!(this.customPermissions && 
           typeof this.customPermissions === 'object' && 
           Object.keys(this.customPermissions).length > 0);
};

// Static method to find users by role
userSchema.statics.findByRole = function(role) {
  return this.find({ role, status: 'active' });
};

// Static method to find active users
userSchema.statics.findActive = function() {
  return this.find({ status: 'active' });
};

// Don't return password and sensitive data in JSON responses
userSchema.methods.toJSON = function() {
  const obj = this.toObject();
  delete obj.password;
  delete obj.__v;
  return obj;
};

// Update lastActive timestamp
userSchema.methods.updateActivity = function() {
  this.lastActive = new Date();
  return this.save();
};

// Indexes for better query performance
userSchema.index({ email: 1 });
userSchema.index({ role: 1 });
userSchema.index({ status: 1 });
userSchema.index({ firebaseUid: 1 });
userSchema.index({ createdAt: -1 });

module.exports = mongoose.model('UserRole', userSchema);