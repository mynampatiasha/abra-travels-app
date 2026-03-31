// lib/features/customer/dashboard/data/repositories/roster_repository.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:abra_fleet/core/services/api_service.dart';

class RosterRepository {
  final ApiService _apiService;

  // Constructor requires an ApiService instance
  RosterRepository({required ApiService apiService}) 
    : _apiService = apiService;

  // ========================================================================
  // EMPLOYEE MANAGEMENT METHODS
  // ========================================================================

  /// Check if an employee exists in the system by email
  /// Used during bulk import to identify existing vs new employees
  Future<Map<String, dynamic>> checkEmployeeExists({
    required String email,
  }) async {
    try {
      debugPrint('🔍 Checking if employee exists: $email');
      
      final response = await _apiService.get(
        '/api/roster/customer/check-employee?email=${Uri.encodeComponent(email)}',
      );

      debugPrint('📥 Employee check response: ${jsonEncode(response)}');

      if (response['success'] == true) {
        return {
          'exists': response['exists'] ?? false,
          'employeeId': response['employeeId'],
          'employeeData': response['employee'],
        };
      } else {
        return {'exists': false};
      }
    } catch (e) {
      debugPrint('❌ Error checking employee existence: $e');
      // If error, assume employee doesn't exist (safer approach for bulk import)
      return {'exists': false};
    }
  }

