// ============================================================================
// HRM EMPLOYEE SERVICE
// ============================================================================
// Handles all API calls for HRM Employee Management
// Author: Abra Fleet Management System
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';

class HRMEmployeeService {
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
  // EMPLOYEE METHODS
  // ============================================================================
  
  /// Get all employees with filters and pagination
  Future<Map<String, dynamic>> getEmployees({
    String? search,
    String? status,
    String? department,
    String? position,
    String? employeeType,
    String? workLocation,
    String? companyName,
    String? country,
    String? state,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      print('📋 Fetching employees...');
      
      // Build query parameters
      final queryParams = <String, String>{};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (status != null && status.isNotEmpty) queryParams['status'] = status;
      if (department != null && department.isNotEmpty) queryParams['department'] = department;
      if (position != null && position.isNotEmpty) queryParams['position'] = position;
      if (employeeType != null && employeeType.isNotEmpty) queryParams['employeeType'] = employeeType;
      if (workLocation != null && workLocation.isNotEmpty) queryParams['workLocation'] = workLocation;
      if (companyName != null && companyName.isNotEmpty) queryParams['companyName'] = companyName;
      if (country != null && country.isNotEmpty) queryParams['country'] = country;
      if (state != null && state.isNotEmpty) queryParams['state'] = state;
      queryParams['page'] = page.toString();
      queryParams['limit'] = limit.toString();
      
      final uri = Uri.parse('$baseUrl/employees').replace(queryParameters: queryParams);
      
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers);
      
      final data = _handleResponse(response);
      
      if (data['success'] == true) {
        return {
          'employees': List<Map<String, dynamic>>.from(data['data'] ?? []),
          'pagination': data['pagination'] ?? {},
        };
      }
      
      return {'employees': [], 'pagination': {}};
    } catch (e) {
      print('❌ Error fetching employees: $e');
      rethrow;
    }
  }
  
  /// Get single employee by ID
  Future<Map<String, dynamic>?> getEmployee(String id) async {
    try {
      print('📄 Fetching employee: $id');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/employees/$id'),
        headers: headers,
      );
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      return null;
    } catch (e) {
      print('❌ Error fetching employee: $e');
      rethrow;
    }
  }
  
  /// Get active employees list for dropdown
  Future<List<Map<String, dynamic>>> getEmployeesList() async {
    try {
      print('📋 Fetching employees list for dropdown...');
      
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
      print('❌ Error fetching employees list: $e');
      rethrow;
    }
  }
  
  /// Create new employee with documents
  Future<Map<String, dynamic>> createEmployee({
    required Map<String, dynamic> employeeData,
    List<File>? documents,
    List<Map<String, String>>? documentMetadata,
  }) async {
    try {
      print('➕ Creating employee...');
      
      final token = await _getToken();
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/employees'),
      );
      
      request.headers['Authorization'] = token != null ? 'Bearer $token' : '';
      
      // Add all employee data as fields
      employeeData.forEach((key, value) {
        if (value != null) {
          request.fields[key] = value.toString();
        }
      });
      
      // Add document metadata as JSON string
      if (documentMetadata != null && documentMetadata.isNotEmpty) {
        request.fields['documentMetadata'] = json.encode(documentMetadata);
      }
      
      // Add document files
      if (documents != null && documents.isNotEmpty) {
        for (var file in documents) {
          request.files.add(
            await http.MultipartFile.fromPath('documents', file.path),
          );
        }
      }
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to create employee');
    } catch (e) {
      print('❌ Error creating employee: $e');
      rethrow;
    }
  }
  
  /// Update employee with optional new documents
  Future<Map<String, dynamic>> updateEmployee({
    required String id,
    required Map<String, dynamic> employeeData,
    List<File>? newDocuments,
    List<Map<String, String>>? documentMetadata,
  }) async {
    try {
      print('✏️ Updating employee: $id');
      
      final token = await _getToken();
      
      var request = http.MultipartRequest(
        'PUT',
        Uri.parse('$baseUrl/employees/$id'),
      );
      
      request.headers['Authorization'] = token != null ? 'Bearer $token' : '';
      
      // Add all employee data as fields
      employeeData.forEach((key, value) {
        if (value != null) {
          request.fields[key] = value.toString();
        }
      });
      
      // Add document metadata as JSON string
      if (documentMetadata != null && documentMetadata.isNotEmpty) {
        request.fields['documentMetadata'] = json.encode(documentMetadata);
      }
      
      // Add new document files
      if (newDocuments != null && newDocuments.isNotEmpty) {
        for (var file in newDocuments) {
          request.files.add(
            await http.MultipartFile.fromPath('documents', file.path),
          );
        }
      }
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      final data = _handleResponse(response);
      
      if (data['success'] == true && data['data'] != null) {
        return data['data'];
      }
      
      throw Exception('Failed to update employee');
    } catch (e) {
      print('❌ Error updating employee: $e');
      rethrow;
    }
  }
  
  /// Delete employee (Super Manager only)
  Future<void> deleteEmployee(String id) async {
    try {
      print('🗑️ Deleting employee: $id');
      
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/employees/$id'),
        headers: headers,
      );
      
      _handleResponse(response);
    } catch (e) {
      print('❌ Error deleting employee: $e');
      rethrow;
    }
  }
  
  /// Delete single document
  Future<void> deleteDocument(String employeeId, String documentId) async {
    try {
      print('🗑️ Deleting document: $documentId');
      
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('$baseUrl/employees/$employeeId/documents/$documentId'),
        headers: headers,
      );
      
      _handleResponse(response);
    } catch (e) {
      print('❌ Error deleting document: $e');
      rethrow;
    }
  }
  
  /// Download document
  Future<List<int>> downloadDocument(String employeeId, String documentId) async {
    try {
      print('⬇️ Downloading document: $documentId');
      
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/employees/$employeeId/documents/$documentId/download'),
        headers: {
          'Authorization': token != null ? 'Bearer $token' : '',
        },
      );
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        throw Exception('Failed to download document');
      }
    } catch (e) {
      print('❌ Error downloading document: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // CSV EXPORT/IMPORT
  // ============================================================================
  
  /// Export employees to CSV
  Future<String> exportCSV() async {
    try {
      print('📥 Exporting employees to CSV...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/export/csv'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return response.body;
      }
      
      throw Exception('Failed to export CSV');
    } catch (e) {
      print('❌ Error exporting CSV: $e');
      rethrow;
    }
  }
  
  /// Import employees from CSV
  Future<Map<String, dynamic>> importCSV(File file) async {
    try {
      print('📤 Importing employees from CSV...');
      
      final token = await _getToken();
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/import/csv'),
      );
      
      request.headers['Authorization'] = token != null ? 'Bearer $token' : '';
      
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      final data = _handleResponse(response);
      
      if (data['success'] == true) {
        return data['data'] ?? {};
      }
      
      throw Exception('Failed to import CSV');
    } catch (e) {
      print('❌ Error importing CSV: $e');
      rethrow;
    }
  }
  
  /// Download CSV template
  Future<String> downloadCSVTemplate() async {
    try {
      print('📄 Downloading CSV template...');
      
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/export/template'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        return response.body;
      }
      
      throw Exception('Failed to download template');
    } catch (e) {
      print('❌ Error downloading template: $e');
      rethrow;
    }
  }
  
  // ============================================================================
  // MASTER DATA HELPERS (for dropdowns)
  // ============================================================================
  
  /// Get departments from master settings
  Future<List<String>> getDepartments() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/departments'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token != null ? 'Bearer $token' : '',
        },
      );
      
      final data = json.decode(response.body);
      
      if (data['success'] == true && data['data'] != null) {
        return List<String>.from(
          (data['data'] as List).map((d) => d['name'].toString())
        );
      }
      
      return [];
    } catch (e) {
      print('❌ Error fetching departments: $e');
      return [];
    }
  }
  
  /// Get positions from master settings
  Future<List<String>> getPositions() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/positions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token != null ? 'Bearer $token' : '',
        },
      );
      
      final data = json.decode(response.body);
      
      if (data['success'] == true && data['data'] != null) {
        return List<String>.from(
          (data['data'] as List).map((p) => p['title'].toString())
        );
      }
      
      return [];
    } catch (e) {
      print('❌ Error fetching positions: $e');
      return [];
    }
  }
  
  /// Get work locations from master settings
  Future<List<String>> getWorkLocations() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/locations'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token != null ? 'Bearer $token' : '',
        },
      );
      
      final data = json.decode(response.body);
      
      if (data['success'] == true && data['data'] != null) {
        return List<String>.from(
          (data['data'] as List).map((l) => l['locationName'].toString())
        );
      }
      
      return [];
    } catch (e) {
      print('❌ Error fetching work locations: $e');
      return [];
    }
  }
  
  /// Get companies from master settings
  Future<List<String>> getCompanies() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/companies'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token != null ? 'Bearer $token' : '',
        },
      );
      
      final data = json.decode(response.body);
      
      if (data['success'] == true && data['data'] != null) {
        return List<String>.from(
          (data['data'] as List).map((c) => c['companyName'].toString())
        );
      }
      
      return [];
    } catch (e) {
      print('❌ Error fetching companies: $e');
      return [];
    }
  }
  
  /// Get office timings from master settings
  Future<List<String>> getTimings() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/timings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': token != null ? 'Bearer $token' : '',
        },
      );
      
      final data = json.decode(response.body);
      
      if (data['success'] == true && data['data'] != null) {
        return List<String>.from(
          (data['data'] as List).map((t) => '${t['startTime']} - ${t['endTime']}')
        );
      }
      
      return [];
    } catch (e) {
      print('❌ Error fetching timings: $e');
      return [];
    }
  }
}