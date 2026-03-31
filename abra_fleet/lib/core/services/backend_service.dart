// File: lib/core/services/backend_service.dart
// Complete backend service that replaces direct MongoDB connection

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Models
class Driver {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String licenseNumber;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Driver({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.licenseNumber,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      id: json['_id'] ?? json['id'],
      name: json['name'],
      email: json['email'],
      phone: json['phone'],
      licenseNumber: json['licenseNumber'],
      status: json['status'] ?? 'active',
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'licenseNumber': licenseNumber,
      'status': status,
    };
  }
}

class Vehicle {
  final String id;
  final String plateNumber;
  final String make;
  final String model;
  final int year;
  final String type;
  final String status;
  final String? assignedDriverId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Vehicle({
    required this.id,
    required this.plateNumber,
    required this.make,
    required this.model,
    required this.year,
    required this.type,
    required this.status,
    this.assignedDriverId,
    required this.createdAt,
    this.updatedAt,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['_id'] ?? json['id'],
      plateNumber: json['plateNumber'],
      make: json['make'],
      model: json['model'],
      year: json['year'],
      type: json['type'],
      status: json['status'] ?? 'active',
      assignedDriverId: json['assignedDriverId'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'plateNumber': plateNumber,
      'make': make,
      'model': model,
      'year': year,
      'type': type,
      'status': status,
      'assignedDriverId': assignedDriverId,
    };
  }
}

class Trip {
  final String id;
  final String driverId;
  final String vehicleId;
  final String startLocation;
  final String? endLocation;
  final String status;
  final DateTime startTime;
  final DateTime? endTime;
  final double? distance;
  final List<Map<String, dynamic>>? waypoints;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Trip({
    required this.id,
    required this.driverId,
    required this.vehicleId,
    required this.startLocation,
    this.endLocation,
    required this.status,
    required this.startTime,
    this.endTime,
    this.distance,
    this.waypoints,
    required this.createdAt,
    this.updatedAt,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['_id'] ?? json['id'],
      driverId: json['driverId'],
      vehicleId: json['vehicleId'],
      startLocation: json['startLocation'],
      endLocation: json['endLocation'],
      status: json['status'] ?? 'pending',
      startTime: DateTime.parse(json['startTime']),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      distance: json['distance']?.toDouble(),
      waypoints: json['waypoints'] != null 
          ? List<Map<String, dynamic>>.from(json['waypoints']) 
          : null,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'driverId': driverId,
      'vehicleId': vehicleId,
      'startLocation': startLocation,
      'endLocation': endLocation,
      'status': status,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime?.toIso8601String(),
      'distance': distance,
      'waypoints': waypoints,
    };
  }
}

// Exceptions
class BackendException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic error;

  BackendException(this.message, [this.statusCode, this.error]);

  @override
  String toString() => 'BackendException: $message${statusCode != null ? ' (Status: $statusCode)' : ''}';
}

// Main Backend Service
class BackendService {
  static final BackendService _instance = BackendService._internal();
  late final String _baseUrl;
  String? _authToken;
  
  factory BackendService() => _instance;
  
  BackendService._internal() {
    _baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:3001';
  }

  // Initialize service
  Future<void> initialize() async {
    try {
      if (kIsWeb) {
        debugPrint('Web environment detected, using existing configuration');
      } else {
        await dotenv.load(fileName: ".env");
        debugPrint('Environment variables loaded');
      }
    } catch (e) {
      debugPrint('Warning: Could not load .env file: $e');
    }
  }

  // Set authentication token
  void setAuthToken(String token) {
    _authToken = token;
  }

  // Clear authentication token
  void clearAuthToken() {
    _authToken = null;
  }

