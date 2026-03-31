// ============================================================================
// SALES ORDERS LIST PAGE - Complete Implementation
// ============================================================================
// File: lib/screens/billing/sales_orders_list_page.dart
// Features: Filter, Search, Bulk Import, Excel Export, PDF Download, Convert to Invoice
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_pkg;
import 'dart:typed_data';
import 'dart:convert';
import 'package:universal_html/html.dart' as html;
import '../../../../core/utils/export_helper.dart';
import '../../../../core/services/sales_order_service.dart';
import '../app_top_bar.dart';
import 'new_sales_order.dart';

class SalesOrdersListPage extends StatefulWidget {
  const SalesOrdersListPage({Key? key}) : super(key: key);

  @override
  State<SalesOrdersListPage> createState() => _SalesOrdersListPageState();
}

class _SalesOrdersListPageState extends State<SalesOrdersListPage> {
  // Data
  List<SalesOrder> _salesOrders = [];
  SalesOrderStats? _stats;
  bool _isLoading = true;
  String? _errorMessage;
  
  // Filters
  String _selectedStatus = 'All';
  final List<String> _statusFilters = [
    'All',
    'DRAFT',
    'OPEN',
    'CONFIRMED',
    'PACKED',
    'SHIPPED',
    'INVOICED',
    'CLOSED',
    'CANCELLED',
  ];
  
  // Date Range Filter
  DateTime? _fromDate;
  DateTime? _toDate;
  
  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalSalesOrders = 0;
  final int _itemsPerPage = 20;
  
  // Selection
  final Set<String> _selectedSalesOrders = {};
  bool _selectAll = false;
  
  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSalesOrders();
    _loadStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSalesOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await SalesOrderService.getSalesOrders(
        status: _selectedStatus == 'All' ? null : _selectedStatus,
        page: _currentPage,
        limit: _itemsPerPage,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
        fromDate: _fromDate,
        toDate: _toDate,
      );

