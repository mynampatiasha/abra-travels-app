import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FeedbackService {
  static final String baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:3001';

  // ✅ FIXED: Submit trip feedback
  static Future<Map<String, dynamic>> submitFeedback({
    required String tripId,
    required String driverId,  // ✅ ADDED: driverId is required
    required int rating,
    String? feedback,  // ✅ Changed from 'comment' to 'feedback'
    String? rideAgain,  // ✅ Added: rideAgain parameter
    List<String> quickTags = const [],
    String comment = '',
    String feedbackType = 'post_trip',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      print('\n⭐ FEEDBACK SERVICE - SUBMITTING FEEDBACK');
      print('   Trip ID: $tripId');
      print('   Driver ID: $driverId');
      print('   Rating: $rating');
      print('   Feedback: ${feedback ?? comment}');
      print('   Ride Again: $rideAgain');

      final response = await http.post(
        Uri.parse('$baseUrl/api/driver/customer/feedback/submit'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'tripId': tripId,
          'driverId': driverId,  // ✅ ADDED
          'rating': rating,
          if (feedback != null && feedback.isNotEmpty) 'feedback': feedback,
          if (comment.isNotEmpty && feedback == null) 'feedback': comment,
          if (rideAgain != null) 'rideAgain': rideAgain,
          // Optional: keep these for other uses
          if (quickTags.isNotEmpty) 'quickTags': quickTags,
          'feedbackType': feedbackType,
        }),
      );

      print('   Response Status: ${response.statusCode}');
      print('   Response Body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Feedback submitted successfully');
        return jsonDecode(response.body);
      } else {
        print('❌ Failed to submit feedback: ${response.body}');
        throw Exception('Failed to submit feedback: ${response.body}');
      }
    } catch (e) {
      print('❌ Error submitting feedback: $e');
      rethrow;
    }
  }

  // Rest of the methods remain the same...
  
  static Future<Map<String, dynamic>> checkFeedbackEligibility(String tripId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.get(
        Uri.parse('$baseUrl/api/feedback/eligibility/$tripId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to check eligibility: ${response.body}');
      }
    } catch (e) {
      print('Error checking feedback eligibility: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getMyFeedback({
    int limit = 20,
    int skip = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.get(
        Uri.parse('$baseUrl/api/feedback/my-feedback?limit=$limit&skip=$skip'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch feedback: ${response.body}');
      }
    } catch (e) {
      print('Error fetching feedback: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getDriverStats(
    String driverId, {
    String period = 'month',
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.get(
        Uri.parse('$baseUrl/api/feedback/driver/$driverId/stats?period=$period'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch driver stats: ${response.body}');
      }
    } catch (e) {
      print('Error fetching driver stats: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getAllFeedback({
    String? organizationId,
    int? rating,
    String? status,
    String? startDate,
    String? endDate,
    int limit = 50,
    int skip = 0,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final queryParams = <String, String>{
        'limit': limit.toString(),
        'skip': skip.toString(),
      };

      if (organizationId != null) queryParams['organizationId'] = organizationId;
      if (rating != null) queryParams['rating'] = rating.toString();
      if (status != null) queryParams['status'] = status;
      if (startDate != null) queryParams['startDate'] = startDate;
      if (endDate != null) queryParams['endDate'] = endDate;

      final uri = Uri.parse('$baseUrl/api/feedback/admin/all')
          .replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch feedback: ${response.body}');
      }
    } catch (e) {
      print('Error fetching admin feedback: $e');
      rethrow;
    }
  }
}