  // Get default headers
  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    
    return headers;
  }

  // Generic HTTP methods
  Future<Map<String, dynamic>> _get(String endpoint, {Map<String, String>? queryParams}) async {
    try {
      var uri = Uri.parse('$_baseUrl$endpoint');
      if (queryParams != null) {
        uri = uri.replace(queryParameters: queryParams);
      }
      
      debugPrint('GET: $uri');
      
      final response = await http.get(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('GET Error: $e');
      throw BackendException('Network error during GET request', null, e);
    }
  }

  Future<Map<String, dynamic>> _post(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      debugPrint('POST: $uri');
      
      final response = await http.post(
        uri,
        headers: _headers,
        body: body != null ? jsonEncode(body) : null,
      );
      
      return _handleResponse(response);
    } catch (e) {
      debugPrint('POST Error: $e');
      throw BackendException('Network error during POST request', null, e);
    }
  }

  Future<Map<String, dynamic>> _put(String endpoint, {Map<String, dynamic>? body}) async {
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      debugPrint('PUT: $uri');
      
      final response = await http.put(
        uri,
        headers: _headers,
        body: body != null ? jsonEncode(body) : null,
      );
      
      return _handleResponse(response);
    } catch (e) {
      debugPrint('PUT Error: $e');
      throw BackendException('Network error during PUT request', null, e);
    }
  }

  Future<Map<String, dynamic>> _delete(String endpoint) async {
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      debugPrint('DELETE: $uri');
      
      final response = await http.delete(uri, headers: _headers);
      return _handleResponse(response);
    } catch (e) {
      debugPrint('DELETE Error: $e');
      throw BackendException('Network error during DELETE request', null, e);
    }
  }

  // Handle HTTP response
  Map<String, dynamic> _handleResponse(http.Response response) {
    debugPrint('Response Status: ${response.statusCode}');
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        if (response.body.isEmpty) {
          return {'success': true};
        }
        return jsonDecode(response.body) as Map<String, dynamic>;
      } catch (e) {
        throw BackendException('Invalid JSON response', response.statusCode, e);
      }
    } else {
      String errorMessage = 'Request failed';
      try {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>;
        errorMessage = errorBody['message'] ?? errorBody['error'] ?? errorMessage;
      } catch (e) {
        errorMessage = response.body.isNotEmpty ? response.body : errorMessage;
      }
      
      throw BackendException(errorMessage, response.statusCode);
    }
  }

  // Authentication methods
  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _post('/auth/login', body: {
      'email': email,
      'password': password,
    });
    
    if (response['token'] != null) {
      setAuthToken(response['token']);
    }
    
    return response;
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> userData) async {
    return await _post('/auth/register', body: userData);
  }

  Future<void> logout() async {
    try {
      await _post('/auth/logout');
    } finally {
      clearAuthToken();
    }
  }

  // Driver methods
  Future<List<Driver>> getDrivers() async {
    final response = await _get('/api/drivers');
    final List<dynamic> driversJson = response['drivers'] ?? response['data'] ?? [];
    return driversJson.map((json) => Driver.fromJson(json)).toList();
  }

  Future<Driver> getDriver(String driverId) async {
    final response = await _get('/api/drivers/$driverId');
    return Driver.fromJson(response['driver'] ?? response);
  }

  Future<Driver> createDriver(Driver driver) async {
    final response = await _post('/api/drivers', body: driver.toJson());
    return Driver.fromJson(response['driver'] ?? response);
  }

  Future<Driver> updateDriver(String driverId, Driver driver) async {
    final response = await _put('/api/drivers/$driverId', body: driver.toJson());
    return Driver.fromJson(response['driver'] ?? response);
  }

  Future<void> deleteDriver(String driverId) async {
    await _delete('/api/drivers/$driverId');
  }

  // Vehicle methods
  Future<List<Vehicle>> getVehicles() async {
    final response = await _get('/api/vehicles');
    final List<dynamic> vehiclesJson = response['vehicles'] ?? response['data'] ?? [];
    return vehiclesJson.map((json) => Vehicle.fromJson(json)).toList();
  }

  Future<Vehicle> getVehicle(String vehicleId) async {
    final response = await _get('/api/vehicles/$vehicleId');
    return Vehicle.fromJson(response['vehicle'] ?? response);
  }

  Future<Vehicle> createVehicle(Vehicle vehicle) async {
    final response = await _post('/api/vehicles', body: vehicle.toJson());
    return Vehicle.fromJson(response['vehicle'] ?? response);
  }

  Future<Vehicle> updateVehicle(String vehicleId, Vehicle vehicle) async {
    final response = await _put('/api/vehicles/$vehicleId', body: vehicle.toJson());
    return Vehicle.fromJson(response['vehicle'] ?? response);
  }

  Future<void> deleteVehicle(String vehicleId) async {
    await _delete('/api/vehicles/$vehicleId');
  }

  // Trip methods
  Future<List<Trip>> getTrips() async {
    final response = await _get('/api/trips');
    final List<dynamic> tripsJson = response['trips'] ?? response['data'] ?? [];
    return tripsJson.map((json) => Trip.fromJson(json)).toList();
  }

  Future<Trip> getTrip(String tripId) async {
    final response = await _get('/api/trips/$tripId');
    return Trip.fromJson(response['trip'] ?? response);
  }

  Future<Trip> createTrip(Trip trip) async {
    final response = await _post('/api/trips', body: trip.toJson());
    return Trip.fromJson(response['trip'] ?? response);
  }

  Future<Trip> updateTrip(String tripId, Trip trip) async {
    final response = await _put('/api/trips/$tripId', body: trip.toJson());
    return Trip.fromJson(response['trip'] ?? response);
  }

  Future<void> deleteTrip(String tripId) async {
    await _delete('/api/trips/$tripId');
  }

  // Location tracking
  Future<void> updateLocation(String tripId, double latitude, double longitude) async {
    await _post('/api/trips/$tripId/location', body: {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getLocationHistory(String tripId) async {
    final response = await _get('/api/trips/$tripId/locations');
    return List<Map<String, dynamic>>.from(response['locations'] ?? response['data'] ?? []);
  }

  // Health check
  Future<bool> checkHealth() async {
    try {
      await _get('/health');
      return true;
    } catch (e) {
      debugPrint('Health check failed: $e');
      return false;
    }
  }

  // Statistics and analytics
  Future<Map<String, dynamic>> getDashboardStats() async {
    return await _get('/api/dashboard/stats');
  }

  Future<Map<String, dynamic>> getDriverStats(String driverId) async {
    return await _get('/api/drivers/$driverId/stats');
  }

  Future<Map<String, dynamic>> getVehicleStats(String vehicleId) async {
    return await _get('/api/vehicles/$vehicleId/stats');
  }
}