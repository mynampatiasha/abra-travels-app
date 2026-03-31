// File: lib/features/notifications/data/repositories/mock_notification_repository_impl.dart
// Mock implementation of NotificationRepository for local development and testing.

import 'dart:async';
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:abra_fleet/features/notifications/domain/entities/notification_entity.dart';
import 'package:abra_fleet/features/notifications/domain/repositories/notification_repository.dart';

class MockNotificationRepositoryImpl implements NotificationRepository {
  // In-memory list to store notifications
  final List<NotificationEntity> _mockNotifications = [
    NotificationEntity(
      id: 'notif001',
      title: 'Maintenance Due Soon',
      body: 'Vehicle "Cargo Van 1" (AB-123-CD) is due for its scheduled oil change in 3 days.',
      timestamp: DateTime.now().subtract(const Duration(hours: 2)),
      type: NotificationType.alert,
      isRead: false,
      relatedItemId: 'v001',
      relatedItemType: 'vehicle',
    ),
    NotificationEntity(
      id: 'notif002',
      title: 'New Booking Assigned',
      body: 'You have a new booking (BK-789) for package delivery starting at 2:00 PM.',
      timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      type: NotificationType.booking,
      isRead: true,
      relatedItemId: 'bk789',
      relatedItemType: 'booking',
    ),
    NotificationEntity(
      id: 'notif003',
      title: 'System Update Scheduled',
      body: 'A system update is scheduled for tonight at 2:00 AM. Expect brief downtime.',
      timestamp: DateTime.now().subtract(const Duration(days: 1, hours: 5)),
      type: NotificationType.system,
      isRead: false,
    ),
    NotificationEntity(
      id: 'notif004',
      title: 'Welcome to Abra Travels!',
      body: 'Thank you for joining our platform. Explore the features and get started.',
      timestamp: DateTime.now().subtract(const Duration(days: 3)),
      type: NotificationType.info,
      isRead: true,
    ),
    NotificationEntity(
      id: 'notif005',
      title: 'Driver License Expiring',
      body: 'Driver John Doe\'s license (DLX12345) is expiring in 15 days.',
      timestamp: DateTime.now().subtract(const Duration(hours: 20)),
      type: NotificationType.alert,
      isRead: false,
      relatedItemId: 'd001',
      relatedItemType: 'driver',
    ),
  ];
  int _nextIdCounter = 6;

  // Simulate network delay
  Future<void> _simulateDelay({int milliseconds = 200}) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

  @override
  Future<List<NotificationEntity>> getNotifications() async {
    await _simulateDelay(milliseconds: 400);
    // Sort by newest first
    _mockNotifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    debugPrint('[MockNotificationRepo] Returning ${_mockNotifications.length} notifications.');
    return List<NotificationEntity>.from(_mockNotifications); // Return a copy
  }

  @override
  Future<void> markNotificationAsRead(String notificationId) async {
    await _simulateDelay();
    try {
      final notification = _mockNotifications.firstWhere((n) => n.id == notificationId);
      if (!notification.isRead) {
        notification.isRead = true;
        debugPrint('[MockNotificationRepo] Marked notification ID $notificationId as read.');
      }
    } catch (e) {
      debugPrint('[MockNotificationRepo] Notification ID $notificationId not found to mark as read.');
      // Optionally throw an error or handle silently
    }
  }

  @override
  Future<void> markAllNotificationsAsRead() async {
    await _simulateDelay();
    for (var notification in _mockNotifications) {
      notification.isRead = true;
    }
    debugPrint('[MockNotificationRepo] Marked all notifications as read.');
  }

  @override
  Future<int> getUnreadNotificationCount({bool adminOnly = false}) async {
    await _simulateDelay();
    final count = _mockNotifications.where((n) => !n.isRead).length;
    debugPrint('[MockNotificationRepo] Unread count: $count');
    return count;
  }

// --- Optional Methods (Not yet in interface, but common) ---
// Future<void> addNotification(NotificationEntity notification) async {
//   await _simulateDelay();
//   final newNotification = notification.copyWith(
//     id: 'notif${(_nextIdCounter++).toString().padLeft(3,'0')}',
//     timestamp: DateTime.now(), // Ensure timestamp is current if added this way
//   );
//   _mockNotifications.insert(0, newNotification); // Add to top
//   debugPrint('[MockNotificationRepo] Added new notification: ${newNotification.title}');
// }

// Future<void> deleteNotification(String notificationId) async {
//   await _simulateDelay();
//   _mockNotifications.removeWhere((n) => n.id == notificationId);
//   debugPrint('[MockNotificationRepo] Deleted notification ID $notificationId');
// }

// Future<void> clearAllNotifications() async {
//   await _simulateDelay();
//   _mockNotifications.clear();
//   debugPrint('[MockNotificationRepo] Cleared all notifications.');
// }
}
