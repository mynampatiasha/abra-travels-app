import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// ADDED IMPORTS FOR SOS FUNCTIONALITY
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:intl/intl.dart';

// âœ… IMPORT NOTIFICATION SERVICE
import 'package:abra_fleet/core/services/notification_service.dart';
import 'package:abra_fleet/features/notifications/presentation/screens/customer_notifications_screen.dart';
import 'package:abra_fleet/features/customer/dashboard/data/services/customer_stats_service.dart';
import 'package:abra_fleet/features/tracking/screens/tracking_screen.dart';
import 'package:abra_fleet/core/services/backend_location_tracking_service.dart';

class SOSAlert {
  final String id;
  final String status;
  final DateTime timestamp;
  final String adminNotes;

  SOSAlert({
    required this.id,
    required this.status,
    required this.timestamp,
    this.adminNotes = '',
  });

  factory SOSAlert.fromMap(Map<dynamic, dynamic> map, String id) {
    return SOSAlert(
      id: id,
      status: map['status'] ?? 'Unknown',
      timestamp: DateTime.tryParse(map['timestamp'] ?? '') ?? DateTime.now(),
      adminNotes: map['adminNotes'] ?? '',
    );
  }
}

class CustomerDashboard extends StatefulWidget {
  final VoidCallback onNavigateToMyTrips;
  final VoidCallback onNavigateToProfile;
  final VoidCallback onNavigateToCreateRoster;
  final VoidCallback onNavigateToMyStats;
  final VoidCallback onLogout;

  const CustomerDashboard({
    super.key,
    required this.onNavigateToMyTrips,
    required this.onNavigateToProfile,
    required this.onNavigateToCreateRoster,
    required this.onNavigateToMyStats,
    required this.onLogout,
  });

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  String _userName = 'Customer';
  String? _userId;
  String? _userEmail;
  
  // âœ… ADD THESE THREE LINES:
  SharedPreferences? prefs;
  String? token;

  final CustomerStatsService _statsService = CustomerStatsService();
  bool _statsLoading = true;
  Map<String, dynamic> _quickStats = {};
  StreamSubscription<DatabaseEvent>? _sosStatusSubscription;
  String? _activeSOSId;
  bool _isAcknowledged = false;

  List<SOSAlert> _sosHistory = [];
  bool _sosHistoryLoading = true;
  StreamSubscription<DatabaseEvent>? _sosHistorySubscription;

  // âœ… ADD NOTIFICATION SERVICE
  final NotificationService _notificationService = NotificationService();
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  int _unreadNotificationCount = 0;
  
  // âœ… ADD TRACKING SERVICE
  final BackendLocationTrackingService _trackingService = BackendLocationTrackingService();
  String? _activeTripId;
  bool _loadingTripId = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();  // â† Changed from _loadUserData()
    _loadQuickStats();
    _listenForSOSHistory();
    
    // âœ… INITIALIZE NOTIFICATION LISTENER
    _setupNotificationListener();
    _loadUnreadCount();
    
