// lib/core/services/enhanced_customer_tracking_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:abra_fleet/app/config/api_config.dart';

/// Enhanced service for customers to track their trip in real-time
/// Features: Live driver location, ETA, route, status updates
class EnhancedCustomerTrackingService {
  static final EnhancedCustomerTrackingService _instance = 
      EnhancedCustomerTrackingService._internal();
  factory EnhancedCustomerTrackingService() => _instance;
  EnhancedCustomerTrackingService._internal();

  Timer? _pollingTimer;
  final StreamController<TripTrackingData> _trackingController = 
      StreamController<TripTrackingData>.broadcast();

  Stream<TripTrackingData> get trackingStream => _trackingController.stream;

  /// Start tracking a trip (polls every 5 seconds)
  void startTracking(String tripId) {
    debugPrint('🚀 Starting customer tracking for trip: $tripId');
    
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchAndEmitTripData(tripId),
    );

    // Fetch immediately
    _fetchAndEmitTripData(tripId);
  }

  /// Stop tracking
  void stopTracking() {
    debugPrint('🛑 Stopping customer tracking');
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Fetch trip data and emit to stream
  Future<void> _fetchAndEmitTripData(String tripId) async {
    try {
      final data = await getTripTrackingData(tripId);
      if (data != null && !_trackingController.isClosed) {
        _trackingController.add(data);
      }
    } catch (e) {
      debugPrint('❌ Error fetching trip data: $e');
    }
  }

  /// Get complete trip tracking data (call this directly or use stream)
  Future<TripTrackingData?> getTripTrackingData(String tripId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      if (token == null) {
        debugPrint('❌ No auth token found');
        return null;
      }

      // Call backend API to get trip with driver/vehicle details
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/customer/track-trip/$tripId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true && data['data'] != null) {
          return TripTrackingData.fromJson(data['data']);
        }
      }

      debugPrint('⚠️ API returned: ${response.statusCode}');
      return null;
      
    } catch (e) {
      debugPrint('❌ Error getting trip tracking data: $e');
      return null;
    }
  }

  /// Get OSRM route between two points
  Future<List<LatLng>> getRoutePolyline(LatLng start, LatLng end) async {
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/'
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
          '?overview=full&geometries=geojson';

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final coords = route['geometry']['coordinates'] as List;
          
          return coords.map((c) => LatLng(c[1], c[0])).toList();
        }
      }
    } catch (e) {
      debugPrint('❌ Error getting route: $e');
    }
    
    // Fallback: return straight line
    return [start, end];
  }

  /// Calculate ETA in minutes
  int calculateETA(double distanceMeters, double speedMps) {
    if (speedMps < 1) {
      // Driver stopped or slow, use average city speed (20 km/h)
      speedMps = 20 / 3.6; // Convert to m/s
    }
    
    final timeSeconds = distanceMeters / speedMps;
    return (timeSeconds / 60).ceil();
  }

  /// Determine trip status based on distance and data
  TripStatus determineTripStatus(TripTrackingData data) {
    if (data.driverLocation == null) {
      return TripStatus.notStarted;
    }

    final distance = data.distanceToCustomer;

    if (distance < 50) {
      return TripStatus.arrived;
    } else if (distance < 500) {
      return TripStatus.nearby;
    } else if (data.trip.status == 'started' || data.trip.status == 'in_progress') {
      return TripStatus.onTheWay;
    } else {
      return TripStatus.notStarted;
    }
  }

  void dispose() {
    stopTracking();
    _trackingController.close();
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

enum TripStatus {
  notStarted,
  onTheWay,
  nearby,    // < 500m
  arrived,   // < 50m
  completed,
  locationUnavailable,
}

enum TripState {
  notStarted,      // Trip hasn't started yet (scheduled/assigned)
  active,          // Trip is in progress with live location
  completed,       // Trip has ended
  locationUnavailable, // Trip should be active but no location data
}

class TripTrackingData {
  final TripData trip;
  final DriverData? driver;
  final VehicleData? vehicle;
  final LocationData? driverLocation;
  final LocationData customerLocation;
  final double distanceToCustomer; // in meters
  final int eta; // in minutes
  final TripStatus status;
  final TripState tripState; // Added
  final List<LatLng>? routePolyline;

  TripTrackingData({
    required this.trip,
    this.driver,
    this.vehicle,
    this.driverLocation,
    required this.customerLocation,
    required this.distanceToCustomer,
    required this.eta,
    required this.status,
    required this.tripState,
    this.routePolyline,
  });

  factory TripTrackingData.fromJson(Map<String, dynamic> json) {
    final trip = TripData.fromJson(json['trip']);
    final driver = json['driver'] != null ? DriverData.fromJson(json['driver']) : null;
    final vehicle = json['vehicle'] != null ? VehicleData.fromJson(json['vehicle']) : null;
    
    LocationData? driverLoc;
    if (json['driverLocation'] != null) {
      driverLoc = LocationData.fromJson(json['driverLocation']);
    }
    
    final customerLoc = LocationData.fromJson(json['customerLocation']);
    
    final distance = (json['distanceToCustomer'] as num?)?.toDouble() ?? 0.0;
    final eta = (json['eta'] as num?)?.toInt() ?? 0;
    
    final statusStr = json['status'] as String? ?? 'not_started';
    TripStatus status;
    switch (statusStr.toLowerCase()) {
      case 'arrived':
        status = TripStatus.arrived;
        break;
      case 'nearby':
        status = TripStatus.nearby;
        break;
      case 'on_the_way':
      case 'started':
      case 'in_progress':
        status = TripStatus.onTheWay;
        break;
      case 'completed':
        status = TripStatus.completed;
        break;
      case 'location_unavailable':
        status = TripStatus.locationUnavailable;
        break;
      default:
        status = TripStatus.notStarted;
    }

    // Parse trip state
    final tripStateStr = json['tripState'] as String? ?? 'not_started';
    TripState tripState;
    switch (tripStateStr.toLowerCase()) {
      case 'active':
        tripState = TripState.active;
        break;
      case 'completed':
        tripState = TripState.completed;
        break;
      case 'location_unavailable':
        tripState = TripState.locationUnavailable;
        break;
      default:
        tripState = TripState.notStarted;
    }

    List<LatLng>? polyline;
    if (json['routePolyline'] != null) {
      final coords = json['routePolyline'] as List;
      polyline = coords.map((c) => LatLng(c[0], c[1])).toList();
    }

    return TripTrackingData(
      trip: trip,
      driver: driver,
      vehicle: vehicle,
      driverLocation: driverLoc,
      customerLocation: customerLoc,
      distanceToCustomer: distance,
      eta: eta,
      status: status,
      tripState: tripState,
      routePolyline: polyline,
    );
  }
}

class TripData {
  final String id;
  final String tripNumber;
  final String status;
  final String scheduledPickupTime;
  final String? actualStartTime;

  TripData({
    required this.id,
    required this.tripNumber,
    required this.status,
    required this.scheduledPickupTime,
    this.actualStartTime,
  });

  factory TripData.fromJson(Map<String, dynamic> json) {
    return TripData(
      id: json['_id'] ?? json['id'] ?? '',
      tripNumber: json['tripNumber'] ?? 'N/A',
      status: json['status'] ?? 'unknown',
      scheduledPickupTime: json['readyByTime'] ?? json['estimatedPickupTime'] ?? 'N/A',
      actualStartTime: json['actualStartTime'],
    );
  }
}

class DriverData {
  final String id;
  final String name;
  final String phone;
  final String? email;

  DriverData({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
  });

  factory DriverData.fromJson(Map<String, dynamic> json) {
    return DriverData(
      id: json['driverId'] ?? json['_id'] ?? '',
      name: json['name'] ?? json['driverName'] ?? 'Unknown Driver',
      phone: json['phone'] ?? json['driverPhone'] ?? '',
      email: json['email'],
    );
  }
}

class VehicleData {
  final String id;
  final String registrationNumber;
  final String? make;
  final String? model;
  final String? color;

  VehicleData({
    required this.id,
    required this.registrationNumber,
    this.make,
    this.model,
    this.color,
  });

  factory VehicleData.fromJson(Map<String, dynamic> json) {
    return VehicleData(
      id: json['vehicleId'] ?? json['_id'] ?? '',
      registrationNumber: json['registrationNumber'] ?? json['vehicleNumber'] ?? 'N/A',
      make: json['make'] ?? json['vehicleMake'],
      model: json['model'] ?? json['vehicleModel'],
      color: json['color'],
    );
  }
}

class LocationData {
  final double latitude;
  final double longitude;
  final DateTime? timestamp;
  final double? speed;
  final double? heading;

  LocationData({
    required this.latitude,
    required this.longitude,
    this.timestamp,
    this.speed,
    this.heading,
  });

  factory LocationData.fromJson(Map<String, dynamic> json) {
    double lat, lng;
    
    // Handle different coordinate formats
    if (json['coordinates'] != null) {
      final coords = json['coordinates'];
      if (coords is Map) {
        lat = (coords['latitude'] ?? coords[1] ?? 0).toDouble();
        lng = (coords['longitude'] ?? coords[0] ?? 0).toDouble();
      } else if (coords is List && coords.length >= 2) {
        lat = (coords[1] ?? 0).toDouble();
        lng = (coords[0] ?? 0).toDouble();
      } else {
        lat = 0;
        lng = 0;
      }
    } else {
      lat = (json['latitude'] ?? json['lat'] ?? 0).toDouble();
      lng = (json['longitude'] ?? json['lng'] ?? 0).toDouble();
    }

    DateTime? timestamp;
    if (json['timestamp'] != null) {
      if (json['timestamp'] is Map && json['timestamp']['\$date'] != null) {
        timestamp = DateTime.parse(json['timestamp']['\$date']);
      } else if (json['timestamp'] is String) {
        timestamp = DateTime.tryParse(json['timestamp']);
      }
    }

    return LocationData(
      latitude: lat,
      longitude: lng,
      timestamp: timestamp,
      speed: (json['speed'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
    );
  }

  LatLng toLatLng() => LatLng(latitude, longitude);
}