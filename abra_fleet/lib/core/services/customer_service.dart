// lib/core/services/customer_service.dart
// ============================================================================
// CUSTOMER SERVICE - Centralized Customer Data Fetching
// ============================================================================
// This service fetches ALL customers from MongoDB 'customers' collection
// regardless of how they were created:
// - Self-registration (unified_registration.js)
// - Admin creation (admin-customers-unified.js)
// - Bulk import (roster_router.js)
// - Employee import (employeeManagement.js)
// ============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import '../models/customer_model.dart';

class CustomerService {
  // Singleton pattern
  static final CustomerService _instance = CustomerService._internal();
  factory CustomerService() => _instance;
  CustomerService._internal();

  /// Fetch ALL customers from MongoDB 'customers' collection
  /// This is the SINGLE SOURCE OF TRUTH for all customer data
  Future<List<CustomerModel>> getAllCustomers({
    String? status,
    String? search,
    String? organization,
    String? department,
    int page = 1,
    int limit = 100,
  }) async {
    try {
      print('\n🔍 FETCHING ALL CUSTOMERS FROM BACKEND');
      print('─' * 80);

      // Build query parameters
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (status != null && status.isNotEmpty && status != 'All') {
        queryParams['status'] = status;
      }

      if (search != null && search.isNotEmpty) {
        queryParams['search'] = search;
      }

      if (organization != null && organization.isNotEmpty && organization != 'All Organizations') {
        queryParams['organization'] = organization;
      }

      if (department != null && department.isNotEmpty && department != 'All Departments') {
        queryParams['department'] = department;
      }

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/customers')
          .replace(queryParameters: queryParams);

      print('📡 API URL: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout - Please check your connection');
        },
      );