    // âœ… LOAD ACTIVE TRIP ID
    _loadActiveTripId();
  }

  @override
  void dispose() {
    _sosStatusSubscription?.cancel();
    _sosHistorySubscription?.cancel();
    _notificationSubscription?.cancel();
    super.dispose();
  }

  // âœ… Setup real-time notification listener
  void _setupNotificationListener() {
    debugPrint('ðŸ”” Setting up notification listener in CustomerDashboard');
    
    _notificationSubscription = _notificationService.onNewNotification.listen(
      (notification) {
        debugPrint('ðŸ“¬ NEW NOTIFICATION RECEIVED IN DASHBOARD:');
        debugPrint('   Title: ${notification['title']}');
        debugPrint('   Body: ${notification['body']}');
        debugPrint('   Type: ${notification['type']}');
        debugPrint('   Priority: ${notification['priority']}');
        
        if (mounted) {
          _showNotificationToast(notification);
          _loadUnreadCount();
          
          if (notification['type'] == 'roster_assigned') {
            _showRosterAssignedDialog(notification);
          }
        }
      },
      onError: (error) {
        debugPrint('âŒ Error in notification stream: $error');
      },
    );
  }

  // âœ… Load unread notification count
  Future<void> _loadUnreadCount() async {
    try {
      final count = await _notificationService.getUnreadCount();
      if (mounted) {
        setState(() {
          _unreadNotificationCount = count;
        });
        debugPrint('ðŸ“Š Unread notification count: $count');
      }
    } catch (e) {
      debugPrint('âŒ Error loading unread count: $e');
    }
  }

  // âœ… Show notification toast with navigation
  void _showNotificationToast(Map<String, dynamic> notification) {
    final icon = NotificationService.getNotificationIcon(
      notification['type'] ?? 'system',
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
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification['body'] ?? '',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Color(NotificationService.getNotificationColor(
          notification['priority'] ?? 'normal',
        )),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const CustomerNotificationsScreen(),
              ),
            ).then((_) {
              _loadUnreadCount();
            });
          },
        ),
      ),
    );
  }

  // âœ… Show roster assigned dialog
  void _showRosterAssignedDialog(Map<String, dynamic> notification) {
    final data = notification['data'] as Map<String, dynamic>?;
    
    if (data == null) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[700], size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Roster Assigned!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  notification['body'] ?? '',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                _buildInfoRow('Driver', data['driverName'] ?? 'N/A'),
                if (data['driverPhone'] != null)
                  _buildInfoRow('Phone', data['driverPhone']),
                _buildInfoRow('Vehicle', data['vehicleReg'] ?? 'N/A'),
                if (data['vehicleMake'] != null && data['vehicleModel'] != null)
                  _buildInfoRow('Vehicle Model', '${data['vehicleMake']} ${data['vehicleModel']}'),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                _buildInfoRow('Office', data['officeLocation'] ?? 'N/A'),
                _buildInfoRow('Type', data['rosterType'] ?? 'N/A'),
                if (data['startDate'] != null)
                  _buildInfoRow('Start Date', DateFormat('MMM dd, yyyy').format(DateTime.parse(data['startDate']))),
                if (data['startTime'] != null)
                  _buildInfoRow('Time', '${data['startTime']} - ${data['endTime']}'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
              ),
              child: const Text('View Details'),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onNavigateToMyTrips();
              },
            ),
          ],
        );
      },
    );
  }

