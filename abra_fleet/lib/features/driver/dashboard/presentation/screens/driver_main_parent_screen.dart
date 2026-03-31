import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

// ✅ IMPORT NOTIFICATION SERVICE & SCREEN
import 'package:abra_fleet/core/services/notification_service.dart';
import 'package:abra_fleet/features/notifications/presentation/screens/driver_notifications_screen.dart';

// ✅ IMPORT ONESIGNAL SERVICE
import 'package:abra_fleet/core/services/one_signal_service.dart';

// ✅ IMPORT HRM SCREEN  ← NEW
// Place hrm_driver_management.dart in the same folder as this file
// and update the import path if needed.
import 'package:abra_fleet/features/driver/dashboard/presentation/screens/hrm_driver_management.dart';

// Import your feature pages
import 'package:abra_fleet/features/driver/dashboard/presentation/screens/driver_dashboard_screen.dart';
import 'package:abra_fleet/features/driver/dashboard/presentation/screens/trips_driver_page.dart';
import 'package:abra_fleet/features/driver/dashboard/presentation/screens/customer_driver_page.dart';
import 'package:abra_fleet/features/driver/dashboard/presentation/screens/reports_driver_page.dart';
import 'package:abra_fleet/features/driver/dashboard/presentation/screens/profile_driver_page.dart';
import 'package:abra_fleet/features/driver/dashboard/presentation/screens/driver_individual_trips.dart';

const Color kPrimaryColor = Color(0xFF0D47A1);

class DriverMainShell extends StatefulWidget {
  const DriverMainShell({super.key});

  @override
  State<DriverMainShell> createState() => _DriverMainShellState();
}

class _DriverMainShellState extends State<DriverMainShell> {
  int _selectedIndex = 0;

  // ✅ Notification Variables
  final NotificationService _notificationService = NotificationService();
  StreamSubscription<Map<String, dynamic>>? _notificationSubscription;
  bool _notificationsInitialized = false;

