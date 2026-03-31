// lib/core/services/erp_users_management_service.dart
// ============================================================================
// 🔌 ERP USERS MANAGEMENT SERVICE - API Communication Layer
// ============================================================================
// Connects Flutter frontend to Node.js backend using SafeApiService
// ============================================================================

import 'package:abra_fleet/core/services/safe_api_service.dart';

class ERPUsersManagementService {
  final SafeApiService _api = SafeApiService();

  // ========================================================================
  // 📦 FETCH ALL ERP USERS
  // ========================================================================
  Future<Map<String, dynamic>> fetchAllUsers() async {
    return await _api.safeGet(
      '/api/erp-users',
      context: 'Fetch All ERP Users',
      fallback: {'success': false, 'data': []},
    );
  }

  // ========================================================================
  // 🔍 FETCH SINGLE USER
  // ========================================================================
  Future<Map<String, dynamic>> fetchUser(String userId) async {
    return await _api.safeGet(
      '/api/erp-users/$userId',
      context: 'Fetch ERP User',
      fallback: {'success': false, 'data': null},
    );
  }

  // ========================================================================
  // ➕ CREATE NEW USER
  // ========================================================================
  Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    return await _api.safePost(
      '/api/erp-users',
      body: userData,
      context: 'Create ERP User',
      fallback: {'success': false, 'message': 'Failed to create user'},
    );
  }

  // ========================================================================
  // ✏️ UPDATE USER
  // ========================================================================
  Future<Map<String, dynamic>> updateUser(
    String userId,
    Map<String, dynamic> userData,
  ) async {
    return await _api.safePut(
      '/api/erp-users/$userId',
      body: userData,
      context: 'Update ERP User',
      fallback: {'success': false, 'message': 'Failed to update user'},
    );
  }

  // ========================================================================
  // 🗑️ DELETE USER
  // ========================================================================
  Future<Map<String, dynamic>> deleteUser(String userId) async {
    return await _api.safeDelete(
      '/api/erp-users/$userId',
      context: 'Delete ERP User',
      fallback: {'success': false, 'message': 'Failed to delete user'},
    );
  }

  // ========================================================================
  // 🔐 FETCH USER PERMISSIONS
  // ========================================================================
  Future<Map<String, dynamic>> fetchPermissions(String userId) async {
    return await _api.safeGet(
      '/api/erp-users/$userId/permissions',
      context: 'Fetch User Permissions',
      fallback: {'success': false, 'data': {}},
    );
  }

  // ========================================================================
  // 💾 SAVE USER PERMISSIONS
  // ========================================================================
  Future<Map<String, dynamic>> savePermissions(
    String userId,
    Map<String, dynamic> permissions,
  ) async {
    return await _api.safePost(
      '/api/erp-users/$userId/permissions',
      body: {'permissions': permissions},
      context: 'Save User Permissions',
      fallback: {'success': false, 'message': 'Failed to save permissions'},
    );
  }

  // ========================================================================
  // 🔄 BATCH OPERATIONS (Optional - for bulk updates)
  // ========================================================================
  
  /// Update multiple users' status at once
  Future<Map<String, dynamic>> updateUsersStatus(
    List<String> userIds,
    String status,
  ) async {
    final results = <String, bool>{};
    
    for (final userId in userIds) {
      final response = await updateUser(userId, {'status': status});
      results[userId] = response['success'] == true;
    }
    
    return {
      'success': results.values.every((success) => success),
      'results': results,
    };
  }

  /// Delete multiple users at once
  Future<Map<String, dynamic>> deleteUsers(List<String> userIds) async {
    final results = <String, bool>{};
    
    for (final userId in userIds) {
      final response = await deleteUser(userId);
      results[userId] = response['success'] == true;
    }
    
    return {
      'success': results.values.every((success) => success),
      'results': results,
    };
  }
}