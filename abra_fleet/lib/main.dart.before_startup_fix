// File: lib/main.dart - COMPLETE VERSION WITH FLOATING NOTIFICATIONS FOR ALL ROLES
// Abra Travels Management - Main Application Entry Point
// ✅ UPDATED: JWT authentication with diagnostic logging
// ✅ ADDED: Global Ctrl+A keyboard shortcut support
// 🔥 UPDATED: FCM with Floating Banners for Driver, Customer, Admin

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:overlay_support/overlay_support.dart'; // 🔥 NEW

// 🔥 FCM for Push Notifications
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:abra_fleet/core/services/fcm_service.dart';
import 'package:abra_fleet/core/widgets/notification_overlay_widget.dart'; // 🔥 NEW

// Auth - JWT based
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/features/auth/data/repositories/jwt_auth_repository_impl.dart';
import 'package:abra_fleet/features/auth/domain/entities/user_entity.dart';

// Core
import 'package:abra_fleet/core/services/backend_connection_manager.dart';

// Screens
import 'package:abra_fleet/features/auth/presentation/screens/login_screen.dart';
import 'package:abra_fleet/features/auth/presentation/screens/welcome_screen.dart';
import 'package:abra_fleet/app/presentation/screens/main_app_shell.dart';
import 'package:abra_fleet/features/auth/presentation/screens/splash_screen.dart';

// Vehicle
import 'package:abra_fleet/features/admin/vehicle_management/domain/repositories/vehicle_repository.dart';
import 'package:abra_fleet/features/admin/vehicle_management/data/repositories/api_vehicle_repository_impl.dart';
import 'package:abra_fleet/features/admin/vehicle_management/presentation/providers/vehicle_provider.dart';

// Driver
import 'package:abra_fleet/features/admin/driver_management/domain/repositories/driver_repository.dart';
import 'package:abra_fleet/features/admin/driver_management/data/repositories/mock_driver_repository_impl.dart';
import 'package:abra_fleet/features/admin/driver_management/presentation/providers/driver_provider.dart';

// Customer
import 'package:abra_fleet/features/admin/customer_management/presentation/providers/customer_provider.dart';

// Services
import 'package:abra_fleet/core/services/roster_service.dart';
import 'package:abra_fleet/core/services/api_service.dart';

// Notifications
import 'package:abra_fleet/features/notifications/presentation/providers/notification_provider.dart';

// Import the custom AppTheme
import 'package:abra_fleet/app/config/theme/app_theme.dart';

// Import dashboard screens
import 'package:abra_fleet/features/customer/dashboard/presentation/screens/customer_dashboard.dart';
import 'package:abra_fleet/features/driver/dashboard/presentation/screens/driver_dashboard_screen.dart';
import 'package:abra_fleet/features/client/client_main_shell.dart';

// 🔥 Import ALL notification screens for routing
import 'package:abra_fleet/features/notifications/presentation/screens/screens/driver_trip_response_screen.dart';
import 'package:abra_fleet/features/notifications/presentation/screens/driver_notifications_screen.dart';
import 'package:abra_fleet/features/notifications/presentation/screens/customer_notifications_screen.dart';
import 'package:abra_fleet/features/notifications/presentation/screens/admin_notifications_screen.dart';
import 'package:abra_fleet/features/notifications/presentation/screens/client_notifications_screen.dart';

// Global navigator key for navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global FCM service instance (mobile only)
FCMService? _globalFcmService;

