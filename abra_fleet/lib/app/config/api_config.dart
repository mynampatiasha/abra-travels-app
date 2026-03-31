// File: lib/app/config/api_config.dart
// FIXED - Uses your actual IP: 10.38.15.123

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  static const String environment = String.fromEnvironment(
    'ENV',
    defaultValue: 'development',
  );

  // #region agent log
  static void _agentLog(String location, String message, Map<String, dynamic> data, String hypothesisId) {
    try {
      final payload = jsonEncode({
        'sessionId': 'debug-session',
        'runId': 'pre-fix',
        'hypothesisId': hypothesisId,
        'location': location,
        'message': message,
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      
      if (!kIsWeb) {
        try {
          File(r'd:\Documents\Fleet_Management\.cursor\debug.log')
              .writeAsStringSync('$payload\n', mode: FileMode.append, flush: true);
        } catch (_) {}
      }
    } catch (_) {}
  }
  // #endregion

  // ✅ YOUR IP ADDRESS: 10.38.15.123
  static String get baseUrl {
    if (kDebugMode) {
      print('🔧 API Config - Platform: ${kIsWeb ? 'WEB' : 'MOBILE'}');
      print('🔧 API Config - Checking .env for API_BASE_URL...');
    }
    
    // 1. Check .env file first
    final envUrl = dotenv.env['API_BASE_URL'];
    if (envUrl != null && envUrl.isNotEmpty) {
      if (kDebugMode) {
        print('✅ Using .env API_BASE_URL: $envUrl');
      }
      _agentLog(
        'api_config.dart:baseUrl',
        'Using .env API_BASE_URL',
        {'value': envUrl, 'platform': kIsWeb ? 'web' : 'mobile'},
        'H1',
      );
      return envUrl;
    }
    
    // 2. Fallback to development defaults (should use .env in production!)
    if (kIsWeb) {
      // WEB - Use localhost with correct port 3001
      const webUrl = 'http://localhost:3001';
      
      if (kDebugMode) {
        print('⚠️  WARNING: Using hardcoded localhost URL. Set API_BASE_URL in .env for production!');
        print('🌐 Web platform - Using: $webUrl');
      }
      
      _agentLog(
        'api_config.dart:baseUrl',
        'Using fallback web base URL',
        {'value': webUrl, 'warning': 'Should use .env in production'},
        'H2',
      );
      return webUrl;
    } else {
      // MOBILE - Use your computer's IP with correct port 3001
      const mobileUrl = 'http://192.168.1.3:3001';
      
      if (kDebugMode) {
        print('⚠️  WARNING: Using hardcoded IP address. Set API_BASE_URL in .env for production!');
        print('📱 Mobile platform - Using: $mobileUrl');
      }
      
      _agentLog(
        'api_config.dart:baseUrl',
        'Using fallback mobile base URL',
        {'value': mobileUrl, 'warning': 'Should use .env in production'},
        'H2',
      );
      return mobileUrl;
    }
  }

  static String get wsUrl {
    if (kDebugMode) {
      print('🔧 WebSocket Config - Checking .env for WEBSOCKET_URL...');
    }
    
    final envWsUrl = dotenv.env['WEBSOCKET_URL'];
    if (envWsUrl != null && envWsUrl.isNotEmpty) {
      if (kDebugMode) {
        print('✅ Using .env WEBSOCKET_URL: $envWsUrl');
      }
      _agentLog(
        'api_config.dart:wsUrl',
        'Using .env WEBSOCKET_URL',
        {'value': envWsUrl, 'platform': kIsWeb ? 'web' : 'mobile'},
        'H1',
      );
      return envWsUrl;
    }
    
    if (kIsWeb) {
      const webWsUrl = 'ws://localhost:3001';
      
      if (kDebugMode) {
        print('⚠️  WARNING: Using hardcoded localhost WebSocket. Set WEBSOCKET_URL in .env for production!');
        print('🌐 Web WebSocket - Using: $webWsUrl');
      }
      
      _agentLog(
        'api_config.dart:wsUrl',
        'Using fallback web websocket URL',
        {'value': webWsUrl, 'warning': 'Should use .env in production'},
        'H3',
      );
      return webWsUrl;
    } else {
      const mobileWsUrl = 'ws://192.168.1.3:3001';
      
      if (kDebugMode) {
        print('⚠️  WARNING: Using hardcoded IP WebSocket. Set WEBSOCKET_URL in .env for production!');
        print('📱 Mobile WebSocket - Using: $mobileWsUrl');
      }
      
      _agentLog(
        'api_config.dart:wsUrl',
        'Using fallback mobile websocket URL',
        {'value': mobileWsUrl, 'warning': 'Should use .env in production'},
        'H3',
      );
      return mobileWsUrl;
    }
  }

  // API endpoints
  static const String driverTripsActive = '/api/driver/trips/active';
  static const String driverTripsUpdateStatus = '/api/driver/trips/update-status';
  static const String driverTripsShareLocation = '/api/driver/trips/share-location';
  static const String driverTripsEndTrip = '/api/driver/trips/end-trip';
  static const String driverTripsUpdateLocation = '/api/driver/trips/update-location';
  static const String driverTripsHistory = '/api/driver/trips/history';

  // Timeout configurations
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  static bool get isDebugMode => environment == 'development';

  static void printConfig() {
    print('\n' + '=' * 60);
    print('🚀 API CONFIGURATION');
    print('=' * 60);
    print('Environment: $environment');
    print('Platform: ${kIsWeb ? '🌐 Web' : '📱 Mobile'}');
    print('Base URL: $baseUrl');
    print('WebSocket URL: $wsUrl');
    print('Debug Mode: $isDebugMode');
    print('.env loaded: ${dotenv.isInitialized}');
    if (dotenv.isInitialized) {
      print('.env API_BASE_URL: ${dotenv.env['API_BASE_URL'] ?? 'NOT SET'}');
      print('.env WEBSOCKET_URL: ${dotenv.env['WEBSOCKET_URL'] ?? 'NOT SET'}');
    }
    print('=' * 60 + '\n');
  }
  
  static Future<bool> testConnection() async {
    try {
      print('🔍 Testing connection to: $baseUrl/health');
      return true;
    } catch (e) {
      print('❌ Connection test failed: $e');
      return false;
    }
  }
}

extension DotEnvExtension on DotEnv {
  bool get isInitialized {
    try {
      return env.isNotEmpty;
    } catch (e) {
      return false;
    }
  }
}