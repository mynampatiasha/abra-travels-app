// lib/core/services/user_management_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/config/api_config.dart';

class UserManagementService {
  // Get auth token from SharedPreferences
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  // Get headers with auth token
  Future<Map<String, String>> _getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ============================================
  // CREATE USER WITH PERMISSIONS
  // ============================================
  Future<Map<String, dynamic>> createUser({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String role,
    required List<Map<String, dynamic>> standardPermissions,
    required List<Map<String, dynamic>> customPermissions,
  }) async {
    try {
      print('\n📝 Creating user: $email');
      
      final headers = await _getHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}/admin/users');
      
      final body = jsonEncode({
        'name': name,
        'email': email,
        'phone': phone,
        'password': password,
        'role': role,
        'standardPermissions': standardPermissions,
        'customPermissions': customPermissions,
      });

      print('   Request URL: $url');
      print('   Request body: $body');

      final response = await http.post(
        url,
        headers: headers,
        body: body,
      );

      print('   Response status: ${response.statusCode}');
      print('   Response body: ${response.body}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        print('✅ User created successfully');
        return {
          'success': true,
          'message': data['message'] ?? 'User created successfully',
          'data': data['data'],
        };
      } else {
        print('❌ Failed to create user: ${data['message']}');
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to create user',
          'error': data['error'],
        };
      }
    } catch (e) {
      print('❌ Exception creating user: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'error': 'NETWORK_ERROR',
      };
    }
  }

  // ============================================
  // GET ALL USERS (WITH PAGINATION)
  // ============================================
  Future<Map<String, dynamic>> getUsers({
    int page = 1,
    int limit = 10,
    String search = '',
    String roleFilter = '',
  }) async {
    try {
      print('\n📋 Fetching users (page: $page, limit: $limit)');
      
      final headers = await _getHeaders();
      final queryParams = {
        'page': page.toString(),
        'limit': limit.toString(),
        if (search.isNotEmpty) 'search': search,
        if (roleFilter.isNotEmpty) 'role': roleFilter,
      };
      
      final url = Uri.parse('${ApiConfig.baseUrl}/admin/users')
          .replace(queryParameters: queryParams);

      print('   Request URL: $url');

      final response = await http.get(url, headers: headers);

      print('   Response status: ${response.statusCode}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ Users fetched: ${data['data']['users'].length}');
        return {
          'success': true,
          'users': data['data']['users'],
          'pagination': data['data']['pagination'],
        };
      } else {
        print('❌ Failed to fetch users: ${data['message']}');
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to fetch users',
          'error': data['error'],
        };
      }
    } catch (e) {
      print('❌ Exception fetching users: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'error': 'NETWORK_ERROR',
      };
    }
  }

  // ============================================
  // GET USER BY ID
  // ============================================
  Future<Map<String, dynamic>> getUserById(String userId) async {
    try {
      print('\n👤 Fetching user: $userId');
      
      final headers = await _getHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}/admin/users/$userId');

      print('   Request URL: $url');

      final response = await http.get(url, headers: headers);

      print('   Response status: ${response.statusCode}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ User fetched: ${data['data']['user']['email']}');
        return {
          'success': true,
          'user': data['data']['user'],
        };
      } else {
        print('❌ Failed to fetch user: ${data['message']}');
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to fetch user',
          'error': data['error'],
        };
      }
    } catch (e) {
      print('❌ Exception fetching user: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'error': 'NETWORK_ERROR',
      };
    }
  }

  // ============================================
  // UPDATE USER PERMISSIONS
  // ============================================
  Future<Map<String, dynamic>> updateUser({
    required String userId,
    String? name,
    String? phone,
    String? role,
    List<Map<String, dynamic>>? standardPermissions,
    List<Map<String, dynamic>>? customPermissions,
    bool? isActive,
  }) async {
    try {
      print('\n✏️  Updating user: $userId');
      
      final headers = await _getHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}/admin/users/$userId');
      
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (phone != null) body['phone'] = phone;
      if (role != null) body['role'] = role;
      if (standardPermissions != null) body['standardPermissions'] = standardPermissions;
      if (customPermissions != null) body['customPermissions'] = customPermissions;
      if (isActive != null) body['isActive'] = isActive;

      print('   Request URL: $url');
      print('   Request body: ${jsonEncode(body)}');

      final response = await http.put(
        url,
        headers: headers,
        body: jsonEncode(body),
      );

      print('   Response status: ${response.statusCode}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ User updated successfully');
        return {
          'success': true,
          'message': data['message'] ?? 'User updated successfully',
          'data': data['data'],
        };
      } else {
        print('❌ Failed to update user: ${data['message']}');
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to update user',
          'error': data['error'],
        };
      }
    } catch (e) {
      print('❌ Exception updating user: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'error': 'NETWORK_ERROR',
      };
    }
  }

  // ============================================
  // DELETE USER (SOFT DELETE)
  // ============================================
  Future<Map<String, dynamic>> deleteUser(String userId) async {
    try {
      print('\n🗑️  Deleting user: $userId');
      
      final headers = await _getHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}/admin/users/$userId');

      print('   Request URL: $url');

      final response = await http.delete(url, headers: headers);

      print('   Response status: ${response.statusCode}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ User deleted successfully');
        return {
          'success': true,
          'message': data['message'] ?? 'User deleted successfully',
        };
      } else {
        print('❌ Failed to delete user: ${data['message']}');
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to delete user',
          'error': data['error'],
        };
      }
    } catch (e) {
      print('❌ Exception deleting user: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'error': 'NETWORK_ERROR',
      };
    }
  }

  // ============================================
  // TOGGLE USER STATUS (ACTIVATE/DEACTIVATE)
  // ============================================
  Future<Map<String, dynamic>> toggleUserStatus(String userId) async {
    try {
      print('\n🔄 Toggling user status: $userId');
      
      final headers = await _getHeaders();
      final url = Uri.parse('${ApiConfig.baseUrl}/admin/users/$userId/toggle-status');

      print('   Request URL: $url');

      final response = await http.patch(url, headers: headers);

      print('   Response status: ${response.statusCode}');

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ User status toggled successfully');
        return {
          'success': true,
          'message': data['message'] ?? 'User status toggled successfully',
          'isActive': data['data']['isActive'],
        };
      } else {
        print('❌ Failed to toggle user status: ${data['message']}');
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to toggle user status',
          'error': data['error'],
        };
      }
    } catch (e) {
      print('❌ Exception toggling user status: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'error': 'NETWORK_ERROR',
      };
    }
  }
}
