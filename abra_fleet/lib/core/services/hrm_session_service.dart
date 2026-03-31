// lib/core/services/hrm_session_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Service to create PHP session for HRM KPI/KPQ system
/// Converts Flutter JWT token to PHP session
class HrmSessionService {
  static const String _sessionBridgeUrl = 'https://www.abra-travels.com/hrm/jwt-session-bridge.php';
  
  /// Create PHP session from JWT token
  /// Call this before loading any HRM WebView pages
  static Future<bool> createPhpSession() async {
    try {
      debugPrint('📊 HRM Session: Creating PHP session...');
      
      // Get JWT token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      if (token == null || token.isEmpty) {
        debugPrint('❌ HRM Session: No JWT token found');
        return false;
      }
      
      debugPrint('📊 HRM Session: Token found, calling bridge endpoint...');
      
      // Call session bridge endpoint
      final response = await http.post(
        Uri.parse(_sessionBridgeUrl),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⏱️ HRM Session: Request timeout');
          throw Exception('Session creation timeout');
        },
      );
      
      debugPrint('📊 HRM Session: Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          debugPrint('✅ HRM Session: PHP session created successfully');
          debugPrint('📊 Session data: ${data['session_data']}');
          return true;
        } else {
          debugPrint('❌ HRM Session: Bridge returned success=false');
          return false;
        }
      } else {
        debugPrint('❌ HRM Session: Bridge returned status ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        return false;
      }
      
    } catch (e) {
      debugPrint('❌ HRM Session Error: $e');
      return false;
    }
  }
  
  /// Check if session is still valid (optional - for future use)
  static Future<bool> isSessionValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      return token != null && token.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}
