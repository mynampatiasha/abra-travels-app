// lib/core/config/navigation_config.dart

import 'package:flutter/material.dart';

/// ============================================================================
/// CENTRALIZED NAVIGATION CONFIGURATION
/// ============================================================================
/// This is the SINGLE SOURCE OF TRUTH for all navigation items in the app.
/// Both admin_main_shell.dart and user_role_admin_access.dart read from here.
/// 
/// ✅ NEW: TMS (Ticket Management System) added!
/// ============================================================================

class NavigationConfig {
  /// All navigation items in the application
  static final Map<String, NavigationItem> items = {
    
    // ========== DASHBOARD ==========
    'dashboard': NavigationItem(
      key: 'dashboard',
      title: 'Dashboard',
      icon: Icons.dashboard_rounded,
      index: 0,
      requiredPermission: 'dashboard',
      description: 'Main dashboard with overview and analytics',
      category: 'Core',
    ),
    
    // ========== VEHICLE MANAGEMENT (PARENT) ==========
    'vehicle_management': NavigationItem(
      key: 'vehicle_management',
      title: 'Vehicle Management',
      icon: Icons.directions_car_filled,
      isParent: true,
      requiredPermission: 'fleet_management',
      description: 'Complete vehicle fleet management',
      category: 'Fleet',
      children: [
        'vehicle_master',
        'trip_operation',
        'gps_tracking',
        'maintenance_management',
        'vehicle_reports',
      ],
    ),
    
    'vehicle_master': NavigationItem(
      key: 'vehicle_master',
      title: 'Vehicle Master',
      parent: 'vehicle_management',
      index: 11,
      requiredPermission: 'fleet_vehicles',
      description: 'Add, edit, delete vehicles',
      category: 'Fleet',
    ),
    
    'trip_operation': NavigationItem(
      key: 'trip_operation',
      title: 'Trip Operation',
      parent: 'vehicle_management',
      index: 12,
      requiredPermission: 'fleet_trips',
      description: 'Start trips, route planning, trip management',
      category: 'Fleet',
    ),
    
    'gps_tracking': NavigationItem(
      key: 'gps_tracking',
      title: 'GPS Tracking',
      parent: 'vehicle_management',
      index: 25,
      requiredPermission: 'fleet_gps_tracking',
      description: 'Real-time vehicle tracking and monitoring',
      category: 'Fleet',
    ),
    
    'maintenance_management': NavigationItem(
      key: 'maintenance_management',
      title: 'Maintenance Management',
      parent: 'vehicle_management',
      index: 13,
      requiredPermission: 'fleet_maintenance',
      description: 'Schedule and track vehicle maintenance',
      category: 'Fleet',
    ),
    
    'vehicle_reports': NavigationItem(
      key: 'vehicle_reports',
      title: 'Reports & Analytics',
      parent: 'vehicle_management',
      index: 14,
      requiredPermission: 'fleet_management',
      description: 'Vehicle-specific reports and analytics',
      category: 'Fleet',
    ),
    
    // ========== DRIVERS ==========
    'drivers': NavigationItem(
      key: 'drivers',
      title: 'Drivers',
      icon: Icons.groups,
      index: 1,
      requiredPermission: 'fleet_drivers',
      description: 'Driver management and monitoring',
      category: 'Fleet',
    ),
    
    // ========== CUSTOMER MANAGEMENT (PARENT) ==========
    'customer_management': NavigationItem(
      key: 'customer_management',
      title: 'Customer Management',
      icon: Icons.people,
      isParent: true,
      requiredPermission: 'customer_fleet',
      description: 'Customer and employee management',
      category: 'Customers',
      children: [
        'all_customers',
        'pending_approvals',
        'pending_rosters',
        'approved_rosters',
        'trip_cancellation',
      ],
    ),
    
    'all_customers': NavigationItem(
      key: 'all_customers',
      title: 'All Customers',
      parent: 'customer_management',
      index: 15,
      requiredPermission: 'customer_fleet',
      description: 'View and manage all customers',
      category: 'Customers',
    ),
    
    'pending_approvals': NavigationItem(
      key: 'pending_approvals',
      title: 'Pending Approvals',
      parent: 'customer_management',
      index: 16,
      requiredPermission: 'customer_fleet',
      description: 'Approve new customer registrations',
      category: 'Customers',
    ),
    
    'pending_rosters': NavigationItem(
      key: 'pending_rosters',
      title: 'Pending Rosters',
      parent: 'customer_management',
      index: 17,
      requiredPermission: 'customer_fleet',
      description: 'Review and assign roster requests',
      category: 'Customers',
    ),
    
    'approved_rosters': NavigationItem(
      key: 'approved_rosters',
      title: 'Approved Rosters',
      parent: 'customer_management',
      index: 18,
      requiredPermission: 'customer_fleet',
      description: 'Manage approved roster assignments',
      category: 'Customers',
    ),
    
    'trip_cancellation': NavigationItem(
      key: 'trip_cancellation',
      title: 'Trip Cancellation',
      parent: 'customer_management',
      index: 19,
      requiredPermission: 'customer_fleet',
      description: 'Handle trip cancellations and leaves',
      category: 'Customers',
    ),
    
    // ========== CLIENT MANAGEMENT (PARENT) ==========
    'client_management': NavigationItem(
      key: 'client_management',
      title: 'Client Management',
      icon: Icons.business,
      isParent: true,
      requiredPermission: 'abra_global_trading',
      description: 'Corporate client management',
      category: 'Clients',
      children: [
        'client_details',
        'billing_invoices',
        'trips',
      ],
    ),
    
    'client_details': NavigationItem(
      key: 'client_details',
      title: 'Client Details',
      parent: 'client_management',
      index: 20,
      requiredPermission: 'abra_global_trading',
      description: 'Manage client accounts and details',
      category: 'Clients',
    ),
    
    'billing_invoices': NavigationItem(
      key: 'billing_invoices',
      title: 'Billing & Invoices',
      parent: 'client_management',
      index: 21,
      requiredPermission: 'abra_global_trading',
      description: 'Invoices, payments, and billing',
      category: 'Clients',
    ),
    
    'trips': NavigationItem(
      key: 'trips',
      title: 'Trips',
      parent: 'client_management',
      index: 22,
      requiredPermission: 'abra_global_trading',
      description: 'Client trip scheduling and management',
      category: 'Clients',
    ),
    
    // ========== FLEET MAP VIEW ==========
    'fleet_map': NavigationItem(
      key: 'fleet_map',
      title: 'Fleet Map View',
      icon: Icons.map,
      index: 5,
      requiredPermission: 'fleet_list',
      description: 'Real-time fleet tracking on map',
      category: 'Fleet',
    ),
    
    // ========== REPORTS ==========
    'reports': NavigationItem(
      key: 'reports',
      title: 'Reports',
      icon: Icons.analytics,
      index: 6,
      requiredPermission: 'fleet_management',
      description: 'Generate system reports and analytics',
      category: 'Reports',
    ),
    
    // ========== SOS ALERTS (PARENT) ==========
    'sos_alerts': NavigationItem(
      key: 'sos_alerts',
      title: 'SOS Alerts',
      icon: Icons.sos_rounded,
      isParent: true,
      requiredPermission: 'fleet_management',
      description: 'Emergency SOS alert management',
      category: 'Emergency',
      children: [
        'incomplete_alerts',
        'resolved_alerts',
      ],
    ),
    
    'incomplete_alerts': NavigationItem(
      key: 'incomplete_alerts',
      title: 'Incomplete Alerts',
      parent: 'sos_alerts',
      index: 8,
      requiredPermission: 'fleet_management',
      description: 'Handle active SOS emergency alerts',
      category: 'Emergency',
    ),
    
    'resolved_alerts': NavigationItem(
      key: 'resolved_alerts',
      title: 'Resolved Alerts',
      parent: 'sos_alerts',
      index: 7,
      requiredPermission: 'fleet_management',
      description: 'View resolved SOS alerts history',
      category: 'Emergency',
    ),
    
    // ========== 🎫 TMS - TICKET MANAGEMENT SYSTEM (NEW!) ==========
    'tms': NavigationItem(
      key: 'tms',
      title: 'TMS',
      icon: Icons.confirmation_number_rounded,
      isParent: true,
      requiredPermission: 'fleet_management',
      description: 'Complete Ticket Management System',
      category: 'Support',
      children: [
        'raise_ticket',
        'my_tickets',
        'all_tickets',
        'closed_tickets',
      ],
    ),
    
    'raise_ticket': NavigationItem(
      key: 'raise_ticket',
      title: 'Raise a Ticket',
      parent: 'tms',
      index: 36,
      requiredPermission: 'fleet_management',
      description: 'Create and submit new support tickets',
      category: 'Support',
    ),
    
    'my_tickets': NavigationItem(
      key: 'my_tickets',
      title: 'My Tickets',
      parent: 'tms',
      index: 37,
      requiredPermission: 'fleet_management',
      description: 'View tickets assigned to you',
      category: 'Support',
    ),
    
    'all_tickets': NavigationItem(
      key: 'all_tickets',
      title: 'All Tickets',
      parent: 'tms',
      index: 38,
      requiredPermission: 'fleet_management',
      description: 'Manage all tickets in the system (Admin)',
      category: 'Support',
    ),
    
    'closed_tickets': NavigationItem(
      key: 'closed_tickets',
      title: 'Closed Tickets',
      parent: 'tms',
      index: 39,
      requiredPermission: 'fleet_management',
      description: 'Archive of resolved and closed tickets',
      category: 'Support',
    ),
    
    // ========== HRM PORTAL (PARENT) ==========
    'hrm_portal': NavigationItem(
      key: 'hrm_portal',
      title: 'HRM Portal',
      icon: Icons.people,
      isParent: true,
      requiredPermission: 'hrm_feedback',
      description: 'Human Resource Management',
      category: 'HRM',
      children: [
        'hrm_employees',
        //'hrm_departments',
        'hrm_leave_requests',
        'notice_board',
        'attendance',
      ],
    ),
    
    'hrm_employees': NavigationItem(
      key: 'hrm_employees',
      title: 'Employees',
      parent: 'hrm_portal',
      index: 32,
      requiredPermission: 'hrm_feedback',
      description: 'Employee management and records',
      category: 'HRM',
    ),
    
    // 'hrm_departments': NavigationItem(
    //   key: 'hrm_departments',
    //   title: 'Departments',
    //   parent: 'hrm_portal',
    //   index: 33,
    //   requiredPermission: 'hrm_feedback',
    //   description: 'Department management and structure',
    //   category: 'HRM',
    // ),
    
    'hrm_leave_requests': NavigationItem(
      key: 'hrm_leave_requests',
      title: 'Leave Requests',
      parent: 'hrm_portal',
      index: 34,
      requiredPermission: 'hrm_feedback',
      description: 'Employee leave request management',
      category: 'HRM',
    ),
    
    'notice_board': NavigationItem(
      key: 'notice_board',
      title: 'Notice Board',
      parent: 'hrm_portal',
      index: 30,
      requiredPermission: 'hrm_feedback',
      description: 'Company announcements and notices',
      category: 'HRM',
    ),
    
    'attendance': NavigationItem(
      key: 'attendance',
      title: 'Attendance',
      parent: 'hrm_portal',
      index: 31,
      requiredPermission: 'hrm_feedback',
      description: 'Employee attendance tracking',
      category: 'HRM',
    ),
    
    // ========== FEEDBACK (PARENT) ==========
    'feedback': NavigationItem(
      key: 'feedback',
      title: 'Feedback',
      icon: Icons.feedback,
      isParent: true,
      requiredPermission: 'hrm_feedback',
      description: 'Feedback from customers, drivers, and clients',
      category: 'Feedback',
      children: [
        'customer_feedback',
        'driver_feedback',
        'client_feedback',
      ],
    ),
    
    'customer_feedback': NavigationItem(
      key: 'customer_feedback',
      title: 'Customer Feedback',
      parent: 'feedback',
      index: 27,
      requiredPermission: 'hrm_feedback',
      description: 'View and manage customer feedback',
      category: 'Feedback',
    ),
    
    'driver_feedback': NavigationItem(
      key: 'driver_feedback',
      title: 'Driver Feedback',
      parent: 'feedback',
      index: 28,
      requiredPermission: 'hrm_feedback',
      description: 'View and manage driver feedback',
      category: 'Feedback',
    ),
    
    'client_feedback': NavigationItem(
      key: 'client_feedback',
      title: 'Client Feedback',
      parent: 'feedback',
      index: 29,
      requiredPermission: 'hrm_feedback',
      description: 'View and manage client feedback',
      category: 'Feedback',
    ),
    
    // ========== ROLE ACCESS CONTROL ==========
    'role_access_control': NavigationItem(
      key: 'role_access_control',
      title: 'Role Access Control',
      icon: Icons.admin_panel_settings,
      index: 24,
      requiredPermission: 'fleet_management',
      description: 'Manage user roles and permissions',
      category: 'Administration',
    ),
  };
  
