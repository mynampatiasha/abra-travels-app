// lib/core/services/vehicle_service.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class VehicleService {
  // Vehicle API endpoint
  static String get _vehiclesEndpoint => '${ApiConfig.baseUrl}/api/admin/vehicles';

  Future<String?> _getAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      print('Error getting auth token: $e');
      return null;
    }
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getAuthToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> getVehicles({
    int page = 1,
    int limit = 100,
    String? search,
    String? status,
    String? vehicleType,
    String? engineType,
  }) async {
    try {
      final headers = await _getHeaders();
      
      final queryParams = {
        'page': page.toString(),
        'limit': limit.toString(),
        if (search != null && search.isNotEmpty) 'search': search,
        if (status != null && status.isNotEmpty) 'status': status,
        if (vehicleType != null && vehicleType.isNotEmpty) 'vehicleType': vehicleType,
        if (engineType != null && engineType.isNotEmpty) 'engineType': engineType,
      };

      final uri = Uri.parse(_vehiclesEndpoint).replace(queryParameters: queryParams);
      print('Fetching vehicles from: $uri');

      final response = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      print('Get vehicles response status: ${response.statusCode}');
      print('Get vehicles response: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'data': responseData['data'] ?? [],
          'pagination': responseData['pagination'] ?? {},
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to fetch vehicles',
        };
      }
    } catch (e) {
      print('Error fetching vehicles: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> getVehicleById(String id) async {
    try {
      final headers = await _getHeaders();
      
      final response = await http.get(
        Uri.parse('$_vehiclesEndpoint/$id'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Vehicle not found',
        };
      }
    } catch (e) {
      print('Error fetching vehicle: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // ============================================
  // 🆕 CHECK AVAILABLE SEATS FOR A VEHICLE
  // ============================================
  
  /// Check available seats for a vehicle
  /// 
  /// [vehicleId] - The vehicle ID or MongoDB _id
  /// [requestedSeats] - Number of seats you want to check (default: 1)
  /// 
  /// Returns:
  /// {
  ///   'success': true/false,
  ///   'message': 'Seats available' or error message,
  ///   'data': {
  ///     'totalCapacity': 10,
  ///     'assignedSeats': 6,
  ///     'availableSeats': 4,
  ///     'requestedSeats': 5
  ///   }
  /// }
  Future<Map<String, dynamic>> checkAvailableSeats({
    required String vehicleId,
    int requestedSeats = 1,
  }) async {
    try {
      final headers = await _getHeaders();
      
      final queryParams = {
        'requestedSeats': requestedSeats.toString(),
      };

      final uri = Uri.parse('$_vehiclesEndpoint/$vehicleId/available-seats')
          .replace(queryParameters: queryParams);
      
      print('=== CHECK AVAILABLE SEATS ===');
      print('URL: $uri');
      print('Vehicle ID: $vehicleId');
      print('Requested Seats: $requestedSeats');
      print('============================');

      final response = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      print('=== SEAT CHECK RESPONSE ===');
      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');
      print('===========================');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': responseData['success'] ?? false,
          'message': responseData['message'] ?? 'Seat check completed',
          'data': responseData['data'] ?? {},
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to check seat availability',
          'data': responseData['data'],
        };
      }
    } catch (e) {
      print('Error checking available seats: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'data': null,
      };
    }
  }

  // ============================================
  // 🆕 VALIDATE SEATS BEFORE BOOKING
  // ============================================
  
  /// Validate if enough seats are available before creating a booking
  /// Returns true if seats are available, false otherwise
  /// Shows detailed error message if seats are not available
  Future<Map<String, dynamic>> validateSeatsForBooking({
    required String vehicleId,
    required int numberOfPassengers,
  }) async {
    try {
      final seatCheck = await checkAvailableSeats(
        vehicleId: vehicleId,
        requestedSeats: numberOfPassengers,
      );

      if (seatCheck['success'] == true) {
        final data = seatCheck['data'];
        return {
          'isValid': true,
          'message': 'Seats available for booking',
          'seatInfo': data,
        };
      } else {
        return {
          'isValid': false,
          'message': seatCheck['message'] ?? 'Insufficient seats available',
          'seatInfo': seatCheck['data'],
        };
      }
    } catch (e) {
      print('Error validating seats: $e');
      return {
        'isValid': false,
        'message': 'Error validating seat availability',
        'seatInfo': null,
      };
    }
  }

  // Get vehicle route history
  Future<Map<String, dynamic>> getVehicleRouteHistory({
    required String vehicleId,
    int? days = 1,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final headers = await _getHeaders();
      
      final queryParams = {
        if (days != null) 'days': days.toString(),
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
      };

      final uri = Uri.parse('$_vehiclesEndpoint/$vehicleId/route-history')
          .replace(queryParameters: queryParams);
      
      print('Fetching route history from: $uri');

      final response = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      print('Route history response status: ${response.statusCode}');
      print('Route history response: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'data': responseData['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to fetch route history',
        };
      }
    } catch (e) {
      print('Error fetching route history: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Get vehicle trip route
  Future<Map<String, dynamic>> getVehicleTripRoute({
    required String vehicleId,
    required String tripId,
  }) async {
    try {
      final headers = await _getHeaders();
      
      final response = await http.get(
        Uri.parse('$_vehiclesEndpoint/$vehicleId/trips/$tripId/route'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      print('Trip route response status: ${response.statusCode}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'data': responseData['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to fetch trip route',
        };
      }
    } catch (e) {
      print('Error fetching trip route: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Create a new vehicle
  Future<Map<String, dynamic>> createVehicle({
    required String registrationNumber,
    required String vehicleType,
    required String make,
    required String model,
    required int yearOfManufacture,
    required String engineType,
    required double engineCapacity,
    required int seatingCapacity,
    required double mileage,
    String? status,
    String? vendor,
    String? country,
    String? state,
    String? city,
  }) async {
    try {
      final headers = await _getHeaders();
      
      // Combine make and model properly
      final makeModel = '$make $model'.trim();
      
      final body = {
        'registrationNumber': registrationNumber.toUpperCase(),
        'vehicleType': vehicleType, // Keep exact case from CSV
        'makeModel': makeModel, // Combined make and model
        'yearOfManufacture': yearOfManufacture,
        'engineType': engineType,
        'engineCapacity': engineCapacity,
        'seatingCapacity': seatingCapacity,
        'mileage': mileage,
        'status': (status ?? 'active').toLowerCase(),
        if (vendor != null && vendor.isNotEmpty) 'vendor': vendor,
        if (country != null && country.isNotEmpty) 'country': country,
        if (state != null && state.isNotEmpty) 'state': state,
        if (city != null && city.isNotEmpty) 'city': city,
      };

      print('=== CREATE VEHICLE REQUEST ===');
      print('URL: $_vehiclesEndpoint');
      print('Headers: $headers');
      print('Body: ${jsonEncode(body)}');
      print('============================');

      final response = await http.post(
        Uri.parse(_vehiclesEndpoint),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      print('=== CREATE VEHICLE RESPONSE ===');
      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');
      print('==============================');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Vehicle created successfully',
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to create vehicle',
          'errors': responseData['errors'],
        };
      }
    } catch (e) {
      print('Error creating vehicle: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Update vehicle
  Future<Map<String, dynamic>> updateVehicle(
    String mongoId,
    Map<String, dynamic> updateData,
  ) async {
    try {
      final headers = await _getHeaders();

      // Combine make and model into makeModel as backend expects
      final make = updateData['make'] ?? '';
      final model = updateData['model'] ?? '';
      final makeModel = '$make $model'.trim();

      // Parse numeric values properly
      final yearOfManufacture = updateData['year'] != null 
          ? int.tryParse(updateData['year'].toString()) ?? updateData['yearOfManufacture'] ?? 0
          : updateData['yearOfManufacture'] ?? 0;
      
      final engineCapacity = updateData['engineCapacity'] != null
          ? double.tryParse(updateData['engineCapacity'].toString()) ?? 0.0
          : 0.0;
      
      final seatingCapacity = updateData['seatingCapacity'] != null
          ? int.tryParse(updateData['seatingCapacity'].toString()) ?? 0
          : 0;
      
      final mileage = updateData['mileage'] != null
          ? double.tryParse(updateData['mileage'].toString()) ?? 0.0
          : 0.0;

      final body = {
        'registrationNumber': (updateData['registrationNumber'] ?? '').toString().toUpperCase(),
        'vehicleType': updateData['type'] ?? updateData['vehicleType'] ?? 'Car',
        'makeModel': makeModel,
        'yearOfManufacture': yearOfManufacture,
        'engineType': updateData['engineType'] ?? 'Diesel',
        'engineCapacity': engineCapacity,
        'seatingCapacity': seatingCapacity,
        'mileage': mileage,
        'status': (updateData['status'] ?? 'active').toString().toLowerCase(),
      };

      print('=== UPDATE VEHICLE REQUEST ===');
      print('MongoDB ID: $mongoId');
      print('URL: $_vehiclesEndpoint/$mongoId');
      print('Body: ${jsonEncode(body)}');
      print('============================');

      final response = await http.put(
        Uri.parse('$_vehiclesEndpoint/$mongoId'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      print('=== UPDATE VEHICLE RESPONSE ===');
      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');
      print('==============================');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Vehicle updated successfully',
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to update vehicle',
          'errors': responseData['errors'],
        };
      }
    } catch (e) {
      print('Error updating vehicle: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Delete vehicle
  Future<Map<String, dynamic>> deleteVehicle(String vehicleId) async {
    try {
      final headers = await _getHeaders();

      print('=== DELETE VEHICLE REQUEST ===');
      print('Vehicle ID: $vehicleId');
      print('URL: $_vehiclesEndpoint/$vehicleId');
      print('============================');

      final response = await http.delete(
        Uri.parse('$_vehiclesEndpoint/$vehicleId'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      print('=== DELETE VEHICLE RESPONSE ===');
      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');
      print('==============================');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 204) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Vehicle deleted successfully',
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to delete vehicle',
        };
      }
    } catch (e) {
      print('Error deleting vehicle: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Get vehicle statistics
  Future<Map<String, dynamic>> getVehicleStats() async {
    try {
      final headers = await _getHeaders();

      final response = await http.get(
        Uri.parse('$_vehiclesEndpoint/stats/overview'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success']) {
        return {
          'success': true,
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to fetch statistics',
        };
      }
    } catch (e) {
      print('Error fetching stats: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Add vehicle document
  Future<Map<String, dynamic>> addVehicleDocument(
    String vehicleId,
    String documentType,
    String documentName,
    String documentUrl,
    DateTime? expiryDate,
    bool isDriverDoc,
  ) async {
    try {
      final headers = await _getHeaders();

      final body = {
        'documentType': documentType,
        'documentName': documentName,
        'documentUrl': documentUrl,
        if (expiryDate != null) 'expiryDate': expiryDate.toIso8601String(),
        'isDriverDoc': isDriverDoc,
      };

      print('=== ADD DOCUMENT REQUEST ===');
      print('Vehicle ID: $vehicleId');
      print('URL: $_vehiclesEndpoint/$vehicleId/documents');
      print('Body: ${jsonEncode(body)}');
      print('============================');

      final response = await http.post(
        Uri.parse('$_vehiclesEndpoint/$vehicleId/documents'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      print('=== ADD DOCUMENT RESPONSE ===');
      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');
      print('==============================');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Document added successfully',
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to add document',
        };
      }
    } catch (e) {
      print('Error adding document: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Delete vehicle document (MongoDB API)
  Future<Map<String, dynamic>> deleteVehicleDocument(
    String vehicleId,
    String documentId,
    bool isDriverDoc,
  ) async {
    try {
      final headers = await _getHeaders();

      final queryParams = {
        'isDriverDoc': isDriverDoc.toString(),
      };

      // Use MongoDB document API endpoint
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/documents/vehicles/$vehicleId/documents/$documentId')
          .replace(queryParameters: queryParams);

      print('=== DELETE DOCUMENT REQUEST (MongoDB) ===');
      print('Vehicle ID: $vehicleId');
      print('Document ID: $documentId');
      print('URL: $uri');
      print('============================');

      final response = await http.delete(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      print('=== DELETE DOCUMENT RESPONSE ===');
      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');
      print('==============================');

      if (response.statusCode == 200 || response.statusCode == 204) {
        final responseData = response.body.isNotEmpty 
            ? jsonDecode(response.body) 
            : {'success': true};
        return {
          'success': true,
          'message': responseData['message'] ?? 'Document deleted successfully',
        };
      } else {
        final responseData = jsonDecode(response.body);
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to delete document',
        };
      }
    } catch (e) {
      print('Error deleting document: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Upload document to MongoDB (no CORS issues!)
  Future<Map<String, dynamic>> uploadVehicleDocumentToMongoDB({
    required String vehicleId,
    required File? file,
    required Uint8List? bytes,
    required String fileName,
    required String documentType,
    required String documentName,
    DateTime? expiryDate,
    required bool isDriverDoc,
  }) async {
    try {
      final token = await _getAuthToken();
      
      // Create multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/documents/vehicles/$vehicleId/documents'),
      );
      
      // Add headers
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }
      
      // Add file
      if (kIsWeb && bytes != null) {
        // Web - use bytes
        request.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ));
      } else if (file != null) {
        // Mobile/Desktop - use file
        request.files.add(await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: fileName,
        ));
      } else {
        return {
          'success': false,
          'message': 'No file provided',
        };
      }
      
      // Add form fields
      request.fields['documentType'] = documentType;
      request.fields['documentName'] = documentName;
      request.fields['isDriverDoc'] = isDriverDoc.toString();
      if (expiryDate != null) {
        request.fields['expiryDate'] = expiryDate.toIso8601String();
      }
      
      print('=== UPLOAD TO MONGODB ===');
      print('URL: ${request.url}');
      print('Fields: ${request.fields}');
      print('========================');
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      print('=== MONGODB UPLOAD RESPONSE ===');
      print('Status: ${response.statusCode}');
      print('Body: ${response.body}');
      print('==============================');
      
      final responseData = jsonDecode(response.body);
      
      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': responseData['message'] ?? 'Document uploaded successfully',
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['message'] ?? 'Upload failed',
        };
      }
    } catch (e) {
      print('Error uploading to MongoDB: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Get assigned customers for a vehicle
  Future<Map<String, dynamic>> getAssignedCustomers(String vehicleId) async {
    try {
      final headers = await _getHeaders();
      final uri = Uri.parse('$_vehiclesEndpoint/$vehicleId/assigned-customers');

      print('=== GET ASSIGNED CUSTOMERS REQUEST ===');
      print('Vehicle ID: $vehicleId');
      print('URL: $uri');
      print('====================================');

      final response = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      print('=== GET ASSIGNED CUSTOMERS RESPONSE ===');
      print('Status: ${response.statusCode}');
      print('Body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}...');
      print('=====================================');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return responseData;
      } else {
        final responseData = jsonDecode(response.body);
        return {
          'success': false,
          'message': responseData['message'] ?? 'Failed to fetch assigned customers',
        };
      }
    } catch (e) {
      print('Error fetching assigned customers: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

/// Check if vehicle can take consecutive trips (time-based validation)
/// 
/// [vehicleId] - Vehicle MongoDB ObjectId
/// [scheduledDate] - Date in YYYY-MM-DD format
/// [startTime] - Trip start time in HH:mm format (24-hour)
/// [endTime] - Trip end time in HH:mm format (24-hour)
/// 
/// Returns whether vehicle is available for this time slot
Future<Map<String, dynamic>> checkConsecutiveTripAvailability({
  required String vehicleId,
  required String scheduledDate,
  required String startTime,
  required String endTime,
}) async {
  try {
    final headers = await _getHeaders();
    
    final queryParams = {
      'scheduledDate': scheduledDate,
      'startTime': startTime,
      'endTime': endTime,
    };

    final uri = Uri.parse('$_vehiclesEndpoint/$vehicleId/check-availability')
        .replace(queryParameters: queryParams);
    
    print('=== CHECK CONSECUTIVE TRIP AVAILABILITY ===');
    print('URL: $uri');
    print('Vehicle ID: $vehicleId');
    print('Date: $scheduledDate');
    print('Time Slot: $startTime - $endTime');
    print('==========================================');

    final response = await http.get(uri, headers: headers)
        .timeout(const Duration(seconds: 30));

    print('=== AVAILABILITY CHECK RESPONSE ===');
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
    print('===================================');

    final responseData = jsonDecode(response.body);

    if (response.statusCode == 200) {
      return {
        'success': responseData['success'] ?? false,
        'available': responseData['available'] ?? false,
        'message': responseData['message'] ?? 'Availability check completed',
        'conflictingTrips': responseData['conflictingTrips'] ?? [],
      };
    } else {
      return {
        'success': false,
        'available': false,
        'message': responseData['message'] ?? 'Failed to check availability',
        'conflictingTrips': [],
      };
    }
  } catch (e) {
    print('Error checking consecutive trip availability: $e');
    return {
      'success': false,
      'available': false,
      'message': 'Network error: ${e.toString()}',
      'conflictingTrips': [],
    };
  }
}

  // Get detailed vehicle information with driver and customer details
  Future<Map<String, dynamic>> getVehicleDetailsForMap(String vehicleId) async {
    try {
      final headers = await _getHeaders();
      
      // Get basic vehicle details
      final vehicleResponse = await getVehicleById(vehicleId);
      if (!vehicleResponse['success']) {
        return vehicleResponse;
      }

      // Get assigned customers
      final customersResponse = await getAssignedCustomers(vehicleId);
      
      return {
        'success': true,
        'data': {
          'vehicle': vehicleResponse['data'],
          'assignedCustomers': customersResponse['success'] ? customersResponse['data'] : null,
        },
      };
    } catch (e) {
      print('Error fetching vehicle details for map: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }
}