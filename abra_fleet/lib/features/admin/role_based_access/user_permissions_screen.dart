// lib/features/admin/role_based_access/user_permissions_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/app/config/navigation_config.dart';

/// ============================================================================
/// USER PERMISSIONS SCREEN (Like PHP permissions.php)
/// ============================================================================
/// Shows permission checkboxes for a specific user
/// Receives user info from user_management_screen.dart
/// ============================================================================

class UserPermissionsScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String userEmail;
  final String userRole;

  const UserPermissionsScreen({
    Key? key,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.userRole,
  }) : super(key: key);

  @override
  State<UserPermissionsScreen> createState() => _UserPermissionsScreenState();
}

class _UserPermissionsScreenState extends State<UserPermissionsScreen> {
  // API configuration
  String get apiUrl => '${ApiConfig.baseUrl}/api';

  // State variables
  Map<String, Map<String, bool>> permissions = {};
  bool isLoading = false;
  bool isSaving = false;
  String? authToken;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    try {
      // Get JWT auth token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      setState(() {
        authToken = token;
      });
      
      if (token != null && token.isNotEmpty) {
        fetchUserPermissions();
      }
    } catch (e) {
      debugPrint('Error initializing auth: $e');
      _showSnackBar('Authentication error: $e', isError: true);
    }
  }

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

  Future<void> fetchUserPermissions() async {
    setState(() => isLoading = true);
    try {
      debugPrint('📥 Fetching permissions for user: ${widget.userId}');

      final response = await http.get(
        Uri.parse('$apiUrl/user-management/permissions/${widget.userId}'),
        headers: headers,
      );

      debugPrint('📥 Permissions response: ${response.statusCode}');
      debugPrint('📥 Permissions body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);

        if (jsonData['success'] == true && jsonData['data'] != null) {
          final permData = jsonData['data']['permissions'] ?? {};

          // Initialize permissions map
          final Map<String, Map<String, bool>> newPermissions = {};

          // Get all navigation keys from config
          final allKeys = NavigationConfig.getAllKeys();

          for (final key in allKeys) {
            newPermissions[key] = {
              'can_access': permData[key]?['can_access'] == true ||
                  permData[key]?['canAccess'] == true ||
                  permData[key] == true,
              'edit_delete': permData[key]?['edit_delete'] == true ||
                  permData[key]?['editDelete'] == true,
            };
          }

          setState(() {
            permissions = newPermissions;
            isLoading = false;
          });

          debugPrint('✅ Loaded permissions for user ${widget.userId}');
        } else {
          // No permissions found, initialize with defaults
          _initializeDefaultPermissions();
        }
      } else if (response.statusCode == 404) {
        // User has no permissions yet, initialize with defaults
        _initializeDefaultPermissions();
      } else {
        throw Exception('Failed to load permissions: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint('Error fetching permissions: $e');
      _initializeDefaultPermissions();
    }
  }

  void _initializeDefaultPermissions() {
    final Map<String, Map<String, bool>> newPermissions = {};
    final allKeys = NavigationConfig.getAllKeys();

    for (final key in allKeys) {
      newPermissions[key] = {
        'can_access': false,
        'edit_delete': false,
      };
    }

    setState(() {
      permissions = newPermissions;
      isLoading = false;
    });
  }

  Future<void> savePermissions() async {
    setState(() => isSaving = true);

    try {
      debugPrint('💾 Saving permissions for user: ${widget.userId}');

      final response = await http.put(
        Uri.parse('$apiUrl/user-management/permissions/${widget.userId}'),
        headers: headers,
        body: json.encode({
          'permissions': permissions,
        }),
      );

      debugPrint('📤 Save response: ${response.statusCode}');
      debugPrint('📤 Save body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        _showSnackBar(jsonData['message'] ?? 'Permissions updated successfully!');
      } else {
        final jsonData = json.decode(response.body);
        _showSnackBar(jsonData['error'] ?? 'Failed to update permissions', isError: true);
      }
    } catch (e) {
      debugPrint('❌ Error saving permissions: $e');
      _showSnackBar('Error saving permissions: $e', isError: true);
    } finally {
      setState(() => isSaving = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFE74C3C) : const Color(0xFF27AE60),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _getRoleColor(String? role) {
    switch (role?.toLowerCase()) {
      case 'super_admin':
      case 'superadmin':
        return const Color(0xFFE74C3C); // Red
      case 'admin':
        return const Color(0xFFE67E22); // Orange
      case 'fleet_manager':
        return const Color(0xFF3498DB); // Blue
      case 'hr_manager':
        return const Color(0xFF27AE60); // Green
      case 'finance':
        return const Color(0xFF9B59B6); // Purple
      default:
        return const Color(0xFF95A5A6); // Gray
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Manage Permissions',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF2C3E50),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          _buildUserInfoHeader(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildPermissionsTable(),
          ),
          _buildSaveButton(),
        ],
      ),
    );
  }

  Widget _buildUserInfoHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: _getRoleColor(widget.userRole),
            child: Text(
              widget.userName[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Permissions for ${widget.userName}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.userEmail,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getRoleColor(widget.userRole),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.userRole,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsTable() {
    // Get all parent items from navigation config
    final parentItems = NavigationConfig.getParentItems();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
            ),
          ],
        ),
        child: Table(
          border: TableBorder.all(color: Colors.grey[300]!, width: 1),
          columnWidths: const {
            0: FlexColumnWidth(3),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
          },
          children: [
            // Table header
            TableRow(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2C3E50), Color(0xFF34495E)],
                ),
              ),
              children: [
                _buildTableHeaderCell('Section Name'),
                _buildTableHeaderCell('Access'),
                _buildTableHeaderCell('Edit/Delete'),
              ],
            ),
            // Table rows
            ...parentItems.expand((parent) {
              List<TableRow> rows = [];

              // If parent has children, show parent as category header
              if (parent.hasChildren) {
                // Category header
                rows.add(
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey[100]),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            if (parent.icon != null)
                              Icon(parent.icon, size: 20, color: const Color(0xFF3498DB)),
                            if (parent.icon != null) const SizedBox(width: 8),
                            Text(
                              parent.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(),
                      Container(),
                    ],
                  ),
                );

                // Children rows
                final children = NavigationConfig.getChildrenOf(parent.key);
                for (final child in children) {
                  rows.add(_buildPermissionRow(child, isChild: true));
                }
              } else {
                // Single item without children
                rows.add(_buildPermissionRow(parent));
              }

              return rows;
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  TableRow _buildPermissionRow(NavigationItem item, {bool isChild = false}) {
    final permissionData = permissions[item.key] ?? {'can_access': false, 'edit_delete': false};

    return TableRow(
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: isChild ? 32 : 12,
            top: 12,
            bottom: 12,
            right: 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: TextStyle(
                  fontWeight: isChild ? FontWeight.normal : FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              if (item.description != null) ...[
                const SizedBox(height: 4),
                Text(
                  item.description!,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ],
          ),
        ),
        Center(
          child: Checkbox(
            value: permissionData['can_access'] ?? false,
            onChanged: (value) {
              setState(() {
                permissions[item.key] = {
                  'can_access': value ?? false,
                  'edit_delete': permissionData['edit_delete'] ?? false,
                };
              });
            },
            activeColor: const Color(0xFF3498DB), // Blue
          ),
        ),
        Center(
          child: Checkbox(
            value: permissionData['edit_delete'] ?? false,
            onChanged: (value) {
              setState(() {
                permissions[item.key] = {
                  'can_access': permissionData['can_access'] ?? false,
                  'edit_delete': value ?? false,
                };
              });
            },
            activeColor: const Color(0xFF9B59B6), // Purple
          ),
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ElevatedButton.icon(
            onPressed: isSaving ? null : savePermissions,
            icon: isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(isSaving ? 'Saving...' : 'Update Permissions'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60), // Green
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}