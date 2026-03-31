// models/Role.js - Role model for Abra Travel with Hierarchical Permissions Support
const mongoose = require('mongoose');

const roleSchema = new mongoose.Schema({
  id: {
    type: String,
    required: true,
    unique: true,
    index: true
  },
  title: {
    type: String,
    required: true
  },
  icon: {
    type: String,
    default: '👤'
  },
  color: {
    type: String,
    default: '#667eea'
  },
  // OLD FORMAT - Keep for backward compatibility
  // Format: { "Fleet Management": ["permission1", "permission2"], ... }
  permissions: {
    type: Map,
    of: [String], // Array of permission strings
    required: true,
    default: {}
  },
  // NEW FORMAT - Hierarchical permissions from Flutter UI
  // Format: { "Vehicle Management": { "Vehicle Master": { enabled: true, index: 12, ... }, ... }, ... }
  customPermissions: {
    type: mongoose.Schema.Types.Mixed,
    default: {}
  },
  // Track when permissions were last updated
  permissionsUpdatedAt: {
    type: Date,
    default: null
  }
}, {
  timestamps: true
});

// Virtual for user count
roleSchema.virtual('userCount', {
  ref: 'UserRole',
  localField: 'id',
  foreignField: 'role',
  count: true
});

// Method to check if role has a specific permission
roleSchema.methods.hasPermission = function(module, permission) {
  // Check in custom permissions first (hierarchical format)
  if (this.customPermissions && this.customPermissions[module]) {
    const modulePerms = this.customPermissions[module];
    
    // If it's the new hierarchical format
    if (typeof modulePerms === 'object' && !Array.isArray(modulePerms)) {
      return modulePerms[permission]?.enabled === true;
    }
  }
  
  // Fallback to old format
  if (this.permissions && this.permissions.get(module)) {
    return this.permissions.get(module).includes(permission);
  }
  
  return false;
};

// Method to get all enabled permissions for a module
roleSchema.methods.getModulePermissions = function(module) {
  // Check custom permissions first
  if (this.customPermissions && this.customPermissions[module]) {
    const modulePerms = this.customPermissions[module];
    
    // If it's the new hierarchical format, extract enabled permissions
    if (typeof modulePerms === 'object' && !Array.isArray(modulePerms)) {
      return Object.keys(modulePerms).filter(perm => modulePerms[perm]?.enabled === true);
    }
  }
  
  // Fallback to old format
  return this.permissions.get(module) || [];
};

// Method to check if role has custom permissions configured
roleSchema.methods.hasCustomPermissions = function() {
  return !!(this.customPermissions && 
           typeof this.customPermissions === 'object' && 
           Object.keys(this.customPermissions).length > 0);
};

// Static method to get role with user count
roleSchema.statics.findWithUserCount = async function(query = {}) {
  const roles = await this.find(query);
  const UserRole = mongoose.model('UserRole');
  
  const rolesWithCount = await Promise.all(
    roles.map(async (role) => {
      const userCount = await UserRole.countDocuments({ role: role.id });
      return {
        ...role.toObject(),
        userCount
      };
    })
  );
  
  return rolesWithCount;
};

// Configure JSON serialization
roleSchema.set('toJSON', { 
  virtuals: true,
  transform: function(doc, ret) {
    // Convert Map to plain object for JSON serialization
    if (ret.permissions instanceof Map) {
      ret.permissions = Object.fromEntries(ret.permissions);
    }
    return ret;
  }
});

roleSchema.set('toObject', { 
  virtuals: true,
  transform: function(doc, ret) {
    // Convert Map to plain object
    if (ret.permissions instanceof Map) {
      ret.permissions = Object.fromEntries(ret.permissions);
    }
    return ret;
  }
});

// Index for faster queries
roleSchema.index({ id: 1 });
roleSchema.index({ title: 1 });

module.exports = mongoose.model('Role', roleSchema);