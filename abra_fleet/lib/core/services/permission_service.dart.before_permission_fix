// lib/core/services/permission_service.dart
// ============================================================================
// 🔐 PERMISSION SERVICE - ✅ CORRECTED VERSION
// ============================================================================
// ✅ FIXED: All navigation keys now map to ACTUAL MongoDB permission keys
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:abra_fleet/core/services/safe_api_service.dart';

class PermissionService {
  final SafeApiService _api = SafeApiService();
  
  // Cache permissions to avoid repeated API calls
  Map<String, dynamic> _permissionsCache = {};
  DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  // ============================================================================
  // 🗺️ NAVIGATION TO PERMISSION MAPPING - ✅ FULLY CORRECTED
  // ============================================================================
  // This maps NavigationKeys to the ACTUAL permission keys stored in MongoDB
  
  static const Map<String, String> navigationToPermissionMap = {
    // Dashboard - Available to everyone
    'dashboard': 'dashboard',
    
    // HRM - Correct MongoDB keys
    'hrm_employees': 'hrm_employees',
    'hrm_departments': 'hrm_departments',
    'hrm_attendance': 'hrm_attendance',
    'hrm_leave_requests': 'hrm_leave_requests',
    'hrm_payroll': 'hrm_payroll',
    'hrm_notice_board': 'hrm_notice_board',
    'hrm_kpq': 'hrm_kpq',
    'hrm_kpi_evaluation': 'hrm_kpi_evaluation',
    
    // TMS - Correct MongoDB keys
    'raise_ticket': 'raise_ticket',
    'my_tickets': 'my_tickets',
    'all_tickets': 'all_tickets',
    'closed_tickets': 'closed_tickets',
    
    // Feedback Management
    'feedback_management': 'feedback_management',
    
    // Client Management
    'client_details': 'client_details',
    
    // Customer Management
    'all_customers': 'all_customers',
    'pending_approvals': 'pending_approvals',
    'pending_rosters': 'pending_rosters',
    
    // Driver Management
    'drivers': 'drivers',
    'driver_list': 'drivers',
    'driver_trip_reports': 'driver_feedback',
    'driver_feedback': 'driver_feedback',
    
    // Vehicle Management
    'vehicle_master': 'vehicle_master',
    'vehicle_checklist': 'vehicle_checklist',
    'gps_tracking': 'gps_tracking',
    'maintenance_management': 'maintenance_management',
    
    // Operations
    'trip_operation': 'trip_operation',
    'operations_pending_rosters': 'pending_rosters',
    'operations_admin_trips': 'trip_operation',
    'operations_client_trips': 'client_details',
    
    // Fleet Map
    'fleet_map': 'vehicle_master',
    
    // Trips Summary
    'trips_summary': 'trips_summary',
    
    // SOS Alerts
    'resolved_alerts': 'resolved_alerts',
    'incomplete_alerts': 'incomplete_alerts',
    
    // Finance/Billing
    'finance': 'billing',
    'billing': 'billing',
    
    // Reports
    'reports': 'reports',
    
    // Role Access Control
    'role_access_control': 'role_access_control',
    
    // Tours & Travels
    'tt_tour_packages': 'tt_tour_packages',
    'tt_custom_quotes': 'tt_custom_quotes',
    'tt_sales_leads': 'tt_sales_leads',
    'tt_manual_leads': 'tt_manual_leads',
    'tt_careers': 'tt_careers',
  };

