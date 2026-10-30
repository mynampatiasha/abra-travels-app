// File: lib/features/admin/customer_management/presentation/screens/admin_all_customers.dart
// âœ… COMPLETE VERSION - All Features Working
// 
// Features:
// - Filter button (opens AlternativeFilterBar overlay)
// - Export to Excel (with/without filters)
// - Branch column in table
// - Improved UI/UX
// - All previous functionality preserved

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:abra_fleet/features/admin/customer_management/domain/entities/customer_entity.dart';
import 'package:abra_fleet/features/admin/customer_management/presentation/providers/customer_provider.dart';
import 'package:abra_fleet/features/admin/customer_management/presentation/screens/admin_customer_details_screen.dart';
import 'package:abra_fleet/features/admin/customer_management/customer_form_overlay.dart';
import 'package:abra_fleet/features/admin/customer_management/bulk_import_overlay.dart';
import 'package:abra_fleet/features/client/bulk_import_rosters.dart';
import 'package:abra_fleet/features/admin/widgets/horizontal_filter_bar.dart';
import 'package:abra_fleet/features/admin/widgets/country_state_city_filter.dart';
import 'package:abra_fleet/app/config/api_config.dart';
import 'package:flutter/gestures.dart';
import 'package:abra_fleet/core/widgets/permission_restricted_dialog.dart';

// For web download - conditional import
import 'package:abra_fleet/download_helper_stub.dart'
    if (dart.library.html) 'package:abra_fleet/download_helper_web.dart' as download_helper;

class AdminAllCustomersPage extends StatefulWidget {
  const AdminAllCustomersPage({Key? key}) : super(key: key);

  @override
  State<AdminAllCustomersPage> createState() => _AdminAllCustomersPageState();
}