// ===================================================================
// MAIN FUNCTION - JWT AUTHENTICATION WITH FCM
// ===================================================================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize environment variables
  try {
    // For web, .env file loading might fail - use fallback values
    if (kIsWeb) {
      debugPrint("🌐 Running on Web - Using default configuration");
      debugPrint("🔥 Firebase FCM will be enabled for web push notifications");
      
      // Set default values for web
      dotenv.testLoad(fileInput: '''
API_BASE_URL=http://localhost:3001
WEBSOCKET_URL=ws://localhost:3001
FIREBASE_PROJECT_ID=abrafleet-cec94
''');
    } else {
      await dotenv.load(fileName: ".env");
    }
    debugPrint("✅ Environment variables loaded");
    debugPrint("═══════════════════════════════════════════════");
    debugPrint("🔍 ENVIRONMENT CONFIGURATION CHECK");
    debugPrint("═══════════════════════════════════════════════");
    debugPrint("📍 API_BASE_URL: ${dotenv.env['API_BASE_URL']}");
    debugPrint("📍 WEBSOCKET_URL: ${dotenv.env['WEBSOCKET_URL']}");
    debugPrint("═══════════════════════════════════════════════");
  } catch (e) {
    debugPrint("⚠️ Warning: Could not load .env file: $e");
    debugPrint("Using fallback configuration...");
    // Fallback configuration
    dotenv.testLoad(fileInput: '''
API_BASE_URL=http://localhost:3001
WEBSOCKET_URL=ws://localhost:3001
FIREBASE_PROJECT_ID=abrafleet-cec94
''');
  }

  // Initialize Backend Connection Manager
  final connectionManager = BackendConnectionManager();
  try {
    await connectionManager.initialize();
    print("✅ Backend Connection Manager initialized");
  } catch (e) {
    print("❌ Backend Connection Manager initialization failed: $e");
  }

  if (kDebugMode) {
    debugPrint("🔍 Debug mode is enabled");
  }

  // 🔥 INITIALIZE FIREBASE CORE (REQUIRED FOR FCM) - BOTH WEB AND MOBILE
  try {
    debugPrint('🔥 ========================================');
    if (kIsWeb) {
      debugPrint('🔥 INITIALIZING FIREBASE FOR WEB');
      debugPrint('🔥 ========================================');
      
      // Web: Firebase is initialized via firebase-config.js in index.html
      // Just create the FCM service which will use the existing Firebase instance
      _globalFcmService = FCMService();
      debugPrint('✅ FCM Service created for Web');
      debugPrint('✅ Firebase JS SDK will be used (initialized in index.html)');
      debugPrint('✅ Floating notifications will work on web!');
    } else {
      debugPrint('🔥 INITIALIZING FIREBASE FOR MOBILE');
      debugPrint('🔥 ========================================');
      
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('✅ Firebase initialized successfully for Mobile');
      
      // 🔥 CREATE GLOBAL FCM SERVICE INSTANCE FOR MOBILE
      _globalFcmService = FCMService();
      debugPrint('✅ FCM Service created for Mobile');
      debugPrint('✅ Floating notifications will work on mobile!');
    }
    debugPrint('🔥 ========================================');
  } catch (e) {
    debugPrint('❌ Error initializing Firebase: $e');
    debugPrint('⚠️ Continuing without Firebase - notifications may not work');
  }

  // ✅ CREATE JWT AUTH REPOSITORY INSTANCE WITH DIAGNOSTICS
  final jwtAuthRepo = JwtAuthRepositoryImpl();
  
  debugPrint('\n' + '🔍' * 80);
  debugPrint('🔍 AUTH REPOSITORY CREATION');
  debugPrint('🔍' * 80);
  debugPrint('Created Type: ${jwtAuthRepo.runtimeType}');
  debugPrint('Is JwtAuthRepositoryImpl: ${jwtAuthRepo is JwtAuthRepositoryImpl}');
  debugPrint('Is AuthRepository: ${jwtAuthRepo is AuthRepository}');
  debugPrint('Instance: $jwtAuthRepo');
  debugPrint('🔍' * 80 + '\n');

  runApp(
    MultiProvider(
      providers: [
        // ✅ JWT Authentication Repository - Using .value to provide existing instance
        Provider<AuthRepository>.value(value: jwtAuthRepo),
        
        // ✅ Also provide as concrete type for debugging
        Provider<JwtAuthRepositoryImpl>.value(value: jwtAuthRepo),

        // Backend Connection Manager
        Provider<BackendConnectionManager>(
          create: (_) => connectionManager,
        ),

        // API Service
        Provider<ApiService>(
          create: (_) => ApiService(),
        ),

        // Roster Service
        Provider<RosterService>(
          create: (context) => RosterService(
            apiService: context.read<ApiService>(),
          ),
        ),

        // Customer Provider
        ChangeNotifierProvider<CustomerProvider>(
          create: (_) => CustomerProvider()..initialize(),
        ),

        // Driver Provider
        ChangeNotifierProvider<DriverProvider>(
          create: (_) => DriverProvider(),
        ),

        // Vehicle Provider
        ChangeNotifierProvider<VehicleProvider>(
          create: (_) => VehicleProvider(),
        ),

        // Notification Provider
        ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider(),
        ),

        // 🔥 FCM Service Provider (mobile only - null on web)
        if (_globalFcmService != null)
          Provider<FCMService>.value(value: _globalFcmService!),
      ],
      child: const AbraFleetApp(),
    ),
  );
}

