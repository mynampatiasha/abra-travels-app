// File: lib/features/driver/domain/services/trip_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TripService {
  // Use your local IP from ipconfig (10.16.47.123)
  // Make sure your backend server is running on this IP
  // For local development: http://10.16.47.123:3001
  // For production: Use your actual API domain
  final String baseUrl;

  TripService({required this.baseUrl});

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

  // Get driver's active trip
  Future<TripResponse?> getActiveTrip() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/driver/trips/active'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          return TripResponse.fromJson(data['data']);
        }
        return null;
      } else {
        throw Exception('Failed to fetch active trip: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching active trip: $e');
      rethrow;
    }
  }

  // Update trip status
  Future<bool> updateTripStatus({
    required String tripId,
    required String status,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http.patch(
        Uri.parse('$baseUrl/api/driver/trips/update-status'),
        headers: headers,
        body: json.encode({
          'tripId': tripId,
          'status': status,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'success';
      }
      return false;
    } catch (e) {
      print('Error updating trip status: $e');
      return false;
    }
  }

  // Share location with customer
  Future<bool> shareLocation({
    required String tripId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/driver/trips/share-location'),
        headers: headers,
        body: json.encode({
          'tripId': tripId,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'success';
      }
      return false;
    } catch (e) {
      print('Error sharing location: $e');
      return false;
    }
  }

  // End trip
  Future<bool> endTrip({
    required String tripId,
    Map<String, double>? endLocation,
    double? finalOdometer,
  }) async {
    try {
      final headers = await _getHeaders();
      final body = {
        'tripId': tripId,
        if (endLocation != null) 'endLocation': endLocation,
        if (finalOdometer != null) 'finalOdometer': finalOdometer,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/driver/trips/end-trip'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'success';
      }
      return false;
    } catch (e) {
      print('Error ending trip: $e');
      return false;
    }
  }

  // Update location continuously (for real-time tracking)
  Future<bool> updateLocation({
    required String tripId,
    required double latitude,
    required double longitude,
    double? speed,
    double? heading,
  }) async {
    try {
      final headers = await _getHeaders();
      final body = {
        'tripId': tripId,
        'latitude': latitude,
        'longitude': longitude,
        if (speed != null) 'speed': speed,
        if (heading != null) 'heading': heading,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/driver/trips/update-location'),
        headers: headers,
        body: json.encode(body),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error updating location: $e');
      return false;
    }
  }

  // Get trip history
  Future<TripHistoryResponse?> getTripHistory({
    int page = 1,
    int limit = 20,
    String? status,
  }) async {
    try {
      final headers = await _getHeaders();
      final queryParams = {
        'page': page.toString(),
        'limit': limit.toString(),
        if (status != null) 'status': status,
      };

      final uri = Uri.parse('$baseUrl/api/driver/trips/history')
          .replace(queryParameters: queryParams);

      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          return TripHistoryResponse.fromJson(data['data']);
        }
      }
      return null;
    } catch (e) {
      print('Error fetching trip history: $e');
      rethrow;
    }
  }

  // Get driver's daily stats
  Future<DriverStats?> getDashboardStats() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/driver/dashboard/stats'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          return DriverStats.fromJson(data['data']);
        }
        return null;
      } else {
        throw Exception('Failed to fetch dashboard stats: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching dashboard stats: $e');
      rethrow;
    }
  }

  // Get vehicle check status
  Future<VehicleCheckResponse?> getVehicleCheck() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/driver/dashboard/vehicle-check'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && data['data'] != null) {
          return VehicleCheckResponse.fromJson(data['data']);
        }
        return null;
      } else {
        throw Exception('Failed to fetch vehicle check: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching vehicle check: $e');
      rethrow;
    }
  }

  // Submit vehicle check
  Future<VehicleCheckSubmitResponse?> submitVehicleCheck({
    required String vehicleId,
    required List<VehicleCheckItem> checks,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/api/driver/dashboard/vehicle-check'),
        headers: headers,
        body: json.encode({
          'vehicleId': vehicleId,
          'checks': checks.map((check) => check.toJson()).toList(),
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          return VehicleCheckSubmitResponse.fromJson(data);
        }
      }
      return null;
    } catch (e) {
      print('Error submitting vehicle check: $e');
      rethrow;
    }
  }
}

// Models
class TripResponse {
  final Trip trip;
  final Customer? customer;
  final Vehicle? vehicle;

  TripResponse({
    required this.trip,
    this.customer,
    this.vehicle,
  });

  factory TripResponse.fromJson(Map<String, dynamic> json) {
    return TripResponse(
      trip: Trip.fromJson(json['trip']),
      customer: json['customer'] != null ? Customer.fromJson(json['customer']) : null,
      vehicle: json['vehicle'] != null ? Vehicle.fromJson(json['vehicle']) : null,
    );
  }
}

class Trip {
  final String id;
  final String tripNumber;
  final String from;
  final String to;
  final double distance;
  final int customers;
  final String status;
  final DateTime? startTime;
  final DateTime? estimatedEndTime;
  final Map<String, dynamic>? currentLocation;