class _AdminAllCustomersPageState extends State<AdminAllCustomersPage> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  Timer? _autoRefreshTimer;
  String? selectedOrganization = 'All Organizations';
  String? selectedStatus = 'All';
  String? selectedDepartment = 'All Departments';
  final TextEditingController searchController = TextEditingController();
  bool _showAddCustomerOverlay = false;
  bool _showBulkImportOverlay = false;
  bool _showBulkImportRostersOverlay = false;
  bool _showFilterOverlay = false;
  bool _isExporting = false;
  CustomerEntity? _editingCustomer;
  
  // Filter state
  Map<String, dynamic> _activeFilters = {};
  List<CustomerEntity> _allCustomers = [];

  final List<String> _departments = [
    'All Departments',
    'Engineering',
    'Human Resources',
    'Finance',
    'Sales',
    'Marketing',
    'Operations',
    'IT Support',
    'Customer Service',
    'Product Management',
    'Legal',
    'Administration',
    'Research & Development',
  ];

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    searchController.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    if (!mounted) return;
    
    try {
      print('\nðŸŸ¢ INITIALIZING CUSTOMER DATA');
      print('â”€' * 80);
      
      final provider = Provider.of<CustomerProvider>(context, listen: false);
      
      await provider.initialize();
      
      if (!mounted) return;
      
      await provider.fetchCustomers(
        status: selectedStatus != 'All' ? selectedStatus?.toLowerCase() : null,
        search: '',
        organization: selectedOrganization == 'All Organizations' ? null : selectedOrganization,
        department: selectedDepartment == 'All Departments' ? null : selectedDepartment,
      );
      
      if (!mounted) return;
      
      print('âœ… Customer data initialized successfully');
    } catch (e) {
      print('âŒ Error initializing customer data: $e');
      
      if (!mounted) return;
      
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F2557), Color(0xFF1A3FC4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 2,
        shadowColor: const Color(0x590F2557),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pop();
          },
          tooltip: 'Back to Admin Dashboard',
        ),
        title: const Text(
          'Customer Management',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: Stack(
        children: [
          Consumer<CustomerProvider>(
            builder: (context, customerProvider, child) {
              if (customerProvider.isLoading && customerProvider.customers.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (customerProvider.errorMessage != null && customerProvider.customers.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(customerProvider.errorMessage!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _initializeData(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              final filteredCustomers = _getFilteredCustomers(customerProvider.customers);

              return RefreshIndicator(
                onRefresh: () => _refreshCustomers(),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatsGrid(customerProvider.customers),
                      const SizedBox(height: 24),
                      
                      // ðŸ†• NEW: Country State City Filter (replaces Advanced Filters button)
                      CountryStateCityFilter(
                        onFilterApplied: (filterData) {
                          setState(() {
                            _activeFilters = {};
                            
                            // Map the filter data to our active filters
                            if (filterData['fromDate'] != null) {
                              _activeFilters['startDate'] = filterData['fromDate'];
                            }
                            if (filterData['toDate'] != null) {
                              _activeFilters['endDate'] = filterData['toDate'];
                            }
                            if (filterData['country'] != null && filterData['country'].toString().isNotEmpty) {
                              _activeFilters['country'] = filterData['country'];
                            }
                            if (filterData['state'] != null && filterData['state'].toString().isNotEmpty) {
                              _activeFilters['state'] = filterData['state'];
                            }
                            if (filterData['city'] != null && filterData['city'].toString().isNotEmpty) {
                              _activeFilters['city'] = filterData['city'];
                            }
                            if (filterData['localArea'] != null && filterData['localArea'].toString().isNotEmpty) {
                              _activeFilters['area'] = filterData['localArea'];
                            }
                          });
                          _refreshCustomers();
                        },
                      ),
                      const SizedBox(height: 24),
                      
                      _buildFilterSection(customerProvider),
                      const SizedBox(height: 24),
                      _buildCustomerDirectory(filteredCustomers),
                    ],
                  ),
                ),
              );
            },
          ),
          
          // Add/Edit Customer Overlay
          if (_showAddCustomerOverlay)
            _buildCustomerFormOverlay(),
          
          // Bulk Import Overlay
          if (_showBulkImportOverlay)
            _buildBulkImportOverlay(),
          
          // Bulk Import Rosters Overlay
          if (_showBulkImportRostersOverlay)
            BulkImportRostersScreen(
              onCancel: () {
                if (mounted) {
                  setState(() {
                    _showBulkImportRostersOverlay = false;
                  });
                }
              },
              onImportComplete: () {
                if (mounted) {
                  setState(() {
                    _showBulkImportRostersOverlay = false;
                  });
                  _refreshCustomers();
                }
              },
            ),
          
          // ðŸ†• Advanced Filter Overlay
          if (_showFilterOverlay)
            _buildAdvancedFilterOverlay(),
        ],
      ),
    );
  }

  List<CustomerEntity> _getFilteredCustomers(List<CustomerEntity> allCustomers) {
    List<CustomerEntity> filtered = allCustomers;

    // Apply horizontal filter bar filters first
    filtered = _applyLocalFilters(filtered);

    if (selectedOrganization != null && selectedOrganization != 'All Organizations') {
      filtered = filtered.where((c) => 
        c.companyName?.toLowerCase() == selectedOrganization!.toLowerCase()
      ).toList();
    }

    if (selectedStatus != null && selectedStatus != 'All') {
      filtered = filtered.where((c) => 
        c.status.toLowerCase() == selectedStatus!.toLowerCase()
      ).toList();
    }

    if (selectedDepartment != null && selectedDepartment != 'All Departments') {
      filtered = filtered.where((c) => 
        c.department?.toLowerCase() == selectedDepartment!.toLowerCase()
      ).toList();
    }

    if (searchController.text.isNotEmpty) {
      final searchTerm = searchController.text.toLowerCase();
      filtered = filtered.where((c) =>
        c.name.toLowerCase().contains(searchTerm) ||
        c.email.toLowerCase().contains(searchTerm) ||
        (c.employeeId?.toLowerCase().contains(searchTerm) ?? false) ||
        (c.companyName?.toLowerCase().contains(searchTerm) ?? false)
      ).toList();
    }

    return filtered;
  }

  List<CustomerEntity> _applyLocalFilters(List<CustomerEntity> customers) {
    if (_activeFilters.isEmpty) return customers;
    
    return customers.where((customer) {
      // Date range filter
      if (_activeFilters.containsKey('startDate') && _activeFilters.containsKey('endDate')) {
        final startDate = _activeFilters['startDate'] as DateTime;
        final endDate = _activeFilters['endDate'] as DateTime;
        final customerDate = customer.createdAt;
        if (customerDate == null || 
            customerDate.isBefore(startDate) || 
            customerDate.isAfter(endDate)) {
          return false;
        }
      }
      
      // Country filter
      if (_activeFilters.containsKey('country')) {
        final country = _activeFilters['country'] as String;
        if (customer.address == null || 
            !customer.address!.toLowerCase().contains(country.toLowerCase())) {
          return false;
        }
      }
      
      // State filter
      if (_activeFilters.containsKey('state')) {
        final state = _activeFilters['state'] as String;
        if (customer.address == null || 
            !customer.address!.toLowerCase().contains(state.toLowerCase())) {
          return false;
        }
      }
      
      // City filter
      if (_activeFilters.containsKey('city')) {
        final city = _activeFilters['city'] as String;
        if (customer.address == null || 
            !customer.address!.toLowerCase().contains(city.toLowerCase())) {
          return false;
        }
      }
      
      // Area filter
      if (_activeFilters.containsKey('area')) {
        final area = _activeFilters['area'] as String;
        if (customer.address == null || 
            !customer.address!.toLowerCase().contains(area.toLowerCase())) {
          return false;
        }
      }
      
      return true;
    }).toList();
  }

  void _handleFilterApplied(Map<String, dynamic> filters) {
    setState(() {
      _activeFilters = filters;
      _showFilterOverlay = false;
    });
  }

  void _handleFilterCleared() {
    setState(() {
      _activeFilters = {};
      _showFilterOverlay = false;
    });
  }

  // ðŸ†• Quick Actions Section (Advanced Filters Button Commented Out)
  Widget _buildQuickActions() {
    final activeFilterCount = _activeFilters.length;
    
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
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // âŒ COMMENTED OUT - Advanced Filters Button
          // Expanded(
          //   child: ElevatedButton.icon(
          //     onPressed: () {
          //       setState(() {
          //         _showFilterOverlay = true;
          //       });
          //     },
          //     icon: Stack(
          //       clipBehavior: Clip.none,
          //       children: [
          //         const Icon(Icons.filter_alt, size: 20),
          //         if (activeFilterCount > 0)
          //           Positioned(
          //             right: -8,
          //             top: -8,
          //             child: Container(
          //               padding: const EdgeInsets.all(4),
          //               decoration: const BoxDecoration(
          //                 color: Colors.red,
          //                 shape: BoxShape.circle,
          //               ),
          //               constraints: const BoxConstraints(
          //                 minWidth: 18,
          //                 minHeight: 18,
          //               ),
          //               child: Text(
          //                 '$activeFilterCount',
          //                 style: const TextStyle(
          //                   color: Colors.white,
          //                   fontSize: 10,
          //                   fontWeight: FontWeight.bold,
          //                 ),
          //                 textAlign: TextAlign.center,
          //               ),
          //             ),
          //           ),
          //       ],
          //     ),
          //     label: Text(activeFilterCount > 0 
          //       ? 'Filters Applied ($activeFilterCount)' 
          //       : 'Advanced Filters'),
          //     style: ElevatedButton.styleFrom(
          //       backgroundColor: activeFilterCount > 0 
          //         ? const Color(0xFF8B5CF6) 
          //         : const Color(0xFF2563EB),
          //       foregroundColor: Colors.white,
          //       padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          //       shape: RoundedRectangleBorder(
          //         borderRadius: BorderRadius.circular(10),
          //       ),
          //     ),
          //   ),
          // ),
          // const SizedBox(width: 12),
          
          // Note: Advanced Filters button has been commented out.
          // The new CountryStateCityFilter widget is now used after the cards section.
        ],
      ),
    );
  }

  // ðŸ†• Advanced Filter Overlay
  Widget _buildAdvancedFilterOverlay() {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.9,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.filter_alt, color: Colors.white),
                    const SizedBox(width: 12),
                    const Text(
                      'Advanced Filters',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _showFilterOverlay = false;
                        });
                      },
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              
              // Filter Content
              Expanded(
                child: SingleChildScrollView(
                  child: AlternativeFilterBar(
                    onFilterApplied: _handleFilterApplied,
                    onFilterCleared: _handleFilterCleared,
                    initialFilters: _activeFilters,
                    showDateFilter: false,
                    showDateRangeFilter: true,
                    showCountryFilter: true,
                    showStateFilter: true,
                    showCityFilter: true,
                    showAreaFilter: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ðŸ†• Export Customers to Excel
  Future<void> _exportCustomers() async {
    if (_isExporting) return;
    
    setState(() {
      _isExporting = true;
    });

    try {
      print('\nðŸ“Š EXPORTING CUSTOMERS TO EXCEL');
      print('â”€' * 80);

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null) {
        throw Exception('Authentication required');
      }

      // Build query parameters from active filters
      final queryParams = <String, String>{};
      
      if (selectedStatus != null && selectedStatus != 'All') {
        queryParams['status'] = selectedStatus!.toLowerCase();
      }
      
      if (selectedOrganization != null && selectedOrganization != 'All Organizations') {
        queryParams['organization'] = selectedOrganization!;
      }
      
      if (selectedDepartment != null && selectedDepartment != 'All Departments') {
        queryParams['department'] = selectedDepartment!;
      }
      
      if (searchController.text.isNotEmpty) {
        queryParams['search'] = searchController.text;
      }
      
      // Add advanced filters
      if (_activeFilters.containsKey('country')) {
        queryParams['country'] = _activeFilters['country'];
      }
      
      if (_activeFilters.containsKey('state')) {
        queryParams['state'] = _activeFilters['state'];
      }
      
      if (_activeFilters.containsKey('city')) {
        queryParams['city'] = _activeFilters['city'];
      }
      
      if (_activeFilters.containsKey('startDate')) {
        queryParams['startDate'] = (_activeFilters['startDate'] as DateTime).toIso8601String();
      }
      
      if (_activeFilters.containsKey('endDate')) {
        queryParams['endDate'] = (_activeFilters['endDate'] as DateTime).toIso8601String();
      }

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/customers/legacy/export')
          .replace(queryParameters: queryParams);

      print('ðŸ“¡ Export URL: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(
        const Duration(minutes: 2),
        onTimeout: () {
          throw Exception('Export timeout - Please try again');
        },
      );

      print('ðŸ“¥ Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final timestamp = DateTime.now().toIso8601String().split('T')[0];
        final filename = 'customers_export_$timestamp.xlsx';

        if (kIsWeb) {
          // Web download
          download_helper.downloadFile(bytes, filename);
        } else {
          // Mobile/Desktop download
          final directory = await getApplicationDocumentsDirectory();
          final file = File('${directory.path}/$filename');
          await file.writeAsBytes(bytes);
          
          if (!mounted) return;
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File saved to: ${file.path}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Excel file exported successfully! ($filename)',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          ),
        );

        print('âœ… Export completed successfully');
      } else {
        throw Exception('Export failed: ${response.statusCode}');
      }
    } catch (e) {
      print('âŒ Export error: $e');
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Export failed: ${e.toString()}')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: _exportCustomers,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  Widget _buildStatsGrid(List<CustomerEntity> customers) {
    final activeCustomers = customers.where((c) => c.status.toLowerCase() == 'active').length;
    final inactiveCustomers = customers.where((c) => c.status.toLowerCase() == 'inactive').length;
    final pendingCustomers = customers.where((c) => c.status.toLowerCase() == 'pending').length;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            label: 'Total Customers',
            value: customers.length.toString(),
            subtitle: 'All registered',
            icon: Icons.people_alt_rounded,
            color: const Color(0xFF0F2557),
            iconBg: const Color(0xFFEFF6FF),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            label: 'Active Customers',
            value: activeCustomers.toString(),
            subtitle: customers.isEmpty 
              ? '0%' 
              : '${((activeCustomers / customers.length) * 100).toStringAsFixed(0)}% active',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF10B981),
            iconBg: const Color(0xFFECFDF5),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            label: 'Inactive',
            value: inactiveCustomers.toString(),
            subtitle: 'Need attention',
            icon: Icons.pause_circle_filled_rounded,
            color: const Color(0xFFF59E0B),
            iconBg: const Color(0xFFFFFBEB),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            label: 'Pending Approval',
            value: pendingCustomers.toString(),
            subtitle: 'Awaiting verification',
            icon: Icons.hourglass_top_rounded,
            color: const Color(0xFFEF4444),
            iconBg: const Color(0xFFFEF2F2),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required Color iconBg,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.2), width: 1.5),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection(CustomerProvider provider) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.search, size: 18, color: Color(0xFF0F2557)),
              SizedBox(width: 8),
              Text(
                'Quick Search & Filter',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F2557),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _buildOrganizationDropdown(provider)),
              const SizedBox(width: 16),
              Expanded(child: _buildStatusDropdown()),
              const SizedBox(width: 16),
              Expanded(child: _buildDepartmentDropdown()),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: _buildSearchField()),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F2557), Color(0xFF1A3FC4)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F2557).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() {});
                  },
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text(
                    'Apply Filter',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    selectedOrganization = 'All Organizations';
                    selectedStatus = 'All';
                    selectedDepartment = 'All Departments';
                    searchController.clear();
                  });
                },
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text(
                  'Reset',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF64748B),
                  side: const BorderSide(color: Color(0xFFE2E8F0), width: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrganizationDropdown(CustomerProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Organization',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: selectedOrganization,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: InputBorder.none,
                  ),
                  items: provider.companies.map((org) {
                    return DropdownMenuItem(
                      value: org,
                      child: Text(
                        org,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedOrganization = value);
                  },
                ),
              ),
              Container(
                height: 40,
                width: 1,
                color: const Color(0xFFE2E8F0),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showAddCompanyDialog(provider),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: const Icon(
                      Icons.add_business,
                      size: 20,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showAddCompanyDialog(CustomerProvider provider) {
    final TextEditingController companyController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.business, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Text('Add New Company'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the company name to add to the list',
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: companyController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Company Name',
                  hintText: 'e.g., Acme Corporation',
                  prefixIcon: const Icon(Icons.business_center),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF2563EB),
                      width: 2,
                    ),
                  ),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                final companyName = companyController.text.trim();
                if (companyName.isNotEmpty) {
                  final success = await provider.addCompany(companyName);
                  
                  if (mounted) {
                    Navigator.pop(dialogContext);
                    
                    if (success) {
                      setState(() {
                        selectedOrganization = companyName;
                      });
                      
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Company "$companyName" added successfully'),
                          backgroundColor: Colors.green,
                          action: SnackBarAction(
                            label: 'Undo',
                            textColor: Colors.white,
                            onPressed: () async {
                              await provider.removeCompany(companyName);
                              setState(() {
                                selectedOrganization = 'All Organizations';
                              });
                            },
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Company already exists in the list'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                  }
                }
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Company'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Status',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: selectedStatus,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
          items: const [
            DropdownMenuItem(
              value: 'All',
              child: Text('All', style: TextStyle(fontSize: 13)),
            ),
            DropdownMenuItem(
              value: 'Active',
              child: Text('Active', style: TextStyle(fontSize: 13)),
            ),
            DropdownMenuItem(
              value: 'Inactive',
              child: Text('Inactive', style: TextStyle(fontSize: 13)),
            ),
            DropdownMenuItem(
              value: 'Pending',
              child: Text('Pending', style: TextStyle(fontSize: 13)),
            ),
          ],
          onChanged: (value) {
            setState(() => selectedStatus = value);
          },
        ),
      ],
    );
  }

  Widget _buildDepartmentDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Department',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: selectedDepartment,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
          items: _departments.map((dept) {
            return DropdownMenuItem(
              value: dept,
              child: Text(
                dept,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => selectedDepartment = value);
          },
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Search',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: searchController,
          decoration: InputDecoration(
            hintText: 'Name, Email, ID...',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            suffixIcon: searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() => searchController.clear());
                  },
                )
              : null,
          ),
          onChanged: (value) => setState(() {}),
        ),
      ],
    );
  }

  Widget _buildCustomerDirectory(List<CustomerEntity> customers) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Table Top Bar with Quick Scroll Controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.people_alt, color: Color(0xFF0F2557), size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Customer Directory (${customers.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F2557),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Scroll Left Button
                    IconButton.filledTonal(
                      onPressed: () {
                        _horizontalScrollController.animateTo(
                          0,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      },
                      icon: const Icon(Icons.arrow_back_ios_new, size: 14),
                      tooltip: 'Scroll to First Column',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF6FF),
                        foregroundColor: const Color(0xFF1A3FC4),
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                    // Scroll Right Button
                    IconButton.filledTonal(
                      onPressed: () {
                        _horizontalScrollController.animateTo(
                          _horizontalScrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      },
                      icon: const Icon(Icons.arrow_forward_ios, size: 14),
                      tooltip: 'Scroll to Actions / Status',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFEFF6FF),
                        foregroundColor: const Color(0xFF1A3FC4),
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                    const SizedBox(width: 4),

                    // Export Button
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF10B981), Color(0xFF059669)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _isExporting ? null : _exportCustomers,
                        icon: _isExporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.file_download_outlined, size: 17),
                        label: Text(
                          _isExporting ? 'Exporting...' : 'Export',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    
                    // Add Customer Button
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F2557), Color(0xFF1A3FC4)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F2557).withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _editingCustomer = null;
                            _showAddCustomerOverlay = true;
                          });
                        },
                        icon: const Icon(Icons.person_add_alt_1, size: 17),
                        label: const Text(
                          'Add Customer',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    
                    // Bulk Import Button
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _showBulkImportOverlay = true;
                          });
                        },
                        icon: const Icon(Icons.upload_file_outlined, size: 17),
                        label: const Text(
                          'Bulk Import',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    
                    // Bulk Import Rosters Button
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFEC4899), Color(0xFFDB2777)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEC4899).withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _showBulkImportRostersOverlay = true;
                          });
                        },
                        icon: const Icon(Icons.calendar_today_outlined, size: 16),
                        label: const Text(
                          'Bulk Import Rosters',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    
                    // Refresh Button
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0D9488).withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => _refreshCustomers(),
                        icon: const Icon(Icons.refresh, size: 17),
                        label: const Text(
                          'Refresh',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Horizontal Drag Hint Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFEFF6FF),
              border: Border(
                bottom: BorderSide(color: Color(0xFFBFDBFE), width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.pan_tool_alt_outlined, size: 15, color: Color(0xFF1A3FC4)),
                const SizedBox(width: 8),
                const Text(
                  'Horizontal & Vertical Scrolling: Click and drag with mouse, use trackpad, or use the scrollbar below to scroll columns.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () {
                    _horizontalScrollController.animateTo(
                      _horizontalScrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  },
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Jump to Status & Actions',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A3FC4),
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward, size: 13, color: Color(0xFF1A3FC4)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Table Section with Visible Sticky Dual Scrollbars
          customers.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(56.0),
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Icon(Icons.people_outline, size: 36, color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      searchController.text.isNotEmpty
                        ? 'No customers match your search criteria'
                        : 'No customers found\nClick "Add Customer" to create one',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              )
            : Container(
                height: 560,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    dragDevices: {
                      PointerDeviceKind.touch,
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.trackpad,
                      PointerDeviceKind.stylus,
                    },
                  ),
                  child: RawScrollbar(
                    controller: _horizontalScrollController,
                    thumbVisibility: true,
                    trackVisibility: true,
                    thickness: 10,
                    radius: const Radius.circular(5),
                    thumbColor: const Color(0xFF1A3FC4),
                    trackColor: const Color(0xFFE2E8F0),
                    trackRadius: const Radius.circular(5),
                    scrollbarOrientation: ScrollbarOrientation.bottom,
                    child: SingleChildScrollView(
                      controller: _horizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 1200),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: DataTable(
                            border: const TableBorder(
                              horizontalInside: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                              verticalInside: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                              top: BorderSide(color: Color(0xFF0F2557), width: 1),
                              bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
                              left: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                              right: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                            ),
                            columnSpacing: 24,
                            horizontalMargin: 20,
                            headingRowHeight: 56,
                            dataRowMinHeight: 60,
                            dataRowMaxHeight: 64,
                            headingRowColor: WidgetStateProperty.all(
                              const Color(0xFF0F2557),
                            ),
                            headingTextStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                            dataRowColor: WidgetStateProperty.resolveWith<Color>((states) {
                              if (states.contains(WidgetState.hovered)) {
                                return const Color(0xFFEFF6FF);
                              }
                              return Colors.white;
                            }),
                          columns: const [
                            DataColumn(label: SizedBox(width: 110, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('EMPLOYEE ID')))),
                            DataColumn(label: SizedBox(width: 170, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('NAME')))),
                            DataColumn(label: SizedBox(width: 220, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('EMAIL')))),
                            DataColumn(label: SizedBox(width: 130, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('PHONE')))),
                            DataColumn(label: SizedBox(width: 160, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('COMPANY')))),
                            DataColumn(label: SizedBox(width: 150, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('DEPARTMENT')))),
                            DataColumn(label: SizedBox(width: 120, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('BRANCH')))),
                            DataColumn(label: SizedBox(width: 100, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('STATUS')))),
                            DataColumn(label: SizedBox(width: 120, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('ACTIONS')))),
                          ],
                          rows: customers.map((customer) {
                            final hasEmpId = customer.employeeId != null && 
                                             customer.employeeId!.trim().isNotEmpty && 
                                             customer.employeeId!.trim().toUpperCase() != 'N/A';
                            return DataRow(
                              cells: [
                                // Employee ID
                                DataCell(
                                  SizedBox(
                                    width: 110,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: hasEmpId
                                            ? Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF1F5F9),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: const Color(0xFFCBD5E1)),
                                                ),
                                                child: Text(
                                                  customer.employeeId!,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontFamily: 'monospace',
                                                    fontSize: 13,
                                                    color: Color(0xFF0F2557),
                                                  ),
                                                ),
                                              )
                                            : const Text(
                                                '—',
                                                style: TextStyle(
                                                  color: Color(0xFF94A3B8),
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                                
                                // Name
                                DataCell(
                                  SizedBox(
                                    width: 170,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor: const Color(0xFF0F2557),
                                            child: Text(
                                              customer.name.isNotEmpty 
                                                  ? customer.name[0].toUpperCase() 
                                                  : 'C',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              customer.name,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                                color: Color(0xFF1E293B),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                
                                // Email
                                DataCell(
                                  SizedBox(
                                    width: 220,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Text(
                                        customer.email,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                
                                // Phone
                                DataCell(
                                  SizedBox(
                                    width: 130,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Text(
                                        (customer.phoneNumber != null && customer.phoneNumber!.isNotEmpty)
                                            ? customer.phoneNumber!
                                            : '—',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF334155),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                
                                // Company Chip
                                DataCell(
                                  SizedBox(
                                    width: 160,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: (customer.companyName != null && customer.companyName!.isNotEmpty)
                                            ? Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFEEF2FF),
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: const Color(0xFFC7D2FE)),
                                                ),
                                                child: Text(
                                                  customer.companyName!,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF4338CA),
                                                  ),
                                                ),
                                              )
                                            : const Text('—', style: TextStyle(color: Color(0xFF94A3B8))),
                                      ),
                                    ),
                                  ),
                                ),
                                
                                // Department Chip
                                DataCell(
                                  SizedBox(
                                    width: 150,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: (customer.department != null && customer.department!.isNotEmpty)
                                            ? Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF1F5F9),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  customer.department!,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF475569),
                                                  ),
                                                ),
                                              )
                                            : const Text('—', style: TextStyle(color: Color(0xFF94A3B8))),
                                      ),
                                    ),
                                  ),
                                ),
                                
                                // Branch
                                DataCell(
                                  SizedBox(
                                    width: 120,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Text(
                                        (customer.branch != null && customer.branch!.isNotEmpty)
                                            ? customer.branch!
                                            : '—',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                
                                // Status Badge
                                DataCell(
                                  SizedBox(
                                    width: 100,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: _buildStatusBadge(customer.status),
                                      ),
                                    ),
                                  ),
                                ),
                                
                                // Actions
                                DataCell(
                                  SizedBox(
                                    width: 120,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // View Details
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEEF2FF),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFC7D2FE)),
                                            ),
                                            child: IconButton(
                                              onPressed: () => _navigateToDetails(customer),
                                              icon: const Icon(Icons.visibility, size: 15),
                                              color: const Color(0xFF1A3FC4),
                                              tooltip: 'View Details',
                                              padding: EdgeInsets.zero,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          
                                          // Edit
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFEF3C7),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFFCD34D)),
                                            ),
                                            child: IconButton(
                                              onPressed: () async {
                                                final canEdit = await PermissionRestrictedDialog.checkAndWarn(
                                                  context,
                                                  permissionKey: 'all_customers',
                                                  moduleName: 'customers',
                                                );
                                                if (!canEdit) return;
                                                if (!mounted) return;
                                                setState(() {
                                                  _editingCustomer = customer;
                                                  _showAddCustomerOverlay = true;
                                                });
                                              },
                                              icon: const Icon(Icons.edit, size: 15),
                                              color: const Color(0xFF92400E),
                                              tooltip: 'Edit Customer',
                                              padding: EdgeInsets.zero,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          
                                          // Delete
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFEE2E2),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: const Color(0xFFFCA5A5)),
                                            ),
                                            child: IconButton(
                                              onPressed: () => _deleteCustomer(customer),
                                              icon: const Icon(Icons.delete, size: 15),
                                              color: const Color(0xFF991B1B),
                                              tooltip: 'Delete Customer',
                                              padding: EdgeInsets.zero,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),      // DataTable
                      ),        // MouseRegion
                    ),          // ConstrainedBox
                  ),              // SingleChildScrollView (horizontal)
                ),                  // RawScrollbar (horizontal)
              ),                    // ScrollConfiguration
            ),                      // Container
          ],                      // Column children
        ),                        // Column
      );                          // outer Container
  }

  Widget _buildStatusBadge(String status) {
    Color backgroundColor;
    Color textColor;
    Color borderColor;
    String text = status;

    switch (status.toLowerCase()) {
      case 'active':
        backgroundColor = const Color(0xFFECFDF5);
        textColor = const Color(0xFF047857);
        borderColor = const Color(0xFFA7F3D0);
        break;
      case 'pending':
        backgroundColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFF92400E);
        borderColor = const Color(0xFFFCD34D);
        break;
      case 'inactive':
      case 'rejected':
      case 'deleted':
        backgroundColor = const Color(0xFFFEF2F2);
        textColor = const Color(0xFFB91C1C);
        borderColor = const Color(0xFFFECACA);
        break;
      default:
        backgroundColor = const Color(0xFFF1F5F9);
        textColor = const Color(0xFF475569);
        borderColor = const Color(0xFFCBD5E1);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildCustomerFormOverlay() {
    return CustomerFormOverlay(
      customer: _editingCustomer,
      onClose: () {
        if (mounted) {
          setState(() {
            _showAddCustomerOverlay = false;
            _editingCustomer = null;
          });
        }
      },
      onSaved: () async {
        if (mounted) {
          setState(() {
            _showAddCustomerOverlay = false;
            _editingCustomer = null;
          });
          await _refreshCustomers();
        }
      },
    );
  }

  Future<void> _refreshCustomers() async {
    if (!mounted) return;
    
    try {
      final provider = Provider.of<CustomerProvider>(context, listen: false);
      
      await provider.initialize();
      
      if (!mounted) return;
      
      await provider.fetchCustomers(
        status: selectedStatus != 'All' ? selectedStatus?.toLowerCase() : null,
        search: searchController.text.isNotEmpty ? searchController.text : null,
        organization: selectedOrganization != 'All Organizations' ? selectedOrganization : null,
        department: selectedDepartment != 'All Departments' ? selectedDepartment : null,
        city: _activeFilters['city']?.toString(),
        state: _activeFilters['state']?.toString(),
        country: _activeFilters['country']?.toString(),
        area: _activeFilters['area']?.toString(),
        startDate: _activeFilters['startDate'] != null ? (_activeFilters['startDate'] as DateTime).toIso8601String() : null,
        endDate: _activeFilters['endDate'] != null ? (_activeFilters['endDate'] as DateTime).toIso8601String() : null,
      );
      
      if (!mounted) return;
      
      print('âœ… Customers refreshed successfully');
    } catch (e) {
      print('âŒ Error refreshing customers: $e');
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Failed to refresh: ${e.toString()}'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _refreshCustomers(),
          ),
        ),
      );
    }
  }

  Widget _buildBulkImportOverlay() {
    return BulkImportOverlay(
      onClose: () {
        if (mounted) {
          setState(() {
            _showBulkImportOverlay = false;
          });
          
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              _refreshCustomers();
            }
          });
        }
      },
      onImported: () async {
        if (mounted) {
          setState(() {
            _showBulkImportOverlay = false;
          });
          
          await Future.delayed(const Duration(milliseconds: 1500));
          
          if (!mounted) return;
          
          await _refreshCustomers();
          
          if (mounted) {
            final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Import complete! ${customerProvider.customers.length} total customers',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.all(16),
                action: SnackBarAction(
                  label: 'View All',
                  textColor: Colors.white,
                  onPressed: () {
                    setState(() {
                      searchController.clear();
                      selectedOrganization = 'All Organizations';
                      selectedStatus = 'All';
                      selectedDepartment = 'All Departments';
                    });
                  },
                ),
              ),
            );
          }
        }
      },
    );
  }

  void _navigateToDetails(CustomerEntity customer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminCustomerDetailsScreen(
          customerId: customer.id,
        ),
      ),
    ).then((_) {
      _refreshCustomers();
    });
  }

  Future<void> _deleteCustomer(CustomerEntity customer) async {
    if (!mounted) return;
    
    final canDelete = await PermissionRestrictedDialog.checkAndWarn(
      context,
      permissionKey: 'all_customers',
      moduleName: 'customers',
    );
    if (!canDelete) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Delete Customer'),
          content: Text(
            'Are you sure you want to delete ${customer.name}?\n\nThis action cannot be undone.',
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
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (confirmed == true) {
      try {
        final provider = Provider.of<CustomerProvider>(context, listen: false);
        final success = await provider.deleteCustomer(customer.id);

        if (!mounted) return;

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${customer.name} deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          await _refreshCustomers();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete customer'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting customer: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}