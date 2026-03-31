// File: lib/features/notifications/presentation/screens/client_notifications_screen.dart
// Client notifications screen - Works IDENTICAL to DriverNotificationsScreen
// Uses direct HTTP + JWT token → /api/notifications (same backend endpoint as driver)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class ClientNotificationsScreen extends StatefulWidget {
  const ClientNotificationsScreen({super.key});

  static const String routeName = '/client/notifications';

  @override
  State<ClientNotificationsScreen> createState() =>
      _ClientNotificationsScreenState();
}

class _ClientNotificationsScreenState
    extends State<ClientNotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _pollingTimer;
  int _unreadCount = 0;

  // ─── JWT token helper — identical to driver screen ───────────────────────
  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      debugPrint('❌ Error getting JWT token: $e');
      return null;
    }
  }

  // ─── Client-specific notification types ──────────────────────────────────
  static const List<String> _clientNotificationTypes = [
    // Roster management
    'roster_assigned',
    'roster_assignment_updated',
    'roster_bulk_import_completed',
    'roster_optimization_completed',

    // Employee management
    'employee_bulk_import_completed',
    'employee_added',
    'employee_updated',

    // Trip management
    'trip_created',
    'trip_updated',
    'trip_cancelled',
    'trip_completed',
    'multiple_trips_assigned',
    'client_trip_confirmed',  // ✅ ADDED - When admin confirms a trip
    'trip_confirmed',         // ✅ ADDED - Alternative naming

    // Billing and reports
    'invoice_generated',
    'payment_received',
    'monthly_report_ready',
    'billing_summary_ready',

    // System notifications
    'system_maintenance',
    'feature_update',
    'data_backup_completed',
    'system',

    // Feedback and support
    'feedback_received',
    'support_ticket_created',
    'support_ticket_resolved',
 'client_request',
    // Alerts and warnings
    'vehicle_maintenance_due',
    'driver_unavailable',
    'route_optimization_failed',
    'capacity_exceeded',

    // Document expiry (shared with driver but relevant to clients too)
    'document_expiring_soon',
    'document_expired',

    // Admin alerts
    'admin_alert',
  ];

  // ─── Lifecycle ────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    debugPrint('🔔 ClientNotificationsScreen: initState called');
    _loadNotifications();
    _setupPollingListener();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  // ─── Load notifications — exact same pattern as driver screen ─────────────
  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('🔔 CLIENT NOTIFICATIONS - LOADING');
      debugPrint('═══════════════════════════════════════════════════════');

      // Step 1: Get JWT token
      debugPrint('📝 Step 1: Getting JWT token...');
      final token = await _getToken();

      if (token == null) {
        debugPrint('❌ ERROR: No JWT token found!');
        throw Exception('No authentication token found');
      }

      debugPrint('✅ JWT token retrieved');
      debugPrint('   Token length: ${token.length} characters');

      // Decode JWT to show user info
      try {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = json.decode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
          );
          debugPrint('   JWT userId: ${payload['userId']}');
          debugPrint('   JWT email: ${payload['email']}');
          debugPrint('   JWT role: ${payload['role']}');
        }
      } catch (e) {
        debugPrint('   (Could not decode JWT: $e)');
      }

      // Step 2: Make API request — SAME endpoint as driver screen
      final url = '${ApiConfig.baseUrl}/api/notifications';
      debugPrint('');
      debugPrint('📡 Step 2: Making API request...');
      debugPrint('   URL: $url');
      debugPrint('   Method: GET');

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

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        debugPrint('');
        debugPrint('📦 Step 4: Parsing response data');
        debugPrint('   success: ${data['success']}');
        debugPrint('   total: ${data['total']}');
        debugPrint('   unreadCount: ${data['unreadCount']}');

        if (data['success'] == true) {
          final notifications =
              data['notifications'] as List<dynamic>? ?? [];

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
            debugPrint('   Check backend console for query logs.');
          }

          // Step 5: Filter for client-relevant notifications
          debugPrint('');
          debugPrint('🔍 Step 5: Filtering client notifications');

          _notifications = notifications
              .cast<Map<String, dynamic>>()
              .where((notification) {
                final type = notification['type']?.toString() ?? '';
                final isAllowed = _clientNotificationTypes.contains(type);
                if (!isAllowed) {
                  debugPrint('   ⊗ Filtered out: $type');
                }
                return isAllowed;
              })
              .toList();

          debugPrint('   Filtered count: ${_notifications.length}');

          // Sort newest first
          _notifications.sort((a, b) {
            final aDate = DateTime.parse(
                a['createdAt'] ?? DateTime.now().toIso8601String());
            final bDate = DateTime.parse(
                b['createdAt'] ?? DateTime.now().toIso8601String());
            return bDate.compareTo(aDate);
          });

          _unreadCount =
              _notifications.where((n) => n['isRead'] != true).length;

          debugPrint('');
          debugPrint('✅ FINAL RESULT:');
          debugPrint('   Total notifications: ${_notifications.length}');
          debugPrint('   Unread count: $_unreadCount');
          debugPrint('═══════════════════════════════════════════════════════');
          debugPrint('');
        } else {
          _errorMessage = data['message'] ?? 'Failed to load notifications';
          debugPrint('❌ API returned success: false — $_errorMessage');
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

  // ─── Polling — identical to driver screen (30s interval) ─────────────────
  void _setupPollingListener() {
    debugPrint('🔔 Setting up polling for real-time client notifications');
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) _loadNotifications();
    });
  }

  // ─── Mark single as read ──────────────────────────────────────────────────
  Future<void> _markAsRead(String notificationId) async {
    try {
      final token = await _getToken();
      if (token == null) return;

      final response = await http.put(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/notifications/$notificationId/read'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200 && mounted) {
        setState(() {
          final index =
              _notifications.indexWhere((n) => n['_id'] == notificationId);
          if (index != -1) {
            _notifications[index]['isRead'] = true;
            _unreadCount =
                _notifications.where((n) => n['isRead'] != true).length;
          }
        });
      }
    } catch (e) {
      debugPrint('❌ Error marking notification as read: $e');
    }
  }

  // ─── Mark all as read ─────────────────────────────────────────────────────
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
                content: Text('All notifications marked as read')),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error marking all as read: $e');
    }
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Client Notifications'),
            if (_unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            Text('No notifications yet',
                style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text(
              'You\'ll see updates about your fleet,\nrosters, billing, and reports here',
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

  // ─── Notification card — same structure as driver screen ─────────────────
  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final isRead = notification['isRead'] == true;
    final title = notification['title']?.toString() ?? 'Notification';
    final body = notification['body']?.toString() ??
        notification['message']?.toString() ??
        '';
    final type = notification['type']?.toString() ?? '';
    final priority = notification['priority']?.toString() ?? 'normal';
    final createdAt = notification['createdAt']?.toString();
    final notificationId = notification['_id']?.toString() ?? '';

    DateTime? dateTime;
    if (createdAt != null) {
      try {
        dateTime = DateTime.parse(createdAt);
      } catch (e) {
        debugPrint('Error parsing date: $e');
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: isRead ? null : Colors.blue.shade50,
      elevation: isRead ? 1 : 3,
      child: ListTile(
        leading: _getNotificationIcon(type, priority),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(body,
                  maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getPriorityColor(priority).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    priority.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getPriorityColor(priority),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (dateTime != null)
                  Text(
                    DateFormat('MMM dd, yyyy • hh:mm a').format(dateTime),
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ],
        ),
        trailing: !isRead
            ? IconButton(
                icon: const Icon(Icons.check, color: Colors.blue),
                onPressed: () => _markAsRead(notificationId),
              )
            : null,
        onTap: () {
          _showNotificationDetails(notification);
          if (!isRead) _markAsRead(notificationId);
        },
      ),
    );
  }

  // ─── Details dialog ───────────────────────────────────────────────────────
  void _showNotificationDetails(Map<String, dynamic> notification) {
    final title = notification['title']?.toString() ?? 'Notification';
    final body = notification['body']?.toString() ??
        notification['message']?.toString() ??
        '';
    final type = notification['type']?.toString() ?? '';
    final priority = notification['priority']?.toString() ?? 'normal';
    final createdAt = notification['createdAt']?.toString();
    final data =
        notification['data'] as Map<String, dynamic>? ?? {};

    DateTime? dateTime;
    if (createdAt != null) {
      try {
        dateTime = DateTime.parse(createdAt);
      } catch (_) {}
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blue.shade700,
                      Colors.blue.shade900
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getIconForType(type),
                        size: 32,
                        color: Colors.white,
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
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          if (dateTime != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('MMM dd, yyyy • hh:mm a')
                                  .format(dateTime),
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Priority badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getPriorityColor(priority)
                                .withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            priority.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _getPriorityColor(priority),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Message
                    if (body.isNotEmpty) ...[
                      const Text(
                        'Message',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        body,
                        style: const TextStyle(
                            fontSize: 15, height: 1.5),
                      ),
                    ],

                    // Extra data fields (if any)
                    if (data.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      const Text(
                        'Details',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...data.entries
                          .where((e) => e.value != null)
                          .map((entry) => Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 8),
                                child: _buildDetailRow(
                                  icon: Icons.info_outline,
                                  label: entry.key
                                      .replaceAll('_', ' ')
                                      .toUpperCase(),
                                  value:
                                      entry.value?.toString() ?? 'N/A',
                                ),
                              ))
                          .toList(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ─── Detail row helper (same as driver screen) ────────────────────────────
  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool isHighlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isHighlight
                ? Colors.blue.shade50
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isHighlight
                ? Colors.blue.shade700
                : Colors.grey.shade600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isHighlight
                      ? FontWeight.bold
                      : FontWeight.w500,
                  color: isHighlight
                      ? Colors.blue.shade900
                      : Colors.grey.shade900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Icon for notification type ───────────────────────────────────────────
  IconData _getIconForType(String type) {
    switch (type) {
      case 'roster_assigned':
      case 'roster_assignment_updated':
        return Icons.assignment;
      case 'roster_bulk_import_completed':
        return Icons.cloud_upload;
      case 'roster_optimization_completed':
        return Icons.auto_fix_high;
      case 'employee_bulk_import_completed':
      case 'employee_added':
        return Icons.people;
      case 'employee_updated':
        return Icons.person;
      case 'trip_created':
        return Icons.add_road;
      case 'trip_updated':
        return Icons.edit_road;
      case 'trip_cancelled':
        return Icons.cancel;
      case 'trip_completed':
        return Icons.check_circle;
      case 'client_trip_confirmed':
      case 'trip_confirmed':
        return Icons.check_circle_outline;
      case 'multiple_trips_assigned':
        return Icons.multiple_stop;
      case 'invoice_generated':
        return Icons.receipt;
      case 'payment_received':
        return Icons.payment;
      case 'monthly_report_ready':
        return Icons.analytics;
      case 'billing_summary_ready':
        return Icons.account_balance;
      case 'system_maintenance':
        return Icons.build;
      case 'feature_update':
        return Icons.new_releases;
      case 'data_backup_completed':
        return Icons.backup;
      case 'feedback_received':
        return Icons.feedback;
      case 'support_ticket_created':
        return Icons.support_agent;
      case 'support_ticket_resolved':
        return Icons.check_circle;
      case 'vehicle_maintenance_due':
        return Icons.car_repair;
      case 'driver_unavailable':
        return Icons.person_off;
      case 'route_optimization_failed':
        return Icons.error;
      case 'capacity_exceeded':
        return Icons.warning;
      case 'document_expiring_soon':
        return Icons.description;
      case 'document_expired':
        return Icons.warning_amber;
      case 'admin_alert':
        return Icons.campaign;
      default:
        return Icons.notifications;
    }
  }

  // ─── Icon widget ──────────────────────────────────────────────────────────
  Widget _getNotificationIcon(String type, String priority) {
    final color = _getPriorityColor(priority);
    return CircleAvatar(
      backgroundColor: color.withOpacity(0.1),
      child: Icon(
        _getIconForType(type),
        size: 20,
        color: color,
      ),
    );
  }

  // ─── Priority colour ──────────────────────────────────────────────────────
  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'urgent':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'normal':
        return Colors.blue;
      case 'low':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }
}