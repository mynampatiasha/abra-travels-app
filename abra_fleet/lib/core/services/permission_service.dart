// lib/core/services/permission_service.dart
// ============================================================================
// 🔐 PERMISSION SERVICE — BILLING-STYLE (thin wrapper)
// ============================================================================
// The admin_main_shell.dart now loads permissions once at login and checks
// them synchronously from its local _permissions map (same as billing_main_shell).
//
// This service is kept for backward compatibility with any other callers.
// It reads from SharedPreferences cache (written by admin_main_shell on load).
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:abra_fleet/core/services/safe_api_service.dart';

class PermissionService {
  final SafeApiService _api = SafeApiService();

  // In-memory cache (mirrors what admin_main_shell stores in _permissions)
  Map<String, dynamic> _cache = {};
  DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  // ── Navigation key → permission key map ──────────────────────────────────
  static const Map<String, String> navigationToPermissionMap = {
    'dashboard': 'dashboard',
    'hrm_employees': 'hrm_employees',
    'hrm_departments': 'hrm_departments',
    'hrm_attendance': 'hrm_attendance',
    'hrm_leave_requests': 'hrm_leave_requests',
    'hrm_payroll': 'hrm_payroll',
    'hrm_notice_board': 'hrm_notice_board',
    'hrm_kpq': 'hrm_kpq',
    'hrm_kpi_evaluation': 'hrm_kpi_evaluation',
    'raise_ticket': 'raise_ticket',
    'my_tickets': 'my_tickets',
    'all_tickets': 'all_tickets',
    'closed_tickets': 'closed_tickets',
    'feedback_management': 'feedback_management',
    'client_details': 'client_details',
    'all_customers': 'all_customers',
    'pending_approvals': 'pending_approvals',
    'pending_rosters': 'pending_rosters',
    'drivers': 'drivers',
    'driver_list': 'drivers',
    'driver_trip_reports': 'driver_feedback',
    'driver_feedback': 'driver_feedback',
    'vehicle_master': 'vehicle_master',
    'vehicle_checklist': 'vehicle_checklist',
    'gps_tracking': 'gps_tracking',
    'maintenance_management': 'maintenance_management',
    'trip_operation': 'trip_operation',
    'operations_pending_rosters': 'pending_rosters',
    'operations_admin_trips': 'trip_operation',
    'operations_client_trips': 'client_details',
    'fleet_map': 'vehicle_master',
    'trips_summary': 'trips_summary',
    'resolved_alerts': 'resolved_alerts',
    'incomplete_alerts': 'incomplete_alerts',
    'finance': 'billing',
    'billing': 'billing',
    'reports': 'reports',
    'role_access_control': 'role_access_control',
    'tt_tour_packages': 'tt_tour_packages',
    'tt_custom_quotes': 'tt_custom_quotes',
    'tt_sales_leads': 'tt_sales_leads',
    'tt_manual_leads': 'tt_manual_leads',
    'tt_careers': 'tt_careers',
    'customer_analytics': 'customer_analytics_al',
    'meta_ads_analytics': 'meta_ads_analytics_al',
    'google_ads_analytics': 'google_ads_analytics_al',
    'search_console': 'search_console_al',
    'content_studio': 'youtube_studio_al',
    'video_insights': 'youtube_studio_al',
    'content_and_posts': 'social_media_al',
    'reports_and_insights': 'social_media_al',
    'hrm_workforce_journey': 'hrm_workforce_journey',
    'hrm_hiring_process': 'hrm_hiring_process',
    'hrm_screening_kpq': 'hrm_screening_kpq',
    'hrm_onboarding': 'hrm_onboarding',
    'hrm_training_oje': 'hrm_training_oje',
    'hrm_employee_checklist': 'hrm_employee_checklist',
    'hrm_employee_evaluation': 'hrm_employee_evaluation',
    'hrm_exit_initiation': 'hrm_exit_initiation',
    'hrm_exit_handover': 'hrm_exit_handover',
    'hrm_exit_interview': 'hrm_exit_interview',
    'hrm_exit_settlement': 'hrm_exit_settlement',
    'expense_tracker': 'expense_tracker',
    'essential_purchases': 'essential_purchases',
  };

