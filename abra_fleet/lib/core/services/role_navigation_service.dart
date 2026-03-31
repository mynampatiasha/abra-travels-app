// lib/core/services/role_navigation_service.dart
// Dynamic role-based navigation filtering service

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/app/config/api_config.dart';

class RoleNavigationService {
  // Cache for user permissions to avoid repeated API calls
  static Map<String, Map<String, dynamic>>? _cachedUserPermissions;
  static String? _cachedUserId;
  
  // Fallback permissions for when API is unavailable (offline mode)
  static const Map<String, List<int>> _fallbackRoleNavigationMap = {
    'super_admin': [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33],
    'hr_manager': [0, 3, 7, 17, 18, 19, 20, 21, 23, 25, 27, 28, 29, 30, 31],
    'fleet_manager': [0, 1, 2, 6, 7, 12, 13, 14, 15, 16, 25, 26],
    'finance': [0, 4, 7, 22, 23, 24, 25],
  };

  // Fallback notification permissions
  static const Map<String, List<String>> _fallbackNotificationMap = {
    'super_admin': ['sos_alerts', 'pending_rosters', 'approved_rosters', 'document_expiry', 'address_change', 'customer_registration', 'leave_approvals'],
    'hr_manager': ['pending_rosters', 'approved_rosters', 'address_change', 'customer_registration', 'leave_approvals'],
    'fleet_manager': ['sos_alerts', 'document_expiry'],
    'finance': [],
  };

  // Get allowed navigation indices for a role
  static List<int> getAllowedNavigationIndices(String? userRole) {
    if (userRole == null) return [];
    
    final normalizedRole = userRole.toLowerCase().replaceAll(' ', '_');
    return _roleNavigationMap[normalizedRole] ?? [];
  }

  // Check if user can access a specific navigation index
  static bool canAccessNavigation(String? userRole, int navigationIndex) {
    final allowedIndices = getAllowedNavigationIndices(userRole);
    final canAccess = allowedIndices.contains(navigationIndex);
    
    // Debug logging
    if (!canAccess) {
      print('🚫 Access denied: User role $userRole cannot access navigation index $navigationIndex');
      print('   Allowed indices: $allowedIndices');
    }
    
    return canAccess;
  }

  // Get allowed notifications for a role
  static List<String> getAllowedNotifications(String? userRole) {
    if (userRole == null) return [];
    
    final normalizedRole = userRole.toLowerCase().replaceAll(' ', '_');
    return _roleNotificationMap[normalizedRole] ?? [];
  }

  // Check if user can see specific notification type
  static bool canSeeNotification(String? userRole, String notificationType) {
    final allowedNotifications = getAllowedNotifications(userRole);
    return allowedNotifications.contains(notificationType);
  }

  // Get role display name
  static String getRoleDisplayName(String? role) {
    if (role == null) return 'Unknown';
    
    switch (role.toLowerCase().replaceAll(' ', '_')) {
      case 'super_admin':
        return 'Super Admin';
      case 'hr_manager':
        return 'HR Manager';
      case 'fleet_manager':
        return 'Fleet Manager';
      case 'finance':
        return 'Finance Manager';
      default:
        return role;
    }
  }
  
  // Get role color for UI badges
  static String getRoleColor(String? role) {
    if (role == null) return '#9E9E9E';
    
    switch (role.toLowerCase().replaceAll(' ', '_')) {
      case 'super_admin':
        return '#FF0000'; // Red
      case 'hr_manager':
        return '#FF9800'; // Orange
      case 'fleet_manager':
        return '#0D47A1'; // Blue
      case 'finance':
        return '#4CAF50'; // Green
      default:
        return '#9E9E9E'; // Gray
    }
  }
}