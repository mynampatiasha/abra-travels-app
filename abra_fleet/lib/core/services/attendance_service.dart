// lib/core/services/attendance_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class AttendanceService {
  static final AttendanceService _instance = AttendanceService._internal();
  factory AttendanceService() => _instance;
  AttendanceService._internal();

  String get baseUrl => ApiConfig.baseUrl;

  // Get auth token
  Future<String?> _getAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        print('❌ No JWT token found');
        return null;
      }
      return token;
    } catch (e) {
      print('❌ Error getting auth token: $e');
      return null;
    }
  }

  // Auto-mark attendance when driver starts trip
  Future<Map<String, dynamic>> autoMarkAttendance({
    required String driverId,
    required String tripId,
    String? vehicleId,
  }) async {
    try {
      final token = await _getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      print('📤 Auto-marking attendance for driver $driverId, trip $tripId');

      // Get current location
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition();
      } catch (e) {
        print('⚠️ Could not get location: $e');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/attendance/auto-mark'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'driverId': driverId,
          'tripId': tripId,
          'vehicleId': vehicleId,
          if (position != null)
            'location': {
              'latitude': position.latitude,
              'longitude': position.longitude,
            },
        }),
      );

      print('📥 Attendance response: ${response.statusCode}');
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        print('✅ Attendance auto-marked successfully');
        return {
          'success': true,
          'message': data['message'],
          'attendance': data['attendance'],
          'isLate': data['isLate'] ?? false,
          'lateByMinutes': data['lateByMinutes'] ?? 0,
        };
      } else {
        throw Exception(data['message'] ?? 'Failed to mark attendance');
      }
    } catch (e) {
      print('❌ Error auto-marking attendance: $e');
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  // Complete attendance when driver ends trip
  Future<Map<String, dynamic>> completeAttendance({
    required String driverId,
    required String tripId,
  }) async {
    try {
      final token = await _getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      print('📤 Completing attendance for driver $driverId, trip $tripId');

      // Get current location
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition();
      } catch (e) {
        print('⚠️ Could not get location: $e');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/attendance/complete'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'driverId': driverId,
          'tripId': tripId,
          if (position != null)
            'location': {
              'latitude': position.latitude,
              'longitude': position.longitude,
            },
        }),
      );

      print('📥 Attendance completion response: ${response.statusCode}');
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        print('✅ Attendance completed successfully');
        return {
          'success': true,
          'message': data['message'],
          'totalHours': data['totalHours'],
          'totalTrips': data['totalTrips'],
          'completedTrips': data['completedTrips'],
        };
      } else {
        throw Exception(data['message'] ?? 'Failed to complete attendance');
      }
    } catch (e) {
      print('❌ Error completing attendance: $e');
      return {
        'success': false,
        'message': e.toString(),
      };
    }
  }

  // Get today's attendance
  Future<Map<String, dynamic>?> getTodayAttendance(String driverId) async {
    try {
      final token = await _getAuthToken();
      if (token == null) throw Exception('Not authenticated');

      final response = await http.get(
        Uri.parse('$baseUrl/api/attendance/driver/$driverId/today'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['attendance'];
      }
    } catch (e) {
      print('❌ Error getting today attendance: $e');
    }
    return null;
  }
}