      setState(() {
        _salesOrders = response.salesOrders;
        _totalPages = response.pagination.pages;
        _totalSalesOrders = response.pagination.total;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStats() async {
    try {
      final stats = await SalesOrderService.getStats();
      setState(() {
        _stats = stats;
      });
    } catch (e) {
      print('Error loading stats: $e');
    }
  }

  Future<void> _refreshData() async {
    await Future.wait([
      _loadSalesOrders(),
      _loadStats(),
    ]);
    _showSuccessSnackbar('Data refreshed successfully');
  }

  void _filterByStatus(String status) {
    setState(() {
      _selectedStatus = status;
      _currentPage = 1;
    });
    _loadSalesOrders();
  }

  void _toggleSelection(String salesOrderId) {
    setState(() {
      if (_selectedSalesOrders.contains(salesOrderId)) {
        _selectedSalesOrders.remove(salesOrderId);
      } else {
        _selectedSalesOrders.add(salesOrderId);
      }
      _selectAll = _selectedSalesOrders.length == _salesOrders.length;
    });
  }

  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedSalesOrders.addAll(_salesOrders.map((so) => so.id));
      } else {
        _selectedSalesOrders.clear();
      }
    });
  }

  void _openNewSalesOrder() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NewSalesOrderScreen()),
    );

    if (result == true) {
      _refreshData();
    }
  }

  void _openEditSalesOrder(String salesOrderId) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => NewSalesOrderScreen(salesOrderId: salesOrderId)),
    );

    if (result == true) {
      _refreshData();
    }
  }

  Future<void> _viewSalesOrderDetails(SalesOrder salesOrder) async {
    setState(() => _isLoading = true);
    
    try {
      final fullSalesOrder = await SalesOrderService.getSalesOrder(salesOrder.id);
      setState(() => _isLoading = false);
      
      showDialog(
        context: context,
        builder: (context) => SalesOrderDetailsDialog(salesOrder: fullSalesOrder),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackbar('Failed to load sales order details: ${e.toString()}');
    }
  }

  Future<void> _deleteSalesOrder(SalesOrder salesOrder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sales Order'),
        content: Text('Are you sure you want to delete sales order ${salesOrder.salesOrderNumber}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await SalesOrderService.deleteSalesOrder(salesOrder.id);
        _showSuccessSnackbar('Sales order deleted successfully');
        _refreshData();
      } catch (e) {
        _showErrorSnackbar('Failed to delete sales order: $e');
      }
    }
  }

  Future<void> _sendSalesOrder(SalesOrder salesOrder) async {
    try {
      await SalesOrderService.sendSalesOrder(salesOrder.id);
      _showSuccessSnackbar('Sales order sent to ${salesOrder.customerEmail}');
      _refreshData();
    } catch (e) {
      _showErrorSnackbar('Failed to send sales order: $e');
    }
  }

  Future<void> _downloadSalesOrderPDF(SalesOrder salesOrder) async {
    try {
      _showSuccessSnackbar('Preparing PDF download...');
      
      final pdfUrl = await SalesOrderService.downloadPDF(salesOrder.id);
      
      if (kIsWeb) {
        html.AnchorElement(href: pdfUrl)
          ..setAttribute('download', '${salesOrder.salesOrderNumber}.pdf')
          ..setAttribute('target', '_blank')
          ..click();
        
        _showSuccessSnackbar('✅ PDF download started for ${salesOrder.salesOrderNumber}');
      } else {
        final uri = Uri.parse(pdfUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          _showSuccessSnackbar('✅ PDF opened for ${salesOrder.salesOrderNumber}');
        } else {
          throw 'Could not launch PDF viewer';
        }
      }
    } catch (e) {
      print('PDF Download Error: $e');
      _showErrorSnackbar('Failed to download PDF: $e');
    }
  }

  Future<void> _confirmSalesOrder(SalesOrder salesOrder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Sales Order'),
        content: Text('Mark sales order ${salesOrder.salesOrderNumber} as CONFIRMED?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27AE60)),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await SalesOrderService.confirmSalesOrder(salesOrder.id);
        _showSuccessSnackbar('Sales order confirmed successfully');
        _refreshData();
      } catch (e) {
        _showErrorSnackbar('Failed to confirm sales order: $e');
      }
    }
  }

  Future<void> _convertToInvoice(SalesOrder salesOrder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert to Invoice'),
        content: Text('Convert sales order ${salesOrder.salesOrderNumber} to an invoice?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27AE60)),
            child: const Text('Convert'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await SalesOrderService.convertToInvoice(salesOrder.id);
        _showSuccessSnackbar('Sales order converted to invoice successfully');
        _refreshData();
        
        // Navigate to Invoices List Page after successful conversion
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/admin/billing/invoices');
        }
      } catch (e) {
        _showErrorSnackbar('Failed to convert to invoice: $e');
      }
    }
  }

  Future<void> _exportToExcel() async {
    try {
      if (_salesOrders.isEmpty) {
        _showErrorSnackbar('No sales orders to export');
        return;
      }

      _showSuccessSnackbar('Preparing Excel export...');

      List<List<dynamic>> csvData = [
        [
          'Date',
          'SO Number',
          'Reference Number',
          'Customer Name',
          'Customer Email',
          'Status',
          'Expected Shipment',
          'Payment Terms',
          'Sub Total',
          'CGST',
          'SGST',
          'IGST',
          'Total Amount',
        ],
      ];

      for (var so in _salesOrders) {
        csvData.add([
          DateFormat('dd/MM/yyyy').format(so.salesOrderDate),
          so.salesOrderNumber,
          so.referenceNumber ?? '',
          so.customerName,
          so.customerEmail ?? '',
          so.status,
          so.expectedShipmentDate != null 
              ? DateFormat('dd/MM/yyyy').format(so.expectedShipmentDate!) 
              : '',
          so.paymentTerms,
          so.subTotal.toStringAsFixed(2),
          so.cgst.toStringAsFixed(2),
          so.sgst.toStringAsFixed(2),
          so.igst.toStringAsFixed(2),
          so.totalAmount.toStringAsFixed(2),
        ]);
      }

      await ExportHelper.exportToExcel(
        data: csvData,
        filename: 'sales_orders',
      );

      _showSuccessSnackbar('✅ Excel file downloaded with ${_salesOrders.length} sales orders!');
    } catch (e) {
      _showErrorSnackbar('Failed to export: $e');
    }
  }

  // ============================================================================
  // BULK IMPORT FUNCTIONALITY
  // ============================================================================
  
  void _handleBulkImport() {
    showDialog(
      context: context,
      builder: (context) => BulkImportSalesOrdersDialog(
        onImportComplete: () {
          _refreshData();
        },
      ),
    );
  }

  Future<void> _selectFromDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (picked != null) {
      setState(() {
        _fromDate = picked;
      });
      _loadSalesOrders();
    }
  }

  Future<void> _selectToDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _toDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (picked != null) {
      setState(() {
        _toDate = picked;
      });
      _loadSalesOrders();
    }
  }
  
  void _clearDateFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
    });
    _loadSalesOrders();
  }

  // 🆕 NEW: Show Sales Order Lifecycle Dialog
  void _showSalesOrderLifecycleDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.85,
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          color: Color(0xFF3498DB),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Sales Order Lifecycle Process',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          child: InteractiveViewer(
                            panEnabled: true,
                            minScale: 0.5,
                            maxScale: 4.0,
                            child: Center(
                              child: Image.asset(
                                'assets/sales_order.png',
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.broken_image_outlined,
                                        size: 80,
                                        color: Colors.grey[400],
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Image not found',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Please ensure "assets/sales_order.png" exists',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Tip: Pinch to zoom, drag to pan',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: 40,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.6),
                  padding: const EdgeInsets.all(14),
                ),
                tooltip: 'Close',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppTopBar(title: 'Sales Orders'),
    backgroundColor: Colors.grey[50],
    body: Column(
      children: [
        _buildTopBar(),
        if (_stats != null) _buildStatsCards(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
                  ? _buildErrorState()
                  : _salesOrders.isEmpty
                      ? _buildEmptyState()
                      : _buildSalesOrderTable(),
        ),
        if (!_isLoading && _salesOrders.isNotEmpty) _buildPagination(),
      ],
    ),
  );
}

