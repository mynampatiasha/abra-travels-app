// ============================================================================
// ITEMS BILLING PAGE - WITH BULK IMPORT FUNCTIONALITY
// ============================================================================
// File: lib/features/admin/Billing/pages/items_billing.dart
// 
// Features:
// - Search functionality
// - Advanced filters
// - Export button (Excel, PDF, CSV)
// - Bulk Import button (Excel/CSV)
// - Refresh button
// - Full-page table
// - Edit/Delete buttons
// - Same layout as vendors_list_page.dart
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'dart:typed_data';
import 'dart:convert';
import '../../../../core/utils/export_helper.dart';
import 'new_item_billing.dart';
import '../../../../core/services/item_billing_service.dart';

class ItemsBilling extends StatefulWidget {
  const ItemsBilling({Key? key}) : super(key: key);

  @override
  State<ItemsBilling> createState() => _ItemsBillingState();
}

class _ItemsBillingState extends State<ItemsBilling> {
  final ItemBillingService _itemService = ItemBillingService();
  
  // Search and Filter state
  final TextEditingController _searchController = TextEditingController();
  String selectedFilter = 'All Items';
  String selectedTypeFilter = 'All Types';
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
    'All Items',
    'Active Items',
    'Inactive Items',
  ];
  
  final List<String> typeFilters = [
    'All Types',
    'Service',
    'Goods',
  ];
  
  // Item data from API
  List<ItemData> items = [];
  List<ItemData> filteredItems = [];
  
  @override
  void initState() {
    super.initState();
    _loadItems();
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
  // LOAD ITEMS FROM API
  // ============================================================================
  
  Future<void> _loadItems() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });
    
    try {
      print('\n🔄 Loading items from API...');
      
      final result = await _itemService.fetchAllItems();
      
      setState(() {
        items = result.map((json) => ItemData.fromJson(json)).toList();
        isLoading = false;
      });
      
      print('✅ Loaded ${items.length} items');
      _applyFiltersAndSearch();
      
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = 'Failed to load items: ${e.toString()}';
      });
      print('❌ Error loading items: $e');
      _showError('Failed to load items. Please check your connection.');
    }
  }
  
  // ============================================================================
  // SEARCH AND FILTER LOGIC
  // ============================================================================
  
  void _applyFiltersAndSearch() {
    setState(() {
      filteredItems = items.where((item) {
        // Search filter
        if (_searchController.text.isNotEmpty) {
          final searchLower = _searchController.text.toLowerCase();
          final matchesSearch = item.name.toLowerCase().contains(searchLower) ||
              (item.description?.toLowerCase().contains(searchLower) ?? false);
          
          if (!matchesSearch) return false;
        }
        
        // Quick filter
        if (selectedFilter == 'Active Items') {
          if (item.status != 'Active') return false;
        } else if (selectedFilter == 'Inactive Items') {
          if (item.status != 'Inactive') return false;
        }
        
        // Type filter
        if (selectedTypeFilter != 'All Types') {
          if (item.type != selectedTypeFilter) return false;
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
      selectedFilter = 'All Items';
      selectedTypeFilter = 'All Types';
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
        selectedRows = Set.from(List.generate(filteredItems.length, (i) => i));
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
        if (selectedRows.length == filteredItems.length) {
          selectAll = true;
        }
      }
    });
  }
  
  // ============================================================================
  // NAVIGATION
  // ============================================================================
  
  void _navigateToNewItem() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const NewItemBilling(),
      ),
    );
    
    if (result == true) {
      _loadItems();
    }
  }
  
  void _navigateToEditItem(ItemData item) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewItemBilling(itemToEdit: item.toJson()),
      ),
    );
    
    if (result == true) {
      _loadItems();
    }
  }
  
  // ============================================================================
  // DELETE FUNCTIONALITY
  // ============================================================================
  
  Future<void> _deleteItem(ItemData item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item'),
        content: Text(
          'Are you sure you want to delete "${item.name}"?\n\n'
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
      
      await _itemService.deleteItem(item.id);
      _showSuccess('Item deleted successfully');
      _loadItems();
      
    } catch (e) {
      setState(() => isLoading = false);
      _showError('Failed to delete item: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // EXPORT FUNCTIONALITY
  // ============================================================================
  
  void _handleExport() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Items'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Export ${selectedRows.isEmpty ? filteredItems.length : selectedRows.length} items',
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
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('CSV'),
              onTap: () {
                Navigator.pop(context);
                _exportToCSV();
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
      if (filteredItems.isEmpty) {
        _showError('No items to export');
        return;
      }

      _showSuccess('Preparing Excel export...');

      // Prepare data for export
      List<List<dynamic>> csvData = [
        // Headers
        [
          'Item Name',
          'Type',
          'Unit',
          'Selling Price',
          'Cost Price',
          'Status',
          'Created Date',
        ],
      ];

      print('📊 Exporting ${filteredItems.length} items...');

      // Add data rows
      for (var item in filteredItems) {
        csvData.add([
          item.name,
          item.type,
          item.unit ?? '',
          item.sellingPrice.toStringAsFixed(2),
          item.costPrice?.toStringAsFixed(2) ?? '0.00',
          item.status,
          DateFormat('dd/MM/yyyy').format(item.createdDate),
        ]);
      }

      // Use ExportHelper to export
      await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'items',
      );

      _showSuccess('✅ Excel file downloaded with ${filteredItems.length} items!');
    } catch (e) {
      print('❌ Export Error: $e');
      _showError('Failed to export: $e');
    }
  }
  
  Future<void> _exportToPDF() async {
    try {
      if (filteredItems.isEmpty) {
        _showError('No items to export');
        return;
      }

      _showSuccess('Preparing PDF export...');

      // Prepare data for PDF (limited columns for better fit)
      List<List<dynamic>> pdfData = [];
      for (var item in filteredItems) {
        pdfData.add([
          item.name,
          item.type,
          item.sellingPrice.toStringAsFixed(2),
          item.status,
        ]);
      }

      // Use ExportHelper to export
      await ExportHelper.exportToPDF(
        title: 'Items Report',
        headers: ['Name', 'Type', 'Price', 'Status'],
        data: pdfData,
        filename: 'items',
      );

      _showSuccess('✅ PDF file downloaded with ${filteredItems.length} items!');
    } catch (e) {
      print('❌ Export Error: $e');
      _showError('Failed to export PDF: $e');
    }
  }
  
  Future<void> _exportToCSV() async {
    // CSV is same as Excel for now
    await _exportToExcel();
  }
  
  // ============================================================================
  // BULK IMPORT FUNCTIONALITY
  // ============================================================================
  
  void _handleBulkImport() {
    showDialog(
      context: context,
      builder: (context) => BulkImportDialog(
        onImportComplete: () {
          _loadItems();
        },
      ),
    );
  }
  
  // ============================================================================
  // OTHER ACTIONS
  // ============================================================================
  
  void _handleRefresh() {
    _loadItems();
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
        title: const Text('Items'),
        backgroundColor: const Color(0xFF2C3E50),
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: Column(
        children: [
          // Top action bar with search and filters
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // First row: Search, Filters, Actions
                Row(
                  children: [
                    // Search field
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search by name, description...',
                          prefixIcon: const Icon(Icons.search, size: 20),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  onPressed: () {
                                    _searchController.clear();
                                  },
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
                    
                    // Quick filter dropdown
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
                    
                    // Advanced filters button
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
                    
                    // Export button
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
                    
                    // Bulk Import button
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
                    
                    // Refresh button
                    IconButton(
                      onPressed: _handleRefresh,
                      icon: const Icon(Icons.refresh),
                      color: const Color(0xFF2C3E50),
                      tooltip: 'Refresh',
                    ),
                    
                    const SizedBox(width: 12),
                    
                    // New button
                    ElevatedButton.icon(
                      onPressed: _navigateToNewItem,
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
                
                // Advanced filters (shown when toggled)
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
          
          // Table (full height)
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
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
                      : filteredItems.isEmpty
                          ? _buildEmptyState()
                          : Column(
                              children: [
                                // Header row
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF34495E), // Dark blue-grey like customers
                                    borderRadius: const BorderRadius.only(
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
                                        flex: 3,
                                        child: Text(
                                          'ITEM NAME',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const Expanded(
                                        flex: 1,
                                        child: Text(
                                          'TYPE',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const Expanded(
                                        flex: 2,
                                        child: Text(
                                          'SELLING PRICE',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const Expanded(
                                        flex: 1,
                                        child: Text(
                                          'STATUS',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(
                                        width: 100,
                                        child: Text(
                                          'ACTIONS',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Data rows
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: filteredItems.length,
                                    itemBuilder: (context, index) {
                                      final item = filteredItems[index];
                                      final isSelected = selectedRows.contains(index);
                                      
                                      return InkWell(
                                        onTap: () => _navigateToEditItem(item),
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
                                                  onChanged: (value) {
                                                    _toggleRowSelection(index);
                                                  },
                                                  activeColor: const Color(0xFF3498DB),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      item.name,
                                                      style: const TextStyle(
                                                        color: Color(0xFF3498DB),
                                                        fontWeight: FontWeight.w500,
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                    if (item.description != null && item.description!.isNotEmpty)
                                                      Text(
                                                        item.description!,
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors.grey[600],
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              Expanded(
                                                flex: 1,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: item.type == 'Service' 
                                                        ? Colors.blue[50] 
                                                        : Colors.green[50],
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    item.type,
                                                    style: TextStyle(
                                                      color: item.type == 'Service' 
                                                          ? Colors.blue[700] 
                                                          : Colors.green[700],
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  '₹${item.sellingPrice.toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 1,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: _getStatusColor(item.status).withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    item.status,
                                                    style: TextStyle(
                                                      color: _getStatusColor(item.status),
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ),
                                              SizedBox(
                                                width: 100,
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.edit_outlined, size: 18),
                                                      color: const Color(0xFF3498DB),
                                                      tooltip: 'Edit',
                                                      onPressed: () => _navigateToEditItem(item),
                                                    ),
                                                    IconButton(
                                                      icon: const Icon(Icons.delete_outline, size: 18),
                                                      color: Colors.red,
                                                      tooltip: 'Delete',
                                                      onPressed: () => _deleteItem(item),
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
          
          // Footer with count
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              children: [
                Text(
                  'Showing ${filteredItems.length} of ${items.length} item${items.length != 1 ? 's' : ''}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                if (selectedRows.isNotEmpty) ...[
                  const SizedBox(width: 16),
                  Text(
                    '(${selectedRows.length} selected)',
                    style: const TextStyle(
                      color: Color(0xFF3498DB),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
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
          Icon(
            Icons.inventory_2_outlined,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No items found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchController.text.isNotEmpty || 
            selectedFilter != 'All Items' ||
            selectedTypeFilter != 'All Types'
                ? 'No items match your filters'
                : 'Get started by adding your first item',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _navigateToNewItem,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add Item'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 16,
              ),
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
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3498DB)),
          ),
          SizedBox(height: 16),
          Text(
            'Loading items...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 80,
            color: Colors.red[300],
          ),
          const SizedBox(height: 16),
          Text(
            'Error Loading Items',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              errorMessage ?? 'An unexpected error occurred',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadItems,
            icon: const Icon(Icons.refresh, size: 20),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// BULK IMPORT DIALOG FOR ITEMS
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
  final ItemBillingService _itemService = ItemBillingService();
  bool isDownloading = false;
  bool isUploading = false;
  String? uploadedFileName;
  List<Map<String, dynamic>>? importResults;
  
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
          'Item Name*',
          'Type*',
          'Unit',
          'Selling Price*',
          'Cost Price',
          'Sales Description',
          'Purchase Description',
          'Status',
        ],
        // Example row 1 - Goods
        [
          'Apple iPhone 15 Pro',
          'Goods',
          'pcs',
          '129999.00',
          '110000.00',
          'Latest flagship smartphone with titanium design',
          'iPhone 15 Pro 256GB - Black Titanium',
          'Active',
        ],
        // Example row 2 - Service
        [
          'Web Development Service',
          'Service',
          'hour',
          '5000.00',
          '3000.00',
          'Professional web development and design services',
          'Hourly rate for web development',
          'Active',
        ],
        // Example row 3 - Goods with unit
        [
          'Premium Coffee Beans',
          'Goods',
          'kg',
          '899.00',
          '650.00',
          'Arabica coffee beans - Medium roast',
          'Coffee beans bulk purchase',
          'Active',
        ],
        // Instructions row
        [
          'INSTRUCTIONS:',
          '1. Fields marked with * are required',
          '2. Type: Must be either "Goods" or "Service"',
          '3. Unit: pcs, dz, kg, ltr, box, carton, unit, hour, etc.',
          '4. Prices should be numbers (decimal allowed)',
          '5. Status: Active or Inactive (default: Active)',
          '6. Delete this instruction row before uploading',
          '',
          '',
        ],
      ];
      
      await ExportHelper.exportToExcel(
        data: templateData,
        filename: 'items_import_template',
      );
      
      setState(() => isDownloading = false);
      
      _showSuccess('Template downloaded successfully!');
    } catch (e) {
      setState(() => isDownloading = false);
      _showError('Failed to download template: ${e.toString()}');
    }
  }
  
  // ============================================================================
  // UPLOAD AND IMPORT FILE
  // ============================================================================
  
  Future<void> _uploadFile() async {
    try {
      print('📁 Opening file picker...');
      
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false,
        withData: true,
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
      List<Map<String, dynamic>> itemsToImport = [];
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
          
          // Parse item data with safe access
          String itemName = _getStringValue(row, 0);
          String itemType = _getStringValue(row, 1);
          String unit = _getStringValue(row, 2);
          String sellingPriceStr = _getStringValue(row, 3);
          String costPriceStr = _getStringValue(row, 4);
          String salesDescription = _getStringValue(row, 5);
          String purchaseDescription = _getStringValue(row, 6);
          String status = _getStringValue(row, 7, 'Active');
          
          // Validate required fields
          List<String> rowErrors = [];
          
          if (itemName.isEmpty) {
            rowErrors.add('Item Name is required');
          }
          if (itemType.isEmpty) {
            rowErrors.add('Type is required');
          } else if (itemType != 'Goods' && itemType != 'Service') {
            rowErrors.add('Type must be "Goods" or "Service"');
          }
          if (sellingPriceStr.isEmpty) {
            rowErrors.add('Selling Price is required');
          }
          
          double? sellingPrice;
          double? costPrice;
          
          if (sellingPriceStr.isNotEmpty) {
            sellingPrice = double.tryParse(sellingPriceStr);
            if (sellingPrice == null) {
              rowErrors.add('Selling Price must be a valid number');
            }
          }
          
          if (costPriceStr.isNotEmpty) {
            costPrice = double.tryParse(costPriceStr);
            if (costPrice == null) {
              rowErrors.add('Cost Price must be a valid number');
            }
          }
          
          if (rowErrors.isNotEmpty) {
            errors.add('Row ${i + 1}: ${rowErrors.join(", ")}');
            print('❌ Row $i validation failed: ${rowErrors.join(", ")}');
            continue;
          }
          
          print('✅ Row $i validated successfully');
          
          itemsToImport.add({
            'name': itemName,
            'type': itemType,
            'unit': unit.isNotEmpty ? unit : null,
            'sellingPrice': sellingPrice,
            'costPrice': costPrice,
            'salesDescription': salesDescription.isNotEmpty ? salesDescription : null,
            'purchaseDescription': purchaseDescription.isNotEmpty ? purchaseDescription : null,
            'status': status,
            'isSellable': true,
            'isPurchasable': costPrice != null && costPrice > 0,
          });
        } catch (e) {
          errors.add('Row ${i + 1}: ${e.toString()}');
          print('❌ Error processing row $i: $e');
        }
      }
      
      print('📊 Import Summary:');
      print('  - Total rows processed: ${rows.length - 1}');
      print('  - Valid items: ${itemsToImport.length}');
      print('  - Errors: ${errors.length}');
      
      if (itemsToImport.isEmpty) {
        throw Exception('No valid item data found in the file. Please check the format and required fields.');
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
                  'Found ${itemsToImport.length} item(s) to import.',
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
      
      print('🚀 Starting bulk import...');
      
      // Import items one by one
      int successCount = 0;
      int failedCount = 0;
      List<String> importErrors = [];
      
      for (var itemData in itemsToImport) {
        try {
          await _itemService.createItem(itemData);
          successCount++;
        } catch (e) {
          failedCount++;
          importErrors.add('${itemData['name']}: ${e.toString()}');
        }
      }
      
      print('✅ Bulk import completed');
      print('  - Success: $successCount');
      print('  - Failed: $failedCount');
      
      setState(() {
        isUploading = false;
        importResults = [
          {
            'success': successCount,
            'failed': failedCount,
            'total': itemsToImport.length,
            'errors': importErrors,
          }
        ];
      });
      
      _showSuccess('Import completed successfully!');
      widget.onImportComplete();
      
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
          if (cell?.value == null) return '';
          
          if (cell!.value is excel_pkg.TextCellValue) {
            return (cell.value as excel_pkg.TextCellValue).value;
          }
          
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
  // PARSE CSV FILE
  // ============================================================================
  
  List<List<dynamic>> _parseCSVImproved(Uint8List bytes) {
    try {
      print('📊 Decoding CSV file...');
      
      String csvString = utf8.decode(bytes, allowMalformed: true);
      
      print('📊 CSV file size: ${csvString.length} characters');
      
      List<String> lines = csvString.split(RegExp(r'\r?\n'));
      
      print('📊 Found ${lines.length} lines in CSV');
      
      List<List<dynamic>> rows = [];
      
      for (int i = 0; i < lines.length; i++) {
        String line = lines[i].trim();
        
        if (line.isEmpty) {
          continue;
        }
        
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
  // PARSE CSV LINE
  // ============================================================================
  
  List<String> _parseCSVLine(String line) {
    List<String> fields = [];
    StringBuffer currentField = StringBuffer();
    bool inQuotes = false;
    
    for (int i = 0; i < line.length; i++) {
      String char = line[i];
      
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          currentField.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        fields.add(currentField.toString().trim());
        currentField.clear();
      } else {
        currentField.write(char);
      }
    }
    
    fields.add(currentField.toString().trim());
    
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
                    'Bulk Import Items',
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
                    '2. Fill in your item data\n'
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

class ItemData {
  final String id;
  final String name;
  final String? description;
  final String type;
  final String? unit;
  final double sellingPrice;
  final double? costPrice;
  final String status;
  final DateTime createdDate;
  
  ItemData({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    this.unit,
    required this.sellingPrice,
    this.costPrice,
    required this.status,
    required this.createdDate,
  });
  
  factory ItemData.fromJson(Map<String, dynamic> json) {
    return ItemData(
      id: json['_id'] ?? '',
      name: json['name'] ?? 'Unknown Item',
      description: json['description'],
      type: json['type'] ?? 'Goods',
      unit: json['unit'],
      sellingPrice: (json['sellingPrice'] ?? 0).toDouble(),
      costPrice: json['costPrice'] != null ? (json['costPrice']).toDouble() : null,
      status: json['status'] ?? 'Active',
      createdDate: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'description': description,
      'type': type,
      'unit': unit,
      'sellingPrice': sellingPrice,
      'costPrice': costPrice,
      'status': status,
      'createdAt': createdDate.toIso8601String(),
    };
  }
}