  // ─────────────────────────────────────────────────────────────────────────
  //  Bottom nav tap-index  ↔  IndexedStack slot  (exact 1-to-1 mapping)
  //
  //   0 → Dashboard
  //   1 → Trips
  //   2 → Reports
  //   3 → HRM          ← NEW real widget in IndexedStack (NOT a push)
  //   4 → Profile
  //
  //  ⚠️  There is NO SizedBox.shrink() placeholder at index 3.
  //      A SizedBox.shrink() at any IndexedStack slot causes the
  //      focus_traversal null-dereference crash seen in the console.
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _initializeNotifications();
    _initializeOneSignal();
  }

  // ── OneSignal ─────────────────────────────────────────────────────────────

  Future<void> _initializeOneSignal() async {
    try {
      debugPrint('\n' + '🔔' * 50);
      debugPrint('🔔 INITIALIZING ONESIGNAL FOR DRIVER');
      debugPrint('🔔' * 50);

      final prefs     = await SharedPreferences.getInstance();
      final userId    = prefs.getString('user_id');
      final userRole  = prefs.getString('user_role');
      final userEmail = prefs.getString('user_email');
      final authToken = prefs.getString('jwt_token');

      debugPrint('📋 Stored User Data:');
      debugPrint('   User ID: $userId');
      debugPrint('   User Role: $userRole');
      debugPrint('   User Email: $userEmail');
      debugPrint(
          '   Auth Token: ${authToken != null ? "Present (${authToken.length} chars)" : "Missing"}');

      if (userId != null && userEmail != null && authToken != null) {
        debugPrint('\n🚀 STEP 1: Requesting browser notification permission...');

        final permissionGranted =
            await OneSignal.Notifications.requestPermission(true);
        debugPrint('📱 Permission request result: $permissionGranted');

        final hasPermission = await OneSignal.Notifications.permission;
        debugPrint('🔐 Current permission status: $hasPermission');

        if (!hasPermission) {
          debugPrint('⚠️ WARNING: Notification permission NOT granted!');
          debugPrint('   User must enable notifications in browser settings.');
          debugPrint('   Instructions:');
          debugPrint('   1. Click lock icon 🔒 in address bar');
          debugPrint('   2. Find "Notifications" setting');
          debugPrint('   3. Change to "Allow"');
          debugPrint('   4. Refresh the page');
        } else {
          debugPrint('✅ Notification permission GRANTED!');
        }

        debugPrint('\n🚀 STEP 2: Initializing OneSignal service with tags...');

        await OneSignalService().initialize(
          userId:    userId,
          userRole:  userRole ?? 'driver',
          authToken: authToken,
          userEmail: userEmail,
        );

        final subscriptionId = OneSignal.User.pushSubscription.id;
        debugPrint('\n📡 OneSignal Subscription Check:');
        debugPrint(
            '   Subscription ID: ${subscriptionId ?? "NOT SUBSCRIBED"}');

        if (subscriptionId == null) {
          debugPrint('   ⚠️ Device is NOT subscribed to push notifications');
          debugPrint('   This usually means permission was denied.');
        } else {
          debugPrint(
              '   ✅ Device is subscribed and ready to receive notifications');
        }

        debugPrint('\n✅ OneSignal initialized successfully for driver');
        debugPrint('   ✓ Device will be tagged with:');
        debugPrint('     - userId: $userId');
        debugPrint('     - userRole: ${userRole ?? "driver"}');
        debugPrint('     - email: $userEmail');
        debugPrint('🔔' * 50 + '\n');
      } else {
        debugPrint('\n❌ Missing required data for OneSignal initialization:');
        if (userId == null) debugPrint('   ✗ User ID is missing');
        if (userEmail == null) debugPrint('   ✗ User Email is missing');
        if (authToken == null) debugPrint('   ✗ Auth Token is missing');
        debugPrint('🔔' * 50 + '\n');
      }
    } catch (e, stackTrace) {
      debugPrint('\n❌ OneSignal initialization error: $e');
      debugPrint('Stack trace:');
      debugPrint(stackTrace.toString());
      debugPrint('🔔' * 50 + '\n');
    }
  }

  // ── Notification navigation ───────────────────────────────────────────────

  void _navigateToNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (context) => const DriverNotificationsScreen()),
    );
  }

  // ── Notification service init ─────────────────────────────────────────────

  Future<void> _initializeNotifications() async {
    try {
      await _notificationService.initialize();

      _notificationSubscription =
          _notificationService.onNewNotification.listen((notification) {
        if (mounted) {
          if (notification['type'] == 'vehicle_assigned') {
            _showVehicleAssignedDialog(notification);
          } else if (notification['type'] == 'trip_assigned') {
            _showTripAssignedDialog(notification);
          }
        }
      });

      if (mounted) {
        setState(() {
          _notificationsInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Error initializing notifications: $e');
    }
  }

  // ── Trip Assignment Dialog ────────────────────────────────────────────────

  void _showTripAssignedDialog(Map<String, dynamic> notification) {
    final data        = notification['data'] ?? {};
    final tripNumber  = data['tripNumber']  ?? 'Unknown';
    final vehicleNumber = data['vehicleNumber'] ?? 'Vehicle';
    final distance    = data['distance']    ?? 'Unknown';
    final pickupTime  = data['pickupTime']  ?? 'Unknown';

    showDialog(
      context:            context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.directions_bus, color: kPrimaryColor, size: 28),
            SizedBox(width: 10),
            Text('New Trip Assigned!',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trip $tripNumber has been assigned to you!',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            Container(
              width:   double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:        Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border:       Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.local_taxi, color: Colors.green[700], size: 20),
                    const SizedBox(width: 8),
                    Text('Vehicle: $vehicleNumber',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.straighten, color: Colors.green[700], size: 20),
                    const SizedBox(width: 8),
                    Text('Distance: $distance km',
                        style: const TextStyle(fontSize: 14)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.access_time, color: Colors.green[700], size: 20),
                    const SizedBox(width: 8),
                    Text('Pickup: $pickupTime',
                        style: const TextStyle(fontSize: 14)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('What would you like to do?',
                style: TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Send decline response to backend
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Trip declined'),
                    backgroundColor: Colors.red),
              );
            },
            style: TextButton.styleFrom(
                backgroundColor: Colors.red.shade400,
                foregroundColor: Colors.white),
            child: const Text('❌ Decline'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Send accept response to backend
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Trip accepted!'),
                    backgroundColor: Colors.green),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white),
            child: const Text('✅ Accept'),
          ),
        ],
      ),
    );
  }

  // ── Vehicle Assignment Dialog ─────────────────────────────────────────────

  void _showVehicleAssignedDialog(Map<String, dynamic> notification) {
    final data        = notification['data'] ?? {};
    final vehicleName = data['vehicleName']        ?? 'a vehicle';
    final regNumber   = data['registrationNumber'] ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.directions_car, color: kPrimaryColor, size: 28),
            SizedBox(width: 10),
            Text('Vehicle Assigned'),
          ],
        ),
        content: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification['body'] ??
                'You have been assigned a new vehicle.'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:        Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border:       Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vehicle: $vehicleName',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (regNumber.isNotEmpty)
                    Text('Registration: $regNumber',
                        style: TextStyle(color: Colors.grey[800])),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style:     ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
            onPressed: () => Navigator.pop(context),
            child:     const Text('Acknowledge'),
          ),
        ],
      ),
    );
  }

  // ── dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _notificationService.dispose();
    super.dispose();
  }

  // ── tab switch ────────────────────────────────────────────────────────────

  void _onItemTapped(int index) {
    // All 5 tabs switch directly via IndexedStack — no Navigator.push for HRM.
    setState(() => _selectedIndex = index);
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── IndexedStack holds ALL 5 real widgets ─────────────────────────
          // ⚠️  Every slot must be a real content widget.
          //     SizedBox.shrink() at any slot causes the focus_traversal crash.
          IndexedStack(
            index: _selectedIndex,
            children: [

              // ── 0: Dashboard ──────────────────────────────────────────────
              DriverTripDashboard(
                onNavigateToReportTab:     () => _onItemTapped(2),
                onNavigateToNotifications: _navigateToNotifications,
              ),

              // ── 1: Trips ──────────────────────────────────────────────────
              const TripsDriverPage(),

              // ── 2: Reports ────────────────────────────────────────────────
              const ReportsDriverPage(),

              // ── 3: HRM  ← real widget, NO Scaffold inside ─────────────────
              // Because HrmDriverManagementScreen has no Scaffold, this shell's
              // Scaffold (and its bottom nav bar) stays visible at all times.
              HrmDriverManagementScreen(
                onNavigateToNotifications: _navigateToNotifications,
              ),

              // ── 4: Profile ────────────────────────────────────────────────
              const ProfileDriverPage(),
            ],
          ),

          // ── Connecting indicator ──────────────────────────────────────────
          if (!_notificationsInitialized)
            Positioned(
              top:   MediaQuery.of(context).padding.top + 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:        Colors.orange.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width:  12,
                      height: 12,
                      child:  CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    SizedBox(width: 8),
                    Text('Connecting...',
                        style: TextStyle(color: Colors.white, fontSize: 10)),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildCustomBottomNavBar(),
    );
  }

  // ── bottom nav ────────────────────────────────────────────────────────────

  Widget _buildCustomBottomNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color:     Colors.white,
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withOpacity(0.10),
            blurRadius: 10,
            offset:     const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(
              icon:  Icons.dashboard_rounded,
              label: 'Dashboard',
              index: 0,
            ),
            _buildNavItemWithBadge(
              icon:       Icons.drive_eta_rounded,
              label:      'Trips',
              index:      1,
              badgeCount: 0,
            ),
            _buildNavItem(
              icon:  Icons.bar_chart_rounded,
              label: 'Reports',
              index: 2,
            ),
            // ✅ HRM tab — index 3 — real IndexedStack slot
            _buildNavItem(
              icon:  Icons.people_alt_rounded,
              label: 'HRM',
              index: 3,
            ),
            _buildNavItem(
              icon:  Icons.person_rounded,
              label: 'Profile',
              index: 4,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String   label,
    required int      index,
  }) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap:    () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width:    60,
        padding:  const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
        decoration: BoxDecoration(
          color:        isSelected ? kPrimaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size:  24,
                color: isSelected ? Colors.white : Colors.grey[700]),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize:   10,
                fontWeight: FontWeight.bold,
                color:      isSelected ? Colors.white : Colors.grey[600],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItemWithBadge({
    required IconData icon,
    required String   label,
    required int      index,
    required int      badgeCount,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildNavItem(icon: icon, label: label, index: index),
        if (badgeCount > 0)
          Positioned(
            top:   -4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color:  Colors.red,
                shape:  BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text(
                '$badgeCount',
                style: const TextStyle(
                  color:      Colors.white,
                  fontSize:   10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}