// lib/core/services/individual_trip_service.dart
// ============================================================================
// INDIVIDUAL TRIP SERVICE - API Integration for Admin-Created Trips
// ============================================================================
// Handles all API calls for individual trips (accept/decline flow)
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import '../../app/config/api_config.dart';

class IndividualTripService {
  static final IndividualTripService _instance = IndividualTripService._internal();
  factory IndividualTripService() => _instance;
  IndividualTripService._internal();

  final ApiService _apiService = ApiService();

  // ========================================================================
  // GET PENDING TRIPS (Status: assigned)
  // ========================================================================
  Future<List<Map<String, dynamic>>> getPendingTrips() async {
    try {
      print('📋 Fetching pending trips...');
      
      final response = await _apiService.get('/api/trips/pending');
      
      if (response['success'] == true) {
        final trips = List<Map<String, dynamic>>.from(response['data'] ?? []);
        print('✅ Fetched ${trips.length} pending trip(s)');
        return trips;
      }
      
      throw Exception(response['message'] ?? 'Failed to fetch pending trips');
    } catch (e) {
      print('❌ Error fetching pending trips: $e');
      rethrow;
    }
  }

  // ========================================================================
  // GET ACCEPTED TRIPS (Status: accepted, started, in_progress)
  // ========================================================================
  Future<List<Map<String, dynamic>>> getAcceptedTrips() async {
    try {
      print('📋 Fetching accepted trips...');
      
      final response = await _apiService.get('/api/trips/accepted');
      
      if (response['success'] == true) {
        final trips = List<Map<String, dynamic>>.from(response['data'] ?? []);
        print('✅ Fetched ${trips.length} accepted trip(s)');
        return trips;
      }
      
      throw Exception(response['message'] ?? 'Failed to fetch accepted trips');
    } catch (e) {
      print('❌ Error fetching accepted trips: $e');
      rethrow;
    }
  }

  // ========================================================================
  // GET COMPLETED TRIPS (Status: completed)
  // ========================================================================
  Future<List<Map<String, dynamic>>> getCompletedTrips() async {
    try {
      print('📋 Fetching completed trips...');
      
      final response = await _apiService.get('/api/trips/completed');
      
      if (response['success'] == true) {
        final trips = List<Map<String, dynamic>>.from(response['data'] ?? []);
        print('✅ Fetched ${trips.length} completed trip(s)');
        return trips;
      }
      
      throw Exception(response['message'] ?? 'Failed to fetch completed trips');
    } catch (e) {
      print('❌ Error fetching completed trips: $e');
      rethrow;
    }
  }

  // ========================================================================
  // ACCEPT OR DECLINE TRIP
  // ========================================================================
  Future<Map<String, dynamic>> respondToTrip({
    required String tripId,
    required String response, // 'accept' or 'decline'
    required String notes,
  }) async {
    try {
      print('📱 Responding to trip: $tripId');
      print('   Response: $response');
      print('   Notes: ${notes.isEmpty ? "None" : notes}');
      
      final result = await _apiService.post(
        '/api/trips/$tripId/driver-response',
        body: {
          'response': response,
          'notes': notes,
        },
      );
      
      if (result['success'] == true) {
        print('✅ Trip response sent successfully');
        return result['data'];
      }
      
      throw Exception(result['message'] ?? 'Failed to respond to trip');
    } catch (e) {
      print('❌ Error responding to trip: $e');
      rethrow;
    }
  }

