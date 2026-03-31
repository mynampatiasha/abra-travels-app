// controllers/roleController.js - Role management for Abra Travel with Hierarchical Permissions
const Role = require('../models/Role');
const UserRole = require('../models/UserRole');

// Get all roles with user counts
exports.getAllRoles = async (req, res) => {
  console.log('\n📋 GET ALL ROLES');
  console.log('─'.repeat(80));
  
  try {
    const roles = await Role.find();
    
    // Calculate user count for each role
    const rolesWithCount = await Promise.all(
      roles.map(async (role) => {
        const userCount = await UserRole.countDocuments({ role: role.id });
        return {
          ...role.toObject(),
          userCount
        };
      })
    );

    console.log(`   Found ${rolesWithCount.length} roles`);
    console.log('✅ ROLES RETRIEVED');
    console.log('─'.repeat(80) + '\n');
    res.json({
      success: true,
      data: rolesWithCount
    });
  } catch (error) {
    console.error('❌ GET ROLES FAILED:', error.message);
    console.error('─'.repeat(80) + '\n');
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
};

// Update role permissions - UPDATED VERSION with hierarchical permissions
exports.updateRolePermissions = async (req, res) => {
  console.log('\n✏️  UPDATE ROLE PERMISSIONS');
  console.log('─'.repeat(80));
  console.log('   Role ID:', req.params.roleId);
  
  try {
    const { permissions, updatedAt } = req.body;
    
    const role = await Role.findOne({ id: req.params.roleId });
    if (!role) {
      console.log('   ❌ Role not found');
      return res.status(404).json({ 
        success: false,
        error: 'Role not found' 
      });
    }

    // Update permissions with hierarchical structure
    role.customPermissions = permissions; // Store hierarchical permissions
    role.permissionsUpdatedAt = updatedAt || new Date();
    await role.save();

    console.log('   ✅ Hierarchical permissions updated');
    console.log('   📊 Modules configured:', Object.keys(permissions).length);
    
    // Count total sub-permissions
    let totalSubPermissions = 0;
    for (const module in permissions) {
      totalSubPermissions += Object.keys(permissions[module]).length;
    }
    console.log('   🔧 Sub-permissions configured:', totalSubPermissions);
    
    console.log('─'.repeat(80) + '\n');
    res.json({ 
      success: true,
      message: `Permissions updated successfully for ${role.title}`,
      data: role,
      stats: {
        modules: Object.keys(permissions).length,
        subPermissions: totalSubPermissions
      }
    });
  } catch (error) {
    console.error('❌ UPDATE PERMISSIONS FAILED:', error.message);
    console.error('─'.repeat(80) + '\n');
    res.status(400).json({ 
      success: false,
      error: error.message 
    });
  }
};

// Get role by ID
exports.getRoleById = async (req, res) => {
  console.log('\n🔍 GET ROLE BY ID');
  console.log('─'.repeat(80));
  console.log('   Role ID:', req.params.roleId);
  
  try {
    const role = await Role.findOne({ id: req.params.roleId });
    
    if (!role) {
      console.log('   ❌ Role not found');
      return res.status(404).json({ 
        success: false,
        error: 'Role not found' 
      });
    }

    // Get user count for this role
    const userCount = await UserRole.countDocuments({ role: role.id });
    
    console.log('   ✅ Role found:', role.title);
    console.log('   👥 User count:', userCount);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: {
        ...role.toObject(),
        userCount
      }
    });
  } catch (error) {
    console.error('❌ GET ROLE FAILED:', error.message);
    console.error('─'.repeat(80) + '\n');
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
};