// ===================================================================
// MAIN APP WITH CTRL+A SUPPORT + FCM NAVIGATOR KEY + ROUTES
// ===================================================================
class AbraFleetApp extends StatefulWidget {
  const AbraFleetApp({super.key});

  @override
  State<AbraFleetApp> createState() => _AbraFleetAppState();
}

class _AbraFleetAppState extends State<AbraFleetApp> {
  bool _fcmInitialized = false;

  @override
  void initState() {
    super.initState();
    debugPrint('✅ AbraFleetApp initialized - FCM will start after login');
  }

  /// Initialize FCM after user logs in
  Future<void> _initializeFCMAfterLogin() async {
    if (_fcmInitialized) {
      debugPrint('⚠️  FCM already initialized');
      return;
    }

    // Skip FCM initialization on web
    if (_globalFcmService == null) {
      debugPrint('⚠️  FCM not available on web platform');
      return;
    }

    try {
      debugPrint('🔥 ========================================');
      debugPrint('🔥 INITIALIZING FCM AFTER LOGIN');
      debugPrint('🔥 ========================================');

      final success = await _globalFcmService!.initialize(
        onNotificationReceived: _handleForegroundNotification,
        onNotificationClicked: _handleNotificationClick,
      );

      if (success) {
        setState(() {
          _fcmInitialized = true;
        });
        debugPrint('✅ FCM initialized successfully after login');
      } else {
        debugPrint('❌ FCM initialization failed');
      }

      debugPrint('🔥 ========================================');
    } catch (e) {
      debugPrint('❌ Error initializing FCM: $e');
    }
  }

  // 🔥 SHOW FLOATING NOTIFICATION BANNER (TOP OVERLAY)
  void _handleForegroundNotification(Map<String, dynamic> notification) {
    debugPrint('\n' + '📩' * 40);
    debugPrint('📩 FOREGROUND NOTIFICATION RECEIVED IN MAIN.DART');
    debugPrint('   Title: ${notification['title']}');
    debugPrint('   Body: ${notification['body']}');
    debugPrint('   Type: ${notification['data']?['type']}');
    debugPrint('   Full notification data: $notification');
    debugPrint('📩' * 40);

    // Get the current context
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('❌ ERROR: No context available for notification overlay');
      debugPrint('   navigatorKey.currentContext is NULL');
      debugPrint('   Cannot show floating notification!');
      return;
    }

    debugPrint('✅ Context available, showing floating notification...');

    try {
      // Show floating top banner
      showOverlayNotification(
        (context) {
          debugPrint('🎨 Building NotificationOverlayWidget...');
          return NotificationOverlayWidget(
            title: notification['title'] ?? 'New Notification',
            body: notification['body'] ?? '',
            data: notification['data'] ?? {},
            onTap: () {
              debugPrint('👆 Notification tapped');
              // Dismiss overlay and handle navigation
              OverlaySupportEntry.of(context)?.dismiss();
              _handleNotificationClick(notification);
            },
            onDismiss: () {
              debugPrint('❌ Notification dismissed');
              OverlaySupportEntry.of(context)?.dismiss();
            },
          );
        },
        duration: const Duration(seconds: 5),
      );
      
      debugPrint('✅ showOverlayNotification called successfully');
      debugPrint('🎉 Floating notification should now be visible!');
    } catch (e, stackTrace) {
      debugPrint('❌ ERROR showing overlay notification: $e');
      debugPrint('   Stack trace: $stackTrace');
    }
    
