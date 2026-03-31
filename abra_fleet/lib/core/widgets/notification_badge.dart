// lib/widgets/notification_badge.dart
import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/notification_service.dart';

/// A widget that displays a notification bell icon with an unread count badge
class NotificationBadge extends StatefulWidget {
  final NotificationService notificationService;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? badgeColor;
  final double iconSize;

  const NotificationBadge({
    super.key,
    required this.notificationService,
    required this.onTap,
    this.iconColor,
    this.badgeColor,
    this.iconSize = 24.0,
  });

  @override
  State<NotificationBadge> createState() => _NotificationBadgeState();
}

class _NotificationBadgeState extends State<NotificationBadge> {
  int _unreadCount = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _setupRealTimeListener();
  }

  Future<void> _loadUnreadCount() async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    
    try {
      final count = await widget.notificationService.getUnreadCount();
      if (mounted) {
        setState(() {
          _unreadCount = count;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading unread count: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupRealTimeListener() {
    widget.notificationService.onNewNotification.listen((_) {
      _loadUnreadCount();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(
            Icons.notifications,
            size: widget.iconSize,
            color: widget.iconColor ?? Colors.white,
          ),
          onPressed: widget.onTap,
        ),
        if (_unreadCount > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: widget.badgeColor ?? Colors.red,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              constraints: const BoxConstraints(
                minWidth: 20,
                minHeight: 20,
              ),
              child: Center(
                child: Text(
                  _unreadCount > 99 ? '99+' : _unreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ========== NOTIFICATION LIST ITEM WIDGET ==========

class NotificationListItem extends StatelessWidget {
  final Map<String, dynamic> notification;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;

  const NotificationListItem({
    super.key,
    required this.notification,
    required this.onTap,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isRead = notification['isRead'] == true;
    final type = notification['type'] ?? 'system';
    final priority = notification['priority'] ?? 'normal';
    final icon = NotificationService.getNotificationIcon(type);
    final color = Color(NotificationService.getNotificationColor(priority));

    final item = Card(
      elevation: isRead ? 1 : 2,
      color: isRead ? null : Colors.blue.withOpacity(0.05),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Center(
                  child: Text(icon, style: const TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification['title'] ?? 'Notification',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  isRead ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification['body'] ?? '',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimestamp(notification['createdAt']),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (onDismiss != null) {
      return Dismissible(
        key: Key(notification['id']?.toString() ?? ''),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: Colors.red,
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        confirmDismiss: (direction) async {
          return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete Notification'),
              content: const Text('Delete this notification?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
        },
        onDismissed: (direction) => onDismiss?.call(),
        child: item,
      );
    }

    return item;
  }

  String _formatTimestamp(dynamic timestamp) {
    try {
      final dateTime = timestamp is DateTime
          ? timestamp
          : DateTime.parse(timestamp.toString());
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${difference.inDays ~/ 7}w ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }
}

// ========== NOTIFICATION TOAST ==========

void showNotificationToast(
  BuildContext context,
  Map<String, dynamic> notification, {
  VoidCallback? onTap,
}) {
  final icon = NotificationService.getNotificationIcon(
    notification['type'] ?? 'system',
  );
  final color = Color(
    NotificationService.getNotificationColor(
      notification['priority'] ?? 'normal',
    ),
  );

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notification['title'] ?? 'Notification',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notification['body'] ?? '',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: color,
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      action: onTap != null
          ? SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: onTap,
            )
          : null,
    ),
  );
}