  Trip({
    required this.id,
    required this.tripNumber,
    required this.from,
    required this.to,
    required this.distance,
    required this.customers,
    required this.status,
    this.startTime,
    this.estimatedEndTime,
    this.currentLocation,
  });

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      id: json['id'].toString(),
      tripNumber: json['tripNumber'] ?? '',
      from: json['from'] ?? '',
      to: json['to'] ?? '',
      distance: (json['distance'] ?? 0).toDouble(),
      customers: json['customers'] ?? 1,
      status: json['status'] ?? '',
      startTime: json['startTime'] != null ? DateTime.parse(json['startTime']) : null,
      estimatedEndTime: json['estimatedEndTime'] != null ? DateTime.parse(json['estimatedEndTime']) : null,
      currentLocation: json['currentLocation'],
    );
  }
}

class Customer {
  final String name;
  final String phone;

  Customer({required this.name, required this.phone});

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
    );
  }
}

class Vehicle {
  final String registrationNumber;
  final String model;

  Vehicle({required this.registrationNumber, required this.model});

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      registrationNumber: json['registrationNumber'] ?? '',
      model: json['model'] ?? '',
    );
  }
}

class TripHistoryResponse {
  final List<Trip> trips;
  final Pagination pagination;

  TripHistoryResponse({required this.trips, required this.pagination});

  factory TripHistoryResponse.fromJson(Map<String, dynamic> json) {
    return TripHistoryResponse(
      trips: (json['trips'] as List).map((t) => Trip.fromJson(t)).toList(),
      pagination: Pagination.fromJson(json['pagination']),
    );
  }
}

class Pagination {
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  Pagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      page: json['page'],
      limit: json['limit'],
      total: json['total'],
      totalPages: json['totalPages'],
    );
  }
}

class DriverStats {
  final int totalTrips;
  final double totalDistance;
  final String averageRating;
  final String onTimePercentage;

  DriverStats({
    required this.totalTrips,
    required this.totalDistance,
    required this.averageRating,
    required this.onTimePercentage,
  });

  factory DriverStats.fromJson(Map<String, dynamic> json) {
    return DriverStats(
      totalTrips: json['totalTrips'] ?? 0,
      totalDistance: (json['totalDistance'] ?? 0).toDouble(),
      averageRating: json['averageRating']?.toString() ?? '5.0',
      onTimePercentage: json['onTimePercentage']?.toString() ?? '100%',
    );
  }
}

class VehicleCheckResponse {
  final bool vehicleAssigned;
  final String? vehicleId;
  final String? vehicleNumber;
  final String? vehicleModel;
  final List<VehicleCheckItem> checks;
  final DateTime? lastCheckDate;

  VehicleCheckResponse({
    required this.vehicleAssigned,
    this.vehicleId,
    this.vehicleNumber,
    this.vehicleModel,
    required this.checks,
    this.lastCheckDate,
  });

  factory VehicleCheckResponse.fromJson(Map<String, dynamic> json) {
    return VehicleCheckResponse(
      vehicleAssigned: json['vehicleAssigned'] ?? false,
      vehicleId: json['vehicleId'],
      vehicleNumber: json['vehicleNumber'],
      vehicleModel: json['vehicleModel'],
      checks: json['checks'] != null
          ? (json['checks'] as List)
              .map((check) => VehicleCheckItem.fromJson(check))
              .toList()
          : [],
      lastCheckDate: json['lastCheckDate'] != null
          ? DateTime.parse(json['lastCheckDate'])
          : null,
    );
  }
}

class VehicleCheckItem {
  final String label;
  final String status;
  final bool isOk;
  final DateTime? lastChecked;

  VehicleCheckItem({
    required this.label,
    required this.status,
    required this.isOk,
    this.lastChecked,
  });

  factory VehicleCheckItem.fromJson(Map<String, dynamic> json) {
    return VehicleCheckItem(
      label: json['label'] ?? '',
      status: json['status'] ?? '',
      isOk: json['isOk'] ?? true,
      lastChecked: json['lastChecked'] != null
          ? DateTime.parse(json['lastChecked'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'status': status,
      'isOk': isOk,
      if (lastChecked != null) 'lastChecked': lastChecked!.toIso8601String(),
    };
  }
}

class VehicleCheckSubmitResponse {
  final String status;
  final String message;
  final VehicleCheckSubmitData? data;

  VehicleCheckSubmitResponse({
    required this.status,
    required this.message,
    this.data,
  });

  factory VehicleCheckSubmitResponse.fromJson(Map<String, dynamic> json) {
    return VehicleCheckSubmitResponse(
      status: json['status'] ?? '',
      message: json['message'] ?? '',
      data: json['data'] != null
          ? VehicleCheckSubmitData.fromJson(json['data'])
          : null,
    );
  }
}

class VehicleCheckSubmitData {
  final String checkId;
  final int issuesFound;

  VehicleCheckSubmitData({
    required this.checkId,
    required this.issuesFound,
  });

  factory VehicleCheckSubmitData.fromJson(Map<String, dynamic> json) {
    return VehicleCheckSubmitData(
      checkId: json['checkId']?.toString() ?? '',
      issuesFound: json['issuesFound'] ?? 0,
    );
  }
}