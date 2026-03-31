// lib/features/admin/role_based_access/user_permission_dialog.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/app/config/navigation_config.dart';

class UserPermissionDialog extends StatefulWidget {
  final String userId;

  const UserPermissionDialog({
    super.key,
    required this.userId,
  });

  @override
  State<UserPermissionDialog> createState() => _UserPermissionDialogState();
}

class _UserPermissionDialogState extends State<UserPermissionDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _userData;
  List<NavigationItem> _navigationItems = [];
  
  // 🔥 NEW APPROACH: Use Map<String, Map<String, bool>> for complete isolation
  Map<String, Map<String, bool>> _permissionData = {};
  
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  // User detail controllers
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _navigationItems = NavigationConfig.getAllLeafItems();
    _fetchUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Get JWT auth token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) {
        throw Exception('Not authenticated');
      }
      
      debugPrint('🔍 Fetching user data for ID: ${widget.userId}');
      
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/employee-management/employees/${widget.userId}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('📡 Response status: ${response.statusCode}');
      debugPrint('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          // ✅ FIX: Handle nested 'user' object
          final userData = data['data']['user'] ?? data['data'];
          
          debugPrint('✅ User data loaded: ${userData['name_parson']}');
          debugPrint('📋 Permissions: ${userData['permissions']}');
          
          setState(() {
            _userData = userData;
            _loadUserDetails();
            _loadPermissions();
            _isLoading = false;
          });
        } else {
          throw Exception(data['message'] ?? 'Failed to load user');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error loading user: $e');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _loadUserDetails() {
    if (_userData == null) return;
    
    debugPrint('📝 Loading user details...');
    debugPrint('   name_parson: ${_userData!['name_parson']}');
    debugPrint('   name: ${_userData!['name']}');
    debugPrint('   email: ${_userData!['email']}');
    
    _nameController.text = _userData!['name_parson']?.toString() ?? '';
    _usernameController.text = _userData!['name']?.toString() ?? '';
    _emailController.text = _userData!['email']?.toString() ?? '';
    _phoneController.text = _userData!['phone']?.toString() ?? '';
    _isActive = _userData!['isActive'] ?? true;
    
    debugPrint('✅ User details loaded into controllers');
  }

  void _loadPermissions() {
    if (_userData == null) return;
    
    // Clear existing data
    _permissionData.clear();
    
    final userPermissions = _userData!['permissions'];
    
    debugPrint('🔐 Loading permissions...');
    debugPrint('   Raw permissions type: ${userPermissions.runtimeType}');
    debugPrint('   Raw permissions: $userPermissions');
    
    // Handle both Map and other types
    Map<String, dynamic> permissionsMap = {};
    
    if (userPermissions is Map) {
      permissionsMap = Map<String, dynamic>.from(userPermissions);
    } else if (userPermissions == null) {
      permissionsMap = {};
    }
    
    debugPrint('   Permissions map keys: ${permissionsMap.keys.toList()}');
    
    // Initialize ALL permissions with false by default
    for (final item in _navigationItems) {
      final permKey = item.requiredPermission;
      if (permKey != null) {
        _permissionData[permKey] = {
          'can_access': false,
          'edit_delete': false,
        };
      }
    }
    
    // Now load actual user permissions
    permissionsMap.forEach((key, value) {
      debugPrint('   Processing permission: $key = $value (${value.runtimeType})');
      
      if (value is Map) {
        final canAccess = _convertToBool(value['can_access']);
        final editDelete = _convertToBool(value['edit_delete']);
        
        _permissionData[key] = {
          'can_access': canAccess,
          'edit_delete': editDelete,
        };
        
        debugPrint('     ✅ Set $key: access=$canAccess, edit=$editDelete');
      }
    });
    
    debugPrint('✅ Total permissions loaded: ${_permissionData.length}');
    _permissionData.forEach((key, value) {
      debugPrint('   $key: ${value['can_access']}/${value['edit_delete']}');
    });
  }
  
  // Helper method to convert various types to boolean
  bool _convertToBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    return false;
  }

  // 🔥 COMPLETELY NEW: Direct update without setState cascade
  void _updatePermissionValue(String permKey, String field, bool value) {
    debugPrint('🔄 Update: $permKey.$field = $value');
    
    if (!_permissionData.containsKey(permKey)) {
      _permissionData[permKey] = {'can_access': false, 'edit_delete': false};
    }
    
    _permissionData[permKey]![field] = value;
    
    debugPrint('   ✅ Updated: ${_permissionData[permKey]}');
    
    // Force rebuild
    setState(() {});
  }

  Future<void> _saveUserDetails() async {
    setState(() => _isSaving = true);

    try {
      // Get JWT token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) {
        throw Exception('Not authenticated');
      }
      
      debugPrint('💾 Saving user details...');
      debugPrint('   name_parson: ${_nameController.text}');
      debugPrint('   name: ${_usernameController.text}');
      debugPrint('   email: ${_emailController.text}');
      
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/employee-management/employees/${widget.userId}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'name_parson': _nameController.text.trim(),
          'name': _usernameController.text.trim(),
          'email': _emailController.text.trim(),
          'phone': _phoneController.text.trim(),
          'isActive': _isActive,
        }),
      );

      debugPrint('📡 Save response: ${response.statusCode}');
      debugPrint('📡 Save body: ${response.body}');

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ User details updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _fetchUserData(); // Refresh data
      } else {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? 'Failed to update user');
      }
    } catch (e) {
      debugPrint('❌ Save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _savePermissions() async {
    setState(() => _isSaving = true);

    try {
      // Get JWT token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null || token.isEmpty) {
        throw Exception('Not authenticated');
      }
      
      debugPrint('🔐 Saving permissions...');
      debugPrint('   Total permissions: ${_permissionData.length}');
      
      _permissionData.forEach((key, value) {
        debugPrint('   $key: ${value['can_access']}/${value['edit_delete']}');
      });
      
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/api/employee-management/employees/${widget.userId}/permissions'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'permissions': _permissionData,
        }),
      );

      debugPrint('📡 Permission save response: ${response.statusCode}');
      debugPrint('📡 Permission save body: ${response.body}');

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Permissions updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        final data = json.decode(response.body);
        throw Exception(data['message'] ?? 'Failed to update permissions');
      }
    } catch (e) {
      debugPrint('❌ Permission save error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.settings, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'User Management',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        if (_userData != null)
                          Text(
                            _userData!['name_parson']?.toString() ?? 'Unknown User',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF64748B),
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            // Tabs
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Colors.grey[200]!),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF6366F1),
                unselectedLabelColor: Colors.grey,
                indicatorColor: const Color(0xFF6366F1),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.person),
                    text: 'User Details',
                  ),
                  Tab(
                    icon: Icon(Icons.security),
                    text: 'Permissions',
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(_errorMessage!),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _fetchUserData,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildUserDetailsTab(),
                            _buildPermissionsTab(),
                          ],
                        ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSaving
                          ? null
                          : () {
                              if (_tabController.index == 0) {
                                _saveUserDetails();
                              } else {
                                _savePermissions();
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(_tabController.index == 0
                              ? 'Save Details'
                              : 'Save Permissions'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Account Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _isActive
                  ? const Color(0xFF10B981).withOpacity(0.1)
                  : const Color(0xFFEF4444).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isActive
                    ? const Color(0xFF10B981).withOpacity(0.3)
                    : const Color(0xFFEF4444).withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isActive ? Icons.check_circle : Icons.cancel,
                  color: _isActive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Account Status',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        _isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _isActive
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isActive,
                  onChanged: (value) {
                    setState(() {
                      _isActive = value;
                    });
                  },
                  activeColor: const Color(0xFF10B981),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // User Information
          const Text(
            'User Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),

          // Full Name
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Full Name',
              hintText: 'Enter full name',
              prefixIcon: const Icon(Icons.person),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Username
          TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: 'Username',
              hintText: 'Enter username',
              prefixIcon: const Icon(Icons.account_circle),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Email
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email',
              hintText: 'user@example.com',
              prefixIcon: const Icon(Icons.email),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Phone
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Phone',
              hintText: 'Enter phone number',
              prefixIcon: const Icon(Icons.phone),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsTab() {
    // Group navigation items by category
    final itemsByCategory = <String, List<NavigationItem>>{};
    for (final item in _navigationItems) {
      final category = item.category ?? 'Other';
      itemsByCategory.putIfAbsent(category, () => []).add(item);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bulk Actions
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    for (final key in _permissionData.keys) {
                      _permissionData[key] = {
                        'can_access': true,
                        'edit_delete': true,
                      };
                    }
                  });
                },
                icon: const Icon(Icons.check_circle, size: 18),
                label: const Text('Select All'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    for (final key in _permissionData.keys) {
                      _permissionData[key] = {
                        'can_access': false,
                        'edit_delete': false,
                      };
                    }
                  });
                },
                icon: const Icon(Icons.cancel, size: 18),
                label: const Text('Deselect All'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Permission Categories
          ...itemsByCategory.entries.map((entry) {
            return _buildCategorySection(entry.key, entry.value);
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildCategorySection(String category, List<NavigationItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category Header
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF6366F1).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                _getCategoryIcon(category),
                size: 20,
                color: const Color(0xFF6366F1),
              ),
              const SizedBox(width: 8),
              Text(
                category,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6366F1),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Permission Items
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey[200]!),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: items.map((item) => _buildPermissionRow(item)).toList(),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildPermissionRow(NavigationItem item) {
    final permKey = item.requiredPermission;
    if (permKey == null) return const SizedBox();

    // Initialize if doesn't exist
    if (!_permissionData.containsKey(permKey)) {
      _permissionData[permKey] = {
        'can_access': false,
        'edit_delete': false,
      };
    }
    
    final canAccess = _permissionData[permKey]!['can_access'] ?? false;
    final editDelete = _permissionData[permKey]!['edit_delete'] ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!),
        ),
      ),
      child: Row(
        children: [
          // Permission Name
          Expanded(
            flex: 3,
            child: Row(
              children: [
                if (item.parent != null)
                  const Padding(
                    padding: EdgeInsets.only(left: 24),
                    child: Icon(Icons.subdirectory_arrow_right, size: 16),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Access Checkbox
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Access', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                Checkbox(
                  value: canAccess,
                  onChanged: (value) {
                    _updatePermissionValue(permKey, 'can_access', value ?? false);
                  },
                  activeColor: const Color(0xFF10B981),
                ),
              ],
            ),
          ),
          
          // Edit/Delete Checkbox
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Edit/Delete', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                Checkbox(
                  value: editDelete,
                  onChanged: (value) {
                    _updatePermissionValue(permKey, 'edit_delete', value ?? false);
                  },
                  activeColor: const Color(0xFF10B981),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'core':
        return Icons.dashboard;
      case 'fleet':
        return Icons.directions_car;
      case 'customers':
        return Icons.people;
      case 'clients':
        return Icons.business;
      case 'reports':
        return Icons.analytics;
      case 'emergency':
        return Icons.sos;
      case 'hrm':
        return Icons.work;
      case 'feedback':
        return Icons.feedback;
      case 'administration':
        return Icons.admin_panel_settings;
      case 'support':
        return Icons.support_agent;
      default:
        return Icons.folder;
    }
  }
}