Widget _buildTopBar() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    color: Colors.white,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: _selectedStatus,
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down),
              items: _statusFilters.map((status) {
                return DropdownMenuItem(
                  value: status,
                  child: Text(
                    status == 'All' ? 'All Sales Orders' : status.replaceAll('_', ' '),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) _filterByStatus(value);
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search sales orders...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (_searchQuery == value.toLowerCase()) {
                    _loadSalesOrders();
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: _selectFromDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _fromDate != null ? const Color(0xFF1e3a8a).withOpacity(0.08) : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _fromDate != null ? const Color(0xFF1e3a8a) : Colors.grey[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today, size: 16, color: _fromDate != null ? const Color(0xFF1e3a8a) : Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(
                    _fromDate != null ? 'From: ${DateFormat('dd/MM/yy').format(_fromDate!)}' : 'From Date',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _fromDate != null ? FontWeight.w600 : FontWeight.normal,
                      color: _fromDate != null ? const Color(0xFF1e3a8a) : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _selectToDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _toDate != null ? const Color(0xFF1e3a8a).withOpacity(0.08) : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _toDate != null ? const Color(0xFF1e3a8a) : Colors.grey[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today, size: 16, color: _toDate != null ? const Color(0xFF1e3a8a) : Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(
                    _toDate != null ? 'To: ${DateFormat('dd/MM/yy').format(_toDate!)}' : 'To Date',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _toDate != null ? FontWeight.w600 : FontWeight.normal,
                      color: _toDate != null ? const Color(0xFF1e3a8a) : Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_fromDate != null || _toDate != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.clear, color: Colors.red, size: 20),
              onPressed: _clearDateFilters,
              tooltip: 'Clear Date Filters',
              style: IconButton.styleFrom(
                backgroundColor: Colors.red[50],
                padding: const EdgeInsets.all(8),
              ),
            ),
          ],
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _isLoading ? null : _refreshData,
            tooltip: 'Refresh',
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey[200],
              padding: const EdgeInsets.all(8),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.account_tree, size: 20, color: Color(0xFF1e3a8a)),
            onPressed: _showSalesOrderLifecycleDialog,
            tooltip: 'View Sales Order Process',
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFF1e3a8a).withOpacity(0.1),
              padding: const EdgeInsets.all(8),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: _openNewSalesOrder,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Sales Order', style: TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1e3a8a),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _handleBulkImport,
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('Bulk Import', style: TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9B59B6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _exportToExcel,
            icon: const Icon(Icons.file_download, size: 16),
            label: const Text('Export Excel', style: TextStyle(fontSize: 13)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
        ],
      ),
    ),
  );
}
Widget _buildStatsCards() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    color: Colors.white,
    child: Row(
      children: [
        Expanded(child: _buildStatCard('Total Orders', _stats!.totalSalesOrders.toString(), Icons.shopping_cart, const Color(0xFF1e3a8a))),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('Confirmed', _stats!.confirmedSalesOrders.toString(), Icons.check_circle, Colors.green)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('Shipped', _stats!.shippedSalesOrders.toString(), Icons.local_shipping, Colors.purple)),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard('Total Value', '₹${_stats!.totalValue.toStringAsFixed(2)}', Icons.attach_money, Colors.orange)),
      ],
    ),
  );
}

