// lib/features/auth/data/repositories/jwt_auth_repository_impl.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:abra_fleet/features/auth/domain/entities/user_entity.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'package:abra_fleet/core/utils/role_mapper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JwtAuthRepositoryImpl implements AuthRepository {
  final ApiService _apiService;
  
  // Cache variables - Prevent redundant API calls
  UserEntity? _cachedUser;
  DateTime? _lastFetch;
  String? _lastToken;
  
  // JWT token storage key
  static const String _tokenKey = 'jwt_token';
  static const String _userDataKey = 'user_data';

  JwtAuthRepositoryImpl({
    ApiService? apiService,
  }) : _apiService = apiService ?? ApiService();

  @override
  Stream<UserEntity> get user {
    return Stream.periodic(const Duration(seconds: 1))
        .asyncMap((_) async {
      // ✅ FIXED: Removed duplicate declarations
      final token = await _getStoredToken();
      
      if (token == null || token.isEmpty) {
        _clearCache();
        return UserEntity.empty;
      }
      
      // Return cached user if token hasn't changed and cache is fresh
      if (_cachedUser != null && 
          _lastToken == token && 
          _lastFetch != null &&
          DateTime.now().difference(_lastFetch!) < const Duration(minutes: 5)) {
        return _cachedUser!;
      }
      
      try {
        // Verify token and get user info
        final response = await _apiService.get('/api/auth/me');
        
        if (response['success'] == true && response['data'] != null) {
          final userData = response['data']['user'];
          
          final userEntity = UserEntity(
            id: userData['userId']?.toString() ?? '',
            firebaseUid: userData['userId']?.toString() ?? '', // Use userId as firebaseUid for compatibility
            email: userData['email']?.toString() ?? '',
            name: userData['name']?.toString() ?? '',
            role: RoleMapper.normalizeRole(userData['role']?.toString()),
            phoneNumber: userData['phone']?.toString(),
            photoUrl: userData['photoUrl']?.toString(),
          );
          
          // Cache the result
          _cachedUser = userEntity;
          _lastFetch = DateTime.now();
          _lastToken = token;
          
          // Store user data locally
          await _storeUserData(userEntity);
          
          return userEntity;
        } else {
          // Token is invalid, clear it
          await _clearStoredToken();
          _clearCache();
          return UserEntity.empty;
        }
      } catch (e) {
        print('[JwtAuth] Error verifying token: $e');
        
        // Try to return cached user if available
        if (_cachedUser != null) {
          return _cachedUser!;
        }
        
        // Try to return stored user data
        final storedUser = await _getStoredUserData();
        if (storedUser != null) {
          return storedUser;
        }
        
        return UserEntity.empty;
      }
    }).distinct((prev, next) => prev.id == next.id && prev.role == next.role);
  }

  @override
  UserEntity get currentUser {
    return _cachedUser ?? UserEntity.empty;
  }

  @override
  Future<UserEntity> getCurrentUserWithRole() async {
    final token = await _getStoredToken();
    if (token == null) return UserEntity.empty;

    try {
      print('[JwtAuth] 🔍 Getting current user with role...');
      print('[JwtAuth] Token available: ${token.isNotEmpty}');
      
      // ✅ CRITICAL FIX: Force API service to use the latest token
      _apiService.setAuthToken(token);
      
      final response = await _apiService.get('/api/auth/me');
      
      if (response['success'] == true && response['data'] != null) {
        final userData = response['data']['user'];
        
        final userEntity = UserEntity(
          id: userData['userId']?.toString() ?? '',
          firebaseUid: userData['userId']?.toString() ?? '',
          email: userData['email']?.toString() ?? '',
          name: userData['name']?.toString() ?? '',
          role: RoleMapper.normalizeRole(userData['role']?.toString()),
          phoneNumber: userData['phone']?.toString(),
          photoUrl: userData['photoUrl']?.toString(),
        );
        
        print('[JwtAuth] ✅ User retrieved successfully');
        print('[JwtAuth] User ID: ${userEntity.id}');
        print('[JwtAuth] Role: ${userEntity.role}');
        
        return userEntity;
      }
    } catch (e) {
      print('[JwtAuth] Error getting current user: $e');
    }
    
    return UserEntity.empty;
  }

  @override
  Future<void> signUp({
    required String email,
    required String password,
    String? name,
    required String role,
    String? phoneNumber,
  }) async {
    try {
      print('[JwtAuth] Registering user: $email with role: $role');
      
      // Use API service instead of direct HTTP call
      final response = await _apiService.post('/api/auth/register', body: {
        'email': email,
        'password': password,
        'name': name ?? email.split('@')[0],
        'role': role,
        'phoneNumber': phoneNumber,
      });
      
      if (response['success'] == true && response['data'] != null) {
        // Store the JWT token
        final token = response['data']['token'];
        await _storeToken(token);
        
        // Create and cache user entity
        final userData = response['data']['user'];
        final userEntity = UserEntity(
          id: userData['id']?.toString() ?? '',
          firebaseUid: userData['id']?.toString() ?? '',
          email: userData['email']?.toString() ?? '',
          name: userData['name']?.toString() ?? '',
          role: RoleMapper.normalizeRole(userData['role']?.toString()),
          phoneNumber: userData['phoneNumber']?.toString(),
        );
        
        _cachedUser = userEntity;
        _lastFetch = DateTime.now();
        _lastToken = token;
        
        await _storeUserData(userEntity);
        
        print('[JwtAuth] Registration successful');
      } else {
        throw Exception(response['message'] ?? 'Registration failed');
      }
    } catch (e) {
      print('[JwtAuth] Registration error: $e');
      rethrow;
    }
  }

  @override