    debugPrint('📩' * 40 + '\n');
  }

  // 🔥 ROLE-AWARE NOTIFICATION CLICK HANDLER
  void _handleNotificationClick(Map<String, dynamic> data) {
    debugPrint('\n' + '🔔' * 40);
    debugPrint('🔔 NOTIFICATION CLICKED');
    debugPrint('   Data: $data');
    debugPrint('🔔' * 40 + '\n');

    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('⚠️  No context available for navigation');
      return;
    }

    // Extract notification type
    final type = data['type'] ?? data['data']?['type'] ?? '';
    debugPrint('🎯 Notification type: $type');

    // 🔥 GET USER ROLE FOR ROLE-AWARE NAVIGATION
    String userRole = 'driver'; // Default fallback
    
    try {
      final authRepo = Provider.of<AuthRepository>(context, listen: false);
      // Get current user synchronously if available
      authRepo.user.listen((user) {
        if (user != null && user.role != null) {
          userRole = user.role.toString().toLowerCase().trim();
          debugPrint('👤 User role detected: $userRole');
        }
      });
    } catch (e) {
      debugPrint('⚠️  Could not get user role: $e');
    }

    // Handle different notification types based on user role
    switch (type) {
      // ========== DRIVER NOTIFICATIONS ==========
      case 'trip_assigned':
        if (userRole == 'driver') {
          final tripId = data['tripId'] ?? data['data']?['tripId'];
          final tripNumber = data['tripNumber'] ?? data['data']?['tripNumber'];

          debugPrint('🚗 Driver: Navigating to trip response screen');
          if (tripId != null) {
            Navigator.pushNamed(
              context,
              '/driver/trip-response',
              arguments: {
                'tripId': tripId,
                'tripNumber': tripNumber ?? 'Unknown',
                'tripData': data['data'] ?? data,
              },
            );
          }
        } else {
          _navigateToNotificationsScreen(context, userRole);
        }
        break;

      case 'route_assigned_driver':
      case 'driver_route_assignment':
      case 'roster_assigned':
      case 'vehicle_assigned':
      case 'roster_updated':
      case 'roster_cancelled':
      case 'payment_received':
      case 'shift_reminder':
      case 'document_expiring_soon':
      case 'document_expired':
        if (userRole == 'driver') {
          Navigator.pushNamed(context, '/driver/notifications');
        } else {
          _navigateToNotificationsScreen(context, userRole);
        }
        break;

      // ========== CUSTOMER NOTIFICATIONS ==========
      case 'trip_started':
      case 'eta_15min':
      case 'eta_5min':
      case 'driver_arrived':
      case 'trip_completed':
      case 'trip_delayed':
      case 'feedback_request':
      case 'feedback_reply':
      case 'pickup_reminder':
      case 'address_change_approved':
      case 'address_change_rejected':
      case 'leave_approved':
      case 'leave_rejected':
        if (userRole == 'customer') {
          Navigator.pushNamed(context, '/customer/notifications');
        } else {
          _navigateToNotificationsScreen(context, userRole);
        }
        break;

      case 'trip_driver_confirmed':
        if (userRole == 'customer') {
          Navigator.pushNamed(context, '/customer/trip-tracking');
        } else {
          _navigateToNotificationsScreen(context, userRole);
        }
        break;

      // ========== ADMIN NOTIFICATIONS ==========
      case 'trip_accepted_admin':
      case 'trip_declined_admin':
      case 'trip_created_admin':
      case 'sos_alert':
      case 'emergency_alert':
      case 'leave_request':
      case 'leave_request_pending':
      case 'driver_report':
      case 'customer_registration':
      case 'new_user_registered':
      case 'vehicle_maintenance':
      case 'maintenance_due':
      case 'roster_pending':
      case 'roster_assigned_admin':
        if (userRole == 'admin' || userRole == 'super_admin' || userRole == 'superadmin') {
          Navigator.pushNamed(context, '/admin/notifications');
        } else {
          _navigateToNotificationsScreen(context, userRole);
        }
        break;

      // ========== CLIENT NOTIFICATIONS ==========
      case 'roster_assignment_updated':
      case 'roster_bulk_import_completed':
      case 'roster_optimization_completed':
      case 'employee_bulk_import_completed':
      case 'employee_added':
      case 'employee_updated':
      case 'client_trip_confirmed':
      case 'trip_confirmed':
      case 'multiple_trips_assigned':
      case 'invoice_generated':
      case 'monthly_report_ready':
      case 'billing_summary_ready':
      case 'system_maintenance':
      case 'feature_update':
      case 'data_backup_completed':
      case 'feedback_received':
      case 'support_ticket_created':
      case 'support_ticket_resolved':
      case 'client_request':
      case 'vehicle_maintenance_due':
      case 'driver_unavailable':
      case 'route_optimization_failed':
      case 'capacity_exceeded':
      case 'admin_alert':
        if (userRole == 'client') {
          Navigator.pushNamed(context, '/client/notifications');
        } else {
          _navigateToNotificationsScreen(context, userRole);
        }
        break;

      // ========== COMMON NOTIFICATIONS ==========
      case 'trip_cancelled':
      case 'trip_updated':
      case 'system':
      case 'broadcast':
      case 'test':
        _navigateToNotificationsScreen(context, userRole);
        break;

      default:
        debugPrint('📬 Unknown notification type - navigate to role-specific screen');
        _navigateToNotificationsScreen(context, userRole);
    }
  }

  // Helper method to navigate to correct notifications screen based on role
  void _navigateToNotificationsScreen(BuildContext context, String role) {
    debugPrint('📱 Navigating to notifications screen for role: $role');
    
    switch (role.toLowerCase().trim()) {
      case 'driver':
        Navigator.pushNamed(context, '/driver/notifications');
        break;
      case 'customer':
        Navigator.pushNamed(context, '/customer/notifications');
        break;
      case 'admin':
      case 'super_admin':
      case 'superadmin':
        Navigator.pushNamed(context, '/admin/notifications');
        break;
      case 'client':
        Navigator.pushNamed(context, '/client/notifications');
        break;
      default:
        debugPrint('⚠️  Unknown role: $role, defaulting to driver notifications');
        Navigator.pushNamed(context, '/driver/notifications');
    }
  }

  @override
  Widget build(BuildContext context) {
    return OverlaySupport.global( // 🔥 Wrap with OverlaySupport
      child: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          // For Windows/Linux - Ctrl+A
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyA): 
              const SelectAllIntent(),
          // For Mac - Cmd+A
          LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyA): 
              const SelectAllIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            SelectAllIntent: CallbackAction<SelectAllIntent>(
              onInvoke: (SelectAllIntent intent) {
                // This enables Ctrl+A for focused TextField widgets
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: MaterialApp(
              title: 'Abra Travels Management',
              theme: AppTheme.lightTheme,
              navigatorKey: navigatorKey,  // ✅ Global navigator for FCM
              home: AuthWrapperWithFCM(
                onLoginSuccess: _initializeFCMAfterLogin,
              ),
              debugShowCheckedModeBanner: false,

              builder: (context, child) {
                ErrorWidget.builder = (FlutterErrorDetails details) {
                  return Container(); // Hide error widgets
                };
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
                  child: child!,
                );
              },

              // 🔥 CRITICAL: Named routes for FCM notification navigation - ALL ROLES
              routes: {
                // ========== DRIVER ROUTES ==========
                '/driver/trip-response': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
                  if (args == null) {
                    return const Scaffold(
                      body: Center(child: Text('Missing trip data')),
                    );
                  }
                  return DriverTripResponseScreen(
                    tripId: args['tripId'] ?? '',
                    tripNumber: args['tripNumber'] ?? 'Unknown',
                    tripData: args['tripData'] ?? {},
                  );
                },
                '/driver/notifications': (context) => const DriverNotificationsScreen(),
                
                // ========== CUSTOMER ROUTES ==========
                '/customer/notifications': (context) => const CustomerNotificationsScreen(),
                '/customer/trip-tracking': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
                  // TODO: Create CustomerTripTrackingScreen if needed
                  return const CustomerNotificationsScreen(); // Fallback for now
                },
                
                // ========== ADMIN ROUTES ==========
                '/admin/notifications': (context) => const AdminNotificationsScreen(),
                '/admin/trip-details': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
                  // TODO: Create AdminTripDetailsScreen if needed
                  return const AdminNotificationsScreen(); // Fallback for now
                },
                
                // ========== CLIENT ROUTES ==========
                '/client/notifications': (context) => const ClientNotificationsScreen(),
                
                // ========== COMMON ROUTES ==========
                '/notifications': (context) {
                  // Generic fallback - redirect to driver notifications
                  return const DriverNotificationsScreen();
                },
                '/trip-tracking': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
                  // TODO: Create general TripTrackingScreen
                  return const DriverNotificationsScreen(); // Fallback for now
                },
                '/trip-history': (context) {
                  // TODO: Create TripHistoryScreen
                  return const DriverNotificationsScreen(); // Fallback for now
                },
                '/roster-details': (context) {
                  final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
                  // TODO: Create RosterDetailsScreen
                  return const DriverNotificationsScreen(); // Fallback for now
                },
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ===================================================================
// JWT-BASED AUTH WRAPPER WITH FCM INITIALIZATION
// ===================================================================
class AuthWrapperWithFCM extends StatefulWidget {
  final Future<void> Function() onLoginSuccess;

