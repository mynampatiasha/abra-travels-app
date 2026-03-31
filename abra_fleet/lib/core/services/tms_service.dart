// lib/core/services/tms_service.dart
// ============================================================================
// 🎫 TICKET MANAGEMENT SYSTEM (TMS) SERVICE - API Communication Layer
// ============================================================================
// UPDATED: Added fetchAllTicketsAdmin for admin dashboard
// ============================================================================

import 'dart:io';
import 'package:abra_fleet/core/services/safe_api_service.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:http/http.dart' as http;

class TMSService {
  final SafeApiService _api = SafeApiService();

  // ========================================================================
  // 📦 FETCH ALL EMPLOYEES (for "Assign To" dropdown)
  // ========================================================================
  Future<Map<String, dynamic>> fetchEmployees() async {
    print('🔍 Fetching employees from /api/tickets/employees'); // Debug
    
    final result = await _api.safeGet(
      '/api/tickets/employees',
      context: 'Fetch Employees',
      fallback: {'success': false, 'data': []},
    );
    
    print('📋 Employees result: $result'); // Debug
    return result;
  }

  // ========================================================================
  // ➕ CREATE NEW TICKET
  // ========================================================================
  Future<Map<String, dynamic>> createTicket({
    required String subject,
    required String message,
    required String priority,
    required int timeline, // in minutes
    required String assignedTo, // employee _id
    String status = 'Open',
    File? attachment,
  }) async {
    // If attachment exists, use multipart upload
    if (attachment != null) {
      return await _uploadTicketWithAttachment(
        subject: subject,
        message: message,
        priority: priority,
        timeline: timeline,
        assignedTo: assignedTo,
        status: status,
        attachment: attachment,
      );
    }

    // No attachment - regular POST
    return await _api.safePost(
      '/api/tickets',
      body: {
        'subject': subject,
        'message': message,
        'priority': priority,
        'timeline': timeline,
        'assigned_to': assignedTo,
        'status': status,
      },
      context: 'Create Ticket',
      fallback: {'success': false, 'message': 'Failed to create ticket'},
    );
  }

