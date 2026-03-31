// lib/core/services/individual_trip_service.dart
// ============================================================================
// INDIVIDUAL TRIP SERVICE
// ============================================================================
// Backend mount:   app.use('/api/driver-trips', individualTripsRouter)
// Routes inside:   /individual/pending, /individual/accepted, etc.
// Full URLs:       /api/driver-trips/individual/pending  ← CORRECT
//
// Previous bug:    /api/trips/pending  → hits multiTripRoutes (roster only)
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IndividualTripService {
  // ========================================================================
  // HELPERS
  // ========================================================================

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ========================================================================
  // GET TRIPS BY STATUS
  // ========================================================================

  Future<List<Map<String, dynamic>>> getPendingTrips() async {
    try {
      final headers = await _getHeaders();
      final url = '${ApiConfig.baseUrl}/api/driver-trips/individual/pending';
      print('🔍 Fetching pending trips: $url');

      final response = await http.get(Uri.parse(url), headers: headers);
      print('📡 Status: ${response.statusCode}');
      print('📄 Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final trips = List<Map<String, dynamic>>.from(
          data['data'] ?? data['trips'] ?? [],
        );
        print('✅ Pending trips: ${trips.length}');
        return trips;
      }
      throw Exception('Failed to load pending trips: ${response.body}');
    } catch (e) {
      print('❌ getPendingTrips: $e');
      throw Exception('Failed to load pending trips: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getAcceptedTrips() async {
    try {
      final headers = await _getHeaders();
      final url = '${ApiConfig.baseUrl}/api/driver-trips/individual/accepted';
      print('🔍 Fetching accepted trips: $url');

      final response = await http.get(Uri.parse(url), headers: headers);
      print('📡 Status: ${response.statusCode}');
      print('📄 Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final trips = List<Map<String, dynamic>>.from(
          data['data'] ?? data['trips'] ?? [],
        );
        print('✅ Accepted trips: ${trips.length}');
        return trips;
      }
      throw Exception('Failed to load accepted trips: ${response.body}');
    } catch (e) {
      print('❌ getAcceptedTrips: $e');
      throw Exception('Failed to load accepted trips: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getCompletedTrips() async {
    try {
      final headers = await _getHeaders();
      final url = '${ApiConfig.baseUrl}/api/driver-trips/individual/completed';
      print('🔍 Fetching completed trips: $url');

      final response = await http.get(Uri.parse(url), headers: headers);
      print('📡 Status: ${response.statusCode}');
      print('📄 Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final trips = List<Map<String, dynamic>>.from(
          data['data'] ?? data['trips'] ?? [],
        );
        print('✅ Completed trips: ${trips.length}');
        return trips;
      }
      throw Exception('Failed to load completed trips: ${response.body}');
    } catch (e) {
      print('❌ getCompletedTrips: $e');
      throw Exception('Failed to load completed trips: $e');
    }
  }

  // ========================================================================
  // TRIP ACTIONS
  // ========================================================================

  Future<void> respondToTrip({
    required String tripId,
    required String response,
    String? notes,
  }) async {
    try {
      final headers = await _getHeaders();
      final url = '${ApiConfig.baseUrl}/api/driver-trips/individual/$tripId/respond';
      print('📤 Driver response "$response" → $url');

      final httpResponse = await http.post(
        Uri.parse(url),
        headers: headers,
        body: json.encode({'response': response, 'notes': notes ?? ''}),
      );

      print('📡 Status: ${httpResponse.statusCode}');
      print('📄 Body: ${httpResponse.body}');

      if (httpResponse.statusCode != 200) {
        throw Exception('Failed to respond: ${httpResponse.body}');
      }
      print('✅ Response sent');
    } catch (e) {
      print('❌ respondToTrip: $e');
      throw Exception('Failed to respond to trip: $e');
    }
  }

  Future<void> startTrip({
    required String tripId,
    required XFile photo,
    required int odometerReading,
  }) async {
    try {
      final token = await _getToken();
      final url = '${ApiConfig.baseUrl}/api/driver-trips/individual/$tripId/start';
      print('🚀 Start trip → $url  odometer: $odometerReading');

      var request = http.MultipartRequest('POST', Uri.parse(url));
      request.headers['Authorization'] = 'Bearer $token';

      final bytes = await photo.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'photo',
        bytes,
        filename: 'odometer_start_${DateTime.now().millisecondsSinceEpoch}.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));
      // Backend accepts both field names
      request.fields['odometerReading'] = odometerReading.toString();
      request.fields['reading'] = odometerReading.toString();

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      print('📡 Status: ${response.statusCode}');
      print('📄 Body: ${response.body}');

      if (response.statusCode != 200) {
        throw Exception('Failed to start trip: ${response.body}');
      }
      print('✅ Trip started');
    } catch (e) {
      print('❌ startTrip: $e');
      throw Exception('Failed to start trip: $e');
    }
  }

  Future<Map<String, dynamic>> endTrip({
    required String tripId,
    required XFile photo,
    required int odometerReading,
  }) async {
    try {
      final token = await _getToken();
      final url = '${ApiConfig.baseUrl}/api/driver-trips/individual/$tripId/end';
      print('🏁 End trip → $url  odometer: $odometerReading');

      var request = http.MultipartRequest('POST', Uri.parse(url));
      request.headers['Authorization'] = 'Bearer $token';

      final bytes = await photo.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'photo',
        bytes,
        filename: 'odometer_end_${DateTime.now().millisecondsSinceEpoch}.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));
      request.fields['odometerReading'] = odometerReading.toString();
      request.fields['reading'] = odometerReading.toString();

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      print('📡 Status: ${response.statusCode}');
      print('📄 Body: ${response.body}');

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        final actualDistance =
            result['actualDistance'] ?? result['data']?['actualDistance'] ?? 0;
        print('✅ Trip ended — distance: $actualDistance km');
        return {'actualDistance': actualDistance};
      }
      throw Exception('Failed to end trip: ${response.body}');
    } catch (e) {
      print('❌ endTrip: $e');
      throw Exception('Failed to end trip: $e');
    }
  }

  // ========================================================================
  // LOCATION / STOP METHODS
  // ========================================================================

  Future<void> markArrived({
    required String tripId,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final headers = await _getHeaders();
      final url = '${ApiConfig.baseUrl}/api/driver-trips/individual/$tripId/arrive';

      final body = <String, dynamic>{};
      if (latitude != null) body['latitude'] = latitude;
      if (longitude != null) body['longitude'] = longitude;

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to mark arrived: ${response.body}');
      }
      print('✅ Marked arrived');
    } catch (e) {
      print('❌ markArrived: $e');
      throw Exception('Failed to mark arrived: $e');
    }
  }

  Future<void> markDeparted({
    required String tripId,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final headers = await _getHeaders();
      final url = '${ApiConfig.baseUrl}/api/driver-trips/individual/$tripId/depart';

      final body = <String, dynamic>{};
      if (latitude != null) body['latitude'] = latitude;
      if (longitude != null) body['longitude'] = longitude;

      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to mark departed: ${response.body}');
      }
      print('✅ Marked departed');
    } catch (e) {
      print('❌ markDeparted: $e');
      throw Exception('Failed to mark departed: $e');
    }
  }

  Future<void> updateLocation({
    required String tripId,
    required double latitude,
    required double longitude,
    double? speed,
    double? heading,
  }) async {
    try {
      final headers = await _getHeaders();
      final url = '${ApiConfig.baseUrl}/api/driver-trips/individual/$tripId/location';

      await http.post(
        Uri.parse(url),
        headers: headers,
        body: json.encode({
          'latitude': latitude,
          'longitude': longitude,
          if (speed != null) 'speed': speed,
          if (heading != null) 'heading': heading,
        }),
      );
    } catch (e) {
      // Silent fail — location updates must never crash the app
      print('⚠️ updateLocation: $e');
    }
  }
}