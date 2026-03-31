// File: lib/features/client/presentation/screens/client_employee_management.dart
// Client Employee Management with Organization-based Filtering using CustomerService

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/core/services/customer_service.dart';
import 'package:abra_fleet/core/models/customer_model.dart';
import 'package:abra_fleet/features/admin/customer_management/domain/entities/customer_entity.dart';
import 'package:abra_fleet/features/admin/customer_management/presentation/providers/customer_provider.dart';
import 'package:abra_fleet/features/admin/customer_management/customer_form_overlay.dart';
import 'package:abra_fleet/features/admin/customer_management/bulk_import_overlay.dart';
import 'package:abra_fleet/features/auth/domain/repositories/auth_repository.dart';

class ClientEmployeeManagement extends StatefulWidget {
  const ClientEmployeeManagement({Key? key}) : super(key: key);

  @override
  State<ClientEmployeeManagement> createState() => _ClientEmployeeManagementState();
}

class _ClientEmployeeManagementState extends State<ClientEmployeeManagement> {
  final TextEditingController _searchController = TextEditingController();
  final CustomerService _customerService = CustomerService();
  
  String _searchQuery = '';
  bool _showAddEmployeeOverlay = false;
  bool _showBulkImportOverlay = false;
  bool _isLoading = false;
  String? _errorMessage;
  
  CustomerEntity? _editingEmployee;
  String? _clientOrganizationDomain;
  List<CustomerModel> _organizationEmployees = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  Future<void> _initializeData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      print('🟢 Initializing client employee management');
      
      // Get current logged-in user's email
      final authRepo = Provider.of<AuthRepository>(context, listen: false);
      final currentUser = await authRepo.getCurrentUserWithRole();
      