  // ── Read permissions (SharedPreferences first, then backend) ─────────────
  Future<Map<String, dynamic>> getUserPermissions() async {
    try {
      // In-memory cache
      if (_cache.isNotEmpty && _lastFetchTime != null) {
        if (DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
          return _cache;
        }
      }

      final prefs = await SharedPreferences.getInstance();

      // SharedPreferences cache (written by admin_main_shell)
      final cached = prefs.getString('user_permissions');
      if (cached != null && cached.isNotEmpty) {
        final decoded = jsonDecode(cached);
        if (decoded is Map<String, dynamic>) {
          _cache = decoded;
          _lastFetchTime = DateTime.now();
          debugPrint('🔐 PermissionService: ${_cache.length} permissions from cache');
          return _cache;
        }
      }

      // Fallback: fetch from backend
      final email = prefs.getString('user_email') ?? '';
      if (email.isEmpty) return {};

      final response = await _api.safeGet(
        '/api/employee-management/permissions/$email',
        context: 'PermissionService.getUserPermissions',
        fallback: {'success': false, 'data': {}},
      );

      if (response['success'] == true && response['data'] != null) {
        dynamic raw = response['data'];
        if (raw is Map && raw.containsKey('permissions')) raw = raw['permissions'];

        if (raw is Map<String, dynamic>) {
          final Map<String, dynamic> normalised = {};
          raw.forEach((key, value) {
            if (value is Map) {
              final ca = value['can_access'];
              final ed = value['edit_delete'];
              normalised[key] = {
                'can_access': ca == true || ca == 1 || ca == '1' || ca == 'true',
                'edit_delete': ed == true || ed == 1 || ed == '1' || ed == 'true',
              };
            } else if (value is bool) {
              normalised[key] = {'can_access': value, 'edit_delete': false};
            } else {
              normalised[key] = {'can_access': false, 'edit_delete': false};
            }
          });
          await prefs.setString('user_permissions', jsonEncode(normalised));
          _cache = normalised;
          _lastFetchTime = DateTime.now();
          return _cache;
        }
      }

      return {};
    } catch (e) {
      debugPrint('❌ PermissionService.getUserPermissions error: $e');
      return {};
    }
  }

  // ── Synchronous check against in-memory cache ─────────────────────────────
  bool hasPermissionSync(String permissionKey) {
    final perm = _cache[permissionKey];
    if (perm == null) return false;
    if (perm is Map) {
      final ca = perm['can_access'];
      return ca == true || ca == 1 || ca == '1' || ca == 'true';
    }
    if (perm is bool) return perm;
    if (perm is int) return perm == 1;
    return false;
  }

  // ── Async wrappers (kept for backward compat) ─────────────────────────────
  Future<bool> hasAccess(String permissionKey) async {
    final permissions = await getUserPermissions();
    final perm = permissions[permissionKey];
    if (perm == null) return false;
    if (perm is Map) {
      final ca = perm['can_access'];
      return ca == true || ca == 1 || ca == '1' || ca == 'true';
    }
    if (perm is bool) return perm;
    if (perm is int) return perm == 1;
    return false;
  }

  Future<bool> hasNavigationAccess(String navigationKey) async {
    final permKey = navigationToPermissionMap[navigationKey];
    if (permKey == null) return false;
    return hasAccess(permKey);
  }

  Future<bool> canEditDelete(String permissionKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final role = (prefs.getString('user_role') ?? '').toLowerCase();
      if (role == 'super_admin' || role == 'admin') {
        return true;
      }
    } catch (_) {}

    final permissions = await getUserPermissions();
    final perm = permissions[permissionKey];
    if (perm == null) return false;
    if (perm is Map) {
      final ed = perm['edit_delete'];
      return ed == true || ed == 1 || ed == '1' || ed == 'true';
    }
    return false;
  }

  Future<bool> hasAnyPermission(List<String> permissionKeys) async {
    for (final key in permissionKeys) {
      if (await hasAccess(key)) return true;
    }
    return false;
  }

  String? getPermissionKey(String navigationKey) =>
      navigationToPermissionMap[navigationKey];

  void clearCache() {
    _cache.clear();
    _lastFetchTime = null;
  }

  Future<void> refreshPermissions() async {
    clearCache();
    await getUserPermissions();
  }
}
