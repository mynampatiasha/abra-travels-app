// File: lib/features/admin/user_management/presentation/screens/user_management_screen.dart
// User management screen for admin to create and manage users

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';
import 'package:abra_fleet/core/services/api_service.dart';
import 'create_user_screen.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  // Using HTTP API instead of Firebase
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String _selectedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    
    try {
      final response = await ApiService().get('/api/users', queryParams: {
        if (_selectedFilter != 'all') 'role': _selectedFilter,
      });
      
      setState(() {
        _users = List<Map<String, dynamic>>.from(response['users'] ?? response['data'] ?? []);
        
        // Sort by creation date (newest first)
        _users.sort((a, b) {
          final aTime = a['createdAt'] as String?;
          final bTime = b['createdAt'] as String?;
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;
          if (bTime == null) return -1;
          return DateTime.parse(bTime).compareTo(DateTime.parse(aTime));
        });
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading users: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteUser(String userId, String email) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Are you sure you want to delete user: $email?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Delete via HTTP API
        await ApiService().delete('/api/users/$userId');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadUsers(); // Refresh the list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting user: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final role = user['role'] ?? 'unknown';
    final name = user['name'] ?? 'No Name';
    final email = user['email'] ?? 'No Email';
    final phone = user['phoneNumber'] ?? 'No Phone';
    final createdAt = user['createdAt'] as String?;
    
    Color roleColor;
    IconData roleIcon;
    
    switch (role.toLowerCase()) {
      case 'driver':
        roleColor = Colors.green;
        roleIcon = Icons.drive_eta;
        break;
      case 'customer':
        roleColor = Colors.blue;
        roleIcon = Icons.person;
        break;
      case 'admin':
        roleColor = Colors.red;
        roleIcon = Icons.admin_panel_settings;
        break;
      default:
        roleColor = Colors.grey;
        roleIcon = Icons.help;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: roleColor.withOpacity(0.1),
          child: Icon(roleIcon, color: roleColor),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email),
            Text(phone),
            if (createdAt != null)
              Text(
                'Created: ${DateTime.parse(createdAt).toString().split('.')[0]}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'delete':
                _deleteUser(user['id'], email);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsers,
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('Filter: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: _selectedFilter == 'all',
                        onSelected: (selected) {
                          setState(() => _selectedFilter = 'all');
                          _loadUsers();
                        },
                      ),
                      FilterChip(
                        label: const Text('Customers'),
                        selected: _selectedFilter == 'customer',
                        onSelected: (selected) {
                          setState(() => _selectedFilter = 'customer');
                          _loadUsers();
                        },
                      ),
                      FilterChip(
                        label: const Text('Drivers'),
                        selected: _selectedFilter == 'driver',
                        onSelected: (selected) {
                          setState(() => _selectedFilter = 'driver');
                          _loadUsers();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Users list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No users found',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create your first user using the + button',
                              style: TextStyle(
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          return _buildUserCard(_users[index]);
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: "add_user_fab",
        onPressed: () async {
          final result = await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const CreateUserScreen(),
            ),
          );
          
          if (result == true) {
            _loadUsers(); // Refresh the list if a user was created
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
