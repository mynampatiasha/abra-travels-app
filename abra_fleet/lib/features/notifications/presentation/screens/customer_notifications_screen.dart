// File: lib/features/notifications/presentation/screens/customer_notifications_screen.dart
// Customer-specific notifications screen - FCM/Database Implementation
// Enhanced with beautiful UI, real-time mark-as-read, delete functionality, feedback handling

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/features/admin/hrm/hrm_feedback.dart';

class CustomerNotificationsScreen extends StatefulWidget {
  const CustomerNotificationsScreen({super.key});

  static const String routeName = '/customer/notifications';

  @override
  State<CustomerNotificationsScreen> createState() => _CustomerNotificationsScreenState();
}

class _CustomerNotificationsScreenState extends State<CustomerNotificationsScreen> {
  
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _pollingTimer;
  int _unreadCount = 0;

  // Helper method to get JWT token
  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      debugPrint('❌ Error getting JWT token: $e');
      return null;
    }
  }

  // ✅ MODIFIED: Added new trip notification types including feedback_request
  static const List<String> _customerNotificationTypes = [
    // Original types
     'route_assignment',
    'route_assigned',
    'roster_assigned',
    'roster_assignment_updated',
    'leave_approved',
    'leave_rejected',
    'trip_updated',
    'trip_cancelled',
    'pickup_reminder',
    'address_change_approved',
    'address_change_rejected',
    
    // ✅ NEW: Trip-specific notifications (RouteMatic-style)
    'trip_assigned',           // Trip assigned to customer
    'trip_started',            // Driver started the trip
    'eta_15min',               // Driver 15 minutes away
    'eta_5min',                // Driver 5 minutes away
    'driver_arrived',          // Driver arrived at pickup
    'trip_delayed',            // Trip is delayed
    'trip_completed',          // Trip completed successfully
    
    // ✅ NEW: Feedback notifications
    'feedback_reply',          // Admin replied to customer feedback
    'feedback_request',        // Request for trip feedback
  ];

  @override
  void initState() {
    super.initState();
    debugPrint('🔔 CustomerNotificationsScreen: initState called');
    _loadNotifications();
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('🔔 CUSTOMER NOTIFICATIONS - LOADING');
      debugPrint('═══════════════════════════════════════════════════════');
      
      // Step 1: Get JWT token
      debugPrint('📝 Step 1: Getting JWT token...');
      final token = await _getToken();
      
      if (token == null) {
        debugPrint('❌ ERROR: No JWT token found!');
        debugPrint('   Action: User needs to login again');
        throw Exception('No authentication token found');
      }
      
      debugPrint('✅ JWT token retrieved');
      debugPrint('   Token length: ${token.length} characters');
      debugPrint('   Token preview: ${token.substring(0, 50)}...');
      
      // Decode JWT to show user info
      try {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = json.decode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))
          );
          debugPrint('   JWT userId: ${payload['userId']}');
          debugPrint('   JWT email: ${payload['email']}');
          debugPrint('   JWT role: ${payload['role']}');
        }
      } catch (e) {
        debugPrint('   (Could not decode JWT: $e)');
      }

      // Step 2: Make API request
      final url = '${ApiConfig.baseUrl}/api/notifications';
      debugPrint('');
      debugPrint('📡 Step 2: Making API request...');
      debugPrint('   URL: $url');
      debugPrint('   Method: GET');
      debugPrint('   Headers: Authorization: Bearer <token>');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      // Step 3: Check response
      debugPrint('');
      debugPrint('📊 Step 3: Response received');
      debugPrint('   Status code: ${response.statusCode}');
      debugPrint('   Response body length: ${response.body.length} bytes');
      debugPrint('   Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        debugPrint('');
        debugPrint('📦 Step 4: Parsing response data');
        debugPrint('   success: ${data['success']}');
        debugPrint('   total: ${data['total']}');
        debugPrint('   unreadCount: ${data['unreadCount']}');
        
        if (data['success'] == true) {
          final notifications = data['notifications'] as List<dynamic>? ?? [];
          
          debugPrint('   Raw notifications count: ${notifications.length}');
          
          if (notifications.isNotEmpty) {
            debugPrint('');
            debugPrint('📬 Notification details:');
            for (var i = 0; i < notifications.length && i < 3; i++) {
              final notif = notifications[i];
              debugPrint('   ${i + 1}. ${notif['type']} - ${notif['title']}');
              debugPrint('      userId: ${notif['userId']}');
              debugPrint('      userEmail: ${notif['userEmail']}');
              debugPrint('      isRead: ${notif['isRead']}');
              debugPrint('      createdAt: ${notif['createdAt']}');
            }
            if (notifications.length > 3) {
              debugPrint('   ... and ${notifications.length - 3} more');
            }
          } else {
            debugPrint('');
            debugPrint('⚠️  WARNING: No notifications in response!');
            debugPrint('   This means:');
            debugPrint('   1. Backend query returned empty result');
            debugPrint('   2. Check backend console for query logs');
            debugPrint('   3. Verify notification exists in MongoDB');
          }
          
          // Filter for customer-relevant notifications
          debugPrint('');
          debugPrint('🔍 Step 5: Filtering customer notifications');
          debugPrint('   Allowed types: ${_customerNotificationTypes.join(', ')}');
          
          _notifications = notifications
              .cast<Map<String, dynamic>>()
              .where((notification) {
                final type = notification['type']?.toString() ?? '';
                final isAllowed = _customerNotificationTypes.contains(type);
                if (!isAllowed) {
                  debugPrint('   ⊗ Filtered out: $type (not in allowed list)');
                }
                return isAllowed;
              })
              .toList();

          debugPrint('   Filtered count: ${_notifications.length}');

          // Sort by date (newest first)
          _notifications.sort((a, b) {
            final aDate = DateTime.parse(a['createdAt'] ?? DateTime.now().toIso8601String());
            final bDate = DateTime.parse(b['createdAt'] ?? DateTime.now().toIso8601String());
            return bDate.compareTo(aDate);
          });

          // Count unread
          _unreadCount = _notifications.where((n) => n['isRead'] != true).length;

          debugPrint('');
          debugPrint('✅ FINAL RESULT:');
          debugPrint('   Total notifications: ${_notifications.length}');
          debugPrint('   Unread count: $_unreadCount');
          debugPrint('═══════════════════════════════════════════════════════');
          debugPrint('');
        } else {
          _errorMessage = data['message'] ?? 'Failed to load notifications';
          debugPrint('❌ API returned success: false');
          debugPrint('   Message: $_errorMessage');
        }
      } else {
        _errorMessage = 'Server error: ${response.statusCode}';
        debugPrint('❌ HTTP Error: ${response.statusCode}');
        debugPrint('   Response: ${response.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('');
      debugPrint('❌ EXCEPTION OCCURRED:');
      debugPrint('   Error: $e');
      debugPrint('   Stack trace: $stackTrace');
      _errorMessage = 'Failed to load notifications: $e';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _setupRealtimeListener() {
    debugPrint('🔔 Setting up polling for real-time notifications');
    // Poll every 30 seconds for new notifications
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadNotifications();
      }
    });
  }

  // ✅ ENHANCED: Mark as read with real-time UI update
  Future<void> _markAsRead(String notificationId) async {
    try {
      debugPrint('📖 Marking notification as read: $notificationId');
      
      final token = await _getToken();
      if (token == null) {
        debugPrint('❌ No token available');
        return;
      }

      // Validate notification exists before updating
      final notificationIndex = _notifications.indexWhere((n) => n['_id'] == notificationId);
      if (notificationIndex == -1) {
        debugPrint('⚠️ Notification not found in local list: $notificationId');
        return;
      }

      // Check if already marked as read
      if (_notifications[notificationIndex]['isRead'] == true) {
        debugPrint('ℹ️ Notification already marked as read');
        return;
      }

      // Optimistically update UI immediately for better UX
      if (mounted) {
        setState(() {
          _notifications[notificationIndex]['isRead'] = true;
          _unreadCount = _notifications.where((n) => n['isRead'] != true).length;
          debugPrint('✅ UI updated optimistically - Unread count: $_unreadCount');
        });
      }

      // Make API call
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/notifications/$notificationId/read'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('📡 Mark as read response: ${response.statusCode}');

      if (response.statusCode == 200) {
        debugPrint('✅ Notification marked as read successfully');
        final responseData = json.decode(response.body);
        debugPrint('   Response: $responseData');
      } else if (response.statusCode == 404) {
        debugPrint('⚠️ Notification not found in database (may have been deleted)');
        // Keep the optimistic update - notification doesn't exist anyway
        // Remove from local list
        if (mounted) {
          setState(() {
            _notifications.removeAt(notificationIndex);
            _unreadCount = _notifications.where((n) => n['isRead'] != true).length;
          });
        }
      } else {
        debugPrint('❌ Failed to mark as read: ${response.statusCode}');
        debugPrint('   Response: ${response.body}');
        
        // Revert optimistic update on failure
        if (mounted) {
          setState(() {
            if (notificationIndex < _notifications.length) {
              _notifications[notificationIndex]['isRead'] = false;
              _unreadCount = _notifications.where((n) => n['isRead'] != true).length;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error marking notification as read: $e');
      
      // Revert optimistic update on error
      if (mounted) {
        setState(() {
          final index = _notifications.indexWhere((n) => n['_id'] == notificationId);
          if (index != -1) {
            _notifications[index]['isRead'] = false;
            _unreadCount = _notifications.where((n) => n['isRead'] != true).length;
          }
        });
      }
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      final token = await _getToken();
      if (token == null) return;

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/notifications/mark-all-read'),
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
            const SnackBar(
              content: Text('All notifications marked as read'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error marking all as read: $e');
    }
  }

  // ✅ NEW: Show delete confirmation dialog
  Future<bool?> _showDeleteConfirmation(String notificationId) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Notification?'),
          ],
        ),
        content: const Text('Are you sure you want to delete this notification? This action cannot be undone.'),
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

  // ✅ NEW: Delete notification functionality
  Future<void> _deleteNotification(String notificationId) async {
    try {
      debugPrint('🗑️ Deleting notification: $notificationId');
      
      final token = await _getToken();
      if (token == null) {
        debugPrint('❌ No token available');
        return;
      }

      // Optimistically remove from UI
      final notificationIndex = _notifications.indexWhere((n) => n['_id'] == notificationId);
      Map<String, dynamic>? removedNotification;
      
      if (notificationIndex != -1) {
        if (mounted) {
          setState(() {
            removedNotification = _notifications[notificationIndex];
            _notifications.removeAt(notificationIndex);
            _unreadCount = _notifications.where((n) => n['isRead'] != true).length;
            debugPrint('✅ Notification removed from UI optimistically');
          });
        }
      }

      // Make API call to delete
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/notifications/$notificationId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('📡 Delete response: ${response.statusCode}');

      if (response.statusCode == 200) {
        debugPrint('✅ Notification deleted successfully');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Notification deleted'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        debugPrint('❌ Failed to delete: ${response.statusCode}');
        debugPrint('   Response: ${response.body}');
        
        // Restore notification on failure
        if (removedNotification != null && mounted) {
          setState(() {
            _notifications.insert(notificationIndex, removedNotification!);
            _unreadCount = _notifications.where((n) => n['isRead'] != true).length;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete notification'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error deleting notification: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('My Notifications'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'FCM',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
        actions: [
          if (_unreadCount > 0)
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Mark all as read',
              onPressed: _markAllAsRead,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadNotifications,
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
            Text(_errorMessage!, textAlign: TextAlign.center),
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
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No notifications yet', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text(
              'You\'ll see updates about your trips,\nrosters, and leave requests here',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadNotifications,
      child: ListView.builder(
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          final notification = _notifications[index];
          return _buildNotificationCard(notification);
        },
      ),
    );
  }

  // ✅ ENHANCED: Improved notification card with delete button
  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final isRead = notification['isRead'] == true;
    final title = notification['title']?.toString() ?? 'Notification';
    final body = notification['body']?.toString() ?? '';
    final message = notification['message']?.toString() ?? '';
    final displayMessage = message.isNotEmpty ? message : body;
    final type = notification['type']?.toString() ?? '';
    final createdAt = notification['createdAt']?.toString();
    final notificationId = notification['_id']?.toString() ?? '';
    final priority = notification['priority']?.toString() ?? 'normal';

    DateTime? dateTime;
    if (createdAt != null) {
      try {
        dateTime = DateTime.parse(createdAt);
      } catch (e) {
        debugPrint('Error parsing date: $e');
      }
    }

    return Dismissible(
      key: Key(notificationId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete, color: Colors.white, size: 32),
            SizedBox(height: 4),
            Text(
              'Delete',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        final confirmed = await _showDeleteConfirmation(notificationId);
        if (confirmed == true) {
          await _deleteNotification(notificationId);
        }
        return false; // Don't auto-dismiss, we handle it manually
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: isRead ? null : _getPriorityColor(priority),
        elevation: isRead ? 1 : 3,
        child: ListTile(
          leading: _getNotificationIcon(type, priority),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              if (!isRead)
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (displayMessage.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  displayMessage,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
              if (dateTime != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      _getTimeAgo(dateTime),
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ],
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isRead)
                IconButton(
                  icon: const Icon(Icons.check_circle_outline, color: Colors.blue, size: 20),
                  tooltip: 'Mark as read',
                  onPressed: () => _markAsRead(notificationId),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                tooltip: 'Delete',
                onPressed: () async {
                  final confirmed = await _showDeleteConfirmation(notificationId);
                  if (confirmed == true) {
                    _deleteNotification(notificationId);
                  }
                },
              ),
            ],
          ),
          onTap: () {
            _showNotificationDetails(notification);
            if (!isRead) {
              _markAsRead(notificationId);
            }
          },
        ),
      ),
    );
  }

  // ✅ NEW: Get priority-based background color
  Color? _getPriorityColor(String priority) {
    switch (priority) {
      case 'urgent':
        return Colors.red.shade50;
      case 'high':
        return Colors.orange.shade50;
      default:
        return Colors.blue.shade50;
    }
  }

  // ✅ NEW: Calculate time ago
  String _getTimeAgo(DateTime dateTime) {
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

  // ✅ NEW: Map database field names to user-friendly labels
  String _getUserFriendlyLabel(String key) {
    const labelMap = {
      // Trip fields
      'tripGroupId': 'Trip ID',
      'stopId': 'Stop ID',
      'driverId': 'Driver',
      'driverName': 'Driver Name',
      'driverPhone': 'Driver Phone',
      'vehicleNumber': 'Vehicle Number',
      'pickupAddress': 'Pickup Location',
      'dropAddress': 'Drop Location',
      'pickupTime': 'Pickup Time',
      'dropTime': 'Drop Time',
      'eta': 'Estimated Arrival',
      'distance': 'Distance',
      'duration': 'Duration',
      
      // Route/Roster fields
      'routeId': 'Route',
      'routeName': 'Route Name',
      'rosterId': 'Roster',
      'rosterDate': 'Date',
      'shift': 'Shift',
      
      // Leave fields
      'leaveId': 'Leave Request',
      'leaveType': 'Leave Type',
      'startDate': 'Start Date',
      'endDate': 'End Date',
      'reason': 'Reason',
      'status': 'Status',
      
      // Address change fields
      'addressId': 'Address',
      'oldAddress': 'Old Address',
      'newAddress': 'New Address',
      'changeReason': 'Reason',
      
      // Feedback fields
      'feedbackId': 'Feedback',
      'rating': 'Rating',
      'comment': 'Comment',
      'adminReply': 'Admin Reply',
      
      // Generic fields
      'timestamp': 'Time',
      'message': 'Message',
      'description': 'Description',
      'notes': 'Notes',
    };

    return labelMap[key] ?? key.replaceAll('_', ' ').toUpperCase();
  }

  // ✅ NEW: Check if field should be hidden from UI
  bool _shouldHideField(String key, dynamic value) {
    // Hide technical/internal fields
    final hiddenFields = [
      '_id',
      'userId',
      'userEmail',
      'tripGroupId',
      'stopId',
      'driverId',
      'routeId',
      'rosterId',
      'leaveId',
      'addressId',
      'feedbackId',
      'type',
      'priority',
      'isRead',
      'readAt',
      'createdAt',
      'updatedAt',
      '__v',
      'tripId',           // ✅ ADDED: Hide trip ID
      'tripNumber',       // ✅ ADDED: Hide trip number (if it's technical)
    ];

    // Hide if in hidden list
    if (hiddenFields.contains(key)) {
      return true;
    }

    // Hide if value is empty
    if (value == null || value.toString().isEmpty || value.toString() == 'null') {
      return true;
    }

    return false;
  }

  // ✅ NEW: Format field value for display
  String _formatFieldValue(String key, dynamic value) {
    if (value == null) return 'N/A';

    // Format phone numbers
    if (key.toLowerCase().contains('phone')) {
      return value.toString();
    }

    // Format dates
    if (key.toLowerCase().contains('date') || key.toLowerCase().contains('time')) {
      try {
        final dateTime = DateTime.parse(value.toString());
        return DateFormat('MMM dd, yyyy • hh:mm a').format(dateTime);
      } catch (e) {
        return value.toString();
      }
    }

    // Format rating
    if (key.toLowerCase() == 'rating') {
      return '⭐ ${value.toString()} / 5';
    }

    // Format distance
    if (key.toLowerCase().contains('distance')) {
      return '$value km';
    }

    // Format duration
    if (key.toLowerCase().contains('duration')) {
      return '$value min';
    }

    return value.toString();
  }

  // ✅ NEW: Get icon for field
  IconData _getFieldIcon(String key) {
    const iconMap = {
      'driverName': Icons.person,
      'driverPhone': Icons.phone,
      'vehicleNumber': Icons.directions_car,
      'pickupAddress': Icons.location_on,
      'dropAddress': Icons.place,
      'pickupTime': Icons.access_time,
      'dropTime': Icons.schedule,
      'eta': Icons.timer,
      'distance': Icons.straighten,
      'duration': Icons.timelapse,
      'routeName': Icons.route,
      'shift': Icons.work,
      'rosterDate': Icons.calendar_today,
      'leaveType': Icons.event_busy,
      'startDate': Icons.date_range,
      'endDate': Icons.date_range,
      'reason': Icons.description,
      'status': Icons.info,
      'oldAddress': Icons.home,
      'newAddress': Icons.home_work,
      'rating': Icons.star,
      'comment': Icons.comment,
      'adminReply': Icons.reply,
    };

    return iconMap[key] ?? Icons.info_outline;
  }

  // ✅ COMPLETELY REDESIGNED: Beautiful notification details dialog
  void _showNotificationDetails(Map<String, dynamic> notification) {
    final title = notification['title']?.toString() ?? 'Notification Details';
    final body = notification['body']?.toString() ?? '';
    final message = notification['message']?.toString() ?? '';
    final displayMessage = message.isNotEmpty ? message : body;
    final type = notification['type']?.toString() ?? '';
    final createdAt = notification['createdAt']?.toString();
    final data = notification['data'] as Map<String, dynamic>? ?? {};
    final notificationId = notification['_id']?.toString() ?? '';
    final priority = notification['priority']?.toString() ?? 'normal';

    DateTime? dateTime;
    if (createdAt != null) {
      try {
        dateTime = DateTime.parse(createdAt);
      } catch (e) {
        debugPrint('Error parsing date: $e');
      }
    }

    // Filter and format data for display
    final displayData = <String, dynamic>{};
    data.forEach((key, value) {
      if (!_shouldHideField(key, value)) {
        displayData[key] = value;
      }
    });

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ✅ HEADER SECTION - Beautiful gradient header
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _getGradientColors(type, priority),
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: _getNotificationIcon(
                              type, 
                              priority, 
                              size: 32, 
                              color: Colors.white
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                if (dateTime != null) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.access_time,
                                        size: 14,
                                        color: Colors.white70,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        DateFormat('MMM dd, yyyy • hh:mm a').format(dateTime),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ✅ CONTENT SECTION
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Message section
                      if (displayMessage.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.message,
                              size: 20,
                              color: Colors.grey[700],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Message',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Text(
                            displayMessage,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.5,
                              color: Colors.grey[800],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Details section - Only show if there's data to display
                      if (displayData.isNotEmpty) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 20,
                              color: Colors.grey[700],
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Trip Details',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Beautiful detail cards
                        ...displayData.entries.map((entry) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[200]!),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    _getFieldIcon(entry.key),
                                    size: 20,
                                    color: Colors.blue[700],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _getUserFriendlyLabel(entry.key),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatFieldValue(entry.key, entry.value),
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey[900],
                                        ),
                                      ),
                                    ],
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

                // ✅ ACTION BUTTONS SECTION
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Delete button
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showDeleteConfirmation(notificationId).then((confirmed) {
                            if (confirmed == true) _deleteNotification(notificationId);
                          });
                        },
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        label: const Text('Delete', style: TextStyle(color: Colors.red)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),

                      // Action buttons based on type
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Feedback request button
                          if (type == 'feedback_request')
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                
                                final tripId = (data['tripId'] ?? data['stopId'] ?? '').toString().trim();
                                final driverId = (data['driverId'] ?? '').toString().trim();
                                
                                debugPrint('⭐ Opening feedback dialog for trip: $tripId, driver: $driverId');
                                debugPrint('📋 Full notification data: $data');
                                
                                if (tripId.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Error: Trip ID is missing'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }
                                
                                if (driverId.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Error: Driver ID is missing'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }
                                
                                final objectIdRegex = RegExp(r'^[0-9a-fA-F]{24}$');
                                if (!objectIdRegex.hasMatch(tripId)) {
                                  debugPrint('❌ Invalid tripId format: $tripId');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: Invalid trip ID format: $tripId'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }
                                
                                if (!objectIdRegex.hasMatch(driverId)) {
                                  debugPrint('❌ Invalid driverId format: $driverId');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: Invalid driver ID format: $driverId'),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return;
                                }
                                
                                _showFeedbackDialog(
                                  tripId: tripId,
                                  driverId: driverId,
                                  driverName: data['driverName'] ?? 'Your driver',
                                );
                              },
                              icon: const Icon(Icons.star, color: Colors.white, size: 20),
                              label: const Text('Give Feedback'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),

                          // Feedback reply button
                          if (type == 'feedback_reply')
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _navigateToFeedbackScreen();
                              },
                              icon: const Icon(Icons.feedback, color: Colors.white, size: 20),
                              label: const Text('View Feedback'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),

                          const SizedBox(width: 8),

                          // Close button
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[200],
                              foregroundColor: Colors.grey[800],
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ✅ NEW: Get gradient colors based on notification type and priority
  List<Color> _getGradientColors(String type, String priority) {
    if (priority == 'urgent') {
      return [Colors.red[700]!, Colors.red[500]!];
    }

    switch (type) {
      case 'trip_started':
      case 'driver_arrived':
      case 'trip_completed':
        return [Colors.green[600]!, Colors.green[400]!];
      
      case 'eta_15min':
      case 'eta_5min':
      case 'pickup_reminder':
        return [Colors.orange[600]!, Colors.orange[400]!];
      
      case 'trip_cancelled':
      case 'trip_delayed':
      case 'leave_rejected':
        return [Colors.red[600]!, Colors.red[400]!];
      
      case 'feedback_request':
        // ✅ CHANGED: Better gradient for feedback request (Blue-Purple)
        return [const Color(0xFF5E35B1), const Color(0xFF7E57C2)]; // Purple gradient
      
      case 'feedback_reply':
        return [Colors.purple[600]!, Colors.purple[400]!];
      
      case 'leave_approved':
      case 'address_change_approved':
        return [Colors.teal[600]!, Colors.teal[400]!];
      
      default:
        return [Colors.blue[600]!, Colors.blue[400]!];
    }
  }

  // ✅ NEW: Show feedback dialog for customer to give feedback
  void _showFeedbackDialog({
    required String tripId,
    required String driverId,
    required String driverName,
  }) async {
    try {
      debugPrint('⭐ Opening feedback dialog for trip: $tripId, driver: $driverId');
      
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => CustomerFeedbackDialog(
          tripId: tripId,
          driverId: driverId,
          driverName: driverName,
        ),
      );

      if (result == true) {
        debugPrint('✅ Feedback submitted successfully');
        _loadNotifications();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Thank you for your feedback!'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error showing feedback dialog: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ✅ NEW: Navigate to feedback screen
  void _navigateToFeedbackScreen() {
    try {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => HRMFeedbackScreen(),
        ),
      );
    } catch (e) {
      debugPrint('❌ Error navigating to feedback screen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open feedback screen'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ MODIFIED: Enhanced icons for trip notifications with customizable size and color
  Widget _getNotificationIcon(String type, String priority, {double size = 24, Color? color}) {
    IconData iconData;
    Color iconColor;

    switch (type) {
      // Original types
      case 'route_assigned':
      case 'roster_assigned':
        iconData = Icons.directions_car;
        iconColor = Colors.green;
        break;
      case 'roster_assignment_updated':
        iconData = Icons.update;
        iconColor = Colors.blue;
        break;
      case 'leave_approved':
        iconData = Icons.check_circle;
        iconColor = Colors.green;
        break;
      case 'leave_rejected':
        iconData = Icons.cancel;
        iconColor = Colors.red;
        break;
      case 'trip_updated':
        iconData = Icons.edit;
        iconColor = Colors.orange;
        break;
      case 'trip_cancelled':
        iconData = Icons.cancel;
        iconColor = Colors.red;
        break;
      case 'pickup_reminder':
        iconData = Icons.alarm;
        iconColor = Colors.purple;
        break;
      case 'address_change_approved':
        iconData = Icons.location_on;
        iconColor = Colors.green;
        break;
      case 'address_change_rejected':
        iconData = Icons.location_off;
        iconColor = Colors.red;
        break;

      // ✅ NEW: Trip notification icons
      case 'trip_assigned':
        iconData = Icons.assignment_turned_in;
        iconColor = Colors.blue;
        break;
      case 'trip_started':
        iconData = Icons.directions_car_filled;
        iconColor = Colors.green;
        break;
      case 'eta_15min':
        iconData = Icons.schedule;
        iconColor = Colors.orange;
        break;
      case 'eta_5min':
        iconData = Icons.notifications_active;
        iconColor = Colors.red;
        break;
      case 'driver_arrived':
        iconData = Icons.location_on;
        iconColor = Colors.green;
        break;
      case 'trip_delayed':
        iconData = Icons.warning;
        iconColor = Colors.red;
        break;
      case 'trip_completed':
        iconData = Icons.check_circle;
        iconColor = Colors.green;
        break;

      // ✅ NEW: Feedback notifications
      case 'feedback_reply':
        iconData = Icons.reply;
        iconColor = Colors.purple;
        break;
      case 'feedback_request':
        iconData = Icons.star_rate;
        iconColor = Colors.amber;
        break;

      default:
        iconData = Icons.notifications;
        iconColor = Colors.grey;
    }

    // Override color for urgent priority
    if (priority == 'urgent') {
      iconColor = Colors.red;
    }

    // Use custom color if provided
    final finalColor = color ?? iconColor;

    return CircleAvatar(
      backgroundColor: finalColor.withOpacity(0.1),
      child: Icon(iconData, color: finalColor, size: size * 0.6),
    );
  }
}

// ✅ NEW: Customer Feedback Dialog Widget
class CustomerFeedbackDialog extends StatefulWidget {
  final String tripId;
  final String driverId;
  final String driverName;

  const CustomerFeedbackDialog({
    super.key,
    required this.tripId,
    required this.driverId,
    required this.driverName,
  });

  @override
  State<CustomerFeedbackDialog> createState() => _CustomerFeedbackDialogState();
}

class _CustomerFeedbackDialogState extends State<CustomerFeedbackDialog> {
  double _rating = 5.0;
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (_rating < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide a rating'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/driver/customer/feedback/submit'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'tripId': widget.tripId,
          'driverId': widget.driverId,
          'rating': _rating,
          'comment': _commentController.text.trim(),
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        throw Exception('Failed to submit feedback: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error submitting feedback: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star, color: Colors.amber, size: 32),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rate Your Trip',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'How was ${widget.driverName}?',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Rating slider
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return Icon(
                      index < _rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 40,
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Slider(
                  value: _rating,
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: _rating.toString(),
                  activeColor: Colors.amber,
                  onChanged: (value) {
                    setState(() {
                      _rating = value;
                    });
                  },
                ),
                Text(
                  '${_rating.toInt()} out of 5 stars',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
            ),
            
            const SizedBox(height: 20),
            
            // Comment field
            TextField(
              controller: _commentController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Share your experience (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitFeedback,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Submit',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}