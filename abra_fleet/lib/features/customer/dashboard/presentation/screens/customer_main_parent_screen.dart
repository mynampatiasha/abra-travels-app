import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart'; // 🔥 FCM for instant notifications

// Import your app's auth and login screen files
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/presentation/screens/welcome_screen.dart';

// Import MyTripsScreen to access the GlobalKey
import 'my_trips_screen.dart';

// Import NotificationService
import 'package:abra_fleet/core/services/notification_service.dart';

// Floating notification
import 'package:abra_fleet/core/services/floating_notification_service.dart';

import 'package:abra_fleet/features/client/organization_model.dart';

// Import all the pages you want to navigate between
import 'customer_dashboard.dart';
import 'mystats_screen.dart'; 
import 'customer_profile_screen.dart';
import 'roster_screen.dart';
import 'my_trips_screen.dart';

// YOUR MAIN SCREEN WIDGET THAT CONTAINS THE FIXED BOTTOM BAR
class CustomerMainScreen extends StatefulWidget {
  const CustomerMainScreen({super.key});

  @override
  State<CustomerMainScreen> createState() => _CustomerMainScreenState();
}

class _CustomerMainScreenState extends State<CustomerMainScreen> {
  int _selectedIndex = 0;

  // Notification Service instance
  final NotificationService _notificationService = NotificationService();
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  StreamSubscription<RemoteMessage>? _fcmSubscription; // 🔥 FCM instant delivery
  final FloatingNotificationService _floatingNotificationService = FloatingNotificationService();
  bool _notificationsInitialized = false;
  // 🔥 Duplicate prevention
  final Set<String> _processedNotificationIds = {};
  static const int _maxProcessedIds = 100;
   // Organization data
  OrganizationModel? _organization;
  bool _isLoadingOrganization = true;

  // This is the list of all your pages that the bottom navigation bar can show.
  late List<Widget> _widgetOptions;

  // Key for MyTripsScreen to access its state
  final GlobalKey<State<MyTripsScreen>> _myTripsKey = GlobalKey<State<MyTripsScreen>>();

  @override
  void initState() {
    super.initState();
    
    // Initialize notifications
    _initializeNotifications();
    _fetchOrganization();
    
    _initializeWidgets();
  }

