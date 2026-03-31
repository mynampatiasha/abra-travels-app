// Driver Route Service - Handles today's route and customer details
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class DriverRouteService {
  final String baseUrl = ApiConfig.baseUrl;

  Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getAuthToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }
  /// ✅ NEW: Get driver's trip count for today (for multi-trip tracking)
  Future<int> getTodayTripCount() async {
    try {
      final token = await _getAuthToken();
      if (token == null) return 0;

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null) throw Exception('User not authenticated');

      final response = await http.get(
        Uri.parse('$baseUrl/api/trips/driver/$userId/today'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['count'] ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint('Error getting trip count: $e');
      return 0;
    }
  }

  /// ✅ NEW: Update trip status (assigned → started → in_progress → completed)
  Future<bool> updateTripStatus(String tripId, String status) async {
    try {
      final headers = await _getHeaders();

      final response = await http.post(
        Uri.parse('$baseUrl/api/trips/$tripId/status'),
        headers: headers,
        body: json.encode({'status': status}),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error updating trip status: $e');
      return false;
    }
  }

  /// ✅ NEW: Share location for trip tracking
  Future<bool> shareLocationForTrip(String tripId, double latitude, double longitude) async {
    try {
      final headers = await _getHeaders();

      final response = await http.post(
        Uri.parse('$baseUrl/api/trips/$tripId/location'),
        headers: headers,
        body: json.encode({
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error sharing location: $e');
      return false;
    }
  }

  /// Get today's complete route with all assigned customers
  Future<TodayRouteResponse?> getTodayRoute() async {
    try {
      print('🚗 [DriverRouteService] Fetching today\'s route...');
      final headers = await _getHeaders();
      print('🔑 [DriverRouteService] Headers prepared');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/driver/route/today'),
        headers: headers,
      );

      print('📡 [DriverRouteService] Response status: ${response.statusCode}');
      print('📄 [DriverRouteService] Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ [DriverRouteService] Decoded JSON successfully');
        print('📊 [DriverRouteService] Data status: ${data['status']}');
        print('📊 [DriverRouteService] Has data: ${data['data'] != null}');
        
        if (data['status'] == 'success' && data['data'] != null) {
          print('🔍 [DriverRouteService] Parsing TodayRouteResponse...');
          print('📦 [DriverRouteService] Data keys: ${data['data'].keys.toList()}');
          print('📦 [DriverRouteService] hasRoute: ${data['data']['hasRoute']}');
          
          try {
            final routeResponse = TodayRouteResponse.fromJson(data['data']);
            print('✅ [DriverRouteService] Successfully parsed route response');
            print('   - hasRoute: ${routeResponse.hasRoute}');
            print('   - customers count: ${routeResponse.customers?.length ?? 0}');
            return routeResponse;
          } catch (parseError) {
            print('❌ [DriverRouteService] Error parsing response: $parseError');
            print('   Stack trace: ${StackTrace.current}');
            rethrow;
          }
        } else {
          print('⚠️  [DriverRouteService] No valid data in response');
        }
      } else {
        print('❌ [DriverRouteService] Bad status code: ${response.statusCode}');
      }
      return null;
    } catch (e, stackTrace) {
      print('❌ [DriverRouteService] Error fetching today route: $e');
      print('   Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Update customer status (picked_up, dropped_off, etc.)
  Future<bool> updateCustomerStatus(String rosterId, String status) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/driver/route/update-customer-status'),
        headers: headers,
        body: json.encode({
          'rosterId': rosterId,
          'status': status,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'success';
      }
      return false;
    } catch (e) {
      print('Error updating customer status: $e');
      return false;
    }
  }

  /// Mark customer as picked up
  Future<bool> markCustomerPicked(String rosterId, {double? latitude, double? longitude}) async {
    try {
      final headers = await _getHeaders();
      final body = <String, dynamic>{'rosterId': rosterId};
      if (latitude != null && longitude != null) {
        body['latitude'] = latitude;
        body['longitude'] = longitude;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/driver/route/mark-customer-picked'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'success';
      }
      return false;
    } catch (e) {
      print('Error marking customer picked: $e');
      return false;
    }
  }

  /// Mark customer as dropped off
  Future<bool> markCustomerDropped(String rosterId, {double? latitude, double? longitude}) async {
    try {
      final headers = await _getHeaders();
      final body = <String, dynamic>{'rosterId': rosterId};
      if (latitude != null && longitude != null) {
        body['latitude'] = latitude;
        body['longitude'] = longitude;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/driver/route/mark-customer-dropped'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'success';
      }
      return false;
    } catch (e) {
      print('Error marking customer dropped: $e');
      return false;
    }
  }

  /// Get navigation details for a specific customer
  Future<NavigationDetails?> getNavigationDetails(String rosterId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/driver/route/navigation/$rosterId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          return NavigationDetails.fromJson(data['data']);
        }
      }
      return null;
    } catch (e) {
      print('Error fetching navigation details: $e');
      rethrow;
    }
  }
}

// Models
class TodayRouteResponse {
  final bool hasRoute;
  final String? message;
  final VehicleDetails? vehicle;
  final RouteSummary? routeSummary;
  final List<CustomerAssignment>? customers;
  final RouteOptimization? routeOptimization;
  final String? rosterId;
  final DateTime? scheduledDate;
  final String? tripId; // Add tripId property

  TodayRouteResponse({
    required this.hasRoute,
    this.message,
    this.vehicle,
    this.routeSummary,
    this.customers,
    this.routeOptimization,
    this.rosterId,
    this.scheduledDate,
    this.tripId, // Add tripId parameter
  });

  factory TodayRouteResponse.fromJson(Map<String, dynamic> json) {
    return TodayRouteResponse(
      hasRoute: json['hasRoute'] ?? false,
      message: json['message'],
      vehicle: json['vehicle'] != null ? VehicleDetails.fromJson(json['vehicle']) : null,
      routeSummary: json['routeSummary'] != null ? RouteSummary.fromJson(json['routeSummary']) : null,
      customers: json['customers'] != null
          ? (json['customers'] as List).map((c) => CustomerAssignment.fromJson(c)).toList()
          : null,
      routeOptimization: json['routeOptimization'] != null
          ? RouteOptimization.fromJson(json['routeOptimization'])
          : null,
      rosterId: json['rosterId'],
      scheduledDate: json['scheduledDate'] != null ? DateTime.parse(json['scheduledDate']) : null,
      tripId: json['tripId'], // Add tripId parsing
    );
  }
}

class VehicleDetails {
  final String id;
  final String registrationNumber;
  final String model;
  final String? make;
  final int? capacity;
  final int? totalCapacity;
  final int? availableSeats;
  final String? fuelType;
  final String? status;

  VehicleDetails({
    required this.id,
    required this.registrationNumber,
    required this.model,
    this.make,
    this.capacity,
    this.totalCapacity,
    this.availableSeats,
    this.fuelType,
    this.status,
  });

  factory VehicleDetails.fromJson(Map<String, dynamic> json) {
    print('🔍 [VehicleDetails] Parsing: $json');
    
    // Handle capacity - can be int or object {seating: X, standing: Y}
    int? capacityValue;
    if (json['capacity'] != null) {
      if (json['capacity'] is int) {
        capacityValue = json['capacity'] as int;
      } else if (json['capacity'] is Map) {
        // If it's an object, use seating capacity
        final capacityMap = json['capacity'] as Map<String, dynamic>;
        capacityValue = capacityMap['seating'] as int?;
      }
    }
    
    return VehicleDetails(
      id: json['id']?.toString() ?? '',
      registrationNumber: json['registrationNumber']?.toString() ?? 'Unknown',
      model: json['model']?.toString() ?? 'Unknown',
      make: json['make']?.toString(),
      capacity: capacityValue,
      totalCapacity: json['totalCapacity'] as int?,
      availableSeats: json['availableSeats'] as int?,
      fuelType: json['fuelType']?.toString(),
      status: json['status']?.toString(),
    );
  }
}

class RouteSummary {
  final int totalCustomers;
  final int completedCustomers;
  final int pendingCustomers;
  final double totalDistance;
  final int estimatedDuration;
  final String routeType;
  final int? availableSeats;

  RouteSummary({
    required this.totalCustomers,
    required this.completedCustomers,
    required this.pendingCustomers,
    required this.totalDistance,
    required this.estimatedDuration,
    required this.routeType,
    this.availableSeats,
  });

  factory RouteSummary.fromJson(Map<String, dynamic> json) {
    return RouteSummary(
      totalCustomers: json['totalCustomers'] ?? 0,
      completedCustomers: json['completedCustomers'] ?? 0,
      pendingCustomers: json['pendingCustomers'] ?? 0,
      totalDistance: (json['totalDistance'] ?? 0).toDouble(),
      estimatedDuration: json['estimatedDuration'] ?? 0,
      routeType: json['routeType'] ?? 'mixed',
      availableSeats: json['availableSeats'] as int?,
    );
  }
}

class CustomerAssignment {
  final String id;
  final String customerId;
  final String name;
  final String phone;
  final String? email;
  final String tripType; // 'pickup' or 'drop'
  final String tripTypeLabel; // 'LOGIN' or 'LOGOUT'
  final String? shift; // 'morning' or 'evening'
  final String? scheduledTime;
  final String? fromLocation; // Smart: Home for LOGIN, Office for LOGOUT
  final String? toLocation; // Smart: Office for LOGIN, Home for LOGOUT
  final Map<String, dynamic>? fromCoordinates;
  final Map<String, dynamic>? toCoordinates;
  final String status;
  final double distance;
  final int estimatedDuration;
  final String? tripId; // Add tripId property
  final int pickupSequence; // Add pickup sequence

  CustomerAssignment({
    required this.id,
    required this.customerId,
    required this.name,
    required this.phone,
    this.email,
    required this.tripType,
    required this.tripTypeLabel,
    this.shift,
    this.scheduledTime,
    this.fromLocation,
    this.toLocation,
    this.fromCoordinates,
    this.toCoordinates,
    required this.status,
    required this.distance,
    required this.estimatedDuration,
    this.tripId, // Add tripId parameter
    this.pickupSequence = 0, // Add pickup sequence parameter
  });

  bool get isLogin => tripType == 'pickup';
  bool get isLogout => tripType == 'drop';

  factory CustomerAssignment.fromJson(Map<String, dynamic> json) {
    print('🔍 [CustomerAssignment] Parsing: ${json['name']}');
    return CustomerAssignment(
      id: json['id']?.toString() ?? '',
      customerId: json['customerId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Unknown',
      phone: json['phone']?.toString() ?? 'N/A',
      email: json['email']?.toString(),
      tripType: json['tripType']?.toString() ?? 'pickup',
      tripTypeLabel: json['tripTypeLabel']?.toString() ?? 'LOGIN',
      shift: json['shift']?.toString(),
      scheduledTime: json['scheduledTime']?.toString(),
      fromLocation: json['fromLocation']?.toString(),
      toLocation: json['toLocation']?.toString(),
      fromCoordinates: json['fromCoordinates'] as Map<String, dynamic>?,
      toCoordinates: json['toCoordinates'] as Map<String, dynamic>?,
      status: json['status']?.toString() ?? 'pending',
      distance: (json['distance'] ?? 0).toDouble(),
      estimatedDuration: json['estimatedDuration'] ?? 0,
      tripId: json['tripId']?.toString(), // Add tripId parsing
      pickupSequence: json['pickupSequence'] ?? 0, // Add pickup sequence parsing
    );
  }
}

class RouteOptimization {
  final bool optimized;
  final DateTime? optimizedAt;
  final double? totalDistance;
  final int? totalDuration;

  RouteOptimization({
    required this.optimized,
    this.optimizedAt,
    this.totalDistance,
    this.totalDuration,
  });

  factory RouteOptimization.fromJson(Map<String, dynamic> json) {
    return RouteOptimization(
      optimized: json['optimized'] ?? false,
      optimizedAt: json['optimizedAt'] != null ? DateTime.parse(json['optimizedAt']) : null,
      totalDistance: json['totalDistance']?.toDouble(),
      totalDuration: json['totalDuration'],
    );
  }
}

class NavigationDetails {
  final CustomerInfo customer;
  final LocationInfo pickup;
  final LocationInfo drop;
  final String? scheduledTime;
  final double? distance;
  final int? estimatedDuration;

  NavigationDetails({
    required this.customer,
    required this.pickup,
    required this.drop,
    this.scheduledTime,
    this.distance,
    this.estimatedDuration,
  });

  factory NavigationDetails.fromJson(Map<String, dynamic> json) {
    return NavigationDetails(
      customer: CustomerInfo.fromJson(json['customer']),
      pickup: LocationInfo.fromJson(json['pickup']),
      drop: LocationInfo.fromJson(json['drop']),
      scheduledTime: json['scheduledTime'],
      distance: json['distance']?.toDouble(),
      estimatedDuration: json['estimatedDuration'],
    );
  }
}

class CustomerInfo {
  final String name;
  final String phone;

  CustomerInfo({required this.name, required this.phone});

  factory CustomerInfo.fromJson(Map<String, dynamic> json) {
    return CustomerInfo(
      name: json['name'],
      phone: json['phone'],
    );
  }
}

class LocationInfo {
  final String address;
  final Map<String, dynamic>? coordinates;

  LocationInfo({required this.address, this.coordinates});

  factory LocationInfo.fromJson(Map<String, dynamic> json) {
    return LocationInfo(
      address: json['address'],
      coordinates: json['coordinates'],
    );
  }
}
