// lib/features/customer/trips/data/services/my_trips_service.dart
// ============================================================================
// CUSTOMER TRIPS SERVICE - API Integration
// ============================================================================
// Handles all API communication for customer trip management
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/core/services/backend_connection_manager.dart';

class MyTripsService {
  final BackendConnectionManager _connectionManager = BackendConnectionManager();
  
  /// Get daily trips for customer from roster-assigned-trips collection
  /// 
  /// Parameters:
  /// - [rosterId]: Optional roster ID to filter trips
  /// - [startDate]: Optional start date (YYYY-MM-DD)
  /// - [endDate]: Optional end date (YYYY-MM-DD)
  /// 
  /// Returns a list of daily trips with all details
  Future<Map<String, dynamic>> getDailyTrips({
    String? rosterId,
    String? startDate,
    String? endDate,
  }) async {
    try {
      print('📋 Fetching daily trips...');
      if (rosterId != null) print('   Roster ID: $rosterId');
      if (startDate != null) print('   Start Date: $startDate');
      if (endDate != null) print('   End Date: $endDate');

      // Build query parameters
      final Map<String, String> queryParams = {};
      if (rosterId != null && rosterId.isNotEmpty) {
        queryParams['rosterId'] = rosterId;
      }
      if (startDate != null && startDate.isNotEmpty) {
        queryParams['startDate'] = startDate;
      }
      if (endDate != null && endDate.isNotEmpty) {
        queryParams['endDate'] = endDate;
      }

      // Make API call
      final response = await _connectionManager.apiService.get(
        '/api/customer/trips/daily-trips',
        queryParams: queryParams,
      );

      print('   Response: ${response['success']}');
      
      if (response['success'] == true) {
        final List<dynamic> tripsData = response['data'] ?? [];
        print('   ✅ Retrieved ${tripsData.length} trip(s)');
        
        return {
          'success': true,
          'data': tripsData,
          'count': response['count'] ?? tripsData.length,
        };
      } else {
        print('   ❌ API returned error: ${response['message']}');
        return {
          'success': false,
          'message': response['message'] ?? 'Failed to fetch trips',
          'data': [],
        };
      }
    } catch (e) {
      print('❌ Error fetching daily trips: $e');
      return {
        'success': false,
        'message': 'Failed to fetch trips: ${e.toString()}',
        'data': [],
      };
    }
  }

  /// Cancel a specific trip for a specific date
  /// 
  /// Parameters:
  /// - [tripId]: The trip ID from roster-assigned-trips
  /// - [tripDate]: The date of the trip to cancel (YYYY-MM-DD)
  /// - [rosterId]: Optional roster ID
  /// - [reason]: Optional cancellation reason
  /// 
  /// Returns success status and cancellation details
  Future<Map<String, dynamic>> cancelSingleTrip({
    required String tripId,
    required String tripDate,
    String? rosterId,
    String? reason,
  }) async {
    try {
      print('🚫 Cancelling trip...');
      print('   Trip ID: $tripId');
      print('   Trip Date: $tripDate');
      print('   Reason: ${reason ?? "Not specified"}');

      final response = await _connectionManager.apiService.post(
        '/api/customer/trips/cancel-single',
        body: {
          'tripId': tripId,
          'tripDate': tripDate,
          if (rosterId != null) 'rosterId': rosterId,
          if (reason != null) 'reason': reason,
        },
      );

      if (response['success'] == true) {
        print('   ✅ Trip cancelled successfully');
        return {
          'success': true,
          'message': response['message'] ?? 'Trip cancelled successfully',
          'data': response['data'],
        };
      } else {
        print('   ❌ Cancellation failed: ${response['message']}');
        return {
          'success': false,
          'message': response['message'] ?? 'Failed to cancel trip',
        };
      }
    } catch (e) {
      print('❌ Error cancelling trip: $e');
      return {
        'success': false,
        'message': 'Failed to cancel trip: ${e.toString()}',
      };
    }
  }

