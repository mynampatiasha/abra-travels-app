// lib/core/services/maintenance_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class MaintenanceService {
  static String get _maintenanceEndpoint => '${ApiConfig.baseUrl}/api/maintenance';

  Future<String?> _getAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      print('Error getting auth token: $e');
      return null;
    }
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getAuthToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Schedule maintenance and send email to vendor
  Future<Map<String, dynamic>> scheduleMaintenanceWithEmail({
    required String vehicleId,
    required String maintenanceType,
    required DateTime scheduledDate,
    required String vendorEmail,
    required String vendorName,
    String? vendorPhone,
    String? description,
    double? estimatedCost,
    String priority = 'medium',
  }) async {
    try {
      final headers = await _getHeaders();
      
      final body = {
        'vehicleId': vehicleId,
        'maintenanceType': maintenanceType,
        'scheduledDate': scheduledDate.toIso8601String(),
        'vendorEmail': vendorEmail,
        'vendorName': vendorName,
        if (vendorPhone != null && vendorPhone.isNotEmpty) 'vendorPhone': vendorPhone,
        if (description != null && description.isNotEmpty) 'description': description,
        if (estimatedCost != null) 'estimatedCost': estimatedCost,
        'priority': priority,
      };

      print('=== SCHEDULE MAINTENANCE REQUEST ===');
      print('URL: $_maintenanceEndpoint/schedule');
      print('Body: ${jsonEncode(body)}');
      print('====================================');

      final response = await http.post(
        Uri.parse('$_maintenanceEndpoint/schedule'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      print('=== SCHEDULE MAINTENANCE RESPONSE ===');
      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');
      print('=====================================');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Maintenance scheduled successfully',
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to schedule maintenance',
          'errors': responseData['errors'],
        };
      }
    } catch (e) {
      print('Error scheduling maintenance: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Get maintenance schedules
  Future<Map<String, dynamic>> getMaintenanceSchedules({
    int page = 1,
    int limit = 10,
    String? status,
    String? vehicleId,
  }) async {
    try {
      final headers = await _getHeaders();
      
      final queryParams = {
        'page': page.toString(),
        'limit': limit.toString(),
        if (status != null && status.isNotEmpty) 'status': status,
        if (vehicleId != null && vehicleId.isNotEmpty) 'vehicleId': vehicleId,
      };

      final uri = Uri.parse('$_maintenanceEndpoint/schedules').replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'data': responseData['data'] ?? [],
          'pagination': responseData['pagination'] ?? {},
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to fetch maintenance schedules',
        };
      }
    } catch (e) {
      print('Error fetching maintenance schedules: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Create maintenance report
  Future<Map<String, dynamic>> createMaintenanceReport({
    required String vehicleId,
    required String maintenanceType,
    required DateTime completedDate,
    required String vendorName,
    String? vendorEmail,
    required double actualCost,
    required String description,
    required String status,
    List<String>? partsReplaced,
    DateTime? nextMaintenanceDue,
    String? warrantyInfo,
    String? invoiceNumber,
  }) async {
    try {
      final headers = await _getHeaders();
      
      final body = {
        'vehicleId': vehicleId,
        'maintenanceType': maintenanceType,
        'completedDate': completedDate.toIso8601String(),
        'vendorName': vendorName,
        if (vendorEmail != null && vendorEmail.isNotEmpty) 'vendorEmail': vendorEmail,
        'actualCost': actualCost,
        'description': description,
        'status': status,
        if (partsReplaced != null && partsReplaced.isNotEmpty) 'partsReplaced': partsReplaced,
        if (nextMaintenanceDue != null) 'nextMaintenanceDue': nextMaintenanceDue.toIso8601String(),
        if (warrantyInfo != null && warrantyInfo.isNotEmpty) 'warrantyInfo': warrantyInfo,
        if (invoiceNumber != null && invoiceNumber.isNotEmpty) 'invoiceNumber': invoiceNumber,
      };

      print('=== CREATE MAINTENANCE REPORT REQUEST ===');
      print('URL: $_maintenanceEndpoint/reports');
      print('Body: ${jsonEncode(body)}');
      print('=========================================');

      final response = await http.post(
        Uri.parse('$_maintenanceEndpoint/reports'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      print('=== CREATE MAINTENANCE REPORT RESPONSE ===');
      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');
      print('==========================================');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Maintenance report created successfully',
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to create maintenance report',
          'errors': responseData['errors'],
        };
      }
    } catch (e) {
      print('Error creating maintenance report: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Get maintenance reports
  Future<Map<String, dynamic>> getMaintenanceReports({
    int page = 1,
    int limit = 10,
    String? status,
    String? vehicleId,
    String? maintenanceType,
  }) async {
    try {
      final headers = await _getHeaders();
      
      final queryParams = {
        'page': page.toString(),
        'limit': limit.toString(),
        if (status != null && status.isNotEmpty) 'status': status,
        if (vehicleId != null && vehicleId.isNotEmpty) 'vehicleId': vehicleId,
        if (maintenanceType != null && maintenanceType.isNotEmpty) 'maintenanceType': maintenanceType,
      };

      final uri = Uri.parse('$_maintenanceEndpoint/reports').replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'data': responseData['data'] ?? [],
          'pagination': responseData['pagination'] ?? {},
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to fetch maintenance reports',
        };
      }
    } catch (e) {
      print('Error fetching maintenance reports: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Update maintenance report
  Future<Map<String, dynamic>> updateMaintenanceReport({
    required String reportId,
    required String vehicleId,
    required String maintenanceType,
    required DateTime completedDate,
    required String vendorName,
    String? vendorEmail,
    required double actualCost,
    required String description,
    required String status,
    List<String>? partsReplaced,
    DateTime? nextMaintenanceDue,
    String? warrantyInfo,
    String? invoiceNumber,
  }) async {
    try {
      final headers = await _getHeaders();
      
      final body = {
        'vehicleId': vehicleId,
        'maintenanceType': maintenanceType,
        'completedDate': completedDate.toIso8601String(),
        'vendorName': vendorName,
        if (vendorEmail != null && vendorEmail.isNotEmpty) 'vendorEmail': vendorEmail,
        'actualCost': actualCost,
        'description': description,
        'status': status,
        if (partsReplaced != null && partsReplaced.isNotEmpty) 'partsReplaced': partsReplaced,
        if (nextMaintenanceDue != null) 'nextMaintenanceDue': nextMaintenanceDue.toIso8601String(),
        if (warrantyInfo != null && warrantyInfo.isNotEmpty) 'warrantyInfo': warrantyInfo,
        if (invoiceNumber != null && invoiceNumber.isNotEmpty) 'invoiceNumber': invoiceNumber,
      };

      final response = await http.put(
        Uri.parse('$_maintenanceEndpoint/reports/$reportId'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Maintenance report updated successfully',
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to update maintenance report',
          'errors': responseData['errors'],
        };
      }
    } catch (e) {
      print('Error updating maintenance report: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Delete maintenance report
  Future<Map<String, dynamic>> deleteMaintenanceReport(String reportId) async {
    try {
      final headers = await _getHeaders();

      final response = await http.delete(
        Uri.parse('$_maintenanceEndpoint/reports/$reportId'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Maintenance report deleted successfully',
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to delete maintenance report',
        };
      }
    } catch (e) {
      print('Error deleting maintenance report: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Get maintenance analytics
  Future<Map<String, dynamic>> getMaintenanceAnalytics({
    String timeframe = '30d',
  }) async {
    try {
      final headers = await _getHeaders();
      
      final queryParams = {
        'timeframe': timeframe,
      };

      final uri = Uri.parse('$_maintenanceEndpoint/analytics').replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to fetch maintenance analytics',
        };
      }
    } catch (e) {
      print('Error fetching maintenance analytics: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }
}