  /// Batch check multiple employees at once (optimization for large imports)
  Future<Map<String, bool>> checkMultipleEmployees({
    required List<String> emails,
  }) async {
    try {
      debugPrint('🔍 Batch checking ${emails.length} employees');
      
      final Map<String, bool> results = {};
      
      // Process in batches of 10 to avoid overwhelming the server
      for (int i = 0; i < emails.length; i += 10) {
        final batch = emails.skip(i).take(10).toList();
        
        await Future.wait(
          batch.map((email) async {
            final result = await checkEmployeeExists(email: email);
            results[email] = result['exists'] ?? false;
          })
        );
        
        // Small delay between batches to respect rate limits
        if (i + 10 < emails.length) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      
      debugPrint('✅ Batch check complete: ${results.length} employees processed');
      return results;
      
    } catch (e) {
      debugPrint('❌ Error in batch employee check: $e');
      return {};
    }
  }

  // ========================================================================
  // ROSTER CREATION METHODS
  // ========================================================================

  /// Creates a new customer roster request
  /// Supports both single roster creation and bulk import with employee data
  Future<Map<String, dynamic>> createRoster({
    required String rosterType,
    required String officeLocation,
    LatLng? officeLocationCoordinates,
    required List<String> weekdays,
    required DateTime fromDate,
    required DateTime toDate,
    required TimeOfDay fromTime,
    required TimeOfDay toTime,
    LatLng? loginPickupLocation,
    String? loginPickupAddress,
    LatLng? logoutDropLocation,
    String? logoutDropAddress,
    String? notes,
    Map<String, dynamic>? employeeData,  // Optional - for bulk import
  }) async {
    try {
      // Prepare the request body to match backend expectations
      final requestBody = {
        'rosterType': rosterType, // 'login', 'logout', 'both'
        'officeLocation': officeLocation,
        'weekdays': weekdays, // Array of strings like ['Mon', 'Tue', ...]
        
        // Send full ISO8601 date strings
        'fromDate': fromDate.toUtc().toIso8601String(),
        'toDate': toDate.toUtc().toIso8601String(),
        
        // Send time as HH:MM string format
        'fromTime': _formatTimeOfDay(fromTime),
        'toTime': _formatTimeOfDay(toTime),
        
        // Office location coordinates (Optional, backend can geocode if missing)
        if (officeLocationCoordinates != null)
          'officeLocationCoordinates': {
            'latitude': officeLocationCoordinates.latitude,
            'longitude': officeLocationCoordinates.longitude,
          },
        
        // CRITICAL: Send Address independently of coordinates
        // This allows the backend to geocode if coordinates are null (Bulk Import scenario)
        'loginPickupAddress': loginPickupAddress ?? '',
        if (loginPickupLocation != null) ...{
          'loginPickupLocation': [
            loginPickupLocation.latitude,
            loginPickupLocation.longitude,
          ],
        },
        
        // CRITICAL: Send Address independently of coordinates
        'logoutDropAddress': logoutDropAddress ?? '',
        if (logoutDropLocation != null) ...{
          'logoutDropLocation': [
            logoutDropLocation.latitude,
            logoutDropLocation.longitude,
          ],
        },
        
        // Optional notes
        if (notes != null && notes.isNotEmpty)
          'notes': notes,
        
        // NEW: Include employee data ONLY if provided (for bulk import)
        if (employeeData != null && employeeData.isNotEmpty)
          'employeeData': employeeData,
      };

      debugPrint('='.repeat(80));
      debugPrint('📤 CREATING ROSTER REQUEST');
      debugPrint('='.repeat(80));
      debugPrint('Endpoint: /api/roster/customer');
      debugPrint('Request Body:');
      debugPrint(jsonEncode(requestBody));
      if (employeeData != null) {
        debugPrint('📋 Employee Data Included:');
        debugPrint(jsonEncode(employeeData));
      }
      debugPrint('='.repeat(80));
      
      // Make the API call to the customer endpoint
      final response = await _apiService.post(
        '/api/roster/customer',
        body: requestBody,
      );

      debugPrint('='.repeat(80));
      debugPrint('✅ ROSTER CREATION RESPONSE');
      debugPrint('='.repeat(80));
      debugPrint('Response: ${jsonEncode(response)}');
      debugPrint('='.repeat(80));
      
      // Check if response indicates success
      if (response['success'] == true) {
        return response;
      } else {
        final errorMessage = response['message'] ?? 'Failed to create roster';
        debugPrint('❌ Backend returned error: $errorMessage');
        throw Exception(errorMessage);
      }
      
    } catch (e) {
      debugPrint('='.repeat(80));
      debugPrint('❌ ERROR CREATING ROSTER');
      debugPrint('='.repeat(80));
      debugPrint('Error: $e');
      debugPrint('Error Type: ${e.runtimeType}');
      debugPrint('='.repeat(80));
      
      // Re-throw with more specific error message if available
      if (e is http.ClientException) {
        throw Exception('Network error: Unable to connect to server. Please check your internet connection.');
      } else if (e.toString().contains('SocketException')) {
        throw Exception('Network error: Cannot reach server. Please verify backend URL and connectivity.');
      } else if (e.toString().contains('Connection refused')) {
        throw Exception('Network error: Server is not responding. Please check if backend is running.');
      } else if (e.toString().contains('401')) {
        throw Exception('Authentication failed. Please login again.');
      } else if (e.toString().contains('400')) {
        // Try to extract the actual validation error from backend
        final errorMsg = e.toString();
        if (errorMsg.contains('Validation failed')) {
          throw Exception('Validation failed: Please check all required fields.');
        }
        // Pass the backend error message through if possible
        throw Exception(e.toString().replaceAll('Exception:', '').trim());
      } else if (e.toString().contains('500')) {
        throw Exception('Server error. Please try again later.');
      }
      
      rethrow;
    }
  }

  /// Bulk create multiple rosters (for CSV import)
  Future<Map<String, dynamic>> bulkCreateRosters({
    required List<Map<String, dynamic>> rosters,
  }) async {
    try {
      debugPrint('='.repeat(80));
      debugPrint('📦 BULK ROSTER CREATION');
      debugPrint('='.repeat(80));
      debugPrint('Total rosters to create: ${rosters.length}');
      debugPrint('='.repeat(80));

      final response = await _apiService.post(
        '/api/roster/customer/bulk',
        body: {'rosters': rosters},
      );

      debugPrint('✅ Bulk import response received');
      debugPrint('Response: ${jsonEncode(response)}');

      if (response['success'] == true || response['data'] != null) {
        return {
          'success': true,
          'data': response['data'],
          'message': response['message'],
        };
      } else {
        throw Exception(response['message'] ?? 'Bulk import failed');
      }

    } catch (e) {
      debugPrint('❌ Error in bulk roster creation: $e');
      rethrow;
    }
  }

  // ========================================================================
  // ROSTER RETRIEVAL METHODS
  // ========================================================================

  /// Get user's roster requests with optional filters
  Future<List<Map<String, dynamic>>> getMyRosters({
    String? status,
    String? rosterType,
    String? startDate,
    String? endDate,
  }) async {
    debugPrint('\n' + '🚀 ROSTER REPOSITORY - API CALL TRACKING'.padRight(80, '='));
    debugPrint('📅 Timestamp: ${DateTime.now().toIso8601String()}');
    debugPrint('🎯 Method: getMyRosters');
    debugPrint('📋 Parameters:');
    debugPrint('   status: $status');
    debugPrint('   rosterType: $rosterType');
    debugPrint('   startDate: $startDate');
    debugPrint('   endDate: $endDate');
    
    try {
      final queryParams = <String, String>{};
      if (status != null) queryParams['status'] = status;
      if (rosterType != null) queryParams['rosterType'] = rosterType;
      if (startDate != null) queryParams['startDate'] = startDate;
      if (endDate != null) queryParams['endDate'] = endDate;

      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final endpoint = '/api/roster/customer/my-rosters' + 
          (queryString.isNotEmpty ? '?$queryString' : '');

      debugPrint('🌐 API Endpoint: $endpoint');
      debugPrint('📡 Making API call...');

      final response = await _apiService.get(endpoint);

      debugPrint('📥 Raw API Response received:');
      debugPrint('   Response type: ${response.runtimeType}');
      debugPrint('   Response keys: ${response.keys.toList()}');
      debugPrint('   Success field: ${response['success']}');
      debugPrint('   Message field: ${response['message']}');
      debugPrint('   Data field type: ${response['data']?.runtimeType}');
      
      if (response['data'] is List) {
        debugPrint('   Data array length: ${(response['data'] as List).length}');
      }
      
      // Show first few items for debugging
      if (response['data'] is List && (response['data'] as List).isNotEmpty) {
        final dataList = response['data'] as List;
        debugPrint('\n📋 SAMPLE API DATA (first 2 items):');
        for (int i = 0; i < dataList.length && i < 2; i++) {
          debugPrint('--- Item ${i + 1} ---');
          debugPrint('Type: ${dataList[i].runtimeType}');
          if (dataList[i] is Map) {
            final item = dataList[i] as Map;
            debugPrint('Keys: ${item.keys.toList()}');
            debugPrint('customerName: ${item['customerName']}');
            debugPrint('customerEmail: ${item['customerEmail']}');
            debugPrint('employeeDetails: ${item['employeeDetails']}');
            debugPrint('employeeData: ${item['employeeData']}');
            debugPrint('officeLocation: ${item['officeLocation']}');
            debugPrint('status: ${item['status']}');
            debugPrint('_id: ${item['_id']}');
          }
        }
      }

      if (response['success'] == true) {
        final rosters = List<Map<String, dynamic>>.from(response['data'] ?? []);
        debugPrint('\n✅ API CALL SUCCESSFUL:');
        debugPrint('   Total rosters returned: ${rosters.length}');
        debugPrint('   Conversion successful: ${rosters.runtimeType}');
        
        // Analyze the roster data structure
        if (rosters.isNotEmpty) {
          debugPrint('\n🔍 ROSTER DATA STRUCTURE ANALYSIS:');
          final firstRoster = rosters.first;
          debugPrint('   First roster keys: ${firstRoster.keys.toList()}');
          
          // Check for employee name fields
          final nameFields = ['customerName', 'Employee Name', 'employeeName', 'name'];
          debugPrint('   Employee name fields found:');
          for (String field in nameFields) {
            if (firstRoster.containsKey(field)) {
              debugPrint('     ✅ $field: "${firstRoster[field]}"');
            } else {
              debugPrint('     ❌ $field: not found');
            }
          }
          
          // Check for nested employee data
          if (firstRoster['employeeDetails'] != null) {
            debugPrint('   ✅ employeeDetails found: ${firstRoster['employeeDetails']}');
          } else {
            debugPrint('   ❌ employeeDetails: null');
          }
          
          if (firstRoster['employeeData'] != null) {
            debugPrint('   ✅ employeeData found: ${firstRoster['employeeData']}');
          } else {
            debugPrint('   ❌ employeeData: null');
          }
        }
        
        debugPrint('🏁 ROSTER REPOSITORY API CALL COMPLETED SUCCESSFULLY'.padRight(80, '='));
        return rosters;
      } else {
        debugPrint('❌ API returned success=false');
        debugPrint('   Error message: ${response['message']}');
        debugPrint('   Full response: $response');
        throw Exception(response['message'] ?? 'Failed to fetch rosters');
      }
    } catch (e, stackTrace) {
      debugPrint('\n❌ CRITICAL ERROR in getMyRosters:');
      debugPrint('   Error: $e');
      debugPrint('   Error type: ${e.runtimeType}');
      debugPrint('   Stack trace: $stackTrace');
      debugPrint('🏁 ROSTER REPOSITORY API CALL FAILED'.padRight(80, '='));
      rethrow;
    }
  }

  /// Get a specific roster by ID
  Future<Map<String, dynamic>> getRosterById(String rosterId) async {
    try {
      debugPrint('📥 Fetching roster by ID: $rosterId');
      
      final response = await _apiService.get('/api/roster/customer/$rosterId');

      if (response['success'] == true) {
        debugPrint('✅ Roster fetched successfully');
        return response['data'];
      } else {
        throw Exception(response['message'] ?? 'Roster not found');
      }
    } catch (e) {
      debugPrint('❌ Error fetching roster by ID: $e');
      rethrow;
    }
  }

  /// Get pending rosters (status: pending_assignment)
  Future<List<Map<String, dynamic>>> getPendingRosters() async {
    debugPrint('\n🎯 GETTING PENDING ROSTERS - CLIENT SIDE');
    debugPrint('📋 Calling getMyRosters with status: pending_assignment');
    
    try {
      final result = await getMyRosters(status: 'pending_assignment');
      debugPrint('✅ getPendingRosters completed successfully');
      debugPrint('📊 Returning ${result.length} pending rosters to client');
      return result;
    } catch (e) {
      debugPrint('❌ Error in getPendingRosters: $e');
      debugPrint('🔄 This error will be passed up to the client UI');
      rethrow;
    }
  }

  /// Get assigned rosters
  Future<List<Map<String, dynamic>>> getAssignedRosters() async {
    try {
      return await getMyRosters(status: 'assigned');
    } catch (e) {
      debugPrint('❌ Error fetching assigned rosters: $e');
      rethrow;
    }
  }

  /// Get active rosters (in progress)
  Future<List<Map<String, dynamic>>> getActiveRosters() async {
    try {
      return await getMyRosters(status: 'in_progress');
    } catch (e) {
      debugPrint('❌ Error fetching active rosters: $e');
      rethrow;
    }
  }

  /// Get completed rosters
  Future<List<Map<String, dynamic>>> getCompletedRosters() async {
    try {
      return await getMyRosters(status: 'completed');
    } catch (e) {
      debugPrint('❌ Error fetching completed rosters: $e');
      rethrow;
    }
  }

  // ========================================================================
  // LEAVE REQUEST METHODS
  // ========================================================================

  /// Submit a leave request
  Future<Map<String, dynamic>> submitLeaveRequest({
    required DateTime startDate,
    required DateTime endDate,
    String? reason,
  }) async {
    try {
      debugPrint('📅 Submitting leave request: ${startDate.toIso8601String()} to ${endDate.toIso8601String()}');
      
      final requestBody = {
        'startDate': startDate.toUtc().toIso8601String(),
        'endDate': endDate.toUtc().toIso8601String(),
        'reason': reason ?? '',
      };

      final response = await _apiService.post(
        '/api/roster/customer/leave-request',
        body: requestBody,
      );

      if (response['success'] == true) {
        debugPrint('✅ Leave request submitted successfully');
        return response;
      } else {
        throw Exception(response['message'] ?? 'Failed to submit leave request');
      }
    } catch (e) {
      debugPrint('❌ Error submitting leave request: $e');
      rethrow;
    }
  }

  /// Get customer's leave requests
  Future<List<Map<String, dynamic>>> getLeaveRequests({String? status}) async {
    try {
      debugPrint('📋 Fetching leave requests with status: $status');
      
      final queryParams = <String, String>{};
      if (status != null) queryParams['status'] = status;

      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final endpoint = '/api/roster/customer/leave-requests' + 
          (queryString.isNotEmpty ? '?$queryString' : '');

      final response = await _apiService.get(endpoint);

      if (response['success'] == true) {
        final leaveRequests = List<Map<String, dynamic>>.from(response['data'] ?? []);
        debugPrint('✅ Fetched ${leaveRequests.length} leave requests');
        return leaveRequests;
      } else {
        throw Exception(response['message'] ?? 'Failed to fetch leave requests');
      }
    } catch (e) {
      debugPrint('❌ Error fetching leave requests: $e');
      rethrow;
    }
  }

  /// Cancel a pending leave request
  Future<bool> cancelLeaveRequest(String leaveRequestId) async {
    try {
      debugPrint('🗑️ Cancelling leave request: $leaveRequestId');
      
      final response = await _apiService.delete('/api/roster/customer/leave-request/$leaveRequestId');
      
      if (response['success'] == true) {
        debugPrint('✅ Leave request cancelled successfully');
        return true;
      } else {
        throw Exception(response['message'] ?? 'Failed to cancel leave request');
      }
    } catch (e) {
      debugPrint('❌ Error cancelling leave request: $e');
      rethrow;
    }
  }

  /// Get leave request status options
  List<String> getLeaveRequestStatusOptions() {
    return [
      'pending_approval',
      'approved',
      'rejected',
      'cancelled',
    ];
  }

  /// Get human-readable leave request status
  String getLeaveRequestStatusDisplayText(String status) {
    switch (status) {
      case 'pending_approval':
        return 'Pending Approval';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.replaceAll('_', ' ').titleCase;
    }
  }

  /// Get color for leave request status
  Color getLeaveRequestStatusColor(String status) {
    switch (status) {
      case 'pending_approval':
        return const Color(0xFFF59E0B); // Orange
      case 'approved':
        return const Color(0xFF10B981); // Green
      case 'rejected':
        return const Color(0xFFEF4444); // Red
      case 'cancelled':
        return const Color(0xFF64748B); // Gray
      default:
        return const Color(0xFF64748B); // Gray
    }
  }

  /// Get icon for leave request status
  IconData getLeaveRequestStatusIcon(String status) {
    switch (status) {
      case 'pending_approval':
        return Icons.pending_actions;
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'cancelled':
        return Icons.block;
      default:
        return Icons.help_outline;
    }
  }

  // ========================================================================
  // ROSTER UPDATE METHODS
  // ========================================================================

  /// Update roster request (if allowed)
  Future<Map<String, dynamic>> updateRoster({
    required String rosterId,
    required String rosterType,
    required String officeLocation,
    required List<String> weekdays,
    required DateTime fromDate,
    required DateTime toDate,
    required TimeOfDay fromTime,
    required TimeOfDay toTime,
    LatLng? loginPickupLocation,
    String? loginPickupAddress,
    LatLng? logoutDropLocation,
    String? logoutDropAddress,
    String? notes,
  }) async {
    try {
      // Prepare update data with correct format
      final requestBody = {
        'rosterType': rosterType,
        'officeLocation': officeLocation,
        'weekdays': weekdays,
        
        // Full ISO8601 format
        'fromDate': fromDate.toUtc().toIso8601String(),
        'toDate': toDate.toUtc().toIso8601String(),
        
        'fromTime': _formatTimeOfDay(fromTime),
        'toTime': _formatTimeOfDay(toTime),
        
        // Array format [lat, lng]
        if (loginPickupLocation != null) ...{
          'loginPickupLocation': [
            loginPickupLocation.latitude,
            loginPickupLocation.longitude,
          ],
          'loginPickupAddress': loginPickupAddress ?? '',
        },
        
        if (logoutDropLocation != null) ...{
          'logoutDropLocation': [
            logoutDropLocation.latitude,
            logoutDropLocation.longitude,
          ],
          'logoutDropAddress': logoutDropAddress ?? '',
        },
        
        if (notes != null && notes.isNotEmpty)
          'notes': notes,
      };

      debugPrint('='.repeat(80));
      debugPrint('🔄 UPDATING ROSTER: $rosterId');
      debugPrint('='.repeat(80));
      debugPrint('Request Body:');
      debugPrint(jsonEncode(requestBody));
      debugPrint('='.repeat(80));

      final response = await _apiService.put(
        '/api/roster/customer/$rosterId',
        body: requestBody,
      );

      debugPrint('✅ Roster updated successfully');
      debugPrint('Response: ${jsonEncode(response)}');

      if (response['success'] == true) {
        return response;
      } else {
        throw Exception(response['message'] ?? 'Failed to update roster');
      }
    } catch (e) {
      debugPrint('❌ Error updating roster: $e');
      rethrow;
    }
  }

// ========================================================================
// DUPLICATE CHECK METHODS
// ========================================================================

/// Check if a roster already exists to prevent duplicates during bulk import
Future<Map<String, dynamic>> checkRosterExists({
  required String employeeEmail,
  required String fromDate,
  required String startTime,
  required String rosterType,
}) async {
  try {
    debugPrint('🔍 Checking if roster exists: $employeeEmail - $fromDate $startTime');
    
    final queryParams = {
      'employeeEmail': Uri.encodeComponent(employeeEmail),
      'fromDate': Uri.encodeComponent(fromDate),
      'startTime': Uri.encodeComponent(startTime),
      'rosterType': Uri.encodeComponent(rosterType),
    };
    
    final queryString = queryParams.entries
        .map((e) => '${e.key}=${e.value}')
        .join('&');
    
    final response = await _apiService.get(
      '/api/roster/customer/check-duplicate?$queryString',
    );

    debugPrint('📥 Roster check response: ${jsonEncode(response)}');

    if (response['success'] == true) {
      return {
        'exists': response['exists'] ?? false,
        'rosterId': response['rosterId'],
      };
    } else {
      return {'exists': false};
    }
  } catch (e) {
    debugPrint('❌ Error checking roster existence: $e');
    // If error, assume roster doesn't exist (safer for bulk import)
    return {'exists': false};
  }
}  

  /// Cancel a roster request
  Future<bool> cancelRoster(String rosterId) async {
    try {
      debugPrint('🗑️ Cancelling roster: $rosterId');
      
      final response = await _apiService.delete('/api/roster/customer/$rosterId');
      
      if (response['success'] == true) {
        debugPrint('✅ Roster cancelled successfully');
        return true;
      } else {
        throw Exception(response['message'] ?? 'Failed to cancel roster');
      }
    } catch (e) {
      debugPrint('❌ Error cancelling roster: $e');
      rethrow;
    }
  }

  // ========================================================================
  // VALIDATION METHODS
  // ========================================================================

  /// Validate roster data before submission
  Map<String, String> validateRosterData({
    required String rosterType,
    required String officeLocation,
    required List<String> weekdays,
    required DateTime fromDate,
    required DateTime toDate,
    required TimeOfDay fromTime,
    required TimeOfDay toTime,
    LatLng? loginPickupLocation,
    String? loginPickupAddress,
    LatLng? logoutDropLocation,
    String? logoutDropAddress,
  }) {
    final errors = <String, String>{};

    debugPrint('🔍 Validating roster data...');

    // Validate roster type
    if (!['login', 'logout', 'both'].contains(rosterType)) {
      errors['rosterType'] = 'Invalid roster type';
      debugPrint('❌ Invalid roster type: $rosterType');
    }

    // Validate office location
    if (officeLocation.isEmpty) {
      errors['officeLocation'] = 'Office location is required';
      debugPrint('❌ Office location is empty');
    }

    // Validate weekdays
    if (weekdays.isEmpty) {
      errors['weekdays'] = 'At least one weekday must be selected';
      debugPrint('❌ No weekdays selected');
    }

    // Validate date range
    if (fromDate.isAfter(toDate)) {
      errors['dateRange'] = 'Start date must be before end date';
      debugPrint('❌ Invalid date range: $fromDate to $toDate');
    }

    // Validate time range
    final fromMinutes = fromTime.hour * 60 + fromTime.minute;
    final toMinutes = toTime.hour * 60 + toTime.minute;
    if (fromMinutes == toMinutes) {
      errors['timeRange'] = 'Start time must be before end time';
      debugPrint('❌ Invalid time range: $fromTime to $toTime');
    }

    // Validate location requirements based on roster type
    // Allow EITHER Coordinates OR Address (backend will geocode)
    if (rosterType == 'login' || rosterType == 'both') {
      if (loginPickupLocation == null && (loginPickupAddress == null || loginPickupAddress.isEmpty)) {
        errors['loginLocation'] = 'Pickup location (Map or Address) is required for login roster';
        debugPrint('❌ Login pickup location missing');
      } else {
        debugPrint('✅ Login pickup location present (Map or Address)');
      }
    }

    if (rosterType == 'logout' || rosterType == 'both') {
      if (logoutDropLocation == null && (logoutDropAddress == null || logoutDropAddress.isEmpty)) {
        errors['logoutLocation'] = 'Drop location (Map or Address) is required for logout roster';
        debugPrint('❌ Logout drop location missing');
      } else {
        debugPrint('✅ Logout drop location present (Map or Address)');
      }
    }

    if (errors.isEmpty) {
      debugPrint('✅ Validation passed');
    } else {
      debugPrint('❌ Validation failed with ${errors.length} error(s)');
    }

    return errors;
  }

  // ========================================================================
  // HELPER METHODS
  // ========================================================================

  /// Get roster status options
  List<String> getRosterStatusOptions() {
    return [
      'pending_assignment',
      'assigned',
      'in_progress',
      'completed',
      'cancelled',
    ];
  }

  /// Get roster type options
  List<String> getRosterTypeOptions() {
    return [
      'login',
      'logout', 
      'both',
    ];
  }

  /// Formats TimeOfDay to HH:MM format
  String _formatTimeOfDay(TimeOfDay tod) {
    final hour = tod.hour.toString().padLeft(2, '0');
    final minute = tod.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Parse time string to TimeOfDay
  TimeOfDay _parseTimeString(String timeString) {
    final parts = timeString.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  /// Helper method to format dates for display
  String formatDateForDisplay(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Helper method to get human-readable status
  String getStatusDisplayText(String status) {
    switch (status) {
      case 'pending_assignment':
        return 'Pending Assignment';
      case 'assigned':
        return 'Assigned';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.replaceAll('_', ' ').titleCase;
    }
  }

  /// Get color for roster status
  Color getStatusColor(String status) {
    switch (status) {
      case 'pending_assignment':
        return const Color(0xFFF59E0B); // Orange
      case 'assigned':
        return const Color(0xFF2563EB); // Blue
      case 'in_progress':
        return const Color(0xFF10B981); // Green
      case 'completed':
        return const Color(0xFF64748B); // Gray
      case 'cancelled':
        return const Color(0xFFEF4444); // Red
      default:
        return const Color(0xFF64748B); // Gray
    }
  }

  /// Get icon for roster status
  IconData getStatusIcon(String status) {
    switch (status) {
      case 'pending_assignment':
        return Icons.pending_actions;
      case 'assigned':
        return Icons.assignment_turned_in;
      case 'in_progress':
        return Icons.directions_car;
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  // ========================================================================
  // ADDRESS CHANGE REQUEST METHODS
  // ========================================================================

  /// Submit an address change request
  Future<Map<String, dynamic>> submitAddressChangeRequest({
    required String currentPickupAddress,
    required String newPickupAddress,
    double? newPickupLat,
    double? newPickupLng,
    required String currentDropAddress,
    required String newDropAddress,
    double? newDropLat,
    double? newDropLng,
    String? reason,
  }) async {
    try {
      debugPrint('📍 Submitting address change request');
      
      final requestBody = {
        'currentPickupAddress': currentPickupAddress,
        'newPickupAddress': newPickupAddress,
        if (newPickupLat != null) 'newPickupLat': newPickupLat,
        if (newPickupLng != null) 'newPickupLng': newPickupLng,
        'currentDropAddress': currentDropAddress,
        'newDropAddress': newDropAddress,
        if (newDropLat != null) 'newDropLat': newDropLat,
        if (newDropLng != null) 'newDropLng': newDropLng,
        'reason': reason ?? '',
      };

      final response = await _apiService.post(
        '/api/address-change/customer/request',
        body: requestBody,
      );

      if (response['success'] == true) {
        debugPrint('✅ Address change request submitted successfully');
        return response;
      } else {
        throw Exception(response['message'] ?? 'Failed to submit address change request');
      }
    } catch (e) {
      debugPrint('❌ Error submitting address change request: $e');
      rethrow;
    }
  }

  /// Get customer's address change requests
  Future<List<Map<String, dynamic>>> getAddressChangeRequests({String? status}) async {
    try {
      debugPrint('📋 Fetching address change requests with status: $status');
      
      final queryParams = <String, String>{};
      if (status != null && status != 'all') queryParams['status'] = status;

      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final endpoint = '/api/address-change/customer/requests' + 
          (queryString.isNotEmpty ? '?$queryString' : '');

      final response = await _apiService.get(endpoint);

      if (response['success'] == true) {
        final requests = List<Map<String, dynamic>>.from(response['data'] ?? []);
        debugPrint('✅ Fetched ${requests.length} address change requests');
        return requests;
      } else {
        throw Exception(response['message'] ?? 'Failed to fetch address change requests');
      }
    } catch (e) {
      debugPrint('❌ Error fetching address change requests: $e');
      rethrow;
    }
  }

  /// Get address change request status options
  List<String> getAddressChangeStatusOptions() {
    return [
      'under_review',
      'processing',
      'completed',
      'rejected',
    ];
  }

  /// Get human-readable address change status
  String getAddressChangeStatusDisplayText(String status) {
    switch (status) {
      case 'under_review':
        return 'Under Review';
      case 'processing':
        return 'Processing';
      case 'completed':
        return 'Completed';
      case 'rejected':
        return 'Rejected';
      default:
        return status.replaceAll('_', ' ').titleCase;
    }
  }

  /// Get color for address change status
  Color getAddressChangeStatusColor(String status) {
    switch (status) {
      case 'under_review':
        return const Color(0xFFF59E0B); // Orange
      case 'processing':
        return const Color(0xFF2196F3); // Blue
      case 'completed':
        return const Color(0xFF10B981); // Green
      case 'rejected':
        return const Color(0xFFEF4444); // Red
      default:
        return const Color(0xFF64748B); // Gray
    }
  }

  /// Get icon for address change status
  IconData getAddressChangeStatusIcon(String status) {
    switch (status) {
      case 'under_review':
        return Icons.pending;
      case 'processing':
        return Icons.sync;
      case 'completed':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }
}

// Extension to capitalize first letter of each word
extension StringExtension on String {
  String get titleCase => split(' ')
      .map((word) => word.isEmpty 
          ? word 
          : word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join(' ');
  
  // Helper to repeat strings (for debug logs)
  String repeat(int count) => List.filled(count, this).join();
}