  // ========================================================================
  // 📎 PRIVATE: UPLOAD TICKET WITH ATTACHMENT (Multipart)
  // ========================================================================
  Future<Map<String, dynamic>> _uploadTicketWithAttachment({
    required String subject,
    required String message,
    required String priority,
    required int timeline,
    required String assignedTo,
    required String status,
    required File attachment,
  }) async {
    try {
      // Get headers with token from SafeApiService's underlying ApiService
      final apiService = ApiService();
      final headers = await apiService.getHeaders();
      final token = headers['Authorization']?.replaceFirst('Bearer ', '');
      
      if (token == null) {
        return {'success': false, 'message': 'Authentication token not found'};
      }

      final uri = Uri.parse('${apiService.baseUrl}/api/tickets');
      final request = http.MultipartRequest('POST', uri);

      // Add headers
      request.headers['Authorization'] = 'Bearer $token';

      // Add fields
      request.fields['subject'] = subject;
      request.fields['message'] = message;
      request.fields['priority'] = priority;
      request.fields['timeline'] = timeline.toString();
      request.fields['assigned_to'] = assignedTo;
      request.fields['status'] = status;

      // Add file
      request.files.add(
        await http.MultipartFile.fromPath(
          'attachment',
          attachment.path,
        ),
      );

      // Send request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 201 || response.statusCode == 200) {
        return {
          'success': true,
          'message': 'Ticket created successfully',
          'data': responseBody,
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to create ticket: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Upload failed: $e'};
    }
  }

  // ========================================================================
  // 📋 FETCH TICKETS RAISED BY ME (only Approved/Rejected/Reply ones)
  // ========================================================================
  Future<Map<String, dynamic>> fetchRaisedByMe() async {
    return await _api.safeGet(
      '/api/tickets',
      queryParams: {'raised_by_me': 'true'},
      context: 'Fetch Raised By Me',
      fallback: {'success': false, 'data': []},
    );
  }

  // ========================================================================
  // 📋 FETCH MY TICKETS (assigned to logged-in user - EMAIL BASED)
  // ========================================================================
  Future<Map<String, dynamic>> fetchMyTickets({
    String? status,
    String? priority,
    String? dateFrom,
    String? dateTo,
  }) async {
    final params = <String, String>{};

    if (status != null) params['status'] = status;
    if (priority != null) params['priority'] = priority;
    if (dateFrom != null) params['dateFrom'] = dateFrom;
    if (dateTo != null) params['dateTo'] = dateTo;

    return await _api.safeGet(
      '/api/tickets',
      queryParams: params,
      context: 'Fetch My Tickets',
      fallback: {'success': false, 'data': []},
    );
  }

  // ========================================================================
  // 📋 FETCH ALL TICKETS (ADMIN - Shows ALL tickets without email filter)
  // ========================================================================
  Future<Map<String, dynamic>> fetchAllTicketsAdmin({
    String? status,
    String? priority,
    String? dateFrom,
    String? dateTo,
    String? assignedTo,
  }) async {
    final params = <String, String>{};

    // Add 'admin' flag to bypass email filtering
    params['admin'] = 'true';

    if (status != null) params['status'] = status;
    if (priority != null) params['priority'] = priority;
    if (dateFrom != null) params['dateFrom'] = dateFrom;
    if (dateTo != null) params['dateTo'] = dateTo;
    if (assignedTo != null) params['assignedTo'] = assignedTo;

    print('🎫 Fetching ALL tickets (admin) with params: $params'); // Debug

    return await _api.safeGet(
      '/api/tickets',
      queryParams: params,
      context: 'Fetch All Tickets (Admin)',
      fallback: {'success': false, 'data': []},
    );
  }

  // ========================================================================
  // 📋 FETCH CLOSED TICKETS
  // ========================================================================
  Future<Map<String, dynamic>> fetchClosedTickets({
    String? dateFrom,
    String? dateTo,
    String? assignedTo,
  }) async {
    final params = <String, String>{};

    if (dateFrom != null) params['dateFrom'] = dateFrom;
    if (dateTo != null) params['dateTo'] = dateTo;
    if (assignedTo != null) params['assignedTo'] = assignedTo;

    return await _api.safeGet(
      '/api/tickets/closed',
      queryParams: params,
      context: 'Fetch Closed Tickets',
      fallback: {'success': false, 'data': []},
    );
  }

  // ========================================================================
  // 🔍 FETCH SINGLE TICKET
  // ========================================================================
  Future<Map<String, dynamic>> fetchTicket(String ticketId) async {
    return await _api.safeGet(
      '/api/tickets/$ticketId',
      context: 'Fetch Ticket',
      fallback: {'success': false, 'data': null},
    );
  }

  // ========================================================================
  // ✏️ UPDATE TICKET STATUS
  // ========================================================================
  Future<Map<String, dynamic>> updateTicketStatus(
    String ticketId,
    String status, {
    String? replySubject,
    String? replyMessage,
  }) async {
    final body = <String, dynamic>{'status': status};
    if (replySubject != null) body['reply_subject'] = replySubject;
    if (replyMessage != null) body['reply_message'] = replyMessage;
    return await _api.safePut(
      '/api/tickets/$ticketId',
      body: body,
      context: 'Update Ticket Status',
      fallback: {'success': false, 'message': 'Failed to update status'},
    );
  }

  // ========================================================================
  // ✏️ UPDATE TICKET (general - can update any field)
  // ========================================================================
  Future<Map<String, dynamic>> updateTicket(
    String ticketId,
    Map<String, dynamic> updates,
  ) async {
    return await _api.safePut(
      '/api/tickets/$ticketId',
      body: updates,
      context: 'Update Ticket',
      fallback: {'success': false, 'message': 'Failed to update ticket'},
    );
  }

  // ========================================================================
  // 🔄 REASSIGN TICKET (admin only)
  // ========================================================================
  Future<Map<String, dynamic>> reassignTicket(
    String ticketId,
    String newEmployeeId,
  ) async {
    return await _api.safePost(
      '/api/tickets/$ticketId/reassign',
      body: {'new_employee_id': newEmployeeId},
      context: 'Reassign Ticket',
      fallback: {'success': false, 'message': 'Failed to reassign ticket'},
    );
  }

  // ========================================================================
  // 🔄 REOPEN TICKET
  // ========================================================================
  Future<Map<String, dynamic>> reopenTicket(String ticketId) async {
    return await _api.safePost(
      '/api/tickets/$ticketId/reopen',
      body: {},
      context: 'Reopen Ticket',
      fallback: {'success': false, 'message': 'Failed to reopen ticket'},
    );
  }

  // ========================================================================
  // 🗑️ DELETE TICKET (admin only)
  // ========================================================================
  Future<Map<String, dynamic>> deleteTicket(String ticketId) async {
    return await _api.safeDelete(
      '/api/tickets/$ticketId',
      context: 'Delete Ticket',
      fallback: {'success': false, 'message': 'Failed to delete ticket'},
    );
  }

  // ========================================================================
  // 📊 FETCH TICKET STATISTICS
  // ========================================================================
  Future<Map<String, dynamic>> fetchStatistics() async {
    return await _api.safeGet(
      '/api/tickets/stats',
      context: 'Fetch Ticket Statistics',
      fallback: {
        'success': false,
        'data': {
          'total': 0,
          'open': 0,
          'in_progress': 0,
          'closed': 0,
          'high_priority': 0,
          'unassigned': 0,
        }
      },
    );
  }
}