  // ========== HELPER METHODS ==========
  
  /// Get all parent items (items without a parent)
  static List<NavigationItem> getParentItems() {
    return items.values
        .where((item) => item.parent == null)
        .toList()
      ..sort((a, b) => (a.index ?? 999).compareTo(b.index ?? 999));
  }
  
  /// Get children of a specific parent
  static List<NavigationItem> getChildrenOf(String parentKey) {
    final parent = items[parentKey];
    if (parent == null || parent.children == null) return [];
    
    return parent.children!
        .map((childKey) => items[childKey])
        .whereType<NavigationItem>()
        .toList()
      ..sort((a, b) => (a.index ?? 999).compareTo(b.index ?? 999));
  }
  
  /// Get all navigation keys (for permissions)
  static List<String> getAllKeys() {
    return items.keys.toList()..sort();
  }
  
  /// Get all leaf items (items that can be directly accessed, not parent containers)
  static List<NavigationItem> getAllLeafItems() {
    return items.values
        .where((item) => !item.isParent)
        .toList()
      ..sort((a, b) => (a.index ?? 999).compareTo(b.index ?? 999));
  }
  
  /// Get item by key
  static NavigationItem? getItem(String key) {
    return items[key];
  }
  
  /// Get all items that require a specific permission
  static List<NavigationItem> getItemsByPermission(String permission) {
    return items.values
        .where((item) => item.requiredPermission == permission)
        .toList();
  }
  
