// lib/core/utils/role_mapper.dart

class RoleMapper {
  /// Normalize backend roles to frontend format
  /// Converts camelCase backend roles to snake_case frontend roles
  static String normalizeRole(String? backendRole) {
    if (backendRole == null || backendRole.isEmpty) return 'customer';
    
    // Role mapping from backend (camelCase) to frontend (snake_case)
    final roleMap = {
      // Admin roles
      'superAdmin': 'super_admin',
      'super_admin': 'super_admin',
      'orgAdmin': 'org_admin',
      'org_admin': 'org_admin',
      'admin': 'super_admin', // Map generic 'admin' to super_admin
      
      // Manager roles
      'fleetManager': 'fleet_manager',
      'fleet_manager': 'fleet_manager',
      'hrManager': 'hr_manager',
      'hr_manager': 'hr_manager',
      
      // Standard roles
      'operations': 'operations',
      'finance': 'finance',
      'customer': 'customer',
      'driver': 'driver',
      'client': 'client',
    };
    
    // Return mapped role or convert to lowercase if not found
    final normalizedRole = roleMap[backendRole] ?? backendRole.toLowerCase();
    
    print('[RoleMapper] Normalized "$backendRole" → "$normalizedRole"');
    
    return normalizedRole;
  }
  
  /// Convert frontend roles back to backend format
  /// Converts snake_case frontend roles to camelCase backend roles
  static String toBackendRole(String? frontendRole) {
    if (frontendRole == null || frontendRole.isEmpty) return 'customer';
    
    // Role mapping from frontend (snake_case) to backend (camelCase)
    final roleMap = {
      'super_admin': 'superAdmin',
      'org_admin': 'orgAdmin',
      'fleet_manager': 'fleetManager',
      'hr_manager': 'hrManager',
      'operations': 'operations',
      'finance': 'finance',
      'customer': 'customer',
      'driver': 'driver',
      'client': 'client',
    };
    
    return roleMap[frontendRole] ?? frontendRole;
  }
  
  /// Check if a role has admin privileges
  static bool isAdmin(String? role) {
    return role == 'super_admin' || role == 'org_admin';
  }
  
  /// Check if a role has manager privileges
  static bool isManager(String? role) {
    return role == 'fleet_manager' || 
           role == 'hr_manager' || 
           isAdmin(role);
  }
}