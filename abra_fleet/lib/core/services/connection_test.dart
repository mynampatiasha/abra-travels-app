import 'package:flutter/foundation.dart';
import 'backend_connection_manager.dart';
import 'api_service.dart';
import 'websocket_service.dart';

class ConnectionTestResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? details;
  final Duration? responseTime;

  ConnectionTestResult({
    required this.success,
    required this.message,
    this.details,
    this.responseTime,
  });
}

class ConnectionTest {
  static final BackendConnectionManager _connectionManager = BackendConnectionManager();
  static final ApiService _apiService = ApiService();
  static final WebSocketService _wsService = WebSocketService();
  
  // Test authentication token
  static const String testToken = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6InRlc3QtdXNlci0xMjMiLCJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20iLCJyb2xlIjoiYWRtaW4iLCJpYXQiOjE3NTc1ODU1MTYsImV4cCI6MTc1NzY3MTkxNn0.6t1r1_w553gJFW_Z_cyAjBLB08WkZyelz0BYwQWnAgQ';

  // Test all backend connections
  static Future<Map<String, ConnectionTestResult>> testAllConnections({
    String? tripId,
    String? authToken,
  }) async {
    final results = <String, ConnectionTestResult>{};

    // Initialize connection manager and set auth token
    await _connectionManager.initialize();
    _connectionManager.setAuthToken(authToken ?? testToken);
    _apiService.setAuthToken(authToken ?? testToken);

    // Test API connection
    results['api'] = await testApiConnection();

    // Test WebSocket connection if tripId provided
    if (tripId != null) {
      results['websocket'] = await testWebSocketConnection(tripId, authToken: authToken);
    }

    // Test full connection manager
    results['connection_manager'] = await testConnectionManager(tripId: tripId);

    return results;
  }

  // Test API connection
  static Future<ConnectionTestResult> testApiConnection() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      debugPrint('🧪 Testing API connection...');
      
      final isHealthy = await _apiService.checkHealth();
      stopwatch.stop();
      
