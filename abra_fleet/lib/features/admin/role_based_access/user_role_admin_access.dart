// lib/features/admin/role_based_access/user_management_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:abra_fleet/features/admin/role_based_access/user_permissions_screen.dart';

/// ============================================================================
/// USER MANAGEMENT SCREEN (Like PHP users.php)
/// ============================================================================
/// Shows all users in a table with Add, Edit, Delete, and Permissions buttons
/// ============================================================================

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({Key? key}) : super(key: key);

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  // API configuration
  String get apiUrl => '${ApiConfig.baseUrl}/api';

  // State variables
  List<dynamic> users = [];
  bool isLoading = false;
  String searchQuery = '';
  String? authToken;
  bool isAuthenticated = false;
  bool hasAccess = false;
  String? currentUserRole;

  // Define which roles can access this screen
  static const List<String> allowedRoles = [
    'super_admin',
    'superadmin',
    'admin',
    'org_admin',
    'organization_admin',
  ];

  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    try {
      // Get JWT auth token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      debugPrint('🔐 UserManagementScreen - Checking JWT token');

      if (token != null && token.isNotEmpty) {
        debugPrint('🔐 UserManagementScreen - Got JWT token');

        final authRepository = Provider.of<AuthRepository>(context, listen: false);
        final userStream = authRepository.user;

        userStream.listen((userEntity) {
          if (userEntity != null && userEntity.isAuthenticated) {
            final userRole = userEntity.role?.toLowerCase().trim().replaceAll(' ', '_') ?? '';
            debugPrint('🔐 UserManagementScreen - Current user role: "$userRole"');

            setState(() {
              currentUserRole = userRole;
              hasAccess = _checkRoleAccess(userRole);
              authToken = token;
              isAuthenticated = true;
            });

            if (hasAccess) {
              debugPrint('✅ UserManagementScreen - Access granted for role: $userRole');
              fetchUsers();
            } else {
              debugPrint('❌ UserManagementScreen - Access denied for role: $userRole');
            }
          }
        });
      } else {
        setState(() {
          isAuthenticated = false;
          hasAccess = false;
        });
        _showSnackBar('No user logged in. Please login first.', isError: true);
      }
    } catch (e) {
      debugPrint('❌ UserManagementScreen - Error checking authentication: $e');
      setState(() {
        isAuthenticated = false;
        hasAccess = false;
      });
      _showSnackBar('Authentication error: $e', isError: true);
    }
  }

  bool _checkRoleAccess(String userRole) {
    if (userRole.isEmpty) return false;

    final normalizedRole = userRole.toLowerCase().trim().replaceAll(' ', '_');

    bool hasAccess = allowedRoles.any((allowedRole) =>
        normalizedRole == allowedRole.toLowerCase() ||
        normalizedRole.contains(allowedRole.toLowerCase()) ||
        allowedRole.toLowerCase().contains(normalizedRole));

    debugPrint('🔍 Role Access Check: "$normalizedRole" -> ${hasAccess ? "ALLOWED" : "DENIED"}');
    return hasAccess;
  }

  Map<String, String> get headers => {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

  Future<void> _refreshToken() async {
    try {
      // Get JWT token from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      
      if (token != null && token.isNotEmpty) {
        setState(() {
          authToken = token;
        });
      } else {
        debugPrint('No JWT token found in SharedPreferences');
      }
    } catch (e) {
      debugPrint('Error refreshing token: $e');
    }
  }

  Future<void> fetchUsers() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('$apiUrl/user-management/users'),
        headers: headers,
      );

      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        debugPrint('🔍 Processing user data...');

        List<dynamic> userData = [];
        if (jsonData['success'] == true) {
          if (jsonData['data'] is List) {
            userData = jsonData['data'];
          } else if (jsonData['data'] is Map && jsonData['data']['users'] != null) {
            userData = jsonData['data']['users'];
          }
        }

        debugPrint('🔍 Found ${userData.length} users');

        setState(() {
          users = userData;
          isLoading = false;
        });
      } else if (response.statusCode == 401) {
        await _refreshToken();
        await fetchUsers(); // Retry
      } else {
        throw Exception('Failed to load users: ${response.statusCode}');
      }
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint('Error fetching users: $e');
      _showSnackBar('Error fetching users: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  List<dynamic> get filteredUsers {
    if (searchQuery.isEmpty) return users;
    return users.where((user) {
      final name = user['name']?.toString().toLowerCase() ?? '';
      final email = user['email']?.toString().toLowerCase() ?? '';
      return name.contains(searchQuery.toLowerCase()) ||
          email.contains(searchQuery.toLowerCase());
    }).toList();
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
      case 'driver':
        return const Color(0xFF95A5A6); // Gray
      default:
        return const Color(0xFF34495E); // Dark gray
    }
  }

  void _navigateToPermissions(dynamic user) {
    final userId = user['_id'] ?? user['id'];
    final userName = user['name'] ?? 'Unknown';
    final userEmail = user['email'] ?? '';
    final userRole = user['role'] ?? '';

    debugPrint('🔄 Navigating to permissions for user: $userName ($userId)');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserPermissionsScreen(
          userId: userId,
          userName: userName,
          userEmail: userEmail,
          userRole: userRole,
        ),
      ),
    ).then((_) {
      // Refresh users when coming back
      fetchUsers();
    });
  }

  void _showAddUserDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'fleet_manager';
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.person_add, color: Colors.blue[700]),
              const SizedBox(width: 8),
              const Text('Add New User'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name *',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email *',
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    labelText: 'Username *',
                    prefixIcon: const Icon(Icons.account_circle),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password *',
                    prefixIcon: const Icon(Icons.lock),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'Min. 6 characters',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: InputDecoration(
                    labelText: 'Role *',
                    prefixIcon: const Icon(Icons.shield),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'fleet_manager', child: Text('Fleet Manager')),
                    DropdownMenuItem(value: 'hr_manager', child: Text('HR Manager')),
                    DropdownMenuItem(value: 'finance', child: Text('Finance')),
                    DropdownMenuItem(value: 'driver', child: Text('Driver')),
                  ],
                  onChanged: (value) {
                    selectedRole = value!;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      // Validate fields
                      if (nameController.text.trim().isEmpty) {
                        _showSnackBar('Please enter full name', isError: true);
                        return;
                      }
                      if (emailController.text.trim().isEmpty) {
                        _showSnackBar('Please enter email', isError: true);
                        return;
                      }
                      if (!emailController.text.contains('@')) {
                        _showSnackBar('Please enter valid email', isError: true);
                        return;
                      }
                      if (usernameController.text.trim().isEmpty) {
                        _showSnackBar('Please enter username', isError: true);
                        return;
                      }
                      if (passwordController.text.length < 6) {
                        _showSnackBar('Password must be at least 6 characters', isError: true);
                        return;
                      }

                      setState(() => isSubmitting = true);

                      try {
                        debugPrint('➕ Creating new user: ${emailController.text}');

                        final response = await http.post(
                          Uri.parse('$apiUrl/user-management/users'),
                          headers: headers,
                          body: json.encode({
                            'name': nameController.text.trim(),
                            'email': emailController.text.trim().toLowerCase(),
                            'phone': phoneController.text.trim(),
                            'username': usernameController.text.trim(),
                            'password': passwordController.text,
                            'role': selectedRole,
                          }),
                        );

                        debugPrint('Response status: ${response.statusCode}');
                        debugPrint('Response body: ${response.body}');

                        final jsonData = json.decode(response.body);

                        if (response.statusCode == 201 || response.statusCode == 200) {
                          Navigator.pop(context);
                          _showSnackBar(jsonData['message'] ?? 'User created successfully!');
                          fetchUsers(); // Refresh user list
                        } else {
                          _showSnackBar(
                            jsonData['message'] ?? jsonData['error'] ?? 'Failed to create user',
                            isError: true,
                          );
                        }
                      } catch (e) {
                        debugPrint('❌ Error creating user: $e');
                        _showSnackBar('Error creating user: $e', isError: true);
                      } finally {
                        setState(() => isSubmitting = false);
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF27AE60), // Green
                foregroundColor: Colors.white,
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Add User'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUser(dynamic user) async {
    final userId = user['_id'] ?? user['id'];
    final userName = user['name'] ?? 'Unknown';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete user "$userName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE74C3C), // Red
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // TODO: Implement delete functionality
      _showSnackBar('Delete user functionality - Coming soon!');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'User Management',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF2C3E50),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: !isAuthenticated
          ? _buildAuthRequiredScreen()
          : !hasAccess
              ? _buildAccessDeniedScreen()
              : _buildMainContent(),
    );
  }

  Widget _buildAuthRequiredScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Authentication Required',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2c3e50)),
            ),
            const SizedBox(height: 8),
            const Text(
              'You need to be logged in to access User Management',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccessDeniedScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block, size: 80, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Access Denied',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red),
            ),
            const SizedBox(height: 8),
            Text(
              'Your role ($currentUserRole) does not have permission to access this section.',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildUserTable(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people, size: 32, color: Color(0xFF2C3E50)),
              const SizedBox(width: 12),
              const Text(
                'ERP Users',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _showAddUserDialog,
                icon: const Icon(Icons.person_add, size: 20),
                label: const Text('Add User'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27AE60), // Green
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (value) => setState(() => searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Search users by name or email...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTable() {
    if (filteredUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'No users found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
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
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(2),
            3: FlexColumnWidth(1.5),
            4: FlexColumnWidth(1.5),
            5: FlexColumnWidth(1),
            6: FlexColumnWidth(1),
          },
          children: [
            // Header row
            TableRow(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2C3E50), Color(0xFF34495E)],
                ),
              ),
              children: [
                _buildTableHeaderCell('Name'),
                _buildTableHeaderCell('Username'),
                _buildTableHeaderCell('Email'),
                _buildTableHeaderCell('Phone'),
                _buildTableHeaderCell('Role'),
                _buildTableHeaderCell('Permissions'),
                _buildTableHeaderCell('Actions'),
              ],
            ),
            // Data rows
            ...filteredUsers.map((user) => _buildUserRow(user)),
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

  TableRow _buildUserRow(dynamic user) {
    return TableRow(
      children: [
        _buildTableCell(user['name'] ?? 'N/A'),
        _buildTableCell(user['username'] ?? user['name'] ?? 'N/A'),
        _buildTableCell(user['email'] ?? 'N/A'),
        _buildTableCell(user['phone'] ?? 'N/A'),
        _buildRoleCell(user['role']),
        _buildPermissionsCell(user),
        _buildActionsCell(user),
      ],
    );
  }

  Widget _buildTableCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildRoleCell(String? role) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getRoleColor(role),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            role ?? 'N/A',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionsCell(dynamic user) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Center(
        child: ElevatedButton(
          onPressed: () => _navigateToPermissions(user),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3498DB), // Blue
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: const Text(
            'Manage',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildActionsCell(dynamic user) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () {
              _showSnackBar('Edit user functionality - Coming soon!');
            },
            icon: const Icon(Icons.edit, size: 18),
            color: const Color(0xFFF39C12), // Orange
            tooltip: 'Edit',
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => _deleteUser(user),
            icon: const Icon(Icons.delete, size: 18),
            color: const Color(0xFFE74C3C), // Red
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}