  // ============================================================================
  // 📥 GET USER PERMISSIONS
  // ============================================================================
  Future<Map<String, dynamic>> getUserPermissions() async {
    try {
      // Check cache first
      if (_permissionsCache.isNotEmpty && _lastFetchTime != null) {
        final now = DateTime.now();
        if (now.difference(_lastFetchTime!) < _cacheDuration) {
          debugPrint('🔐 Using cached permissions (${_permissionsCache.keys.length} items)');
          return _permissionsCache;
        }
      }

      debugPrint('🔐 ========================================');
      debugPrint('🔐 FETCHING USER PERMISSIONS FROM BACKEND');
      debugPrint('🔐 ========================================');
      
      // Get current user email from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userEmail = prefs.getString('user_email');
      
      if (userEmail == null) {
        debugPrint('❌ No user email found in SharedPreferences');
        return {};
      }

      debugPrint('🔐 Loading permissions for: $userEmail');

      // Fetch permissions from backend
      final response = await _api.safeGet(
        '/api/employee-management/permissions/$userEmail',
        context: 'User Permissions',
        fallback: {'success': false, 'data': {}},
      );

      if (response['success'] == true && response['data'] != null) {
        final permissions = response['data']['permissions'] as Map<String, dynamic>? ?? {};
        
        debugPrint('✅ Permissions loaded successfully: ${permissions.keys.length} items');
        debugPrint('🔐 Permission keys: ${permissions.keys.join(", ")}');
        
        // Log each permission for debugging
        permissions.forEach((key, value) {
          if (value is Map) {
            debugPrint('   📋 $key: can_access=${value['can_access']}, edit_delete=${value['edit_delete']}');
          }
        });
        
        // Cache the permissions
        _permissionsCache = permissions;
        _lastFetchTime = DateTime.now();
        
        // Also save to SharedPreferences for offline access
        await prefs.setString('user_permissions', jsonEncode(permissions));
        
        debugPrint('🔐 ========================================');
        debugPrint('✅ PERMISSIONS CACHED SUCCESSFULLY');
        debugPrint('🔐 ========================================');
        
        return permissions;
      } else {
        debugPrint('⚠️ Failed to load permissions from backend, checking cache...');
        
        // Try to load from SharedPreferences
        final cachedPermissions = prefs.getString('user_permissions');
        if (cachedPermissions != null) {
          debugPrint('✅ Using cached permissions from SharedPreferences');
          _permissionsCache = jsonDecode(cachedPermissions) as Map<String, dynamic>;
          return _permissionsCache;
        }
      }

      return {};
    } catch (e) {
      debugPrint('❌ Error loading permissions: $e');
      
      // Try to load from SharedPreferences as fallback
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedPermissions = prefs.getString('user_permissions');
        if (cachedPermissions != null) {
          debugPrint('✅ Using cached permissions from SharedPreferences (fallback)');
          _permissionsCache = jsonDecode(cachedPermissions) as Map<String, dynamic>;
          return _permissionsCache;
        }
      } catch (cacheError) {
        debugPrint('❌ Failed to load cached permissions: $cacheError');
      }
      
      return {};
    }
  }

  // ============================================================================
  // 🔍 CHECK IF USER HAS ACCESS
  // ============================================================================
  Future<bool> hasAccess(String permissionKey) async {
    try {
      final permissions = await getUserPermissions();
      
      if (permissions.isEmpty) {
        debugPrint('⚠️ No permissions loaded for key: $permissionKey');
        return false;
      }

      final permission = permissions[permissionKey];
      
      if (permission == null) {
        debugPrint('⚠️ Permission not found: $permissionKey');
        debugPrint('   Available: ${permissions.keys.join(", ")}');
        return false;
      }

      // Handle different data types for can_access
      final canAccess = permission['can_access'];
      
      bool result = false;
      if (canAccess is bool) {
        result = canAccess;
        debugPrint('🔐 Permission $permissionKey: $result (bool)');
      } else if (canAccess is int) {
        result = canAccess == 1;
        debugPrint('🔐 Permission $permissionKey: $result (int: $canAccess)');
      } else if (canAccess is String) {
        result = canAccess.toLowerCase() == 'true' || canAccess == '1';
        debugPrint('🔐 Permission $permissionKey: $result (string: "$canAccess")');
      } else {
        debugPrint('⚠️ Invalid can_access type for $permissionKey: ${canAccess.runtimeType}');
      }
      
      return result;
    } catch (e) {
      debugPrint('❌ Error checking access for $permissionKey: $e');
      return false;
    }
  }

  // ============================================================================
  // 🗺️ GET PERMISSION KEY FROM NAVIGATION KEY
  // ============================================================================
  String? getPermissionKey(String navigationKey) {
    final permissionKey = navigationToPermissionMap[navigationKey];
    
    if (permissionKey == null) {
      debugPrint('⚠️ No permission mapping for navigation key: $navigationKey');
      debugPrint('   Available mappings: ${navigationToPermissionMap.keys.join(", ")}');
    }
    
    return permissionKey;
  }

  // ============================================================================
  // 🔍 CHECK NAVIGATION ACCESS
  // ============================================================================
  Future<bool> hasNavigationAccess(String navigationKey) async {
    debugPrint('🔍 ========================================');
    debugPrint('🔍 Checking navigation access: $navigationKey');
    
    final permissionKey = getPermissionKey(navigationKey);
    
    if (permissionKey == null) {
      debugPrint('❌ No permission mapping for: $navigationKey');
      debugPrint('🔍 ========================================');
      return false;
    }

    debugPrint('🔍 Permission key: $permissionKey');
    final hasAccessResult = await hasAccess(permissionKey);
    debugPrint('🔍 Result: $navigationKey -> $permissionKey = $hasAccessResult');
    debugPrint('🔍 ========================================');
    
    return hasAccessResult;
  }

  // ============================================================================
  // 🔍 CHECK IF USER CAN EDIT/DELETE
  // ============================================================================
  Future<bool> canEditDelete(String permissionKey) async {
    try {
      final permissions = await getUserPermissions();
      
      if (permissions.isEmpty) {
        return false;
      }

      final permission = permissions[permissionKey];
      
      if (permission == null) {
        return false;
      }

      // Handle different data types for edit_delete
      final editDelete = permission['edit_delete'];
      
      if (editDelete is bool) return editDelete;
      if (editDelete is int) return editDelete == 1;
      if (editDelete is String) {
        return editDelete.toLowerCase() == 'true' || editDelete == '1';
      }

      return false;
    } catch (e) {
      debugPrint('❌ Error checking edit/delete permission: $e');
      return false;
    }
  }

  // ============================================================================
  // 🔍 CHECK IF USER HAS ANY OF THE GIVEN PERMISSIONS
  // ============================================================================
  Future<bool> hasAnyPermission(List<String> permissionKeys) async {
    for (final key in permissionKeys) {
      if (await hasAccess(key)) {
        debugPrint('✅ Found permission: $key');
        return true;
      }
    }
    debugPrint('❌ No permissions found in: ${permissionKeys.join(", ")}');
    return false;
  }

  // ============================================================================
  // 🗑️ CLEAR CACHE
  // ============================================================================
  void clearCache() {
    debugPrint('🗑️ Clearing permission cache');
    _permissionsCache.clear();
    _lastFetchTime = null;
  }

  // ============================================================================
  // 🔄 REFRESH PERMISSIONS
  // ============================================================================
  Future<void> refreshPermissions() async {
    debugPrint('🔄 Forcing permission refresh');
    clearCache();
    await getUserPermissions();
  }

  // ============================================================================
  // 📊 GET PERMISSION SUMMARY (FOR DEBUGGING)
  // ============================================================================
  Future<void> logPermissionSummary() async {
    final permissions = await getUserPermissions();
    
    debugPrint('📊 ========================================');
    debugPrint('📊 PERMISSION SUMMARY');
    debugPrint('📊 ========================================');
    debugPrint('📊 Total permissions: ${permissions.keys.length}');
    
    if (permissions.isEmpty) {
      debugPrint('⚠️ No permissions loaded');
    } else {
      permissions.forEach((key, value) {
        if (value is Map) {
          final canAccess = value['can_access'];
          final editDelete = value['edit_delete'];
          debugPrint('   $key: access=$canAccess, edit=$editDelete');
        }
      });
    }
    
    debugPrint('📊 ========================================');
  }
}