Widget _buildStatCard(String label, String value, IconData icon, Color color) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(
      children: [
        Icon(icon, size: 32, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildSalesOrderTable() {
  return Container(
    margin: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2)),
      ],
    ),
    child: Column(
      children: [
        // Fixed Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: const BoxDecoration(
            color: Color(0xFF1e3a8a),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(8),
              topRight: Radius.circular(8),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Checkbox(
                  value: _selectAll,
                  onChanged: _toggleSelectAll,
                  fillColor: MaterialStateProperty.all(Colors.white),
                  checkColor: const Color(0xFF1e3a8a),
                ),
              ),
              const Expanded(flex: 2, child: Text('DATE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
              const Expanded(flex: 2, child: Text('SO#', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
              const Expanded(flex: 2, child: Text('REFERENCE#', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
              const Expanded(flex: 3, child: Text('CUSTOMER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
              const Expanded(flex: 2, child: Text('STATUS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
              const Expanded(flex: 2, child: Text('SHIPMENT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
              const Expanded(flex: 2, child: Text('AMOUNT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
              const SizedBox(width: 40),
            ],
          ),
        ),
        // Scrollable Rows
        Expanded(
          child: ListView.separated(
            itemCount: _salesOrders.length,
            separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey[200]),
            itemBuilder: (context, index) => _buildSalesOrderRow(_salesOrders[index]),
          ),
        ),
      ],
    ),
  );
}

Widget _buildSalesOrderRow(SalesOrder salesOrder) {
  final isSelected = _selectedSalesOrders.contains(salesOrder.id);

  return InkWell(
    onTap: () => _openEditSalesOrder(salesOrder.id),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      color: isSelected ? const Color(0xFF1e3a8a).withOpacity(0.06) : null,
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Checkbox(
              value: isSelected,
              onChanged: (value) => _toggleSelection(salesOrder.id),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              DateFormat('dd/MM/yyyy').format(salesOrder.salesOrderDate),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: () => _openEditSalesOrder(salesOrder.id),
              child: Text(
                salesOrder.salesOrderNumber,
                style: const TextStyle(color: Color(0xFF1e3a8a), fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              salesOrder.referenceNumber ?? '-',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              salesOrder.customerName,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: _buildStatusBadge(salesOrder.status),
          ),
          Expanded(
            flex: 2,
            child: Text(
              salesOrder.expectedShipmentDate != null
                  ? DateFormat('dd/MM/yyyy').format(salesOrder.expectedShipmentDate!)
                  : '-',
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '₹${salesOrder.totalAmount.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 40,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'view',
                  child: ListTile(
                    leading: Icon(Icons.visibility, size: 18, color: Color(0xFF1e3a8a)),
                    title: Text('View Details', style: TextStyle(fontSize: 13)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit, size: 18),
                    title: Text('Edit', style: TextStyle(fontSize: 13)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                if (salesOrder.status == 'DRAFT' || salesOrder.status == 'OPEN') ...[
                  const PopupMenuItem(
                    value: 'send',
                    child: ListTile(
                      leading: Icon(Icons.send, size: 18),
                      title: Text('Send', style: TextStyle(fontSize: 13)),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
                const PopupMenuItem(
                  value: 'download',
                  child: ListTile(
                    leading: Icon(Icons.download, size: 18),
                    title: Text('Download PDF', style: TextStyle(fontSize: 13)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                if (salesOrder.status == 'DRAFT' || salesOrder.status == 'OPEN') ...[
                  const PopupMenuItem(
                    value: 'confirm',
                    child: ListTile(
                      leading: Icon(Icons.check_circle, size: 18, color: Color(0xFF27AE60)),
                      title: Text('Confirm Order', style: TextStyle(color: Color(0xFF27AE60), fontSize: 13)),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
                if (salesOrder.status == 'CONFIRMED' || salesOrder.status == 'OPEN' ||
                    salesOrder.status == 'PACKED' || salesOrder.status == 'SHIPPED') ...[
                  const PopupMenuItem(
                    value: 'convert_invoice',
                    child: ListTile(
                      leading: Icon(Icons.receipt_long, size: 18, color: Color(0xFF27AE60)),
                      title: Text('Convert to Invoice', style: TextStyle(color: Color(0xFF27AE60), fontSize: 13)),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, size: 18, color: Colors.red),
                    title: Text('Delete', style: TextStyle(color: Colors.red, fontSize: 13)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
              onSelected: (value) async {
                switch (value) {
                  case 'view': _viewSalesOrderDetails(salesOrder); break;
                  case 'edit': _openEditSalesOrder(salesOrder.id); break;
                  case 'send': _sendSalesOrder(salesOrder); break;
                  case 'download': await _downloadSalesOrderPDF(salesOrder); break;
                  case 'confirm': _confirmSalesOrder(salesOrder); break;
                  case 'convert_invoice': _convertToInvoice(salesOrder); break;
                  case 'delete': _deleteSalesOrder(salesOrder); break;
                }
              },
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildHeaderCell(String text, {double width = 100}) {
  return SizedBox(
    width: width,
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
    ),
  );
}



  Widget _buildStatusBadge(String status) {
    Color backgroundColor;
    Color textColor;

    switch (status) {
      case 'CONFIRMED':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        break;
      case 'DRAFT':
        backgroundColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
        break;
      case 'OPEN':
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        break;
      case 'PACKED':
        backgroundColor = Colors.cyan[100]!;
        textColor = Colors.cyan[800]!;
        break;
      case 'SHIPPED':
        backgroundColor = Colors.purple[100]!;
        textColor = Colors.purple[800]!;
        break;
      case 'INVOICED':
        backgroundColor = Colors.teal[100]!;
        textColor = Colors.teal[800]!;
        break;
      case 'CLOSED':
        backgroundColor = Colors.blueGrey[100]!;
        textColor = Colors.blueGrey[800]!;
        break;
      case 'CANCELLED':
        backgroundColor = Colors.red[100]!;
        textColor = Colors.red[800]!;
        break;
      default:
        backgroundColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildPagination() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    color: Colors.white,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Showing ${(_currentPage - 1) * _itemsPerPage + 1} - ${(_currentPage * _itemsPerPage).clamp(0, _totalSalesOrders)} of $_totalSalesOrders',
          style: TextStyle(color: Colors.grey[700], fontSize: 13),
        ),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 20),
              onPressed: _currentPage > 1
                  ? () {
                      setState(() => _currentPage--);
                      _loadSalesOrders();
                    }
                  : null,
              padding: const EdgeInsets.all(4),
            ),
            ...List.generate(
              _totalPages.clamp(0, 5),
              (index) {
                final pageNum = index + 1;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: () {
                      setState(() => _currentPage = pageNum);
                      _loadSalesOrders();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _currentPage == pageNum ? const Color(0xFF1e3a8a) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        pageNum.toString(),
                        style: TextStyle(
                          fontSize: 13,
                          color: _currentPage == pageNum ? Colors.white : Colors.grey[700],
                          fontWeight: _currentPage == pageNum ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 20),
              onPressed: _currentPage < _totalPages
                  ? () {
                      setState(() => _currentPage++);
                      _loadSalesOrders();
                    }
                  : null,
              padding: const EdgeInsets.all(4),
            ),
          ],
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
          Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No sales orders found',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[700]),
          ),
          const SizedBox(height: 8),
          Text('Create your first sales order to get started', style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _openNewSalesOrder,
            icon: const Icon(Icons.add),
            label: const Text('Create Sales Order'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
          Icon(Icons.error_outline, size: 80, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            'Error Loading Sales Orders',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey[700]),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Unknown error',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// BULK IMPORT SALES ORDERS DIALOG
// ============================================================================

class BulkImportSalesOrdersDialog extends StatefulWidget {
  final VoidCallback onImportComplete;

  const BulkImportSalesOrdersDialog({
    Key? key,
    required this.onImportComplete,
  }) : super(key: key);

  @override
  State<BulkImportSalesOrdersDialog> createState() => _BulkImportSalesOrdersDialogState();
}

class _BulkImportSalesOrdersDialogState extends State<BulkImportSalesOrdersDialog> {
  bool isDownloading = false;
  bool isUploading = false;
  String? uploadedFileName;
  List<Map<String, dynamic>>? importResults;
  
  String _parsePhoneNumber(dynamic value) {
    if (value == null) return '';
    
    String strValue = value.toString().trim();
    if (strValue.isEmpty) return '';
    
    if (strValue.toUpperCase().contains('E')) {
      try {
        double numValue = double.parse(strValue);
        int intValue = numValue.round();
        return intValue.toString();
      } catch (e) {
        return strValue;
      }
    }
    
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
  
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    
    try {
      return double.parse(value.toString().trim());
    } catch (e) {
      return 0.0;
    }
  }
  
  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    
    String strValue = value.toString().trim();
    if (strValue.isEmpty) return null;
    
    List<String> formats = [
      'dd/MM/yyyy',
      'dd-MM-yyyy',
      'yyyy-MM-dd',
      'MM/dd/yyyy',
    ];
    
    for (String format in formats) {
      try {
        return DateFormat(format).parse(strValue);
      } catch (e) {
        continue;
      }
    }
    
    return null;
  }
  
  Future<void> _downloadTemplate() async {
    setState(() => isDownloading = true);
    
    try {
      List<List<dynamic>> templateData = [
        [
          'SO Date* (dd/MM/yyyy)',
          'SO Number',
          'Reference Number',
          'Customer Name*',
          'Customer Email*',
          'Customer Phone*',
          'Expected Shipment (dd/MM/yyyy)',
          'Payment Terms*',
          'Delivery Method',
          'Status*',
          'Salesperson',
          'Subject',
          'Sub Total*',
          'CGST',
          'SGST',
          'IGST',
          'TDS Amount',
          'TCS Amount',
          'Total Amount*',
          'Customer Notes',
          'Terms and Conditions',
        ],
        [
          '01/01/2024',
          'SO-2024-001',
          'PO-ABC-001',
          'ABC Corporation',
          'contact@abccorp.com',
          '9876543210',
          '15/01/2024',
          'Net 30',
          'Express Delivery',
          'DRAFT',
          'John Sales',
          'Order for Office Supplies',
          '100000.00',
          '9000.00',
          '9000.00',
          '0.00',
          '0.00',
          '0.00',
          '118000.00',
          'Please prepare for shipment by next week.',
          'Payment due within 30 days of invoice date.',
        ],
        [
          '02/01/2024',
          'SO-2024-002',
          'PO-XYZ-002',
          'XYZ Enterprises',
          'info@xyzent.com',
          '9123456789',
          '20/01/2024',
          'Net 15',
          'Standard Delivery',
          'CONFIRMED',
          'Jane Sales',
          'Bulk Order - Equipment',
          '250000.00',
          '22500.00',
          '22500.00',
          '0.00',
          '0.00',
          '0.00',
          '295000.00',
          'Rush order - priority handling required.',
          'Payment: 50% advance, 50% on delivery.',
        ],
        [
          'INSTRUCTIONS:',
          '1. Fields marked with * are required',
          '2. Date format: dd/MM/yyyy (e.g., 31/12/2024)',
          '3. Status: DRAFT, OPEN, CONFIRMED, PACKED, SHIPPED, INVOICED, CLOSED, CANCELLED',
          '4. Payment Terms: Due on Receipt, Net 15, Net 30, Net 45, Net 60',
          '5. Phone: 10 digits',
          '6. Email: valid format',
          '7. All amounts: numbers (decimals allowed)',
          '8. Total = SubTotal + CGST + SGST + IGST + TCS - TDS',
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
        ],
      ];
      
      await ExportHelper.exportToExcel(
        data: templateData,
        filename: 'sales_orders_import_template',
      );
      
      setState(() => isDownloading = false);
      
      _showSuccess('Template downloaded successfully!');
    } catch (e) {
      setState(() => isDownloading = false);
      _showError('Failed to download template: ${e.toString()}');
    }
  }
  
  Future<void> _uploadFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        allowMultiple: false,
        withData: true,
      );
      
      if (result == null || result.files.isEmpty) return;
      
      final file = result.files.first;
      
      setState(() {
        uploadedFileName = file.name;
        isUploading = true;
        importResults = null;
      });
      
      Uint8List? bytes = file.bytes;
      if (bytes == null) {
        throw Exception('Failed to read file');
      }
      
      List<List<dynamic>> rows;
      final extension = file.extension?.toLowerCase() ?? '';
      
      if (extension == 'csv') {
        rows = _parseCSV(bytes);
      } else {
        rows = _parseExcel(bytes);
      }
      
      if (rows.length < 2) {
        throw Exception('File must contain header row and data');
      }
      
      List<Map<String, dynamic>> salesOrdersToImport = [];
      List<String> errors = [];
      
      for (int i = 1; i < rows.length; i++) {
        try {
          var row = rows[i];
          
          if (row.isEmpty || 
              row[0] == null ||
              row[0].toString().trim().isEmpty ||
              row[0].toString().toUpperCase().contains('INSTRUCTION')) {
            continue;
          }
          
          DateTime? soDate = _parseDate(_getValue(row, 0));
          String soNumber = _getStringValue(row, 1);
          String referenceNumber = _getStringValue(row, 2);
          String customerName = _getStringValue(row, 3);
          String customerEmail = _getStringValue(row, 4);
          String customerPhone = _parsePhoneNumber(_getValue(row, 5));
          DateTime? expectedShipment = _parseDate(_getValue(row, 6));
          String paymentTerms = _getStringValue(row, 7, 'Net 30');
          String deliveryMethod = _getStringValue(row, 8);
          String status = _getStringValue(row, 9, 'DRAFT');
          String salesperson = _getStringValue(row, 10);
          String subject = _getStringValue(row, 11);
          double subTotal = _parseDouble(_getValue(row, 12));
          double cgst = _parseDouble(_getValue(row, 13));
          double sgst = _parseDouble(_getValue(row, 14));
          double igst = _parseDouble(_getValue(row, 15));
          double tdsAmount = _parseDouble(_getValue(row, 16));
          double tcsAmount = _parseDouble(_getValue(row, 17));
          double totalAmount = _parseDouble(_getValue(row, 18));
          String customerNotes = _getStringValue(row, 19);
          String termsConditions = _getStringValue(row, 20);
          
          List<String> rowErrors = [];
          
          if (soDate == null) rowErrors.add('SO Date required (dd/MM/yyyy)');
          if (customerName.isEmpty) rowErrors.add('Customer Name required');
          if (customerEmail.isEmpty) rowErrors.add('Customer Email required');
          else if (!_isValidEmail(customerEmail)) rowErrors.add('Invalid email');
          if (customerPhone.isEmpty) rowErrors.add('Customer Phone required');
          else if (customerPhone.length != 10) rowErrors.add('Phone must be 10 digits');
          if (subTotal <= 0) rowErrors.add('Sub Total > 0');
          if (totalAmount <= 0) rowErrors.add('Total Amount > 0');
          
          final validStatuses = ['DRAFT', 'OPEN', 'CONFIRMED', 'PACKED', 'SHIPPED', 'INVOICED', 'CLOSED', 'CANCELLED'];
          if (!validStatuses.contains(status.toUpperCase())) {
            rowErrors.add('Invalid status');
          }
          
          if (rowErrors.isNotEmpty) {
            errors.add('Row ${i + 1}: ${rowErrors.join(", ")}');
            continue;
          }
          
          salesOrdersToImport.add({
            'salesOrderDate': soDate!.toIso8601String(),
            'salesOrderNumber': soNumber,
            'referenceNumber': referenceNumber,
            'customerName': customerName,
            'customerEmail': customerEmail,
            'customerPhone': customerPhone,
            'expectedShipmentDate': expectedShipment?.toIso8601String(),
            'paymentTerms': paymentTerms,
            'deliveryMethod': deliveryMethod,
            'status': status.toUpperCase(),
            'salesperson': salesperson,
            'subject': subject,
            'subTotal': subTotal,
            'cgst': cgst,
            'sgst': sgst,
            'igst': igst,
            'tdsAmount': tdsAmount,
            'tcsAmount': tcsAmount,
            'totalAmount': totalAmount,
            'customerNotes': customerNotes,
            'termsConditions': termsConditions,
          });
        } catch (e) {
          errors.add('Row ${i + 1}: ${e.toString()}');
        }
      }
      
      if (salesOrdersToImport.isEmpty) {
        throw Exception('No valid sales order data found');
      }
      
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
                  'Found ${salesOrdersToImport.length} sales order(s) to import.',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '${errors.length} row(s) skipped:',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
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
                const Text('Proceed with import?'),
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3498DB)),
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
      
      final importResult = await SalesOrderService.bulkImportSalesOrders(salesOrdersToImport);
      
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
      print('Upload Error: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        isUploading = false;
        uploadedFileName = null;
      });
      _showError('Failed to import: ${e.toString()}');
    }
  }
  
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
  
  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    try {
      var excel = excel_pkg.Excel.decodeBytes(bytes);
      var sheet = excel.tables.keys.first;
      var rows = excel.tables[sheet]?.rows;
      
      if (rows == null || rows.isEmpty) {
        throw Exception('Excel file is empty');
      }
      
      List<List<dynamic>> result = rows.map((row) {
        return row.map((cell) {
          if (cell?.value == null) return '';
          if (cell!.value is excel_pkg.TextCellValue) {
            return (cell.value as excel_pkg.TextCellValue).value;
          }
          return cell.value;
        }).toList();
      }).toList();
      
      return result;
    } catch (e) {
      throw Exception('Failed to parse Excel: ${e.toString()}');
    }
  }
  
  List<List<dynamic>> _parseCSV(Uint8List bytes) {
    try {
      String csvString = utf8.decode(bytes, allowMalformed: true);
      List<String> lines = csvString.split(RegExp(r'\r?\n'));
      
      List<List<dynamic>> rows = [];
      
      for (String line in lines) {
        String trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;
        
        List<String> fields = _parseCSVLine(trimmedLine);
        rows.add(fields);
      }
      
      return rows;
    } catch (e) {
      throw Exception('Failed to parse CSV: ${e.toString()}');
    }
  }
  
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
      SnackBar(content: Text(message), backgroundColor: Colors.red, duration: const Duration(seconds: 4)),
    );
  }
  
  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green, duration: const Duration(seconds: 2)),
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
            Row(
              children: [
                const Icon(Icons.upload_file, color: Color(0xFF9B59B6), size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Bulk Import Sales Orders',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 32),
            
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
                      Text('How to Import Sales Orders', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue[700])),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '1. Download the sample template\n'
                    '2. Fill in your sales order data\n'
                    '3. Dates in dd/MM/yyyy format\n'
                    '4. Upload completed file (.xlsx, .xls, .csv)\n'
                    '5. Review and confirm import',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isDownloading || isUploading ? null : _downloadTemplate,
                icon: isDownloading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
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
            
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isDownloading || isUploading ? null : _uploadFile,
                icon: isUploading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF9B59B6))))
                    : const Icon(Icons.upload_file),
                label: Text(isUploading ? 'Processing...' : 'Upload Excel or CSV File'),
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
                        style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            if (importResults != null) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text('Import Results', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
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
                      const Text('Errors:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
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
                  onPressed: () => Navigator.pop(context),
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
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// Sales Order Details Dialog
class SalesOrderDetailsDialog extends StatelessWidget {
  final SalesOrder salesOrder;

  const SalesOrderDetailsDialog({Key? key, required this.salesOrder}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_cart, color: Color(0xFF3498DB), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(salesOrder.salesOrderNumber, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
                      Text('Sales Order Details', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                    ],
                  ),
                ),
                _buildStatusBadge(salesOrder.status),
                const SizedBox(width: 12),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(height: 32),
            
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection('Customer Information', [
                      _buildInfoRow('Customer Name', salesOrder.customerName),
                      _buildInfoRow('Email', salesOrder.customerEmail),
                      _buildInfoRow('Phone', salesOrder.customerPhone),
                    ]),
                    const SizedBox(height: 24),
                    
                    _buildSection('Sales Order Information', [
                      _buildInfoRow('SO Number', salesOrder.salesOrderNumber),
                      _buildInfoRow('Reference Number', salesOrder.referenceNumber),
                      _buildInfoRow('SO Date', DateFormat('dd MMM yyyy').format(salesOrder.salesOrderDate)),
                      _buildInfoRow('Expected Shipment', salesOrder.expectedShipmentDate != null ? DateFormat('dd MMM yyyy').format(salesOrder.expectedShipmentDate!) : 'Not Set'),
                      _buildInfoRow('Payment Terms', salesOrder.paymentTerms),
                      _buildInfoRow('Delivery Method', salesOrder.deliveryMethod),
                      _buildInfoRow('Salesperson', salesOrder.salesperson),
                      _buildInfoRow('Subject', salesOrder.subject),
                    ]),
                    const SizedBox(height: 24),
                    
                    if (salesOrder.items.isNotEmpty) ...[
                      _buildLineItemsSection(salesOrder.items),
                      const SizedBox(height: 24),
                    ],
                    
                    _buildSection('Amount Details', [
                      _buildInfoRow('Subtotal', '₹${salesOrder.subTotal.toStringAsFixed(2)}'),
                      if (salesOrder.tdsAmount > 0) _buildInfoRow('TDS', '₹${salesOrder.tdsAmount.toStringAsFixed(2)}'),
                      if (salesOrder.tcsAmount > 0) _buildInfoRow('TCS', '₹${salesOrder.tcsAmount.toStringAsFixed(2)}'),
                      _buildInfoRow('CGST', '₹${salesOrder.cgst.toStringAsFixed(2)}'),
                      _buildInfoRow('SGST', '₹${salesOrder.sgst.toStringAsFixed(2)}'),
                      _buildInfoRow('IGST', '₹${salesOrder.igst.toStringAsFixed(2)}'),
                      _buildInfoRow('Total Amount', '₹${salesOrder.totalAmount.toStringAsFixed(2)}', isBold: true),
                    ]),
                    
                    if (salesOrder.customerNotes != null && salesOrder.customerNotes!.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildSection('Customer Notes', [
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(salesOrder.customerNotes!, style: TextStyle(fontSize: 14, color: Colors.grey[800])),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
            
            const Divider(height: 32),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatusBadge(String status) {
    Color backgroundColor;
    Color textColor;

    switch (status) {
      case 'CONFIRMED':
        backgroundColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        break;
      case 'OPEN':
        backgroundColor = Colors.blue[100]!;
        textColor = Colors.blue[800]!;
        break;
      case 'PACKED':
        backgroundColor = Colors.cyan[100]!;
        textColor = Colors.cyan[800]!;
        break;
      case 'SHIPPED':
        backgroundColor = Colors.purple[100]!;
        textColor = Colors.purple[800]!;
        break;
      case 'INVOICED':
        backgroundColor = Colors.teal[100]!;
        textColor = Colors.teal[800]!;
        break;
      default:
        backgroundColor = Colors.grey[200]!;
        textColor = Colors.grey[800]!;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: backgroundColor, borderRadius: BorderRadius.circular(12)),
      child: Text(status, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600)),
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
          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
          child: Column(children: children),
        ),
      ],
    );
  }
  
  Widget _buildInfoRow(String label, dynamic value, {bool isBold = false}) {
    if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: const Color(0xFF2C3E50), fontSize: 14)),
          ),
          Expanded(
            child: Text(value.toString(), style: TextStyle(color: Colors.grey[800], fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildLineItemsSection(List<SalesOrderItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Line Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2C3E50))),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey[200]!)),
          child: Table(
            border: TableBorder.all(color: Colors.grey[300]!, width: 1),
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(color: Colors.grey[200]),
                children: const [
                  Padding(padding: EdgeInsets.all(12), child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(12), child: Text('Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(12), child: Text('Rate', style: TextStyle(fontWeight: FontWeight.bold))),
                  Padding(padding: EdgeInsets.all(12), child: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
              ...items.map<TableRow>((item) {
                return TableRow(
                  children: [
                    Padding(padding: const EdgeInsets.all(12), child: Text(item.itemDetails)),
                    Padding(padding: const EdgeInsets.all(12), child: Text(item.quantity.toString())),
                    Padding(padding: const EdgeInsets.all(12), child: Text('₹${item.rate.toStringAsFixed(2)}')),
                    Padding(padding: const EdgeInsets.all(12), child: Text('₹${item.amount.toStringAsFixed(2)}')),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }
}