// ============================================================================
  // ðŸ†• FUNCTION 8: Show Fallback Emergency Dialog (100/112)
  // ============================================================================
  void _showFallbackEmergencyDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange[700], size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'No Police Station Found',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'We couldn\'t find a nearby police station, but you can call emergency services:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              _buildEmergencyNumberCard('100', 'Police Emergency', Colors.blue),
              const SizedBox(height: 8),
              _buildEmergencyNumberCard('112', 'All Emergency Services', Colors.red),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
          ),
        ],
      );
    },
  );
  }

  Widget _buildEmergencyNumberCard(String number, String label, Color color) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        _initiatePoliceCall(number, label);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.phone, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    number,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                fontSize: 13,
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
  }

  // âœ… ADD THIS NEW METHOD:
  Future<void> _initializeApp() async {
    try {
      prefs = await SharedPreferences.getInstance();
      token = prefs?.getString('jwt_token');
      
      final userDataString = prefs?.getString('user_data');
      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        
        if (mounted) {
          setState(() {
            _userId = userData['id'];
            _userEmail = userData['email'];
            _userName = userData['name'] ??
                       (userData['email']?.split('@')[0]) ??
                       'Customer';
          });
        }
      }
      debugPrint('ðŸ‘¤ User initialized: $_userName ($_userId)');
    } catch (e) {
      debugPrint('âŒ Error initializing app: $e');
    }
  }

  Future<void> _loadQuickStats() async {
    try {
      if (!mounted) return;
      setState(() {
        _statsLoading = true;
      });

      final stats = await _statsService.getAllStats();

      if (mounted) {
        setState(() {
          _quickStats = stats;
          _statsLoading = false;
        });
      }
    } catch (e) {
      debugPrint('âŒ Error loading quick stats: $e');
      if (mounted) {
        setState(() {
          _quickStats = {
            'totalTrips': {'total': 0, 'completed': 0, 'ongoing': 0, 'cancelled': 0},
            'onTimeDelivery': {'onTime': 0, 'delayed': 0},
            'totalDistance': 0.0,
          };
          _statsLoading = false;
        });
      }
    }
  }

  // âœ… NEW: Refresh Dashboard Function
  Future<void> _refreshDashboard() async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Refreshing dashboard...'),
            ],
          ),
          duration: Duration(seconds: 2),
          backgroundColor: Colors.blue,
        ),
      );

      // Refresh all data
      await Future.wait([
        _loadQuickStats(),
        _loadUnreadCount(),
        _loadActiveTripId(),
      ]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Text('Dashboard refreshed successfully!'),
              ],
            ),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('âŒ Error refreshing dashboard: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed to refresh: ${e.toString()}')),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // âœ… LOAD ACTIVE TRIP ID FROM BACKEND
  Future<void> _loadActiveTripId() async {
    if (_loadingTripId || token == null || token!.isEmpty || _userId == null) return;
    
    setState(() {
      _loadingTripId = true;
    });

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/rosters/active-trip/$_userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['hasActiveTrip'] == true && data['trip'] != null) {
          final activeTrip = data['trip'];
          if (mounted) {
            setState(() {
              _activeTripId = activeTrip['tripId'] ?? activeTrip['id'];
            });
          }
          debugPrint('âœ… Loaded active trip ID: $_activeTripId');
        } else {
          if (mounted) {
            setState(() {
              _activeTripId = null;
            });
          }
          debugPrint('â„¹ï¸ No active trips found');
        }
      }
    } catch (e) {
      debugPrint('âŒ Error loading active trip: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingTripId = false;
        });
      }
    }
  }

  Future<void> _showLogoutConfirmationDialog() async {
    final bool? confirmLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirm Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Logout'),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmLogout == true) {
      widget.onLogout();
    }
  }

  void _listenForSOSHistory() {
    if (token == null || token!.isEmpty || _userId == null) return;

    final sosEventsRef = FirebaseDatabase.instance
        .ref('sos_events')
        .orderByChild('customerId')
        .equalTo(_userId);

    _sosHistorySubscription = sosEventsRef.onValue.listen((DatabaseEvent event) {
      if (event.snapshot.exists && mounted) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final List<SOSAlert> history = [];
        data.forEach((key, value) {
          history.add(SOSAlert.fromMap(value, key));
        });
        history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        setState(() {
          _sosHistory = history;
          _sosHistoryLoading = false;
        });
      } else {
        setState(() {
          _sosHistory = [];
          _sosHistoryLoading = false;
        });
      }
    }, onError: (error) {
      debugPrint("âŒ Error listening to SOS history: $error");
      setState(() {
        _sosHistoryLoading = false;
      });
    });
  }

  void _listenForSOSAcknowledgment() {
    if (_activeSOSId == null) return;

    _sosStatusSubscription?.cancel();
    final sosEventRef =
        FirebaseDatabase.instance.ref('sos_events/$_activeSOSId');

    _sosStatusSubscription = sosEventRef.onValue.listen((DatabaseEvent event) {
      if (!event.snapshot.exists || !mounted) return;

      final data = event.snapshot.value as Map<dynamic, dynamic>;
      final currentStatus = data['status'] as String?;
      final adminNotes = data['adminNotes'] as String?;

      final acknowledgedStatuses = ['In Progress', 'Escalated', 'Resolved'];

      if (currentStatus != null &&
          acknowledgedStatuses.contains(currentStatus) &&
          !_isAcknowledged) {
        _showAdminAcknowledgedDialog(currentStatus, adminNotes);

        setState(() {
          _isAcknowledged = true;
        });
      }

      if (currentStatus == 'Resolved') {
        _sosStatusSubscription?.cancel();
        setState(() {
          _activeSOSId = null;
        });
      }
    }, onError: (error) {
      debugPrint("âŒ Error listening to SOS status: $error");
    });
  }

  Future<void> _showAdminAcknowledgedDialog(String status, String? notes) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[700]),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Update on Your SOS',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'An admin has updated your alert status to "$status".',
                  style: const TextStyle(fontSize: 14),
                ),
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Message from Admin:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      notes,
                      style: const TextStyle(
                          fontSize: 13, fontStyle: FontStyle.italic),
                    ),
                  ),
                ]
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  // ðŸ’¬ Show Support Dialog as Overlay
  Future<void> _showSupportDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final isMobile = screenWidth <= 600;
        
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isMobile ? screenWidth * 0.9 : 500,
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: EdgeInsets.all(isMobile ? 20 : 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).primaryColor,
                        Theme.of(context).primaryColor.withOpacity(0.8),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.headset_mic,
                          color: Colors.white,
                          size: isMobile ? 28 : 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'We\'re Here to Help!',
                              style: TextStyle(
                                fontSize: isMobile ? 18 : 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Choose your preferred way to reach us',
                              style: TextStyle(
                                fontSize: isMobile ? 12 : 13,
                                color: Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isMobile ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Support Hours
                        Container(
                          padding: EdgeInsets.all(isMobile ? 14 : 16),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.access_time_rounded, color: Colors.blue[700], size: 24),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Available 24/7',
                                      style: TextStyle(
                                        fontSize: isMobile ? 14 : 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                    Text(
                                      'All Days â€¢ Round the Clock',
                                      style: TextStyle(
                                        fontSize: isMobile ? 11 : 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        // Contact Options
                        Text(
                          'Contact Us',
                          style: TextStyle(
                            fontSize: isMobile ? 15 : 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Phone
                        _buildSupportOptionCard(
                          context,
                          icon: Icons.phone,
                          title: 'Call Us',
                          subtitle: '+91 886-728-8076',
                          color: const Color(0xFF4299E1),
                          onTap: () => _launchPhoneCall(context),
                          onCopy: () => _copyToClipboard(context, '+918867288076', 'Phone number'),
                          isMobile: isMobile,
                        ),
                        const SizedBox(height: 10),
                        
                        // WhatsApp
                        _buildSupportOptionCard(
                          context,
                          icon: Icons.chat_bubble,
                          title: 'WhatsApp',
                          subtitle: 'Chat with us instantly',
                          color: const Color(0xFF48BB78),
                          onTap: () => _launchWhatsApp(context),
                          isMobile: isMobile,
                        ),
                        const SizedBox(height: 10),
                        
                        // Email
                        _buildSupportOptionCard(
                          context,
                          icon: Icons.email,
                          title: 'Email Us',
                          subtitle: 'hostelmatrix19@gmail.com',
                          color: const Color(0xFFED8936),
                          onTap: () => _launchEmail(context),
                          onCopy: () => _copyToClipboard(context, 'hostelmatrix19@gmail.com', 'Email address'),
                          isMobile: isMobile,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSupportOptionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    VoidCallback? onCopy,
    required bool isMobile,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: isMobile ? 14 : 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: isMobile ? 11 : 12,
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onCopy != null)
                IconButton(
                  icon: Icon(Icons.copy, color: Colors.grey[600], size: 18),
                  onPressed: onCopy,
                  tooltip: 'Copy',
                ),
              Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ðŸ“ž Launch Phone Call
  Future<void> _launchPhoneCall(BuildContext context) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: '+918867288076');
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (mounted) {
          _showErrorSnackBar(context, 'Unable to open phone dialer');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(context, 'Error: $e');
      }
    }
  }

  // ðŸ’¬ Launch WhatsApp
  Future<void> _launchWhatsApp(BuildContext context) async {
    final Uri whatsappUri = Uri.parse('https://wa.me/918867288076');
    try {
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          _showErrorSnackBar(context, 'Unable to open WhatsApp');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(context, 'Error: $e');
      }
    }
  }

  // ðŸ“§ Launch Email - WEB & MOBILE OPTIMIZED
  Future<void> _launchEmail(BuildContext context) async {
    final String email = 'hostelmatrix19@gmail.com';
    final String subject = 'Support Request';
    final String body = 'Hello Abra Travels Support Team,\n\n';
    
    try {
      final Uri emailUri = Uri(
        scheme: 'mailto',
        path: email,
        query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
      );
      
      if (kIsWeb) {
        // For WEB: Use platformDefault mode which respects user gesture
        await launchUrl(emailUri, mode: LaunchMode.platformDefault);
      } else {
        // For MOBILE/DESKTOP: Use external application
        if (await canLaunchUrl(emailUri)) {
          await launchUrl(emailUri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not launch email';
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(
          context,
          'Unable to open email client. Email copied to clipboard.',
        );
        _copyToClipboard(context, email, 'Email address');
      }
    }
  }

  // ðŸ“‹ Copy to Clipboard
  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Text('$label copied to clipboard!'),
          ],
        ),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
  
  Future<void> _showSOSConfirmationDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Confirm SOS Alert',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  'This will send an immediate emergency alert with your current location to our support team.',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 16),
                Text(
                  'Are you sure you need help?',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('CONFIRM SOS'),
              onPressed: () {
                Navigator.of(context).pop();
                _triggerSOS();
              },
            ),
          ],
        );
      },
    );
  }

  // ============================================================================
  // ðŸ†• NEW FUNCTION 1: Check if customer has an active trip
  // ============================================================================
  Future<Map<String, dynamic>?> _checkActiveTrip() async {
    try {
      if (token == null || token!.isEmpty || _userId == null) return null;

      debugPrint('ðŸ” Checking for active trip for user: $_userId');

      final url = Uri.parse('${ApiConfig.baseUrl}/api/rosters/active-trip/$_userId');
      
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['hasActiveTrip'] == true && data['trip'] != null) {
          debugPrint('âœ… Active trip found');
          return data['trip'] as Map<String, dynamic>;
        } else {
          debugPrint('âŒ No active trip found');
          return null;
        }
      }
      return null;
    } catch (e) {
      debugPrint('âŒ Error checking active trip: $e');
      return null;
    }
  }

  // ============================================================================
  // ðŸ†• NEW FUNCTION 2: Fetch complete trip details
  // ============================================================================
  Future<Map<String, dynamic>?> _fetchTripDetails(String tripId) async {
    try {
      debugPrint('ðŸ“¥ Fetching trip details for: $tripId');

      final url = Uri.parse('${ApiConfig.baseUrl}/api/rosters/trip-details/$tripId');
      
      final response = await http.get(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('âœ… Trip details fetched successfully');
        return data['tripDetails'] as Map<String, dynamic>;
      } else {
        debugPrint('âš ï¸ Failed to fetch trip details: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('âŒ Error fetching trip details: $e');
      return null;
    }
  }

  // ============================================================================
  // ðŸ”„ MODIFIED: Enhanced SOS Trigger with Trip Validation
  // ============================================================================
  Future<void> _triggerSOS() async {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Checking trip status...')),
    );

    try {
      if (token == null || token!.isEmpty || _userId == null) {
        throw Exception('User is not logged in.');
      }

      final activeTripData = await _checkActiveTrip();
      
      if (activeTripData == null) {
        if (mounted) {
          _showNoActiveTripError();
        }
        return;
      }

      debugPrint('âœ… Active trip validated. Proceeding with SOS...');

      String customerName = _userName;
      String customerEmail = _userEmail ?? '';
      String customerPhone = '';

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Getting your location...')),
      );

      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      final sosPayload = {
        'customerId': _userId,
        'customerName': customerName,
        'customerEmail': customerEmail,
        'customerPhone': customerPhone,
        
        'tripId': activeTripData['tripId'] ?? activeTripData['_id'] ?? 'unknown',
        'rosterId': activeTripData['rosterId'] ?? activeTripData['_id'] ?? 'unknown',
        
        'driverId': activeTripData['driverId'] ?? 'unknown',
        'driverName': activeTripData['driverName'] ?? 'N/A',
        'driverPhone': activeTripData['driverPhone'] ?? 'N/A',
        
        'vehicleReg': activeTripData['vehicleReg'] ?? 'N/A',
        'vehicleMake': activeTripData['vehicleMake'] ?? 'N/A',
        'vehicleModel': activeTripData['vehicleModel'] ?? 'N/A',
        
        'pickupLocation': activeTripData['pickupLocation'] ?? 'N/A',
        'dropLocation': activeTripData['dropLocation'] ?? 'N/A',
        
        'gps': {
          'latitude': position.latitude,
          'longitude': position.longitude,
        },
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'status': 'ACTIVE',
        'adminNotes': '',
      };

      debugPrint('ðŸ“¤ Sending SOS payload to backend...');

      final url = Uri.parse('${ApiConfig.baseUrl}/api/sos');

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sending SOS alert...')),
      );
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(sosPayload),
      );

      if (response.statusCode == 201) {
        final responseBody = json.decode(response.body);
        final String newSosId = responseBody['eventId'];
        final bool policeNotified = responseBody['policeNotified'] ?? false;
        final String policeEmail = responseBody['policeEmail'] ?? 'none';
        final List<dynamic> nearbyPoliceStations = responseBody['nearbyPoliceStations'] ?? [];

        if (mounted) {
          setState(() {
            _activeSOSId = newSosId;
            _isAcknowledged = false;
          });

          _listenForSOSAcknowledgment();
          _showSOSSuccessDialog(policeNotified, policeEmail, activeTripData, nearbyPoliceStations);
          
          if (nearbyPoliceStations.isNotEmpty) {
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) {
                _showNearbyPoliceStations(nearbyPoliceStations, position);
              }
            });
          }
        }
      } else {
        throw Exception('Failed to send SOS. Server Error: ${response.body}');
      }
    } catch (e) {
      debugPrint('âŒ Error triggering SOS: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error triggering SOS: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============================================================================
// ðŸ†• FUNCTION 5: Find Nearest Police Station (OpenStreetMap - FREE)
// ============================================================================
Future<Map<String, String>?> _findNearestPoliceStation(double lat, double lon) async {
  try {
    debugPrint('ðŸ” Searching for police stations near: $lat, $lon');

    // OpenStreetMap Nominatim API (FREE - No API Key Required)
    final radius = 5000; // Search within 5km radius
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?'
      'q=police+station&'
      'format=json&'
      'lat=$lat&'
      'lon=$lon&'
      'limit=5&'
      'addressdetails=1'
    );

    final response = await http.get(
      url,
      headers: {
        'User-Agent': 'AbraTravels/1.0', // Required by Nominatim
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> results = json.decode(response.body);
      
      if (results.isEmpty) {
        debugPrint('âŒ No police stations found nearby');
        return null;
      }

      // Get the closest police station
      final closestStation = results[0];
      final stationName = closestStation['display_name'] ?? 'Local Police Station';
      final stationLat = double.tryParse(closestStation['lat'] ?? '0') ?? 0;
      final stationLon = double.tryParse(closestStation['lon'] ?? '0') ?? 0;

      // Try to find phone number from OpenStreetMap data
      // Note: Phone numbers are not always available in OSM
      String? phoneNumber;
      
      // Check if address details contain phone
      if (closestStation['address'] != null) {
        final address = closestStation['address'] as Map<String, dynamic>;
        phoneNumber = address['phone'] as String?;
      }

      debugPrint('âœ… Found police station: $stationName');
      debugPrint('ðŸ“ Location: $stationLat, $stationLon');
      
      return {
        'name': stationName,
        'phone': phoneNumber ?? '100', // Fallback to 100 if no phone found
        'latitude': stationLat.toString(),
        'longitude': stationLon.toString(),
        'address': stationName,
      };
    } else {
      debugPrint('âš ï¸ OpenStreetMap API error: ${response.statusCode}');
      return null;
    }
  } catch (e) {
    debugPrint('âŒ Error finding police station: $e');
    return null;
  }
}

// ============================================================================
// ðŸ†• FUNCTION 6: Show Police Call Confirmation Dialog
// ============================================================================
Future<void> _showPoliceCallConfirmation(
  Map<String, String> policeStation,
  Position currentLocation,
) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      final phoneNumber = policeStation['phone'] ?? '100';
      final stationName = policeStation['name'] ?? 'Local Police Station';
      
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.local_police, color: Colors.blue, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Call Police Station?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_city, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            stationName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.phone, size: 16, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          phoneNumber,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'ðŸ“ž We will automatically call this police station for emergency assistance.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange[700], size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Your location will be shared with police',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            icon: const Icon(Icons.phone, size: 20),
            label: const Text('Call Now'),
            onPressed: () {
              Navigator.of(context).pop();
              _initiatePoliceCall(phoneNumber, stationName);
            },
          ),
        ],
      );
    },
  );
}

