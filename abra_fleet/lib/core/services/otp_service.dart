// ============================================================================
// lib/core/services/otp_service.dart
// OTP API SERVICE — All OTP-related API calls
// ============================================================================

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'api_service.dart';
import '../../app/config/api_config.dart';

class OtpService {
  static final OtpService _instance = OtpService._internal();
  factory OtpService() => _instance;
  OtpService._internal();

  final ApiService _apiService = ApiService();

  // ============================================================================
  // Generate Step-In OTPs for all customers at a stop
  // Called after driver marks "Arrived"
  // ============================================================================
  Future<List<Map<String, dynamic>>> generateStepInOTPs({
    required String tripGroupId,
    required String stopId,
    required List<Map<String, dynamic>> customers,
  }) async {
    try {
      debugPrint('🔐 Generating step-in OTPs for ${customers.length} customer(s)');

      final response = await _apiService.post(
        '/api/otp/generate-step-in',
        body: {
          'tripGroupId': tripGroupId,
          'stopId': stopId,
          'customers': customers,
        },
      );

      if (response['success'] == true) {
        final data = List<Map<String, dynamic>>.from(response['data'] ?? []);
        debugPrint('✅ Generated ${data.length} step-in OTP(s)');
        return data;
      }

      throw Exception(response['message'] ?? 'Failed to generate OTPs');
    } catch (e) {
      debugPrint('❌ generateStepInOTPs error: $e');
      rethrow;
    }
  }

  // ============================================================================
  // Generate Step-Out OTP for a specific customer
  // Called when driver marks a passenger as "Boarded"
  // ============================================================================
  Future<Map<String, dynamic>> boardPassenger({
    required String tripGroupId,
    required String stopId,
    required String passengerId,
  }) async {
    try {
      debugPrint('🚌 Marking passenger $passengerId as boarded');

      final response = await _apiService.post(
        '/api/driver/trips/$tripGroupId/stop/$stopId/passenger/$passengerId/board',
        body: {},
      );

      if (response['success'] == true) {
        debugPrint('✅ Passenger boarded, step-out OTP generated');
        return response['data'] ?? {};
      }

      throw Exception(response['message'] ?? 'Failed to board passenger');
    } catch (e) {
      debugPrint('❌ boardPassenger error: $e');
      rethrow;
    }
  }

  // ============================================================================
  // Verify OTP entered by driver
  // ============================================================================
  Future<Map<String, dynamic>> verifyOTP({
    required String tripGroupId,
    required String stopId,
    required String passengerId,
    required String otp,
  }) async {
    try {
      debugPrint('🔍 Verifying OTP for passenger $passengerId');

      final response = await _apiService.post(
        '/api/otp/verify',
        body: {
          'tripGroupId': tripGroupId,
          'stopId': stopId,
          'passengerId': passengerId,
          'otp': otp,
        },
      );

      return response;
    } catch (e) {
      debugPrint('❌ verifyOTP error: $e');
      rethrow;
    }
  }

  // ============================================================================
  // Resend OTP — generates fresh code, resets attempts
  // ============================================================================
  Future<Map<String, dynamic>> resendOTP({
    required String tripGroupId,
    required String stopId,
    required String passengerId,
  }) async {
    try {
      debugPrint('🔄 Resending OTP for passenger $passengerId');

      final response = await _apiService.post(
        '/api/otp/resend',
        body: {
          'tripGroupId': tripGroupId,
          'stopId': stopId,
          'passengerId': passengerId,
        },
      );

      if (response['success'] == true) {
        debugPrint('✅ OTP resent');
        return response['data'] ?? {};
      }

      throw Exception(response['message'] ?? 'Failed to resend OTP');
    } catch (e) {
      debugPrint('❌ resendOTP error: $e');
      rethrow;
    }
  }

