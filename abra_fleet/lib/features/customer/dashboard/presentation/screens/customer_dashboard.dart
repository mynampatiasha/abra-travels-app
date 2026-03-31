import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// ADDED IMPORTS FOR SOS FUNCTIONALITY
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:intl/intl.dart';

// ✅ IMPORT NOTIFICATION SERVICE
import 'package:abra_fleet/core/services/notification_service.dart';
import 'package:abra_fleet/features/notifications/presentation/screens/customer_notifications_screen.dart';
import 'package:abra_fleet/features/customer/dashboard/data/services/customer_stats_service.dart';
import 'package:abra_fleet/features/tracking/screens/tracking_screen.dart';
import 'package:abra_fleet/core/services/backend_location_tracking_service.dart';
// ✅ IMPORT ENHANCED TRACKING SCREEN (Routematic-style)
import 'package:abra_fleet/features/customer/dashboard/presentation/screens/enhanced_tracking_screen.dart';
// ✅ NEW: Import My Trips Service
import 'package:abra_fleet/core/services/my_trips_service.dart';
// ✅ IMPORT SAFE API SERVICE
import 'package:abra_fleet/core/services/safe_api_service.dart';

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
  
  SharedPreferences? prefs;
  String? token;

  final CustomerStatsService _statsService = CustomerStatsService();
  // ✅ NEW: Add My Trips Service
  final MyTripsService _tripsService = MyTripsService();
  
  bool _statsLoading = true;
  Map<String, dynamic> _quickStats = {};
  StreamSubscription? _sosStatusSubscription;
  String? _activeSOSId;
  bool _isAcknowledged = false;

  List<SOSAlert> _sosHistory = [];
  bool _sosHistoryLoading = true;
  StreamSubscription? _sosHistorySubscription;

  final NotificationService _notificationService = NotificationService();
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  int _unreadNotificationCount = 0;
  
  final BackendLocationTrackingService _trackingService = BackendLocationTrackingService();
  String? _activeTripId;
  bool _loadingTripId = false;
  
  // ✅ NEW: Add variable to store active trip data
  Map<String, dynamic>? _activeTripData;
  
  // Add missing SOS trigger variables
  bool _isSOSTriggerLoading = false;
  String? _activeSosEventId;
  Timer? _resolutionPoller;
  bool _isPollingForResolution = false;
  final SafeApiService _safeApi = SafeApiService();

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _loadQuickStats();
    _listenForSOSHistory();
    
    _setupNotificationListener();
    _loadUnreadCount();
    
    // ✅ UPDATED: Load active trip from My Trips data
    _loadActiveTripFromMyTrips();
  }

  @override
  void dispose() {
    _sosStatusSubscription?.cancel();
    _sosHistorySubscription?.cancel();
    _notificationSubscription?.cancel();
    super.dispose();
  }

  void _setupNotificationListener() {
    debugPrint('🔔 Setting up notification listener in CustomerDashboard');
    
    _notificationSubscription = _notificationService.onNewNotification.listen(
      (notification) {
        debugPrint('📬 NEW NOTIFICATION RECEIVED IN DASHBOARD:');
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
        debugPrint('❌ Error in notification stream: $error');
      },
    );
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await _notificationService.getUnreadCount();
      if (mounted) {
        setState(() {
          _unreadNotificationCount = count;
        });
        debugPrint('📊 Unread notification count: $count');
      }
    } catch (e) {
      debugPrint('❌ Error loading unread count: $e');
    }
  }

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
      debugPrint('👤 User initialized: $_userName ($_userId)');
    } catch (e) {
      debugPrint('❌ Error initializing app: $e');
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
      debugPrint('❌ Error loading quick stats: $e');
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

  Future<void> _refreshDashboard() async {
    try {
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

      await Future.wait([
        _loadQuickStats(),
        _loadUnreadCount(),
        _loadActiveTripFromMyTrips(),
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
      debugPrint('❌ Error refreshing dashboard: $e');
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

  // ============================================================================
  // ✅ FIX #2 & #3: Load Active Trip from My Trips Data
  // ============================================================================
  Future<void> _loadActiveTripFromMyTrips() async {
    if (_loadingTripId || token == null || token!.isEmpty) return;
    
    setState(() {
      _loadingTripId = true;
      _activeTripId = null;
      _activeTripData = null;
    });

    try {
      debugPrint('🔍 Loading active trip from My Trips data...');
      
      // Get today's date in YYYY-MM-DD format
      final today = DateTime.now();
      final todayString = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      
      debugPrint('   Today: $todayString');
      
      // Call the My Trips Service to get today's trips
      final result = await _tripsService.getDailyTrips(
        startDate: todayString,
        endDate: todayString,
      );
      
      if (result['success'] == true) {
        final List<dynamic> trips = result['data'] ?? [];
        debugPrint('   Found ${trips.length} trip(s) for today');
        
        // Find ongoing trip (status: 'ongoing' or 'in_progress')
        final activeTrip = trips.firstWhere(
          (trip) {
            final status = (trip['status'] ?? '').toString().toLowerCase();
            debugPrint('   Trip status: $status');
            return status == 'ongoing' || status == 'in_progress' || status == 'started';
          },
          orElse: () => null,
        );
        
        if (activeTrip != null) {
          if (mounted) {
            setState(() {
              _activeTripId = activeTrip['tripId'] ?? activeTrip['_id'];
              _activeTripData = Map<String, dynamic>.from(activeTrip);
            });
          }
          debugPrint('✅ Active trip found: $_activeTripId');
          debugPrint('   Driver: ${activeTrip['driverName']}');
          debugPrint('   Vehicle: ${activeTrip['vehicleNumber']}');
        } else {
          debugPrint('ℹ️ No active trips found for today');
          if (mounted) {
            setState(() {
              _activeTripId = null;
              _activeTripData = null;
            });
          }
        }
      } else {
        debugPrint('⚠️ Failed to fetch trips: ${result['message']}');
      }
    } catch (e) {
      debugPrint('❌ Error loading active trip: $e');
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

  void _listenForSOSHistory() async {
    if (token == null || token!.isEmpty || _userId == null) return;

    await _fetchSOSHistory();

    _sosHistorySubscription = Stream.periodic(const Duration(seconds: 10))
        .asyncMap((_) => _fetchSOSHistory())
        .listen((_) {}, onError: (error) {
      debugPrint("❌ Error in SOS history stream: $error");
    });
  }

  // ============================================================================
  // ✅ FIX #4: Fetch Only RESOLVED SOS History for THIS Customer
  // ============================================================================
  Future<void> _fetchSOSHistory() async {
    if (!mounted || token == null || _userId == null) {
      debugPrint('❌ Cannot fetch SOS history: Missing required parameters');
      return;
    }

    try {
      debugPrint('🔍 Fetching RESOLVED SOS history for customer: $_userId');
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/sos?status=Resolved&limit=100'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('📊 SOS history response status: ${data['status']}');
        
        final List<SOSAlert> history = [];
        
        final List<dynamic> sosData = data['data'] is List ? data['data'] : [];
        
        debugPrint('📋 Total SOS events received: ${sosData.length}');
        
        for (var alert in sosData) {
          try {
            final alertStatus = (alert['status']?.toString() ?? 'Unknown').toLowerCase();
            final alertCustomerId = alert['customerId']?.toString() ?? '';
            
            if (alertStatus == 'resolved' && alertCustomerId == _userId) {
              history.add(SOSAlert(
                id: alert['_id']?.toString() ?? alert['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
                status: 'Resolved',
                timestamp: DateTime.tryParse(alert['timestamp']?.toString() ?? alert['createdAt']?.toString() ?? '') ?? DateTime.now(),
                adminNotes: alert['adminNotes']?.toString() ?? '',
              ));
            }
          } catch (e) {
            debugPrint('⚠️ Error parsing SOS alert: $e');
          }
        }
        
        debugPrint('✅ Filtered to ${history.length} RESOLVED SOS alerts for customer $_userId');
        
        history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        
        if (mounted) {
          setState(() {
            _sosHistory = history;
            _sosHistoryLoading = false;
          });
          debugPrint('✅ Loaded ${_sosHistory.length} resolved SOS history items');
        }
      } else {
        debugPrint('❌ Failed to fetch SOS history: ${response.statusCode} - ${response.body}');
        if (mounted) {
          setState(() {
            _sosHistory = [];
            _sosHistoryLoading = false;
          });
        }
      }
    } catch (error, stackTrace) {
      debugPrint('❌ Error in _fetchSOSHistory:');
      debugPrint('   Error: $error');
      debugPrint('   Stack trace: $stackTrace');
      
      if (mounted) {
        setState(() {
          _sosHistory = [];
          _sosHistoryLoading = false;
        });
      }
    }
  }

  void _listenForSOSAcknowledgment() async {
    if (_activeSOSId == null) return;

    Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!mounted || _activeSOSId == null) {
        timer.cancel();
        return;
      }

      try {
        final response = await http.get(
          Uri.parse('${ApiConfig.baseUrl}/api/sos/$_activeSOSId'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200 && mounted) {
          final data = json.decode(response.body);
          final currentStatus = data['status'] as String?;
          final adminNotes = data['adminNotes'] as String?;

          final acknowledgedStatuses = ['In Progress', 'Escalated', 'Resolved'];

          if (currentStatus != null &&
              acknowledgedStatuses.contains(currentStatus) &&
              !_isAcknowledged) {
            _showAdminAcknowledgedDialog(currentStatus, adminNotes);
            timer.cancel();
            
            setState(() {
              _isAcknowledged = true;
            });
          }

          if (currentStatus == 'Resolved') {
            timer.cancel();
            setState(() {
              _activeSOSId = null;
            });
          }
        }
      } catch (error) {
        debugPrint("❌ Error checking SOS status: $error");
      }
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
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isMobile ? 16 : 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                                      'All Days • Round the Clock',
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
                        
                        Text(
                          'Contact Us',
                          style: TextStyle(
                            fontSize: isMobile ? 15 : 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 12),
                        
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
                        
                        _buildSupportOptionCard(
                          context,
                          icon: Icons.email,
                          title: 'Email Us',
                          subtitle: 'support@fleet.abra-travels.com',
                          color: const Color(0xFFED8936),
                          onTap: () => _launchEmail(context),
                          onCopy: () => _copyToClipboard(context, 'support@fleet.abra-travels.com', 'Email address'),
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

  Future<void> _launchPhoneCall(BuildContext context) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: '+918867288076');
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        if (mounted) {
          _showErrorSnackbar('Unable to open phone dialer');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Error: $e');
      }
    }
  }

  Future<void> _launchWhatsApp(BuildContext context) async {
    final Uri whatsappUri = Uri.parse('https://wa.me/918867288076');
    try {
      if (await canLaunchUrl(whatsappUri)) {
        await launchUrl(whatsappUri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          _showErrorSnackbar('Unable to open WhatsApp');
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Error: $e');
      }
    }
  }

  Future<void> _launchEmail(BuildContext context) async {
    final String email = 'support@fleet.abra-travels.com';
    final String subject = 'Support Request';
    final String body = 'Hello Abra Travels Support Team,\n\n';
    
    try {
      final Uri emailUri = Uri(
        scheme: 'mailto',
        path: email,
        query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
      );
      
      if (kIsWeb) {
        await launchUrl(emailUri, mode: LaunchMode.platformDefault);
      } else {
        if (await canLaunchUrl(emailUri)) {
          await launchUrl(emailUri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not launch email';
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar(
          'Unable to open email client. Email copied to clipboard.',
        );
        _copyToClipboard(context, email, 'Email address');
      }
    }
  }

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

  void _showErrorSnackbar(String message) {
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
  // ✅ FIX #3: Check Active Trip Using My Trips Data
  // ============================================================================
  Future<Map<String, dynamic>?> _checkActiveTrip() async {
    try {
      if (token == null || token!.isEmpty || _userId == null) return null;

      debugPrint('🔍 Checking for active trip using My Trips data...');

      if (_activeTripData != null) {
        debugPrint('✅ Active trip found (from cached data)');
        return _activeTripData;
      }

      await _loadActiveTripFromMyTrips();
      
      if (_activeTripData != null) {
        debugPrint('✅ Active trip found (from fresh API call)');
        return _activeTripData;
      } else {
        debugPrint('❌ No active trip found');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error checking active trip: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchTripDetails(String tripId) async {
    try {
      debugPrint('📥 Fetching trip details for: $tripId');

      final url = Uri.parse('${ApiConfig.baseUrl}/api/rosters/trip-details/$tripId');
      
      final response = await http.get(
        url,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('✅ Trip details fetched successfully');
        return data['tripDetails'] as Map<String, dynamic>;
      } else {
        debugPrint('⚠️ Failed to fetch trip details: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error fetching trip details: $e');
      return null;
    }
  }

 Future<void> _triggerSOS() async {
  if (_isSOSTriggerLoading) return;
  setState(() => _isSOSTriggerLoading = true);

  try {
    // ── Check for active trip ────────────────────────────────────────────
    final tripsResponse =
        await MyTripsService().getDailyTrips();
    Map<String, dynamic>? activeTrip;
    if (tripsResponse['success'] == true && tripsResponse['data'] != null) {
      final trips = tripsResponse['data'] as List;
      activeTrip = trips.firstWhere(
        (t) =>
            t['status']?.toString().toLowerCase() == 'active' ||
            t['status']?.toString().toLowerCase() == 'in progress',
        orElse: () => null,
      );
    }

    // ── Get GPS ──────────────────────────────────────────────────────────
    double? latitude, longitude;
    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      latitude = pos.latitude;
      longitude = pos.longitude;
    } catch (_) {}

    // ── Build payload ────────────────────────────────────────────────────
    final payload = {
      'customerId': _userId,
      'customerName': _userName ?? 'Customer',
      'email': _userEmail ?? '',
      'phone': '',
      'tripId': activeTrip?['_id']?.toString(),
      'driverId': activeTrip?['driverId']?.toString(),
      'driverName': activeTrip?['driverName']?.toString(),
      'driverPhone': activeTrip?['driverPhone']?.toString(),
      'vehicleReg': activeTrip?['vehicleReg']?.toString(),
      'vehicleMake': activeTrip?['vehicleMake']?.toString(),
      'vehicleModel': activeTrip?['vehicleModel']?.toString(),
      'pickupLocation': activeTrip?['pickupLocation']?.toString(),
      'dropLocation': activeTrip?['dropLocation']?.toString(),
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      'liveTrackingUrl': activeTrip?['liveTrackingUrl']?.toString(),
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    // ── POST to backend ──────────────────────────────────────────────────
    final response = await _safeApi.safePost(
      '/api/sos',
      body: payload,
      context: 'SOS Trigger',
    );

    setState(() => _isSOSTriggerLoading = false);

    if (!mounted) return;

    if (response['status'] == 'success' || response['eventId'] != null) {
      // ✅ Store the eventId so we can poll for resolution
      final eventId = response['eventId']?.toString();
      if (eventId != null) {
        setState(() => _activeSosEventId = eventId);
        _startResolutionPoller(eventId);
      }

      final nearbyStations = List<Map<String, dynamic>>.from(
          response['nearbyPoliceStations'] ?? []);
      
      // ✅ NEW: check if backend returned fallback emergency numbers
      final bool isFallback = response['nearbyStationsFallback'] == true;

      // ── Step 1: Show SOS sent confirmation ──────────────────────────
      _showSOSSentConfirmation(nearbyStations, isFallback: isFallback);
    } else {
      _showErrorSnackbar(
          'SOS could not be sent. Please call 112 directly.');
    }
  } catch (e) {
    setState(() => _isSOSTriggerLoading = false);
    debugPrint('❌ SOS trigger error: $e');
    if (mounted) {
      _showErrorSnackbar('SOS failed. Please call 112 directly.');
    }
  }
}


void _showSOSSentConfirmation(List<Map<String, dynamic>> nearbyStations, {bool isFallback = false}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── SOS sent icon ────────────────────────────────────────────
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle,
                  color: Colors.green.shade700, size: 48),
            ),
            const SizedBox(height: 20),

            const Text(
              '🚨 SOS Alert Sent!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Your emergency alert has been sent to your admin. '
              'Help is on the way.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // ── Police prompt ────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                children: [
                  Icon(isFallback ? Icons.phone_in_talk : Icons.local_police,
                      size: 32, color: Colors.blue),
                  const SizedBox(height: 8),
                  Text(
                    isFallback
                        ? 'Do you want to call emergency services?'
                        : 'Do you also want to notify the police?',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isFallback
                        ? 'We\'ll show you emergency helpline numbers to call.'
                        : 'Nearby police station numbers will be shown so you can call directly.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // ── No button ──────────────────────────────────────
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: Colors.grey),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('No, Thanks',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // ── Yes button ─────────────────────────────────────
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _showNearbyPoliceStations(nearbyStations, isFallback: isFallback);
                          },
                          icon: Icon(isFallback ? Icons.phone_in_talk : Icons.local_police, size: 18),
                          label: Text(isFallback ? 'Show Emergency Numbers' : 'Yes, Show Stations'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
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
  );
}


  // ============================================================================
  // ✅ FEATURE B: Manual Share Live Location via WhatsApp
  // ============================================================================
  Future<void> _shareLiveLocationManual() async {
    if (!mounted) return;

    try {
      // Check if user is logged in
      if (token == null || token!.isEmpty || _userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please log in to share location'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Check for active trip
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checking for active trip...')),
      );

      final activeTripData = await _checkActiveTrip();
      
      if (activeTripData == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No active trip found. Start a trip to share location.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Build tracking URL
      final tripId = activeTripData['tripId'] ?? activeTripData['_id'] ?? 'unknown';
      final liveTrackingUrl = '${ApiConfig.baseUrl}/live-track/$tripId';
      
      final tripNumber = activeTripData['tripNumber'] ?? 'N/A';
      final vehicleNumber = activeTripData['vehicleNumber'] ?? 'N/A';
      final driverName = activeTripData['driverName'] ?? 'Driver';

      // Build WhatsApp message
      final message = 'Hello! 👋\n\n'
          'I\'m sharing my live trip location with you.\n\n'
          '🚗 Trip: *$tripNumber*\n'
          '🚙 Vehicle: *$vehicleNumber*\n'
          '👤 Driver: *$driverName*\n\n'
          '📍 Track my ride in real time:\n'
          '$liveTrackingUrl\n\n'
          'Powered by Abra Travels';

      // Open WhatsApp with message
      await _openWhatsAppWithMessage(message);

    } catch (e) {
      debugPrint('❌ Error sharing live location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sharing location: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Opens WhatsApp with a pre-filled message (no phone number - user chooses contact)
  Future<void> _openWhatsAppWithMessage(String message) async {
    try {
      final encoded = Uri.encodeComponent(message);
      // Use WhatsApp share URL without phone number - lets user choose contact
      final uri = Uri.parse('https://wa.me/?text=$encoded');
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open WhatsApp. Please install WhatsApp.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ WhatsApp error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('WhatsApp error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<Map<String, String>?> _findNearestPoliceStation(double lat, double lon) async {
    try {
      debugPrint('🔍 Searching for police stations near: $lat, $lon');

      final radius = 5000;
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
          'User-Agent': 'AbraTravels/1.0',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> results = json.decode(response.body);
        
        if (results.isEmpty) {
          debugPrint('❌ No police stations found nearby');
          return null;
        }

        final closestStation = results[0];
        final stationName = closestStation['display_name'] ?? 'Local Police Station';
        final stationLat = double.tryParse(closestStation['lat'] ?? '0') ?? 0;
        final stationLon = double.tryParse(closestStation['lon'] ?? '0') ?? 0;

        String? phoneNumber;
        
        if (closestStation['address'] != null) {
          final address = closestStation['address'] as Map<String, dynamic>;
          phoneNumber = address['phone'] as String?;
        }

        debugPrint('✅ Found police station: $stationName');
        debugPrint('📍 Location: $stationLat, $stationLon');
        
        return {
          'name': stationName,
          'phone': phoneNumber ?? '100',
          'latitude': stationLat.toString(),
          'longitude': stationLon.toString(),
          'address': stationName,
        };
      } else {
        debugPrint('⚠️ OpenStreetMap API error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error finding police station: $e');
      return null;
    }
  }

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
                  '📞 We will automatically call this police station for emergency assistance.',
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

  Future<void> _initiatePoliceCall(String phoneNumber, String stationName) async {
    try {
      debugPrint('📞 Initiating call to police: $phoneNumber');
      
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
      debugPrint('❌ Error initiating call: $e');
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

void _showNearbyPoliceStations(List<Map<String, dynamic>> stations, {bool isFallback = false}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Handle ───────────────────────────────────────────────────
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),

            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isFallback ? Colors.red.shade100 : Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                        isFallback ? Icons.phone_in_talk : Icons.local_police,
                        color: isFallback ? Colors.red.shade700 : Colors.blue.shade700,
                        size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            isFallback
                                ? 'Emergency Helpline Numbers'
                                : 'Nearby Police Stations',
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                        Text(
                          isFallback
                              ? 'No local stations found — use these numbers'
                              : stations.isEmpty
                                  ? 'No stations found nearby'
                                  : '${stations.length} station${stations.length == 1 ? '' : 's'} found near your location',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),

            // ── Banner: fallback explanation OR emergency reminder ──────
            if (isFallback)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'No police stations found near your location. '
                        'Please use these national helpline numbers.',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.emergency, color: Colors.red.shade600, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'For immediate emergency, call 112 (National Emergency)',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.red),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _callNumber('112'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('Call 112',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ),

            const Divider(height: 16),

            // ── Station/Helpline list ────────────────────────────────────
            Expanded(
              child: stations.isEmpty
                  ? _buildNoStationsFound()
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: stations.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (_, i) =>
                          _buildPoliceStationCard(stations[i], i, isFallback: isFallback),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}


// ============================================================================
// Police station card with call button
// ============================================================================
Widget _buildPoliceStationCard(Map<String, dynamic> station, int index, {bool isFallback = false}) {
  final name = station['name']?.toString() ?? 'Emergency Number';
  final phone = station['phone']?.toString() ?? '112';
  final area = station['area']?.toString() ?? '';
  final distance = station['distance'];
  
  // ✅ Don't show "X km away" for fallback national numbers
  final distanceText = (!isFallback && distance != null && (distance as num) > 0)
      ? '${(distance as num).toStringAsFixed(1)} km away'
      : '';

  // ── Color scheme for fallback vs normal ──────────────────────────────────
  final Color cardBorderColor = isFallback
      ? (index == 0 ? Colors.red.shade300 : Colors.orange.shade200)
      : (index == 0 ? Colors.blue.shade300 : Colors.grey.shade200);
  final Color badgeColor = isFallback
      ? (index == 0 ? Colors.red.shade600 : Colors.orange.shade600)
      : (index == 0 ? Colors.blue.shade700 : Colors.grey.shade600);
  final Color badgeBg = isFallback
      ? (index == 0 ? Colors.red.shade100 : Colors.orange.shade50)
      : (index == 0 ? Colors.blue.shade100 : Colors.grey.shade100);

  // ── Special labels per helpline number ──────────────────────────────────
  String? specialLabel;
  if (isFallback) {
    switch (phone) {
      case '100':
        specialLabel = '🚔 Police';
        break;
      case '112':
        specialLabel = '🆘 Emergency';
        break;
      case '1091':
        specialLabel = '👩 Women Safety';
        break;
      case '108':
        specialLabel = '🚑 Ambulance';
        break;
      case '101':
        specialLabel = '🔥 Fire & Rescue';
        break;
      case '1098':
        specialLabel = '👶 Child Helpline';
        break;
      case '1073':
        specialLabel = '🛣️ Highway';
        break;
    }
  }

  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: cardBorderColor,
          width: index == 0 ? 2 : 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // ── Index badge ─────────────────────────────────────────────────
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: badgeColor),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // ── Info ─────────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    // ── Label badge ────────────────────────────────────────
                    if (isFallback && specialLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(specialLabel,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      )
                    else if (!isFallback && index == 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Nearest',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                if (area.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(area,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                ],
                if (distanceText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.directions,
                          size: 12, color: Colors.blue.shade400),
                      const SizedBox(width: 4),
                      Text(distanceText,
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue.shade600,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(phone,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isFallback
                              ? Colors.red.shade700
                              : Colors.black87)),
                ],
              ],
            ),
          ),

          // ── Call button ──────────────────────────────────────────────────
          if (phone.isNotEmpty)
            GestureDetector(
              onTap: () => _callNumber(phone),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isFallback
                      ? Colors.red.shade500
                      : Colors.green.shade500,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: (isFallback ? Colors.red : Colors.green)
                          .withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(Icons.phone,
                    color: Colors.white, size: 22),
              ),
            ),
        ],
      ),
    ),
  );
}

Widget _buildNoStationsFound() {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_off, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('No Nearby Stations Found',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Please call the national emergency number directly.',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _callNumber('112'),
            icon: const Icon(Icons.phone),
            label: const Text('Call 112 (Emergency)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    ),
  );
}

// ============================================================================
// Call a phone number
// ============================================================================
Future<void> _callNumber(String phone) async {
  final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
  final uri = Uri.parse('tel:$cleaned');
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  } catch (e) {
    debugPrint('❌ Could not launch call: $e');
  }
}

// ============================================================================
// ✅ NEW: _startResolutionPoller
// Polls every 30 seconds to check if admin has resolved the SOS
// Shows popup to customer with admin notes + resolution photo
// ============================================================================
void _startResolutionPoller(String eventId) {
  _resolutionPoller?.cancel();
  setState(() => _isPollingForResolution = true);

  _resolutionPoller =
      Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (!mounted) {
      timer.cancel();
      return;
    }
    try {
      final response = await _safeApi.safeGet(
        '/api/sos/$eventId',
        context: 'SOS Resolution Poll',
        fallback: null,
      );

      if (response == null) return;

      final status =
          response['status']?.toString().toLowerCase() ?? '';
      if (status == 'resolved') {
        timer.cancel();
        if (mounted) {
          setState(() {
            _activeSosEventId = null;
            _isPollingForResolution = false;
          });
          _showResolutionNotification(response);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Resolution poll error: $e');
    }
  });
}

// ============================================================================
// ✅ NEW: _showResolutionNotification
// Shown to customer when admin has resolved their SOS alert.
// Displays: status, admin notes, resolution photo (if any)
// ============================================================================
void _showResolutionNotification(Map<String, dynamic> sosEvent) {
  final resolution = sosEvent['resolution'] as Map<String, dynamic>?;
  final adminNotes = sosEvent['adminNotes']?.toString() ??
      resolution?['notes']?.toString() ??
      '';
  final resolvedBy =
      resolution?['resolvedBy']?.toString() ?? 'Admin';
  final resolvedAt = resolution?['timestamp'] != null
      ? DateTime.tryParse(resolution!['timestamp'].toString())
      : null;

  // ── Decode photo if present ──────────────────────────────────────────
  Uint8List? photoBytes;
  if (resolution?['photoBase64'] != null) {
    try {
      photoBytes = base64Decode(resolution!['photoBase64']);
    } catch (_) {}
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ───────────────────────────────────────────────
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.verified_rounded,
                      color: Colors.green.shade700, size: 40),
                ),
                const SizedBox(height: 16),
                const Text('✅ Your SOS Has Been Resolved',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'Resolved by $resolvedBy'
                  '${resolvedAt != null ? '\n${_formatResolvedAt(resolvedAt)}' : ''}',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),

                // ── Admin notes ──────────────────────────────────────────
                if (adminNotes.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.notes,
                                size: 16,
                                color: Colors.blue.shade700),
                            const SizedBox(width: 6),
                            Text('Admin Notes',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight:
                                        FontWeight.bold,
                                    color:
                                        Colors.blue.shade700)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          adminNotes,
                          style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87),
                        ),
                      ],
                    ),
                  ),

                // ── Resolution photo ─────────────────────────────────────
                if (photoBytes != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              12, 12, 12, 6),
                          child: Row(
                            children: [
                              Icon(Icons.photo_camera,
                                  size: 16,
                                  color:
                                      Colors.grey.shade600),
                              const SizedBox(width: 6),
                              Text('Resolution Photo',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight:
                                          FontWeight.bold,
                                      color: Colors
                                          .grey.shade600)),
                            ],
                          ),
                        ),
                        ClipRRect(
                          borderRadius:
                              const BorderRadius.vertical(
                                  bottom: Radius.circular(12)),
                          child: Image.memory(
                            photoBytes,
                            width: double.infinity,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // ── Safety check prompt ──────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.favorite,
                          color: Colors.red.shade400, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'We hope you are safe! If you still need help, please call 112 immediately.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Dismiss button ───────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(12)),
                    ),
                    child: const Text('I\'m Safe, Thank You',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

String _formatResolvedAt(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
  if (diff.inHours < 24) return '${diff.inHours} hours ago';
  return '${dt.day}/${dt.month}/${dt.year}';
}

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
                  '⚠️ SOS Alert can only be triggered during an active trip.',
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
                  '✅ Your emergency alert has been sent successfully.',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                _buildSuccessInfoRow('Police', policeNotified ? 'Notified ✓' : 'Admin notified', 
                    policeNotified ? Colors.green : Colors.orange),
                if (policeNotified && policeEmail != 'none')
                  _buildSuccessInfoRow('Email', policeEmail, Colors.grey),
                _buildSuccessInfoRow('Support Team', 'Alerted ✓', Colors.green),
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
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.directions_bus, size: 32, color: Colors.white);
              },
            ),
          ),
          const SizedBox(width: 12),
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
        IconButton(
          icon: Icon(
            Icons.refresh,
            color: Colors.white,
            size: isMobile ? 24 : 26,
          ),
          onPressed: _refreshDashboard,
          tooltip: 'Refresh Dashboard',
        ),
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
        if (!isSmallMobile)
          IconButton(
            icon: Icon(Icons.headset_mic_outlined, color: Colors.white, size: isMobile ? 24 : 26),
            onPressed: () => _showSupportDialog(context),
            tooltip: 'Support',
          ),
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
                  '$greeting, $userName! 👋',
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

  // ============================================================================
  // ✅ FIX #1: Show "Completed Trips" instead of "Total Trips"
  // ============================================================================
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
                            'Completed Trips',
                            _getCompletedTripsValue(),
                            Icons.check_circle,
                            Colors.green,
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

  String _getCompletedTripsValue() {
    try {
      final trips = _quickStats['totalTrips'] as Map<String, dynamic>?;
      if (trips != null) {
        final completed = trips['completed'] ?? 0;
        return completed.toString();
      }
      return '0';
    } catch (e) {
      return '0';
    }
  }

  Widget _buildTrackingCard(BuildContext context, bool isMobile) {
    if (_activeTripId != null) {
      return LiveTripCard(tripId: _activeTripId!);
    }
    
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Track My Vehicle',
                        style: TextStyle(
                          fontSize: isMobile ? 18 : 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'See live location of your driver',
                        style: TextStyle(
                          fontSize: isMobile ? 13 : 14,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loadingTripId ? null : () async {
                  if (token != null && token!.isNotEmpty) {
                    await _loadActiveTripFromMyTrips();
                    
                    if (_activeTripId != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EnhancedTrackingScreen(
                            tripId: _activeTripId!,
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No active trips found'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  }
                },
                icon: _loadingTripId 
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.navigation),
                label: Text(_loadingTripId ? 'Checking...' : 'Track Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    vertical: isMobile ? 14 : 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ),
            // ✅ REMOVED: Share Live Location button from dashboard (moved to tracking screen)
          ],
        ),
      ),
    );
  }

  Widget _buildResponsiveSOSHistorySection(bool isMobile, bool isSmallMobile) {
    final padding = isSmallMobile ? 16.0 : isMobile ? 20.0 : 24.0;
    final titleFontSize = isSmallMobile ? 16.0 : isMobile ? 17.0 : 18.0;

    return Container(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isMobile ? 16 : 20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 0,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: Icon(Icons.history, color: Colors.purple[700], size: isMobile ? 20 : 24),
        title: Text(
          'SOS Alert History',
          style: TextStyle(
            fontSize: titleFontSize,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        children: [
          _sosHistoryLoading
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              : _sosHistory.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(isMobile ? 12.0 : 16.0),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 48,
                              color: Colors.green[300],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No resolved SOS alerts found.',
                              style: TextStyle(
                                fontSize: isMobile ? 13 : 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'You\'re all safe! 🎉',
                              style: TextStyle(
                                fontSize: isMobile ? 12 : 13,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _sosHistory.length,
                      itemBuilder: (context, index) {
                        final alert = _sosHistory[index];
                        return Container(
                          margin: EdgeInsets.only(bottom: isMobile ? 8 : 4),
                          decoration: BoxDecoration(
                            color: _getStatusColor(alert.status).withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _getStatusColor(alert.status).withOpacity(0.2),
                            ),
                          ),
                          child: ListTile(
                            dense: isMobile,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 12 : 16,
                              vertical: isMobile ? 4 : 8,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _getStatusColor(alert.status).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _getStatusIcon(alert.status),
                                color: _getStatusColor(alert.status),
                                size: isMobile ? 20 : 24,
                              ),
                            ),
                            title: Text(
                              'SOS on ${DateFormat.yMMMd().format(alert.timestamp)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: isSmallMobile ? 13 : isMobile ? 14 : 16,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(alert.status),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    alert.status,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (alert.adminNotes.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                '💬 Admin: "${alert.adminNotes}"',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  fontSize: isSmallMobile ? 11 : 12,
                                  color: Colors.grey[700],
                                ),
                                maxLines: isMobile ? 2 : 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.access_time,
                              size: 14,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat.jm().format(alert.timestamp),
                              style: TextStyle(
                                fontSize: isSmallMobile ? 10 : 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    ],
  ),
);
}
Color _getStatusColor(String status) {
switch (status) {
case 'Resolved':
return Colors.green;
case 'In Progress':
return Colors.orange;
case 'Escalated':
return Colors.red;
default:
return Colors.grey;
}
}
IconData _getStatusIcon(String status) {
switch (status) {
case 'Resolved':
return Icons.check_circle;
case 'In Progress':
return Icons.hourglass_top;
case 'Escalated':
return Icons.warning;
default:
return Icons.help;
}
}
String _getDistanceValue() {
try {
final distance = _quickStats['totalDistance'] ?? 0.0;
if (distance is num) {
if (distance >= 1000) {
return '${(distance / 1000).toStringAsFixed(1)}k km';
}
return '${distance.toStringAsFixed(0)} km';
}
return '0 km';
} catch (e) {
return '0 km';
}
}
Widget _buildQuickStatItem(String label, String value, IconData icon, Color color) {
return Container(
padding: const EdgeInsets.all(16),
decoration: BoxDecoration(
gradient: LinearGradient(
begin: Alignment.topLeft,
end: Alignment.bottomRight,
colors: [
color.withOpacity(0.1),
color.withOpacity(0.05),
],
),
borderRadius: BorderRadius.circular(16),
border: Border.all(color: color.withOpacity(0.3)),
boxShadow: [
BoxShadow(
color: color.withOpacity(0.1),
spreadRadius: 0,
blurRadius: 8,
offset: const Offset(0, 2),
),
],
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Container(
padding: const EdgeInsets.all(8),
decoration: BoxDecoration(
color: color.withOpacity(0.15),
borderRadius: BorderRadius.circular(10),
),
child: Icon(icon, color: color, size: 22),
),
const SizedBox(width: 10),
Expanded(
child: Text(
label,
style: TextStyle(
fontSize: 13,
color: Colors.grey[700],
fontWeight: FontWeight.w600,
),
overflow: TextOverflow.ellipsis,
),
),
],
),
const SizedBox(height: 12),
Text(
value,
style: TextStyle(
fontSize: 24,
fontWeight: FontWeight.bold,
color: color,
letterSpacing: -0.5,
),
),
],
),
);
}
}
// ============================================================================
// ✅ LIVE TRIP CARD WIDGET
// ============================================================================
class LiveTripCard extends StatelessWidget {
final String tripId;
const LiveTripCard({
super.key,
required this.tripId,
});
@override
Widget build(BuildContext context) {
return Card(
elevation: 2,
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
child: Container(
padding: const EdgeInsets.all(20),
decoration: BoxDecoration(
gradient: LinearGradient(
colors: [Colors.green.shade50, Colors.green.shade100],
begin: Alignment.topLeft,
end: Alignment.bottomRight,
),
borderRadius: BorderRadius.circular(16),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Container(
padding: const EdgeInsets.all(12),
decoration: BoxDecoration(
color: Colors.green,
borderRadius: BorderRadius.circular(12),
),
child: const Icon(
Icons.directions_car,
color: Colors.white,
size: 28,
),
),
const SizedBox(width: 16),
const Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'Trip in Progress',
style: TextStyle(
fontSize: 18,
fontWeight: FontWeight.bold,
color: Colors.green,
),
),
SizedBox(height: 4),
Text(
'Your ride is ongoing',
style: TextStyle(
fontSize: 14,
color: Colors.green,
),
),
],
),
),
],
),
const SizedBox(height: 16),
SizedBox(
width: double.infinity,
child: ElevatedButton.icon(
onPressed: () {
Navigator.push(
context,
MaterialPageRoute(
builder: (context) => EnhancedTrackingScreen(
tripId: tripId,
),
),
);
},
icon: const Icon(Icons.navigation),
label: const Text('Track Live'),
style: ElevatedButton.styleFrom(
backgroundColor: Colors.green,
foregroundColor: Colors.white,
padding: const EdgeInsets.symmetric(vertical: 14),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(12),
),
elevation: 2,
),
),
),
],
),
),
);
}
}
