// lib/features/admin/customer_management/notification/roster_model.dart

// Firebase removed - using HTTP API
import 'package:flutter/material.dart';

class RosterNotification {
  final String id;
  final String customerId;
  final String customerName;
  final String rosterType; // 'login', 'logout', 'both'
  final String officeLocation;
  final List<String> weekdays;
  final DateTime fromDate;
  final DateTime toDate;
  final TimeOfDay fromTime;
  final TimeOfDay toTime;
  final String status; // 'pending_assignment', 'assigned', 'cancelled'
  final DateTime createdAt;
  final Map<String, dynamic>? loginPickupLocation;
  final String? loginPickupAddress;
  final Map<String, dynamic>? logoutDropLocation;
  final String? logoutDropAddress;
  final String? notes;
  final String? assignedDriverId;
  final String? assignedVehicleId;

  RosterNotification({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.rosterType,
    required this.officeLocation,
    required this.weekdays,
    required this.fromDate,
    required this.toDate,
    required this.fromTime,
    required this.toTime,
    required this.status,
    required this.createdAt,
    this.loginPickupLocation,
    this.loginPickupAddress,
    this.logoutDropLocation,
    this.logoutDropAddress,
    this.notes,
    this.assignedDriverId,
    this.assignedVehicleId,
  });

  // Removed Firebase DataSnapshot method - use fromJson instead
  // factory RosterNotification.fromSnapshot(DataSnapshot snapshot) { ... }

  factory RosterNotification.fromJson(Map<String, dynamic> json) {
    return RosterNotification(
      id: json['_id'] ?? json['id'] ?? '',
      customerId: json['userId'] ?? '',
      customerName: json['customerName'] ?? 'Unknown Customer',
      rosterType: json['rosterType'] ?? 'both',
      officeLocation: json['officeLocation'] ?? '',
      weekdays: List<String>.from(json['weekdays'] ?? []),
      fromDate: DateTime.parse(json['fromDate'] ?? DateTime.now().toIso8601String()),
      toDate: DateTime.parse(json['toDate'] ?? DateTime.now().toIso8601String()),
      fromTime: _parseTimeOfDay(json['fromTime']),
      toTime: _parseTimeOfDay(json['toTime']),
      status: json['status'] ?? 'pending_assignment',
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      loginPickupLocation: json['loginPickupLocation'],
      loginPickupAddress: json['loginPickupAddress'],
      logoutDropLocation: json['logoutDropLocation'],
      logoutDropAddress: json['logoutDropAddress'],
      notes: json['notes'],
      assignedDriverId: json['assignedDriverId'],
      assignedVehicleId: json['assignedVehicleId'],
    );
  }

  static TimeOfDay _parseTimeOfDay(dynamic timeData) {
    if (timeData == null) return const TimeOfDay(hour: 9, minute: 0);
    
    if (timeData is String) {
      final parts = timeData.split(':');
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    }
    
    return const TimeOfDay(hour: 9, minute: 0);
  }

  String get formattedDateRange {
    return '${_formatDate(fromDate)} - ${_formatDate(toDate)}';
  }

  String get formattedTimeRange {
    return '${_formatTime(fromTime)} - ${_formatTime(toTime)}';
  }

  String get weekdaysDisplay {
    return weekdays.join(', ');
  }

  String get rosterTypeDisplay {
    switch (rosterType) {
      case 'login':
        return 'Login Only';
      case 'logout':
        return 'Logout Only';
      case 'both':
        return 'Login & Logout';
      default:
        return rosterType;
    }
  }

  String get statusDisplay {
    switch (status) {
      case 'pending_assignment':
        return 'Pending Assignment';
      case 'assigned':
        return 'Assigned';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Color get statusColor {
    switch (status) {
      case 'pending_assignment':
        return Colors.orange;
      case 'assigned':
        return Colors.blue;
      case 'in_progress':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  bool get isPending => status == 'pending_assignment';
  bool get isAssigned => status == 'assigned';

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}