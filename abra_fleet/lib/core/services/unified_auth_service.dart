// lib/core/services/unified_auth_service.dart
// JWT + MongoDB Version - No Firebase Auth

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/core/exceptions/auth_exception.dart';

class UnifiedAuthService {
  static final String _baseUrl = ApiConfig.baseUrl;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
  };

  // Helper method to get auth token from SharedPreferences
  Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('jwt_token');
  }

  // Helper method to get headers with JWT token
  Future<Map<String, String>> _getAuthHeaders() async {
    final token = await _getAuthToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ============================================================================
  // UNIFIED REGISTRATION (Clients & Customers)
  // ============================================================================

  /// Register as client (self-registration)
  Future<Map<String, dynamic>> registerAsClient({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? companyName,
    String? organizationName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/register'),
        headers: _headers,
        body: json.encode({
          'name': name,
          'email': email,
          'password': password,
          'phone': phone,
          'companyName': companyName,
          'organizationName': organizationName,
          'role': 'client',
          'status': 'active',
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          // Save JWT token and user data
          await _saveAuthData(data);
          return data;
        }
      }
      
      final errorData = json.decode(response.body);
      throw AuthException(
        code: 'registration-failed',
        message: errorData['message'] ?? 'Registration failed',
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        code: 'registration-error',
        message: 'Client registration failed: $e',
      );
    }
  }

  /// Register as customer (self-registration)
  Future<Map<String, dynamic>> registerAsCustomer({
    required String name,
    required String email,
    required String password,
    String? phone,
    String? companyName,
    String? department,
    String? branch,
    String? employeeId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/register'),
        headers: _headers,
        body: json.encode({
          'name': name,
          'email': email,
          'password': password,
          'phone': phone,
          'companyName': companyName,
          'department': department,
          'branch': branch,
          'employeeId': employeeId,
          'role': 'customer',
          'status': 'active',
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          // Save JWT token and user data
          await _saveAuthData(data);
          return data;
        }
      }
      
      final errorData = json.decode(response.body);
      throw AuthException(
        code: 'registration-failed',
        message: errorData['message'] ?? 'Registration failed',
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        code: 'registration-error',
        message: 'Customer registration failed: $e',
      );
    }
  }

  /// Generic registration method (role-based routing)
  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String role, // 'client' or 'customer'
    String? phone,
    String? companyName,
    String? organizationName,
    String? department,
    String? branch,
    String? employeeId,
  }) async {
    try {
      final body = {
        'name': name,
        'email': email,
        'password': password,
        'role': role.toLowerCase(),
        'status': 'active',
      };

      // Add optional fields
      if (phone != null && phone.isNotEmpty) body['phone'] = phone;
      if (companyName != null && companyName.isNotEmpty) body['companyName'] = companyName;
      if (organizationName != null && organizationName.isNotEmpty) body['organizationName'] = organizationName;
      if (department != null && department.isNotEmpty) body['department'] = department;
      if (branch != null && branch.isNotEmpty) body['branch'] = branch;
      if (employeeId != null && employeeId.isNotEmpty) body['employeeId'] = employeeId;

      final response = await http.post(
        Uri.parse('$_baseUrl/auth/register'),
        headers: _headers,
        body: json.encode(body),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          // Save JWT token and user data
          await _saveAuthData(data);
          return data;
        }
      }
      
      final errorData = json.decode(response.body);
      throw AuthException(
        code: 'registration-failed',
        message: errorData['message'] ?? 'Registration failed',
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        code: 'registration-error',
        message: 'Registration failed: $e',
      );
    }
  }

  // ============================================================================
  // AUTHENTICATION METHODS
  // ============================================================================

  /// Sign in with email and password (JWT-based)
  Future<Map<String, dynamic>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/login'),
        headers: _headers,
        body: json.encode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          // Save JWT token and user data
          await _saveAuthData(data);
          return data;
        }
      }
      
      final errorData = json.decode(response.body);
      throw AuthException(
        code: errorData['code'] ?? 'login-failed',
        message: errorData['message'] ?? 'Login failed',
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        code: 'login-error',
        message: 'Sign in failed: $e',
      );
    }
  }

  /// Save authentication data to SharedPreferences
  Future<void> _saveAuthData(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Save JWT token
    if (data['token'] != null) {
      await prefs.setString('jwt_token', data['token']);
    }
    
    // Save user data
    if (data['user'] != null) {
      await prefs.setString('user_data', json.encode(data['user']));
      await prefs.setString('user_role', data['user']['role'] ?? '');
      await prefs.setString('user_id', data['user']['id'] ?? '');
      await prefs.setString('user_email', data['user']['email'] ?? '');
      await prefs.setString('user_name', data['user']['name'] ?? '');
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwt_token');
      await prefs.remove('user_data');
      await prefs.remove('user_role');
      await prefs.remove('user_id');
      await prefs.remove('user_email');
      await prefs.remove('user_name');
    } catch (e) {
      throw AuthException(
        code: 'signout-error',
        message: 'Sign out failed: $e',
      );
    }
  }

  /// Get current user data from SharedPreferences
  Future<Map<String, dynamic>?> getCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString('user_data');
      if (userDataString != null) {
        return json.decode(userDataString);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Check if user is signed in
  Future<bool> isSignedIn() async {
    final token = await _getAuthToken();
    return token != null && token.isNotEmpty;
  }

  /// Get current user token
  Future<String?> getCurrentUserToken() async {
    return await _getAuthToken();
  }

  /// Get current user role
  Future<String?> getCurrentUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_role');
  }

  /// Get current user ID
  Future<String?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  // ============================================================================
  // PASSWORD RESET
  // ============================================================================

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/forgot-password'),
        headers: _headers,
        body: json.encode({'email': email}),
      );

      if (response.statusCode != 200) {
        final errorData = json.decode(response.body);
        throw AuthException(
          code: 'password-reset-failed',
          message: errorData['message'] ?? 'Failed to send password reset email',
        );
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        code: 'password-reset-error',
        message: 'Failed to send password reset email: $e',
      );
    }
  }

  /// Confirm password reset
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/reset-password'),
        headers: _headers,
        body: json.encode({
          'resetToken': code,
          'newPassword': newPassword,
        }),
      );

      if (response.statusCode != 200) {
        final errorData = json.decode(response.body);
        throw AuthException(
          code: 'password-reset-failed',
          message: errorData['message'] ?? 'Failed to reset password',
        );
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        code: 'password-reset-error',
        message: 'Failed to reset password: $e',
      );
    }
  }

  // ============================================================================
  // PROFILE MANAGEMENT
  // ============================================================================

  /// Update user profile
  Future<void> updateProfile({
    String? displayName,
    String? photoURL,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.put(
        Uri.parse('$_baseUrl/api/users/profile'),
        headers: headers,
        body: json.encode({
          if (displayName != null) 'name': displayName,
          if (photoURL != null) 'photoURL': photoURL,
        }),
      );

      if (response.statusCode == 200) {
        // Update local user data
        final userData = await getCurrentUser();
        if (userData != null) {
          if (displayName != null) userData['name'] = displayName;
          if (photoURL != null) userData['photoURL'] = photoURL;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_data', json.encode(userData));
        }
      } else {
        final errorData = json.decode(response.body);
        throw AuthException(
          code: 'update-profile-failed',
          message: errorData['message'] ?? 'Failed to update profile',
        );
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        code: 'update-profile-error',
        message: 'Failed to update profile: $e',
      );
    }
  }

  /// Update email
  Future<void> updateEmail(String newEmail) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.put(
        Uri.parse('$_baseUrl/api/users/email'),
        headers: headers,
        body: json.encode({'email': newEmail}),
      );

      if (response.statusCode == 200) {
        // Update local user data
        final userData = await getCurrentUser();
        if (userData != null) {
          userData['email'] = newEmail;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_data', json.encode(userData));
          await prefs.setString('user_email', newEmail);
        }
      } else {
        final errorData = json.decode(response.body);
        throw AuthException(
          code: 'update-email-failed',
          message: errorData['message'] ?? 'Failed to update email',
        );
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        code: 'update-email-error',
        message: 'Failed to update email: $e',
      );
    }
  }

  /// Update password
  Future<void> updatePassword(String newPassword) async {
    try {
      final headers = await _getAuthHeaders();
      final response = await http.put(
        Uri.parse('$_baseUrl/api/users/password'),
        headers: headers,
        body: json.encode({'newPassword': newPassword}),
      );

      if (response.statusCode != 200) {
        final errorData = json.decode(response.body);
        throw AuthException(
          code: 'update-password-failed',
          message: errorData['message'] ?? 'Failed to update password',
        );
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(
        code: 'update-password-error',
        message: 'Failed to update password: $e',
      );
    }
  }

  // ============================================================================
  // VALIDATION METHODS
  // ============================================================================

  /// Check if email is available for registration
  Future<bool> isEmailAvailable(String email) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/auth/validate-email?email=$email'),
        headers: _headers,
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

  /// Check if employee ID is available for customer registration
  Future<bool> isEmployeeIdAvailable(String employeeId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/auth/validate-employee-id?employeeId=$employeeId'),
        headers: _headers,
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
