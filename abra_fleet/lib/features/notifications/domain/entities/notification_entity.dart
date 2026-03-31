// File: lib/features/notifications/domain/entities/notification_entity.dart
// Defines the data structure for a Notification.

import 'package:flutter/material.dart'; // For IconData, Color (optional for type hints)

enum NotificationType {
  info,       // General information
  alert,      // Important alert, e.g., maintenance due
  message,    // Direct message or communication
  booking,    // Booking status update
  system,     // System-level notification
  promotion,  // Promotional content
}

class NotificationEntity {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final NotificationType type;
  bool isRead;
  final String? relatedItemId; // e.g., vehicleId, driverId, bookingId
  final String? relatedItemType; // e.g., "vehicle", "driver", "booking"
  final String? deepLink; // Optional: for navigation on tap

  NotificationEntity({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.type = NotificationType.info,
    this.isRead = false,
    this.relatedItemId,
    this.relatedItemType,
    this.deepLink,
  });

  // Helper to get an icon based on type (optional, UI concern but can be here)
  IconData get iconData {
    switch (type) {
      case NotificationType.alert:
        return Icons.warning_amber_rounded;
      case NotificationType.message:
        return Icons.message_rounded;
      case NotificationType.booking:
        return Icons.event_available_rounded;
      case NotificationType.system:
        return Icons.settings_applications_rounded;
      case NotificationType.promotion:
        return Icons.campaign_rounded;
      case NotificationType.info:
      default:
        return Icons.info_outline_rounded;
    }
  }

  // Helper to get a color based on type (optional)
  Color? get typeColor { // Return type Color?
    switch (type) {
      case NotificationType.alert:
        return Colors.orange.shade700;
      case NotificationType.system:
        return Colors.blue.shade700;
      case NotificationType.promotion:
        return Colors.purple.shade700;
      default:
        return null; // Use default theme color
    }
  }


  @override
  String toString() {
    return 'Notification(id: $id, title: $title, read: $isRead)';
  }

  NotificationEntity copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? timestamp,
    NotificationType? type,
    bool? isRead,
    ValueGetter<String?>? relatedItemId,
    ValueGetter<String?>? relatedItemType,
    ValueGetter<String?>? deepLink,
  }) {
    return NotificationEntity(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
      relatedItemId: relatedItemId != null ? relatedItemId() : this.relatedItemId,
      relatedItemType: relatedItemType != null ? relatedItemType() : this.relatedItemType,
      deepLink: deepLink != null ? deepLink() : this.deepLink,
    );
  }
}