  const AuthWrapperWithFCM({
    super.key,
    required this.onLoginSuccess,
  });

  @override
  State<AuthWrapperWithFCM> createState() => _AuthWrapperWithFCMState();
}

class _AuthWrapperWithFCMState extends State<AuthWrapperWithFCM> {
  UserEntity? _lastKnownUser;
  bool _isInitializing = true;
  bool _hasInitializedSession = false;
  bool _hasInitializedFCM = false;

  @override
  void initState() {
    super.initState();
    
    // ✅ ADD DIAGNOSTIC ON INIT
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final authRepo = Provider.of<AuthRepository>(context, listen: false);
        debugPrint('\n' + '🔍' * 80);
        debugPrint('🔍 AUTH WRAPPER - REPOSITORY CHECK');
        debugPrint('🔍' * 80);
        debugPrint('Retrieved Type: ${authRepo.runtimeType}');
        debugPrint('Is JwtAuthRepositoryImpl: ${authRepo is JwtAuthRepositoryImpl}');
        debugPrint('Instance: $authRepo');
        debugPrint('🔍' * 80 + '\n');
      }
    });
    
    _initializeAuthState();
  }

  /// Initialize JWT authentication state on app start
  Future<void> _initializeAuthState() async {
    try {
      final authRepo = Provider.of<AuthRepository>(context, listen: false);
      
      // Check if there's a stored JWT token
      final token = await authRepo.getAuthToken();
      
      if (token != null && token.isNotEmpty) {
        // Get current user with role
        final currentUser = await authRepo.getCurrentUserWithRole();
        
        if (currentUser != UserEntity.empty && currentUser.isAuthenticated) {
          debugPrint('✅ AuthWrapper: Found existing JWT authenticated user: ${currentUser.email}');
          setState(() {
            _lastKnownUser = currentUser;
            _isInitializing = false;
          });
          
          // Initialize session AND FCM
          await _initializeSession(context);
          await _initializeFCMForUser();
          return;
        }
      }
      
      debugPrint('ℹ️ AuthWrapper: No authenticated user found');
      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      debugPrint('❌ AuthWrapper: Error initializing auth state: $e');
      setState(() {
        _isInitializing = false;
      });
    }
  }

  /// Initialize FCM when user is logged in
  Future<void> _initializeFCMForUser() async {
    if (_hasInitializedFCM) {
      debugPrint('⚠️  FCM already initialized for this user');
      return;
    }

    try {
      debugPrint('🔥 Initializing FCM for logged-in user...');
      await widget.onLoginSuccess();
      setState(() {
        _hasInitializedFCM = true;
      });
    } catch (e) {
      debugPrint('❌ Error initializing FCM for user: $e');
    }
  }

  /// Initialize session with JWT token
  Future<void> _initializeSession(BuildContext context) async {
    if (_hasInitializedSession) return;
    
    final authRepo = Provider.of<AuthRepository>(context, listen: false);
    final connectionManager = Provider.of<BackendConnectionManager>(context, listen: false);

    try {
      debugPrint("🔄 AuthWrapper: Starting JWT session initialization...");
      
      final token = await authRepo.getAuthToken();
      
      if (token != null && token.isNotEmpty) {
        connectionManager.apiService.setAuthToken(token);
        debugPrint("✅ AuthWrapper: JWT session initialized. Token set in ApiService.");
        _hasInitializedSession = true;
      } else {
        debugPrint("⚠️ AuthWrapper: No JWT token found.");
        await authRepo.signOut();
      }
    } catch (e) {
      debugPrint("❌ AuthWrapper: Error in JWT session initialization: $e");
    }
  }

  /// Build main app with session initialization
  Widget _buildMainAppWithSession(BuildContext context, UserEntity user) {
    // Initialize session if not already done
    if (!_hasInitializedSession) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_hasInitializedSession) {
          _initializeSession(context).catchError((error) {
            debugPrint("❌ AuthWrapper: Error initializing session: $error");
          });
        }
      });
    }

    // Initialize FCM if not already done
    if (!_hasInitializedFCM && _hasInitializedSession) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_hasInitializedFCM) {
          _initializeFCMForUser().catchError((error) {
            debugPrint("❌ AuthWrapper: Error initializing FCM: $error");
          });
        }
      });
    }

    // Show the dashboard based on role
    final role = user.role.toString().toLowerCase().trim();
    debugPrint('✅ AuthWrapper - Role: "$role", Loading Dashboard...');

    if (role == 'customer' || role == 'driver' || role == 'admin' || role == 'super_admin' || role == 'superadmin') {
      return const MainAppShell();
    } else if (role == 'client') {
      return const ClientMainShell();
    } else {
      debugPrint('⚠️ AuthWrapper: Unknown role: $role');
      return const ContactSupportScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthRepository>(context);

    return StreamBuilder<UserEntity>(
      stream: auth.user,
      builder: (_, AsyncSnapshot<UserEntity> snapshot) {
        // Show splash screen during initial app load
        if (_isInitializing) {
          return const SplashScreen();
        }

        final UserEntity? user = snapshot.data;

        // Handle connection states
        if (snapshot.connectionState == ConnectionState.waiting) {
          // If we have a last known authenticated user, show their dashboard while waiting
          if (_lastKnownUser != null && _lastKnownUser!.isAuthenticated) {
            debugPrint('🔄 AuthWrapper: Using cached user while waiting for auth stream: ${_lastKnownUser!.email}');
            return _buildMainAppWithSession(context, _lastKnownUser!);
          }
          return const SplashScreen();
        }

        // Handle errors gracefully
        if (snapshot.hasError) {
          debugPrint('❌ AuthWrapper: Auth stream error: ${snapshot.error}');
          if (_lastKnownUser != null && _lastKnownUser!.isAuthenticated) {
            debugPrint('🔄 AuthWrapper: Using cached user despite auth stream error');
            return _buildMainAppWithSession(context, _lastKnownUser!);
          }
          return const WelcomeScreen();
        }

        // Update last known user if we have valid data
        if (user != null && user != UserEntity.empty && user.isAuthenticated) {
          _lastKnownUser = user;
        }

        // If user is null or empty, check cached user
        if (user == null || user == UserEntity.empty) {
          if (_lastKnownUser != null && _lastKnownUser!.isAuthenticated) {
            debugPrint('🔄 AuthWrapper: Auth stream returned null, but using cached authenticated user');
            return _buildMainAppWithSession(context, _lastKnownUser!);
          }
          
          // Clear cached user and show welcome screen
          _lastKnownUser = null;
          _hasInitializedSession = false;
          _hasInitializedFCM = false;
          return const WelcomeScreen();
        }

        // If user exists but has no role, show contact support
        if (user.role == null || user.role.toString().trim().isEmpty) {
          debugPrint('AuthWrapper: User has no role');
          return const ContactSupportScreen();
        }

        // User has valid role, proceed with session initialization
        return _buildMainAppWithSession(context, user);
      },
    );
  }
}

// ===================================================================
// ADMIN DASHBOARD
// ===================================================================
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            onPressed: () {
              Provider.of<AuthRepository>(context, listen: false).signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Welcome Admin!'),
            ElevatedButton(
              onPressed: () {
                Provider.of<AuthRepository>(context, listen: false).signOut();
              },
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================================================================
// CONTACT SUPPORT SCREEN
// ===================================================================
class ContactSupportScreen extends StatelessWidget {
  const ContactSupportScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    try {
      final authRepo = Provider.of<AuthRepository>(context, listen: false);
      await authRepo.signOut();

      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const WelcomeScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error signing out: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Support'),
        actions: [
          IconButton(
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.support_agent, size: 64, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              'Role Unclear',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Please contact support team for assistance'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _signOut(context),
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================================================================
// SELECT ALL INTENT - FOR CTRL+A SUPPORT
// ===================================================================
class SelectAllIntent extends Intent {
  const SelectAllIntent();
}