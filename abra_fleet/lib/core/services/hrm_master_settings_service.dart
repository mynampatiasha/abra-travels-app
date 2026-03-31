// ============================================================================
// HRM MASTER SETTINGS SERVICE
// ============================================================================
// Handles all API calls for HRM Master Settings
// Author: Abra Fleet Management System
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';

class HRMMasterSettingsService {
  // ============================================================================
  // CONFIGURATION
  // ============================================================================
  
  static String get baseUrl => '${ApiConfig.baseUrl}/api/hrm';
  
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
      return json.decode(response.body);
    } else if (response.statusCode == 401) {
      throw Exception('Unauthorized. Please login again.');
    } else if (response.statusCode == 403) {
      throw Exception('Access denied. Insufficient permissions.');
    } else if (response.statusCode == 404) {
      throw Exception('Resource not found.');
    } else {
      final body = json.decode(response.body);
      throw Exception(body['message'] ?? body['error'] ?? 'Request failed');
    }
  }
  
  // ============================================================================
  // DEPARTMENT METHODS
  // ============================================================================
  
  /// Get all departments
  Future<List<Map<String, dynamic>>> getDepartments() async {
    try {
      print('📋 Fetching departments...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/departments'),
        headers: headers,
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
      
      return [];
    } catch (e) {
      print('❌ Error fetching departments: $e');
      rethrow;
    }
  }
  
  /// Create new department
  Future<Map<String, dynamic>> createDepartment(String name) async {
    try {
      print('➕ Creating department: $name');
      
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/departments'),
        headers: headers,
        body: json.encode({'name': name}),
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to create department');
    } catch (e) {
      print('❌ Error creating department: $e');
      rethrow;
    }
  }
  
  /// Update department
  Future<Map<String, dynamic>> updateDepartment(String id, String name) async {
    try {
      print('✏️ Updating department: $id');
      
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/departments/$id'),
        headers: headers,
        body: json.encode({'name': name}),
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to update department');
    } catch (e) {
      print('❌ Error updating department: $e');
      rethrow;
    }
  }
  
  /// Delete department
  Future<void> deleteDepartment(String id) async {
    try {
      print('🗑️ Deleting department: $id');
      
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/departments/$id'),
        headers: headers,
      );
      
      _handleResponse(response);
    } catch (e) {
      print('❌ Error deleting department: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // POSITION METHODS
  // ============================================================================
  
  /// Get all positions
  Future<List<Map<String, dynamic>>> getPositions() async {
    try {
      print('📋 Fetching all positions...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/positions'),
        headers: headers,
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
      
      return [];
    } catch (e) {
      print('❌ Error fetching positions: $e');
      rethrow;
    }
  }
  
  /// Get positions by department
  Future<List<Map<String, dynamic>>> getPositionsByDepartment(String deptId) async {
    try {
      print('📋 Fetching positions for department: $deptId');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/departments/$deptId/positions'),
        headers: headers,
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
      
      return [];
    } catch (e) {
      print('❌ Error fetching positions: $e');
      rethrow;
    }
  }
  
  /// Create new position
  Future<Map<String, dynamic>> createPosition(String title, String departmentId) async {
    try {
      print('➕ Creating position: $title');
      
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/positions'),
        headers: headers,
        body: json.encode({
          'title': title,
          'departmentId': departmentId,
        }),
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to create position');
    } catch (e) {
      print('❌ Error creating position: $e');
      rethrow;
    }
  }
  
  /// Update position
  Future<Map<String, dynamic>> updatePosition(String id, String title, String departmentId) async {
    try {
      print('✏️ Updating position: $id');
      
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/positions/$id'),
        headers: headers,
        body: json.encode({
          'title': title,
          'departmentId': departmentId,
        }),
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to update position');
    } catch (e) {
      print('❌ Error updating position: $e');
      rethrow;
    }
  }
  
  /// Delete position
  Future<void> deletePosition(String id) async {
    try {
      print('🗑️ Deleting position: $id');
      
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/positions/$id'),
        headers: headers,
      );
      
      _handleResponse(response);
    } catch (e) {
      print('❌ Error deleting position: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // LOCATION METHODS
  // ============================================================================
  
  /// Get all locations
  Future<List<Map<String, dynamic>>> getLocations() async {
    try {
      print('📍 Fetching locations...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/locations'),
        headers: headers,
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
      
      return [];
    } catch (e) {
      print('❌ Error fetching locations: $e');
      rethrow;
    }
  }
  
  /// Create new location
  Future<Map<String, dynamic>> createLocation(String locationName, String latitude, String longitude) async {
    try {
      print('➕ Creating location: $locationName');
      
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/locations'),
        headers: headers,
        body: json.encode({
          'locationName': locationName,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to create location');
    } catch (e) {
      print('❌ Error creating location: $e');
      rethrow;
    }
  }
  
  /// Update location
  Future<Map<String, dynamic>> updateLocation(String id, String locationName, String latitude, String longitude) async {
    try {
      print('✏️ Updating location: $id');
      
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/locations/$id'),
        headers: headers,
        body: json.encode({
          'locationName': locationName,
          'latitude': latitude,
          'longitude': longitude,
        }),
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to update location');
    } catch (e) {
      print('❌ Error updating location: $e');
      rethrow;
    }
  }
  
  /// Delete location
  Future<void> deleteLocation(String id) async {
    try {
      print('🗑️ Deleting location: $id');
      
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/locations/$id'),
        headers: headers,
      );
      
      _handleResponse(response);
    } catch (e) {
      print('❌ Error deleting location: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // TIMING METHODS
  // ============================================================================
  
  /// Get all timings
  Future<List<Map<String, dynamic>>> getTimings() async {
    try {
      print('⏰ Fetching timings...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/timings'),
        headers: headers,
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
      
      return [];
    } catch (e) {
      print('❌ Error fetching timings: $e');
      rethrow;
    }
  }
  
  /// Create new timing
  Future<Map<String, dynamic>> createTiming(String startTime, String endTime) async {
    try {
      print('➕ Creating timing: $startTime - $endTime');
      
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/timings'),
        headers: headers,
        body: json.encode({
          'startTime': startTime,
          'endTime': endTime,
        }),
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to create timing');
    } catch (e) {
      print('❌ Error creating timing: $e');
      rethrow;
    }
  }
  
  /// Update timing
  Future<Map<String, dynamic>> updateTiming(String id, String startTime, String endTime) async {
    try {
      print('✏️ Updating timing: $id');
      
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/timings/$id'),
        headers: headers,
        body: json.encode({
          'startTime': startTime,
          'endTime': endTime,
        }),
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to update timing');
    } catch (e) {
      print('❌ Error updating timing: $e');
      rethrow;
    }
  }
  
  /// Delete timing
  Future<void> deleteTiming(String id) async {
    try {
      print('🗑️ Deleting timing: $id');
      
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/timings/$id'),
        headers: headers,
      );
      
      _handleResponse(response);
    } catch (e) {
      print('❌ Error deleting timing: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // COMPANY METHODS
  // ============================================================================
  
  /// Get all companies
  Future<List<Map<String, dynamic>>> getCompanies() async {
    try {
      print('🏢 Fetching companies...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/companies'),
        headers: headers,
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
      
      return [];
    } catch (e) {
      print('❌ Error fetching companies: $e');
      rethrow;
    }
  }
  
  /// Create new company with logo
  Future<Map<String, dynamic>> createCompany(String companyName, {File? logoFile}) async {
    try {
      print('➕ Creating company: $companyName');
      
      final token = await _getToken();
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/companies'),
      );
      
      request.headers['Authorization'] = token != null ? 'Bearer $token' : '';
      request.fields['companyName'] = companyName;
      
      if (logoFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath('logo', logoFile.path),
        );
      }
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to create company');
    } catch (e) {
      print('❌ Error creating company: $e');
      rethrow;
    }
  }
  
  /// Update company with optional logo
  Future<Map<String, dynamic>> updateCompany(String id, String companyName, {File? logoFile}) async {
    try {
      print('✏️ Updating company: $id');
      
      final token = await _getToken();
      
      var request = http.MultipartRequest(
        'PUT',
        Uri.parse('$baseUrl/companies/$id'),
      );
      
      request.headers['Authorization'] = token != null ? 'Bearer $token' : '';
      request.fields['companyName'] = companyName;
      
      if (logoFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath('logo', logoFile.path),
        );
      }
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to update company');
    } catch (e) {
      print('❌ Error updating company: $e');
      rethrow;
    }
  }
  
  /// Delete company
  Future<void> deleteCompany(String id) async {
    try {
      print('🗑️ Deleting company: $id');
      
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/companies/$id'),
        headers: headers,
      );
      
      _handleResponse(response);
    } catch (e) {
      print('❌ Error deleting company: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // LEAVE HIERARCHY METHODS
  // ============================================================================
  
  /// Get all leave hierarchies
  Future<List<Map<String, dynamic>>> getLeaveHierarchies() async {
    try {
      print('👥 Fetching leave hierarchies...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/leave-hierarchy'),
        headers: headers,
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return List<Map<String, dynamic>>.from(data['data']);
      }
      
      return [];
    } catch (e) {
      print('❌ Error fetching hierarchies: $e');
      rethrow;
    }
  }
  
  /// Save leave hierarchy
  Future<Map<String, dynamic>> saveLeaveHierarchy(
    String positionId,
    String? approver1Id,
    String? approver2Id,
  ) async {
    try {
      print('💾 Saving leave hierarchy for position: $positionId');
      
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/leave-hierarchy'),
        headers: headers,
        body: json.encode({
          'positionId': positionId,
          'approver1Id': approver1Id,
          'approver2Id': approver2Id,
        }),
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to save hierarchy');
    } catch (e) {
      print('❌ Error saving hierarchy: $e');
      rethrow;
    }
  }
  
  /// Clear leave hierarchy
  Future<void> clearLeaveHierarchy(String positionId) async {
    try {
      print('🗑️ Clearing hierarchy for position: $positionId');
      
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/leave-hierarchy/$positionId'),
        headers: headers,
      );
      
      _handleResponse(response);
    } catch (e) {
      print('❌ Error clearing hierarchy: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // EXPORT METHODS
  // ============================================================================
  
  /// Export departments to CSV
  Future<String> exportDepartments() async {
    try {
      print('📥 Exporting departments...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/export/departments'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return response.body;
      }
      
      throw Exception('Failed to export departments');
    } catch (e) {
      print('❌ Error exporting departments: $e');
      rethrow;
    }
  }
  
  /// Export positions to CSV
  Future<String> exportPositions() async {
    try {
      print('📥 Exporting positions...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/export/positions'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return response.body;
      }
      
      throw Exception('Failed to export positions');
    } catch (e) {
      print('❌ Error exporting positions: $e');
      rethrow;
    }
  }
  
  /// Export locations to CSV
  Future<String> exportLocations() async {
    try {
      print('📥 Exporting locations...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/export/locations'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return response.body;
      }
      
      throw Exception('Failed to export locations');
    } catch (e) {
      print('❌ Error exporting locations: $e');
      rethrow;
    }
  }
  
  /// Export timings to CSV
  Future<String> exportTimings() async {
    try {
      print('📥 Exporting timings...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/export/timings'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return response.body;
      }
      
      throw Exception('Failed to export timings');
    } catch (e) {
      print('❌ Error exporting timings: $e');
      rethrow;
    }
  }
  
  /// Export companies to CSV
  Future<String> exportCompanies() async {
    try {
      print('📥 Exporting companies...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/export/companies'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return response.body;
      }
      
      throw Exception('Failed to export companies');
    } catch (e) {
      print('❌ Error exporting companies: $e');
      rethrow;
    }
  }
  
  /// Export leave hierarchy to CSV
  Future<String> exportLeaveHierarchy() async {
    try {
      print('📥 Exporting leave hierarchy...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/export/leave-hierarchy'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return response.body;
      }
      
      throw Exception('Failed to export hierarchy');
    } catch (e) {
      print('❌ Error exporting hierarchy: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // IMPORT METHODS
  // ============================================================================
  
  /// Import departments from parsed CSV data
  Future<Map<String, dynamic>> importDepartments(List<Map<String, dynamic>> departments) async {
    try {
      print('📤 Importing ${departments.length} departments...');
      
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/import/departments'),
        headers: headers,
        body: json.encode({'departments': departments}),
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true) {
        return data;
      }
      
      throw Exception('Failed to import departments');
    } catch (e) {
      print('❌ Error importing departments: $e');
      rethrow;
    }
  }
}