  // Initialize all the widgets with proper callbacks
  void _initializeWidgets() {
    _widgetOptions = <Widget>[
      // Index 0: Home
      CustomerDashboard(
        onLogout: _handleLogout,
        onNavigateToMyTrips: () => _onItemTapped(3),
        onNavigateToProfile: () => _onItemTapped(4),
        onNavigateToCreateRoster: () => _onItemTapped(1),
        onNavigateToMyStats: () => _onItemTapped(2),
      ),
      
      // Index 1: Roster - Use a Builder to get the context
      Builder(
        builder: (context) => CreateRosterScreen(
          organization: _organization,
          organizationId: _organization?.id,
          // Add a callback to handle when a roster is created/updated
          onRosterSaved: (success) {
            if (success == true) {
              // If we're on the MyTripsScreen, it will auto-refresh via its onRefresh callback
              if (_selectedIndex == 3) {
                // MyTripsScreen will refresh automatically
                debugPrint('✅ Roster saved, MyTripsScreen will auto-refresh');
              } else {
                // If not on MyTripsScreen, show a snackbar and navigate to MyTrips
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Trip created successfully!'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                  // Navigate to MyTrips screen
                  _onItemTapped(3);
                }
              }
            }
          },
        ),
      ),
      
      // Index 2: My Stats / Activity Report
      const MyStatsScreen(),
      
      // Index 3: My Trips - Add a key to be able to refresh it
      MyTripsScreen(
        key: _myTripsKey,
      ),
      
      // Index 4: My Profile
      const CustomerProfileScreen(),
    ];
  }

  // Initialize notification service
  Future<void> _initializeNotifications() async {
    try {
      debugPrint('Initializing NotificationService in CustomerMainScreen...');
      await _notificationService.initialize();

      // 🔥 FCM LISTENER — instant delivery (PRIMARY)
      _fcmSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (!mounted) return;
        final notifId = message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
        if (_processedNotificationIds.contains(notifId)) return;
        _processedNotificationIds.add(notifId);
        if (_processedNotificationIds.length > _maxProcessedIds) {
          _processedNotificationIds.remove(_processedNotificationIds.first);
        }
        _showBanner({
          'type'    : message.data['type'] ?? 'general',
          'title'   : message.notification?.title ?? 'New Notification',
          'message' : message.notification?.body ?? '',
          'priority': message.data['priority'] ?? 'normal',
        });
      });

      // 🔔 OneSignal stream — backup (SECONDARY)
      _notificationSubscription =
          _notificationService.onNewNotification.listen((notification) {
        if (!mounted) return;
        final notifId = (notification['id'] ?? notification['_id'] ??
            DateTime.now().millisecondsSinceEpoch.toString()).toString();
        if (_processedNotificationIds.contains(notifId)) return;
        _processedNotificationIds.add(notifId);
        if (_processedNotificationIds.length > _maxProcessedIds) {
          _processedNotificationIds.remove(_processedNotificationIds.first);
        }
        _showBanner(notification);
      });

      if (mounted) setState(() => _notificationsInitialized = true);
      debugPrint('✅ NotificationService initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing NotificationService: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initialize notifications: $e'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _showBanner(Map<String, dynamic> notification) {
    final type     = notification['type']?.toString() ?? 'general';
    final title    = notification['title']?.toString() ?? 'New Notification';
    final body     = notification['message']?.toString() ??
                     notification['body']?.toString() ?? '';
    final priority = notification['priority']?.toString() ?? 'normal';

    const iconMap = {
      'trip_started'           : '🚗',
      'trip_completed'         : '✅',
      'trip_cancelled'         : '❌',
      'driver_arrived'         : '📍',
      'eta_15min'              : '⏰',
      'eta_5min'               : '⏰',
      'leave_approved'         : '✅',
      'leave_rejected'         : '❌',
      'address_change_approved': '📍',
      'address_change_rejected': '❌',
      'feedback_request'       : '⭐',
      'roster_assigned'        : '📋',
      'payment_received'       : '💰',
    };
    const colorMap = {
      'urgent': Color(0xFFDC2626),
      'high'  : Color(0xFFD97706),
      'normal': Color(0xFF1D4ED8),
      'low'   : Color(0xFF059669),
    };

    _floatingNotificationService.showFloatingNotification(
      context: context,
      title: title,
      body: body,
      icon: iconMap[type] ?? '🔔',
      type: type,
      priority: priority,
      backgroundColor: colorMap[priority] ?? const Color(0xFF1D4ED8),
      duration: const Duration(seconds: 5),
    );
  }

  Future<void> _fetchOrganization() async {
  try {
    // TODO: Replace with your actual API call to get organization
    // Example: 
    // final org = await organizationRepository.getMyOrganization();
    // setState(() {
    //   _organization = org;
    //   _isLoadingOrganization = false;
    // });
    
    // For now, using null (which will use default shifts from ShiftTemplates)
    setState(() {
      _organization = null;
      _isLoadingOrganization = false;
    });
    
    debugPrint('⚠️ Organization data not fetched - using default shifts for testing');
  } catch (e) {
    debugPrint('❌ Error fetching organization: $e');
    setState(() {
      _isLoadingOrganization = false;
    });
  }
}


  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _fcmSubscription?.cancel(); // 🔥 Cancel FCM subscription
    _notificationService.dispose();
    _floatingNotificationService.dispose();
    _processedNotificationIds.clear();
    super.dispose();
  }

  // Logout function with full logic
  Future<void> _handleLogout() async {
    try {
      // Get the AuthRepository from the Provider tree
      final authRepository = Provider.of<AuthRepository>(context, listen: false);

      // Call the signOut method
      await authRepository.signOut();

      // Navigate to the WelcomeScreen and remove all previous routes
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const WelcomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      // Handle any potential errors during sign-out
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // This function is the core of the navigation
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main content
          IndexedStack(
            index: _selectedIndex,
            children: _widgetOptions,
          ),
          
          // ✅ ADD THIS: Show initialization indicator
          if (!_notificationsInitialized)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Connecting...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      
      // This is your permanent, fixed bottom navigation bar
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF4F46E5),
        unselectedItemColor: Colors.grey[500],
        elevation: 8,
        items: const [
          // Index 0
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            label: 'Home',
          ),
          // Index 1
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today_outlined),
            label: 'Roster',
          ),
          // Index 2
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            label: 'Activity Report',
          ),
          // Index 3
          BottomNavigationBarItem(
            icon: Icon(Icons.card_travel_outlined),
            label: 'My Trips',
          ),
          // Index 4
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'My Profile',
          ),
        ],
      ),
    );
  }
}