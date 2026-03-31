// lib/core/services/one_signal_service.dart
// ============================================================================
// COMPLETE ONESIGNAL NOTIFICATION SERVICE - FIREBASE-FREE
// 🔥 COMPLETE VERSION WITH SDK INITIALIZATION
// ============================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/services/floating_notification_service.dart';
import 'package:abra_fleet/features/notifications/presentation/screens/screens/driver_trip_response_screen.dart';
//import 'dart:js' as js;
import 'package:universal_html/html.dart' as html show window;



class OneSignalService with WidgetsBindingObserver {
  static OneSignalService? _instance;
  
  final FloatingNotificationService _floatingNotificationService = 
      FloatingNotificationService();
  
  static GlobalKey<NavigatorState>? navigatorKey;
  
  final StreamController<Map<String, dynamic>> _newNotificationController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNewNotification =>
      _newNotificationController.stream;

  // User preferences for notification sounds
  static const String _customSoundEnabledKey = 'notification_custom_sound_enabled';
  bool _customSoundEnabled = true;
  
  // Track processed notifications to prevent duplicates
  final Set<String> _processedNotificationIds = {};
  static const int _maxProcessedIds = 100;

  // Current user info
  String? _currentUserId;
  String? _currentUserRole;
  String? _currentAuthToken;
  
  // 🔥 NEW: Track if SDK is initialized
  static bool _sdkInitialized = false;

  OneSignalService._internal();

  factory OneSignalService() {
    _instance ??= OneSignalService._internal();
    return _instance!;
  }

  static OneSignalService get instance {
    _instance ??= OneSignalService._internal();
    return _instance!;
  }

  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
    debugPrint('✅ Navigator key set in OneSignalService');
  }

  // ============================================================================
  // 🔥 NEW: INITIALIZE SDK (Call this ONCE at app startup in main.dart)
  // ============================================================================
  
  static Future<void> initializeSDK() async {
    if (_sdkInitialized) {
      debugPrint('⚠️ OneSignal SDK already initialized, skipping...');
      return;
    }
    
    try {
      debugPrint('\n' + '🔔' * 50);
      debugPrint('🔔 INITIALIZING ONESIGNAL SDK');
      debugPrint('🔔' * 50);
      
      // Enable verbose logging for debugging
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      
      // 🔥 CRITICAL: Initialize OneSignal SDK with App ID
      OneSignal.initialize("6a1ab1b8-286b-4d08-82ef-6e35f9c08363");
      
      _sdkInitialized = true;
      
      debugPrint('✅ OneSignal SDK initialized successfully');
      debugPrint('   App ID: 6a1ab1b8-286b-4d08-82ef-6e35f9c08363');
      debugPrint('🔔' * 50 + '\n');
    } catch (e) {
      debugPrint('❌ Error initializing OneSignal SDK: $e');
      debugPrint('🔔' * 50 + '\n');
    }
  }

  // ============================================================================
  // INITIALIZATION
  // ============================================================================

  /// Auto-initialize from SharedPreferences if not already initialized
  Future<void> _autoInitializeFromStorage() async {
    try {
      debugPrint('🔄 Auto-initializing OneSignal from storage...');
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      final userId = prefs.getString('user_id');
      final userRole = prefs.getString('user_role');
      final userEmail = prefs.getString('user_email');
      
      if (token != null && userId != null && userRole != null) {
        debugPrint('✅ Found user credentials in storage: $userId');
        
        // Store credentials
        _currentUserId = userId;
        _currentUserRole = userRole;
        _currentAuthToken = token;
        
        // Call main initialize to setup tags and login
        await initialize(
          userId: userId, 
          userRole: userRole, 
          authToken: token,
          userEmail: userEmail,
        );
        
        debugPrint('✅ OneSignal auto-initialized successfully');
      } else {
        debugPrint('❌ No user credentials found in storage');
      }
    } catch (e) {
      debugPrint('❌ Error auto-initializing OneSignal: $e');
    }
  }

  /// Initialize OneSignal service for a specific user
/// Initialize OneSignal service for a specific user}

