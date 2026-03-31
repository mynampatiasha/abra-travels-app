// middleware/employeePermissions.js
// ============================================================================
// EMPLOYEE PERMISSION MIDDLEWARE - For EmployeeAdmin model only
// ============================================================================

const EmployeeAdmin = require('../models/EmployeeAdmin');

/**
 * Check if current employee has specific permission
 * @param {string} permissionKey - Navigation permission key (e.g., 'fleet_vehicles', 'dashboard')
 */
function checkEmployeePermission(permissionKey) {
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

      console.log(`\n🔐 Permission Check: ${permissionKey}`);
      console.log(`   User: ${currentUserEmail}`);

      // Find employee in employee_admins collection
      const employee = await EmployeeAdmin.findOne({ email: currentUserEmail });

      if (!employee) {
        console.log('⚠️  Employee not found in employee_admins collection');
        return res.status(404).json({
          success: false,
          error: 'Employee not found',
          message: 'Current employee not found in database',
        });
      }

      // Check if employee is active
      if (!employee.isActive) {
        return res.status(403).json({
          success: false,
          error: 'Account inactive',
          message: 'Your account is currently inactive',
        });
      }

      // Super admins have all access
      if (employee.role === 'super_admin') {
        console.log(`   ✅ Super admin - access granted`);
        req.currentEmployee = employee;
        return next();
      }

      // Check if employee has the specific permission
      const hasAccess = employee.hasPermission(permissionKey);

      if (!hasAccess) {
        console.log(`⚠️  Employee ${currentUserEmail} denied access to ${permissionKey}`);
        return res.status(403).json({
          success: false,
          error: 'Forbidden',
          message: `You don't have permission to access ${permissionKey}`,
        });
      }

      console.log(`✅ Employee ${currentUserEmail} granted access to ${permissionKey}`);
      req.currentEmployee = employee;
      next();
    } catch (error) {
      console.error('❌ Employee permission check failed:', error);
      res.status(500).json({
        success: false,
        error: 'Permission check failed',
        message: error.message,
      });
    }
  };
}

/**
 * Check if employee can edit/delete in a specific module
 * @param {string} permissionKey - Navigation permission key
 */
function checkEmployeeEditPermission(permissionKey) {
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

      console.log(`\n🔐 Edit Permission Check: ${permissionKey}`);
      console.log(`   User: ${currentUserEmail}`);

      const employee = await EmployeeAdmin.findOne({ email: currentUserEmail });

      if (!employee) {
        return res.status(404).json({
          success: false,
          error: 'Employee not found',
        });
      }

      if (!employee.isActive) {
        return res.status(403).json({
          success: false,
          error: 'Account inactive',
        });
      }

      // Super admins can edit everything
      if (employee.role === 'super_admin') {
        console.log(`   ✅ Super admin - edit access granted`);
        req.currentEmployee = employee;
        return next();
      }

      // Check edit/delete permission
      const canEdit = employee.canEditDelete(permissionKey);

      if (!canEdit) {
        console.log(`⚠️  Employee ${currentUserEmail} denied edit access to ${permissionKey}`);
        return res.status(403).json({
          success: false,
          error: 'Forbidden',
          message: `You don't have permission to edit/delete in ${permissionKey}`,
        });
      }

      console.log(`✅ Employee ${currentUserEmail} granted edit access to ${permissionKey}`);
      req.currentEmployee = employee;
      next();
    } catch (error) {
      console.error('❌ Edit permission check failed:', error);
      res.status(500).json({
        success: false,
        error: 'Permission check failed',
        message: error.message,
      });
    }
  };
}

module.exports = {
  checkEmployeePermission,
  checkEmployeeEditPermission,
};