  /// Get all items in a specific category
  static List<NavigationItem> getItemsByCategory(String category) {
    return items.values
        .where((item) => item.category == category)
        .toList();
  }
  
  /// Get all unique categories
  static List<String> getAllCategories() {
    return items.values
        .map((item) => item.category)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
  }
  
  /// Get all unique permissions
  static List<String> getAllPermissions() {
    return items.values
        .map((item) => item.requiredPermission)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
  }
  
  /// Check if a user has permission to access an item
  static bool hasPermission(
    String itemKey, 
    Map<String, bool> userPermissions,
  ) {
    final item = items[itemKey];
    if (item == null) return false;
    
    final permission = item.requiredPermission;
    if (permission == null) return true; // No permission required
    
    return userPermissions[permission] == true;
  }
  
  /// Get all accessible items for a user based on their permissions
  static List<NavigationItem> getAccessibleItems(
    Map<String, bool> userPermissions,
  ) {
    return items.values
        .where((item) => hasPermission(item.key, userPermissions))
        .toList();
  }
}

// ========== NAVIGATION ITEM CLASS ==========
class NavigationItem {
  final String key;
  final String title;
  final IconData? icon;
  final int? index;
  final bool isParent;
  final String? parent;
  final List<String>? children;
  final String? requiredPermission;
  final String? description;
  final String? category;
  
