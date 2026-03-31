import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'api_service.dart';
import 'websocket_service.dart';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

class BackendConnectionManager {
  static final BackendConnectionManager _instance = BackendConnectionManager._internal();
  
  final ApiService _apiService = ApiService();
  final WebSocketService _wsService = WebSocketService();

  // #region agent log
  void _agentLog(String location, String message, Map<String, dynamic> data, String hypothesisId) {
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
      File(r'd:\Documents\Fleet_Management\.cursor\debug.log')
          .writeAsStringSync('$payload\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
  // #endregion
  
  final ValueNotifier<ConnectionStatus> _connectionStatus = ValueNotifier(ConnectionStatus.disconnected);
  final ValueNotifier<String?> _lastError = ValueNotifier(null);
  
  Timer? _healthCheckTimer;
  String? _currentTripId;
  String? _authToken;
  
  factory BackendConnectionManager() => _instance;
  
  BackendConnectionManager._internal();

  // Getters
  ValueNotifier<ConnectionStatus> get connectionStatus => _connectionStatus;
  ValueNotifier<String?> get lastError => _lastError;
  ApiService get apiService => _apiService;
  WebSocketService get wsService => _wsService;
  bool get isConnected => _connectionStatus.value == ConnectionStatus.connected;

  // Initialize the connection manager
  Future<void> initialize() async {
    try {
      if (kIsWeb) {
        // For web, environment variables should already be set in main
        debugPrint('✅ Web environment detected, using existing configuration');
        _agentLog(
          'backend_connection_manager.dart:initialize',
          'Web detected, skipping .env load',
          {'platform': 'web'},
          'H1',
        );
      } else {
        await dotenv.load(fileName: ".env");
        debugPrint('✅ Environment variables loaded');
        _agentLog(
          'backend_connection_manager.dart:initialize',
          '.env loaded on mobile',
          {
            'apiBaseUrl': dotenv.env['API_BASE_URL'],
            'wsUrl': dotenv.env['WEBSOCKET_URL'],
          },
          'H1',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Warning: Could not load .env file: $e');
      // Set defaults if not already set
      if (dotenv.env['API_BASE_URL'] == null) {
        dotenv.env['API_BASE_URL'] = 'http://localhost:3001';
        dotenv.env['WEBSOCKET_URL'] = 'ws://localhost:3001';
        debugPrint('✅ Using default configuration');
        _agentLog(
          'backend_connection_manager.dart:initialize',
          'Dotenv load failed, using defaults',
          {
            'apiBaseUrl': dotenv.env['API_BASE_URL'],
            'wsUrl': dotenv.env['WEBSOCKET_URL'],
            'error': e.toString(),
          },
          'H2',
        );
      } else {
        _agentLog(
          'backend_connection_manager.dart:initialize',
          'Dotenv load failed but env already set',
          {
            'apiBaseUrl': dotenv.env['API_BASE_URL'],
            'wsUrl': dotenv.env['WEBSOCKET_URL'],
            'error': e.toString(),
          },
          'H2',
        );
      }
    }
    
    // Start periodic health checks
    _startHealthCheck();
  }

  // Set authentication token for both API and WebSocket
  void setAuthToken(String token) {
    _authToken = token;
    _apiService.setAuthToken(token);
  }

  // Clear authentication token
  void clearAuthToken() {
    _authToken = null;
    _apiService.clearAuthToken();
  }

  // Connect to backend services
  Future<void> connect({String? tripId}) async {
    if (_connectionStatus.value == ConnectionStatus.connecting) {
      debugPrint('Already connecting...');
      return;
    }

    _connectionStatus.value = ConnectionStatus.connecting;
    _lastError.value = null;

    try {
      // Test API connectivity first
      debugPrint('🔄 Testing API connectivity...');
      final isApiHealthy = await _apiService.checkHealth();
      
      if (!isApiHealthy) {
        throw Exception('API server is not responding');
      }

      debugPrint('✅ API connection established');

      // Connect to WebSocket if tripId is provided
      if (tripId != null) {
        _currentTripId = tripId;
        debugPrint('🔄 Connecting to WebSocket for trip: $tripId');
        await _wsService.connect(tripId, authToken: _authToken);
        debugPrint('✅ WebSocket connection established');
      }

      _connectionStatus.value = ConnectionStatus.connected;
      debugPrint('🎉 Backend connection fully established');
      
    } catch (e) {
      debugPrint('❌ Backend connection failed: $e');
      _lastError.value = e.toString();
      _connectionStatus.value = ConnectionStatus.error;
      
      // Schedule reconnection attempt
      _scheduleReconnection(tripId: tripId);
      rethrow;
    }
  }

  // Disconnect from backend services
  Future<void> disconnect() async {
    debugPrint('🔄 Disconnecting from backend...');
    
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
    
    await _wsService.disconnect();
    _currentTripId = null;
    
    _connectionStatus.value = ConnectionStatus.disconnected;
    debugPrint('✅ Disconnected from backend');
  }

  // Reconnect to backend services
  Future<void> reconnect() async {
    debugPrint('🔄 Reconnecting to backend...');
    _connectionStatus.value = ConnectionStatus.reconnecting;
    
    try {
      await disconnect();
      await connect(tripId: _currentTripId);
    } catch (e) {
      debugPrint('❌ Reconnection failed: $e');
      _lastError.value = e.toString();
      _connectionStatus.value = ConnectionStatus.error;
    }
  }

  // Connect to a specific trip's WebSocket
  Future<void> connectToTrip(String tripId) async {
    _currentTripId = tripId;
    
    if (_connectionStatus.value == ConnectionStatus.connected) {
      // Already connected to API, just connect WebSocket
      try {
        await _wsService.connect(tripId, authToken: _authToken);
      } catch (e) {
        debugPrint('❌ Failed to connect to trip WebSocket: $e');
        _lastError.value = e.toString();
        rethrow;
      }
    } else {
      // Full connection including API
      await connect(tripId: tripId);
    }
  }

  // Disconnect from current trip WebSocket
  Future<void> disconnectFromTrip() async {
    await _wsService.disconnect();
    _currentTripId = null;
  }

  // Start periodic health checks
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (_connectionStatus.value == ConnectionStatus.connected) {
        try {
          final isHealthy = await _apiService.checkHealth();
          if (!isHealthy) {
            debugPrint('⚠️ Health check failed, attempting reconnection...');
            await reconnect();
          }
        } catch (e) {
          debugPrint('⚠️ Health check error: $e');
          _lastError.value = e.toString();
          _connectionStatus.value = ConnectionStatus.error;
        }
      }
    });
  }

  // Schedule reconnection attempt
  void _scheduleReconnection({String? tripId}) {
    Timer(const Duration(seconds: 5), () async {
      if (_connectionStatus.value == ConnectionStatus.error) {
        debugPrint('🔄 Attempting scheduled reconnection...');
        try {
          await connect(tripId: tripId);
        } catch (e) {
          debugPrint('❌ Scheduled reconnection failed: $e');
        }
      }
    });
  }

  // Send location update via WebSocket
  Future<void> sendLocationUpdate(double latitude, double longitude, {Map<String, dynamic>? additionalData}) async {
    if (!_wsService.isConnected.value) {
      throw Exception('WebSocket not connected');
    }

    final data = {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().toIso8601String(),
      ...?additionalData,
    };

    await _wsService.sendMessage('LOCATION_UPDATE', data);
  }

  // Send status update via WebSocket
  Future<void> sendStatusUpdate(String status, {Map<String, dynamic>? additionalData}) async {
    if (!_wsService.isConnected.value) {
      throw Exception('WebSocket not connected');
    }

    final data = {
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
      ...?additionalData,
    };

    await _wsService.sendMessage('STATUS_UPDATE', data);
  }

  // Send emergency alert via WebSocket
  Future<void> sendEmergencyAlert(String message, {Map<String, dynamic>? additionalData}) async {
    if (!_wsService.isConnected.value) {
      throw Exception('WebSocket not connected');
    }

    final data = {
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
      'priority': 'high',
      ...?additionalData,
    };

    await _wsService.sendMessage('EMERGENCY_ALERT', data);
  }

  // Get connection info for debugging
  Map<String, dynamic> getConnectionInfo() {
    return {
      'status': _connectionStatus.value.toString(),
      'lastError': _lastError.value,
      'currentTripId': _currentTripId,
      'hasAuthToken': _authToken != null,
      'apiBaseUrl': dotenv.env['API_BASE_URL'] ?? 'Not configured',
      'websocketUrl': dotenv.env['WEBSOCKET_URL'] ?? 'Not configured',
      'wsConnected': _wsService.isConnected.value,
      'wsLastConnection': _wsService.lastConnectionTime.value?.toIso8601String(),
    };
  }

  // Dispose resources
  void dispose() {
    _healthCheckTimer?.cancel();
    _wsService.dispose();
    _connectionStatus.dispose();
    _lastError.dispose();
  }
}
