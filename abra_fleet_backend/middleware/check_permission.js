// backend/middleware/check_permission.js
// ============================================================================
// 🔐 PERMISSION MIDDLEWARE FOR ERP USERS SYSTEM
// ============================================================================
// Works with employee_admins collection permissions
// ============================================================================

/**
 * Middleware to check if user has a specific permission
 * Works with JWT tokens that contain permissions object
 * 
 * Permission names in MongoDB:
 * - vehicle_master
 * - trip_operation
 * - gps_tracking
 * - maintenance_management
 * - drivers
 * - all_customers
 * - pending_approvals
 * - pending_rosters
 * - approved_rosters
 * - trip_cancellation
 * - client_details
 * - trips
 * - hrm_employees
 * - hrm_leave_requests
 * - hrm_payroll
 * - notice_board
 * - attendance
 * - raise_ticket
 * - my_tickets
 * - all_tickets
 * - closed_tickets
 * - reports
 * - resolved_alerts
 * - incomplete_alerts
 * - feedback_management
 * - role_access_control
 */

const checkPermission = (requiredPermission) => {
  return (req, res, next) => {
    console.log('\n🔐 CHECKING PERMISSION');
    console.log('─'.repeat(80));
    console.log('Required permission:', requiredPermission);
    console.log('User email:', req.user.email);
    console.log('User role:', req.user.role);
    
    // ✅ Admin always has access
    if (req.user.role === 'admin' || req.user.role === 'super_admin') {
      console.log('✅ Admin access granted');
      console.log('─'.repeat(80) + '\n');
      return next();
    }
    
    // ✅ Check if permissions exist in JWT token
    const permissions = req.user.permissions || {};
    
    console.log('Permissions in JWT:', Object.keys(permissions).length, 'items');
    
    // ✅ Check if user has the required permission
    const hasPermission = permissions[requiredPermission];
    
    if (hasPermission && hasPermission.can_access === true) {
      console.log(`✅ Permission granted: ${requiredPermission}`);
      console.log('─'.repeat(80) + '\n');
      return next();
    }
    
    console.log(`❌ Permission denied: ${requiredPermission}`);
    console.log('Available permissions:', Object.keys(permissions).join(', '));
    console.log('─'.repeat(80) + '\n');
    
    return res.status(403).json({
      success: false,
      error: 'Forbidden',
      message: "You don't have permission to access this resource"
    });
  };
};

/**
 * Check if user has ANY of the specified permissions
 * Used for routes that can be accessed by multiple permission types
 */
const checkAnyPermission = (...requiredPermissions) => {
  return (req, res, next) => {
    console.log('\n🔐 CHECKING ANY PERMISSION');
    console.log('─'.repeat(80));
    console.log('Required permissions (any of):', requiredPermissions.join(', '));
    console.log('User email:', req.user.email);
    console.log('User role:', req.user.role);
    
    // ✅ Admin always has access
    if (req.user.role === 'admin' || req.user.role === 'super_admin') {
      console.log('✅ Admin access granted');
      console.log('─'.repeat(80) + '\n');
      return next();
    }
    
    const permissions = req.user.permissions || {};
    console.log('Permissions in JWT:', Object.keys(permissions).length, 'items');
    
    // ✅ Check if user has ANY of the required permissions
    const hasAnyPermission = requiredPermissions.some(permission => {
      const perm = permissions[permission];
      return perm && perm.can_access === true;
    });
    
    if (hasAnyPermission) {
      console.log('✅ Permission granted (has at least one required permission)');
      console.log('─'.repeat(80) + '\n');
      return next();
    }
    
    console.log('❌ Permission denied - user does not have any required permissions');
    console.log('Available permissions:', Object.keys(permissions).join(', '));
    console.log('─'.repeat(80) + '\n');
    
    return res.status(403).json({
      success: false,
      error: 'Forbidden',
      message: "You don't have permission to access this resource"
    });
  };
};

module.exports = {
  checkPermission,
  checkAnyPermission
};