  NavigationItem({
    required this.key,
    required this.title,
    this.icon,
    this.index,
    this.isParent = false,
    this.parent,
    this.children,
    this.requiredPermission,
    this.description,
    this.category,
  });
  
  /// Check if this item has children
  bool get hasChildren => children != null && children!.isNotEmpty;
  
  /// Get display title
  String get displayTitle => title;
  
  /// Get formatted permission name for display
  String get permissionDisplayName {
    if (requiredPermission == null) return 'No permission required';
    return requiredPermission!
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
  
  /// Convert to JSON for API calls
  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'title': title,
      'index': index,
      'isParent': isParent,
      'parent': parent,
      'children': children,
      'requiredPermission': requiredPermission,
      'description': description,
      'category': category,
    };
  }
  
  /// Create from JSON
  factory NavigationItem.fromJson(Map<String, dynamic> json) {
    return NavigationItem(
      key: json['key'] as String,
      title: json['title'] as String,
      index: json['index'] as int?,
      isParent: json['isParent'] as bool? ?? false,
      parent: json['parent'] as String?,
      children: (json['children'] as List<dynamic>?)?.cast<String>(),
      requiredPermission: json['requiredPermission'] as String?,
      description: json['description'] as String?,
      category: json['category'] as String?,
    );
  }
}