      if (isHealthy) {
        return ConnectionTestResult(
          success: true,
          message: 'API connection successful',
          responseTime: stopwatch.elapsed,
          details: {
            'endpoint': 'health check',
            'response_time_ms': stopwatch.elapsedMilliseconds,
          },
        );
      } else {
        return ConnectionTestResult(
          success: false,
          message: 'API health check failed',
          responseTime: stopwatch.elapsed,
        );
      }
    } catch (e) {
      stopwatch.stop();
      return ConnectionTestResult(
        success: false,
        message: 'API connection failed: $e',
        responseTime: stopwatch.elapsed,
        details: {'error': e.toString()},
      );
    }
  }

  // Test WebSocket connection
  static Future<ConnectionTestResult> testWebSocketConnection(
    String tripId, {
    String? authToken,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      debugPrint('🧪 Testing WebSocket connection...');
      
      // Connect to WebSocket
      await _wsService.connect(tripId, authToken: authToken);
      
      // Wait a moment for connection to establish
      await Future.delayed(const Duration(milliseconds: 500));
      
      stopwatch.stop();
      
      if (_wsService.isConnected.value) {
        // Clean up
        await _wsService.disconnect();
        
        return ConnectionTestResult(
          success: true,
          message: 'WebSocket connection successful',
          responseTime: stopwatch.elapsed,
          details: {
            'trip_id': tripId,
            'connection_time_ms': stopwatch.elapsedMilliseconds,
          },
        );
      } else {
        return ConnectionTestResult(
          success: false,
          message: 'WebSocket connection failed to establish',
          responseTime: stopwatch.elapsed,
        );
      }
    } catch (e) {
      stopwatch.stop();
      // Clean up on error
      try {
        await _wsService.disconnect();
      } catch (_) {}
      
      return ConnectionTestResult(
        success: false,
        message: 'WebSocket connection failed: $e',
        responseTime: stopwatch.elapsed,
        details: {'error': e.toString()},
      );
    }
  }

  // Test connection manager
  static Future<ConnectionTestResult> testConnectionManager({String? tripId}) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      debugPrint('🧪 Testing Connection Manager...');
      
      // Test connection
      await _connectionManager.connect(tripId: tripId);
      
      stopwatch.stop();
      
      if (_connectionManager.isConnected) {
        final connectionInfo = _connectionManager.getConnectionInfo();
        
        // Clean up
        await _connectionManager.disconnect();
        
        return ConnectionTestResult(
          success: true,
          message: 'Connection Manager working correctly',
          responseTime: stopwatch.elapsed,
          details: connectionInfo,
        );
      } else {
        return ConnectionTestResult(
          success: false,
          message: 'Connection Manager failed to establish connection',
          responseTime: stopwatch.elapsed,
        );
      }
    } catch (e) {
      stopwatch.stop();
      // Clean up on error
      try {
        await _connectionManager.disconnect();
      } catch (_) {}
      
      return ConnectionTestResult(
        success: false,
        message: 'Connection Manager failed: $e',
        responseTime: stopwatch.elapsed,
        details: {'error': e.toString()},
      );
    }
  }

  // Test specific API endpoints
  static Future<Map<String, ConnectionTestResult>> testApiEndpoints({
    String? authToken,
  }) async {
    final results = <String, ConnectionTestResult>{};
    
    // Set auth token (use test token if none provided)
    _apiService.setAuthToken(authToken ?? testToken);

    // Test vehicles endpoint
    results['vehicles'] = await _testEndpoint(
      'vehicles',
      () => _apiService.getVehicles(),
    );

    // Test drivers endpoint
    results['drivers'] = await _testEndpoint(
      'drivers',
      () => _apiService.getDrivers(),
    );

    // Test trips endpoint
    results['trips'] = await _testEndpoint(
      'trips',
      () => _apiService.getTrips(),
    );

    return results;
  }

  static Future<ConnectionTestResult> _testEndpoint(
    String endpointName,
    Future<dynamic> Function() testFunction,
  ) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      debugPrint('🧪 Testing $endpointName endpoint...');
      
      final result = await testFunction();
      stopwatch.stop();
      
      return ConnectionTestResult(
        success: true,
        message: '$endpointName endpoint working',
        responseTime: stopwatch.elapsed,
        details: {
          'endpoint': endpointName,
          'response_time_ms': stopwatch.elapsedMilliseconds,
          'data_received': result != null,
        },
      );
    } catch (e) {
      stopwatch.stop();
      return ConnectionTestResult(
        success: false,
        message: '$endpointName endpoint failed: $e',
        responseTime: stopwatch.elapsed,
        details: {'error': e.toString()},
      );
    }
  }

  // Generate a comprehensive test report
  static String generateTestReport(Map<String, ConnectionTestResult> results) {
    final buffer = StringBuffer();
    buffer.writeln('🔍 Backend Connection Test Report');
    buffer.writeln('=' * 40);
    buffer.writeln();
    
    int passed = 0;
    int total = results.length;
    
    for (final entry in results.entries) {
      final testName = entry.key;
      final result = entry.value;
      
      final status = result.success ? '✅ PASS' : '❌ FAIL';
      final time = result.responseTime != null 
          ? ' (${result.responseTime!.inMilliseconds}ms)'
          : '';
      
      buffer.writeln('$status $testName$time');
      buffer.writeln('   ${result.message}');
      
      if (result.details != null) {
        result.details!.forEach((key, value) {
          buffer.writeln('   - $key: $value');
        });
      }
      
      buffer.writeln();
      
      if (result.success) passed++;
    }
    
    buffer.writeln('Summary: $passed/$total tests passed');
    
    if (passed == total) {
      buffer.writeln('🎉 All tests passed! Backend is ready.');
    } else {
      buffer.writeln('⚠️ Some tests failed. Check your backend configuration.');
    }
    
    return buffer.toString();
  }
}
