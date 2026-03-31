// File: lib/core/services/user_verification_service.dart
// 🔥 FIXED: Simplified MongoDB-only verification with proper error handling
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class UserVerificationService {
  static String get apiUrl => '${ApiConfig.baseUrl}/api';

  // Verify user status by email (for users created through admin system)
  static Future<Map<String, dynamic>?> verifyUserByEmail(String email) async {
    try {
      print('🔍 UserVerificationService - Verifying user: $email');
      
      // Get JWT token for authentication
      final prefs = await SharedPreferences.getInstance();
      String? idToken = prefs.getString('jwt_token');
      
      final headers = {
        'Content-Type': 'application/json',
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      };
      
      final response = await http.get(
        Uri.parse('$apiUrl/auth/verify-email/$email'),
        headers: headers,
      ).timeout(
        const Duration(seconds: 10), // Increased timeout to 10 seconds
        onTimeout: () {
          print('⏰ UserVerificationService - Request timed out for: $email');
          throw TimeoutException('User verification request timed out', const Duration(seconds: 10));
        },
      );
      
      print('🔍 UserVerificationService - Response status: ${response.statusCode}');
      print('🔍 UserVerificationService - Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData['success'] == true) {
          print('✅ UserVerificationService - User verified successfully');
          return jsonData['user'] ?? jsonData['data'];
        } else {
          throw Exception(jsonData['message'] ?? 'User verification failed');
        }
      } else if (response.statusCode == 404) {
        // User not found in MongoDB - return null (not an error)
        print('⚠️ UserVerificationService - User not found in MongoDB (might be Firestore user)');
        return null;
      } else if (response.statusCode == 403) {
        final jsonData = json.decode(response.body);
        throw Exception(jsonData['message'] ?? 'Account inactive');
      } else {
        // For any other error, return null instead of throwing
        print('⚠️ UserVerificationService - Verification failed with status ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ UserVerificationService - Error: $e');
      // Return null instead of rethrowing to prevent login blocking
      return null;
    }
  }

  // Check if user exists in MongoDB (admin-created users)
  static Future<bool> isAdminCreatedUser(String email) async {
    try {
      final userData = await verifyUserByEmail(email);
      return userData != null;
    } catch (e) {
      // If verification fails, assume it's not an admin-created user
      return false;
    }
  }
}