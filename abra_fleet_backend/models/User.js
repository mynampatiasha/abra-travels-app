// models/User.js
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

// Sub-schema for standard permissions with filters
const permissionFilterSchema = new mongoose.Schema({
  permission: String,          // e.g., "view_vehicles"
  filters: [String],            // e.g., ["Bangalore", "Client A"]
  customFilters: [String]       // e.g., ["Only AC vehicles"]
}, { _id: false });

// Sub-schema for custom permissions
const customPermissionSchema = new mongoose.Schema({
  name: String,                 // e.g., "Manage Bangalore Fleet Only"
  description: String,          // e.g., "Full access to vehicles in Bangalore"
  module: String                // e.g., "vehicles"
}, { _id: false });

// Main User Schema
const userSchema = new mongoose.Schema({
  // Basic Information
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
    trim: true
  },
  // Branch/Location Information
  branch: {
    type: String,
    trim: true,
    index: true  // Add index for efficient filtering
  },
  password: {
    type: String,
    required: true
  },
  
  // Role & Permissions
  role: {
    type: String,
    enum: ['super', 'admin', 'vehicle', 'custom'],
    default: 'custom'
  },
  standardPermissions: [permissionFilterSchema],
  customPermissions: [customPermissionSchema],
  
  // Status & Tracking
  isActive: {
    type: Boolean,
    default: true
  },
  firebaseUid: {
    type: String,
    unique: true,
    sparse: true  // Allows null values while maintaining uniqueness
  },
  createdBy: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  }
}, {
  timestamps: true  // Automatically adds createdAt and updatedAt
});

// Hash password before saving to database
userSchema.pre('save', async function(next) {
  // Only hash if password is new or modified
  if (!this.isModified('password')) return next();
  
  try {
    const salt = await bcrypt.genSalt(10);
    this.password = await bcrypt.hash(this.password, salt);
    next();
  } catch (error) {
    next(error);
  }
});

// Method to compare password during login
userSchema.methods.comparePassword = async function(candidatePassword) {
  return await bcrypt.compare(candidatePassword, this.password);
};

// Method to check if user has a specific permission
userSchema.methods.hasPermission = function(permissionKey) {
  // Super admin has all permissions
  if (this.role === 'super') return true;
  
  // Check in standard permissions
  return this.standardPermissions.some(p => p.permission === permissionKey);
};

// Method to check if user has module access
userSchema.methods.hasModuleAccess = function(moduleName) {
  // Super admin has all access
  if (this.role === 'super') return true;
  
  // Check if user has any permission starting with module name
  return this.standardPermissions.some(p => 
    p.permission.startsWith(moduleName)
  );
};

module.exports = mongoose.model('User', userSchema);

// ============================================
// Example User Document in MongoDB:
// ============================================
/*
{
  "_id": "507f1f77bcf86cd799439011",
  "name": "Rajesh Kumar",
  "email": "rajesh@company.com",
  "phone": "+91 9876543210",
  "password": "$2a$10$hashed_password_here",
  "role": "vehicle",
  "standardPermissions": [
    {
      "permission": "view_vehicles",
      "filters": ["Bangalore", "All Locations"],
      "customFilters": ["Only AC vehicles", "Registered after 2023"]
    },
    {
      "permission": "add_vehicle",
      "filters": ["Bangalore Only"],
      "customFilters": []
    }
  ],
  "customPermissions": [
    {
      "name": "Manage Bangalore Fleet Only",
      "description": "Full access to vehicles in Bangalore region",
      "module": "vehicles"
    }
  ],
  "isActive": true,
  "firebaseUid": "firebase_uid_12345",
  "createdBy": "507f1f77bcf86cd799439012",
  "createdAt": "2025-01-15T10:30:00.000Z",
  "updatedAt": "2025-01-15T10:30:00.000Z"
}
*/