  // ========================================================================
  // START TRIP (with odometer photo)
  // ========================================================================
  Future<Map<String, dynamic>> startTrip({
    required String tripId,
    required File photo,
    required int odometerReading,
  }) async {
    try {
      print('🚀 Starting trip: $tripId');
      print('📏 Odometer reading: $odometerReading km');
      
      // Read photo bytes
      final photoBytes = await photo.readAsBytes();
      
      // Create multipart request
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/trips/$tripId/start');
      final request = http.MultipartRequest('POST', uri);
      
      // Add headers (with authentication token)
      final headers = await _apiService.getHeaders();
      request.headers.addAll(headers);
      
      // Add fields
      request.fields['reading'] = odometerReading.toString();
      
      // Add photo file
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photoBytes,
          filename: 'odometer_start_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );
      
      print('📤 Uploading odometer photo...');
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      print('📥 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        
        if (responseData['success'] == true) {
          print('✅ Trip started successfully');
          return responseData['data'];
        } else {
          throw Exception(responseData['message'] ?? 'Failed to start trip');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to start trip: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error starting trip: $e');
      rethrow;
    }
  }

  // ========================================================================
  // UPDATE LOCATION (GPS tracking)
  // ========================================================================
  Future<void> updateLocation({
    required String tripId,
    required double latitude,
    required double longitude,
    double? speed,
    double? heading,
  }) async {
    try {
      await _apiService.post(
        '/api/trips/$tripId/location',
        body: {
          'latitude': latitude,
          'longitude': longitude,
          'speed': speed,
          'heading': heading,
        },
      );
      
      print('📍 Location updated: $latitude, $longitude');
    } catch (e) {
      print('⚠️  Error updating location: $e');
      // Don't throw - location updates should fail silently
    }
  }

  // ========================================================================
  // MARK ARRIVED AT PICKUP
  // ========================================================================
  Future<Map<String, dynamic>> markArrived({
    required String tripId,
    double? latitude,
    double? longitude,
  }) async {
    try {
      print('📍 Marking arrival at pickup: $tripId');
      
      final result = await _apiService.post(
        '/api/trips/$tripId/arrive',
        body: {
          'latitude': latitude,
          'longitude': longitude,
        },
      );
      
      if (result['success'] == true) {
        print('✅ Marked as arrived');
        return result['data'];
      }
      
      throw Exception(result['message'] ?? 'Failed to mark arrival');
    } catch (e) {
      print('❌ Error marking arrival: $e');
      rethrow;
    }
  }

  // ========================================================================
  // MARK DEPARTED FROM PICKUP
  // ========================================================================
  Future<Map<String, dynamic>> markDeparted({
    required String tripId,
    double? latitude,
    double? longitude,
  }) async {
    try {
      print('🚗 Marking departure from pickup: $tripId');
      
      final result = await _apiService.post(
        '/api/trips/$tripId/depart',
        body: {
          'latitude': latitude,
          'longitude': longitude,
        },
      );
      
      if (result['success'] == true) {
        print('✅ Marked as departed');
        return result['data'];
      }
      
      throw Exception(result['message'] ?? 'Failed to mark departure');
    } catch (e) {
      print('❌ Error marking departure: $e');
      rethrow;
    }
  }

  // ========================================================================
  // END TRIP (with final odometer photo)
  // ========================================================================
  Future<Map<String, dynamic>> endTrip({
    required String tripId,
    required File photo,
    required int odometerReading,
  }) async {
    try {
      print('🏁 Ending trip: $tripId');
      print('📏 Final odometer reading: $odometerReading km');
      
      // Read photo bytes
      final photoBytes = await photo.readAsBytes();
      
      // Create multipart request
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/trips/$tripId/end');
      final request = http.MultipartRequest('POST', uri);
      
      // Add headers (with authentication token)
      final headers = await _apiService.getHeaders();
      request.headers.addAll(headers);
      
      // Add fields
      request.fields['reading'] = odometerReading.toString();
      
      // Add photo file
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photoBytes,
          filename: 'odometer_end_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );
      
      print('📤 Uploading final odometer photo...');
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      print('📥 Response status: ${response.statusCode}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        
        if (responseData['success'] == true) {
          print('✅ Trip ended successfully');
          print('📏 Distance: ${responseData['data']['actualDistance']} km');
          print('⏱️  Duration: ${responseData['data']['actualDuration']} minutes');
          return responseData['data'];
        } else {
          throw Exception(responseData['message'] ?? 'Failed to end trip');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to end trip: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error ending trip: $e');
      rethrow;
    }
  }

  // ========================================================================
  // GET TRIP DETAILS
  // ========================================================================
  Future<Map<String, dynamic>> getTripDetails(String tripId) async {
    try {
      print('📋 Fetching trip details: $tripId');
      
      final response = await _apiService.get('/api/trips/$tripId');
      
      if (response['success'] == true) {
        print('✅ Trip details fetched');
        return response['data'];
      }
      
      throw Exception(response['message'] ?? 'Failed to fetch trip details');
    } catch (e) {
      print('❌ Error fetching trip details: $e');
      rethrow;
    }
  }
}