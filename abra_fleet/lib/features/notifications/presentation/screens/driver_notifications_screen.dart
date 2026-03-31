// File: lib/features/notifications/presentation/screens/driver_notifications_screen.dart
// Driver-specific notifications screen - FCM/Database Implementation

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/services/individual_trip_service.dart';

class DriverNotificationsScreen extends StatefulWidget {
  const DriverNotificationsScreen({super.key});

  static const String routeName = '/driver/notifications';

  @override
  State<DriverNotificationsScreen> createState() => _DriverNotificationsScreenState();
}

class _DriverNotificationsScreenState extends State<DriverNotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _pollingTimer;
  int _unreadCount = 0;

  // ── Inline response panel state ─────────────────────────────────────────────
  final Map<String, bool>    _expandedResponsePanel = {};
  final Map<String, String>  _respondedTrips        = {};
  final Map<String, String?> _selectedResponse      = {};
  final Map<String, bool>    _submittingResponse    = {};
  final Map<String, TextEditingController> _notesControllers = {};
  final Map<String, TextEditingController> _declineNotesControllers = {};

  final IndividualTripService _tripService = IndividualTripService();

  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      debugPrint('❌ Error getting JWT token: $e');
      return null;
    }
  }

  static const List<String> _driverNotificationTypes = [
    'trip_assigned',
    'trip_updated',
    'route_optimized',
    'payment_received',
    'roster_assigned',
    'vehicle_assigned',
    'roster_updated',
    'roster_cancelled',
    'trip_cancelled',
    'trip_started',
    'trip_completed',
    'route_assigned',
    'route_assigned_driver',
    'driver_route_assignment',
    'admin_alert',
    'shift_reminder',
    'document_expiring_soon',
    'document_expired',
    'client_trip_assigned',
    'client_trip_updated',
    'emergency_alert',
    'feedback_reply',
    'system',
  ];

  @override
  void initState() {
    super.initState();
    debugPrint('🔔 DriverNotificationsScreen: initState called');
    _loadNotifications();
    _setupPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    for (final c in _notesControllers.values) {
      c.dispose();
    }
    for (final c in _declineNotesControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadNotifications({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      debugPrint('');
      debugPrint('═══════════════════════════════════════════════════════');
      debugPrint('🔔 DRIVER NOTIFICATIONS - LOADING');
      debugPrint('═══════════════════════════════════════════════════════');

      debugPrint('📝 Step 1: Getting JWT token...');
      final token = await _getToken();

      if (token == null) {
        debugPrint('❌ ERROR: No JWT token found!');
        throw Exception('No authentication token found');
      }

      debugPrint('✅ JWT token retrieved');

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

      final url = '${ApiConfig.baseUrl}/api/notifications';
      debugPrint('📡 Step 2: Making API request to $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('📊 Step 3: Response received - Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        debugPrint('📦 Step 4: Parsing response data');
        debugPrint('   success: ${data['success']}');
        debugPrint('   total: ${data['total']}');
        debugPrint('   unreadCount: ${data['unreadCount']}');

        if (data['success'] == true) {
          final notifications = data['notifications'] as List<dynamic>? ?? [];

          debugPrint('   Raw notifications count: ${notifications.length}');

          // Build a set of tripIds that have already been responded to from backend data
          // so we can pre-populate _respondedTrips
          for (final notif in notifications) {
            final notifData = notif['data'] as Map<String, dynamic>? ?? {};
            final tripId = notifData['tripId']?.toString();
            final driverResponse = notifData['driverResponse']?.toString();
            if (tripId != null && driverResponse != null &&
                (driverResponse == 'accepted' || driverResponse == 'declined' ||
                 driverResponse == 'accept' || driverResponse == 'decline')) {
              final normalizedResponse = (driverResponse == 'accepted' || driverResponse == 'accept')
                  ? 'accept'
                  : 'decline';
              if (!_respondedTrips.containsKey(tripId)) {
                _respondedTrips[tripId] = normalizedResponse;
              }
            }
            // Also check tripStatus field
            final tripStatus = notifData['tripStatus']?.toString() ?? '';
            if (tripId != null && !_respondedTrips.containsKey(tripId)) {
              if (tripStatus == 'accepted' || tripStatus == 'declined') {
                _respondedTrips[tripId] = tripStatus == 'accepted' ? 'accept' : 'decline';
              }
            }
          }

          _notifications = notifications
              .cast<Map<String, dynamic>>()
              .where((notification) {
                final type = notification['type']?.toString() ?? '';
                final isAllowed = _driverNotificationTypes.contains(type);
                if (!isAllowed) {
                  debugPrint('   ⊗ Filtered out: $type (not in allowed list)');
                }
                return isAllowed;
              })
              .toList();

          debugPrint('   Filtered count: ${_notifications.length}');

          _notifications.sort((a, b) {
            final aDate = DateTime.parse(a['createdAt'] ?? DateTime.now().toIso8601String());
            final bDate = DateTime.parse(b['createdAt'] ?? DateTime.now().toIso8601String());
            return bDate.compareTo(aDate);
          });

          _unreadCount = _notifications.where((n) => n['isRead'] != true).length;

          debugPrint('✅ FINAL RESULT:');
          debugPrint('   Total notifications: ${_notifications.length}');
          debugPrint('   Unread count: $_unreadCount');
          debugPrint('═══════════════════════════════════════════════════════');
        } else {
          if (!silent) _errorMessage = data['message'] ?? 'Failed to load notifications';
          debugPrint('❌ API returned success: false');
        }
      } else {
        if (!silent) _errorMessage = 'Server error: ${response.statusCode}';
        debugPrint('❌ HTTP Error: ${response.statusCode}');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ EXCEPTION OCCURRED: $e');
      debugPrint('   Stack trace: $stackTrace');
      if (!silent) {
        _errorMessage = 'Failed to load notifications: $e';
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _setupPolling() {
    debugPrint('🔔 Setting up polling for real-time notifications');
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _loadNotifications(silent: true);
      }
    });
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      final token = await _getToken();
      if (token == null) return;

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/notifications/$notificationId/read'),
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

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All notifications marked as read')),
        );
      }
    } catch (e) {
      debugPrint('❌ Error marking all as read: $e');
    }
  }

  // ============================================================================
  // INLINE RESPONSE SUBMISSION
  // ============================================================================
  Future<void> _submitInlineResponse(String notificationId, Map<String, dynamic> data) async {
    final tripId = data['tripId']?.toString();
    if (tripId == null) return;

    final response = _selectedResponse[notificationId];
    if (response == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Accept or Decline'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Decline requires notes
    if (response == 'decline') {
      final declineNotes = _declineNotesControllers[notificationId]?.text.trim() ?? '';
      if (declineNotes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please provide a reason for declining'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() => _submittingResponse[notificationId] = true);

    try {
      final notes = response == 'decline'
          ? (_declineNotesControllers[notificationId]?.text.trim() ?? '')
          : (_notesControllers[notificationId]?.text.trim() ?? '');

      final notifType = data['notificationType']?.toString() ?? '';
      final tripType  = data['tripType']?.toString() ?? '';
      final isClientTrip = tripType == 'client_request' ||
          notifType == 'client_trip_assigned' ||
          data['clientName'] != null;

      if (isClientTrip) {
        final token = await _getToken();
        if (token == null) throw Exception('No authentication token found');

        final url = '${ApiConfig.baseUrl}/api/client-trips/$tripId/driver-response';
        debugPrint('📤 Client trip response → $url');

        final httpResp = await http.post(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: json.encode({'response': response, 'notes': notes}),
        );

        debugPrint('📡 ${httpResp.statusCode} | ${httpResp.body}');

        if (httpResp.statusCode != 200) {
          final body = json.decode(httpResp.body);
          throw Exception(body['message'] ?? 'Failed (${httpResp.statusCode})');
        }
        final respData = json.decode(httpResp.body);
        if (respData['success'] != true) {
          throw Exception(respData['message'] ?? 'Server failure');
        }
      } else {
        await _tripService.respondToTrip(
          tripId: tripId,
          response: response,
          notes: notes,
        );
      }

      if (!mounted) return;

      setState(() {
        _respondedTrips[tripId]              = response;
        _expandedResponsePanel[notificationId] = false;
        _submittingResponse[notificationId]    = false;
        _selectedResponse.remove(notificationId);
        
        // Update notification data to persist the response
        final notifIndex = _notifications.indexWhere((n) => n['_id'] == notificationId);
        if (notifIndex != -1) {
          final notifData = _notifications[notifIndex]['data'] as Map<String, dynamic>? ?? {};
          notifData['driverResponse'] = response;
          _notifications[notifIndex]['data'] = notifData;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response == 'accept'
              ? '✅ Trip accepted! Admin has been notified.'
              : '❌ Trip declined. Admin has been notified.'),
          backgroundColor: response == 'accept' ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submittingResponse[notificationId] = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit response: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Driver Notifications'),
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
            onPressed: () => _loadNotifications(),
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
              'You\'ll see updates about your routes,\ntrips, and schedules here',
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

  // ============================================================================
  // NOTIFICATION CARD — compact with small Reply button on the right
  // ============================================================================
  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final isRead          = notification['isRead'] == true;
    final title           = notification['title']?.toString() ?? 'Notification';
    final message         = notification['message']?.toString() ?? '';
    final type            = notification['type']?.toString() ?? '';
    final priority        = notification['priority']?.toString() ?? 'normal';
    final createdAt       = notification['createdAt']?.toString();
    final notificationId  = notification['_id']?.toString() ?? '';
    final data            = notification['data'] as Map<String, dynamic>? ?? {};

    final enrichedData = Map<String, dynamic>.from(data);
    enrichedData['notificationType'] = type;

    final isTripAssignment = (type == 'trip_assigned' || type == 'client_trip_assigned')
        && data['requiresResponse'] == true;

    final tripId           = data['tripId']?.toString();
    final alreadyResponded = tripId != null && _respondedTrips.containsKey(tripId);
    final isPanelOpen      = _expandedResponsePanel[notificationId] == true;
    final isSubmitting     = _submittingResponse[notificationId] == true;
    final currentSelected  = _selectedResponse[notificationId];

    _notesControllers.putIfAbsent(notificationId, () => TextEditingController());
    _declineNotesControllers.putIfAbsent(notificationId, () => TextEditingController());

    DateTime? dateTime;
    if (createdAt != null) {
      try {
        dateTime = DateTime.parse(createdAt).toUtc().toLocal();
      } catch (e) {
        debugPrint('Error parsing date: $e');
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: isRead ? null : Colors.blue.shade50,
      elevation: isTripAssignment && !isRead ? 4 : (isRead ? 1 : 3),
      shape: isTripAssignment && !isRead
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.blue.shade400, width: 1.5),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Main notification row ──────────────────────────────────────────
          InkWell(
            onTap: () {
              _showNotificationDetails(notification);
              if (!isRead) _markAsRead(notificationId);
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  _getNotificationIcon(type, priority),
                  const SizedBox(width: 12),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if (message.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.black87),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Right side: Reply button OR mark-read OR responded badge
                  Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!isRead && !isTripAssignment)
                        IconButton(
                          icon: const Icon(Icons.check, color: Colors.blue, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _markAsRead(notificationId),
                        ),
                      if (isTripAssignment) ...[
                        if (alreadyResponded) ...[
                          // Small responded badge on the right
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _respondedTrips[tripId] == 'accept'
                                  ? Colors.green.shade100
                                  : Colors.red.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _respondedTrips[tripId] == 'accept'
                                    ? Colors.green.shade400
                                    : Colors.red.shade400,
                              ),
                            ),
                            child: Text(
                              _respondedTrips[tripId] == 'accept' ? '✅ Accepted' : '❌ Declined',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _respondedTrips[tripId] == 'accept'
                                    ? Colors.green.shade800
                                    : Colors.red.shade800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          // Small "Respond Again" button below the status badge
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Change Response?'),
                                  content: Text(
                                    'You have already ${_respondedTrips[tripId] == 'accept' ? 'accepted' : 'declined'} this trip. Do you want to change your response?'
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        if (!isRead) _markAsRead(notificationId);
                                        setState(() {
                                          // Clear the previous response so the panel shows Accept/Decline options
                                          _respondedTrips.remove(tripId);
                                          _selectedResponse.remove(notificationId);
                                          _expandedResponsePanel[notificationId] = true;
                                        });
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                      ),
                                      child: const Text('Yes, Change'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.blue.shade400, width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.edit, size: 10, color: Colors.blue.shade700),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Respond Again',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else if (!isPanelOpen)
                          // Small Reply button
                          GestureDetector(
                            onTap: () {
                              if (!isRead) _markAsRead(notificationId);
                              setState(() {
                                _expandedResponsePanel[notificationId] = true;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.blue.shade400, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.shade100,
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.reply, size: 14, color: Colors.blue.shade700),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Reply',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          // Close panel button
                          GestureDetector(
                            onTap: isSubmitting ? null : () => setState(() {
                              _expandedResponsePanel[notificationId] = false;
                              _selectedResponse.remove(notificationId);
                            }),
                            child: Icon(Icons.close, size: 20, color: Colors.grey.shade600),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Inline response OVERLAY card ───────────────────────────────────
          // Show panel if it's open, regardless of whether already responded
          // (user can change their response)
          if (isTripAssignment && isPanelOpen)
            _buildInlineResponsePanel(
              notificationId: notificationId,
              enrichedData: enrichedData,
              currentSelected: currentSelected,
              isSubmitting: isSubmitting,
            ),
        ],
      ),
    );
  }

  // ============================================================================
  // INLINE RESPONSE PANEL — overlays inside the card
  // Decline → mandatory notes field
  // ============================================================================
  Widget _buildInlineResponsePanel({
    required String notificationId,
    required Map<String, dynamic> enrichedData,
    required String? currentSelected,
    required bool isSubmitting,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade300, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade50,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Panel header
          Row(
            children: [
              Icon(Icons.reply, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'Respond to Trip Assignment',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Accept / Decline choice buttons
          Row(
            children: [
              Expanded(
                child: _responseChoiceButton(
                  label: 'Accept',
                  icon: Icons.check_circle,
                  color: Colors.green,
                  isSelected: currentSelected == 'accept',
                  onTap: isSubmitting
                      ? null
                      : () => setState(() {
                            _selectedResponse[notificationId] = 'accept';
                          }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _responseChoiceButton(
                  label: 'Decline',
                  icon: Icons.cancel,
                  color: Colors.red,
                  isSelected: currentSelected == 'decline',
                  onTap: isSubmitting
                      ? null
                      : () => setState(() {
                            _selectedResponse[notificationId] = 'decline';
                          }),
                ),
              ),
            ],
          ),

          // Accept: optional notes
          if (currentSelected == 'accept') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _notesControllers[notificationId],
              maxLines: 2,
              enabled: !isSubmitting,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Add a note (optional)...',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Colors.blue, width: 1.5),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],

          // Decline: MANDATORY reason field
          if (currentSelected == 'decline') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.error_outline, size: 14, color: Colors.red.shade600),
                const SizedBox(width: 4),
                Text(
                  'Reason for declining (required)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _declineNotesControllers[notificationId],
              maxLines: 3,
              enabled: !isSubmitting,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Enter reason for declining this trip...',
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.red.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.red.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.red.shade600, width: 1.5),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.red.shade600, width: 2),
                ),
                filled: true,
                fillColor: Colors.red.shade50,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isSubmitting || currentSelected == null
                  ? null
                  : () => _submitInlineResponse(notificationId, enrichedData),
              style: ElevatedButton.styleFrom(
                backgroundColor: currentSelected == 'accept'
                    ? Colors.green
                    : currentSelected == 'decline'
                        ? Colors.red
                        : Colors.grey.shade400,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: isSubmitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      currentSelected == null
                          ? 'Select a response'
                          : currentSelected == 'accept'
                              ? '✅  Confirm Accept'
                              : '❌  Confirm Decline',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: currentSelected != null ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // Single accept / decline choice button inside the panel
  // ============================================================================
  Widget _responseChoiceButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: isSelected ? color : Colors.grey.shade400),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // RESPONSE BADGE — shown after responding
  // ============================================================================
  Widget _buildResponseBadge(String response) {
    final isAccepted = response == 'accept';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
      decoration: BoxDecoration(
        color: isAccepted ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isAccepted ? Colors.green.shade300 : Colors.red.shade300,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isAccepted ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: isAccepted ? Colors.green.shade700 : Colors.red.shade700,
          ),
          const SizedBox(width: 8),
          Text(
            isAccepted ? 'You accepted this trip' : 'You declined this trip',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isAccepted ? Colors.green.shade800 : Colors.red.shade800,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // NOTIFICATION DETAIL DIALOG — unchanged original behaviour
  // ============================================================================
  void _showNotificationDetails(Map<String, dynamic> notification) {
    final title          = notification['title']?.toString() ?? 'Notification';
    final body           = notification['body']?.toString() ?? '';
    final type           = notification['type']?.toString() ?? '';
    final priority       = notification['priority']?.toString() ?? 'normal';
    final createdAt      = notification['createdAt']?.toString();
    final data           = notification['data'] as Map<String, dynamic>? ?? {};
    final notificationId = notification['_id']?.toString() ?? '';

    final isTripAssignment = (type == 'trip_assigned' || type == 'client_trip_assigned')
        && data['requiresResponse'] == true;

    final tripId           = data['tripId']?.toString();
    final alreadyResponded = tripId != null && _respondedTrips.containsKey(tripId);

    String dialogTitle;
    if (type == 'trip_assigned') {
      dialogTitle = 'New Trip Assignment';
    } else if (type == 'client_trip_assigned') {
      dialogTitle = 'New Client Trip Assignment';
    } else {
      dialogTitle = title;
    }

    final customerOrClientName = data['clientName']?.toString()
        ?? data['customerName']?.toString()
        ?? 'N/A';

    DateTime? dateTime;
    if (createdAt != null) {
      try {
        dateTime = DateTime.parse(createdAt).toUtc().toLocal();
      } catch (e) {
        debugPrint('Error parsing date: $e');
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade700, Colors.blue.shade900],
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
                            dialogTitle,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          if (dateTime != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('MMM dd, yyyy • hh:mm a').format(dateTime),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((type == 'trip_assigned' || type == 'client_trip_assigned') && data.isNotEmpty) ...[
                      _buildDetailRow(
                        icon: Icons.confirmation_number,
                        label: 'Trip Number',
                        value: data['tripNumber']?.toString() ?? 'N/A',
                        isHighlight: true,
                      ),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        icon: Icons.directions_car,
                        label: 'Vehicle',
                        value: data['vehicleNumber']?.toString() ?? 'N/A',
                      ),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        icon: Icons.person,
                        label: type == 'client_trip_assigned' ? 'Client' : 'Customer',
                        value: customerOrClientName,
                      ),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        icon: Icons.straighten,
                        label: 'Distance',
                        value: '${data['distance']?.toString() ?? 'N/A'} km',
                      ),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        icon: Icons.access_time,
                        label: 'Pickup Time',
                        value: _formatPickupTime(data['pickupTime']?.toString()),
                      ),
                      const SizedBox(height: 16),
                      _buildDetailRow(
                        icon: Icons.timer,
                        label: 'Estimated Duration',
                        value: '${data['estimatedDuration']?.toString() ?? 'N/A'} minutes',
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.location_on, color: Colors.green.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pickup Location',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    data['pickupAddress']?.toString() ?? 'N/A',
                                    style: TextStyle(fontSize: 13, color: Colors.green.shade800),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.flag, color: Colors.red.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Drop Location',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    data['dropAddress']?.toString() ?? 'N/A',
                                    style: TextStyle(fontSize: 13, color: Colors.red.shade800),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Text(
                        body,
                        style: const TextStyle(fontSize: 15, height: 1.5),
                      ),
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
          if (isTripAssignment && alreadyResponded) ...[
            Container(
              margin: const EdgeInsets.only(right: 8, bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _respondedTrips[tripId] == 'accept'
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _respondedTrips[tripId] == 'accept'
                      ? Colors.green.shade300
                      : Colors.red.shade300,
                ),
              ),
              child: Text(
                _respondedTrips[tripId] == 'accept' ? '✅ Accepted' : '❌ Declined',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _respondedTrips[tripId] == 'accept'
                      ? Colors.green.shade800
                      : Colors.red.shade800,
                ),
              ),
            ),
          ],
          if (isTripAssignment && !alreadyResponded) ...[
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _expandedResponsePanel[notificationId] = true;
                });
              },
              icon: const Icon(Icons.reply),
              label: const Text('Respond to Trip'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

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
            color: isHighlight ? Colors.blue.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isHighlight ? Colors.blue.shade700 : Colors.grey.shade700,
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
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isHighlight ? FontWeight.bold : FontWeight.w500,
                  color: isHighlight ? Colors.blue.shade900 : Colors.grey.shade900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatPickupTime(String? pickupTime) {
    if (pickupTime == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(pickupTime);
      return DateFormat('MMM dd, yyyy • hh:mm a').format(dateTime);
    } catch (e) {
      return pickupTime;
    }
  }

  void _navigateToTripResponse(Map<String, dynamic> data) {
    try {
      final tripId     = data['tripId']?.toString();
      final tripNumber = data['tripNumber']?.toString() ?? 'Unknown';

      if (tripId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip ID not found in notification'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      Navigator.of(context).pushNamed(
        '/driver/trip-response',
        arguments: {
          'tripId': tripId,
          'tripNumber': tripNumber,
          'tripData': data,
        },
      ).then((_) {
        if (mounted) {
          _loadNotifications(silent: true);
        }
      });
    } catch (e) {
      debugPrint('❌ Error navigating to trip response: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open trip response screen'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _navigateToFeedbackScreen() {
    try {
      Navigator.of(context).pushNamed('/driver/feedback');
    } catch (e) {
      debugPrint('❌ Error navigating to feedback screen: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open feedback screen'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _getNotificationIcon(String type, String priority) {
    final iconData = _getIconForType(type);
    final color    = _getColorForPriority(priority);

    return CircleAvatar(
      backgroundColor: color.withOpacity(0.1),
      child: Icon(iconData, size: 20, color: color),
    );
  }

  Color _getPriorityColor(String priority) {
    return _getColorForPriority(priority);
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'trip_assigned':
        return Icons.local_shipping;
      case 'client_trip_assigned':
        return Icons.directions_car;
      case 'client_trip_updated':
        return Icons.update;
      case 'trip_updated':
        return Icons.update;
      case 'trip_cancelled':
        return Icons.cancel;
      case 'trip_started':
        return Icons.play_circle;
      case 'trip_completed':
        return Icons.check_circle;
      case 'route_assigned':
      case 'route_assigned_driver':
      case 'driver_route_assignment':
        return Icons.map;
      case 'route_optimized':
        return Icons.alt_route;
      case 'roster_assigned':
      case 'roster_updated':
        return Icons.calendar_month;
      case 'roster_cancelled':
        return Icons.event_busy;
      case 'vehicle_assigned':
        return Icons.directions_car;
      case 'payment_received':
        return Icons.payments;
      case 'document_expiring_soon':
      case 'document_expired':
        return Icons.description;
      case 'emergency_alert':
        return Icons.emergency;
      case 'admin_alert':
        return Icons.admin_panel_settings;
      case 'feedback_reply':
        return Icons.feedback;
      case 'shift_reminder':
        return Icons.alarm;
      case 'system':
        return Icons.settings;
      case 'driver_response':
        return Icons.check_circle;
      case 'trip_update':
        return Icons.update;
      case 'sos_alert':
        return Icons.warning;
      default:
        return Icons.notifications;
    }
  }

  Color _getColorForPriority(String priority) {
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