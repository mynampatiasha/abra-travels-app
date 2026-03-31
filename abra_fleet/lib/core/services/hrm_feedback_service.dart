// ============================================================================
// HRM FEEDBACK SERVICE
// ============================================================================
// Handles all API calls for Feedback Management System
// Author: Abra Fleet Management System
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';

class HRMFeedbackService {
  // ============================================================================
  // CONFIGURATION
  // ============================================================================
  
  static String get baseUrl => '${ApiConfig.baseUrl}/api/hrm/feedback';
  
  // ============================================================================
  // HELPER METHODS
  // ============================================================================
  
  /// Get JWT token from storage
  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      print('❌ Error getting token: $e');
      return null;
    }
  }
  
  /// Get current user email from storage
  Future<String?> _getUserEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('user_email');
    } catch (e) {
      print('❌ Error getting user email: $e');
      return null;
    }
  }
  
  /// Get current user role from storage
  Future<String?> _getUserRole() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('user_role');
    } catch (e) {
      print('❌ Error getting user role: $e');
      return null;
    }
  }
  
  /// Get headers with authorization
  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': token != null ? 'Bearer $token' : '',
    };
  }
  
  /// Handle API response
  Map<String, dynamic> _handleResponse(http.Response response) {
    print('📡 Response Status: ${response.statusCode}');
    print('📡 Response Body: ${response.body}');
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        return json.decode(response.body);
      } catch (e) {
        print('❌ JSON Parse Error: $e');
        throw Exception('Invalid response format');
      }
    } else if (response.statusCode == 401) {
      throw Exception('Unauthorized. Please login again.');
    } else if (response.statusCode == 403) {
      throw Exception('Access denied. Insufficient permissions.');
    } else if (response.statusCode == 404) {
      throw Exception('Resource not found.');
    } else if (response.statusCode == 500) {
      throw Exception('Server error. Please try again later.');
    } else {
      try {
        final body = json.decode(response.body);
        throw Exception(body['message'] ?? body['error'] ?? 'Request failed');
      } catch (e) {
        throw Exception('Request failed with status ${response.statusCode}');
      }
    }
  }
  
  // ============================================================================
  // USER ROLE CHECK
  // ============================================================================
  
  /// Check if current user is admin
  Future<bool> isAdmin() async {
    try {
      print('🔐 Checking admin status...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/check-admin'),
        headers: headers,
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true) {
        return data['isAdmin'] ?? false;
      }
      
      return false;
    } catch (e) {
      print('❌ Error checking admin status: $e');
      return false;
    }
  }
  
  // ============================================================================
  // FEEDBACK SUBMISSION METHODS
  // ============================================================================
  
  /// Submit new feedback
  Future<Map<String, dynamic>> submitFeedback({
    required String feedbackType,
    required String subject,
    required String message,
    required int rating,
  }) async {
    try {
      print('📝 Submitting feedback...');
      
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/submit'),
        headers: headers,
        body: json.encode({
          'feedbackType': feedbackType,
          'subject': subject,
          'message': message,
          'rating': rating,
        }),
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to submit feedback');
    } catch (e) {
      print('❌ Error submitting feedback: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // FEEDBACK RETRIEVAL METHODS
  // ============================================================================
  
  /// Get user's own feedback history
  Future<List<Map<String, dynamic>>> getMyFeedback({
    String? dateFrom,
    String? dateTo,
    int page = 1,
    int limit = 15,
  }) async {
    try {
      print('📋 Fetching my feedback...');
      
      final headers = await _getHeaders();
      
      final queryParams = {
        'page': page.toString(),
        'limit': limit.toString(),
      };
      
      if (dateFrom != null && dateFrom.isNotEmpty) {
        queryParams['dateFrom'] = dateFrom;
      }
      
      if (dateTo != null && dateTo.isNotEmpty) {
        queryParams['dateTo'] = dateTo;
      }
      
      final uri = Uri.parse('$baseUrl/my-feedback').replace(
        queryParameters: queryParams,
      );
      
      final response = await http.get(uri, headers: headers);
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
      
      return [];
    } catch (e) {
      print('❌ Error fetching my feedback: $e');
      rethrow;
    }
  }
  
  /// Get all feedback (Admin only)
  Future<Map<String, dynamic>> getAllFeedback({
    String? source,
    String? nameFilter,
    String? type,
    String? dateFrom,
    String? dateTo,
    String? search,
    int page = 1,
    int limit = 15,
  }) async {
    try {
      print('📋 Fetching all feedback (Admin)...');
      
      final headers = await _getHeaders();
      
      final queryParams = {
        'page': page.toString(),
        'limit': limit.toString(),
      };
      
      if (source != null && source != 'all') {
        queryParams['source'] = source;
      }
      
      if (nameFilter != null && nameFilter.isNotEmpty) {
        queryParams['nameFilter'] = nameFilter;
      }
      
      if (type != null && type != 'all') {
        queryParams['type'] = type;
      }
      
      if (dateFrom != null && dateFrom.isNotEmpty) {
        queryParams['dateFrom'] = dateFrom;
      }
      
      if (dateTo != null && dateTo.isNotEmpty) {
        queryParams['dateTo'] = dateTo;
      }
      
      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }
      
      final uri = Uri.parse('$baseUrl/all-feedback').replace(
        queryParameters: queryParams,
      );
      
      final response = await http.get(uri, headers: headers);
      
      final data = _handleResponse(response);
      
      if (data['success'] == true) {
        return {
          'feedbacks': data['data'] ?? [],
          'pagination': data['pagination'] ?? {},
          'statistics': data['statistics'] ?? {},
        };
      }
      
      return {
        'feedbacks': [],
        'pagination': {},
        'statistics': {},
      };
    } catch (e) {
      print('❌ Error fetching all feedback: $e');
      rethrow;
    }
  }
  
  /// Get feedback statistics (Admin only)
  Future<Map<String, dynamic>> getFeedbackStatistics({
    String? source,
    String? nameFilter,
    String? type,
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      print('📊 Fetching feedback statistics...');
      
      final headers = await _getHeaders();
      
      final queryParams = <String, String>{};
      
      if (source != null && source != 'all') {
        queryParams['source'] = source;
      }
      
      if (nameFilter != null && nameFilter.isNotEmpty) {
        queryParams['nameFilter'] = nameFilter;
      }
      
      if (type != null && type != 'all') {
        queryParams['type'] = type;
      }
      
      if (dateFrom != null && dateFrom.isNotEmpty) {
        queryParams['dateFrom'] = dateFrom;
      }
      
      if (dateTo != null && dateTo.isNotEmpty) {
        queryParams['dateTo'] = dateTo;
      }
      
      final uri = Uri.parse('$baseUrl/statistics').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      
      final response = await http.get(uri, headers: headers);
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      return {};
    } catch (e) {
      print('❌ Error fetching statistics: $e');
      rethrow;
    }
  }
  
  /// Get user names for filter dropdown (Admin only)
  Future<Map<String, dynamic>> getUserNames({String? source}) async {
    try {
      print('👥 Fetching user names...');
      
      final headers = await _getHeaders();
      
      final queryParams = <String, String>{};
      
      if (source != null && source != 'all') {
        queryParams['source'] = source;
      }
      
      final uri = Uri.parse('$baseUrl/user-names').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      
      final response = await http.get(uri, headers: headers);
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return {
          'customers': data['data']['customers'] ?? [],
          'drivers': data['data']['drivers'] ?? [],
          'clients': data['data']['clients'] ?? [],
          'employeeAdmins': data['data']['employeeAdmins'] ?? [],
        };
      }
      
      return {
        'customers': [],
        'drivers': [],
        'clients': [],
        'employeeAdmins': [],
      };
    } catch (e) {
      print('❌ Error fetching user names: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // CONVERSATION/THREAD METHODS
  // ============================================================================
  
  /// Get conversation thread
  Future<Map<String, dynamic>> getConversation(String feedbackId) async {
    try {
      print('💬 Fetching conversation: $feedbackId');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/conversation/$feedbackId'),
        headers: headers,
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return {
          'conversation': data['data']['messages'] ?? [],
          'subject': data['data']['subject'] ?? '',
          'threadId': data['data']['threadId'] ?? feedbackId,
          'totalMessages': data['data']['totalMessages'] ?? 0,
        };
      }
      
      return {
        'conversation': [],
        'subject': '',
        'threadId': feedbackId,
        'totalMessages': 0,
      };
    } catch (e) {
      print('❌ Error fetching conversation: $e');
      rethrow;
    }
  }
  
  /// Send reply to feedback thread
  Future<Map<String, dynamic>> sendReply({
    required String threadId,
    required String message,
  }) async {
    try {
      print('💬 Sending reply to thread: $threadId');
      
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/reply'),
        headers: headers,
        body: json.encode({
          'threadId': threadId,
          'message': message,
        }),
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to send reply');
    } catch (e) {
      print('❌ Error sending reply: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // TICKET MANAGEMENT METHODS (Admin only)
  // ============================================================================
  
  /// Get employees for ticket assignment
  Future<List<Map<String, dynamic>>> getEmployeesForTicket() async {
    try {
      print('👥 Fetching employees for ticket assignment...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/employees-list'),
        headers: headers,
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
      
      return [];
    } catch (e) {
      print('❌ Error fetching employees: $e');
      rethrow;
    }
  }
  
  /// Check if ticket already exists for feedback
  Future<Map<String, dynamic>> checkTicketExists({
    required String feedbackId,
    required String submitterName,
    required String subject,
  }) async {
    try {
      print('🎫 Checking if ticket exists...');
      
      final headers = await _getHeaders();
      final uri = Uri.parse('$baseUrl/check-ticket').replace(
        queryParameters: {
          'feedbackId': feedbackId,
          'submitterName': submitterName,
          'subject': subject,
        },
      );
      
      final response = await http.get(uri, headers: headers);
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return {
          'exists': data['data']['exists'] ?? false,
          'ticketNumber': data['data']['ticketNumber'],
          'assignedName': data['data']['assignedName'],
          'status': data['data']['status'],
        };
      }
      
      return {'exists': false};
    } catch (e) {
      print('❌ Error checking ticket: $e');
      rethrow;
    }
  }
  
  /// Create ticket from feedback
  Future<Map<String, dynamic>> createTicket({
    required String feedbackId,
    required String assignedTo,
  }) async {
    try {
      print('🎫 Creating ticket from feedback: $feedbackId');
      
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/create-ticket'),
        headers: headers,
        body: json.encode({
          'feedbackId': feedbackId,
          'assignedTo': assignedTo,
        }),
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to create ticket');
    } catch (e) {
      print('❌ Error creating ticket: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // MY FEEDBACK STATISTICS (Personal Stats)
  // ============================================================================
  
  /// Get personal feedback statistics
  Future<Map<String, dynamic>> getMyFeedbackStatistics({
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      print('📊 Fetching my feedback statistics...');
      
      final headers = await _getHeaders();
      
      final queryParams = <String, String>{};
      
      if (dateFrom != null && dateFrom.isNotEmpty) {
        queryParams['dateFrom'] = dateFrom;
      }
      
      if (dateTo != null && dateTo.isNotEmpty) {
        queryParams['dateTo'] = dateTo;
      }
      
      final uri = Uri.parse('$baseUrl/my-statistics').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      
      final response = await http.get(uri, headers: headers);
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return {
          'totalCount': data['data']['totalCount'] ?? 0,
          'respondedCount': data['data']['respondedCount'] ?? 0,
          'pendingCount': data['data']['pendingCount'] ?? 0,
        };
      }
      
      return {
        'totalCount': 0,
        'respondedCount': 0,
        'pendingCount': 0,
      };
    } catch (e) {
      print('❌ Error fetching my statistics: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // EXPORT METHODS
  // ============================================================================
  
  /// Export all feedback to CSV (Admin only)
  Future<String> exportAllFeedback({
    String? source,
    String? nameFilter,
    String? type,
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      print('📥 Exporting all feedback...');
      
      final headers = await _getHeaders();
      
      final queryParams = <String, String>{};
      
      if (source != null && source != 'all') {
        queryParams['source'] = source;
      }
      
      if (nameFilter != null && nameFilter.isNotEmpty) {
        queryParams['nameFilter'] = nameFilter;
      }
      
      if (type != null && type != 'all') {
        queryParams['type'] = type;
      }
      
      if (dateFrom != null && dateFrom.isNotEmpty) {
        queryParams['dateFrom'] = dateFrom;
      }
      
      if (dateTo != null && dateTo.isNotEmpty) {
        queryParams['dateTo'] = dateTo;
      }
      
      final uri = Uri.parse('$baseUrl/export/all').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      
      final response = await http.get(uri, headers: headers);
      
      if (response.statusCode == 200) {
        return response.body;
      }
      
      throw Exception('Failed to export feedback');
    } catch (e) {
      print('❌ Error exporting feedback: $e');
      rethrow;
    }
  }
  
  /// Export my feedback to CSV
  Future<String> exportMyFeedback({
    String? dateFrom,
    String? dateTo,
  }) async {
    try {
      print('📥 Exporting my feedback...');
      
      final headers = await _getHeaders();
      
      final queryParams = <String, String>{};
      
      if (dateFrom != null && dateFrom.isNotEmpty) {
        queryParams['dateFrom'] = dateFrom;
      }
      
      if (dateTo != null && dateTo.isNotEmpty) {
        queryParams['dateTo'] = dateTo;
      }
      
      final uri = Uri.parse('$baseUrl/export/my-feedback').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      
      final response = await http.get(uri, headers: headers);
      
      if (response.statusCode == 200) {
        return response.body;
      }
      
      throw Exception('Failed to export my feedback');
    } catch (e) {
      print('❌ Error exporting my feedback: $e');
      rethrow;
    }
  }
}