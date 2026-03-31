// lib/core/services/fcm_service.dart
// Flutter FCM Service - Complete Push Notification Handler with Vibration + Heads-Up
// Handles: Permission, Registration, Foreground/Background/Killed state notifications
// 🔥 NEW: High-Importance Android Channel for Meesho/Flipkart-style floating notifications

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../app/config/api_config.dart';

// ============================================================================
// 🔥 FLUTTER LOCAL NOTIFICATIONS PLUGIN - For Heads-Up Notifications
// ============================================================================
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// ============================================================================
// 🔥 TOP-LEVEL BACKGROUND MESSAGE HANDLER - WITH LOCAL NOTIFICATION
// ============================================================================
// This MUST be a top-level function (not inside a class)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🔔 ========================================');
  debugPrint('🔔 BACKGROUND MESSAGE RECEIVED');
  debugPrint('🔔 ========================================');
  debugPrint('   Message ID: ${message.messageId}');
  debugPrint('   Title: ${message.notification?.title}');
  debugPrint('   Body: ${message.notification?.body}');
  debugPrint('   Data: ${message.data}');
  debugPrint('🔔 ========================================');

  // 🔥 CRITICAL: Show local notification for heads-up display
  await _showLocalNotification(
    title: message.notification?.title ?? 'New Notification',
    body: message.notification?.body ?? '',
    payload: jsonEncode(message.data),
  );
}

// ============================================================================
// 🔥 SHOW LOCAL NOTIFICATION - Heads-Up Style (Background/Killed State)
// ============================================================================
Future<void> _showLocalNotification({
  required String title,
  required String body,
  required String payload,
}) async {
  try {
    debugPrint('📱 Showing local notification (heads-up)...');
    debugPrint('   Title: $title');
    debugPrint('   Body: $body');

    // 🔥 Android Notification Details - HIGH IMPORTANCE for heads-up
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'high_priority_channel', // Must match channel ID in backend
      'High Priority Notifications',
      channelDescription: 'Important notifications that require immediate attention',
      importance: Importance.max, // CRITICAL: Max importance for heads-up
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('notification'), // Custom sound
      icon: '@mipmap/ic_launcher', // App icon
      color: const Color(0xFF0D47A1), // Blue color
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'Abra Travels',
      ),
      // 🔥 CRITICAL: These flags ensure heads-up display
      fullScreenIntent: false,
      category: AndroidNotificationCategory.message,
      visibility: NotificationVisibility.public,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique ID
      title,
      body,
      notificationDetails,
      payload: payload,
    );

    debugPrint('✅ Local notification shown successfully');
  } catch (e) {
    debugPrint('❌ Error showing local notification: $e');
  }
}

// ============================================================================
// 📱 FCM SERVICE CLASS
// ============================================================================
class FCMService {
  // Singleton pattern
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  String? _fcmToken;
  bool _isInitialized = false;

  // Callbacks
  Function(Map<String, dynamic>)? onNotificationReceived;
  Function(Map<String, dynamic>)? onNotificationClicked;

  // 🔥 API Configuration - Uses centralized config from .env
  static String get API_BASE_URL => ApiConfig.baseUrl;

  // ========================================================================
  // 🚀 INITIALIZE FCM
  // ========================================================================
  Future<bool> initialize({
    required Function(Map<String, dynamic>) onNotificationReceived,
    required Function(Map<String, dynamic>) onNotificationClicked,
  }) async {
    if (_isInitialized) {
      debugPrint('⚠️  FCM already initialized');
      return true;
    }

    this.onNotificationReceived = onNotificationReceived;
    this.onNotificationClicked = onNotificationClicked;

    try {
      debugPrint('\n' + '🔔' * 40);
      debugPrint('🔔 INITIALIZING FCM SERVICE');
      debugPrint('🔔' * 40);

      // 🔥 STEP 0: Initialize flutter_local_notifications FIRST
      await _initializeLocalNotifications();

      // Step 1: Request permission
      final hasPermission = await _requestPermission();
      if (!hasPermission) {
        debugPrint('❌ FCM: Permission denied');
        return false;
      }

      // Step 2: Get FCM token
      _fcmToken = await _getFCMToken();
      if (_fcmToken == null) {
        debugPrint('❌ FCM: Failed to get token');
        return false;
      }

      debugPrint('✅ FCM Token: ${_fcmToken!.substring(0, 30)}...');

      // Step 3: Register with backend
      await _registerDeviceWithBackend(_fcmToken!);

      // Step 4: Setup listeners
      _setupNotificationListeners();

      // Step 5: Handle initial notification (app opened from killed state)
      await _handleInitialNotification();

      // Step 6: Setup background handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      _isInitialized = true;
      debugPrint('✅ FCM SERVICE INITIALIZED SUCCESSFULLY');
      debugPrint('🔔' * 40 + '\n');

      return true;
    } catch (e) {
      debugPrint('❌ FCM initialization failed: $e');
      return false;
    }
  }

