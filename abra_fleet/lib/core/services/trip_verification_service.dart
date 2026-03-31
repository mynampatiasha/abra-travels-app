// lib/core/services/trip_verification_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TripVerificationService {
  static final TripVerificationService _instance = TripVerificationService._internal();
  factory TripVerificationService() => _instance;
  TripVerificationService._internal();

  // Get auth headers
  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token') ?? '';
    
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ============================================================================
  // Fetch trips with filters
  // ============================================================================
  Future<Map<String, dynamic>> getTripsForVerification({
    String? startDate,
    String? endDate,
    String? driverId,
    String? vehicleId,
    String? status,
    int limit = 100,
    int skip = 0,
  }) async {
    try {
      print('\n📋 Fetching trips for verification...');
      
      // Build query params
      final queryParams = <String, String>{
        'limit': limit.toString(),
        'skip': skip.toString(),
      };
      
      if (startDate != null) queryParams['startDate'] = startDate;
      if (endDate != null) queryParams['endDate'] = endDate;
      if (driverId != null && driverId != 'all') queryParams['driverId'] = driverId;
      if (vehicleId != null && vehicleId != 'all') queryParams['vehicleId'] = vehicleId;
      if (status != null && status != 'all') queryParams['status'] = status;
      
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/trips/verification')
          .replace(queryParameters: queryParams);
      
      print('🌐 Request URL: $uri');
      
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers);
      
      print('📥 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Fetched ${data['count']} trip(s)');
        return data;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to fetch trips');
      }
      
    } catch (e) {
      print('❌ Error fetching trips: $e');
      rethrow;
    }
  }

  // ============================================================================
  // Get trip details by ID
  // ============================================================================
  Future<Map<String, dynamic>> getTripDetails(String tripId) async {
    try {
      print('\n📋 Fetching trip details: $tripId');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/trips/$tripId/details'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Trip details fetched');
        return data;
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to fetch trip details');
      }
      
    } catch (e) {
      print('❌ Error fetching trip details: $e');
      rethrow;
    }
  }

  // ============================================================================
  // Get odometer photo URL
  // ============================================================================
  String getOdometerPhotoUrl(String photoId) {
    return '${ApiConfig.baseUrl}/api/admin/odometer-photo/$photoId';
  }

  // ============================================================================
  // Get list of drivers for filter dropdown
  // ============================================================================
  Future<List<Map<String, dynamic>>> getDriversList() async {
    try {
      print('\n👨‍✈️ Fetching drivers list...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/drivers/list'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Fetched ${data['data'].length} driver(s)');
        return List<Map<String, dynamic>>.from(data['data']);
      } else {
        throw Exception('Failed to fetch drivers');
      }
      
    } catch (e) {
      print('❌ Error fetching drivers: $e');
      return [];
    }
  }

  // ============================================================================
  // Get list of vehicles for filter dropdown
  // ============================================================================
  Future<List<Map<String, dynamic>>> getVehiclesList() async {
    try {
      print('\n🚗 Fetching vehicles list...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/admin/vehicles/list'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ Fetched ${data['data'].length} vehicle(s)');
        return List<Map<String, dynamic>>.from(data['data']);
      } else {
        throw Exception('Failed to fetch vehicles');
      }
      
    } catch (e) {
      print('❌ Error fetching vehicles: $e');
      return [];
    }
  }
}