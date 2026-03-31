// File: lib/features/admin/vehicle_management/presentation/providers/trip_tracking_provider.dart
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:abra_fleet/core/services/websocket_service.dart';

class TripTrackingProvider with ChangeNotifier {
  final WebSocketService _webSocketService = WebSocketService();
  String? _currentTripId;
  LatLng? _currentLocation;
  String _status = 'disconnected';
  bool _isTracking = false;

  // Getters
  LatLng? get currentLocation => _currentLocation;
  String get status => _status;
  bool get isTracking => _isTracking;

  // Start tracking a trip
  void startTracking(String tripId) {
    if (_currentTripId != tripId) {
      _currentTripId = tripId;
      _webSocketService.connect(tripId);
      _setupWebSocketListeners();
      _status = 'connecting';
      _isTracking = true;
      notifyListeners();
    }
  }

  // Stop tracking
  void stopTracking() {
    _webSocketService.disconnect();
    _currentTripId = null;
    _status = 'disconnected';
    _isTracking = false;
    notifyListeners();
  }

  // Send location update to server
  void sendLocationUpdate(LatLng location, {double? speed, double? heading}) {
    _currentLocation = location;
    _webSocketService.sendMessage('LOCATION_UPDATE', {
      'latitude': location.latitude,
      'longitude': location.longitude,
      'speed': speed,
      'heading': heading,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  // Send status update to server
  void sendStatusUpdate(String status, {String? message}) {
    _status = status;
    _webSocketService.sendMessage('STATUS_UPDATE', {
      'status': status,
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
    });
    notifyListeners();
  }

  // Set up WebSocket listeners
  void _setupWebSocketListeners() {
    _webSocketService.messageStream.listen((message) {
      if (message.type == 'LOCATION_UPDATE') {
        _handleLocationUpdate(message.data);
      } else if (message.type == 'STATUS_UPDATE') {
        _handleStatusUpdate(message.data);
      }
    });
  }

  void _handleLocationUpdate(Map<String, dynamic> data) {
    _currentLocation = LatLng(
      data['latitude'],
      data['longitude'],
    );
    notifyListeners();
  }

  void _handleStatusUpdate(Map<String, dynamic> data) {
    _status = data['status'] ?? _status;
    notifyListeners();
  }

  @override
  void dispose() {
    _webSocketService.disconnect();
    super.dispose();
  }
}