      print('📥 Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        
        if (jsonData['success'] == true) {
          final List<dynamic> customersJson = jsonData['data'] ?? [];
          
          print('✅ Successfully fetched ${customersJson.length} customers');
          
          final customers = customersJson
              .map((json) => CustomerModel.fromJson(json))
              .toList();

          // Print summary
          if (jsonData['summary'] != null) {
            print('📊 Summary:');
            print('   Total: ${jsonData['summary']['total']}');
            print('   Active: ${jsonData['summary']['active']}');
            print('   Inactive: ${jsonData['summary']['inactive']}');
          }

          return customers;
        } else {
          throw Exception(jsonData['message'] ?? 'Failed to fetch customers');
        }
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized - Please login again');
      } else if (response.statusCode == 403) {
        throw Exception('Access denied - You don\'t have permission to view customers');
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to fetch customers');
      }
    } catch (e) {
      print('❌ Error fetching customers: $e');
      rethrow;
    }
  }

  /// Get customer by ID
  Future<CustomerModel?> getCustomerById(String customerId) async {
    try {
      print('\n🔍 FETCHING CUSTOMER BY ID: $customerId');

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/customers/$customerId');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        
        if (jsonData['success'] == true && jsonData['data'] != null) {
          print('✅ Customer found');
          return CustomerModel.fromJson(jsonData['data']);
        }
      } else if (response.statusCode == 404) {
        print('⚠️ Customer not found');
        return null;
      }

      throw Exception('Failed to fetch customer details');
    } catch (e) {
      print('❌ Error fetching customer: $e');
      rethrow;
    }
  }

  /// Create new customer (Admin only)
  Future<CustomerModel> createCustomer({
    required String name,
    required String email,
    String? phone,
    String? companyName,
    String? department,
    String? branch,
    String? employeeId,
    String? password,
    String status = 'active',
  }) async {
    try {
      print('\n➕ CREATING NEW CUSTOMER');
      print('─' * 80);

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/customers');

      final body = {
        'name': name,
        'email': email,
        'status': status,
      };

      if (phone != null) body['phone'] = phone;
      if (companyName != null) body['companyName'] = companyName;
      if (department != null) body['department'] = department;
      if (branch != null) body['branch'] = branch;
      if (employeeId != null) body['employeeId'] = employeeId;
      if (password != null) body['password'] = password;

      print('📤 Request body: ${json.encode(body)}');

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
        body: json.encode(body),
      ).timeout(const Duration(seconds: 30));

      print('📥 Response Status: ${response.statusCode}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        
        if (jsonData['success'] == true && jsonData['data'] != null) {
          print('✅ Customer created successfully');
          return CustomerModel.fromJson(jsonData['data']);
        }
      }

      final errorData = json.decode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to create customer');
    } catch (e) {
      print('❌ Error creating customer: $e');
      rethrow;
    }
  }

  /// Update customer
  Future<CustomerModel> updateCustomer({
    required String customerId,
    String? name,
    String? email,
    String? phone,
    String? companyName,
    String? department,
    String? branch,
    String? employeeId,
    String? status,
  }) async {
    try {
      print('\n✏️ UPDATING CUSTOMER: $customerId');

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/customers/$customerId');

      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (email != null) body['email'] = email;
      if (phone != null) body['phone'] = phone;
      if (companyName != null) body['companyName'] = companyName;
      if (department != null) body['department'] = department;
      if (branch != null) body['branch'] = branch;
      if (employeeId != null) body['employeeId'] = employeeId;
      if (status != null) body['status'] = status;

      final response = await http.put(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
        body: json.encode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        
        if (jsonData['success'] == true && jsonData['data'] != null) {
          print('✅ Customer updated successfully');
          return CustomerModel.fromJson(jsonData['data']);
        }
      }

      throw Exception('Failed to update customer');
    } catch (e) {
      print('❌ Error updating customer: $e');
      rethrow;
    }
  }

  /// Delete customer
  Future<bool> deleteCustomer(String customerId) async {
    try {
      print('\n🗑️ DELETING CUSTOMER: $customerId');

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/customers/$customerId');

      final response = await http.delete(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        
        if (jsonData['success'] == true) {
          print('✅ Customer deleted successfully');
          return true;
        }
      }

      throw Exception('Failed to delete customer');
    } catch (e) {
      print('❌ Error deleting customer: $e');
      rethrow;
    }
  }

  /// Get customer statistics
  Future<Map<String, dynamic>> getCustomerStats() async {
    try {
      print('\n📊 FETCHING CUSTOMER STATISTICS');

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/customers?limit=1');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        
        if (jsonData['success'] == true && jsonData['summary'] != null) {
          print('✅ Customer stats fetched successfully');
          return jsonData['summary'];
        }
      }

      // Fallback: return default stats
      return {
        'total': 0,
        'active': 0,
        'inactive': 0,
        'pending': 0,
      };
    } catch (e) {
      print('❌ Error fetching customer stats: $e');
      return {
        'total': 0,
        'active': 0,
        'inactive': 0,
        'pending': 0,
      };
    }
  }

  /// Count customers by email domain
  /// 
  /// This method counts all customers whose email ends with the specified domain
  /// Example: domain = "@abrafleet.com" will count all customers with emails like "user@abrafleet.com"
  /// 
  /// Parameters:
  /// - [domain]: The email domain to match (e.g., "@abrafleet.com")
  /// 
  /// Returns: Count of customers with matching email domain
  Future<int> countCustomersByDomain(String domain) async {
    try {
      print('\n🔍 COUNTING CUSTOMERS BY DOMAIN: $domain');
      print('─' * 80);

      // Ensure domain starts with @
      final searchDomain = domain.startsWith('@') ? domain : '@$domain';

      // Fetch all customers and filter by domain
      final customers = await getAllCustomers(limit: 10000); // Get all customers
      
      // Count customers whose email ends with the domain
      final matchingCustomers = customers.where((customer) {
        return customer.email.toLowerCase().endsWith(searchDomain.toLowerCase());
      }).toList();

      final count = matchingCustomers.length;
      
      print('✅ Found $count customers with domain $searchDomain');
      
      return count;
    } catch (e) {
      print('❌ Error counting customers by domain: $e');
      return 0; // Return 0 on error instead of throwing
    }
  }

  /// Get customers by email domain
  /// 
  /// This method fetches all customers whose email ends with the specified domain
  /// 
  /// Parameters:
  /// - [domain]: The email domain to match (e.g., "@abrafleet.com")
  /// 
  /// Returns: List of CustomerModel objects with matching email domain
  Future<List<CustomerModel>> getCustomersByDomain(String domain) async {
    try {
      print('\n🔍 FETCHING CUSTOMERS BY DOMAIN: $domain');
      print('─' * 80);

      // Ensure domain starts with @
      final searchDomain = domain.startsWith('@') ? domain : '@$domain';

      // Build query parameters with domain filter
      final queryParams = <String, String>{
        'domain': searchDomain,
        'limit': '10000', // Get all matching customers
      };

      // Use client-specific endpoint (no permission check required)
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/client/customers')
          .replace(queryParameters: queryParams);

      print('📡 API URL: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getAuthToken()}',
        },
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Request timeout - Please check your connection');
        },
      );

      print('📥 Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        
        if (jsonData['success'] == true) {
          final List<dynamic> customersJson = jsonData['data'] ?? [];
          
          print('✅ Found ${customersJson.length} customers with domain $searchDomain');
          
          final customers = customersJson
              .map((json) => CustomerModel.fromJson(json))
              .toList();

          return customers;
        } else {
          throw Exception(jsonData['message'] ?? 'Failed to fetch customers');
        }
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized - Please login again');
      } else if (response.statusCode == 403) {
        throw Exception('Access denied - You don\'t have permission to view customers');
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to fetch customers');
      }
    } catch (e) {
      print('❌ Error fetching customers by domain: $e');
      rethrow; // Rethrow to let caller handle the error
    }
  }

  /// Get authentication token from SharedPreferences
  Future<String> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    if (token != null && token.isNotEmpty) {
      return token;
    }
    throw Exception('User not authenticated - Please login again');
  }
}