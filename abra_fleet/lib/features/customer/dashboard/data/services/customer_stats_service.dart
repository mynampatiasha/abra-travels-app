// File: lib/features/customer/dashboard/data/services/customer_stats_service.dart

import 'package:abra_fleet/core/services/api_service.dart';

class CustomerStatsService {
  final ApiService _apiService = ApiService();

  // Get customer's trip statistics
  Future<Map<String, dynamic>> getCustomerStats() async {
    try {
      final response = await _apiService.get('/api/customer/stats');
      return response['data'] ?? response;
    } catch (e) {
      print('Error fetching customer stats: $e');
      rethrow;
    }
  }

  // Get detailed trip breakdown
  Future<Map<String, dynamic>> getTripBreakdown() async {
    try {
      final response = await _apiService.get('/api/customer/stats/trips');
      return response['data'] ?? response;
    } catch (e) {
      print('Error fetching trip breakdown: $e');
      rethrow;
    }
  }

  // Get monthly distance data
  Future<List<Map<String, dynamic>>> getMonthlyDistance({int months = 6}) async {
    try {
      final response = await _apiService.get('/api/customer/stats/distance', 
        queryParams: {'months': months.toString()});
      
      final data = response['data'] ?? response;
      if (data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      print('Error fetching monthly distance: $e');
      rethrow;
    }
  }

  // Get service usage frequency (weekly bookings)
  Future<List<int>> getServiceFrequency({int weeks = 12}) async {
    try {
      final response = await _apiService.get('/api/customer/stats/frequency',
        queryParams: {'weeks': weeks.toString()});
      
      final data = response['data'] ?? response;
      if (data is List) {
        return List<int>.from(data);
      }
      return [];
    } catch (e) {
      print('Error fetching service frequency: $e');
      rethrow;
    }
  }

  // Get most used routes
  Future<List<Map<String, dynamic>>> getTopRoutes({int limit = 3}) async {
    try {
      final response = await _apiService.get('/api/customer/stats/routes',
        queryParams: {'limit': limit.toString()});
      
      final data = response['data'] ?? response;
      if (data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      print('Error fetching top routes: $e');
      rethrow;
    }
  }

  // Get on-time delivery statistics
  Future<Map<String, dynamic>> getDeliveryStats() async {
    try {
      final response = await _apiService.get('/api/customer/stats/delivery-performance');
      return response['data'] ?? response;
    } catch (e) {
      print('Error fetching delivery stats: $e');
      rethrow;
    }
  }

  // Get all stats in one call (for efficiency)
  Future<Map<String, dynamic>> getAllStats() async {
    try {
      final response = await _apiService.get('/api/customer/stats/dashboard');
      return response['data'] ?? response;
    } catch (e) {
      print('Error fetching all stats: $e');
      rethrow;
    }
  }

  // Get monthly distance data for billing with month filter
  Future<Map<String, dynamic>> getMonthlyDistanceForBilling({String? selectedMonth, String? selectedYear}) async {
    try {
      final queryParams = <String, String>{};
      if (selectedMonth != null) queryParams['month'] = selectedMonth;
      if (selectedYear != null) queryParams['year'] = selectedYear;
      
      final response = await _apiService.get('/api/customer/stats/monthly-distance', 
        queryParams: queryParams.isNotEmpty ? queryParams : null);
      return response['data'] ?? response;
    } catch (e) {
      print('Error fetching monthly distance for billing: $e');
      rethrow;
    }
  }

  // Get recent activities for customer dashboard
  Future<List<Map<String, dynamic>>> getRecentActivities() async {
    try {
      final response = await _apiService.get('/api/customer/stats/recent-activities');
      
      final data = response['data'] ?? response;
      if (data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } catch (e) {
      print('Error fetching recent activities: $e');
      rethrow;
    }
  }
}