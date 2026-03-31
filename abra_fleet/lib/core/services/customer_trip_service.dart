// File: lib/core/services/customer_trip_service.dart
// Customer Trip Service - Fetches actual trip data with Trip-XXXXX IDs

import 'package:flutter/material.dart';
import 'package:abra_fleet/core/services/api_service.dart';

class CustomerTripService {
  final ApiService _apiService;

  CustomerTripService({required ApiService apiService}) : _apiService = apiService;

  /// Get all trips for the authenticated customer
  Future<List<Map<String, dynamic>>> getAllTrips() async {
    try {
      debugPrint('📥 CustomerTripService: Fetching all customer trips');
      
      final response = await _apiService.get('/api/trips/customer/all');
      
      if (response['success'] == true) {
        final trips = List<Map<String, dynamic>>.from(response['data'] ?? []);
        debugPrint('✅ Found ${trips.length} trips for customer');
        return trips;
      } else {
        throw Exception(response['message'] ?? 'Failed to get customer trips');
      }
    } catch (e) {
      debugPrint('❌ Error getting customer trips: $e');
      rethrow;
    }
  }

  /// Get active trips for the authenticated customer
  Future<List<Map<String, dynamic>>> getActiveTrips() async {
    try {
      debugPrint('📥 CustomerTripService: Fetching active customer trips');
      
      final response = await _apiService.get('/api/trips/customer/active');
      
      if (response['success'] == true) {
        final trips = List<Map<String, dynamic>>.from(response['data'] ?? []);
        debugPrint('✅ Found ${trips.length} active trips for customer');
        return trips;
      } else {
        throw Exception(response['message'] ?? 'Failed to get active trips');
      }
    } catch (e) {
      debugPrint('❌ Error getting active trips: $e');
      rethrow;
    }
  }

  /// Get trip by ID
  Future<Map<String, dynamic>?> getTripById(String tripId) async {
    try {
      debugPrint('📥 CustomerTripService: Fetching trip $tripId');
      
      final response = await _apiService.get('/api/admin/trips/$tripId');
      
      if (response['success'] == true) {
        debugPrint('✅ Trip found: $tripId');
        return response['data'];
      } else {
        throw Exception(response['message'] ?? 'Trip not found');
      }
    } catch (e) {
      debugPrint('❌ Error getting trip: $e');
      rethrow;
    }
  }
}

/// Trip Status Helper
class TripStatusHelper {
  static Color getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return Colors.blue;
      case 'started':
        return Colors.orange;
      case 'in_progress':
        return Colors.purple;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  static String getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return 'Assigned';
      case 'started':
        return 'Started';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.toUpperCase();
    }
  }

  static IconData getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'assigned':
        return Icons.assignment;
      case 'started':
        return Icons.play_arrow;
      case 'in_progress':
        return Icons.directions_car;
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }
}

/// Trip Type Helper
class TripTypeHelper {
  static String getTypeLabel(String? tripType) {
    switch (tripType?.toLowerCase()) {
      case 'login':
        return 'Morning Trip';
      case 'logout':
        return 'Evening Trip';
      default:
        return 'Trip';
    }
  }

  static IconData getTypeIcon(String? tripType) {
    switch (tripType?.toLowerCase()) {
      case 'login':
        return Icons.wb_sunny; // Morning sun
      case 'logout':
        return Icons.nights_stay; // Evening moon
      default:
        return Icons.trip_origin;
    }
  }

  static Color getTypeColor(String? tripType) {
    switch (tripType?.toLowerCase()) {
      case 'login':
        return Colors.orange; // Morning color
      case 'logout':
        return Colors.indigo; // Evening color
      default:
        return Colors.blue;
    }
  }
}