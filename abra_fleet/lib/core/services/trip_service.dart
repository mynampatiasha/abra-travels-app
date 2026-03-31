// File: lib/core/services/trip_service.dart
// Trip Management Service - Start/Complete trips with backend sync

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../app/config/api_config.dart';

class TripService {
  static String get baseUrl => ApiConfig.baseUrl;

  /// Start a trip - Updates status from 'assigned' to 'started'
  Future<Map<String, dynamic>> startTrip({
    required String tripId,
    String? notes,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        throw Exception('User not authenticated');
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/trips/$tripId/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'status': 'started',
          'notes': notes ?? 'Trip started by driver',
        }),
      );

      debugPrint('🚀 Start Trip Response: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': 'Trip started successfully',
          'trip': data['data'],
        };
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to start trip');
      }
    } catch (e) {
      debugPrint('❌ Error starting trip: $e');
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  /// Complete a trip - Updates status to 'completed'
  Future<Map<String, dynamic>> completeTrip({
    required String tripId,
    String? notes,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        throw Exception('User not authenticated');
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/trips/$tripId/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'status': 'completed',
          'notes': notes ?? 'Trip completed by driver',
        }),
      );

      debugPrint('🏁 Complete Trip Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': 'Trip completed successfully',
          'trip': data['data'],
        };
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to complete trip');
      }
    } catch (e) {
      debugPrint('❌ Error completing trip: $e');
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  /// Update trip to in-progress (when driver starts picking up customers)
  Future<Map<String, dynamic>> setTripInProgress({
    required String tripId,
    String? notes,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        throw Exception('User not authenticated');
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/trips/$tripId/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'status': 'in_progress',
          'notes': notes ?? 'Driver started customer pickups',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': 'Trip status updated to in-progress',
          'trip': data['data'],
        };
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to update trip status');
      }
    } catch (e) {
      debugPrint('❌ Error updating trip status: $e');
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  /// Cancel a trip
  Future<Map<String, dynamic>> cancelTrip({
    required String tripId,
    required String reason,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        throw Exception('User not authenticated');
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/trips/$tripId/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'status': 'cancelled',
          'notes': 'Cancelled by driver: $reason',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'success': true,
          'message': 'Trip cancelled successfully',
          'trip': data['data'],
        };
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to cancel trip');
      }
    } catch (e) {
      debugPrint('❌ Error cancelling trip: $e');
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  /// Get trip details
  Future<Map<String, dynamic>?> getTripDetails(String tripId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        throw Exception('User not authenticated');
      }
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/trips/$tripId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data'];
      }
    } catch (e) {
      debugPrint('❌ Error getting trip details: $e');
    }
    return null;
  }

  /// Update trip location (for real-time tracking)
  Future<bool> updateTripLocation({
    required String tripId,
    required double latitude,
    required double longitude,
    double? speed,
    double? heading,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) return false;
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/trips/$tripId/location'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'latitude': latitude,
          'longitude': longitude,
          'speed': speed,
          'heading': heading,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Error updating trip location: $e');
      return false;
    }
  }
}