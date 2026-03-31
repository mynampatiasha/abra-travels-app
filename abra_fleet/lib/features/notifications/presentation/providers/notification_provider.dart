// File: lib/features/notifications/presentation/providers/notification_provider.dart
// Provider for managing notification state using ChangeNotifier.

import 'package:flutter/material.dart';
import 'package:abra_fleet/features/notifications/domain/entities/notification_entity.dart';
import 'package:abra_fleet/features/notifications/domain/repositories/notification_repository.dart';
// Import the real API implementation
import 'package:abra_fleet/features/notifications/data/repositories/api_notification_repository_impl.dart';

// Assuming DataState enum is defined in a shared location or one of the other providers.
// If not, you might need to define it here or import it.
// For this example, let's assume it's similar to what we used before.
// If you have a common DataState, import that. Otherwise:
enum DataState { initial, loading, loaded, error } // Define if not shared

class NotificationProvider extends ChangeNotifier {
  final NotificationRepository _notificationRepository;

  NotificationProvider({NotificationRepository? notificationRepository, bool adminOnly = false})
      : _notificationRepository = notificationRepository ?? ApiNotificationRepositoryImpl() {
    // Fetch notifications and unread count when the provider is created.
    fetchNotifications();
    fetchUnreadNotificationCount(adminOnly: adminOnly);
  }

  List<NotificationEntity> _notifications = [];
  DataState _state = DataState.initial;
  String? _errorMessage;
  int _unreadCount = 0;

  // Getters for UI to access state
  List<NotificationEntity> get notifications => _notifications;
  DataState get state => _state;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _state == DataState.loading;
  int get unreadCount => _unreadCount;

  // --- Methods to interact with the repositories ---

  Future<void> fetchNotifications() async {
    _state = DataState.loading;
    _errorMessage = null;
    // Don't notify for initial load if unreadCount is also loading,
    // or notify selectively. For simplicity, notify for loading start.
    // notifyListeners(); // Can be too chatty if called with fetchUnreadNotificationCount

    try {
      _notifications = await _notificationRepository.getNotifications();
      _state = DataState.loaded;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "");
      _state = DataState.error;
      debugPrint('Error fetching notifications: $_errorMessage');
    }
    // Consolidate notifications if fetchUnreadNotificationCount is also called in init
    // Or ensure this is the last one to notify if both are called.
    notifyListeners();
  }

  Future<void> fetchUnreadNotificationCount({bool adminOnly = false}) async {
    // No separate loading state for just the count, assume it's quick
    try {
      _unreadCount = await _notificationRepository.getUnreadNotificationCount(adminOnly: adminOnly);
    } catch (e) {
      debugPrint('Error fetching unread notification count: $e');
      _unreadCount = 0; // Default to 0 on error
    }
    notifyListeners();
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    // Optimistically update UI first for responsiveness
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1 && !_notifications[index].isRead) {
      _notifications[index].isRead = true;
      _unreadCount = _unreadCount > 0 ? _unreadCount - 1 : 0;
      notifyListeners();
    }

    try {
      await _notificationRepository.markNotificationAsRead(notificationId);
      // If backend call fails, ideally revert optimistic update or show error
      // For mock, this is fine.
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
      // Revert optimistic update if necessary
      if (index != -1) {
        _notifications[index].isRead = false; // Revert
        _unreadCount++; // Re-increment
        notifyListeners();
      }
      // Optionally show an error message to the user
    }
  }

  Future<void> markAllNotificationsAsRead() async {
    // Optimistic update
    for (var notification in _notifications) {
      notification.isRead = true;
    }
    _unreadCount = 0;
    notifyListeners();

    try {
      await _notificationRepository.markAllNotificationsAsRead();
    } catch (e) {
      debugPrint('Error marking all notifications as read: $e');
      // Revert optimistic update (more complex, might need to re-fetch)
      // For simplicity, we might just re-fetch all data on error.
      await fetchNotifications(); // Re-fetch to get correct state
      await fetchUnreadNotificationCount();
    }
  }

// Example of how you might add a new notification (e.g., from a push notification)
// This would typically be called by a service handling incoming push notifications.
// For now, this isn't directly used by UI but shows how provider could be updated.
// void receiveNewNotification(NotificationEntity newNotification) {
//   _notifications.insert(0, newNotification); // Add to top
//   if (!newNotification.isRead) {
//     _unreadCount++;
//   }
//   notifyListeners();
// }
}
