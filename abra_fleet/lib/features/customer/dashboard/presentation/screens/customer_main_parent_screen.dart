import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Import your app's auth and login screen files
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/presentation/screens/welcome_screen.dart';

// Import MyTripsScreen to access the GlobalKey
import 'my_trips_screen.dart';

// Import NotificationService
import 'package:abra_fleet/core/services/notification_service.dart';

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
  bool _notificationsInitialized = false;
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
      debugPrint(' Initializing NotificationService in CustomerMainScreen...');
      await _notificationService.initialize();
      
      if (mounted) {
        setState(() {
          _notificationsInitialized = true;
        });
      }
      
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
    // ✅ ADD THIS: Dispose notification service
    _notificationService.dispose();
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