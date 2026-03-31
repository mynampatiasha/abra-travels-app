// ============================================================================
// VENDORS LIST PAGE - FIXED VERSION
// ============================================================================
// File: lib/screens/billing/pages/vendors_list_page.dart
// 
// FIXES:
// 1. Improved CSV parsing with proper quote and comma handling
// 2. Fixed file picker to show all files including today's files
// 3. Better error handling and validation
// 4. Support for both .xlsx and .csv formats properly
// ============================================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'dart:typed_data';
import 'dart:convert';
import '../../../../core/utils/export_helper.dart';
import 'new_vendor.dart';
import '../../../../core/services/billing_vendors_service.dart';

class VendorsListPage extends StatefulWidget {
  const VendorsListPage({Key? key}) : super(key: key);

  @override
  State<VendorsListPage> createState() => _VendorsListPageState();
}

class _VendorsListPageState extends State<VendorsListPage> {
  // Search and Filter state
  final TextEditingController _searchController = TextEditingController();
  String selectedFilter = 'All Vendors';
  String selectedTypeFilter = 'All Types';
  String selectedStatusFilter = 'All Statuses';
  bool showAdvancedFilters = false;
  
  // Sort state
  String sortBy = 'createdDate';
  bool sortAscending = false;
  
  // Selection state
  Set<int> selectedRows = {};
  bool selectAll = false;
  
  // Loading state
  bool isLoading = false;
  String? errorMessage;
  
  // Filter options
  final List<String> quickFilters = [
    'All Vendors',
    'Active',
    'Inactive',
    'Blocked',
  ];
  
  final List<String> typeFilters = [
    'All Types',
    'Internal Employee',
    'External Vendor',
    'Contractor',
    'Freelancer',
  ];
  
  final List<String> statusFilters = [
    'All Statuses',
    'Active',
    'Inactive',
    'Blocked',
    'Pending Approval',
  ];
  
  // Sort options
  final List<String> sortOptions = [
    'Name',
    'Company Name',
    'Email',
    'Phone',
    'Created Date',
  ];
  
  // Vendor data from API
  List<VendorData> vendors = [];
  List<VendorData> filteredVendors = [];
  Map<String, dynamic>? statistics;
  
  @override
  void initState() {
    super.initState();
    _loadVendors();
    _searchController.addListener(_onSearchChanged);
  }
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  
  void _onSearchChanged() {
    _applyFiltersAndSearch();
  }
  
  // ============================================================================
  // LOAD VENDORS FROM API
  // ============================================================================
  
