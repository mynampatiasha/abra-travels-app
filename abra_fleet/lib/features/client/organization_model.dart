// lib/features/client/organization_model.dart

import 'package:flutter/material.dart';

class OrganizationModel {
  final String id;
  final String name;
  final String? logo;
  final String address;
  final String contactEmail;
  final String contactPhone;
  final List<ShiftDefinition> shifts;
  final OrganizationSettings settings;
  final DateTime createdAt;
  final DateTime updatedAt;

  OrganizationModel({
    required this.id,
    required this.name,
    this.logo,
    required this.address,
    required this.contactEmail,
    required this.contactPhone,
    required this.shifts,
    required this.settings,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OrganizationModel.fromJson(Map<String, dynamic> json) {
    return OrganizationModel(
      id: json['id'] ?? json['_id'] ?? '',
      name: json['name'] ?? '',
      logo: json['logo'],
      address: json['address'] ?? '',
      contactEmail: json['contactEmail'] ?? '',
      contactPhone: json['contactPhone'] ?? '',
      shifts: (json['shifts'] as List<dynamic>?)
              ?.map((e) => ShiftDefinition.fromJson(e))
              .toList() ??
          [],
      settings: OrganizationSettings.fromJson(json['settings'] ?? {}),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'logo': logo,
      'address': address,
      'contactEmail': contactEmail,
      'contactPhone': contactPhone,
      'shifts': shifts.map((e) => e.toJson()).toList(),
      'settings': settings.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  OrganizationModel copyWith({
    String? id,
    String? name,
    String? logo,
    String? address,
    String? contactEmail,
    String? contactPhone,
    List<ShiftDefinition>? shifts,
    OrganizationSettings? settings,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OrganizationModel(
      id: id ?? this.id,
      name: name ?? this.name,
      logo: logo ?? this.logo,
      address: address ?? this.address,
      contactEmail: contactEmail ?? this.contactEmail,
      contactPhone: contactPhone ?? this.contactPhone,
      shifts: shifts ?? this.shifts,
      settings: settings ?? this.settings,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ShiftDefinition {
  final String id;
  final String shiftName;
  final String shiftType; // 'morning', 'afternoon', 'evening', 'night', 'custom'
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final String? description;
  final Color? color;
  final bool isActive;
  final int maxEmployees;
  final List<String> allowedDays; // ['Mon', 'Tue', 'Wed', etc.]

  ShiftDefinition({
    required this.id,
    required this.shiftName,
    required this.shiftType,
    required this.startTime,
    required this.endTime,
    this.description,
    this.color,
    this.isActive = true,
    this.maxEmployees = 0, // 0 means unlimited
    this.allowedDays = const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
  });

  factory ShiftDefinition.fromJson(Map<String, dynamic> json) {
    return ShiftDefinition(
      id: json['id'] ?? '',
      shiftName: json['shiftName'] ?? '',
      shiftType: json['shiftType'] ?? 'custom',
      startTime: _parseTimeOfDay(json['startTime']),
      endTime: _parseTimeOfDay(json['endTime']),
      description: json['description'],
      color: json['color'] != null ? Color(json['color']) : null,
      isActive: json['isActive'] ?? true,
      maxEmployees: json['maxEmployees'] ?? 0,
      allowedDays: (json['allowedDays'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shiftName': shiftName,
      'shiftType': shiftType,
      'startTime': '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}',
      'endTime': '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
      'description': description,
      'color': color?.value,
      'isActive': isActive,
      'maxEmployees': maxEmployees,
      'allowedDays': allowedDays,
    };
  }

  static TimeOfDay _parseTimeOfDay(dynamic timeString) {
    try {
      if (timeString is String) {
        final parts = timeString.split(':');
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
      return TimeOfDay.now();
    } catch (e) {
      return TimeOfDay.now();
    }
  }

  String getTimeRange() {
  final startFormatted = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
  final endFormatted = '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}';
  return '$startFormatted - $endFormatted';
}

  String getFormattedTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Duration getShiftDuration() {
    final start = Duration(hours: startTime.hour, minutes: startTime.minute);
    final end = Duration(hours: endTime.hour, minutes: endTime.minute);
    
    if (end < start) {
      // Shift crosses midnight
      return Duration(hours: 24) - start + end;
    }
    return end - start;
  }

  bool isOvernight() {
    return endTime.hour < startTime.hour ||
        (endTime.hour == startTime.hour && endTime.minute < startTime.minute);
  }

  ShiftDefinition copyWith({
    String? id,
    String? shiftName,
    String? shiftType,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    String? description,
    Color? color,
    bool? isActive,
    int? maxEmployees,
    List<String>? allowedDays,
  }) {
    return ShiftDefinition(
      id: id ?? this.id,
      shiftName: shiftName ?? this.shiftName,
      shiftType: shiftType ?? this.shiftType,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      description: description ?? this.description,
      color: color ?? this.color,
      isActive: isActive ?? this.isActive,
      maxEmployees: maxEmployees ?? this.maxEmployees,
      allowedDays: allowedDays ?? this.allowedDays,
    );
  }
}

class OrganizationSettings {
  final bool allowCustomShifts;
  final bool requireApprovalForRoster;
  final int maxRostersPerEmployee;
  final int minAdvanceBookingDays;
  final int maxAdvanceBookingDays;
  final bool allowOverlappingRosters;
  final bool autoAssignVehicles;
  final bool notifyOnRosterChanges;
  final String timezone;

  OrganizationSettings({
    this.allowCustomShifts = false,
    this.requireApprovalForRoster = true,
    this.maxRostersPerEmployee = 5,
    this.minAdvanceBookingDays = 1,
    this.maxAdvanceBookingDays = 90,
    this.allowOverlappingRosters = false,
    this.autoAssignVehicles = true,
    this.notifyOnRosterChanges = true,
    this.timezone = 'Asia/Kolkata',
  });

  factory OrganizationSettings.fromJson(Map<String, dynamic> json) {
    return OrganizationSettings(
      allowCustomShifts: json['allowCustomShifts'] ?? false,
      requireApprovalForRoster: json['requireApprovalForRoster'] ?? true,
      maxRostersPerEmployee: json['maxRostersPerEmployee'] ?? 5,
      minAdvanceBookingDays: json['minAdvanceBookingDays'] ?? 1,
      maxAdvanceBookingDays: json['maxAdvanceBookingDays'] ?? 90,
      allowOverlappingRosters: json['allowOverlappingRosters'] ?? false,
      autoAssignVehicles: json['autoAssignVehicles'] ?? true,
      notifyOnRosterChanges: json['notifyOnRosterChanges'] ?? true,
      timezone: json['timezone'] ?? 'Asia/Kolkata',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'allowCustomShifts': allowCustomShifts,
      'requireApprovalForRoster': requireApprovalForRoster,
      'maxRostersPerEmployee': maxRostersPerEmployee,
      'minAdvanceBookingDays': minAdvanceBookingDays,
      'maxAdvanceBookingDays': maxAdvanceBookingDays,
      'allowOverlappingRosters': allowOverlappingRosters,
      'autoAssignVehicles': autoAssignVehicles,
      'notifyOnRosterChanges': notifyOnRosterChanges,
      'timezone': timezone,
    };
  }

  OrganizationSettings copyWith({
    bool? allowCustomShifts,
    bool? requireApprovalForRoster,
    int? maxRostersPerEmployee,
    int? minAdvanceBookingDays,
    int? maxAdvanceBookingDays,
    bool? allowOverlappingRosters,
    bool? autoAssignVehicles,
    bool? notifyOnRosterChanges,
    String? timezone,
  }) {
    return OrganizationSettings(
      allowCustomShifts: allowCustomShifts ?? this.allowCustomShifts,
      requireApprovalForRoster: requireApprovalForRoster ?? this.requireApprovalForRoster,
      maxRostersPerEmployee: maxRostersPerEmployee ?? this.maxRostersPerEmployee,
      minAdvanceBookingDays: minAdvanceBookingDays ?? this.minAdvanceBookingDays,
      maxAdvanceBookingDays: maxAdvanceBookingDays ?? this.maxAdvanceBookingDays,
      allowOverlappingRosters: allowOverlappingRosters ?? this.allowOverlappingRosters,
      autoAssignVehicles: autoAssignVehicles ?? this.autoAssignVehicles,
      notifyOnRosterChanges: notifyOnRosterChanges ?? this.notifyOnRosterChanges,
      timezone: timezone ?? this.timezone,
    );
  }
}

// Predefined shift templates
class ShiftTemplates {
  static List<ShiftDefinition> getDefaultShifts() {
    return [
      ShiftDefinition(
        id: 'shift_morning',
        shiftName: 'Morning Shift',
        shiftType: 'morning',
        startTime: const TimeOfDay(hour: 9, minute: 0),
        endTime: const TimeOfDay(hour: 18, minute: 0),
        description: 'Standard morning shift (9 AM - 6 PM)',
        color: const Color(0xFF2563EB),
      ),
      ShiftDefinition(
        id: 'shift_afternoon',
        shiftName: 'Afternoon Shift',
        shiftType: 'afternoon',
        startTime: const TimeOfDay(hour: 14, minute: 0),
        endTime: const TimeOfDay(hour: 23, minute: 0),
        description: 'Standard afternoon shift (2 PM - 11 PM)',
        color: const Color(0xFFF59E0B),
      ),
      ShiftDefinition(
        id: 'shift_night',
        shiftName: 'Night Shift',
        shiftType: 'night',
        startTime: const TimeOfDay(hour: 23, minute: 0),
        endTime: const TimeOfDay(hour: 8, minute: 0),
        description: 'Standard night shift (11 PM - 8 AM)',
        color: const Color(0xFF8B5CF6),
      ),
      ShiftDefinition(
        id: 'shift_early_morning',
        shiftName: 'Early Morning Shift',
        shiftType: 'morning',
        startTime: const TimeOfDay(hour: 6, minute: 0),
        endTime: const TimeOfDay(hour: 15, minute: 0),
        description: 'Early morning shift (6 AM - 3 PM)',
        color: const Color(0xFF10B981),
      ),
    ];
  }
}