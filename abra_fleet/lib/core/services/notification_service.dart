// lib/core/services/notification_service.dart
// ============================================================================
// DEPRECATED: This service is being replaced by OneSignalService
// Please use OneSignalService for all notification functionality
// ============================================================================
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/services/one_signal_service.dart';

/// DEPRECATED: Use OneSignalService instead
/// This service is maintained for backward compatibility only
class NotificationService with WidgetsBindingObserver {
  static NotificationService? _instance;
  
  // Use OneSignal service instead of Firebase
  final OneSignalService _oneSignalService = OneSignalService();
  
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

  NotificationService._internal();

  factory NotificationService() {
    _instance ??= NotificationService._internal();
    return _instance!;
  }

  static NotificationService get instance {
    _instance ??= NotificationService._internal();
    return _instance!;
  }

  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
    OneSignalService.setNavigatorKey(key);
    debugPrint('✅ Navigator key set in NotificationService (forwarded to OneSignal)');
  }

  // ========== USER PREFERENCES ==========

  /// Load user notification preferences
  Future<void> _loadUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _customSoundEnabled = prefs.getBool(_customSoundEnabledKey) ?? true;
      debugPrint('📱 Custom notification sound enabled: $_customSoundEnabled');
    } catch (e) {
      debugPrint('❌ Error loading notification preferences: $e');
      _customSoundEnabled = true;
    }
  }

  /// Enable or disable custom notification sounds
  Future<void> setCustomSoundEnabled(bool enabled) async {
    // Forward to OneSignal service
    await _oneSignalService.setCustomSoundEnabled(enabled);
    _customSoundEnabled = enabled;
  }

  /// Get current custom sound preference
  bool get isCustomSoundEnabled => _oneSignalService.isCustomSoundEnabled;

  // ========== INITIALIZATION ==========

  /// Initialize notification service (delegates to OneSignal)
  Future<void> initialize() async {
    try {
      debugPrint('🔔 Initializing NotificationService (OneSignal wrapper)...');
      
      // Add lifecycle observer
      WidgetsBinding.instance.addObserver(this);
      
      await _loadUserPreferences();
      
      // Get user info from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      final userId = prefs.getString('user_id');
      final userRole = prefs.getString('user_role');
      
      if (token != null && userId != null && userRole != null) {
        // Initialize OneSignal service
        await _oneSignalService.initialize(
          userId: userId,
          userRole: userRole,
          authToken: token,
        );
        
        // Subscribe to OneSignal notifications
        _oneSignalService.onNewNotification.listen((notification) {
          _newNotificationController.add(notification);
        });
      } else {
        debugPrint('⚠️ No user logged in, skipping OneSignal initialization');
      }
      
      debugPrint('✅ NotificationService initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing NotificationService: $e');
    }
  }

  // Lifecycle observer method
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('📱 App lifecycle state: $state');
  }

  // ========== API METHODS (Delegate to OneSignal) ==========

  /// Get authentication headers
  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Get notifications (delegates to OneSignal)
  Future<Map<String, dynamic>> getNotifications({
    int page = 1,
    int limit = 50,
    bool? isRead,
    String? type,
    String? category,
  }) async {
    return await _oneSignalService.getNotifications(
      page: page,
      limit: limit,
      isRead: isRead,
      type: type,
      category: category,
    );
  }

  /// Get unread count (delegates to OneSignal)
  Future<int> getUnreadCount({bool adminOnly = false}) async {
    return await _oneSignalService.getUnreadCount();
  }

  /// Get stats (delegates to OneSignal)
  Future<Map<String, dynamic>?> getStats() async {
    return await _oneSignalService.getStats();
  }

  /// Mark as read (delegates to OneSignal)
  Future<bool> markAsRead(String notificationId) async {
    return await _oneSignalService.markAsRead(notificationId);
  }

  /// Mark all as read (delegates to OneSignal)
  Future<bool> markAllAsRead() async {
    return await _oneSignalService.markAllAsRead();
  }

  /// Mark multiple as read (delegates to OneSignal)
  Future<bool> markMultipleAsRead(List<String> notificationIds) async {
    bool allSuccess = true;
    for (final id in notificationIds) {
      final success = await _oneSignalService.markAsRead(id);
      if (!success) allSuccess = false;
    }
    return allSuccess;
  }

  /// Delete notification (delegates to OneSignal)
  Future<bool> deleteNotification(String notificationId) async {
    return await _oneSignalService.deleteNotification(notificationId);
  }

  /// Delete all notifications (delegates to OneSignal)
  Future<bool> deleteAllNotifications() async {
    // OneSignal doesn't have delete all, so we skip this
    return true;
  }

  // ========== HELPER METHODS ==========

  /// Get notification icon
  static String getNotificationIcon(String type) {
    return OneSignalService.getNotificationIcon(type);
  }

  /// Get notification color
  static int getNotificationColor(String priority) {
    return OneSignalService.getNotificationColor(priority);
  }

  /// Dispose
  void dispose() {
    _newNotificationController.close();
    _oneSignalService.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }

  // Deprecated methods - kept for backward compatibility
  void stopListening() {
    debugPrint('⚠️ stopListening() is deprecated - OneSignal handles this automatically');
  }
}