// ============================================================================
// ðŸ†• FUNCTION 7: Initiate Phone Call to Police
// ============================================================================
Future<void> _initiatePoliceCall(String phoneNumber, String stationName) async {
  try {
    debugPrint('ðŸ“ž Initiating call to police: $phoneNumber');
    
    // Remove any spaces, dashes, or formatting from phone number
    final cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    
    final Uri phoneUri = Uri(scheme: 'tel', path: cleanNumber);
    
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.phone, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Calling $stationName...'),
                ),
              ],
            ),
            backgroundColor: Colors.green[700],
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      throw 'Could not launch phone dialer';
    }
  } catch (e) {
    debugPrint('âŒ Error initiating call: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Unable to make call. Please dial $phoneNumber manually.'),
              ),
            ],
          ),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Copy',
            textColor: Colors.white,
            onPressed: () {
              _copyToClipboard(context, phoneNumber, 'Phone number');
            },
          ),
        ),
      );
    }
  }
}
  // ============================================================================
  // ðŸ†• NEW FUNCTION 8: Show Nearby Police Stations from Backend Response
  // ============================================================================
  void _showNearbyPoliceStations(List<dynamic> policeStations, Position currentLocation) {
    if (policeStations.isEmpty) {
      _showFallbackEmergencyDialog();
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.local_police, color: Colors.blue, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Nearby Police Stations',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Select a police station to call for immediate assistance:',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: policeStations.length,
                    itemBuilder: (context, index) {
                      final station = policeStations[index];
                      final name = station['name'] ?? 'Police Station';
                      final phone = station['phone'] ?? '100';
                      final distance = station['distance']?.toStringAsFixed(1) ?? '0.0';
                      final address = station['address'] ?? 'Address not available';
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.withOpacity(0.1),
                            child: const Icon(Icons.local_police, color: Colors.blue, size: 20),
                          ),
                          title: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.phone, size: 14, color: Colors.green),
                                  const SizedBox(width: 4),
                                  Text(
                                    phone,
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(Icons.location_on, size: 14, color: Colors.orange),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${distance}km away',
                                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: const Size(80, 36),
                            ),
                            icon: const Icon(Icons.phone, size: 16),
                            label: const Text('Call', style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              Navigator.of(context).pop();
                              _initiatePoliceCall(phone, name);
                            },
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            _initiatePoliceCall(phone, name);
                          },
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange[700], size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Emergency services have been notified. You can also call these local stations directly.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.phone, size: 16),
              label: const Text('Emergency 100'),
              onPressed: () {
                Navigator.of(context).pop();
                _initiatePoliceCall('100', 'Emergency Services');
              },
            ),
          ],
        );
      },
    );
  }

  // ============================================================================
  // ðŸ†• NEW FUNCTION 3: Show "No Active Trip" Error Dialog
  // ============================================================================
  void _showNoActiveTripError() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.block, color: Colors.orange[700], size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'SOS Unavailable',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'âš ï¸ SOS Alert can only be triggered during an active trip.',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                const Text(
                  'You currently don\'t have any ongoing trips.',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.emergency, color: Colors.red[700], size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'For emergencies, please call:\n112 (Emergency Services)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
              ),
              child: const Text('View My Trips'),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onNavigateToMyTrips();
              },
            ),
          ],
        );
      },
    );
  }

  // ============================================================================
  // ðŸ†• NEW FUNCTION 4: Show Enhanced Success Dialog
  // ============================================================================
  void _showSOSSuccessDialog(bool policeNotified, String policeEmail, Map<String, dynamic> tripData, List<dynamic> nearbyPoliceStations) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green[700], size: 28),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'SOS Alert Sent!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'âœ… Your emergency alert has been sent successfully.',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                _buildSuccessInfoRow('Police', policeNotified ? 'Notified âœ“' : 'Admin notified', 
                    policeNotified ? Colors.green : Colors.orange),
                if (policeNotified && policeEmail != 'none')
                  _buildSuccessInfoRow('Email', policeEmail, Colors.grey),
                _buildSuccessInfoRow('Support Team', 'Alerted âœ“', Colors.green),
                _buildSuccessInfoRow('Driver', '${tripData['driverName']} informed', Colors.blue),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer, color: Colors.green[700], size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Help is on the way. Stay safe!\nEstimated response: 5-10 minutes',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildSuccessInfoRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;

    final isDesktop = screenWidth > 1200;
    final isTablet = screenWidth > 800 && screenWidth <= 1200;
    final isMobile = screenWidth <= 800;
    final isSmallMobile = screenWidth <= 360;

    final horizontalPadding = isDesktop ? 32.0 : (isTablet ? 24.0 : (isMobile ? 16.0 : 12.0));
    final verticalPadding = isDesktop ? 32.0 : (isTablet ? 24.0 : 16.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildResponsiveAppBar(context, isMobile, isSmallMobile),
      floatingActionButton: _buildResponsiveFloatingActionButton(isMobile, isSmallMobile),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildResponsiveHeader(context, _userName, screenWidth, isMobile, isSmallMobile),
            SizedBox(height: isMobile ? 16 : isTablet ? 24 : 32),
            _buildQuickStatsOverview(context, isDesktop, isMobile),
            const SizedBox(height: 16),
            _buildTrackingCard(context, isMobile),
            const SizedBox(height: 16),
            _buildResponsiveSOSHistorySection(isMobile, isSmallMobile),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildResponsiveAppBar(BuildContext context, bool isMobile, bool isSmallMobile) {
    return AppBar(
      backgroundColor: Theme.of(context).primaryColor,
      elevation: 2,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          // ðŸŽ¯ Brand Logo/Icon
          Container(
            width: isMobile ? 40 : 44,
            height: isMobile ? 40 : 44,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.asset(
              'assets/logo.png',
              fit: BoxFit.contain,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          // ðŸ“± App Title
          Expanded(
            child: Text(
              'Abra Travels',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isSmallMobile ? 16 : isMobile ? 18 : 20,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
      actions: [
        // ðŸ”„ Refresh Button
        IconButton(
          icon: Icon(
            Icons.refresh,
            color: Colors.white,
            size: isMobile ? 24 : 26,
          ),
          onPressed: _refreshDashboard,
          tooltip: 'Refresh Dashboard',
        ),
        // ðŸ”” Notifications with Badge
        Stack(
          children: [
            IconButton(
              icon: Icon(
                Icons.notifications_outlined,
                color: Colors.white,
                size: isMobile ? 24 : 26,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const CustomerNotificationsScreen(),
                  ),
                ).then((_) {
                  _loadUnreadCount();
                });
              },
              tooltip: 'Notifications',
            ),
            if (_unreadNotificationCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    _unreadNotificationCount > 99 ? '99+' : _unreadNotificationCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
        // ðŸ’¬ Support
        if (!isSmallMobile)
          IconButton(
            icon: Icon(Icons.headset_mic_outlined, color: Colors.white, size: isMobile ? 24 : 26),
            onPressed: () => _showSupportDialog(context),
            tooltip: 'Support',
          ),
        // ðŸšª Logout
        IconButton(
          icon: Icon(
            Icons.logout_rounded,
            color: Colors.white,
            size: isMobile ? 24 : 26,
          ),
          onPressed: _showLogoutConfirmationDialog,
          tooltip: 'Logout',
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildResponsiveFloatingActionButton(bool isMobile, bool isSmallMobile) {
    if (isSmallMobile) {
      return FloatingActionButton(
        onPressed: _showSOSConfirmationDialog,
        backgroundColor: Colors.red[600],
        child: const Text(
          'SOS',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      );
    }
    
    return FloatingActionButton.extended(
      onPressed: _showSOSConfirmationDialog,
      backgroundColor: Colors.red[600],
      label: Text(
        'SOS',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: isMobile ? 14 : 16,
        ),
      ),
      icon: const Icon(Icons.emergency, color: Colors.white, size: 22),
      tooltip: 'Send Emergency Alert',
    );
  }

  Widget _buildResponsiveHeader(BuildContext context, String userName, double screenWidth, bool isMobile, bool isSmallMobile) {
    final now = DateTime.now();
    final hour = now.hour;
    String greeting = hour < 12 ? 'Good Morning' : hour < 17 ? 'Good Afternoon' : 'Good Evening';

    final titleFontSize = isSmallMobile ? 18.0 : isMobile ? 20.0 : screenWidth > 1200 ? 28.0 : 24.0;
    final subtitleFontSize = isSmallMobile ? 12.0 : isMobile ? 13.0 : screenWidth > 1200 ? 16.0 : 14.0;
    final padding = isSmallMobile ? 16.0 : isMobile ? 20.0 : screenWidth > 1200 ? 32.0 : 24.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).primaryColor,
            Theme.of(context).primaryColor.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).primaryColor.withOpacity(0.3),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, $userName! ðŸ‘‹',
                  style: TextStyle(
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Track, manage, and optimize your fleet',
                  style: TextStyle(
                    fontSize: subtitleFontSize,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(width: 24),
            Container(
              width: screenWidth > 1200 ? 100 : 80,
              height: screenWidth > 1200 ? 100 : 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.dashboard_rounded,
                color: Colors.white,
                size: screenWidth > 1200 ? 50 : 40,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickStatsOverview(BuildContext context, bool isDesktop, bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4F46E5),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4F46E5).withOpacity(0.3),
                          spreadRadius: 0,
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.analytics,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Quick Stats',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          _statsLoading
              ? Container(
                  height: 100,
                  child: const Center(child: CircularProgressIndicator()),
                )
              : Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildQuickStatItem(
                            'Total Trips',
                            _getQuickStatValue('totalTrips'),
                            Icons.local_shipping,
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildQuickStatItem(
                            'Distance Covered',
                            _getDistanceValue(),
                            Icons.straighten,
                            Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // âœ… VIEW DETAILS BUTTON
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onNavigateToMyStats,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            vertical: isMobile ? 14 : 16,
                            horizontal: 24,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.bar_chart_rounded, size: 20),
                        label: Text(
                          'View Detailed Statistics',
                          style: TextStyle(
                            fontSize: isMobile ? 14 : 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildTrackingCard(BuildContext context, bool isMobile) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.blue.shade100],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
