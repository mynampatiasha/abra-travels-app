import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';

class ClientManagementService {
  static final String _baseUrl = ApiConfig.baseUrl;

  Future<String> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token != null) {
      return token;
    }
    throw Exception('User not authenticated');
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
  };

  Future<Map<String, String>> get _authHeaders async {
    final token = await _getAuthToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  // ============================================================================
  // CLIENT CRUD OPERATIONS
  // ============================================================================

  /// Get all clients with filtering and pagination
  Future<Map<String, dynamic>> getAllClients({
    int page = 1,
    int limit = 50,
    String? status,
    String? search,
    String? organization,
    bool fullDetails = false,
  }) async {
    try {
      final headers = await _authHeaders;
      
      // Build query parameters
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        'fullDetails': fullDetails.toString(),
      };
      
      if (status != null && status.isNotEmpty) queryParams['status'] = status;
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (organization != null && organization.isNotEmpty) queryParams['organization'] = organization;
      
      final uri = Uri.parse('$_baseUrl/admin/clients/unified').replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      throw Exception('Failed to fetch clients: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching clients: $e');
    }
  }

  /// Get client by ID
  Future<Map<String, dynamic>> getClientById(String clientId) async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/clients/unified/$clientId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data['data'];
        }
      }
      throw Exception('Failed to fetch client: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching client: $e');
    }
  }

  /// Create new client (Admin function)
  Future<Map<String, dynamic>> createClient({
    required String name,
    required String email,
    String? phone,
    String? companyName,
    String? organizationName,
    String? password,
    String status = 'active',
  }) async {
    try {
      final headers = await _authHeaders;
      final body = {
        'name': name,
        'email': email,
        'phone': phone,
        'companyName': companyName,
        'organizationName': organizationName,
        'password': password,
        'status': status,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/admin/clients/unified'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      throw Exception('Failed to create client: ${response.body}');
    } catch (e) {
      throw Exception('Error creating client: $e');
    }
  }

  /// Update client
  Future<Map<String, dynamic>> updateClient(
    String clientId,
    Map<String, dynamic> updateData,
  ) async {
    try {
      final headers = await _authHeaders;
      final response = await http.put(
        Uri.parse('$_baseUrl/admin/clients/unified/$clientId'),
        headers: headers,
        body: json.encode(updateData),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      throw Exception('Failed to update client: ${response.body}');
    } catch (e) {
      throw Exception('Error updating client: $e');
    }
  }

  /// Delete client (soft delete)
  Future<bool> deleteClient(String clientId) async {
    try {
      final headers = await _authHeaders;
      final response = await http.delete(
        Uri.parse('$_baseUrl/admin/clients/unified/$clientId'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] ?? false;
      }
      throw Exception('Failed to delete client: ${response.body}');
    } catch (e) {
      throw Exception('Error deleting client: $e');
    }
  }

  // ============================================================================
  // CLIENT-CUSTOMER RELATIONSHIP
  // ============================================================================

  /// Get all customers for a specific client
  Future<Map<String, dynamic>> getClientCustomers(String clientId) async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/clients/unified/$clientId/customers'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      throw Exception('Failed to fetch client customers: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching client customers: $e');
    }
  }

  /// Sync customer counts for all clients
  Future<Map<String, dynamic>> syncCustomerCounts() async {
    try {
      final headers = await _authHeaders;
      final response = await http.post(
        Uri.parse('$_baseUrl/clients/sync-customer-counts'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      throw Exception('Failed to sync customer counts: ${response.body}');
    } catch (e) {
      throw Exception('Error syncing customer counts: $e');
    }
  }

  // ============================================================================
  // CLIENT ANALYTICS & REPORTS
  // ============================================================================

  /// Get client dashboard analytics
  Future<Map<String, dynamic>> getClientAnalytics(String clientId) async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/clients/unified/$clientId/analytics'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data['analytics'];
        }
      }
      throw Exception('Failed to fetch client analytics: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching client analytics: $e');
    }
  }

  /// Get client trip statistics
  Future<Map<String, dynamic>> getClientTripStats(
    String clientId, {
    String period = 'today',
  }) async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/clients/unified/$clientId/trips/stats?period=$period'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data['stats'];
        }
      }
      throw Exception('Failed to fetch client trip stats: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching client trip stats: $e');
    }
  }

  // ============================================================================
  // BULK OPERATIONS
  // ============================================================================

  /// Bulk import clients from CSV
  Future<Map<String, dynamic>> bulkImportClients(List<Map<String, dynamic>> clientsData) async {
    try {
      final headers = await _authHeaders;
      final response = await http.post(
        Uri.parse('$_baseUrl/admin/clients/unified/bulk-import'),
        headers: headers,
        body: json.encode({'clients': clientsData}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      throw Exception('Failed to bulk import clients: ${response.body}');
    } catch (e) {
      throw Exception('Error bulk importing clients: $e');
    }
  }

  /// Export clients to CSV format
  Future<List<Map<String, dynamic>>> exportClients({
    String? status,
    String? organization,
  }) async {
    try {
      final headers = await _authHeaders;
      
      final queryParams = <String, String>{};
      if (status != null && status.isNotEmpty) queryParams['status'] = status;
      if (organization != null && organization.isNotEmpty) queryParams['organization'] = organization;
      
      final uri = Uri.parse('$_baseUrl/admin/clients/unified/export').replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return List<Map<String, dynamic>>.from(data['clients']);
        }
      }
      throw Exception('Failed to export clients: ${response.body}');
    } catch (e) {
      throw Exception('Error exporting clients: $e');
    }
  }

  // ============================================================================
  // SEARCH & FILTERING
  // ============================================================================

  /// Search clients with advanced filters
  Future<Map<String, dynamic>> searchClients({
    String? query,
    String? status,
    String? organization,
    DateTime? createdAfter,
    DateTime? createdBefore,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final headers = await _authHeaders;
      
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };
      
      if (query != null && query.isNotEmpty) queryParams['search'] = query;
      if (status != null && status.isNotEmpty) queryParams['status'] = status;
      if (organization != null && organization.isNotEmpty) queryParams['organization'] = organization;
      if (createdAfter != null) queryParams['createdAfter'] = createdAfter.toIso8601String();
      if (createdBefore != null) queryParams['createdBefore'] = createdBefore.toIso8601String();
      
      final uri = Uri.parse('$_baseUrl/admin/clients/unified/search').replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data;
        }
      }
      throw Exception('Failed to search clients: ${response.body}');
    } catch (e) {
      throw Exception('Error searching clients: $e');
    }
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Get client statistics summary
  Future<Map<String, dynamic>> getClientsSummary() async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/clients/unified/summary'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          return data['summary'];
        }
      }
      throw Exception('Failed to fetch clients summary: ${response.body}');
    } catch (e) {
      throw Exception('Error fetching clients summary: $e');
    }
  }

  /// Validate client email availability
  Future<bool> isEmailAvailable(String email) async {
    try {
      final headers = await _authHeaders;
      final response = await http.get(
        Uri.parse('$_baseUrl/admin/clients/unified/validate-email?email=$email'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['available'] ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}