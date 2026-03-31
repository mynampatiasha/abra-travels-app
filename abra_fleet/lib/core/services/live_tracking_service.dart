// lib/services/live_tracking_service.dart
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'driver_trip_service.dart';

class LiveTrackingService {
  static final LiveTrackingService _instance = LiveTrackingService._internal();
  factory LiveTrackingService() => _instance;
  LiveTrackingService._internal();

  final DriverTripService _tripService = DriverTripService();
  
  Timer? _locationTimer;
  Timer? _etaTimer;
  Position? _lastPosition;
  String? _currentTripGroupId;
  List<Map<String, dynamic>> _stops = [];
  int _currentStopIndex = 0;
  
  bool _isTracking = false;

  // Start live tracking
  void startTracking({
    required String tripGroupId,
    required List<Map<String, dynamic>> stops,
    required int currentStopIndex,
  }) {
    print('\n📡 STARTING LIVE TRACKING');
    print('Trip: $tripGroupId');
    print('Stops: ${stops.length}');

    _currentTripGroupId = tripGroupId;
    _stops = stops;
    _currentStopIndex = currentStopIndex;
    _isTracking = true;

    // Start location updates (every 10 seconds)
    _startLocationUpdates();

    // Start ETA updates (every 30 seconds)
    _startETAUpdates();
  }

  // Stop tracking
  void stopTracking() {
    print('🛑 Stopping live tracking');
    _isTracking = false;
    _locationTimer?.cancel();
    _etaTimer?.cancel();
    _locationTimer = null;
    _etaTimer = null;
    _currentTripGroupId = null;
    _stops.clear();
  }

  // Update current stop
  void updateCurrentStop(int stopIndex) {
    _currentStopIndex = stopIndex;
  }

  // Start location updates
  void _startLocationUpdates() {
    _locationTimer?.cancel();
    
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (!_isTracking || _currentTripGroupId == null) {
        timer.cancel();
        return;
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        _lastPosition = position;

        // Send to backend
        await _tripService.updateLocation(
          tripGroupId: _currentTripGroupId!,
          latitude: position.latitude,
          longitude: position.longitude,
          speed: position.speed,
          heading: position.heading,
        );

        print('📍 Location updated: ${position.latitude}, ${position.longitude}');

      } catch (e) {
        print('❌ Location update failed: $e');
      }
    });
  }

  // Start ETA updates
  void _startETAUpdates() {
    _etaTimer?.cancel();
    
    _etaTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!_isTracking || _lastPosition == null || _currentStopIndex >= _stops.length) {
        return;
      }

      try {
        final currentStop = _stops[_currentStopIndex];
        final coordinates = currentStop['location']?['coordinates'];
        
        if (coordinates == null) return;

        final stopLat = _extractLatitude(coordinates);
        final stopLng = _extractLongitude(coordinates);

        if (stopLat == 0 || stopLng == 0) return;

        // Calculate ETA
        final eta = await _tripService.calculateETA(
          currentLat: _lastPosition!.latitude,
          currentLng: _lastPosition!.longitude,
          destinationLat: stopLat,
          destinationLng: stopLng,
        );

        print('⏱️ ETA to next stop: $eta minutes');

        // Backend will send FCM notification to customer with this ETA

      } catch (e) {
        print('❌ ETA calculation failed: $e');
      }
    });
  }

  // Helper methods
  double _extractLatitude(dynamic coords) {
    if (coords is Map) {
      return (coords['latitude'] ?? coords[1] ?? 0).toDouble();
    }
    if (coords is List && coords.length >= 2) {
      return (coords[1] ?? 0).toDouble();
    }
    return 0.0;
  }

  double _extractLongitude(dynamic coords) {
    if (coords is Map) {
      return (coords['longitude'] ?? coords[0] ?? 0).toDouble();
    }
    if (coords is List && coords.length >= 2) {
      return (coords[0] ?? 0).toDouble();
    }
    return 0.0;
  }

  void dispose() {
    stopTracking();
  }
}