  /// Restore a previously cancelled trip
  /// 
  /// Parameters:
  /// - [tripId]: The trip ID from roster-assigned-trips
  /// - [tripDate]: The date of the trip to restore (YYYY-MM-DD)
  /// - [rosterId]: Optional roster ID
  /// 
  /// Returns success status and restoration details
  Future<Map<String, dynamic>> restoreSingleTrip({
    required String tripId,
    required String tripDate,
    String? rosterId,
  }) async {
    try {
      print('🔄 Restoring trip...');
      print('   Trip ID: $tripId');
      print('   Trip Date: $tripDate');

      final response = await _connectionManager.apiService.post(
        '/api/customer/trips/restore-single',
        body: {
          'tripId': tripId,
          'tripDate': tripDate,
          if (rosterId != null) 'rosterId': rosterId,
        },
      );

      if (response['success'] == true) {
        print('   ✅ Trip restored successfully');
        return {
          'success': true,
          'message': response['message'] ?? 'Trip restored successfully',
          'data': response['data'],
        };
      } else {
        print('   ❌ Restoration failed: ${response['message']}');
        return {
          'success': false,
          'message': response['message'] ?? 'Failed to restore trip',
        };
      }
    } catch (e) {
      print('❌ Error restoring trip: $e');
      return {
        'success': false,
        'message': 'Failed to restore trip: ${e.toString()}',
      };
    }
  }

  /// Get trip details by trip ID
  /// 
  /// Parameters:
  /// - [tripId]: The trip ID from roster-assigned-trips
  /// 
  /// Returns detailed trip information
  Future<Map<String, dynamic>> getTripDetails(String tripId) async {
    try {
      print('📋 Fetching trip details...');
      print('   Trip ID: $tripId');

      final response = await _connectionManager.apiService.get(
        '/api/customer/trips/details/$tripId',
      );

      if (response['success'] == true) {
        print('   ✅ Trip details retrieved');
        return {
          'success': true,
          'data': response['data'],
        };
      } else {
        print('   ❌ Failed to get trip details: ${response['message']}');
        return {
          'success': false,
          'message': response['message'] ?? 'Failed to fetch trip details',
        };
      }
    } catch (e) {
      print('❌ Error fetching trip details: $e');
      return {
        'success': false,
        'message': 'Failed to fetch trip details: ${e.toString()}',
      };
    }
  }

  /// Format date for API (YYYY-MM-DD)
  String formatDateForApi(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Parse date from API response
  DateTime? parseDateFromApi(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;
    try {
      return DateTime.parse(dateString);
    } catch (e) {
      print('⚠️ Failed to parse date: $dateString');
      return null;
    }
  }

  /// Check if trip can be cancelled (future date only)
  bool canCancelTrip(String tripDate) {
    try {
      final date = DateTime.parse(tripDate);
      final today = DateTime.now();
      final todayDate = DateTime(today.year, today.month, today.day);
      final tripDateOnly = DateTime(date.year, date.month, date.day);
      
      return tripDateOnly.isAfter(todayDate);
    } catch (e) {
      print('⚠️ Failed to check cancellation eligibility: $e');
      return false;
    }
  }

  /// Get trip status display text
  String getTripStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'scheduled':
      case 'assigned':
        return 'Scheduled';
      case 'ongoing':
      case 'started':
      case 'in_progress':
        return 'Ongoing';
      case 'completed':
      case 'done':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  /// Get trip status color
  int getTripStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'scheduled':
      case 'assigned':
        return 0xFFFFA726; // Orange
      case 'ongoing':
      case 'started':
      case 'in_progress':
        return 0xFF9C27B0; // Purple
      case 'completed':
      case 'done':
        return 0xFF4CAF50; // Green
      case 'cancelled':
        return 0xFFF44336; // Red
      default:
        return 0xFF9E9E9E; // Grey
    }
  }
}