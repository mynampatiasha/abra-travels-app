// lib/core/services/client_notification_service.dart
// ============================================================================
// DEPRECATED: This service is being replaced by OneSignalService
// Please use OneSignalService for all notification functionality
// ============================================================================

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/core/services/one_signal_service.dart';

/// DEPRECATED: Use OneSignalService instead
class ClientNotificationService {
  static final ClientNotificationService _instance = ClientNotificationService._internal();
  factory ClientNotificationService() => _instance;
  ClientNotificationService._internal();

  // Use OneSignal service instead
  final OneSignalService _oneSignalService = OneSignalService();
  final _audioPlayer = AudioPlayer();
  final Set<String> _shownNotifications = {};
  
  /// Setup notification listener (delegates to OneSignal)
  Future<void> setupListener(BuildContext context) async {
    debugPrint('⚠️ ClientNotificationService.setupListener() is deprecated');
    debugPrint('   Please use OneSignalService.initialize() instead');
    
    // Get user info from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    final userId = prefs.getString('user_id');
    final userRole = prefs.getString('user_role');
    
    if (token == null || userId == null || userRole == null) {
      debugPrint('❌ No user logged in');
      return;
    }

    // Initialize OneSignal if not already initialized
    await _oneSignalService.initialize(
      userId: userId,
      userRole: userRole,
      authToken: token,
    );
    
    // Subscribe to OneSignal notifications
    _oneSignalService.onNewNotification.listen((notification) {
      final notificationId = notification['id'] ?? '';
      if (_shownNotifications.contains(notificationId)) {
        return;
      }
      _shownNotifications.add(notificationId);
      
      // Play notification sound
      _playNotificationSound();
      
      // Show floating notification using OneSignal's built-in display
      debugPrint('📬 Notification received: ${notification['title']}');
    });
  }

  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('Notification.mp3'));
    } catch (e) {
      debugPrint('Error playing notification sound: $e');
    }
  }

  // Deprecated methods - kept for backward compatibility
  void _showFloatingNotification(
    BuildContext context, {
    required String title,
    required String body,
    required String type,
    required String priority,
  }) {
    debugPrint('⚠️ _showFloatingNotification() is deprecated');
    debugPrint('   OneSignal handles notification display automatically');
  }

  IconData _getNotificationIcon(String type) {
    switch (type) {
      case 'leave_request':
        return Icons.beach_access;
      case 'leave_approved':
        return Icons.check_circle;
      case 'leave_rejected':
        return Icons.cancel;
      case 'roster_assigned':
        return Icons.calendar_month;
      case 'trip_cancelled':
        return Icons.cancel_schedule_send;
      default:
        return Icons.notifications;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'urgent':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'normal':
        return const Color(0xFF2563eb);
      case 'low':
        return Colors.grey;
      default:
        return const Color(0xFF2563eb);
    }
  }

  void dispose() {
    _audioPlayer.dispose();
  }
}