  Future<void> _loadVendors() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    
    try {
      print('\n🔄 Loading vendors from API...');
      
      final result = await BillingVendorsService.getAllVendors(
        sortBy: _getSortField(sortBy),
        sortOrder: sortAscending ? 'asc' : 'desc',
        limit: 1000,
      );
      
      if (result['success'] == true) {
        final data = result['data'];
        final vendorsList = data['vendors'] as List;
        
        setState(() {
          vendors = vendorsList.map((json) => VendorData.fromJson(json)).toList();
          statistics = data['statistics'];
          isLoading = false;
        });
        
        print('✅ Loaded ${vendors.length} vendors');
        _applyFiltersAndSearch();
      } else {
        throw Exception(result['message'] ?? 'Failed to load vendors');
      }
      
    } on BillingVendorsException catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = e.toUserMessage();
      });
      print('❌ BillingVendorsException: ${e.message}');
      _showError(e.toUserMessage());
      
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Failed to load vendors: ${e.toString()}';
      });
      print('❌ Error loading vendors: $e');
      _showError('Failed to load vendors. Please check your connection.');
    }
  }
  
  String _getSortField(String sortBy) {
    switch (sortBy) {
      case 'Name':
        return 'vendorName';
      case 'Company Name':
        return 'companyName';
      case 'Email':
        return 'email';
      case 'Phone':
        return 'phoneNumber';
      case 'Created Date':
        return 'createdDate';
      default:
        return 'createdDate';
    }
  }
  
  // ============================================================================
  // SEARCH AND FILTER LOGIC
  // ============================================================================
  
  void _applyFiltersAndSearch() {
    setState(() {
      filteredVendors = vendors.where((vendor) {
        // Search filter
        if (_searchController.text.isNotEmpty) {
          final searchLower = _searchController.text.toLowerCase();
          final matchesSearch = vendor.name.toLowerCase().contains(searchLower) ||
              vendor.companyName.toLowerCase().contains(searchLower) ||
              vendor.email.toLowerCase().contains(searchLower) ||
              vendor.phoneNumber.contains(searchLower);
          
          if (!matchesSearch) return false;
        }
        
        // Quick filter
        if (selectedFilter != 'All Vendors') {
          if (vendor.status != selectedFilter) return false;
        }
        
        // Type filter
        if (selectedTypeFilter != 'All Types') {
          if (vendor.type != selectedTypeFilter) return false;
        }
        
        // Status filter
        if (selectedStatusFilter != 'All Statuses') {
          if (vendor.status != selectedStatusFilter) return false;
        }
        
        return true;
      }).toList();
      
      // Clear selections when filters change
      selectedRows.clear();
      selectAll = false;
    });
  }
  
  void _clearFilters() {
    setState(() {
      _searchController.clear();
      selectedFilter = 'All Vendors';
      selectedTypeFilter = 'All Types';
      selectedStatusFilter = 'All Statuses';
      _applyFiltersAndSearch();
    });
  }
  
  // ============================================================================
  // ROW SELECTION
  // ============================================================================
  
  void _toggleSelectAll(bool? value) {
    setState(() {
      selectAll = value ?? false;
      if (selectAll) {
        selectedRows = Set.from(List.generate(filteredVendors.length, (i) => i));
      } else {
        selectedRows.clear();
      }
    });
  }
  
  void _toggleRowSelection(int index) {
    setState(() {
      if (selectedRows.contains(index)) {
        selectedRows.remove(index);
        selectAll = false;
      } else {
        selectedRows.add(index);
        if (selectedRows.length == filteredVendors.length) {
          selectAll = true;
        }
      }
    });
  }
  
  // ============================================================================
  // NAVIGATION
  // ============================================================================
  
  void _navigateToNewVendor() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewVendorPage(),
      ),
    );
    
    if (result == true) {
      _loadVendors();
    }
  }
  
  void _navigateToEditVendor(VendorData vendor) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewVendorPage(vendorId: vendor.id),
      ),
    );
    
    if (result == true) {
      _loadVendors();
    }
  }
  
  // ============================================================================
  // VIEW VENDOR DETAILS
  // ============================================================================
  
  Future<void> _viewVendorDetails(VendorData vendor) async {
    setState(() => isLoading = true);
    
    try {
      final result = await BillingVendorsService.getVendorById(vendor.id);
      setState(() => isLoading = false);
      
      if (result['success'] == true) {
        final fullVendorData = result['data'];
        
        showDialog(
          context: context,
          builder: (context) => VendorDetailsDialog(vendorData: fullVendorData),
        );
      } else {
        throw Exception(result['message'] ?? 'Failed to load vendor details');
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showError('Failed to load vendor details: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // DELETE FUNCTIONALITY
  // ============================================================================
  
  Future<void> _deleteVendor(VendorData vendor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Vendor'),
        content: Text(
          'Are you sure you want to delete "${vendor.name}"?\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      setState(() => isLoading = true);
      
      final result = await BillingVendorsService.deleteVendor(vendor.id);
      
      if (result['success'] == true) {
        _showSuccess('Vendor deleted successfully');
        _loadVendors();
      } else {
        throw Exception(result['message'] ?? 'Failed to delete vendor');
      }
    } on BillingVendorsException catch (e) {
      setState(() => isLoading = false);
      _showError(e.toUserMessage());
    } catch (e) {
      setState(() => isLoading = false);
      _showError('Failed to delete vendor: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // EXPORT FUNCTIONALITY
  // ============================================================================
  
  void _handleExport() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Vendors'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Export ${selectedRows.isEmpty ? filteredVendors.length : selectedRows.length} vendors',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            const Text('Select export format:'),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.table_chart),
              title: const Text('Excel (XLSX)'),
              onTap: () {
                Navigator.pop(context);
                _exportToExcel();
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('PDF'),
              onTap: () {
                Navigator.pop(context);
                _exportToPDF();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _exportToExcel() async {
    try {
      if (filteredVendors.isEmpty) {
        _showError('No vendors to export');
        return;
      }

      _showSuccess('Preparing Excel export...');

      List<List<dynamic>> csvData = [
        [
          'Vendor Name',
          'Company Name',
          'Type',
          'Status',
          'Email',
          'Phone Number',
          'Created Date',
        ],
      ];

      for (var vendor in filteredVendors) {
        csvData.add([
          vendor.name,
          vendor.companyName,
          vendor.type,
          vendor.status,
          vendor.email,
          vendor.phoneNumber,
          DateFormat('dd/MM/yyyy').format(vendor.createdDate),
        ]);
      }

      await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'vendors',
      );

      _showSuccess('✅ Excel file downloaded with ${filteredVendors.length} vendors!');
    } catch (e) {
      print('❌ Export Error: $e');
      _showError('Failed to export: $e');
    }
  }
  
  Future<void> _exportToPDF() async {
    try {
      if (filteredVendors.isEmpty) {
        _showError('No vendors to export');
        return;
      }

      _showSuccess('Preparing PDF export...');

      List<List<dynamic>> pdfData = [];
      for (var vendor in filteredVendors) {
        pdfData.add([
          vendor.name,
          vendor.companyName,
          vendor.email,
          vendor.phoneNumber,
          vendor.status,
        ]);
      }

      await ExportHelper.exportToPDF(
        title: 'Vendors Report',
        headers: ['Name', 'Company', 'Email', 'Phone', 'Status'],
        data: pdfData,
        filename: 'vendors',
      );

      _showSuccess('✅ PDF file downloaded with ${filteredVendors.length} vendors!');
    } catch (e) {
      print('❌ Export Error: $e');
      _showError('Failed to export PDF: $e');
    }
  }
  
  // ============================================================================
  // BULK IMPORT FUNCTIONALITY
  // ============================================================================
  
  void _handleBulkImport() {
    showDialog(
      context: context,
      builder: (context) => BulkImportDialog(
        onImportComplete: () {
          _loadVendors();
        },
      ),
    );
  }
  
  // ============================================================================
  // OTHER ACTIONS
  // ============================================================================
  
  void _handleRefresh() {
    _loadVendors();
    _showSuccess('List refreshed');
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }
  
  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Active':
        return Colors.green;
      case 'Inactive':
        return Colors.grey;
      case 'Blocked':
        return Colors.red;
      case 'Pending Approval':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }
  
  // ============================================================================
  // BUILD METHOD
  // ============================================================================
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Vendors'),
        backgroundColor: const Color(0xFF2C3E50),
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: Column(
        children: [
          // Top action bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by name, email, phone, company...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () => _searchController.clear(),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButton<String>(
                        value: selectedFilter,
                        underline: const SizedBox(),
                        icon: const Icon(Icons.arrow_drop_down, size: 20),
                        items: quickFilters.map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value, style: const TextStyle(fontSize: 14)),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            selectedFilter = newValue!;
                            _applyFiltersAndSearch();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          showAdvancedFilters = !showAdvancedFilters;
                        });
                      },
                      icon: Icon(
                        showAdvancedFilters ? Icons.filter_list_off : Icons.filter_list,
                        size: 18,
                      ),
                      label: Text(showAdvancedFilters ? 'Hide Filters' : 'Filters'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF3498DB),
                        side: const BorderSide(color: Color(0xFF3498DB)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _handleExport,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Export'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _handleBulkImport,
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('Bulk Import'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF9B59B6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: _handleRefresh,
                      icon: const Icon(Icons.refresh),
                      color: const Color(0xFF2C3E50),
                      tooltip: 'Refresh',
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _navigateToNewVendor,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3498DB),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
                if (showAdvancedFilters) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: DropdownButton<String>(
                                value: selectedTypeFilter,
                                isExpanded: true,
                                underline: const SizedBox(),
                                items: typeFilters.map((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value, style: const TextStyle(fontSize: 14)),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  setState(() {
                                    selectedTypeFilter = newValue!;
                                    _applyFiltersAndSearch();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[300]!),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: DropdownButton<String>(
                                value: selectedStatusFilter,
                                isExpanded: true,
                                underline: const SizedBox(),
                                items: statusFilters.map((String value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text(value, style: const TextStyle(fontSize: 14)),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  setState(() {
                                    selectedStatusFilter = newValue!;
                                    _applyFiltersAndSearch();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: ElevatedButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Clear'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          
          // Table
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: isLoading
                  ? _buildLoadingState()
                  : errorMessage != null
                      ? _buildErrorState()
                      : filteredVendors.isEmpty
                          ? _buildEmptyState()
                          : Column(
                              children: [
                                // Header row
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF34495E),
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(8),
                                      topRight: Radius.circular(8),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 40,
                                        child: Checkbox(
                                          value: selectAll,
                                          onChanged: _toggleSelectAll,
                                          activeColor: Colors.white,
                                          checkColor: const Color(0xFF34495E),
                                        ),
                                      ),
                                      const Expanded(
                                        flex: 2,
                                        child: Text('NAME', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 12)),
                                      ),
                                      const Expanded(
                                        flex: 2,
                                        child: Text('COMPANY NAME', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 12)),
                                      ),
                                      const Expanded(
                                        flex: 2,
                                        child: Text('EMAIL', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 12)),
                                      ),
                                      const Expanded(
                                        flex: 1,
                                        child: Text('PHONE', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 12)),
                                      ),
                                      const Expanded(
                                        flex: 1,
                                        child: Text('TYPE', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 12)),
                                      ),
                                      const Expanded(
                                        flex: 1,
                                        child: Text('STATUS', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 12)),
                                      ),
                                      const SizedBox(
                                        width: 140,
                                        child: Text('ACTIONS', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white, fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                ),
                                // Data rows
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: filteredVendors.length,
                                    itemBuilder: (context, index) {
                                      final vendor = filteredVendors[index];
                                      final isSelected = selectedRows.contains(index);
                                      
                                      return InkWell(
                                        onTap: () => _navigateToEditVendor(vendor),
                                        child: Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: isSelected ? const Color(0xFF3498DB).withOpacity(0.1) : Colors.white,
                                            border: Border(
                                              bottom: BorderSide(color: Colors.grey[200]!, width: 1),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(
                                                width: 40,
                                                child: Checkbox(
                                                  value: isSelected,
                                                  onChanged: (value) => _toggleRowSelection(index),
                                                  activeColor: const Color(0xFF3498DB),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  vendor.name,
                                                  style: const TextStyle(
                                                    color: Color(0xFF3498DB),
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  vendor.companyName.isNotEmpty ? vendor.companyName : '-',
                                                  style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(vendor.email, style: TextStyle(fontSize: 14, color: Colors.grey[800])),
                                              ),
                                              Expanded(
                                                flex: 1,
                                                child: Text(vendor.phoneNumber, style: TextStyle(fontSize: 14, color: Colors.grey[800])),
                                              ),
                                              Expanded(
                                                flex: 1,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF2C3E50).withOpacity(0.05),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    vendor.type,
                                                    style: const TextStyle(color: Color(0xFF2C3E50), fontSize: 12, fontWeight: FontWeight.w500),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 1,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: _getStatusColor(vendor.status).withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    vendor.status,
                                                    style: TextStyle(
                                                      color: _getStatusColor(vendor.status),
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 140,
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.visibility_outlined, size: 18),
                                                      color: const Color(0xFF2C3E50),
                                                      tooltip: 'View Details',
                                                      onPressed: () => _viewVendorDetails(vendor),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                                      color: const Color(0xFF3498DB),
                                                      tooltip: 'Edit',
                                                      onPressed: () => _navigateToEditVendor(vendor),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.delete_outline, size: 18),
                                                      color: Colors.red,
                                                      tooltip: 'Delete',
                                                      onPressed: () => _deleteVendor(vendor),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
            ),
          ),
          
          // Footer
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Text(
                  'Showing ${filteredVendors.length} of ${vendors.length} vendor${vendors.length != 1 ? 's' : ''}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                if (selectedRows.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  Text(
                    '(${selectedRows.length} selected)',
                    style: const TextStyle(color: Color(0xFF3498DB), fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('No vendors found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Text(
            _searchController.text.isNotEmpty ? 'No vendors match your filters' : 'Get started by adding your first vendor',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _navigateToNewVendor,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add Vendor'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3498DB))),
          SizedBox(height: 16),
          Text('Loading vendors...', style: TextStyle(fontSize: 16, color: Colors.grey)),
        ],
      ),
    );
  }
  
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 80, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text('Error Loading Vendors', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey[600])),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(errorMessage ?? 'An unexpected error occurred', style: TextStyle(fontSize: 14, color: Colors.grey[500]), textAlign: TextAlign.center),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadVendors,
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// VENDOR DETAILS DIALOG
// ============================================================================

class VendorDetailsDialog extends StatelessWidget {
  final Map<String, dynamic> vendorData;

  const VendorDetailsDialog({Key? key, required this.vendorData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: Color(0xFF3498DB), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vendorData['vendorName'] ?? 'Unknown',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)),
                      ),
                      Text(vendorData['vendorId'] ?? '', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(height: 32),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection('Basic Information', [
                      _buildInfoRow('Vendor Type', vendorData['vendorType']),
                      _buildInfoRow('Name', vendorData['vendorName']),
                      _buildInfoRow('Company Name', vendorData['companyName']),
                      _buildInfoRow('Email', vendorData['email']),
                      _buildInfoRow('Phone Number', vendorData['phoneNumber']),
                      _buildInfoRow('Alternate Phone', vendorData['alternatePhone']),
                      _buildInfoRow('Status', vendorData['status']),
                    ]),
                    const SizedBox(height: 24),
                    if (vendorData['bankDetailsProvided'] == true) ...[
                      _buildSection('Bank Details', [
                        _buildInfoRow('Account Holder Name', vendorData['accountHolderName']),
                        _buildInfoRow('Bank Name', vendorData['bankName']),
                        _buildInfoRow('Account Number', vendorData['accountNumber']),
                        _buildInfoRow('IFSC Code', vendorData['ifscCode']),
                      ]),
                      const SizedBox(height: 24),
                    ],
                    if (vendorData['addressProvided'] == true) ...[
                      _buildSection('Address', [
                        _buildInfoRow('Address Line 1', vendorData['addressLine1']),
                        _buildInfoRow('Address Line 2', vendorData['addressLine2']),
                        _buildInfoRow('City', vendorData['city']),
                        _buildInfoRow('State', vendorData['state']),
                        _buildInfoRow('Postal Code', vendorData['postalCode']),
                        _buildInfoRow('Country', vendorData['country']),
                      ]),
                      const SizedBox(height: 24),
                    ],
                    _buildSection('Additional Information', [
                      _buildInfoRow('GST Number', vendorData['gstNumber']),
                      _buildInfoRow('PAN Number', vendorData['panNumber']),
                      _buildInfoRow('Service Category', vendorData['serviceCategory']),
                      _buildInfoRow('Notes', vendorData['notes']),
                    ]),
                  ],
                ),
              ),
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
  
  Widget _buildInfoRow(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2C3E50), fontSize: 14)),
          ),
          Expanded(child: Text(value.toString(), style: TextStyle(color: Colors.grey[800], fontSize: 14))),
        ],
      ),
    );
  }
}

