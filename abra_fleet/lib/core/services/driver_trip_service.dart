// lib/services/driver_trip_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'api_service.dart';
import '../../app/config/api_config.dart';

class DriverTripService {
  static final DriverTripService _instance = DriverTripService._internal();
  factory DriverTripService() => _instance;
  DriverTripService._internal();

  final ApiService _apiService = ApiService();

  Future<List<Map<String, dynamic>>> getTodaysTrips() async {
    try {
      print('\n' + '🚗' * 40);
      print('FETCHING TODAY\'S TRIPS');
      print('🚗' * 40);

      // ✅ Use /today/all to get ALL trips (assigned, started, in_progress, completed)
    final response = await _apiService.get('/api/driver/trips/today/all');

      if (response['success'] == true) {
        final List<dynamic> data = response['data'] ?? [];
        print('✅ Found ${data.length} trip group(s)');
        return List<Map<String, dynamic>>.from(data);
      }

      throw Exception(response['message'] ?? 'Failed to fetch trips');
    } catch (e) {
      print('❌ Error fetching trips: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> startTrip({
    required String tripGroupId,
    required XFile photo,
    required int odometerReading,
  }) async {
    try {
      print('\n' + '🚀' * 40);
      print('STARTING TRIP: $tripGroupId');
      print('🚀' * 40);
      print('📏 Odometer: $odometerReading km');

      print('📸 Reading photo...');
      final photoBytes = await photo.readAsBytes();
      final sizeKB = (photoBytes.length / 1024).toStringAsFixed(2);
      print('✅ Photo size: $sizeKB KB');

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/driver/trips/$tripGroupId/start');
      final request = http.MultipartRequest('POST', uri);

      final headers = await _apiService.getHeaders();
      request.headers.addAll(headers);

      request.fields['reading'] = odometerReading.toString();

      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photoBytes,
          filename: 'odometer_start_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: http.MediaType('image', 'jpeg'),
        ),
      );

      print('📤 Uploading data...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('📥 Response: ${response.statusCode}');
      print('📦 Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('✅ Trip started successfully');
          print('🚀' * 40 + '\n');
          return data['data'];
        }
      }

      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to start trip');
    } catch (e) {
      print('❌ Error starting trip: $e');
      print('🚀' * 40 + '\n');
      rethrow;
    }
  }

  Future<void> updateLocation({
    required String tripGroupId,
    required double latitude,
    required double longitude,
    double? speed,
    double? heading,
  }) async {
    try {
      await _apiService.post(
        '/api/driver/trips/$tripGroupId/location',
        body: {
          'latitude': latitude,
          'longitude': longitude,
          if (speed != null) 'speed': speed,
          if (heading != null) 'heading': heading,
        },
      );
    } catch (e) {
      print('⚠️ Failed to update location: $e');
    }
  }

  Future<void> reportGPSDisabled({required String tripGroupId}) async {
    try {
      print('🚨 Reporting GPS disabled to backend...');
      await _apiService.post(
        '/api/driver/trips/$tripGroupId/gps-disabled',
        body: {
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      print('✅ GPS disabled report sent');
    } catch (e) {
      print('❌ Failed to report GPS disabled: $e');
      // Don't throw - this is a non-critical notification
    }
  }

  Future<void> markArrived({
  required String tripGroupId,  // ✅ NEW: Need tripGroupId
  required String stopId,        // ✅ This is the stopId
  double? latitude,
  double? longitude,
}) async {
  try {
    print('📍 Marking arrival at stop: $stopId');
    print('   Trip Group: $tripGroupId');
    
    // ✅ NEW: Use tripGroupId/stop/stopId/arrive endpoint
    await _apiService.post(
      '/api/driver/trips/$tripGroupId/stop/$stopId/arrive',
      body: {
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
    );
    print('✅ Marked as arrived');
  } catch (e) {
    print('❌ Error marking arrival: $e');
    rethrow;
  }
}

Future<void> markDeparted({
  required String tripGroupId,  // ✅ NEW: Need tripGroupId
  required String stopId,        // ✅ This is the stopId
  double? latitude,
  double? longitude,
}) async {
  try {
    print('🚗 Marking departure from stop: $stopId');
    print('   Trip Group: $tripGroupId');
    
    // ✅ NEW: Use tripGroupId/stop/stopId/depart endpoint
    await _apiService.post(
      '/api/driver/trips/$tripGroupId/stop/$stopId/depart',
      body: {
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
    );
    print('✅ Marked as departed');
  } catch (e) {
    print('❌ Error marking departure: $e');
    rethrow;
  }
}



/// ✅ NEW: Request customer feedback after departure
Future<void> requestCustomerFeedback({required String tripId}) async {
  try {
    print('📧 Requesting customer feedback for trip: $tripId');
    
    // This endpoint is automatically triggered by the backend
    // when driver marks departed, so we don't need to call it manually
    // But if you want to manually trigger it, you can uncomment below:
    
    /*
    await _apiService.post(
      '/api/driver/trips/$tripId/customer-feedback',
      body: {},
    );
    */
    
    print('✅ Feedback request handled by backend automatically');
  } catch (e) {
    print('⚠️ Note: Feedback requests are automatic on departure');
    // Don't throw error - feedback is optional
  }
}

Future<Map<String, dynamic>> submitFeedback({
  required String tripId,
  required String driverId,
  required int rating,
  String? feedback,
  String? rideAgain,
}) async {
  try {
    print('\n⭐ SUBMITTING CUSTOMER FEEDBACK');
    print('   Trip: $tripId');
    print('   Driver: $driverId');
    print('   Rating: $rating/5');
    
    // ✅ FIXED: Correct endpoint path
    final response = await _apiService.post(
      '/api/driver/customer/feedback/submit',  // ← Changed from /api/feedback/submit
      body: {
        'tripId': tripId,
        'driverId': driverId,
        'rating': rating,
        if (feedback != null && feedback.isNotEmpty) 'feedback': feedback,
        if (rideAgain != null) 'rideAgain': rideAgain,
      },
    );
    
    print('✅ Feedback submitted successfully');
    return response;
  } catch (e) {
    print('❌ Error submitting feedback: $e');
    rethrow;
  }
}

  Future<Map<String, dynamic>> endTrip({
    required String tripGroupId,
    required XFile photo,
    required int odometerReading,
  }) async {
    try {
      print('\n' + '🏁' * 40);
      print('ENDING TRIP: $tripGroupId');
      print('🏁' * 40);
      print('📏 Final Odometer: $odometerReading km');

      print('📸 Reading photo...');
      final photoBytes = await photo.readAsBytes();
      final sizeKB = (photoBytes.length / 1024).toStringAsFixed(2);
      print('✅ Photo size: $sizeKB KB');

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/driver/trips/$tripGroupId/end');
      final request = http.MultipartRequest('POST', uri);

      final headers = await _apiService.getHeaders();
      request.headers.addAll(headers);

      request.fields['reading'] = odometerReading.toString();

      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photoBytes,
          filename: 'odometer_end_${DateTime.now().millisecondsSinceEpoch}.jpg',
          contentType: http.MediaType('image', 'jpeg'),
        ),
      );

      print('📤 Uploading data...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('📥 Response: ${response.statusCode}');
      print('📦 Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          print('✅ Trip ended successfully');
          print('📏 Distance traveled: ${data['data']['actualDistance']} km');
          print('🏁' * 40 + '\n');
          return data['data'];
        }
      }

      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to end trip');
    } catch (e) {
      print('❌ Error ending trip: $e');
      print('🏁' * 40 + '\n');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/'
          '$startLng,$startLat;$endLng,$endLat'
          '?overview=full&geometries=geojson&steps=true';

      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];

          return {
            'distance': route['distance'] / 1000,
            'duration': (route['duration'] / 60).round(),
            'polyline': route['geometry']['coordinates'],
            'steps': route['legs'][0]['steps'],
            'fallback': false,
          };
        }
      }

      return _fallbackRoute(startLat, startLng, endLat, endLng);
    } catch (e) {
      print('⚠️ OSRM request failed, using fallback: $e');
      return _fallbackRoute(startLat, startLng, endLat, endLng);
    }
  }

  Future<int> calculateETA({
    required double currentLat,
    required double currentLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    try {
      final route = await getRoute(
        startLat: currentLat,
        startLng: currentLng,
        endLat: destinationLat,
        endLng: destinationLng,
      );
      return route['duration'] as int;
    } catch (e) {
      print('⚠️ ETA calculation failed: $e');
      return 30;
    }
  }

  Map<String, dynamic> _fallbackRoute(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    final distance = _calculateHaversineDistance(startLat, startLng, endLat, endLng);
    final duration = (distance * 3).round();

    return {
      'distance': distance,
      'duration': duration,
      'polyline': [
        [startLng, startLat],
        [endLng, endLat],
      ],
      'fallback': true,
    };
  }

  double _calculateHaversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }
}