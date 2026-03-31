// lib/core/services/role_dashboard_service.dart
// Service to provide role-based dashboard content

import 'package:flutter/material.dart';

class RoleDashboardService {
  // Get dashboard cards based on user role
  static List<Map<String, dynamic>> getDashboardCards(String? userRole) {
    switch (userRole?.toLowerCase().replaceAll(' ', '_')) {
      case 'super_admin':
        return _getSuperAdminCards();
      case 'hr_manager':
        return _getHRManagerCards();
      case 'fleet_manager':
        return _getFleetManagerCards();
      case 'finance':
        return _getFinanceCards();
      default:
        return _getDefaultCards();
    }
  }

  static List<Map<String, dynamic>> _getSuperAdminCards() {
    return [
      {
        'title': 'Total Vehicles',
        'icon': Icons.directions_car,
        'color': Colors.blue,
        'navigationIndex': 1,
      },
      {
        'title': 'Active Drivers',
        'icon': Icons.groups,
        'color': Colors.green,
        'navigationIndex': 2,
      },
      {
        'title': 'Total Customers',
        'icon': Icons.people,
        'color': Colors.orange,
        'navigationIndex': 3,
      },
      {
        'title': 'Active Trips',
        'icon': Icons.route,
        'color': Colors.purple,
        'navigationIndex': 6,
      },
      {
        'title': 'SOS Alerts',
        'icon': Icons.warning,
        'color': Colors.red,
        'navigationIndex': 9,
      },
      {
        'title': 'Reports',
        'icon': Icons.analytics,
        'color': Colors.teal,
        'navigationIndex': 7,
      },
    ];
  }

  static List<Map<String, dynamic>> _getHRManagerCards() {
    return [
      {
        'title': 'Total Customers',
        'icon': Icons.people,
        'color': Colors.orange,
        'navigationIndex': 3,
      },
      {
        'title': 'Pending Approvals',
        'icon': Icons.pending_actions,
        'color': Colors.amber,
        'navigationIndex': 18,
      },
      {
        'title': 'Pending Rosters',
        'icon': Icons.calendar_month,
        'color': Colors.blue,
        'navigationIndex': 19,
      },
      {
        'title': 'Approved Rosters',
        'icon': Icons.check_circle,
        'color': Colors.green,
        'navigationIndex': 20,
      },
      {
        'title': 'HR Reports',
        'icon': Icons.analytics,
        'color': Colors.teal,
        'navigationIndex': 7,
      },
    ];
  }

  static List<Map<String, dynamic>> _getFleetManagerCards() {
    return [
      {
        'title': 'Total Vehicles',
        'icon': Icons.directions_car,
        'color': Colors.blue,
        'navigationIndex': 1,
      },
      {
        'title': 'Active Drivers',
        'icon': Icons.groups,
        'color': Colors.green,
        'navigationIndex': 2,
      },
      {
        'title': 'Vehicle Maintenance',
        'icon': Icons.build,
        'color': Colors.orange,
        'navigationIndex': 14,
      },
      {
        'title': 'Live Tracking',
        'icon': Icons.map,
        'color': Colors.purple,
        'navigationIndex': 6,
      },
      {
        'title': 'SOS Alerts',
        'icon': Icons.warning,
        'color': Colors.red,
        'navigationIndex': 9,
      },
      {
        'title': 'Fleet Reports',
        'icon': Icons.analytics,
        'color': Colors.teal,
        'navigationIndex': 7,
      },
    ];
  }

  static List<Map<String, dynamic>> _getFinanceCards() {
    return [
      {
        'title': 'Client Management',
        'icon': Icons.business,
        'color': Colors.blue,
        'navigationIndex': 4,
      },
      {
        'title': 'Billing & Invoices',
        'icon': Icons.receipt,
        'color': Colors.green,
        'navigationIndex': 23,
      },
      {
        'title': 'Trip Billing',
        'icon': Icons.route,
        'color': Colors.orange,
        'navigationIndex': 24,
      },
      {
        'title': 'Financial Reports',
        'icon': Icons.analytics,
        'color': Colors.teal,
        'navigationIndex': 7,
      },
    ];
  }

  static List<Map<String, dynamic>> _getDefaultCards() {
    return [
      {
        'title': 'Dashboard',
        'icon': Icons.dashboard,
        'color': Colors.blue,
        'navigationIndex': 0,
      },
    ];
  }

  // Get welcome message based on role
  static String getWelcomeMessage(String? userRole, String? userName) {
    final name = userName ?? 'User';
    switch (userRole?.toLowerCase().replaceAll(' ', '_')) {
      case 'super_admin':
        return 'Welcome back, $name! You have full system access.';
      case 'hr_manager':
        return 'Welcome back, $name! Manage customers and rosters efficiently.';
      case 'fleet_manager':
        return 'Welcome back, $name! Keep your fleet running smoothly.';
      case 'finance':
        return 'Welcome back, $name! Manage billing and financial operations.';
      default:
        return 'Welcome back, $name!';
    }
  }

  // Get role-specific quick actions
  static List<Map<String, dynamic>> getQuickActions(String? userRole) {
    switch (userRole?.toLowerCase().replaceAll(' ', '_')) {
      case 'super_admin':
        return [
          {'title': 'Add Vehicle', 'icon': Icons.add_circle, 'action': 'add_vehicle'},
          {'title': 'Create User', 'icon': Icons.person_add, 'action': 'create_user'},
          {'title': 'System Settings', 'icon': Icons.settings, 'action': 'settings'},
        ];
      case 'hr_manager':
        return [
          {'title': 'Approve Customer', 'icon': Icons.person_add, 'action': 'approve_customer'},
          {'title': 'Assign Roster', 'icon': Icons.assignment, 'action': 'assign_roster'},
          {'title': 'View Requests', 'icon': Icons.inbox, 'action': 'view_requests'},
        ];
      case 'fleet_manager':
        return [
          {'title': 'Add Vehicle', 'icon': Icons.add_circle, 'action': 'add_vehicle'},
          {'title': 'Schedule Maintenance', 'icon': Icons.build, 'action': 'schedule_maintenance'},
          {'title': 'Track Fleet', 'icon': Icons.map, 'action': 'track_fleet'},
        ];
      case 'finance':
        return [
          {'title': 'Generate Invoice', 'icon': Icons.receipt, 'action': 'generate_invoice'},
          {'title': 'View Payments', 'icon': Icons.payment, 'action': 'view_payments'},
          {'title': 'Financial Report', 'icon': Icons.analytics, 'action': 'financial_report'},
        ];
      default:
        return [];
    }
  }
}