// Initialize default roles
exports.initializeRoles = async (req, res) => {
  console.log('\n🔧 INITIALIZE DEFAULT ROLES');
  console.log('─'.repeat(80));
  
  try {
    const defaultRoles = [
      {
        id: 'superAdmin',
        title: 'Super Admin',
        icon: '👑',
        color: '#ff6b6b',
        permissions: {
          'Fleet Management': ['View all vehicles', 'Add/Edit/Delete vehicles', 'Assign vehicles to routes', 'Vehicle maintenance', 'Fleet analytics'],
          'Driver Management': ['View all drivers', 'Add/Edit/Delete drivers', 'Manage driver documents', 'Driver performance reports'],
          'Route Planning': ['View all routes', 'Create/Edit/Delete routes', 'Optimize routes', 'Route analytics'],
          'Customer/Employee': ['View all employees', 'Bulk operations', 'Manage rosters', 'Employee analytics'],
          'Billing & Finance': ['View all invoices', 'Generate invoices', 'Payment tracking', 'Audit reports'],
          'System Administration': ['User management', 'Role management', 'System settings', 'API access']
        },
        customPermissions: {} // Empty initially, will be set via UI
      },
      {
        id: 'orgAdmin',
        title: 'Organization Admin',
        icon: '🏢',
        color: '#4ecdc4',
        permissions: {
          'Fleet Management': ['View all vehicles', 'Add/Edit vehicles', 'Assign vehicles', 'Fleet reports'],
          'Driver Management': ['View all drivers', 'Add/Edit drivers', 'Driver assignments'],
          'Route Planning': ['View all routes', 'Create/Edit routes', 'Route optimization'],
          'Customer/Employee': ['View employees', 'Manage rosters', 'Employee reports'],
          'User Management': ['Create users', 'Assign roles', 'Manage departments']
        },
        customPermissions: {}
      },
      {
        id: 'fleetManager',
        title: 'Fleet Manager',
        icon: '🚛',
        color: '#f093fb',
        permissions: {
          'Fleet Management': ['View vehicles', 'Add/Edit vehicles', 'Vehicle maintenance', 'Fleet reports'],
          'Driver Management': ['View drivers', 'Assign drivers', 'Driver performance'],
          'Route Planning': ['View routes', 'Vehicle-route assignment']
        },
        customPermissions: {}
      },
      {
        id: 'operations',
        title: 'Operations Manager',
        icon: '📊',
        color: '#4facfe',
        permissions: {
          'Route Planning': ['View routes', 'Create routes', 'Modify routes', 'Trip scheduling'],
          'Real-Time Tracking': ['Live tracking', 'Trip monitoring', 'Delay management'],
          'Driver Management': ['View drivers', 'Daily assignments']
        },
        customPermissions: {}
      },
      {
        id: 'hrManager',
        title: 'HR Manager',
        icon: '👥',
        color: '#43e97b',
        permissions: {
          'Customer/Employee': ['View employees', 'Manage rosters', 'Create schedules', 'Employee requests'],
          'Route Planning': ['View routes', 'Employee route assignment'],
          'Reports': ['Employee analytics', 'Attendance reports']
        },
        customPermissions: {}
      },
      {
        id: 'finance',
        title: 'Finance Admin',
        icon: '💰',
        color: '#30cfd0',
        permissions: {
          'Billing & Finance': ['View all invoices', 'Generate invoices', 'Payment tracking', 'Tax reports'],
          'Reports': ['Financial reports', 'Audit trails', 'Expense analysis']
        },
        customPermissions: {}
      }
    ];

    // Delete existing roles
    await Role.deleteMany({});
    console.log('   🗑️  Deleted existing roles');

    // Insert default roles
    await Role.insertMany(defaultRoles);
    console.log('   ✅ Inserted default roles');

    console.log('✅ ROLES INITIALIZED');
    console.log('─'.repeat(80) + '\n');
    res.json({ 
      success: true,
      message: 'Roles initialized successfully', 
      count: defaultRoles.length 
    });
  } catch (error) {
    console.error('❌ INITIALIZE ROLES FAILED:', error.message);
    console.error('─'.repeat(80) + '\n');
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
};

// Get permissions for a specific role
exports.getRolePermissions = async (req, res) => {
  console.log('\n🔐 GET ROLE PERMISSIONS');
  console.log('─'.repeat(80));
  console.log('   Role ID:', req.params.roleId);
  
  try {
    const role = await Role.findOne({ id: req.params.roleId });
    
    if (!role) {
      console.log('   ❌ Role not found');
      return res.status(404).json({ 
        success: false,
        error: 'Role not found' 
      });
    }

    console.log('   ✅ Permissions retrieved for:', role.title);
    
    // Return both old format permissions and new hierarchical permissions
    const response = {
      roleId: role.id,
      title: role.title,
      permissions: role.permissions, // Old format (flat)
      customPermissions: role.customPermissions || {}, // New format (hierarchical)
      hasCustomPermissions: !!(role.customPermissions && Object.keys(role.customPermissions).length > 0)
    };
    
    console.log('   📊 Has custom permissions:', response.hasCustomPermissions);
    console.log('─'.repeat(80) + '\n');
    
    res.json({
      success: true,
      data: response
    });
  } catch (error) {
    console.error('❌ GET PERMISSIONS FAILED:', error.message);
    console.error('─'.repeat(80) + '\n');
    res.status(500).json({ 
      success: false,
      error: error.message 
    });
  }
};

// Update role details (name, icon, color)
exports.updateRole = async (req, res) => {
  console.log('\n✏️  UPDATE ROLE DETAILS');
  console.log('─'.repeat(80));
  console.log('   Role ID:', req.params.roleId);
  
  try {
    const { title, icon, color } = req.body;
    
    const role = await Role.findOne({ id: req.params.roleId });
    if (!role) {
      console.log('   ❌ Role not found');
      return res.status(404).json({ 
        success: false,
        error: 'Role not found' 
      });
    }

    // Update role details
    if (title) role.title = title;
    if (icon) role.icon = icon;
    if (color) role.color = color;
    
    await role.save();

    console.log('   ✅ Role details updated');
    console.log('─'.repeat(80) + '\n');
    
    res.json({ 
      success: true,
      message: `Role updated successfully`,
      data: role
    });
  } catch (error) {
    console.error('❌ UPDATE ROLE FAILED:', error.message);
    console.error('─'.repeat(80) + '\n');
    res.status(400).json({ 
      success: false,
      error: error.message 
    });
  }
};

module.exports = exports;