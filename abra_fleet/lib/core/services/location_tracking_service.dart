import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:abra_fleet/core/services/api_service.dart';

/// Real-time GPS tracking service for drivers
/// Updates location via HTTP API every 10 seconds
class LocationTrackingService {
  final ApiService _apiService = ApiService();
  StreamSubscription<Position>? _positionStream;
  Timer? _heartbeatTimer;
  
  String? _currentDriverId;
  String? _currentTripId;
  bool _isTracking = false;

  bool get isTracking => _isTracking;

  /// Start tracking driver location
  Future<void> startTracking({
    required String driverId,
    required String tripId,
  }) async {
    if (_isTracking) {
      debugPrint('⚠️ Tracking already active');
      return;
    }

    _currentDriverId = driverId;
    _currentTripId = tripId;

    // Check location permissions
    final permission = await _checkLocationPermission();
    if (!permission) {
      throw Exception('Location permission denied');
    }

    // Start GPS tracking
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen(
      (Position position) => _updateLocation(position),
      onError: (error) => debugPrint('❌ Location error: $error'),
    );

    // Heartbeat to mark driver as online
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _sendHeartbeat(),
    );

    _isTracking = true;
    debugPrint('✅ Started tracking for driver: $driverId, trip: $tripId');
  }

  /// Stop tracking
  Future<void> stopTracking() async {
    await _positionStream?.cancel();
    _heartbeatTimer?.cancel();
    
    if (_currentDriverId != null) {
      // Mark driver as offline via HTTP API
      try {
        await _apiService.put('/api/live-locations/$_currentDriverId', body: {
          'isOnline': false,
          'lastSeen': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('Error marking driver offline: $e');
      }
    }

    _isTracking = false;
    _currentDriverId = null;
    _currentTripId = null;
    
    debugPrint('🛑 Stopped tracking');
  }

  /// Update location via HTTP API
  Future<void> _updateLocation(Position position) async {
    if (_currentDriverId == null || _currentTripId == null) return;

    try {
      await _apiService.post('/api/live-locations', body: {
        'driverId': _currentDriverId,
        'tripId': _currentTripId,
        'lat': position.latitude,
        'lng': position.longitude,
        'speed': position.speed, // m/s
        'heading': position.heading, // degrees
        'accuracy': position.accuracy, // meters
        'timestamp': DateTime.now().toIso8601String(),
        'isOnline': true,
        'lastSeen': DateTime.now().toIso8601String(),
      });

      debugPrint('📍 Location updated: ${position.latitude}, ${position.longitude}');
      
      // Check if near any customer (geofencing)
      await _checkGeofences(position);
      
    } catch (e) {
      debugPrint('❌ Failed to update location: $e');
    }
  }

  /// Send heartbeat to show driver is online
  Future<void> _sendHeartbeat() async {
    if (_currentDriverId == null) return;

    try {
      await _apiService.put('/api/live-locations/$_currentDriverId', body: {
        'lastSeen': DateTime.now().toIso8601String(),
        'isOnline': true,
      });
    } catch (e) {
      debugPrint('❌ Heartbeat failed: $e');
    }
  }

  /// Check if driver is near any customer (geofencing)
  Future<void> _checkGeofences(Position driverPosition) async {
    if (_currentTripId == null) return;

    try {
      // Get trip details with customer locations via HTTP API
      final response = await _apiService.get('/api/trips/$_currentTripId');
      
      if (response['success'] != true || response['trip'] == null) return;

      final tripData = response['trip'];
      final customers = tripData['customers'] as List<dynamic>? ?? [];

      for (final customer in customers) {
        final customerLat = customer['lat'] as double?;
        final customerLng = customer['lng'] as double?;
        final customerId = customer['customerId'] as String?;
        final isPickedUp = customer['isPickedUp'] as bool? ?? false;

        if (customerLat == null || customerLng == null || customerId == null) continue;
        if (isPickedUp) continue; // Already picked up

        // Calculate distance
        final distance = Geolocator.distanceBetween(
          driverPosition.latitude,
          driverPosition.longitude,
          customerLat,
          customerLng,
        );

        // If within 500 meters, send "arriving soon" notification
        if (distance <= 500) {
          await _sendArrivingSoonNotification(customerId, distance);
        }
      }
    } catch (e) {
      debugPrint('❌ Geofence check failed: $e');
    }
  }

  /// Send "arriving soon" notification to customer via HTTP API
  Future<void> _sendArrivingSoonNotification(String customerId, double distance) async {
    try {
      final eta = _calculateETA(distance);
      
      await _apiService.post('/api/notifications', body: {
        'userId': customerId,
        'title': '🚗 Vehicle Arriving Soon',
        'body': 'Your vehicle is ${distance.round()} meters away (ETA: $eta mins)',
        'type': 'arriving_soon',
        'tripId': _currentTripId,
        'timestamp': DateTime.now().toIso8601String(),
        'isRead': false,
      });

      debugPrint('📢 Sent arriving notification to customer: $customerId');
    } catch (e) {
      debugPrint('❌ Failed to send notification: $e');
    }
  }

  /// Calculate ETA based on distance
  int _calculateETA(double distanceInMeters) {
    // Assume average speed of 20 km/h in city traffic
    const avgSpeedKmh = 20.0;
    final distanceKm = distanceInMeters / 1000;
    final timeHours = distanceKm / avgSpeedKmh;
    final timeMinutes = (timeHours * 60).ceil();
    return timeMinutes;
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

  /// Get current location once
  Future<Position?> getCurrentLocation() async {
    try {
      final permission = await _checkLocationPermission();
      if (!permission) return null;

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      debugPrint('❌ Failed to get current location: $e');
      return null;
    }
  }

  /// Stream driver location via HTTP polling (every 5 seconds)
  Stream<Map<String, dynamic>?> streamDriverLocation(String driverId) {
    return Stream.periodic(Duration(seconds: 5), (_) async {
      try {
        final response = await _apiService.get('/api/live-locations/$driverId');
        return response['location'] as Map<String, dynamic>?;
      } catch (e) {
        debugPrint('Error fetching driver location: $e');
        return null;
      }
    }).asyncMap((future) => future);
  }

  /// Get all active drivers on map via HTTP polling (every 10 seconds)
  Stream<List<Map<String, dynamic>>> streamAllActiveDrivers() {
    return Stream.periodic(Duration(seconds: 10), (_) async {
      try {
        final response = await _apiService.get('/api/live-locations', queryParams: {
          'isOnline': 'true',
        });
        return List<Map<String, dynamic>>.from(response['locations'] ?? []);
      } catch (e) {
        debugPrint('Error fetching active drivers: $e');
        return <Map<String, dynamic>>[];
      }
    }).asyncMap((future) => future);
  }

  /// Calculate distance between two points (in meters)
  double calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
  }
}
