// File: lib/core/services/backend_location_tracking_service.dart
// Real-time GPS tracking with Backend API + WebSocket

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class BackendLocationTrackingService {
  Timer? _locationTimer;
  Timer? _heartbeatTimer;
  WebSocketChannel? _wsChannel;
  
  String? _currentDriverId;
  String? _currentTripId;
  String? _vehicleId;
  bool _isTracking = false;

  bool get isTracking => _isTracking;

  /// Start tracking driver location
  Future<void> startTracking({
    required String driverId,
    String? tripId,
    String? vehicleId,
  }) async {
    if (_isTracking) {
      debugPrint('⚠️  Tracking already active');
      return;
    }

    _currentDriverId = driverId;
    _currentTripId = tripId;
    _vehicleId = vehicleId;

    // Check permissions
    final permission = await _checkLocationPermission();
    if (!permission) {
      throw Exception('Location permission denied');
    }

    // Connect WebSocket if tripId provided
    if (tripId != null) {
      await _connectWebSocket(tripId);
    }

    // Start sending location every 30 seconds
    _locationTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _sendLocationUpdate(),
    );

    // Send heartbeat every minute
    _heartbeatTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _sendHeartbeat(),
    );

    // Send initial location immediately
    await _sendLocationUpdate();

    _isTracking = true;
    debugPrint('✅ Started backend tracking for driver: $driverId');
  }

  /// Stop tracking
  Future<void> stopTracking() async {
    _locationTimer?.cancel();
    _heartbeatTimer?.cancel();
    _wsChannel?.sink.close();
    
    _isTracking = false;
    _currentDriverId = null;
    _currentTripId = null;
    _vehicleId = null;
    
    debugPrint('🛑 Stopped backend tracking');
  }

  /// Send location update to backend
  Future<void> _sendLocationUpdate() async {
    if (_currentDriverId == null) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        debugPrint('❌ User not authenticated');
        return;
      }
      
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/tracking/driver/location'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'speed': position.speed,
          'heading': position.heading,
          'accuracy': position.accuracy,
          'altitude': position.altitude,
          if (_vehicleId != null) 'vehicleId': _vehicleId,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('📍 Location updated: ${data['data']['updatedTrips']} trips');
      } else {
        debugPrint('❌ Location update failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Failed to send location: $e');
    }
  }

  /// Send heartbeat
  Future<void> _sendHeartbeat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) return;
      
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/tracking/heartbeat'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('💓 Heartbeat sent');
    } catch (e) {
      debugPrint('❌ Heartbeat failed: $e');
    }
  }

  /// Connect to WebSocket for real-time updates
  Future<void> _connectWebSocket(String tripId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) return;
      
      final wsUrl = ApiConfig.baseUrl.replaceFirst('http', 'ws');
      _wsChannel = WebSocketChannel.connect(
        Uri.parse('$wsUrl?tripId=$tripId&token=$token'),
      );

      _wsChannel!.stream.listen(
        (message) {
          debugPrint('📡 WebSocket message: $message');
          _handleWebSocketMessage(message);
        },
        onError: (error) {
          debugPrint('❌ WebSocket error: $error');
        },
        onDone: () {
          debugPrint('🔌 WebSocket disconnected');
        },
      );

      debugPrint('✅ WebSocket connected for trip: $tripId');
    } catch (e) {
      debugPrint('❌ WebSocket connection failed: $e');
    }
  }

  /// Handle WebSocket messages
  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = json.decode(message);
      final type = data['type'];
      
      switch (type) {
        case 'CONNECTION_ESTABLISHED':
          debugPrint('✅ WebSocket connection confirmed');
          break;
        case 'LOCATION_UPDATE':
          debugPrint('📍 Location update received');
          break;
        case 'STATUS_UPDATE':
          debugPrint('🔄 Status update received');
          break;
        default:
          debugPrint('📨 Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('❌ Failed to handle WebSocket message: $e');
    }
  }

  /// Check location permissions
  Future<bool> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('❌ Location services disabled');
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('❌ Location permission denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('❌ Location permission permanently denied');
      return false;
    }

    return true;
  }

  /// Get current driver location from backend
  Future<Map<String, dynamic>?> getDriverLocation(String driverId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) return null;
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/tracking/driver/$driverId/location'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data'];
      }
    } catch (e) {
      debugPrint('❌ Failed to get driver location: $e');
    }
    return null;
  }

  /// Get trip location from backend
  Future<Map<String, dynamic>?> getTripLocation(String tripId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) return null;
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/tracking/trip/$tripId/location'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['data'];
      }
    } catch (e) {
      debugPrint('❌ Failed to get trip location: $e');
    }
    return null;
  }

  /// Get complete trip tracking data (for EnhancedTrackingScreen)
  Future<Map<String, dynamic>?> getTripTrackingData(String tripId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        debugPrint('❌ No auth token found');
        return null;
      }
      
      debugPrint('🔍 Fetching trip tracking data for: $tripId');
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/live-track/$tripId/data'),
        headers: {'Authorization': 'Bearer $token'},
      );

      debugPrint('📡 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          debugPrint('✅ Trip data fetched successfully');
          return data['data'];
        } else {
          debugPrint('⚠️ API returned success=false: ${data['message']}');
          return null;
        }
      } else if (response.statusCode == 404) {
        debugPrint('❌ Trip not found: $tripId');
        return null;
      } else {
        debugPrint('❌ Failed to fetch trip data: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Failed to get trip tracking data: $e');
    }
    return null;
  }

  /// Stream driver location (polling every 10 seconds)
  Stream<Map<String, dynamic>?> streamDriverLocation(String driverId) async* {
    while (true) {
      final location = await getDriverLocation(driverId);
      yield location;
      await Future.delayed(const Duration(seconds: 10));
    }
  }

  /// Stream trip location (polling every 10 seconds)
  Stream<Map<String, dynamic>?> streamTripLocation(String tripId) async* {
    while (true) {
      final location = await getTripLocation(tripId);
      yield location;
      await Future.delayed(const Duration(seconds: 10));
    }
  }

  /// Get all active drivers (for admin map)
  Future<List<Map<String, dynamic>>> getAllActiveDrivers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) return [];
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/tracking/all-active-drivers'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['data']['drivers'] ?? []);
      }
    } catch (e) {
      debugPrint('❌ Failed to get active drivers: $e');
    }
    return [];
  }

  /// Calculate distance between two points
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }
}