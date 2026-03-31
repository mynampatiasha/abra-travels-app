import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class ClientReportsService {
  static final String _baseUrl = ApiConfig.baseUrl;

  Future<String> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token != null && token.isNotEmpty) {
      return token;
    }
    throw Exception('User not authenticated');
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
  };

  Future<Map<String, String>> get _authHeaders async {
    final token = await _getAuthToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  // Company Analytics
  Future<Map<String, dynamic>> getCompanyAnalytics({String filter = 'today'}) async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/admin-analytics/company-analytics?filter=$filter'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      throw Exception('Failed to fetch company analytics');
    } catch (e) {
      throw Exception('Error fetching company analytics: $e');
    }
  }

  // Manpower Statistics
  Future<Map<String, dynamic>> getManpowerStats() async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/admin-analytics/manpower-stats'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data['stats'];
        }
      }
      throw Exception('Failed to fetch manpower stats');
    } catch (e) {
      throw Exception('Error fetching manpower stats: $e');
    }
  }

  // Revenue Statistics
  Future<Map<String, dynamic>> getRevenueStats({String filter = 'today'}) async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/admin-analytics/revenue-stats?filter=$filter'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data['revenue'];
        }
      }
      throw Exception('Failed to fetch revenue stats');
    } catch (e) {
      throw Exception('Error fetching revenue stats: $e');
    }
  }

  // Ratings Overview
  Future<Map<String, dynamic>> getRatingsOverview() async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/admin-analytics/ratings/overview'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data['ratingsData'];
        }
      }
      throw Exception('Failed to fetch ratings overview');
    } catch (e) {
      throw Exception('Error fetching ratings overview: $e');
    }
  }

  // Customer Dashboard Stats
  Future<Map<String, dynamic>> getCustomerDashboardStats() async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/customer/stats/dashboard'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data['data'];
        }
      }
      throw Exception('Failed to fetch customer dashboard stats');
    } catch (e) {
      throw Exception('Error fetching customer dashboard stats: $e');
    }
  }

  // Monthly Distance Data
  Future<Map<String, dynamic>> getMonthlyDistance({String? month}) async {
    try {
      final headers = await _authHeaders;
      final url = month != null 
        ? '$_baseUrl/customer/stats/monthly-distance?month=$month'
        : '$_baseUrl/customer/stats/monthly-distance';
        
      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data['data'];
        }
      }
      throw Exception('Failed to fetch monthly distance data');
    } catch (e) {
      throw Exception('Error fetching monthly distance data: $e');
    }
  }

  // Active Trips
  Future<List<dynamic>> getActiveTrips() async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/admin-analytics/trips/active'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data['trips'] ?? [];
        }
      }
      throw Exception('Failed to fetch active trips');
    } catch (e) {
      throw Exception('Error fetching active trips: $e');
    }
  }

  // Completed Trips Today
  Future<List<dynamic>> getCompletedTripsToday() async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/admin-analytics/trips/completed-today'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data['trips'] ?? [];
        }
      }
      throw Exception('Failed to fetch completed trips');
    } catch (e) {
      throw Exception('Error fetching completed trips: $e');
    }
  }

  // Cancelled Trips Today
  Future<List<dynamic>> getCancelledTripsToday() async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/admin-analytics/trips/cancelled-today'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data['trips'] ?? [];
        }
      }
      throw Exception('Failed to fetch cancelled trips');
    } catch (e) {
      throw Exception('Error fetching cancelled trips: $e');
    }
  }

  // Revenue Details
  Future<Map<String, dynamic>> getRevenueDetails({String type = 'today'}) async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/admin-analytics/revenue/details?type=$type'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data['revenueData'];
        }
      }
      throw Exception('Failed to fetch revenue details');
    } catch (e) {
      throw Exception('Error fetching revenue details: $e');
    }
  }

  // Get all reports data in one call
  Future<Map<String, dynamic>> getAllReportsData({
    String timeFilter = 'today',
    String revenueFilter = 'today',
    String? selectedMonth,
  }) async {
    try {
      final results = await Future.wait([
        getCompanyAnalytics(filter: timeFilter),
        getManpowerStats(),
        getRevenueStats(filter: revenueFilter),
        getRatingsOverview(),
        getCustomerDashboardStats(),
        getMonthlyDistance(month: selectedMonth),
        getActiveTrips(),
        getCompletedTripsToday(),
        getCancelledTripsToday(),
      ]);

      return {
        'companyAnalytics': results[0],
        'manpowerStats': results[1],
        'revenueStats': results[2],
        'ratingsData': results[3],
        'customerStats': results[4],
        'monthlyDistance': results[5],
        'activeTrips': results[6],
        'completedTrips': results[7],
        'cancelledTrips': results[8],
      };
    } catch (e) {
      throw Exception('Error fetching all reports data: $e');
    }
  }
}