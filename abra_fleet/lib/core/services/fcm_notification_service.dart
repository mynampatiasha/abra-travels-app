// lib/core/services/fcm_notification_service.dart
// Flutter FCM Service - Complete Push Notification Handler
// Handles: Permission, Registration, Foreground/Background/Killed state notifications

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../app/config/api_config.dart';

// ============================================================================
// 🔥 TOP-LEVEL BACKGROUND MESSAGE HANDLER
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
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  String? _fcmToken;
  bool _isInitialized = false;

  // Callbacks
  Function(Map<String, dynamic>)? onNotificationReceived;
  Function(Map<String, dynamic>)? onNotificationClicked;

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

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/notifications/register-device'),
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
            'appVersion': '1.0.0', // Get from package_info_plus
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('✅ Device registered with backend');
        } else {
          debugPrint('⚠️  Backend registration failed: ${data['message']}');
        }
      } else {
        debugPrint('⚠️  Backend registration failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Backend registration error: $e');
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

      if (onNotificationReceived != null) {
        final notificationData = {
          'title': message.notification?.title ?? '',
          'body': message.notification?.body ?? '',
          'data': message.data,
          'type': 'foreground',
        };
        onNotificationReceived!(notificationData);
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
      'trip_assigned': '/driver/trip-response',
      'trip_accepted_admin': '/admin/trip-details',
      'trip_declined_admin': '/admin/trip-details',
      'trip_driver_confirmed': '/customer/trip-tracking',
      'trip_started': '/trip-tracking',
      'trip_completed': '/trip-history',
      'trip_cancelled': '/trip-history',
      'roster_assigned': '/roster-details',
      'general': '/notifications',
      'broadcast': '/notifications',
    };

    return screenMap[type] ?? '/notifications';
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
        Uri.parse('${ApiConfig.baseUrl}/api/notifications/unregister-device'),
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
        Uri.parse('${ApiConfig.baseUrl}/api/notifications/test'),
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
  // 🔑 GET AUTH TOKEN (USING FLUTTER SECURE STORAGE)
  // ========================================================================
  Future<String?> _getAuthToken() async {
    try {
      // Read auth token from secure storage
      final token = await _storage.read(key: 'authToken');
      
      if (token == null || token.isEmpty) {
        debugPrint('⚠️  No auth token found in secure storage');
        return null;
      }
      
      return token;
    } catch (e) {
      debugPrint('❌ Error reading auth token: $e');
      return null;
    }
  }

  // ========================================================================
  // 📊 GETTERS
  // ========================================================================
  String? get fcmToken => _fcmToken;
  bool get isInitialized => _isInitialized;
}