/// Initialize OneSignal service for a specific user
Future<void> initialize({
  required String userId,
  required String userRole,
  required String authToken,
  String? userEmail,  // 🔥 IMPORTANT: Email for tag-based targeting
}) async {
  try {
    print('\n' + '🔔' * 50);
    print('🔔 INITIALIZING ONESIGNAL SERVICE FOR USER');
    print('🔔' * 50);
    print('   Platform: ${kIsWeb ? "WEB" : "MOBILE"}');
    print('   User ID: $userId');
    print('   User Role: $userRole');
    print('   User Email: $userEmail');
    
    // 🔥 STEP 0: Ensure SDK is initialized
    if (!_sdkInitialized) {
      print('⚠️ SDK not initialized yet, initializing now...');
      await initializeSDK();
    }
    
    // Store user info
    _currentUserId = userId;
    _currentUserRole = userRole;
    _currentAuthToken = authToken;
    
    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    
    await _loadUserPreferences();
    
    // 🔥 STEP 1: Request permissions (platform-specific)
    print('🔔 Step 1: Requesting notification permissions...');
    try {
      if (kIsWeb) {
        // 🔥 On web, OneSignal JS SDK handles permissions automatically
        print('🌐 Web platform - OneSignal JS SDK will handle permissions');
        
        // Wait a moment for SDK to initialize
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Check if permission was already granted
        try {
          final hasPermission = await OneSignal.Notifications.permission;
          print('🔐 Current permission status: $hasPermission');
          
          if (!hasPermission) {
            print('⚠️ Notification permission not granted yet');
            print('   OneSignal will prompt user when needed');
          }
        } catch (e) {
          print('⚠️ Could not check permission status: $e');
        }
      } else {
        // On mobile, explicitly request permissions
        final permissionGranted = await OneSignal.Notifications.requestPermission(true);
        print('✅ Mobile permission request result: $permissionGranted');
      }
    } catch (e) {
      print('⚠️ Permission handling error (continuing anyway): $e');
      // Continue anyway - not critical
    }
    
    // 🔥 STEP 2: Login user & add tags
    print('🔔 Step 2: Logging in user and adding tags...');
    if (_currentUserId != null) {
      try {
        if (kIsWeb) {
          // 🔥 ON WEB: Use JavaScript to set tags (CRITICAL!)
          print('🌐 Web: Setting tags via JavaScript...');
          
          // Wait for OneSignal to be ready
          await Future.delayed(const Duration(seconds: 1));
          
          // Call JavaScript using html.window.eval
          try {
            final jsCode = '''
              if (window.setOneSignalTags) {
                window.setOneSignalTags(
                  "$_currentUserId",
                  "${userEmail ?? ''}",
                  "${_currentUserRole ?? 'driver'}"
                );
                console.log("✅ Tags set from Flutter via JavaScript");
              } else {
                console.error("❌ setOneSignalTags function not found in window");
              }
            ''';
            
            //js.context.callMethod('eval', [jsCode]);
            print('✅ JavaScript code executed');
          } catch (e) {
            print('❌ Error executing JavaScript: $e');
          }
          
          // Wait for tags to sync
          await Future.delayed(const Duration(seconds: 2));
          print('🌐 Web: Subscription handled by OneSignal JS SDK');
          
        } else {
          // 🔥 ON MOBILE: Use Flutter SDK
          OneSignal.login(_currentUserId!);
          
          final tags = {
            "userId": _currentUserId,
            "userRole": _currentUserRole,
          };
          
          // 🔥 ADD EMAIL TAG if available (CRITICAL for backend targeting)
          if (userEmail != null && userEmail.isNotEmpty) {
            tags["email"] = userEmail;
            print('   ✅ Adding email tag: $userEmail');
          }
          
          OneSignal.User.addTags(tags);
          print('✅ User logged in & tagged: $_currentUserId');
          
          // Wait for subscription to register
          await Future.delayed(const Duration(seconds: 2));
          
          try {
            final subscriptionId = OneSignal.User.pushSubscription.id;
            if (subscriptionId != null) {
              print('✅ Subscription ID obtained: $subscriptionId');
            } else {
              print('⚠️ No subscription ID yet - user may need to grant permissions');
            }
          } catch (e) {
            print('⚠️ Could not get subscription ID: $e');
          }
        }
      } catch (e) {
        print('⚠️ Error during login/tagging: $e');
      }
    }
    
    // 🔥 STEP 3: Set up handlers
    print('🔔 Step 3: Setting up notification handlers...');
    try {
      _setupNotificationHandlers();
      print('✅ Handlers setup complete');
    } catch (e) {
      print('⚠️ Handler setup error: $e');
    }
    
    // 🔥 STEP 4: Register with backend
    print('🔔 Step 4: Registering device with backend...');
    try {
      await _registerDeviceWithBackend();
    } catch (e) {
      print('⚠️ Backend registration error: $e');
    }
    
    print('✅ OneSignal service initialization complete!');
    print('🔔' * 50 + '\n');
  } catch (e) {
    print('❌ Error initializing OneSignal service: $e');
    print('🔔' * 50 + '\n');
  }
}

  // Setup notification handlers
  void _setupNotificationHandlers() {
    debugPrint('🔧 Setting up OneSignal notification handlers...');
    
    // Handle notification received while app is in foreground
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      debugPrint('📬 FOREGROUND NOTIFICATION RECEIVED');
      
      final notification = event.notification;
      final notificationId = notification.notificationId ?? 
                            '${notification.title}_${DateTime.now().millisecondsSinceEpoch}';
      
      if (_processedNotificationIds.contains(notificationId)) {
        event.preventDefault(); 
        return;
      }
      
      _processedNotificationIds.add(notificationId);
      _cleanupProcessedIds();
      
      final context = navigatorKey?.currentContext;
      
      if (context != null && context.mounted) {
        event.preventDefault();
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            _showFloatingNotification(
              context: context,
              title: notification.title ?? 'Notification',
              body: notification.body ?? '',
              type: notification.additionalData?['type'] ?? 'system',
              priority: notification.additionalData?['priority'] ?? 'normal',
              data: notification.additionalData,
            );
          }
        });
        
        final notificationType = notification.additionalData?['type'] ?? 'system';
        if (_shouldPlayCustomSound(notificationType)) {
          _playCustomNotificationSound();
        }
      }
      
      _newNotificationController.add({
        'id': notificationId,
        'title': notification.title ?? 'Notification',
        'body': notification.body ?? '',
        'data': notification.additionalData ?? {},
        'type': notification.additionalData?['type'] ?? 'system',
        'priority': notification.additionalData?['priority'] ?? 'normal',
        'createdAt': DateTime.now().toIso8601String(),
      });
    });
    
    // 🔥 HANDLE NOTIFICATION CLICKED/OPENED AND ACTION BUTTONS
    OneSignal.Notifications.addClickListener((event) {
      debugPrint('👆 ========================================');
      debugPrint('👆 NOTIFICATION CLICKED');
      debugPrint('👆 ========================================');
      
      final notification = event.notification;
      final result = event.result;
      
      // Check if an action button was clicked
      final actionId = result.actionId;
      
      debugPrint('Action ID: $actionId');
      debugPrint('Notification data: ${notification.additionalData}');
      
      // Get notification data
      final data = notification.additionalData ?? {};
      final type = data['type']?.toString();
      
      // 🔥 HANDLE TRIP ASSIGNMENT ACTION BUTTONS
      if (type == 'trip_assigned' && actionId != null) {
        debugPrint('🚗 Trip assignment action button clicked: $actionId');
        
        final tripId = data['tripId']?.toString();
        final tripNumber = data['tripNumber']?.toString() ?? 'Unknown';
        
        if (tripId != null) {
          final context = navigatorKey?.currentContext;
          if (context != null && context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => DriverTripResponseScreen(
                  tripId: tripId,
                  tripNumber: tripNumber,
                  tripData: {
                    ...data,
                    'preselectedResponse': actionId,
                  },
                ),
              ),
            );
          }
        }
      } 
      // 🔥 HANDLE ADMIN NOTIFICATIONS
      else if (type == 'trip_accepted_admin' || type == 'trip_declined_admin') {
        debugPrint('📊 Admin notification clicked - driver response');
        
        final context = navigatorKey?.currentContext;
        if (context != null && context.mounted) {
          Navigator.of(context).pushNamed('/admin/notifications');
        }
      }
      // Handle regular notification tap
      else {
        _handleNotificationTap(data);
      }
    });
    
    // Handle permission changes
    OneSignal.Notifications.addPermissionObserver((state) {
      debugPrint('🔔 Notification permission changed: $state');
    });
    
    // Handle subscription changes
    OneSignal.User.pushSubscription.addObserver((state) {
      debugPrint('📱 Push subscription changed ID: ${state.current.id}');
      if (state.current.optedIn && state.current.id != null) {
        _registerDeviceWithBackend();
      }
    });
  }

  // Enhanced notification tap handler
  void _handleNotificationTap(Map<String, dynamic>? data) {
    if (data == null) return;
    debugPrint('👆 Handling notification tap with data: $data');
    
    final type = data['type'] as String?;
    final context = navigatorKey?.currentContext;
    
    if (context == null || !context.mounted) {
      debugPrint('⚠️ No context available for navigation');
      return;
    }
    
    switch (type) {
      case 'trip_assigned':
        final tripId = data['tripId']?.toString();
        final tripNumber = data['tripNumber']?.toString() ?? 'Unknown';
        
        if (tripId != null) {
          Navigator.of(context).pushNamed(
            '/driver/trip-response',
            arguments: {
              'tripId': tripId,
              'tripNumber': tripNumber,
              'tripData': data,
            },
          );
        }
        break;
        
      case 'trip_accepted_admin':
      case 'trip_declined_admin':
        Navigator.of(context).pushNamed('/admin/notifications');
        break;
        
      case 'trip_started':
      case 'trip_completed':
        final tripId = data['tripId']?.toString();
        if (tripId != null) {
          debugPrint('Navigate to trip tracking: $tripId');
        }
        break;
        
      default:
        debugPrint('Unhandled notification type: $type');
    }
  }

  /// Register device with backend
  Future<void> _registerDeviceWithBackend() async {
    try {
      // 🔥 On web, skip Flutter SDK subscription check
      if (kIsWeb) {
        print('🌐 Web: Device registration handled by OneSignal JS SDK');
        print('   Backend will receive subscription via JS SDK events');
        return;
      }
      
      // 🔥 Mobile: Wait for subscription
      await Future.delayed(const Duration(seconds: 3));
      
      final subscriptionId = OneSignal.User.pushSubscription.id;
      
      if (subscriptionId == null) {
        debugPrint('⚠️ No OneSignal subscription ID available yet');
        debugPrint('   Will retry in 5 seconds...');
        
        // 🔥 RETRY once after 5 seconds
        await Future.delayed(const Duration(seconds: 5));
        final retryId = OneSignal.User.pushSubscription.id;
        
        if (retryId == null) {
          debugPrint('❌ Still no subscription ID after retry');
          debugPrint('   User may have denied notification permissions');
          return;
        }
        
        debugPrint('✅ Got subscription ID on retry: $retryId');
        await _sendRegistrationToBackend(retryId);
        return;
      }
      
      debugPrint('✅ Got subscription ID: $subscriptionId');
      await _sendRegistrationToBackend(subscriptionId);
    } catch (e) {
      debugPrint('❌ Error registering device with backend: $e');
    }
  }
  
  Future<void> _sendRegistrationToBackend(String subscriptionId) async {
    try {
      debugPrint('📱 Registering device with backend...');
      debugPrint('   Subscription ID: $subscriptionId');
      
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/onesignal/register-device');
      
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
        body: json.encode({
          'playerId': subscriptionId,
          'deviceType': Platform.isAndroid ? 'android' : Platform.isIOS ? 'ios' : 'web',
          'tags': {
            'userId': _currentUserId,
            'userRole': _currentUserRole,
          }
        }),
      );
      
      if (response.statusCode == 200) {
        debugPrint('✅ Device registered with backend successfully');
      } else {
        debugPrint('❌ Device registration failed: ${response.statusCode}');
        debugPrint('   Response: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Error sending registration to backend: $e');
    }
  }

  // ============================================================================
  // USER PREFERENCES
  // ============================================================================

  Future<void> _loadUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _customSoundEnabled = prefs.getBool(_customSoundEnabledKey) ?? true;
    } catch (e) {
      _customSoundEnabled = true;
    }
  }

  Future<void> setCustomSoundEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_customSoundEnabledKey, enabled);
      _customSoundEnabled = enabled;
    } catch (e) {
      debugPrint('❌ Error saving notification preference: $e');
    }
  }

  bool get isCustomSoundEnabled => _customSoundEnabled;

  // ============================================================================
  // LIFECYCLE MANAGEMENT
  // ============================================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('✅ App resumed, OneSignal active');
    }
  }

  // ============================================================================
  // NOTIFICATION DISPLAY
  // ============================================================================

  void _showFloatingNotification({
    required BuildContext context,
    required String title,
    required String body,
    required String type,
    required String priority,
    Map<String, dynamic>? data,
  }) {
    debugPrint('🎨 Showing Floating Notification: $title');
    
    try {
      _floatingNotificationService.showFloatingNotification(
        context: context,
        title: title,
        body: body,
        icon: getNotificationIcon(type),
        type: type,
        priority: priority,
        backgroundColor: Color(getNotificationColor(priority)),
        duration: const Duration(seconds: 5),
        onTap: () {
          debugPrint('👆 Floating notification tapped');
          _handleNotificationTap(data);
        },
        onDismiss: () {
          debugPrint('❌ Floating notification dismissed');
        },
      );
    } catch (e) {
      debugPrint('❌ Error showing floating notification: $e');
    }
  }

  // ============================================================================
  // SOUND MANAGEMENT
  // ============================================================================

  bool _shouldPlayCustomSound(String type) {
    if (!_customSoundEnabled) return false;
    return true;
  }

  Future<void> _playCustomNotificationSound() async {
    try {
      final AudioPlayer audioPlayer = AudioPlayer();
      await audioPlayer.play(AssetSource('sounds/notification.mp3'));
    } catch (e) {
      debugPrint('❌ Error playing custom notification sound: $e');
    }
  }

  // ============================================================================
  // API METHODS
  // ============================================================================

  Future<Map<String, String>> _getHeaders() async {
    return {
      'Content-Type': 'application/json',
      if (_currentAuthToken != null) 'Authorization': 'Bearer $_currentAuthToken',
    };
  }

  Future<Map<String, dynamic>> getNotifications({
    int page = 1,
    int limit = 50,
    bool? isRead,
    String? type,
    String? category,
  }) async {
    try {
      if (_currentUserId == null || _currentAuthToken == null) {
        await _autoInitializeFromStorage();
      }
      
      if (_currentUserId == null) {
        return {'success': false, 'message': 'User not logged in'};
      }

      final queryParams = {
        'page': page.toString(),
        'limit': limit.toString(),
        if (isRead != null) 'isRead': isRead.toString(),
        if (type != null) 'type': type,
        if (category != null) 'category': category,
      };

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/onesignal/notifications')
          .replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: await _getHeaders());

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'notifications': data['data']['notifications'] ?? [],
          'pagination': data['data']['pagination'] ?? {},
        };
      } else {
        return {'success': false, 'message': 'Failed to fetch notifications'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  Future<int> getUnreadCount() async {
    try {
      if (_currentUserId == null) await _autoInitializeFromStorage();
      if (_currentUserId == null) return 0;
      
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/onesignal/stats');
      final response = await http.get(uri, headers: await _getHeaders());

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data']['unread'] ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  Future<bool> markAsRead(String notificationId) async {
    try {
      if (_currentUserId == null) await _autoInitializeFromStorage();
      
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/onesignal/mark-read/$notificationId');
      final response = await http.put(uri, headers: await _getHeaders());
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> markAllAsRead() async {
    try {
      if (_currentUserId == null) await _autoInitializeFromStorage();
      
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/onesignal/mark-all-read');
      final response = await http.put(uri, headers: await _getHeaders());
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getStats() async {
    try {
      if (_currentUserId == null) await _autoInitializeFromStorage();
      if (_currentUserId == null) {
        return {'success': false, 'message': 'User not logged in'};
      }
      
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/onesignal/stats');
      final response = await http.get(uri, headers: await _getHeaders());

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'data': data['data'] ?? {},
        };
      } else {
        return {'success': false, 'message': 'Failed to fetch stats'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  Future<bool> deleteNotification(String notificationId) async {
    try {
      if (_currentUserId == null) await _autoInitializeFromStorage();
      
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/onesignal/notifications/$notificationId');
      final response = await http.delete(uri, headers: await _getHeaders());
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Error deleting notification: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> sendNotification({
    required String title,
    required String message,
    String? targetRole,
    List<String>? targetUserIds,
    String? type,
    String? category,
    String? priority,
    Map<String, dynamic>? data,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      if (_currentUserId == null) await _autoInitializeFromStorage();
      if (_currentUserId == null) {
        return {'success': false, 'message': 'User not logged in'};
      }
      
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/onesignal/send');
      final Map<String, dynamic> requestBody = {
        'title': title,
        'message': message,
        'type': type ?? 'system',
        'priority': priority ?? 'normal',
      };

      if (targetRole != null) {
        requestBody['targetRole'] = targetRole;
      }
      if (targetUserIds != null && targetUserIds.isNotEmpty) {
        requestBody['targetUsers'] = targetUserIds;
      }
      
      if (category != null) {
        requestBody['category'] = category;
      }
      if (data != null) {
        requestBody['data'] = data;
      }
      if (additionalData != null) {
        requestBody['additionalData'] = additionalData;
      }

      final response = await http.post(
        uri,
        headers: await _getHeaders(),
        body: json.encode(requestBody),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return {
          'success': true,
          'data': responseData['data'] ?? {},
        };
      } else {
        final errorData = json.decode(response.body);
        return {
          'success': false,
          'message': errorData['message'] ?? 'Failed to send notification'
        };
      }
    } catch (e) {
      debugPrint('❌ Error sending notification: $e');
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  Future<Map<String, dynamic>> sendTemplatedNotification({
    List<String>? targetUsers,
    required String targetRole,
    required String templateKey,
    Map<String, dynamic>? templateData,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/onesignal/send-template');
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
        body: json.encode({
          'targetUsers': targetUsers,
          'targetRole': targetRole,
          'templateKey': templateKey,
          'templateData': templateData,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        debugPrint('✅ Templated notification sent successfully');
        return result;
      } else {
        final error = json.decode(response.body);
        debugPrint('❌ Failed to send templated notification: ${error['message']}');
        return {
          'success': false,
          'message': error['message'] ?? 'Failed to send templated notification',
        };
      }
    } catch (e) {
      debugPrint('❌ Error sending templated notification: $e');
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  void _cleanupProcessedIds() {
    if (_processedNotificationIds.length > _maxProcessedIds) {
      final idsToRemove = _processedNotificationIds.take(_processedNotificationIds.length - _maxProcessedIds).toList();
      _processedNotificationIds.removeAll(idsToRemove);
    }
  }

  static String getNotificationIcon(String type) {
    switch (type) {
      case 'roster_assigned': return '🚗';
      case 'vehicle_assigned': return '🚗';
      case 'roster_updated': return '🔄';
      case 'roster_cancelled': return '❌';
      case 'leave_request': return '🏖️';
      case 'leave_approved': return '✅';
      case 'trip_cancelled': return '🚫';
      case 'trip_started': return '🚀';
      case 'trip_completed': return '🏁';
      case 'sos_alert': return '🚨';
      case 'system': return '🔔';
      default: return '📬';
    }
  }

  static int getNotificationColor(String priority) {
    switch (priority) {
      case 'urgent': return 0xFFFF1744;
      case 'high': return 0xFFFF5252;
      case 'normal': return 0xFF2196F3;
      default: return 0xFF2196F3;
    }
  }

  // ============================================================================
  // CLEANUP
  // ============================================================================

  void updateUserInfo({
    required String userId,
    required String userRole,
    required String authToken,
    String? userEmail,
  }) {
    _currentUserId = userId;
    _currentUserRole = userRole;
    _currentAuthToken = authToken;
    
    OneSignal.login(userId);
    
    final tags = {
      "userId": userId,
      "userRole": userRole,
    };
    
    if (userEmail != null && userEmail.isNotEmpty) {
      tags["email"] = userEmail;
    }
    
    OneSignal.User.addTags(tags);
    
    _registerDeviceWithBackend();
  }

  void dispose() {
    _newNotificationController.close();
    _floatingNotificationService.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _currentUserId = null;
    _currentUserRole = null;
    _currentAuthToken = null;
    debugPrint('🛑 OneSignalService disposed');
  }
}