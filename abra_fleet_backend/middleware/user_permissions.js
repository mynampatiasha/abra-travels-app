// middleware/user_permissions.js
// ============================================================================
// USER PERMISSION MIDDLEWARE - For regular User model with standardPermissions
// ============================================================================

const User = require('../models/User');

/**
 * Check if current USER has module access (for regular users, not admin users)
 */
function checkUserPermission(moduleName) {
  return async (req, res, next) => {
    try {
      const currentUserEmail = req.user?.email;
      if (!currentUserEmail) {
        return res.status(401).json({
          success: false,
          error: 'Unauthorized',
          message: 'User not authenticated',
        });
      }

      // ✅ IMPORTANT: Look in User collection (NOT AdminUser)
      const currentUser = await User.findOne({ email: currentUserEmail });

      if (!currentUser) {
        console.log('⚠️  User not found in users collection:', currentUserEmail);
        return res.status(404).json({
          success: false,
          error: 'User not found',
          message: 'Current user not found in database',
        });
      }

      // Check if user is active
      if (!currentUser.isActive) {
        return res.status(403).json({
          success: false,
          error: 'Account inactive',
          message: 'Your account is currently inactive',
        });
      }

      // Super users and super_admins have all access
      if (currentUser.role === 'super' || currentUser.role === 'super_admin') {
        req.currentUser = currentUser;
        return next();
      }

      // Check if user has module access using the hasModuleAccess method
      const hasAccess = currentUser.hasModuleAccess(moduleName);

      if (!hasAccess) {
        console.log(`⚠️  User ${currentUserEmail} denied access to ${moduleName}`);
        return res.status(403).json({
          success: false,
          error: 'Forbidden',
          message: `You don't have permission to access ${moduleName} module`,
        });
      }

      console.log(`✅ User ${currentUserEmail} granted access to ${moduleName}`);
      req.currentUser = currentUser;
      next();
    } catch (error) {
      console.error('❌ User permission check failed:', error);
      res.status(500).json({
        success: false,
        error: 'Permission check failed',
        message: error.message,
      });
    }
  };
}

/**
 * Allow access to either AdminUser OR regular User
 * Checks both collections
 * ✅ UPDATED: Better permission key matching for navigation-based permissions
 */
function checkEitherPermission(permissionOrModule) {
  return async (req, res, next) => {
    try {
      const currentUserEmail = req.user?.email;
      if (!currentUserEmail) {
        return res.status(401).json({
          success: false,
          error: 'Unauthorized',
          message: 'User not authenticated',
        });
      }

      console.log(`\n🔐 Permission Check: ${permissionOrModule}`);
      console.log(`   User: ${currentUserEmail}`);

      // ============================================================
      // TRY ADMIN USER FIRST (navigation-based permissions)
      // ============================================================
      const AdminUser = require('../models/AdminUser');
      const adminUser = await AdminUser.findOne({ email: currentUserEmail });
      
      if (adminUser && adminUser.isActive) {
        console.log(`   Found in AdminUser collection`);
        console.log(`   Role: ${adminUser.role}`);
        
        // Super admin always has access
        if (adminUser.role === 'super_admin') {
          console.log(`   ✅ Super admin - access granted`);
          req.currentAdminUser = adminUser;
          return next();
        }
        
        try {
          // ✅ Check if admin has ANY navigation permission that contains this module
          // Example: if checking 'fleet', accept 'fleet_vehicles', 'fleet_drivers', etc.
          let hasPermission = false;
          
          // First, try exact match
          if (adminUser.hasPermission(permissionOrModule)) {
            hasPermission = true;
            console.log(`   ✅ Exact permission match: ${permissionOrModule}`);
          }
          
          // If no exact match, check for permissions that start with the module name
          if (!hasPermission && adminUser.permissions) {
            const permissions = adminUser.permissions instanceof Map 
              ? Array.from(adminUser.permissions.keys())
              : Object.keys(adminUser.permissions);
            
            // Check if user has any permission starting with the module name
            hasPermission = permissions.some(key => {
              return key.startsWith(permissionOrModule + '_') || 
                     key === permissionOrModule;
            });
            
            if (hasPermission) {
              console.log(`   ✅ Module-based permission match found`);
              console.log(`   Matched permissions:`, permissions.filter(k => 
                k.startsWith(permissionOrModule + '_') || k === permissionOrModule
              ));
            }
          }
          
          if (hasPermission) {
            console.log(`   ✅ Admin user granted access to ${permissionOrModule}`);
            req.currentAdminUser = adminUser;
            return next();
          }
          
          console.log(`   ❌ Admin user has no permission for ${permissionOrModule}`);
        } catch (permError) {
          console.error('   ⚠️  Admin permission check error:', permError.message);
          // Continue to try regular user
        }
      } else {
        console.log(`   Not found in AdminUser collection or inactive`);
      }

      // ============================================================
      // TRY REGULAR USER (standardPermissions)
      // ============================================================
      const regularUser = await User.findOne({ email: currentUserEmail });
      
      if (regularUser && regularUser.isActive) {
        console.log(`   Found in User collection`);
        console.log(`   Role: ${regularUser.role}`);
        
        // Super users and super_admins have all access
        if (regularUser.role === 'super' || regularUser.role === 'super_admin') {
          console.log(`   ✅ Super user/admin - access granted`);
          req.currentUser = regularUser;
          return next();
        }
        
        // Check user permissions
        if (regularUser.hasModuleAccess(permissionOrModule)) {
          console.log(`   ✅ Regular user granted access to ${permissionOrModule}`);
          req.currentUser = regularUser;
          return next();
        }
        
        console.log(`   ❌ Regular user has no permission for ${permissionOrModule}`);
      } else {
        console.log(`   Not found in User collection or inactive`);
      }

      // ============================================================
      // NEITHER HAS ACCESS
      // ============================================================
      console.log(`   ⚠️  Access denied: No valid permissions found`);
      return res.status(403).json({
        success: false,
        error: 'Forbidden',
        message: `You don't have permission to access this resource`,
      });

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

module.exports = {
  checkUserPermission,
  checkEitherPermission,
};