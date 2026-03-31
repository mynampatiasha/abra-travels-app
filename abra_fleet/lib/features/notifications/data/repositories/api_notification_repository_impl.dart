// File: lib/features/notifications/data/repositories/api_notification_repository_impl.dart
// Real implementation that fetches notifications from backend API

import 'package:abra_fleet/features/notifications/domain/entities/notification_entity.dart';
import 'package:abra_fleet/features/notifications/domain/repositories/notification_repository.dart';
import 'package:abra_fleet/core/services/notification_service.dart';

class ApiNotificationRepositoryImpl implements NotificationRepository {
  final NotificationService _notificationService;

  ApiNotificationRepositoryImpl({NotificationService? notificationService})
      : _notificationService = notificationService ?? NotificationService();

  @override
  Future<List<NotificationEntity>> getNotifications() async {
    try {
      final response = await _notificationService.getNotifications(limit: 100);
      
      if (response['success'] == true) {
        final notifications = response['notifications'] as List? ?? [];
        
        return notifications.map<NotificationEntity>((notif) {
          return NotificationEntity(
            id: notif['_id']?.toString() ?? notif['id']?.toString() ?? '',
            title: notif['title']?.toString() ?? 'Notification',
            body: notif['body']?.toString() ?? notif['message']?.toString() ?? '',
            timestamp: _parseTimestamp(notif['createdAt']),
            isRead: notif['isRead'] == true || notif['read'] == true,
            type: _parseNotificationType(notif['type']?.toString()),
            relatedItemId: notif['data']?['leaveRequestId']?.toString() ?? 
                          notif['data']?['rosterId']?.toString() ??
                          notif['data']?['tripId']?.toString(),
            relatedItemType: notif['category']?.toString(),
            deepLink: notif['data']?['deepLink']?.toString(),
          );
        }).toList();
      }
      
      return [];
    } catch (e) {
      throw Exception('Failed to fetch notifications: $e');
    }
  }
  
  NotificationType _parseNotificationType(String? type) {
    if (type == null) return NotificationType.info;
    
    // Map backend notification types to NotificationType enum
    switch (type.toLowerCase()) {
      case 'leave_approved_admin':
      case 'leave_request':
      case 'trip_cancelled':
      case 'sos_alert':
        return NotificationType.alert;
      case 'roster_assigned':
      case 'roster_updated':
      case 'roster_assignment_updated':
      case 'route_assigned':           // ✅ Added: Route assignment notification
      case 'route_assignment':         // ✅ Added: Route assignment notification
      case 'driver_assigned':          // ✅ Added: Driver assigned notification
      case 'driver_route_assignment':  // ✅ Added: Driver route assignment
        return NotificationType.booking;
      case 'customer_registration':
      case 'account_approved':
        return NotificationType.message;
      case 'vehicle_assigned':
      case 'vehicle_maintenance':
        return NotificationType.system;
      default:
        return NotificationType.info;
    }
  }

  @override
  Future<int> getUnreadNotificationCount({bool adminOnly = false}) async {
    try {
      final count = await _notificationService.getUnreadCount(adminOnly: adminOnly);
      return count;
    } catch (e) {
      throw Exception('Failed to fetch unread count: $e');
    }
  }

  @override
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _notificationService.markAsRead(notificationId);
    } catch (e) {
      throw Exception('Failed to mark notification as read: $e');
    }
  }

  @override
  Future<void> markAllNotificationsAsRead() async {
    try {
      await _notificationService.markAllAsRead();
    } catch (e) {
      throw Exception('Failed to mark all notifications as read: $e');
    }
  }

  DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return DateTime.now();
    
    if (timestamp is DateTime) return timestamp;
    
    if (timestamp is String) {
      try {
        return DateTime.parse(timestamp);
      } catch (e) {
        return DateTime.now();
      }
    }
    
    if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    
    return DateTime.now();
  }
}