      if (currentUser.email != null && currentUser.email!.isNotEmpty) {
        // Extract organization domain from email (e.g., @cognizant.com from client123@cognizant.com)
        final emailParts = currentUser.email!.split('@');
        if (emailParts.length == 2) {
          _clientOrganizationDomain = '@${emailParts[1]}';
          print('🟢 Client organization domain: $_clientOrganizationDomain');
          
          // Fetch organization-specific customers using CustomerService
          await _fetchOrganizationEmployees();
          
          print('🟢 Client employee data initialized - Total: ${_organizationEmployees.length}');
        } else {
          throw Exception('Invalid email format: ${currentUser.email}');
        }
      } else {
        throw Exception('No email found for current user');
      }
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('🔴 Error initializing client employee data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: ${e.toString()}'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _initializeData(),
            ),
          ),
        );
      }
    }
  }

  /// Fetch employees by organization domain using CustomerService
  Future<void> _fetchOrganizationEmployees() async {
    if (_clientOrganizationDomain == null) {
      print('⚠️ No organization domain set');
      return;
    }

    try {
      print('🔍 Fetching employees for domain: $_clientOrganizationDomain');
      
      // Use CustomerService to fetch customers by domain
      final customers = await _customerService.getCustomersByDomain(_clientOrganizationDomain!);
      
      if (mounted) {
        setState(() {
          _organizationEmployees = customers;
        });
      }
      
      print('✅ Fetched ${customers.length} employees for organization');
    } catch (e) {
      print('🔴 Error fetching organization employees: $e');
      rethrow;
    }
  }

  /// Convert CustomerModel to CustomerEntity for compatibility with existing UI
  CustomerEntity _convertToEntity(CustomerModel model) {
    return CustomerEntity(
      id: model.id,
      name: model.name,
      email: model.email,
      phoneNumber: model.phone,
      companyName: model.companyName,
      department: model.department,
      status: model.status,
      employeeId: model.employeeId,
      branch: model.branch,
      createdAt: model.createdAt,
      updatedAt: model.updatedAt,
    );
  }

  /// Apply search filter
  List<CustomerEntity> _getFilteredEmployees() {
    // Convert CustomerModel list to CustomerEntity list
    final employees = _organizationEmployees.map(_convertToEntity).toList();
    
    if (_searchQuery.isEmpty) return employees;
    
    return employees.where((emp) {
      return emp.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          emp.email.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (emp.employeeId?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Main content
          if (_isLoading && _organizationEmployees.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (_errorMessage != null && _organizationEmployees.isEmpty)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(_errorMessage!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => _initializeData(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          else
            RefreshIndicator(
              onRefresh: () => _refreshEmployees(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatsGrid(_organizationEmployees.map(_convertToEntity).toList()),
                    const SizedBox(height: 32),
                    _buildEmployeeDirectory(_getFilteredEmployees()),
                  ],
                ),
              ),
            ),

          // Add Employee Overlay
          if (_showAddEmployeeOverlay)
            _buildEmployeeFormOverlay(),

          // Bulk Import Overlay
          if (_showBulkImportOverlay)
            _buildBulkImportOverlay(),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(List<CustomerEntity> employees) {
    final activeEmployees = employees.where((e) => e.status.toLowerCase() == 'active').length;
    final inactiveEmployees = employees.where((e) => e.status.toLowerCase() == 'inactive').length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 40) / 3;
        return Wrap(
          spacing: 20,
          runSpacing: 20,
          children: [
            _buildStatCard(
              icon: Icons.people,
              iconColor: const Color(0xFF2563EB),
              iconBgColor: const Color(0xFF2563EB).withOpacity(0.1),
              value: employees.length.toString(),
              label: 'Total Employees',
              width: cardWidth,
            ),
            _buildStatCard(
              icon: Icons.check_circle,
              iconColor: const Color(0xFF10B981),
              iconBgColor: const Color(0xFF10B981).withOpacity(0.1),
              value: activeEmployees.toString(),
              label: 'Active Users',
              width: cardWidth,
            ),
            _buildStatCard(
              icon: Icons.person_remove,
              iconColor: const Color(0xFFEF4444),
              iconBgColor: const Color(0xFFEF4444).withOpacity(0.1),
              value: inactiveEmployees.toString(),
              label: 'Inactive',
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String value,
    required String label,
    required double width,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeDirectory(List<CustomerEntity> employees) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Colors.black.withOpacity(0.05),
        ),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Employee Directory (${employees.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (_clientOrganizationDomain != null)
                      Text(
                        'Organization: $_clientOrganizationDomain',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildActionButton(
                      icon: Icons.cleaning_services,
                      label: 'Clean Duplicates',
                      color: Colors.orange,
                      onPressed: _cleanupDuplicates,
                    ),
                    _buildActionButton(
                      icon: Icons.refresh,
                      label: 'Refresh',
                      color: const Color(0xFF8B5CF6),
                      onPressed: () => _refreshEmployees(),
                    ),
                    _buildActionButton(
                      icon: Icons.person_add,
                      label: 'Add Employee',
                      color: const Color(0xFF2563EB),
                      onPressed: () {
                        setState(() {
                          _editingEmployee = null;
                          _showAddEmployeeOverlay = true;
                        });
                      },
                    ),
                    _buildActionButton(
                      icon: Icons.upload_file,
                      label: 'Bulk Upload',
                      color: const Color(0xFF10B981),
                      onPressed: () {
                        setState(() {
                          _showBulkImportOverlay = true;
                        });
                      },
                    ),
                    _buildActionButton(
                      icon: Icons.download,
                      label: 'Export',
                      color: const Color(0xFF64748B),
                      onPressed: () {
                        _exportEmployees(employees);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),

          // Search Bar
          Padding(
            padding: const EdgeInsets.all(24),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search by name, email, or employee ID...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF2563EB)),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Table
          employees.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(48.0),
                  child: Column(
                    children: [
                      const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty
                            ? 'No employees match your search'
                            : 'No employees found for your organization\nClick "Add Employee" to create one',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 40,
                    headingRowColor: MaterialStateProperty.all(
                      const Color(0xFFF8FAFC),
                    ),
                    columns: const [
                      DataColumn(
                        label: Text(
                          'ID',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'NAME',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'EMAIL',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'PHONE',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'DEPARTMENT',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'STATUS',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'ACTIONS',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                      ),
                    ],
                    rows: employees.map((employee) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              employee.employeeId ?? 'N/A',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                          DataCell(Text(employee.name)),
                          DataCell(
                            Text(
                              employee.email,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                          DataCell(Text(employee.phoneNumber ?? 'N/A')),
                          DataCell(Text(employee.department ?? 'N/A')),
                          DataCell(_buildStatusBadge(employee.status)),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildIconButton(
                                  icon: Icons.visibility,
                                  color: const Color(0xFF2563EB),
                                  onPressed: () => _showEmployeeDetails(employee),
                                ),
                                const SizedBox(width: 4),
                                _buildIconButton(
                                  icon: Icons.edit,
                                  color: const Color(0xFFF59E0B),
                                  onPressed: () {
                                    setState(() {
                                      _editingEmployee = employee;
                                      _showAddEmployeeOverlay = true;
                                    });
                                  },
                                ),
                                const SizedBox(width: 4),
                                _buildIconButton(
                                  icon: Icons.delete,
                                  color: const Color(0xFFEF4444),
                                  onPressed: () => _deleteEmployee(employee),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor;
    Color textColor;
    String text = status;

    switch (status.toLowerCase()) {
      case 'active':
        bgColor = const Color(0xFF10B981).withOpacity(0.1);
        textColor = const Color(0xFF10B981);
        break;
      case 'inactive':
        bgColor = const Color(0xFFEF4444).withOpacity(0.1);
        textColor = const Color(0xFFEF4444);
        break;
      case 'pending':
        bgColor = const Color(0xFFF59E0B).withOpacity(0.1);
        textColor = const Color(0xFFF59E0B);
        break;
      default:
        bgColor = const Color(0xFF64748B).withOpacity(0.1);
        textColor = const Color(0xFF64748B);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  Widget _buildEmployeeFormOverlay() {
    return Material(
      color: Colors.black54,
      child: Navigator(
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (context) => CustomerFormOverlay(
              customer: _editingEmployee,
              onClose: () {
                if (mounted) {
                  setState(() {
                    _showAddEmployeeOverlay = false;
                    _editingEmployee = null;
                  });
                }
              },
              onSaved: () async {
                if (mounted) {
                  setState(() {
                    _showAddEmployeeOverlay = false;
                    _editingEmployee = null;
                  });
                  await _refreshEmployees();
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildBulkImportOverlay() {
    return Material(
      color: Colors.black54,
      child: Navigator(
        onGenerateRoute: (settings) {
          return MaterialPageRoute(
            builder: (context) => BulkImportOverlay(
              onClose: () {
                if (mounted) {
                  setState(() {
                    _showBulkImportOverlay = false;
                  });
                }
              },
              onImported: () async {
                if (mounted) {
                  setState(() {
                    _showBulkImportOverlay = false;
                  });
                  await _refreshEmployees();
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Bulk import completed successfully'),
                        backgroundColor: Colors.green,
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                }
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _refreshEmployees() async {
    if (_clientOrganizationDomain == null) {
      print('⚠️ No organization domain set, cannot refresh');
      return;
    }
    
    setState(() {
      _isLoading = true;
    });

    try {
      await _fetchOrganizationEmployees();
      
      print('🟢 Employees refreshed successfully');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Employee list refreshed'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      print('🔴 Error refreshing employees: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error refreshing: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showEmployeeDetails(CustomerEntity employee) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Text(employee.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('ID', employee.employeeId ?? 'N/A'),
            _buildDetailRow('Email', employee.email),
            _buildDetailRow('Phone', employee.phoneNumber ?? 'N/A'),
            _buildDetailRow('Company', employee.companyName ?? 'N/A'),
            _buildDetailRow('Department', employee.department ?? 'N/A'),
            _buildDetailRow('Status', employee.status),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEmployee(CustomerEntity employee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning,
                  color: Color(0xFFEF4444),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Delete Employee'),
            ],
          ),
          content: Text('Are you sure you want to delete ${employee.name}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      try {
        // Use CustomerService to delete
        final success = await _customerService.deleteCustomer(employee.id);

        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 12),
                    Text('${employee.name} deleted successfully'),
                  ],
                ),
                backgroundColor: const Color(0xFF10B981),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
            await _refreshEmployees();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to delete employee'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting employee: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _exportEmployees(List<CustomerEntity> employees) {
    // TODO: Implement CSV export functionality
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exporting ${employees.length} employees...'),
        backgroundColor: const Color(0xFF2563EB),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Future<void> _cleanupDuplicates() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cleaning_services, color: Colors.orange),
            SizedBox(width: 12),
            Text('Clean Up Duplicates'),
          ],
        ),
        content: const Text(
          'This will remove duplicate employee records, keeping only the oldest entry for each email.\n\nThis action cannot be undone. Continue?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Clean Up'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Cleaning up duplicates...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final result = await Provider.of<CustomerProvider>(
        context,
        listen: false,
      ).cleanupDuplicateEmployees();

      if (!mounted) return;
      Navigator.pop(context); // Close loading

      if (result['success'] == true) {
        // Show success dialog
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 12),
                Text('Cleanup Complete'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('✅ Duplicates found: ${result['duplicatesFound']}'),
                Text('✅ Duplicates deleted: ${result['duplicatesDeleted']}'),
                const SizedBox(height: 12),
                const Text(
                  'Employee list has been refreshed.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                ),
                child: const Text('OK'),
              ),
            ],
          ),
        );

        // Refresh the list
        if (mounted) {
          await _refreshEmployees();
        }
      } else {
        throw Exception(result['error'] ?? 'Unknown error');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Error: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}