// lib/core/services/trip_notification_service.dart
// ============================================================================
// DEPRECATED: This service is being replaced by OneSignalService
// Please use OneSignalService for all notification functionality
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DEPRECATED: Use OneSignalService instead
class TripNotificationService {
  static final TripNotificationService _instance = TripNotificationService._internal();
  factory TripNotificationService() => _instance;
  TripNotificationService._internal();

  final Set<String> _acknowledgedResponses = {};
  
  // Callback for when driver responds to trip
  Function(Map<String, dynamic>)? onDriverResponse;

  /// Initialize trip notification listener (deprecated)
  void initialize({Function(Map<String, dynamic>)? onDriverResponse}) {
    debugPrint('⚠️ TripNotificationService.initialize() is deprecated');
    debugPrint('   Please use OneSignalService for trip notifications');
    this.onDriverResponse = onDriverResponse;
  }

  /// Show driver response notification
  void showDriverResponseNotification(
    BuildContext context, 
    Map<String, dynamic> response
  ) {
    final isAccepted = response['response'] == 'accept';
    final driverName = response['driverName'] ?? 'Driver';
    final tripId = response['tripId'] ?? 'Unknown';
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isAccepted ? Icons.check_circle : Icons.cancel,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isAccepted 
                        ? '✅ Trip Accepted' 
                        : '❌ Trip Declined',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    '$driverName ${isAccepted ? 'accepted' : 'declined'} Trip $tripId',
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (!isAccepted && response['reason'] != null)
                    Text(
                      'Reason: ${response['reason']}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: isAccepted ? Colors.green : Colors.red,
        duration: Duration(seconds: isAccepted ? 4 : 6),
        action: SnackBarAction(
          label: 'VIEW',
          textColor: Colors.white,
          onPressed: () {
            // Navigate to trip details or trips list
          },
        ),
      ),
    );
  }

  /// Get recent trip responses from backend
  Future<List<Map<String, dynamic>>> getRecentTripResponses() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      if (token == null || token.isEmpty) return [];

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/trips?limit=50'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final trips = List<Map<String, dynamic>>.from(data['data'] ?? []);
        
        // Filter trips with driver responses
        return trips.where((trip) => 
          trip['driverResponse'] != null && 
          trip['driverResponseTime'] != null
        ).toList();
      }
    } catch (e) {
      debugPrint('Error getting recent trip responses: $e');
    }
    return [];
  }

  /// Check for pending driver responses
  Future<int> getPendingResponsesCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      if (token == null || token.isEmpty) return 0;

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/trips?status=assigned'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final trips = List<Map<String, dynamic>>.from(data['data'] ?? []);
        return trips.length;
      }
    } catch (e) {
      debugPrint('Error getting pending responses count: $e');
    }
    return 0;
  }

  /// Dispose resources
  void dispose() {
    _acknowledgedResponses.clear();
  }
}

/// Trip response model for type safety
class TripResponse {
  final String id;
  final String tripId;
  final String driverId;
  final String driverName;
  final String response; // 'accept' or 'decline'
  final String? reason;
  final DateTime responseTime;

  TripResponse({
    required this.id,
    required this.tripId,
    required this.driverId,
    required this.driverName,
    required this.response,
    this.reason,
    required this.responseTime,
  });

  factory TripResponse.fromMap(Map<String, dynamic> map) {
    return TripResponse(
      id: map['id'] ?? '',
      tripId: map['tripId'] ?? '',
      driverId: map['driverId'] ?? '',
      driverName: map['driverName'] ?? '',
      response: map['response'] ?? '',
      reason: map['reason'],
      responseTime: map['responseTime'] is String 
          ? DateTime.parse(map['responseTime'])
          : map['responseTime'] ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tripId': tripId,
      'driverId': driverId,
      'driverName': driverName,
      'response': response,
      'reason': reason,
      'responseTime': responseTime.toIso8601String(),
    };
  }

  bool get isAccepted => response == 'accept';
  bool get isDeclined => response == 'decline';
}