Future<String?> signInWithEmailAndPassword({
  required String email,
  required String password,
}) async {
  try {
    print('[JwtAuth] ========================================');
    print('[JwtAuth] STARTING JWT SIGN IN PROCESS');
    print('[JwtAuth] ========================================');
    print('[JwtAuth] Email: $email');
    print('[JwtAuth] API Base URL: ${_apiService.baseUrl}');
    
    // Clear any existing cache
    _clearCache();
    await _clearStoredToken();
    
    // ✅ CRITICAL FIX: Clear API service token cache too!
    _apiService.clearTokenCache();
    print('[JwtAuth] ✅ Cleared all token caches (auth repo + API service)');
    
    print('[JwtAuth] 📡 Calling API service POST /api/auth/login...');
    
    // Use API service instead of direct HTTP call
    Map<String, dynamic> response;
    try {
      response = await _apiService.post('/api/auth/login', body: {
        'email': email,
        'password': password,
      });
      print('[JwtAuth] ✅ API call completed successfully');
    } catch (apiError) {
      print('[JwtAuth] ❌ API CALL FAILED');
      print('[JwtAuth] Error type: ${apiError.runtimeType}');
      print('[JwtAuth] Error message: $apiError');
      rethrow;
    }

    // 🔍 ADD THIS LINE:
print('[JwtAuth] RAW API RESPONSE: $response');
print('[JwtAuth] Response keys: ${response.keys.toList()}');
print('[JwtAuth] Response[data]: ${response['data']}');
    
    // 🔍 CRITICAL DEBUG LOGGING - ADD THESE LINES
    print('[JwtAuth] ═══════════════════════════════════════════════════════');
    print('[JwtAuth] 📥 FULL RESPONSE ANALYSIS');
    print('[JwtAuth] ═══════════════════════════════════════════════════════');
    print('[JwtAuth] Response type: ${response.runtimeType}');
    print('[JwtAuth] Response is Map: ${response is Map}');
    print('[JwtAuth] Response keys: ${response.keys.toList()}');
    print('[JwtAuth] Response as JSON string:');
    print(jsonEncode(response));
    print('[JwtAuth] ───────────────────────────────────────────────────────');
    print('[JwtAuth] Response["success"]: ${response['success']}');
    print('[JwtAuth] Response["success"] type: ${response['success'].runtimeType}');
    print('[JwtAuth] Response["data"]: ${response['data']}');
    print('[JwtAuth] Response["data"] type: ${response['data']?.runtimeType}');
    
    if (response['data'] != null) {
      print('[JwtAuth] ───────────────────────────────────────────────────────');
      print('[JwtAuth] DATA OBJECT ANALYSIS:');
      if (response['data'] is Map) {
        final dataMap = response['data'] as Map;
        print('[JwtAuth] Data keys: ${dataMap.keys.toList()}');
        print('[JwtAuth] Data["token"]: ${dataMap['token']}');
        print('[JwtAuth] Data["token"] type: ${dataMap['token']?.runtimeType}');
        print('[JwtAuth] Data["token"] is null: ${dataMap['token'] == null}');
        print('[JwtAuth] Data["token"] is empty: ${dataMap['token']?.toString().isEmpty ?? true}');
        
        if (dataMap['token'] != null) {
          print('[JwtAuth] Token length: ${dataMap['token'].toString().length}');
          print('[JwtAuth] Token preview: ${dataMap['token'].toString().substring(0, 20)}...');
        }
      } else {
        print('[JwtAuth] ⚠️ WARNING: data is NOT a Map! Type: ${response['data'].runtimeType}');
      }
    } else {
      print('[JwtAuth] ⚠️ WARNING: data is NULL!');
    }
    print('[JwtAuth] ═══════════════════════════════════════════════════════');
    
    if (response['success'] == true && response['data'] != null) {
      print('[JwtAuth] ✅ Response indicates success');
      
      // ✅ EXPLICIT TYPE CHECKING AND SAFE EXTRACTION
      final data = response['data'];
      
      // Verify data is a Map
      if (data is! Map) {
        print('[JwtAuth] ❌ CRITICAL: data is not a Map! Type: ${data.runtimeType}');
        print('[JwtAuth] Full response: $response');
        throw Exception('Invalid response structure: data is not a Map');
      }
      
      // Cast to Map and extract token
      final dataMap = Map<String, dynamic>.from(data as Map);
      final tokenValue = dataMap['token'];
      
      print('[JwtAuth] Token from response: ${tokenValue != null ? "Present" : "NULL"}');
      print('[JwtAuth] Token type: ${tokenValue?.runtimeType}');
      
      if (tokenValue == null) {
        print('[JwtAuth] ❌ CRITICAL: Token is null!');
        print('[JwtAuth] Available keys in data: ${dataMap.keys.toList()}');
        print('[JwtAuth] Full data object: $dataMap');
        throw Exception('No token in response data');
      }
      
      // Convert to string if needed
      final token = tokenValue.toString();
      
      if (token.isEmpty) {
        print('[JwtAuth] ❌ CRITICAL: Token is empty!');
        throw Exception('Token is empty');
      }
      
      print('[JwtAuth] Token length: ${token.length} chars');
      
      await _storeToken(token);
      print('[JwtAuth] ✅ Token stored successfully');
      
      // ✅ CRITICAL FIX: Set the token in API service cache immediately
      _apiService.setAuthToken(token);
      print('[JwtAuth] ✅ Token set in API service cache');
      
      // Create and cache user entity
      final userData = response['data']['user'];
      print('[JwtAuth] User data from response: $userData');
      
      final userEntity = UserEntity(
        id: userData['id']?.toString() ?? '',
        firebaseUid: userData['id']?.toString() ?? '',
        email: userData['email']?.toString() ?? '',
        name: userData['name']?.toString() ?? '',
        role: RoleMapper.normalizeRole(userData['role']?.toString()),
        phoneNumber: userData['phone']?.toString(),
      );
      
      _cachedUser = userEntity;
      _lastFetch = DateTime.now();
      _lastToken = token;
      
      await _storeUserData(userEntity);
      
      print('[JwtAuth] ✅ JWT Login successful');
      print('[JwtAuth] User ID: ${userEntity.id}');
      print('[JwtAuth] Role: ${userEntity.role}');
      
      // ✅ CRITICAL FIX: Verify token works by calling /api/auth/me
      print('[JwtAuth] 🔍 Verifying token with /api/auth/me...');
      try {
        final meResponse = await _apiService.get('/api/auth/me');
        if (meResponse['success'] == true) {
          print('[JwtAuth] ✅ Token verification successful');
        } else {
          print('[JwtAuth] ⚠️ Token verification returned success=false');
        }
      } catch (verifyError) {
        print('[JwtAuth] ❌ Token verification failed: $verifyError');
        // Don't throw - login was successful, this is just verification
      }
      
      print('[JwtAuth] ========================================');
      
      return token;
    } else {
      final errorMessage = response['message'] ?? 'Login failed';
      print('[JwtAuth] ❌ Login failed: $errorMessage');
      print('[JwtAuth] Full response: $response');
      throw Exception(errorMessage);
    }
  } catch (e) {
    print('[JwtAuth] ❌ Login error: $e');
    print('[JwtAuth] Error type: ${e.runtimeType}');
    rethrow;
  }
}

  @override
  Future<String?> getAuthToken() async {
    try {
      final token = await _getStoredToken();
      if (token != null && token.isNotEmpty) {
        // Verify token is still valid using API service
        try {
          final response = await _apiService.get('/api/auth/me');
          
          if (response['success'] == true) {
            print('[JwtAuth] ✅ Token is valid');
            return token;
          } else {
            print('[JwtAuth] ⚠️ Token is invalid, clearing');
            await _clearStoredToken();
            return null;
          }
        } catch (e) {
          print('[JwtAuth] Error verifying token: $e');
          return token; // Return token anyway, let the API handle it
        }
      } else {
        print('[JwtAuth] No token found');
        return null;
      }
    } catch (e) {
      print('[JwtAuth] Error getting auth token: $e');
      return null;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      // Clear stored token and user data
      await _clearStoredToken();
      await _clearStoredUserData();
      _clearCache();
      
      print('[JwtAuth] User signed out successfully');
    } catch (e) {
      print('[JwtAuth] Error during sign out: $e');
      rethrow;
    }
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      final response = await _apiService.post('/api/auth/forgot-password', body: {
        'email': email,
      });
      
      if (response['success'] != true) {
        throw Exception(response['message'] ?? 'Failed to send password reset email');
      }
      
      print('[JwtAuth] Password reset email sent to: $email');
    } catch (e) {
      print('[JwtAuth] Error sending password reset email: $e');
      rethrow;
    }
  }

  @override
  Future<void> refreshCurrentUser() async {
    print('[JwtAuth] 🔄 Refreshing current user data...');
    
    // Clear cache to force fresh fetch
    _clearCache();
    
    // Trigger user stream update
    await Future.delayed(const Duration(milliseconds: 100));
    
    print('[JwtAuth] ✅ Current user data refresh triggered');
  }

  @override
  void dispose() {
    _clearCache();
  }

  @override
  Future<bool> updateUserProfile({
    required String userId,
    String? name,
    String? phoneNumber,
  }) async {
    try {
      print('[JwtAuth] Updating profile for user: $userId');
      
      final response = await _apiService.put('/api/auth/profile', body: {
        'name': name,
        'phoneNumber': phoneNumber,
      });
      
      if (response['success'] == true) {
        print('[JwtAuth] Profile updated successfully');
        
        // Clear cache to force refresh
        _clearCache();
        
        return true;
      } else {
        print('[JwtAuth] Profile update failed: ${response['message']}');
        return false;
      }
    } catch (e) {
      print('[JwtAuth] Error updating user profile: $e');
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      print('[JwtAuth] Fetching profile for user: $userId');
      
      final response = await _apiService.get('/api/auth/me');
      
      if (response['success'] == true && response['data'] != null) {
        return response['data']['user'];
      } else {
        print('[JwtAuth] User profile not found');
        return null;
      }
    } catch (e) {
      print('[JwtAuth] Error fetching user profile: $e');
      return null;
    }
  }

  // Private helper methods
  Future<String?> _getStoredToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    } catch (e) {
      print('[JwtAuth] Error getting stored token: $e');
      return null;
    }
  }

  Future<void> _storeToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
    } catch (e) {
      print('[JwtAuth] Error storing token: $e');
    }
  }

  Future<void> _clearStoredToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
    } catch (e) {
      print('[JwtAuth] Error clearing stored token: $e');
    }
  }

  Future<void> _storeUserData(UserEntity user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = {
        'id': user.id,
        'firebaseUid': user.firebaseUid,
        'email': user.email,
        'name': user.name,
        'role': user.role,
        'phoneNumber': user.phoneNumber,
        'photoUrl': user.photoUrl,
      };
      await prefs.setString(_userDataKey, jsonEncode(userData));
      
      // ✅ CRITICAL FIX: Store individual keys for OneSignalService and other services
      await prefs.setString('user_id', user.id);
      await prefs.setString('user_role', user.role ?? 'customer');
      await prefs.setString('user_email', user.email ?? '');
      await prefs.setString('user_name', user.name ?? '');
      
      print('[JwtAuth] ✅ User data stored in SharedPreferences');
      print('[JwtAuth]    user_id: ${user.id}');
      print('[JwtAuth]    user_role: ${user.role}');
      print('[JwtAuth]    user_email: ${user.email}');
      print('[JwtAuth]    user_name: ${user.name}');
    } catch (e) {
      print('[JwtAuth] Error storing user data: $e');
    }
  }

  Future<UserEntity?> _getStoredUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataString = prefs.getString(_userDataKey);
      
      if (userDataString != null) {
        final userData = jsonDecode(userDataString);
        return UserEntity(
          id: userData['id'] ?? '',
          firebaseUid: userData['firebaseUid'] ?? '',
          email: userData['email'] ?? '',
          name: userData['name'] ?? '',
          role: userData['role'] ?? 'customer',
          phoneNumber: userData['phoneNumber'],
          photoUrl: userData['photoUrl'],
        );
      }
    } catch (e) {
      print('[JwtAuth] Error getting stored user data: $e');
    }
    return null;
  }

  Future<void> _clearStoredUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userDataKey);
      
      // ✅ CRITICAL FIX: Also clear individual keys
      await prefs.remove('user_id');
      await prefs.remove('user_role');
      await prefs.remove('user_email');
      await prefs.remove('user_name');
      
      print('[JwtAuth] ✅ All user data cleared from SharedPreferences');
    } catch (e) {
      print('[JwtAuth] Error clearing stored user data: $e');
    }
  }

  void _clearCache() {
    _cachedUser = null;
    _lastFetch = null;
    _lastToken = null;
  }
}