// ============================================================================
// BULK IMPORT DIALOG - FIXED VERSION
// ============================================================================

class BulkImportDialog extends StatefulWidget {
  final VoidCallback onImportComplete;

  const BulkImportDialog({
    Key? key,
    required this.onImportComplete,
  }) : super(key: key);

  @override
  State<BulkImportDialog> createState() => _BulkImportDialogState();
}

class _BulkImportDialogState extends State<BulkImportDialog> {
  bool isDownloading = false;
  bool isUploading = false;
  String? uploadedFileName;
  List<Map<String, dynamic>>? importResults;
  
  // ============================================================================
  // HELPER: PARSE SCIENTIFIC NOTATION TO PHONE NUMBER
  // ============================================================================
  
  String _parsePhoneNumber(dynamic value) {
    if (value == null) return '';
    
    String strValue = value.toString().trim();
    if (strValue.isEmpty) return '';
    
    // Check if it's in scientific notation (e.g., 9.88E+09)
    if (strValue.toUpperCase().contains('E')) {
      try {
        // Parse as double and convert to integer string
        double numValue = double.parse(strValue);
        // Convert to integer (remove decimal point)
        int intValue = numValue.round();
        return intValue.toString();
      } catch (e) {
        print('⚠️ Failed to parse scientific notation: $strValue');
        return strValue; // Return original if parsing fails
      }
    }
    
    // Remove any decimal points for regular numbers
    if (strValue.contains('.')) {
      try {
        double numValue = double.parse(strValue);
        int intValue = numValue.round();
        return intValue.toString();
      } catch (e) {
        return strValue;
      }
    }
    
    return strValue;
  }
  
