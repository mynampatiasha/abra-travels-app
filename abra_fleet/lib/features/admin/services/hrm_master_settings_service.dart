// ============================================================================
// HRM MASTER SETTINGS SERVICE
// ============================================================================
// Service for managing HRM master data: Departments, Positions, Locations,
// Timings, Companies, and Leave Hierarchy
// Author: Abra Fleet Management System
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class HRMMasterSettingsService {
  // ============================================================================
  // AUTHENTICATION
  // ============================================================================
  
  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      print('❌ Error getting token: $e');
      return null;
    }
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Authorization': 'Bearer ${token ?? ''}',
      'Content-Type': 'application/json',
    };
  }

  // ============================================================================
  // DEPARTMENTS
  // ============================================================================
  
  Future<List<Map<String, dynamic>>> getDepartments() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/departments'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data'] ?? []);
        }
      }
      throw Exception('Failed to load departments');
    } catch (e) {
      print('❌ Error loading departments: $e');
      rethrow;
    }
  }

  Future<void> createDepartment(String name) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/departments'),
        headers: headers,
        body: json.encode({'name': name}),
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to create department');
      }
    } catch (e) {
      print('❌ Error creating department: $e');
      rethrow;
    }
  }

  Future<void> updateDepartment(String id, String name) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/departments/$id'),
        headers: headers,
        body: json.encode({'name': name}),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update department');
      }
    } catch (e) {
      print('❌ Error updating department: $e');
      rethrow;
    }
  }

  Future<void> deleteDepartment(String id) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/departments/$id'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to delete department');
      }
    } catch (e) {
      print('❌ Error deleting department: $e');
      rethrow;
    }
  }

  Future<String> exportDepartments() async {
    try {
      final departments = await getDepartments();
      final csvRows = <String>[];
      
      // Header
      csvRows.add('ID,Name,Created At');
      
      // Data rows
      for (final dept in departments) {
        csvRows.add('${dept['_id']},${dept['name']},${dept['createdAt'] ?? ''}');
      }
      
      return csvRows.join('\n');
    } catch (e) {
      print('❌ Error exporting departments: $e');
      rethrow;
    }
  }

  Future<Map<String, int>> importDepartments(List<Map<String, dynamic>> departments) async {
    int imported = 0;
    int failed = 0;

    for (final dept in departments) {
      try {
        await createDepartment(dept['name']);
        imported++;
      } catch (e) {
        failed++;
      }
    }

    return {'imported': imported, 'failed': failed};
  }

  // ============================================================================
  // POSITIONS
  // ============================================================================
  
  Future<List<Map<String, dynamic>>> getPositions() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/positions'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data'] ?? []);
        }
      }
      throw Exception('Failed to load positions');
    } catch (e) {
      print('❌ Error loading positions: $e');
      rethrow;
    }
  }

  Future<void> createPosition(String title, String departmentId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/positions'),
        headers: headers,
        body: json.encode({
          'title': title,
          'departmentId': departmentId,
        }),
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to create position');
      }
    } catch (e) {
      print('❌ Error creating position: $e');
      rethrow;
    }
  }

  Future<void> updatePosition(String id, String title, String departmentId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/positions/$id'),
        headers: headers,
        body: json.encode({
          'title': title,
          'departmentId': departmentId,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update position');
      }
    } catch (e) {
      print('❌ Error updating position: $e');
      rethrow;
    }
  }

  Future<void> deletePosition(String id) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/positions/$id'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to delete position');
      }
    } catch (e) {
      print('❌ Error deleting position: $e');
      rethrow;
    }
  }

  Future<String> exportPositions() async {
    try {
      final positions = await getPositions();
      final csvRows = <String>[];
      
      csvRows.add('ID,Title,Department,Created At');
      
      for (final pos in positions) {
        final deptName = pos['departmentId']?['name'] ?? 'N/A';
        csvRows.add('${pos['_id']},${pos['title']},$deptName,${pos['createdAt'] ?? ''}');
      }
      
      return csvRows.join('\n');
    } catch (e) {
      print('❌ Error exporting positions: $e');
      rethrow;
    }
  }

  // ============================================================================
  // LOCATIONS
  // ============================================================================
  
  Future<List<Map<String, dynamic>>> getLocations() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/locations'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data'] ?? []);
        }
      }
      throw Exception('Failed to load locations');
    } catch (e) {
      print('❌ Error loading locations: $e');
      rethrow;
    }
  }

  Future<void> createLocation(String name, String latitude, String longitude) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/locations'),
        headers: headers,
        body: json.encode({
          'locationName': name,
          'latitude': latitude.isEmpty ? null : latitude,
          'longitude': longitude.isEmpty ? null : longitude,
        }),
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to create location');
      }
    } catch (e) {
      print('❌ Error creating location: $e');
      rethrow;
    }
  }

  Future<void> updateLocation(String id, String name, String latitude, String longitude) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/locations/$id'),
        headers: headers,
        body: json.encode({
          'locationName': name,
          'latitude': latitude.isEmpty ? null : latitude,
          'longitude': longitude.isEmpty ? null : longitude,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update location');
      }
    } catch (e) {
      print('❌ Error updating location: $e');
      rethrow;
    }
  }

  Future<String> exportLocations() async {
    return 'ID,Name,Latitude,Longitude\n';
  }

  // ============================================================================
  // TIMINGS
  // ============================================================================
  
  Future<List<Map<String, dynamic>>> getTimings() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/timings'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data'] ?? []);
        }
      }
      throw Exception('Failed to load timings');
    } catch (e) {
      print('❌ Error loading timings: $e');
      rethrow;
    }
  }

  Future<void> createTiming(String startTime, String endTime) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/timings'),
        headers: headers,
        body: json.encode({
          'startTime': startTime,
          'endTime': endTime,
        }),
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to create timing');
      }
    } catch (e) {
      print('❌ Error creating timing: $e');
      rethrow;
    }
  }

  Future<void> updateTiming(String id, String startTime, String endTime) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/timings/$id'),
        headers: headers,
        body: json.encode({
          'startTime': startTime,
          'endTime': endTime,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update timing');
      }
    } catch (e) {
      print('❌ Error updating timing: $e');
      rethrow;
    }
  }

  Future<void> deleteTiming(String id) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/timings/$id'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to delete timing');
      }
    } catch (e) {
      print('❌ Error deleting timing: $e');
      rethrow;
    }
  }

  Future<String> exportTimings() async {
    try {
      final timings = await getTimings();
      final csvRows = <String>[];
      
      csvRows.add('ID,Start Time,End Time,Created At');
      
      for (final timing in timings) {
        csvRows.add('${timing['_id']},${timing['startTime']},${timing['endTime']},${timing['createdAt'] ?? ''}');
      }
      
      return csvRows.join('\n');
    } catch (e) {
      print('❌ Error exporting timings: $e');
      rethrow;
    }
  }

  // ============================================================================
  // COMPANIES
  // ============================================================================
  
  Future<List<Map<String, dynamic>>> getCompanies() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/companies'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['data'] ?? []);
        }
      }
      throw Exception('Failed to load companies');
    } catch (e) {
      print('❌ Error loading companies: $e');
      rethrow;
    }
  }

  Future<void> createCompany(String name, String? logoPath) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/companies'),
        headers: headers,
        body: json.encode({
          'companyName': name,
          'logoPath': logoPath ?? '',
        }),
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to create company');
      }
    } catch (e) {
      print('❌ Error creating company: $e');
      rethrow;
    }
  }

  Future<void> updateCompany(String id, String name, String? logoPath) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/companies/$id'),
        headers: headers,
        body: json.encode({
          'companyName': name,
          'logoPath': logoPath ?? '',
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update company');
      }
    } catch (e) {
      print('❌ Error updating company: $e');
      rethrow;
    }
  }

  Future<void> deleteCompany(String id) async {
    try {
      final headers = await _getHeaders();
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/api/hrm/companies/$id'),
        headers: headers,
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to delete company');
      }
    } catch (e) {
      print('❌ Error deleting company: $e');
      rethrow;
    }
  }

  Future<String> exportCompanies() async {
    try {
      final companies = await getCompanies();
      final csvRows = <String>[];
      
      csvRows.add('ID,Company Name,Logo Path,Created At');
      
      for (final company in companies) {
        csvRows.add('${company['_id']},${company['companyName']},${company['logoPath'] ?? ''},${company['createdAt'] ?? ''}');
      }
      
      return csvRows.join('\n');
    } catch (e) {
      print('❌ Error exporting companies: $e');
      rethrow;
    }
  }

  // ============================================================================
  // LEAVE HIERARCHY
  // ============================================================================
  
  Future<List<Map<String, dynamic>>> getLeaveHierarchies() async {
    return [];
  }

  Future<String> exportLeaveHierarchy() async {
    return 'ID,Position,Approver\n';
  }
}