  // ========================================================================
  // 🔥 INITIALIZE FLUTTER LOCAL NOTIFICATIONS - HIGH IMPORTANCE CHANNEL
  // ========================================================================
  Future<void> _initializeLocalNotifications() async {
    try {
      debugPrint('🔔 Initializing flutter_local_notifications...');

      // 🔥 Android Initialization Settings - HIGH IMPORTANCE CHANNEL
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
      );

      // Initialize plugin
      await flutterLocalNotificationsPlugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('📱 Local notification tapped');
          debugPrint('   Payload: ${response.payload}');

          // Handle notification tap
          if (response.payload != null && response.payload!.isNotEmpty) {
            try {
              final data = jsonDecode(response.payload!);
              if (onNotificationClicked != null) {
                onNotificationClicked!({
                  'data': data,
                  'type': data['type'] ?? 'general',
                });
              }
            } catch (e) {
              debugPrint('❌ Error parsing notification payload: $e');
            }
          }
        },
      );

      // 🔥 CRITICAL: Create HIGH IMPORTANCE Android Notification Channel
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'high_priority_channel', // ID - must match backend
        'High Priority Notifications', // Name shown in settings
        description: 'Important notifications that require immediate attention',
        importance: Importance.max, // CRITICAL: Max importance for heads-up
        playSound: true,
        enableVibration: true,
        showBadge: true,
        sound: RawResourceAndroidNotificationSound('notification'),
      );

      // Create the channel on the device
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      debugPrint('✅ flutter_local_notifications initialized');
      debugPrint('✅ High-importance channel created: high_priority_channel');
      debugPrint('   - Importance: MAX (Heads-up enabled)');
      debugPrint('   - Sound: Enabled');
      debugPrint('   - Vibration: Enabled');
    } catch (e) {
      debugPrint('❌ Local notifications initialization failed: $e');
    }
  }

  // ========================================================================
  // 📳 VIBRATE PHONE
  // ========================================================================
  Future<void> _vibratePhone() async {
    try {
      // Check if device has vibration capability
      if (await Vibration.hasVibrator() ?? false) {
        // Pattern: wait 0ms, vibrate 200ms, wait 100ms, vibrate 200ms
        await Vibration.vibrate(
          pattern: [0, 200, 100, 200],
          intensities: [0, 128, 0, 255], // iOS only
        );
        debugPrint('📳 Phone vibrated');
      }
    } catch (e) {
      debugPrint('⚠️ Vibration error: $e');
    }
  }

  // ========================================================================
  // 🔐 REQUEST PERMISSION
  // ========================================================================
  Future<bool> _requestPermission() async {
    try {
      debugPrint('🔐 Requesting notification permission...');

      final settings = await _fcm.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ User granted notification permission');
        return true;
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('✅ User granted provisional notification permission');
        return true;
      } else {
        debugPrint('❌ User declined notification permission');
        return false;
      }
    } catch (e) {
      debugPrint('❌ Permission request failed: $e');
      return false;
    }
  }

  // ========================================================================
  // 🎫 GET FCM TOKEN
  // ========================================================================
  Future<String?> _getFCMToken() async {
    try {
      debugPrint('🎫 Getting FCM token...');

      final token = await _fcm.getToken();

      if (token != null) {
        debugPrint('✅ FCM token retrieved successfully');
        return token;
      } else {
        debugPrint('❌ FCM token is null');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Get FCM token failed: $e');
      return null;
    }
  }

  // ========================================================================
  // 📤 REGISTER DEVICE WITH BACKEND
  // ========================================================================
  Future<void> _registerDeviceWithBackend(String deviceToken) async {
    try {
      debugPrint('📤 Registering device with backend...');
      debugPrint('   API URL: $API_BASE_URL/api/notifications/register-device');

      // Get auth token from your auth service
      final authToken = await _getAuthToken();
      if (authToken == null) {
        debugPrint('⚠️  No auth token - device not registered');
        return;
      }

      final deviceType = defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : defaultTargetPlatform == TargetPlatform.android
              ? 'android'
              : 'web';

      debugPrint('   Device Type: $deviceType');
      debugPrint('   Token (first 30 chars): ${deviceToken.substring(0, 30)}...');

      final response = await http.post(
        Uri.parse('$API_BASE_URL/api/notifications/register-device'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'deviceToken': deviceToken,
          'deviceType': deviceType,
          'deviceInfo': {
            'platform': defaultTargetPlatform.name,
            'os': defaultTargetPlatform.name,
            'appVersion': '1.0.0',
          }
        }),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Registration timeout - check if backend is running');
        },
      );

      debugPrint('   Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('✅ Device registered with backend');
        } else {
          debugPrint('⚠️  Backend registration failed: ${data['message']}');
        }
      } else {
        debugPrint('⚠️  Backend registration failed: ${response.statusCode}');
        debugPrint('   Response: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Backend registration error: $e');
      debugPrint('   Make sure backend is running at: $API_BASE_URL');
    }
  }

  // ========================================================================
  // 🔔 SETUP NOTIFICATION LISTENERS
  // ========================================================================
  void _setupNotificationListeners() {
    debugPrint('🔔 Setting up notification listeners...');

    // ======== FOREGROUND NOTIFICATIONS ========
    // When app is OPEN and notification arrives
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('\n' + '📩' * 40);
      debugPrint('📩 FOREGROUND NOTIFICATION RECEIVED');
      debugPrint('📩' * 40);
      debugPrint('   Title: ${message.notification?.title}');
      debugPrint('   Body: ${message.notification?.body}');
      debugPrint('   Data: ${message.data}');
      debugPrint('📩' * 40 + '\n');

      // 📳 Vibrate on notification
      _vibratePhone();

      // 🔥 SHOW LOCAL NOTIFICATION (for heads-up even in foreground)
      _showLocalNotification(
        title: message.notification?.title ?? 'New Notification',
        body: message.notification?.body ?? '',
        payload: jsonEncode(message.data),
      );

      // 🔥 CRITICAL: Always call the callback to show floating notification
      if (onNotificationReceived != null) {
        debugPrint('🔥 Calling onNotificationReceived callback...');
        final notificationData = {
          'title': message.notification?.title ?? 'New Notification',
          'body': message.notification?.body ?? '',
          'data': message.data,
          'type': 'foreground',
        };
        
        try {
          onNotificationReceived!(notificationData);
          debugPrint('✅ Callback invoked successfully');
        } catch (e) {
          debugPrint('❌ Error invoking callback: $e');
        }
      } else {
        debugPrint('⚠️  WARNING: onNotificationReceived callback is NULL!');
        debugPrint('⚠️  Floating notification will NOT appear!');
      }
    });

    // ======== BACKGROUND NOTIFICATIONS (APP IN BACKGROUND) ========
    // When app is in BACKGROUND and notification is clicked
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('\n' + '🔔' * 40);
      debugPrint('🔔 BACKGROUND NOTIFICATION CLICKED');
      debugPrint('🔔' * 40);
      debugPrint('   Title: ${message.notification?.title}');
      debugPrint('   Body: ${message.notification?.body}');
      debugPrint('   Data: ${message.data}');
      debugPrint('🔔' * 40 + '\n');

      if (onNotificationClicked != null) {
        _handleNotificationClick(message);
      }
    });

    // ======== TOKEN REFRESH ========
    _fcm.onTokenRefresh.listen((String newToken) {
      debugPrint('🔄 FCM Token refreshed');
      _fcmToken = newToken;
      _registerDeviceWithBackend(newToken);
    });

    debugPrint('✅ Notification listeners setup complete');
  }

  // ========================================================================
  // 🔍 HANDLE INITIAL NOTIFICATION (APP OPENED FROM KILLED STATE)
  // ========================================================================
  Future<void> _handleInitialNotification() async {
    try {
      final RemoteMessage? initialMessage = await _fcm.getInitialMessage();

      if (initialMessage != null) {
        debugPrint('\n' + '🚀' * 40);
        debugPrint('🚀 APP OPENED FROM KILLED STATE BY NOTIFICATION');
        debugPrint('🚀' * 40);
        debugPrint('   Title: ${initialMessage.notification?.title}');
        debugPrint('   Body: ${initialMessage.notification?.body}');
        debugPrint('   Data: ${initialMessage.data}');
        debugPrint('🚀' * 40 + '\n');

        if (onNotificationClicked != null) {
          // Delay to ensure app is fully loaded
          Future.delayed(const Duration(seconds: 1), () {
            _handleNotificationClick(initialMessage);
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Check initial notification error: $e');
    }
  }

  // ========================================================================
  // 🎯 HANDLE NOTIFICATION CLICK
  // ========================================================================
  void _handleNotificationClick(RemoteMessage message) {
    final data = message.data;
    final notificationType = data['type'] ?? 'general';

    debugPrint('🎯 Handling notification click...');
    debugPrint('   Type: $notificationType');
    debugPrint('   Data: $data');

    // Extract navigation data
    final navigationData = {
      'type': notificationType,
      'title': message.notification?.title ?? data['title'] ?? '',
      'body': message.notification?.body ?? data['body'] ?? '',
      'data': data,
      
      // Screen routing
      'screen': _getScreenForNotificationType(notificationType),
      'params': {
        'id': data['tripId'] ?? data['entityId'],
        ...data,
      }
    };

    // Call the navigation handler
    if (onNotificationClicked != null) {
      onNotificationClicked!(navigationData);
    }
  }

  // ========================================================================
  // 🗺️ MAP NOTIFICATION TYPE TO SCREEN
  // ========================================================================
  String _getScreenForNotificationType(String type) {
    const screenMap = {
      // Driver screens
      'trip_assigned': '/driver/trip-response',
      'route_assigned_driver': '/driver/notifications',
      'driver_route_assignment': '/driver/notifications',
      'roster_assigned': '/driver/notifications',
      'vehicle_assigned': '/driver/notifications',
      
      // Customer screens
      'trip_started': '/customer/notifications',
      'eta_15min': '/customer/notifications',
      'eta_5min': '/customer/notifications',
      'driver_arrived': '/customer/notifications',
      'trip_completed': '/customer/notifications',
      'feedback_request': '/customer/notifications',
      'trip_driver_confirmed': '/customer/trip-tracking',
      
      // Admin screens
      'trip_accepted_admin': '/admin/notifications',
      'trip_declined_admin': '/admin/notifications',
      'trip_created_admin': '/admin/notifications',
      'sos_alert': '/admin/notifications',
      'leave_request': '/admin/notifications',
      
      // Common
      'trip_cancelled': '/notifications',
      'general': '/notifications',
      'broadcast': '/notifications',
    };

    return screenMap[type] ?? '/driver/notifications';
  }

  // ========================================================================
  // 🔕 UNREGISTER DEVICE (ON LOGOUT)
  // ========================================================================
  Future<void> unregisterDevice() async {
    try {
      debugPrint('🔕 Unregistering device...');

      final authToken = await _getAuthToken();
      if (authToken == null || _fcmToken == null) {
        debugPrint('⚠️  Cannot unregister - missing token');
        return;
      }

      await http.delete(
        Uri.parse('$API_BASE_URL/api/notifications/unregister-device'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode({
          'deviceToken': _fcmToken,
        }),
      );

      debugPrint('✅ Device unregistered');
      _isInitialized = false;
    } catch (e) {
      debugPrint('❌ Unregister device error: $e');
    }
  }

  // ========================================================================
  // 🧪 SEND TEST NOTIFICATION
  // ========================================================================
  Future<Map<String, dynamic>> sendTestNotification() async {
    try {
      final authToken = await _getAuthToken();
      if (authToken == null) {
        return {
          'success': false,
          'message': 'No auth token',
        };
      }

      final response = await http.post(
        Uri.parse('$API_BASE_URL/api/notifications/test'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        return {
          'success': false,
          'message': 'Request failed: ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('❌ Test notification error: $e');
      return {
        'success': false,
        'message': 'Error: $e',
      };
    }
  }

  // ========================================================================
  // 🔑 GET AUTH TOKEN (FROM YOUR AUTH SYSTEM)
  // ========================================================================
  Future<String?> _getAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      if (token == null || token.isEmpty) {
        debugPrint('⚠️  No auth token found in SharedPreferences');
        return null;
      }
      
      return token;
    } catch (e) {
      debugPrint('❌ Error getting auth token: $e');
      return null;
    }
  }

  // ========================================================================
  // 📊 GETTERS
  // ========================================================================
  String? get fcmToken => _fcmToken;
  bool get isInitialized => _isInitialized;
}