  // ============================================================================
  // DOWNLOAD SAMPLE TEMPLATE
  // ============================================================================
  
  Future<void> _downloadTemplate() async {
    setState(() => isDownloading = true);
    
    try {
      // Create sample Excel template with headers and example data
      List<List<dynamic>> templateData = [
        // Headers
        [
          'Vendor Type*',
          'Vendor Name*',
          'Company Name',
          'Email*',
          'Phone Number*',
          'Alternate Phone',
          'Status',
          'Bank Details Provided (Yes/No)',
          'Account Holder Name',
          'Bank Name',
          'Account Number',
          'IFSC Code',
          'Address Provided (Yes/No)',
          'Address Line 1',
          'Address Line 2',
          'City',
          'State',
          'Postal Code',
          'Country',
          'GST Number',
          'PAN Number',
          'Service Category',
          'Notes',
        ],
        // Example row 1
        [
          'External Vendor',
          'John Doe',
          'ABC Transport',
          'john@abctransport.com',
          '9876543210',
          '9876543211',
          'Active',
          'Yes',
          'John Doe',
          'HDFC Bank',
          '12345678901234',
          'HDFC0001234',
          'Yes',
          '123 Main Street',
          'Apartment 4B',
          'Bangalore',
          'Karnataka',
          '560001',
          'India',
          '29ABCDE1234F1Z5',
          'ABCDE1234F',
          'Logistics',
          'Preferred vendor for North routes',
        ],
        // Example row 2
        [
          'Internal Employee',
          'Jane Smith',
          '',
          'jane.smith@company.com',
          '9123456789',
          '',
          'Active',
          'No',
          '',
          '',
          '',
          '',
          'No',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          'HR Department',
          'Internal HR staff',
        ],
        // Instructions row
        [
          'INSTRUCTIONS:',
          '1. Fields marked with * are required',
          '2. Vendor Type: Internal Employee, External Vendor, Contractor, or Freelancer',
          '3. Status: Active, Inactive, Blocked, or Pending Approval',
          '4. Phone should be 10 digits',
          '5. Email must be valid format',
          '6. If Bank Details Provided = Yes, fill Account Holder Name, Bank Name, Account Number, IFSC Code',
          '7. IFSC Code must be 11 characters (e.g., HDFC0001234)',
          '8. PAN Number must be 10 characters (e.g., ABCDE1234F)',
          '9. Delete this instruction row before uploading',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
          '',
        ],
      ];
      
      await ExportHelper.exportToExcel(
        data: templateData,
        filename: 'vendors_import_template',
      );
      
      setState(() => isDownloading = false);
      
      _showSuccess('Template downloaded successfully!');
    } catch (e) {
      setState(() => isDownloading = false);
      _showError('Failed to download template: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // UPLOAD AND IMPORT FILE - FIXED VERSION
  // ============================================================================
  
  Future<void> _uploadFile() async {
    try {
      print('📁 Opening file picker...');
      
      // FIXED: Allow both XLSX and CSV files with better configuration
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false,
        withData: true, // This ensures we get the file bytes
        withReadStream: false,
      );
      
      print('📁 File picker result: ${result != null ? "File selected" : "Cancelled"}');
      
      if (result == null || result.files.isEmpty) {
        print('❌ No file selected');
        return;
      }
      
      final file = result.files.first;
      print('✅ Selected file: ${file.name}, Extension: ${file.extension}, Size: ${file.size} bytes');
      
      setState(() {
        uploadedFileName = file.name;
        isUploading = true;
        importResults = null;
      });
      
      // Read file bytes
      Uint8List? bytes = file.bytes;
      if (bytes == null) {
        print('❌ Failed to read file bytes - trying path method');
        throw Exception('Failed to read file. Please try again.');
      }
      
      print('✅ File bytes read successfully: ${bytes.length} bytes');
      
      // Determine file type and parse accordingly
      List<List<dynamic>> rows;
      final extension = file.extension?.toLowerCase() ?? '';
      
      print('🔍 Processing file type: $extension');
      
      if (extension == 'csv') {
        print('📊 Parsing as CSV...');
        rows = _parseCSVImproved(bytes);
      } else if (extension == 'xlsx' || extension == 'xls') {
        print('📊 Parsing as Excel...');
        rows = _parseExcel(bytes);
      } else {
        throw Exception('Unsupported file format. Please use .xlsx, .xls, or .csv files only.');
      }
      
      print('✅ Parsed ${rows.length} rows from file');
      
      if (rows.isEmpty) {
        throw Exception('File is empty or could not be read');
      }
      
      if (rows.length < 2) {
        throw Exception('File must contain at least a header row and one data row');
      }
      
      // Log first few rows for debugging
      print('📋 First row (headers): ${rows[0]}');
      if (rows.length > 1) {
        print('📋 Second row (data): ${rows[1]}');
      }
      
      // Skip header row and parse data
      List<Map<String, dynamic>> vendorsToImport = [];
      List<String> errors = [];
      
      for (int i = 1; i < rows.length; i++) {
        try {
          var row = rows[i];
          
          // Skip empty rows or instruction rows
          if (row.isEmpty || 
              row[0] == null ||
              row[0].toString().trim().isEmpty ||
              row[0].toString().toUpperCase().contains('INSTRUCTION')) {
            print('⏭️ Skipping row $i (empty or instruction)');
            continue;
          }
          
          print('🔄 Processing row $i: ${row.take(5).join(", ")}...');
          
          // Parse vendor data with safe access
          String vendorType = _getStringValue(row, 0);
          String vendorName = _getStringValue(row, 1);
          String companyName = _getStringValue(row, 2);
          String email = _getStringValue(row, 3);
          String phoneNumber = _parsePhoneNumber(_getValue(row, 4));
          String alternatePhone = _parsePhoneNumber(_getValue(row, 5));
          String status = _getStringValue(row, 6, 'Active');
          
          bool bankDetailsProvided = _getStringValue(row, 7).toLowerCase() == 'yes';
          String accountHolderName = _getStringValue(row, 8);
          String bankName = _getStringValue(row, 9);
          String accountNumber = _parsePhoneNumber(_getValue(row, 10));
          String ifscCode = _getStringValue(row, 11);
          
          bool addressProvided = _getStringValue(row, 12).toLowerCase() == 'yes';
          String addressLine1 = _getStringValue(row, 13);
          String addressLine2 = _getStringValue(row, 14);
          String city = _getStringValue(row, 15);
          String state = _getStringValue(row, 16);
          String postalCode = _getStringValue(row, 17);
          String country = _getStringValue(row, 18, 'India');
          
          String gstNumber = _getStringValue(row, 19);
          String panNumber = _getStringValue(row, 20);
          String serviceCategory = _getStringValue(row, 21);
          String notes = _getStringValue(row, 22);
          
          // Validate required fields
          List<String> rowErrors = [];
          
          if (vendorType.isEmpty) {
            rowErrors.add('Vendor Type is required');
          }
          if (vendorName.isEmpty) {
            rowErrors.add('Vendor Name is required');
          }
          if (email.isEmpty) {
            rowErrors.add('Email is required');
          } else if (!_isValidEmail(email)) {
            rowErrors.add('Invalid email format');
          }
          if (phoneNumber.isEmpty) {
            rowErrors.add('Phone Number is required');
          } else if (phoneNumber.length != 10) {
            rowErrors.add('Phone Number must be 10 digits');
          }
          
          if (rowErrors.isNotEmpty) {
            errors.add('Row ${i + 1}: ${rowErrors.join(", ")}');
            print('❌ Row $i validation failed: ${rowErrors.join(", ")}');
            continue;
          }
          
          print('✅ Row $i validated successfully');
          
          vendorsToImport.add({
            'vendorType': vendorType,
            'vendorName': vendorName,
            'companyName': companyName,
            'email': email,
            'phoneNumber': phoneNumber,
            'alternatePhone': alternatePhone,
            'status': status,
            'bankDetailsProvided': bankDetailsProvided,
            'accountHolderName': accountHolderName,
            'bankName': bankName,
            'accountNumber': accountNumber,
            'ifscCode': ifscCode,
            'addressProvided': addressProvided,
            'addressLine1': addressLine1,
            'addressLine2': addressLine2,
            'city': city,
            'state': state,
            'postalCode': postalCode,
            'country': country,
            'gstNumber': gstNumber,
            'panNumber': panNumber,
            'serviceCategory': serviceCategory,
            'notes': notes,
          });
        } catch (e) {
          errors.add('Row ${i + 1}: ${e.toString()}');
          print('❌ Error processing row $i: $e');
        }
      }
      
      print('📊 Import Summary:');
      print('  - Total rows processed: ${rows.length - 1}');
      print('  - Valid vendors: ${vendorsToImport.length}');
      print('  - Errors: ${errors.length}');
      
      if (vendorsToImport.isEmpty) {
        throw Exception('No valid vendor data found in the file. Please check the format and required fields.');
      }
      
      // Show confirmation dialog with count
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Import'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Found ${vendorsToImport.length} vendor(s) to import.',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '${errors.length} row(s) skipped due to errors:',
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: Text(
                        errors.join('\n'),
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text('Do you want to proceed with the import?'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3498DB),
              ),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      
      if (confirmed != true) {
        setState(() {
          isUploading = false;
          uploadedFileName = null;
        });
        return;
      }
      
      print('🚀 Starting bulk import API call...');
      
      // Call bulk import API
      final importResult = await BillingVendorsService.bulkImportVendors(vendorsToImport);
      
      print('✅ Bulk import completed: ${importResult['data']}');
      
      setState(() {
        isUploading = false;
        importResults = [
          {
            'success': importResult['data']['successCount'],
            'failed': importResult['data']['failedCount'],
            'total': importResult['data']['totalProcessed'],
            'errors': importResult['data']['errors'] ?? [],
          }
        ];
      });
      
      if (importResult['success'] == true) {
        _showSuccess('Import completed successfully!');
        widget.onImportComplete();
      }
    } catch (e, stackTrace) {
      print('❌ Upload Error: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        isUploading = false;
        uploadedFileName = null;
      });
      _showError('Failed to import: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // HELPER: SAFE VALUE EXTRACTION
  // ============================================================================
  
  dynamic _getValue(List<dynamic> row, int index) {
    if (index >= row.length) return null;
    return row[index];
  }
  
  String _getStringValue(List<dynamic> row, int index, [String defaultValue = '']) {
    if (index >= row.length) return defaultValue;
    final value = row[index];
    if (value == null) return defaultValue;
    return value.toString().trim();
  }
  
  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }
  
  // ============================================================================
  // PARSE EXCEL FILE
  // ============================================================================
  
  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    try {
      print('📊 Decoding Excel file...');
      var excel = excel_pkg.Excel.decodeBytes(bytes);
      
      print('📊 Excel sheets: ${excel.tables.keys.join(", ")}');
      
      // Get first sheet
      var sheet = excel.tables.keys.first;
      var rows = excel.tables[sheet]?.rows;
      
      if (rows == null || rows.isEmpty) {
        throw Exception('Excel file is empty');
      }
      
      print('📊 Found ${rows.length} rows in Excel');
      
      // Convert Excel rows to List<List<dynamic>>
      List<List<dynamic>> result = rows.map((row) {
        return row.map((cell) {
          // Handle different cell value types
          if (cell?.value == null) return '';
          
          // For TextCellValue, extract the actual text
          if (cell!.value is excel_pkg.TextCellValue) {
            return (cell.value as excel_pkg.TextCellValue).value;
          }
          
          // For other types, use the value directly
          return cell.value;
        }).toList();
      }).toList();
      
      print('✅ Excel parsed successfully');
      return result;
    } catch (e, stackTrace) {
      print('❌ Excel parsing error: $e');
      print('Stack trace: $stackTrace');
      throw Exception('Failed to parse Excel file: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // PARSE CSV FILE - IMPROVED VERSION
  // ============================================================================
  
  List<List<dynamic>> _parseCSVImproved(Uint8List bytes) {
    try {
      print('📊 Decoding CSV file...');
      
      // Convert bytes to string with UTF-8 encoding
      String csvString = utf8.decode(bytes, allowMalformed: true);
      
      print('📊 CSV file size: ${csvString.length} characters');
      
      // Split into lines (handle both \r\n and \n)
      List<String> lines = csvString.split(RegExp(r'\r?\n'));
      
      print('📊 Found ${lines.length} lines in CSV');
      
      // Parse each line with proper CSV handling
      List<List<dynamic>> rows = [];
      
      for (int i = 0; i < lines.length; i++) {
        String line = lines[i].trim();
        
        if (line.isEmpty) {
          continue;
        }
        
        // Parse CSV line handling quotes and commas
        List<String> fields = _parseCSVLine(line);
        
        if (i == 0) {
          print('📋 CSV Headers: ${fields.join(" | ")}');
        }
        
        rows.add(fields);
      }
      
      print('✅ CSV parsed successfully: ${rows.length} rows');
      return rows;
    } catch (e, stackTrace) {
      print('❌ CSV parsing error: $e');
      print('Stack trace: $stackTrace');
      throw Exception('Failed to parse CSV file: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // PARSE CSV LINE (PROPER CSV PARSING WITH QUOTES)
  // ============================================================================
  
  List<String> _parseCSVLine(String line) {
    List<String> fields = [];
    StringBuffer currentField = StringBuffer();
    bool inQuotes = false;
    
    for (int i = 0; i < line.length; i++) {
      String char = line[i];
      
      if (char == '"') {
        // Toggle quote state
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          // Escaped quote (two consecutive quotes)
          currentField.write('"');
          i++; // Skip next quote
        } else {
          // Start or end of quoted field
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        // Field separator (only when not in quotes)
        fields.add(currentField.toString().trim());
        currentField.clear();
      } else {
        // Regular character
        currentField.write(char);
      }
    }
    
    // Add last field
    fields.add(currentField.toString().trim());
    
    // Remove surrounding quotes from fields if present
    return fields.map((field) {
      if (field.startsWith('"') && field.endsWith('"')) {
        return field.substring(1, field.length - 1);
      }
      return field;
    }).toList();
  }
  
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }
  
  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.upload_file, color: Color(0xFF9B59B6), size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Bulk Import Vendors',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 32),
            
            // Instructions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'How to Import',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Download the sample template\n'
                    '2. Fill in your vendor data\n'
                    '3. Upload the completed file (.xlsx, .xls, or .csv)\n'
                    '4. Review and confirm the import',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Download Template Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isDownloading || isUploading ? null : _downloadTemplate,
                icon: isDownloading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.download),
                label: Text(isDownloading ? 'Downloading...' : 'Download Sample Template'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3498DB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Upload File Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isDownloading || isUploading ? null : _uploadFile,
                icon: isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF9B59B6)),
                        ),
                      )
                    : const Icon(Icons.upload_file),
                label: Text(
                  isUploading 
                      ? 'Processing...' 
                      : 'Upload Excel or CSV File',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF9B59B6),
                  side: const BorderSide(color: Color(0xFF9B59B6)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            
            if (uploadedFileName != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.green[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        uploadedFileName!,
                        style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // Import Results
            if (importResults != null) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text(
                'Import Results',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    _buildResultRow('Total Processed', importResults![0]['total'].toString(), Colors.blue),
                    const SizedBox(height: 8),
                    _buildResultRow('Successfully Imported', importResults![0]['success'].toString(), Colors.green),
                    const SizedBox(height: 8),
                    _buildResultRow('Failed', importResults![0]['failed'].toString(), Colors.red),
                    if ((importResults![0]['errors'] as List).isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Errors:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: SingleChildScrollView(
                          child: Text(
                            (importResults![0]['errors'] as List).join('\n'),
                            style: const TextStyle(fontSize: 12, color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3498DB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Close'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildResultRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// DATA MODEL
// ============================================================================

class VendorData {
  final String id;
  final String name;
  final String companyName;
  final String email;
  final String phoneNumber;
  final String status;
  final String type;
  final DateTime createdDate;
  
  VendorData({
    required this.id,
    required this.name,
    required this.companyName,
    required this.email,
    required this.phoneNumber,
    required this.status,
    required this.type,
    required this.createdDate,
  });
  
  factory VendorData.fromJson(Map<String, dynamic> json) {
    return VendorData(
      id: json['_id'] ?? json['vendorId'] ?? '',
      name: json['vendorName'] ?? '',
      companyName: json['companyName'] ?? '',
      email: json['email'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      status: json['status'] ?? 'Active',
      type: json['vendorType'] ?? 'External Vendor',
      createdDate: json['createdDate'] != null ? DateTime.parse(json['createdDate']) : DateTime.now(),
    );
  }
}