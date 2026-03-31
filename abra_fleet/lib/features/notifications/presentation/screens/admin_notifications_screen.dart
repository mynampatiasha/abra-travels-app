// File: lib/features/notifications/presentation/screens/admin_notifications_screen.dart
// Admin-specific notifications screen - IMPROVED UI with clean read/unread states

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  static const String routeName = '/admin/notifications';

  @override
  State<AdminNotificationsScreen> createState() => _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  Timer? _pollingTimer;
  
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String? _errorMessage;
  int _unreadCount = 0;

  // Selection mode for bulk delete
  bool _isSelectionMode = false;
  Set<String> _selectedNotifications = {};

  // Comprehensive list of admin notification types
  static const List<String> _adminNotificationTypes = [
    'trip_cancelled', 'trip_started', 'trip_completed', 'trip_issue',
    'sos_alert', 'driver_report', 'vehicle_maintenance', 'maintenance_due',
    'roster_pending', 'roster_assigned', 'roster_updated', 'roster_cancelled',
    'roster_assigned_admin',
    'leave_request', 'leave_request_pending', 'leave_approved', 'leave_rejected',
    'customer_registration','client_trip_request', 'new_user_registered', 'address_change_request',
    'document_expired', 'document_expiring_soon',
    'trip_created_admin', 'trip_accepted_admin', 'trip_declined_admin',
    'system', 'test',
  ];

  @override
  void initState() {
    super.initState();
    debugPrint('🔔 AdminNotificationsScreen: initState called');
    _loadNotifications();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      debugPrint('❌ Error getting token: $e');
      return null;
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadNotifications();
      }
    });
  }

  Future<void> _loadNotifications() async {
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('No authentication token found');
      }
      
      final url = '${ApiConfig.baseUrl}/api/notifications';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true) {
          final notifications = data['notifications'] as List<dynamic>? ?? [];
          
          setState(() {
            _notifications = notifications
                .cast<Map<String, dynamic>>()
                .where((notification) {
                  final type = notification['type']?.toString() ?? '';
                  return _adminNotificationTypes.contains(type);
                })
                .toList();

            _notifications.sort((a, b) {
              final aDate = DateTime.parse(a['createdAt'] ?? DateTime.now().toIso8601String());
              final bDate = DateTime.parse(b['createdAt'] ?? DateTime.now().toIso8601String());
              return bDate.compareTo(aDate);
            });

            _unreadCount = _notifications.where((n) => n['isRead'] != true).length;
            _isLoading = false;
            _errorMessage = null;
          });
        } else {
          throw Exception(data['message'] ?? 'Failed to load notifications');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
      
    } catch (e) {
      debugPrint('❌ Error loading admin notifications: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load notifications: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      final token = await _getToken();
      if (token == null) return;

      final url = '${ApiConfig.baseUrl}/api/notifications/$notificationId/read';
      
      final response = await http.put(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          final index = _notifications.indexWhere((n) => n['_id'] == notificationId);
          if (index != -1) {
            _notifications[index]['isRead'] = true;
            _unreadCount = _notifications.where((n) => n['isRead'] != true).length;
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error marking notification as read: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final token = await _getToken();
      if (token == null) return;

      final url = '${ApiConfig.baseUrl}/api/notifications/mark-all-read';
      
      final response = await http.put(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          for (var notification in _notifications) {
            notification['isRead'] = true;
          }
          _unreadCount = 0;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All notifications marked as read')),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error marking all as read: $e');
    }
  }

  Future<void> _deleteNotification(String notificationId, {bool showConfirmation = true}) async {
    if (showConfirmation) {
      final confirm = await _showDeleteConfirmationDialog(single: true);
      if (confirm != true) return;
    }

    try {
      final token = await _getToken();
      if (token == null) throw Exception('No authentication token');

      final url = '${ApiConfig.baseUrl}/api/notifications/$notificationId';
      
      final response = await http.delete(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          _notifications.removeWhere((n) => n['_id'] == notificationId);
          _unreadCount = _notifications.where((n) => n['isRead'] != true).length;
        });
        
        if (mounted && showConfirmation) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Notification deleted'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception('Delete failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error deleting notification: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to delete: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteSelectedNotifications() async {
    if (_selectedNotifications.isEmpty) return;

    final confirm = await _showDeleteConfirmationDialog(
      single: false,
      count: _selectedNotifications.length,
    );
    
    if (confirm != true) return;

    try {
      int successCount = 0;
      int failCount = 0;
      
      for (String notificationId in _selectedNotifications) {
        try {
          final token = await _getToken();
          if (token == null) continue;

          final url = '${ApiConfig.baseUrl}/api/notifications/$notificationId';
          
          final response = await http.delete(
            Uri.parse(url),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          );

          if (response.statusCode == 200) {
            successCount++;
          } else {
            failCount++;
          }
        } catch (e) {
          failCount++;
        }
      }
      
      if (mounted) {
        setState(() {
          _notifications.removeWhere((n) => _selectedNotifications.contains(n['_id']));
          _unreadCount = _notifications.where((n) => n['isRead'] != true).length;
          _selectedNotifications.clear();
          _isSelectionMode = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Deleted $successCount notification(s)${failCount > 0 ? ', $failCount failed' : ''}'),
            backgroundColor: failCount > 0 ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error in bulk delete: $e');
    }
  }

  Future<void> _deleteAllNotifications() async {
    if (_notifications.isEmpty) return;

    final confirm = await _showDeleteConfirmationDialog(
      single: false,
      count: _notifications.length,
      deleteAll: true,
    );
    
    if (confirm != true) return;

    try {
      int successCount = 0;
      int failCount = 0;
      
      for (var notification in _notifications) {
        try {
          final notificationId = notification['_id']?.toString() ?? '';
          if (notificationId.isEmpty) continue;
          
          final token = await _getToken();
          if (token == null) continue;

          final url = '${ApiConfig.baseUrl}/api/notifications/$notificationId';
          
          final response = await http.delete(
            Uri.parse(url),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          );

          if (response.statusCode == 200) {
            successCount++;
          } else {
            failCount++;
          }
        } catch (e) {
          failCount++;
        }
      }
      
      if (mounted) {
        setState(() {
          _notifications.clear();
          _unreadCount = 0;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Deleted $successCount notification(s)${failCount > 0 ? ', $failCount failed' : ''}'),
            backgroundColor: failCount > 0 ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error deleting all notifications: $e');
    }
  }

  Future<bool?> _showDeleteConfirmationDialog({
    required bool single,
    int count = 1,
    bool deleteAll = false,
  }) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red[700]),
            const SizedBox(width: 8),
            const Text('Delete Notification(s)?'),
          ],
        ),
        content: Text(
          deleteAll
              ? 'Are you sure you want to delete ALL $count notifications? This action cannot be undone.'
              : single
                  ? 'Are you sure you want to delete this notification?'
                  : 'Are you sure you want to delete $count selected notifications?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedNotifications.clear();
      }
    });
  }

  void _toggleNotificationSelection(String notificationId) {
    setState(() {
      if (_selectedNotifications.contains(notificationId)) {
        _selectedNotifications.remove(notificationId);
      } else {
        _selectedNotifications.add(notificationId);
      }
    });
  }

  void _selectAllNotifications() {
    setState(() {
      if (_selectedNotifications.length == _notifications.length) {
        _selectedNotifications.clear();
      } else {
        _selectedNotifications = _notifications
            .map((n) => n['_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        elevation: 0,
        title: _isSelectionMode
            ? Text('${_selectedNotifications.length} selected')
            : Row(
                children: [
                  const Text('Admin Notifications'),
                  if (_unreadCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$_unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: Icon(
                    _selectedNotifications.length == _notifications.length
                        ? Icons.check_box
                        : Icons.check_box_outline_blank,
                  ),
                  tooltip: 'Select all',
                  onPressed: _selectAllNotifications,
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete selected',
                  onPressed: _selectedNotifications.isEmpty
                      ? null
                      : _deleteSelectedNotifications,
                ),
              ]
            : [
                if (_unreadCount > 0)
                  IconButton(
                    icon: const Icon(Icons.done_all),
                    tooltip: 'Mark all as read',
                    onPressed: _markAllAsRead,
                  ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'select':
                        _toggleSelectionMode();
                        break;
                      case 'delete_all':
                        _deleteAllNotifications();
                        break;
                      case 'refresh':
                        _loadNotifications();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'select',
                      child: Row(
                        children: [
                          Icon(Icons.checklist, size: 20),
                          SizedBox(width: 8),
                          Text('Select mode'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'refresh',
                      child: Row(
                        children: [
                          Icon(Icons.refresh, size: 20),
                          SizedBox(width: 8),
                          Text('Refresh'),
                        ],
                      ),
                    ),
                    if (_notifications.isNotEmpty)
                      const PopupMenuItem(
                        value: 'delete_all',
                        child: Row(
                          children: [
                            Icon(Icons.delete_sweep, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete all', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading notifications...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadNotifications,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.notifications_none, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No notifications', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            const Text(
              'You\'re all caught up!',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadNotifications,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadNotifications,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          final notification = _notifications[index];
          return _buildNotificationCard(notification);
        },
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final isRead = notification['isRead'] == true;
    final title = notification['title']?.toString() ?? 'Notification';
    final message = notification['body']?.toString() ?? notification['message']?.toString() ?? '';
    final type = notification['type']?.toString() ?? '';
    final priority = notification['priority']?.toString() ?? 'normal';
    final createdAt = notification['createdAt']?.toString();
    final notificationId = notification['_id']?.toString() ?? '';
    final isSelected = _selectedNotifications.contains(notificationId);
    
    // Driver response detection
    final isDriverResponse = type == 'trip_accepted_admin' || type == 'trip_declined_admin';
    final isAccepted = type == 'trip_accepted_admin';

    DateTime? dateTime;
    if (createdAt != null) {
      try {
        dateTime = DateTime.parse(createdAt);
      } catch (e) {
        debugPrint('Error parsing date: $e');
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected 
            ? Colors.blue.shade100
            : isRead
                ? Colors.white.withOpacity(0.7)  // 🔥 Faded for read notifications
                : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isDriverResponse
            ? Border.all(
                color: isAccepted ? Colors.green.shade400 : Colors.red.shade400,
                width: 2,
              )
            : Border.all(
                color: isRead ? Colors.grey.shade200 : Colors.blue.shade200,
                width: isRead ? 1 : 2,
              ),
        boxShadow: isRead
            ? null  // 🔥 No shadow for read notifications
            : [
                BoxShadow(
                  color: isDriverResponse
                      ? (isAccepted ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1))
                      : Colors.blue.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (_isSelectionMode) {
              _toggleNotificationSelection(notificationId);
            } else {
              _showNotificationDetails(notification);
              if (!isRead) {
                _markAsRead(notificationId);
              }
            }
          },
          onLongPress: () {
            if (!_isSelectionMode) {
              setState(() {
                _isSelectionMode = true;
                _selectedNotifications.add(notificationId);
              });
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Leading icon or checkbox
                if (_isSelectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleNotificationSelection(notificationId),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 12, top: 2),
                    child: _getNotificationIcon(type, priority, isRead),
                  ),
                
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row with badge
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                                color: isRead ? Colors.grey.shade700 : Colors.black87,
                              ),
                            ),
                          ),
                          if (isDriverResponse) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isAccepted ? Colors.green : Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isAccepted ? Icons.check_circle : Icons.cancel,
                                    color: Colors.white,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isAccepted ? 'ACCEPTED' : 'DECLINED',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      
                      // Message
                      if (message.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: isRead ? Colors.grey.shade600 : Colors.grey.shade800,
                            height: 1.4,
                          ),
                        ),
                      ],
                      
                      // Metadata row
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (dateTime != null) ...[
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: isRead ? Colors.grey.shade400 : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatRelativeTime(dateTime),
                              style: TextStyle(
                                fontSize: 12,
                                color: isRead ? Colors.grey.shade500 : Colors.grey.shade600,
                              ),
                            ),
                          ],
                          if (priority.toLowerCase() == 'high' || priority.toLowerCase() == 'urgent') ...[
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.priority_high, size: 12, color: Colors.red.shade700),
                                  const SizedBox(width: 2),
                                  Text(
                                    'URGENT',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Trailing actions
                if (!_isSelectionMode && !isRead)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _getNotificationIcon(String type, String priority, bool isRead) {
    IconData iconData;
    Color color = _getPriorityColor(priority);
    
    // Fade color for read notifications
    if (isRead) {
      color = color.withOpacity(0.5);
    }
    
    switch (type) {
      case 'trip_assigned':
      case 'trip_created_admin':
        iconData = Icons.local_shipping;
        break;
      case 'trip_accepted_admin':
        iconData = Icons.check_circle;
        color = isRead ? Colors.green.shade300 : Colors.green.shade600;
        break;
      case 'trip_declined_admin':
        iconData = Icons.cancel;
        color = isRead ? Colors.red.shade300 : Colors.red.shade600;
        break;
      case 'trip_started':
        iconData = Icons.play_arrow;
        break;
      case 'trip_completed':
        iconData = Icons.check;
        break;
      case 'sos_alert':
        iconData = Icons.warning;
        color = Colors.red;
        break;
      case 'roster_assigned':
      case 'roster_pending':
        iconData = Icons.assignment;
        break;
      case 'leave_request':
        iconData = Icons.event_busy;
        break;
      case 'document_expired':
      case 'document_expiring_soon':
        iconData = Icons.description;
        color = Colors.orange;
        break;
      default:
        iconData = Icons.notifications;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: color, size: 20),
    );
  }

  Color _getPriorityColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'high':
      case 'urgent':
        return Colors.red;
      case 'normal':
      case 'medium':
        return const Color(0xFF0D47A1);
      case 'low':
        return Colors.grey;
      default:
        return const Color(0xFF0D47A1);
    }
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('MMM dd').format(dateTime);
    }
  }

  void _showNotificationDetails(Map<String, dynamic> notification) {
    final title = notification['title']?.toString() ?? 'Notification';
    final message = notification['body']?.toString() ?? notification['message']?.toString() ?? '';
    final type = notification['type']?.toString() ?? '';
    final priority = notification['priority']?.toString() ?? 'normal';
    final category = notification['category']?.toString() ?? '';
    final createdAt = notification['createdAt']?.toString();
    final data = notification['data'] as Map<String, dynamic>? ?? {};
    final notificationId = notification['_id']?.toString() ?? '';
    
    final isDriverResponse = type == 'trip_accepted_admin' || type == 'trip_declined_admin';
    final isAccepted = type == 'trip_accepted_admin';

    DateTime? dateTime;
    if (createdAt != null) {
      try {
        dateTime = DateTime.parse(createdAt);
      } catch (e) {
        debugPrint('Error parsing date: $e');
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            _getNotificationIcon(type, priority, false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (isDriverResponse) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isAccepted ? Colors.green : Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isAccepted ? '✓ ACCEPTED' : '✗ DECLINED',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dateTime != null) ...[
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      DateFormat('MMM dd, yyyy • hh:mm a').format(dateTime),
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (message.isNotEmpty) ...[
                const Text(
                  'Message:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (data.isNotEmpty) ...[
                const Text(
                  'Details:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                ...data.entries.map((entry) {
                  final key = entry.key.replaceAll('_', ' ').toUpperCase();
                  final value = entry.value?.toString() ?? 'N/A';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            '$key:',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            value,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteNotification(notificationId);
            },
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D47A1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}