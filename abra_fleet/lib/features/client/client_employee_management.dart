// File: lib/features/client/presentation/screens/client_employee_management.dart
// Client Employee Management with Organization-based Filtering using CustomerService

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  
  String _searchQuery = '';
  bool _showAddEmployeeOverlay = false;
  bool _showBulkImportOverlay = false;
  bool _showCustomerDetailsOverlay = false;
  bool _isLoading = false;
  String? _errorMessage;
  
  CustomerEntity? _editingEmployee;
  CustomerEntity? _selectedCustomer;
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
  /// Fetch employees by organization domain using CustomerService
/// Fetch employees by organization domain using CustomerService
Future<void> _fetchOrganizationEmployees() async {
  if (_clientOrganizationDomain == null) {
    print('⚠️ No organization domain set');
    return;
  }

  try {
    print('🔍 Fetching employees for domain: $_clientOrganizationDomain');
    
    // ✅ Call the backend API directly (no fallback needed)
    final customers = await _customerService.getCustomersByDomain(
      _clientOrganizationDomain!
    );
    
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
                controller: _verticalScrollController,
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

          // Customer Details Overlay
          if (_showCustomerDetailsOverlay && _selectedCustomer != null)
            _buildCustomerDetailsOverlay(),
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
                    // _buildActionButton(
                    //   icon: Icons.cleaning_services,
                    //   label: 'Clean Duplicates',
                    //   color: Colors.orange,
                    //   onPressed: _cleanupDuplicates,
                    // ),
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

          // Beautiful Table with Blue Gradient Header
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
              : _buildBeautifulTable(employees),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildBeautifulTable(List<CustomerEntity> employees) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Table Header with Blue Gradient
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF3B82F6), // Blue 500
                  Color(0xFF2563EB), // Blue 600
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                },
              ),
              child: SingleChildScrollView(
                controller: _horizontalScrollController,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTableHeaderCell('EMPLOYEE ID', 140),
                    _buildTableHeaderCell('NAME', 200),
                    _buildTableHeaderCell('EMAIL', 250),
                    _buildTableHeaderCell('PHONE', 150),
                    _buildTableHeaderCell('DEPARTMENT', 180),
                    _buildTableHeaderCell('BRANCH', 150),
                    _buildTableHeaderCell('STATUS', 120),
                    _buildTableHeaderCell('ACTIONS', 150),
                  ],
                ),
              ),
            ),
          ),

          // Table Body with Scrollable Content
          Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                },
              ),
              child: Scrollbar(
                controller: _horizontalScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 1340, // Total width of all columns
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: employees.length,
                      itemBuilder: (context, index) {
                        final employee = employees[index];
                        final isEven = index % 2 == 0;
                        
                        return InkWell(
                          onTap: () => _showCustomerDetails(employee),
                          hoverColor: const Color(0xFFF1F5F9),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isEven ? Colors.white : const Color(0xFFF8FAFC),
                              border: Border(
                                bottom: BorderSide(
                                  color: const Color(0xFFE2E8F0),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                _buildTableCell(
                                  employee.employeeId ?? 'N/A',
                                  140,
                                  isBold: true,
                                  textColor: const Color(0xFF1E293B),
                                ),
                                _buildTableCell(
                                  employee.name,
                                  200,
                                  isBold: true,
                                  textColor: const Color(0xFF2563EB),
                                ),
                                _buildTableCell(
                                  employee.email,
                                  250,
                                  textColor: const Color(0xFF64748B),
                                ),
                                _buildTableCell(
                                  employee.phoneNumber ?? 'N/A',
                                  150,
                                ),
                                _buildTableCell(
                                  employee.department ?? 'N/A',
                                  180,
                                ),
                                _buildTableCell(
                                  employee.branch ?? 'N/A',
                                  150,
                                ),
                                _buildTableCellWithWidget(
                                  _buildStatusBadge(employee.status),
                                  120,
                                ),
                                _buildTableCellWithWidget(
                                  _buildActionButtons(employee),
                                  150,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeaderCell(String text, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildTableCell(
    String text,
    double width, {
    bool isBold = false,
    Color? textColor,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
          color: textColor ?? const Color(0xFF1E293B),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildTableCellWithWidget(Widget widget, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: widget,
    );
  }

  Widget _buildActionButtons(CustomerEntity employee) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildIconButton(
          icon: Icons.visibility,
          color: const Color(0xFF2563EB),
          onPressed: () => _showCustomerDetails(employee),
        ),
        const SizedBox(width: 6),
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
        const SizedBox(width: 6),
        _buildIconButton(
          icon: Icons.delete,
          color: const Color(0xFFEF4444),
          onPressed: () => _deleteEmployee(employee),
        ),
      ],
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
  /// Show beautiful customer details overlay (replaces simple dialog)
  void _showCustomerDetails(CustomerEntity employee) {
    setState(() {
      _selectedCustomer = employee;
      _showCustomerDetailsOverlay = true;
    });
  }

  Widget _buildCustomerDetailsOverlay() {
    if (_selectedCustomer == null) return const SizedBox.shrink();

    return Material(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with Gradient
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF3B82F6), // Blue 500
                        Color(0xFF2563EB), // Blue 600
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            _selectedCustomer!.name.isNotEmpty
                                ? _selectedCustomer!.name[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      // Name and Status
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedCustomer!.name,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _buildWhiteStatusBadge(_selectedCustomer!.status),
                                const SizedBox(width: 12),
                                if (_selectedCustomer!.employeeId != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.badge,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'ID: ${_selectedCustomer!.employeeId}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Close Button
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _showCustomerDetailsOverlay = false;
                            _selectedCustomer = null;
                          });
                        },
                        icon: const Icon(Icons.close, color: Colors.white),
                        iconSize: 28,
                      ),
                    ],
                  ),
                ),

                // Body Content - Scrollable
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Contact Information Section
                        _buildDetailSection(
                          icon: Icons.contact_mail,
                          iconColor: const Color(0xFF2563EB),
                          title: 'Contact Information',
                          children: [
                            _buildDetailRow(
                              icon: Icons.email,
                              label: 'Email',
                              value: _selectedCustomer!.email,
                              iconColor: const Color(0xFF3B82F6),
                            ),
                            const SizedBox(height: 16),
                            _buildDetailRow(
                              icon: Icons.phone,
                              label: 'Phone Number',
                              value: _selectedCustomer!.phoneNumber ?? 'Not provided',
                              iconColor: const Color(0xFF10B981),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Organization Information Section
                        _buildDetailSection(
                          icon: Icons.business,
                          iconColor: const Color(0xFF8B5CF6),
                          title: 'Organization Information',
                          children: [
                            _buildDetailRow(
                              icon: Icons.apartment,
                              label: 'Company Name',
                              value: _selectedCustomer!.companyName ?? 'Not provided',
                              iconColor: const Color(0xFF8B5CF6),
                            ),
                            const SizedBox(height: 16),
                            _buildDetailRow(
                              icon: Icons.category,
                              label: 'Department',
                              value: _selectedCustomer!.department ?? 'Not provided',
                              iconColor: const Color(0xFFF59E0B),
                            ),
                            const SizedBox(height: 16),
                            _buildDetailRow(
                              icon: Icons.location_city,
                              label: 'Branch',
                              value: _selectedCustomer!.branch ?? 'Not provided',
                              iconColor: const Color(0xFFEC4899),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // System Information Section
                        _buildDetailSection(
                          icon: Icons.info,
                          iconColor: const Color(0xFF64748B),
                          title: 'System Information',
                          children: [
                            _buildDetailRow(
                              icon: Icons.calendar_today,
                              label: 'Created At',
                              value: _formatDateTime(_selectedCustomer!.createdAt),
                              iconColor: const Color(0xFF64748B),
                            ),
                            const SizedBox(height: 16),
                            _buildDetailRow(
                              icon: Icons.update,
                              label: 'Last Updated',
                              value: _formatDateTime(_selectedCustomer!.updatedAt),
                              iconColor: const Color(0xFF64748B),
                            ),
                            if (_selectedCustomer!.createdBy != null) ...[
                              const SizedBox(height: 16),
                              _buildDetailRow(
                                icon: Icons.person,
                                label: 'Created By',
                                value: _selectedCustomer!.createdBy!,
                                iconColor: const Color(0xFF64748B),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 32),

                        // Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _showCustomerDetailsOverlay = false;
                                    _editingEmployee = _selectedCustomer;
                                    _showAddEmployeeOverlay = true;
                                    _selectedCustomer = null;
                                  });
                                },
                                icon: const Icon(Icons.edit, size: 18),
                                label: const Text('Edit Employee'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2563EB),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _showCustomerDetailsOverlay = false;
                                  });
                                  _deleteEmployee(_selectedCustomer!);
                                },
                                icon: const Icon(Icons.delete, size: 18),
                                label: const Text('Delete Employee'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFEF4444),
                                  side: const BorderSide(
                                    color: Color(0xFFEF4444),
                                    width: 1.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWhiteStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: _getStatusColor(status),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              color: _getStatusColor(status),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return const Color(0xFF10B981);
      case 'inactive':
        return const Color(0xFFEF4444);
      case 'pending':
        return const Color(0xFFF59E0B);
      default:
        return const Color(0xFF64748B);
    }
  }

  Widget _buildDetailSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    
    final day = dateTime.day;
    final month = months[dateTime.month - 1];
    final year = dateTime.year;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    
    return '$day $month $year, $hour:$minute';
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
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to delete this employee?'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      employee.email,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '⚠️ This action cannot be undone.',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
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
      // Close details overlay if open
      if (_showCustomerDetailsOverlay) {
        setState(() {
          _showCustomerDetailsOverlay = false;
          _selectedCustomer = null;
        });
      }

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
        content: Row(
          children: [
            const Icon(Icons.download, color: Colors.white),
            const SizedBox(width: 12),
            Text('Exporting ${employees.length} employees...'),
          ],
        ),
        backgroundColor: const Color(0xFF2563EB),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  // Future<void> _cleanupDuplicates() async {
  //   // Show confirmation dialog
  //   final confirmed = await showDialog<bool>(
  //     context: context,
  //     builder: (context) => AlertDialog(
  //       shape: RoundedRectangleBorder(
  //         borderRadius: BorderRadius.circular(12),
  //       ),
  //       title: Row(
  //         children: [
  //           Container(
  //             padding: const EdgeInsets.all(8),
  //             decoration: BoxDecoration(
  //               color: Colors.orange.withOpacity(0.1),
  //               borderRadius: BorderRadius.circular(8),
  //             ),
  //             child: const Icon(Icons.cleaning_services, color: Colors.orange),
  //           ),
  //           const SizedBox(width: 12),
  //           const Text('Clean Up Duplicates'),
  //         ],
  //       ),
  //       content: const Column(
  //         mainAxisSize: MainAxisSize.min,
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Text(
  //             'This will remove duplicate employee records, keeping only the oldest entry for each email.',
  //             style: TextStyle(fontSize: 14),
  //           ),
  //           SizedBox(height: 12),
  //           Text(
  //             '⚠️ This action cannot be undone. Continue?',
  //             style: TextStyle(
  //               fontSize: 14,
  //               fontWeight: FontWeight.w600,
  //               color: Colors.orange,
  //             ),
  //           ),
  //         ],
  //       ),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.pop(context, false),
  //           child: const Text('Cancel'),
  //         ),
  //         ElevatedButton(
  //           onPressed: () => Navigator.pop(context, true),
  //           style: ElevatedButton.styleFrom(
  //             backgroundColor: Colors.orange,
  //           ),
  //           child: const Text('Clean Up'),
  //         ),
  //       ],
  //     ),
  //   );

  //   if (confirmed != true) return;

  //   // Show loading
  //   showDialog(
  //     context: context,
  //     barrierDismissible: false,
  //     builder: (context) => Center(
  //       child: Card(
  //         shape: RoundedRectangleBorder(
  //           borderRadius: BorderRadius.circular(12),
  //         ),
  //         child: const Padding(
  //           padding: EdgeInsets.all(32.0),
  //           child: Column(
  //             mainAxisSize: MainAxisSize.min,
  //             children: [
  //               SizedBox(
  //                 width: 48,
  //                 height: 48,
  //                 child: CircularProgressIndicator(strokeWidth: 3),
  //               ),
  //               SizedBox(height: 20),
  //               Text(
  //                 'Cleaning up duplicates...',
  //                 style: TextStyle(
  //                   fontSize: 16,
  //                   fontWeight: FontWeight.w500,
  //                 ),
  //               ),
  //             ],
  //           ),
  //         ),
  //       ),
  //     ),
  //   );

  //   try {
  //     final result = await Provider.of<CustomerProvider>(
  //       context,
  //       listen: false,
  //     ).cleanupDuplicateEmployees();

  //     if (!mounted) return;
  //     Navigator.pop(context); // Close loading

  //     if (result['success'] == true) {
  //       // Show success dialog
  //       await showDialog(
  //         context: context,
  //         builder: (context) => AlertDialog(
  //           shape: RoundedRectangleBorder(
  //             borderRadius: BorderRadius.circular(12),
  //           ),
  //           title: Row(
  //             children: [
  //               Container(
  //                 padding: const EdgeInsets.all(8),
  //                 decoration: BoxDecoration(
  //                   color: const Color(0xFF10B981).withOpacity(0.1),
  //                   borderRadius: BorderRadius.circular(8),
  //                 ),
  //                 child: const Icon(
  //                   Icons.check_circle,
  //                   color: Color(0xFF10B981),
  //                 ),
  //               ),
  //               const SizedBox(width: 12),
  //               const Text('Cleanup Complete'),
  //             ],
  //           ),
  //           content: Column(
  //             mainAxisSize: MainAxisSize.min,
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               Container(
  //                 padding: const EdgeInsets.all(16),
  //                 decoration: BoxDecoration(
  //                   color: const Color(0xFFF8FAFC),
  //                   borderRadius: BorderRadius.circular(8),
  //                   border: Border.all(color: const Color(0xFFE2E8F0)),
  //                 ),
  //                 child: Column(
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     _buildResultRow(
  //                       Icons.search,
  //                       'Duplicates found',
  //                       '${result['duplicatesFound']}',
  //                       const Color(0xFF2563EB),
  //                     ),
  //                     const SizedBox(height: 12),
  //                     _buildResultRow(
  //                       Icons.delete,
  //                       'Duplicates deleted',
  //                       '${result['duplicatesDeleted']}',
  //                       const Color(0xFFEF4444),
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //               const SizedBox(height: 16),
  //               const Text(
  //                 'Employee list has been refreshed.',
  //                 style: TextStyle(
  //                   fontWeight: FontWeight.w600,
  //                   color: Color(0xFF10B981),
  //                 ),
  //               ),
  //             ],
  //           ),
  //           actions: [
  //             ElevatedButton(
  //               onPressed: () => Navigator.pop(context),
  //               style: ElevatedButton.styleFrom(
  //                 backgroundColor: const Color(0xFF10B981),
  //                 padding: const EdgeInsets.symmetric(
  //                   horizontal: 24,
  //                   vertical: 12,
  //                 ),
  //               ),
  //               child: const Text('OK'),
  //             ),
  //           ],
  //         ),
  //       );

  //       // Refresh the list
  //       if (mounted) {
  //         await _refreshEmployees();
  //       }
  //     } else {
  //       throw Exception(result['error'] ?? 'Unknown error');
  //     }
  //   } catch (e) {
  //     if (!mounted) return;
  //     Navigator.pop(context); // Close loading

  //     ScaffoldMessenger.of(context).showSnackBar(
  //       SnackBar(
  //         content: Row(
  //           children: [
  //             const Icon(Icons.error, color: Colors.white),
  //             const SizedBox(width: 12),
  //             Expanded(child: Text('Error: $e')),
  //           ],
  //         ),
  //         backgroundColor: Colors.red,
  //         behavior: SnackBarBehavior.floating,
  //         shape: RoundedRectangleBorder(
  //           borderRadius: BorderRadius.circular(8),
  //         ),
  //       ),
  //     );
  //   }
  // }

  Widget _buildResultRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }
}