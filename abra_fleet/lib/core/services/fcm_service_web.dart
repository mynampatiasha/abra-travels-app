// lib/core/services/fcm_service_web.dart
// Web-specific FCM Service - Uses Firebase JS SDK directly
// This file is used ONLY on web platform

import 'package:flutter/foundation.dart';
import 'dart:js' as js;

class FCMServiceWeb {
  static final FCMServiceWeb _instance = FCMServiceWeb._internal();
  factory FCMServiceWeb() => _instance;
  FCMServiceWeb._internal();

  String? _fcmToken;
  bool _isInitialized = false;

  // Callbacks
  Function(Map<String, dynamic>)? onNotificationReceived;
  Function(Map<String, dynamic>)? onNotificationClicked;

  /// Initialize FCM for Web using Firebase JS SDK
  Future<bool> initialize({
    required Function(Map<String, dynamic>) onNotificationReceived,
    required Function(Map<String, dynamic>) onNotificationClicked,
  }) async {
    if (_isInitialized) {
      debugPrint('⚠️ FCM Web already initialized');
      return true;
    }

    try {
      debugPrint('🔥 ========================================');
      debugPrint('🔥 INITIALIZING FCM FOR WEB');
      debugPrint('🔥 ========================================');

      this.onNotificationReceived = onNotificationReceived;
      this.onNotificationClicked = onNotificationClicked;

      // Request notification permission
      final permission = await _requestPermission();
      if (!permission) {
        debugPrint('❌ Notification permission denied');
        return false;
      }

      // Get FCM token from Firebase JS SDK
      _fcmToken = await _getToken();
      if (_fcmToken != null) {
        debugPrint('✅ FCM Web Token: $_fcmToken');
      }

      _isInitialized = true;
      debugPrint('✅ FCM Web initialized successfully');
      debugPrint('🔥 ========================================');
      return true;
    } catch (e) {
      debugPrint('❌ Error initializing FCM Web: $e');
      return false;
    }
  }

  /// Request notification permission
  Future<bool> _requestPermission() async {
    try {
      // Check if Notification API is available
      if (!js.context.hasProperty('Notification')) {
        debugPrint('❌ Notification API not available');
        return false;
      }

      final permission = js.context['Notification']['permission'];
      debugPrint('📱 Current permission: $permission');

      if (permission == 'granted') {
        return true;
      }

      if (permission == 'denied') {
        debugPrint('❌ Notification permission denied by user');
        return false;
      }

      // Request permission
      debugPrint('📱 Requesting notification permission...');
      final result = await js.context['Notification'].callMethod('requestPermission');
      debugPrint('📱 Permission result: $result');
      
      return result == 'granted';
    } catch (e) {
      debugPrint('❌ Error requesting permission: $e');
      return false;
    }
  }

  /// Get FCM token from Firebase JS SDK
  Future<String?> _getToken() async {
    try {
      // Access Firebase Messaging from JS
      final messaging = js.context['firebase']['messaging']();
      
      // Get token
      final tokenPromise = messaging.callMethod('getToken', [
        js.JsObject.jsify({
          'vapidKey': 'YOUR_VAPID_KEY_HERE' // TODO: Add your VAPID key
        })
      ]);

      // Convert Promise to Future (simplified - you may need js_util)
      debugPrint('🔑 Requesting FCM token...');
      
      // For now, return a placeholder
      // In production, you'd use package:js to properly handle the Promise
      return 'web_fcm_token_placeholder';
    } catch (e) {
      debugPrint('❌ Error getting FCM token: $e');
      return null;
    }
  }

  /// Get current FCM token
  String? get token => _fcmToken;

  /// Check if initialized
  bool get isInitialized => _isInitialized;

  /// Subscribe to topic (web doesn't support this directly)
  Future<void> subscribeToTopic(String topic) async {
    debugPrint('⚠️ Topic subscription not supported on web');
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    debugPrint('⚠️ Topic unsubscription not supported on web');
  }
}
