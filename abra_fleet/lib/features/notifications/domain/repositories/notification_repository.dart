// File: lib/features/notifications/domain/repositories/notification_repository.dart
// Defines the contract for notification data operations.

import 'package:abra_fleet/features/notifications/domain/entities/notification_entity.dart';

abstract class NotificationRepository {
  // Get a list of all notifications for the current user.
  // Could optionally take pagination parameters.
  Future<List<NotificationEntity>> getNotifications();

  // Mark a specific notification as read.
  Future<void> markNotificationAsRead(String notificationId);

  // Mark all notifications as read for the current user.
  Future<void> markAllNotificationsAsRead();

  // Get the count of unread notifications for the current user.
  // If adminOnly is true, only count admin-relevant notification types.
  Future<int> getUnreadNotificationCount({bool adminOnly = false});

// Delete a specific notification (optional, depending on requirements).
// Future<void> deleteNotification(String notificationId);

// Clear all notifications for the current user (optional).
// Future<void> clearAllNotifications();

// Stream for real-time updates on new notifications or unread count (more advanced).
// Stream<int> get unreadNotificationCountStream;
// Stream<NotificationEntity> get newNotificationStream;
}