  // ============================================================================
  // Request Override — driver submits override with reason + REQUIRED photo
  // Uses XFile.readAsBytes() — works on both web and mobile
  // ============================================================================
  Future<void> requestOverride({
    required String tripGroupId,
    required String stopId,
    required String passengerId,
    required String reason,
    required XFile photo, // ← required, not optional
  }) async {
    try {
      debugPrint('⚠️ Requesting override for passenger $passengerId');

      // Read bytes — works on web AND mobile (no dart:io needed)
      final photoBytes = await photo.readAsBytes();
      final ext = photo.name.split('.').last.toLowerCase();
      final mimeType = (ext == 'png') ? 'png' : 'jpeg';

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/otp/override-request');
      final request = http.MultipartRequest('POST', uri);

      final headers = await _apiService.getHeaders();
      headers.remove('Content-Type'); // multipart sets its own
      request.headers.addAll(headers);

      request.fields['tripGroupId'] = tripGroupId;
      request.fields['stopId'] = stopId;
      request.fields['passengerId'] = passengerId;
      request.fields['reason'] = reason;

      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photoBytes,
          filename: 'override_${DateTime.now().millisecondsSinceEpoch}.$ext',
          contentType: http.MediaType('image', mimeType),
        ),
      );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);

      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'Failed to request override');
      }

      debugPrint('✅ Override request submitted');
    } catch (e) {
      debugPrint('❌ requestOverride error: $e');
      rethrow;
    }
  }

  // ============================================================================
  // Mark passenger as No-Show (customer didn't arrive at pickup)
  // Unblocks departure without requiring OTP
  // ============================================================================
  Future<void> markNoShow({
    required String tripGroupId,
    required String stopId,
    required String passengerId,
    String? passengerName,
    String? passengerEmail,
  }) async {
    try {
      debugPrint('🚫 Marking no-show for passenger $passengerId');

      final response = await _apiService.post(
        '/api/otp/no-show',
        body: {
          'tripGroupId': tripGroupId,
          'stopId': stopId,
          'passengerId': passengerId,
          if (passengerName != null) 'passengerName': passengerName,
          if (passengerEmail != null) 'passengerEmail': passengerEmail,
        },
      );

      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Failed to mark no-show');
      }

      debugPrint('✅ No-show recorded');
    } catch (e) {
      debugPrint('❌ markNoShow error: $e');
      rethrow;
    }
  }

  // ============================================================================
  // Get OTP status for a stop
  // ============================================================================
  Future<List<Map<String, dynamic>>> getStopOTPStatus({
    required String tripGroupId,
    required String stopId,
  }) async {
    try {
      final response = await _apiService.get('/api/otp/status/$tripGroupId/$stopId');

      if (response['success'] == true) {
        return List<Map<String, dynamic>>.from(response['data'] ?? []);
      }

      throw Exception(response['message'] ?? 'Failed to get OTP status');
    } catch (e) {
      debugPrint('❌ getStopOTPStatus error: $e');
      rethrow;
    }
  }

  // ============================================================================
  // Admin: Get failed OTP log
  // ============================================================================
  Future<List<Map<String, dynamic>>> getFailedOTPLog({
    String? startDate,
    String? endDate,
    String? driverId,
    String? status,
    int limit = 100,
  }) async {
    try {
      final params = <String, String>{};
      if (startDate != null) params['startDate'] = startDate;
      if (endDate != null) params['endDate'] = endDate;
      if (driverId != null) params['driverId'] = driverId;
      if (status != null) params['status'] = status;
      params['limit'] = limit.toString();

      final response = await _apiService.get('/api/otp/failed-log', queryParams: params);

      if (response['success'] == true) {
        return List<Map<String, dynamic>>.from(response['data'] ?? []);
      }

      throw Exception(response['message'] ?? 'Failed to get failed OTP log');
    } catch (e) {
      debugPrint('❌ getFailedOTPLog error: $e');
      rethrow;
    }
  }

  // ============================================================================
  // Admin: Approve or reject override
  // ============================================================================
  Future<void> processOverride({
    required String tripGroupId,
    required String stopId,
    String? passengerId,
    required bool approved,
    String? adminNotes,
  }) async {
    try {
      final response = await _apiService.post(
        '/api/otp/override-approve',
        body: {
          'tripGroupId': tripGroupId,
          if (stopId.isNotEmpty) 'stopId': stopId,
          if (passengerId != null && passengerId.isNotEmpty) 'passengerId': passengerId,
          'approved': approved,
          if (adminNotes != null) 'adminNotes': adminNotes,
        },
      );

      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Failed to process override');
      }

      debugPrint('✅ Override ${approved ? 'approved' : 'rejected'}');
    } catch (e) {
      debugPrint('❌ processOverride error: $e');
      rethrow;
    }
  }
}
